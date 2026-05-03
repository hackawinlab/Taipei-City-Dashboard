// Package controllers stores all the controllers for the Gin router.
package controllers

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"sync"
	"time"

	"TaipeiCityDashboardBE/app/models"
	"TaipeiCityDashboardBE/app/youbike_aggregate"

	"github.com/gin-gonic/gin"
)

// youbike helpers

func youbikeValidateCity(city string) bool {
	return city == "Taipei" || city == "NewTaipei" || city == "all"
}

func youbikeDefaultHour() int {
	loc, err := time.LoadLocation("Asia/Taipei")
	if err != nil {
		return time.Now().UTC().Hour()
	}
	return time.Now().In(loc).Hour()
}

// GetYouBikeMap handles GET /api/v1/commute/youbike/map
// Query params:
//
//	city    (Taipei|NewTaipei|all, default all)
//	hour    (0-23, default current hour)
//	quarter (0-3, optional — restricts to one 15-minute slot of the hour:
//	         0=[:00,:15), 1=[:15,:30), 2=[:30,:45), 3=[:45,:60))
func GetYouBikeMap(c *gin.Context) {
	city := c.DefaultQuery("city", "all")
	if !youbikeValidateCity(city) {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid city: must be Taipei, NewTaipei, or all"})
		return
	}

	hourStr := c.Query("hour")
	var hour int
	if hourStr == "" {
		hour = youbikeDefaultHour()
	} else {
		var err error
		hour, err = strconv.Atoi(hourStr)
		if err != nil || hour < 0 || hour > 23 {
			c.JSON(http.StatusBadRequest, gin.H{"message": "invalid hour: must be an integer 0–23"})
			return
		}
	}

	quarter := -1
	if quarterStr := c.Query("quarter"); quarterStr != "" {
		q, err := strconv.Atoi(quarterStr)
		if err != nil || q < 0 || q > 3 {
			c.JSON(http.StatusBadRequest, gin.H{"message": "invalid quarter: must be an integer 0–3"})
			return
		}
		quarter = q
	}

	if models.DBHackathon == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"message": "hackathon database not available"})
		return
	}

	// Pick the latest snapshot per station within the requested slot. Using
	// the same DISTINCT ON LATEST pattern as GetYouBikeStationHourly so the
	// icon color and the popup chart bar always agree at any given slot.
	query := `
SELECT station_uid, station_name, lat, lon, city,
       ROUND(available_bikes::numeric / NULLIF(total_docks,0) * 100, 1) AS availability_pct,
       available_bikes                                                  AS avg_available,
       total_docks
FROM (
  SELECT DISTINCT ON (station_uid)
         station_uid, station_name, lat, lon, city,
         available_bikes, total_docks
  FROM youbike_snapshots
  WHERE (city = $1 OR $1 = 'all')
    AND EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei') = $2`
	args := []interface{}{city, hour}
	if quarter >= 0 {
		query += `
    AND (EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int / 15) = $3`
		args = append(args, quarter)
	}
	query += `
  ORDER BY station_uid, snapshot_at DESC
) s
ORDER BY availability_pct ASC`

	sqlDB, err := models.DBHackathon.DB()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("db error: %v", err)})
		return
	}

	rows, err := sqlDB.Query(query, args...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("query error: %v", err)})
		return
	}
	defer rows.Close()

	type youbikeMapFeature struct {
		Type     string `json:"type"`
		Geometry struct {
			Type        string    `json:"type"`
			Coordinates []float64 `json:"coordinates"`
		} `json:"geometry"`
		Properties map[string]interface{} `json:"properties"`
	}

	features := []youbikeMapFeature{}

	for rows.Next() {
		var (
			stationUID      string
			stationName     string
			lat, lon        float64
			stationCity     string
			availabilityPct sql.NullFloat64
			avgAvailable    sql.NullInt64
			totalDocks      sql.NullInt64
		)
		if err := rows.Scan(&stationUID, &stationName, &lat, &lon, &stationCity, &availabilityPct, &avgAvailable, &totalDocks); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("scan error: %v", err)})
			return
		}

		feat := youbikeMapFeature{
			Type: "Feature",
		}
		feat.Geometry.Type = "Point"
		feat.Geometry.Coordinates = []float64{lon, lat}
		feat.Properties = map[string]interface{}{
			"station_uid":      stationUID,
			"station_name":     stationName,
			"city":             stationCity,
			"availability_pct": availabilityPct.Float64,
			"avg_available":    avgAvailable.Int64,
			"total_docks":      totalDocks.Int64,
		}
		features = append(features, feat)
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("rows error: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"type":     "FeatureCollection",
		"features": features,
	})
}

// GetYouBikeStationHourly handles GET /api/v1/commute/youbike/station/:uid/hourly
// Returns 96-element arrays (one per 15-min slot, Asia/Taipei) of:
//   - avg available_bikes (total bikes available, includes EVs)
//   - avg electric_bikes  (electric subset of available)
//   - max total_docks     (capacity)
//
// Slot index = hour*4 + (minute/15), so 0 = 00:00, 95 = 23:45.
func GetYouBikeStationHourly(c *gin.Context) {
	uid := c.Param("uid")
	if uid == "" {
		c.JSON(http.StatusBadRequest, gin.H{"message": "missing station uid"})
		return
	}

	if models.DBHackathon == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"message": "hackathon database not available"})
		return
	}

	const slotCount = 96

	// One reading per 15-min slot: take the latest snapshot in each slot via
	// DISTINCT ON. Avoids fractional values that AVG would produce when two
	// CSV captures land in the same slot.
	query := `
SELECT DISTINCT ON (slot)
       slot,
       available_bikes::float AS avg_available,
       electric_bikes::float  AS avg_electric,
       total_docks            AS total_docks,
       station_name,
       city
FROM (
  SELECT (EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int * 4
          + EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int / 15) AS slot,
         snapshot_at, available_bikes, electric_bikes, total_docks, station_name, city
  FROM youbike_snapshots
  WHERE station_uid = $1
) s
ORDER BY slot, snapshot_at DESC`

	sqlDB, err := models.DBHackathon.DB()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("db error: %v", err)})
		return
	}

	rows, err := sqlDB.Query(query, uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("query error: %v", err)})
		return
	}
	defer rows.Close()

	available := make([]float64, slotCount)
	electric := make([]float64, slotCount)
	total := make([]int64, slotCount)
	var stationName, stationCity string

	for rows.Next() {
		var (
			slot       int
			avgAvail   sql.NullFloat64
			avgElec    sql.NullFloat64
			totalDocks sql.NullInt64
			name       sql.NullString
			city       sql.NullString
		)
		if err := rows.Scan(&slot, &avgAvail, &avgElec, &totalDocks, &name, &city); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("scan error: %v", err)})
			return
		}
		if slot >= 0 && slot < slotCount {
			available[slot] = avgAvail.Float64
			electric[slot] = avgElec.Float64
			total[slot] = totalDocks.Int64
		}
		if name.Valid && stationName == "" {
			stationName = name.String
		}
		if city.Valid && stationCity == "" {
			stationCity = city.String
		}
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("rows error: %v", err)})
		return
	}

	if stationName == "" {
		c.JSON(http.StatusNotFound, gin.H{"message": "station not found"})
		return
	}

	slots := make([]string, slotCount)
	for s := 0; s < slotCount; s++ {
		h := s / 4
		m := (s % 4) * 15
		slots[s] = fmt.Sprintf("%02d:%02d", h, m)
	}

	c.JSON(http.StatusOK, gin.H{
		"data": gin.H{
			"station_uid":     uid,
			"station_name":    stationName,
			"city":            stationCity,
			"slots":           slots,
			"available_bikes": available,
			"electric_bikes":  electric,
			"total_docks":     total,
		},
	})
}

// GetYouBikeShortage handles GET /api/v1/commute/youbike/shortage
// Query params: city (Taipei|NewTaipei|all, default all)
func GetYouBikeShortage(c *gin.Context) {
	city := c.DefaultQuery("city", "all")
	if !youbikeValidateCity(city) {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid city: must be Taipei, NewTaipei, or all"})
		return
	}

	if models.DBHackathon == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"message": "hackathon database not available"})
		return
	}

	query := `
SELECT EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int AS hour,
       city,
       COUNT(DISTINCT station_uid) FILTER (WHERE available_bikes = 0) AS empty_stations,
       COUNT(DISTINCT station_uid)                                      AS total_stations
FROM youbike_snapshots
WHERE (city = $1 OR $1 = 'all')
GROUP BY 1, 2
ORDER BY 1, 2`

	sqlDB, err := models.DBHackathon.DB()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("db error: %v", err)})
		return
	}

	rows, err := sqlDB.Query(query, city)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("query error: %v", err)})
		return
	}
	defer rows.Close()

	// Collect data grouped by city into a map[city][hour] → shortage_pct
	type hourPoint struct {
		X string  `json:"x"`
		Y float64 `json:"y"`
	}
	// cityHours holds the computed shortage_pct for each (city, hour) pair seen in DB results.
	cityHours := make(map[string]map[int]float64)
	cityOrder := []string{}

	for rows.Next() {
		var (
			hour          int
			rowCity       string
			emptyStations int64
			totalStations int64
		)
		if err := rows.Scan(&hour, &rowCity, &emptyStations, &totalStations); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("scan error: %v", err)})
			return
		}
		var pct float64
		if totalStations > 0 {
			pct = float64(emptyStations) / float64(totalStations) * 100
			// round to 1 decimal
			pct = math.Round(pct*10) / 10
		}
		if _, exists := cityHours[rowCity]; !exists {
			cityOrder = append(cityOrder, rowCity)
			cityHours[rowCity] = make(map[int]float64)
		}
		cityHours[rowCity][hour] = pct
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("rows error: %v", err)})
		return
	}

	type seriesEntry struct {
		Name string      `json:"name"`
		Data []hourPoint `json:"data"`
	}
	series := []seriesEntry{}
	for _, name := range cityOrder {
		data := make([]hourPoint, 24)
		for h := 0; h < 24; h++ {
			pct := 0.0
			if v, ok := cityHours[name][h]; ok {
				pct = v
			}
			data[h] = hourPoint{X: strconv.Itoa(h), Y: pct}
		}
		series = append(series, seriesEntry{Name: name, Data: data})
	}

	categories := make([]string, 24)
	for i := 0; i < 24; i++ {
		categories[i] = strconv.Itoa(i)
	}

	c.JSON(http.StatusOK, gin.H{
		"series":     series,
		"categories": categories,
	})
}

// GetYouBikeBlacklist handles GET /api/v1/commute/youbike/blacklist
// Query params: city (Taipei|NewTaipei|all, default all), limit (int, default 20)
func GetYouBikeBlacklist(c *gin.Context) {
	city := c.DefaultQuery("city", "all")
	if !youbikeValidateCity(city) {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid city: must be Taipei, NewTaipei, or all"})
		return
	}

	limitStr := c.DefaultQuery("limit", "20")
	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid limit: must be a positive integer"})
		return
	}

	if models.DBHackathon == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"message": "hackathon database not available"})
		return
	}

	query := `
SELECT station_name, city,
  ROUND(COUNT(*) FILTER (WHERE available_bikes=0)*100.0 / NULLIF(COUNT(*),0), 1) AS empty_pct
FROM youbike_snapshots
WHERE (city = $1 OR $1 = 'all')
GROUP BY station_name, city
HAVING COUNT(*) > 2
ORDER BY empty_pct DESC
LIMIT $2`

	sqlDB, err2 := models.DBHackathon.DB()
	if err2 != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("db error: %v", err2)})
		return
	}

	rows, err2 := sqlDB.Query(query, city, limit)
	if err2 != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("query error: %v", err2)})
		return
	}
	defer rows.Close()

	type blacklistEntry struct {
		X    string  `json:"x"`
		Y    float64 `json:"y"`
		City string  `json:"city"`
	}
	data := []blacklistEntry{}

	for rows.Next() {
		var (
			stationName string
			rowCity     string
			emptyPct    sql.NullFloat64
		)
		if err := rows.Scan(&stationName, &rowCity, &emptyPct); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("scan error: %v", err)})
			return
		}
		data = append(data, blacklistEntry{
			X:    stationName,
			Y:    emptyPct.Float64,
			City: rowCity,
		})
	}
	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("rows error: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{"data": data})
}

// Bus congestion timeline — DB-backed timeseries from
// public.bus_congestion_history_segments (dashboard DB). Powers the
// "公車壅塞時序" virtual dashboard.

func busCongestionValidateCity(city string) bool {
	return city == "taipei" || city == "metrotaipei"
}

// busCongestionLabelOrder fixes the chart series order from least to most
// severe so colours stay stable across renders. "無資料" is intentionally
// omitted — it dominates the matview (~75% of rows) and the model layer
// already filters it out.
var busCongestionLabelOrder = []string{"暢通", "輕微", "中度", "嚴重", "極嚴重"}

// GetBusCongestionRoutes handles GET /api/v1/commute/bus-congestion/routes
// Query params: city (taipei|metrotaipei, default taipei).
//
// Returns the full list of route_name values from bus_congestion_segments
// for the requested scope (taipei → 台北市; metrotaipei → 台北市+新北市).
// Routes without edge history will still show up here so users can pick
// them; the timeline endpoint communicates the data gap via data_note.
func GetBusCongestionRoutes(c *gin.Context) {
	city := c.DefaultQuery("city", "taipei")
	if !busCongestionValidateCity(city) {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid city: must be taipei or metrotaipei"})
		return
	}

	routes, err := models.ListBusCongestionRoutes(city)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("query error: %v", err)})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"data": routes,
		"city": city,
	})
}

// GetBusCongestionTimeline handles GET /api/v1/commute/bus-congestion/timeline
// Query params:
//
//	city       (taipei|metrotaipei, default taipei)
//	route_name (optional; empty = aggregate across whole city)
//
// Returns ApexCharts-compatible categories (snapshot times in HH:MM Taipei)
// and stacked series (one per congestion label).
func GetBusCongestionTimeline(c *gin.Context) {
	city := c.DefaultQuery("city", "taipei")
	if !busCongestionValidateCity(city) {
		c.JSON(http.StatusBadRequest, gin.H{"message": "invalid city: must be taipei or metrotaipei"})
		return
	}
	routeName := c.Query("route_name")

	points, err := models.GetBusCongestionTimeline(city, routeName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"message": fmt.Sprintf("query error: %v", err)})
		return
	}

	loc, err := time.LoadLocation("Asia/Taipei")
	if err != nil {
		loc = time.UTC
	}

	// Index unique snapshots in chronological order. Using a slice + map
	// keeps ordering deterministic and lets us back-fill 0 for (snapshot,label)
	// pairs that simply have no rows in that bucket.
	type snapshotKey struct{ t time.Time }
	snapshotIdx := map[time.Time]int{}
	categories := []string{}
	for _, p := range points {
		if _, ok := snapshotIdx[p.SnapshotTime]; ok {
			continue
		}
		snapshotIdx[p.SnapshotTime] = len(categories)
		categories = append(categories, p.SnapshotTime.In(loc).Format("15:04"))
	}

	// Build series per known label, zero-filled.
	type seriesEntry struct {
		Name string  `json:"name"`
		Data []int64 `json:"data"`
	}
	seriesByLabel := map[string]*seriesEntry{}
	for _, name := range busCongestionLabelOrder {
		seriesByLabel[name] = &seriesEntry{Name: name, Data: make([]int64, len(categories))}
	}
	for _, p := range points {
		entry, ok := seriesByLabel[p.Label]
		if !ok {
			// Unknown label — skip. (Would be rare; matview labels are stable.)
			continue
		}
		idx := snapshotIdx[p.SnapshotTime]
		entry.Data[idx] = p.SegmentCount
	}

	series := make([]seriesEntry, 0, len(busCongestionLabelOrder))
	for _, name := range busCongestionLabelOrder {
		series = append(series, *seriesByLabel[name])
	}

	// Surface the data gap when the matview has no rows for the requested
	// route. The dropdown source (bus_congestion_segments) is broader than
	// the matview (history_segments) by design, so users can pick a 新北
	// route like "275" and end up here with zero rows. Tell them why.
	dataNote := ""
	if len(categories) == 0 {
		if routeName != "" {
			dataNote = "此路線目前無邊段歷史資料(matview 僅含台北市 edge)"
		} else {
			dataNote = "此 city 目前無邊段歷史資料"
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"city":           city,
		"route_name":     routeName,
		"snapshot_count": len(categories),
		"categories":     categories,
		"series":         series,
		"data_note":      dataNote,
	})
}

// Shortage aggregate cache — built from the same youbike_snapshots table that
// powers the timemap, then cached in-process for shortageCacheTTL because the
// aggregation reads ~130k rows and is identical for every caller. Shared by
// GetYouBikePersistenceChart and GetYouBikeImbalanceChart.

const shortageCacheTTL = 60 * time.Second

var (
	shortageCacheMu      sync.Mutex
	shortageCachedAt     time.Time
	shortageCachedResult youbike_aggregate.Payload
)

// getYouBikeAggregatePayload returns the cached aggregate payload, computing
// it on first call (or cache expiry).
//
// Returns:
//   - payload: the aggregate result (zero-value on error)
//   - status:  HTTP status code to return on error (0 means OK)
//   - errMsg:  user-facing error message (empty when status==0)
func getYouBikeAggregatePayload(ctx context.Context) (youbike_aggregate.Payload, int, string) {
	if models.DBHackathon == nil {
		return youbike_aggregate.Payload{}, http.StatusServiceUnavailable, "hackathon database not available"
	}

	shortageCacheMu.Lock()
	if !shortageCachedAt.IsZero() && time.Since(shortageCachedAt) < shortageCacheTTL {
		cached := shortageCachedResult
		shortageCacheMu.Unlock()
		return cached, 0, ""
	}
	shortageCacheMu.Unlock()

	sqlDB, err := models.DBHackathon.DB()
	if err != nil {
		return youbike_aggregate.Payload{}, http.StatusInternalServerError, fmt.Sprintf("db error: %v", err)
	}

	loadCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	snapshots, err := youbike_aggregate.LoadFromDB(loadCtx, sqlDB)
	if err != nil {
		return youbike_aggregate.Payload{}, http.StatusInternalServerError, fmt.Sprintf("load error: %v", err)
	}
	if len(snapshots) == 0 {
		return youbike_aggregate.Payload{}, http.StatusServiceUnavailable, "youbike_snapshots is empty — run scripts/load-ubike-data.sh first"
	}

	payload := youbike_aggregate.BuildPayload(snapshots)

	shortageCacheMu.Lock()
	shortageCachedAt = time.Now()
	shortageCachedResult = payload
	shortageCacheMu.Unlock()

	return payload, 0, ""
}

// chartTwoDimSeries / chartTwoDimResponse follow the {status, data:[{name,data}], categories}
// envelope the FE expects from /component/:id/chart for three_d/percent query types
// (the SQL two_d shape has no `name` and no top-level `categories`). The seed marks
// these rows as `query_type='two_d'` for SQL-path consistency, but the SQL is never
// executed: api_endpoint short-circuits the GORM path entirely. The "TwoDim" naming
// just reflects the {x,y} data points, not the query_type discriminator.
type chartTwoDimSeries struct {
	Name string             `json:"name"`
	Data []chartTwoDimPoint `json:"data"`
}

type chartTwoDimPoint struct {
	X string  `json:"x"`
	Y float64 `json:"y"`
}

type chartTwoDimResponse struct {
	Status     string              `json:"status"`
	Data       []chartTwoDimSeries `json:"data"`
	Categories []string            `json:"categories"`
}

// resolveYouBikeAggregateCity maps the dashboard's "?city=" query param onto
// the dataset key used inside aggregate.Payload (Taipei | NewTaipei | All).
//   - "taipei"        → "Taipei"
//   - "metrotaipei"   → "All" (the dual-city slice)
//   - empty / other   → "Taipei"
func resolveYouBikeAggregateCity(c *gin.Context) string {
	switch c.DefaultQuery("city", "taipei") {
	case "metrotaipei":
		return "All"
	default:
		return "Taipei"
	}
}

// GetYouBikePersistenceChart handles GET /api/v1/commute/youbike/persistence.
//
// Returns the chronic-shortage station ranking for the requested city slice
// in the standard chart-data response shape, so it can be consumed by frontend
// components whose component_charts.api_endpoint points here.
//
// Top 20 stations sorted by empty-hour ratio (desc), as built by
// aggregate.buildBarPersistence; y is the integer "empty hours" count.
func GetYouBikePersistenceChart(c *gin.Context) {
	payload, status, errMsg := getYouBikeAggregatePayload(c.Request.Context())
	if status != 0 {
		c.JSON(status, gin.H{"message": errMsg})
		return
	}

	cityKey := resolveYouBikeAggregateCity(c)
	rows := payload.BarPersistence[cityKey]
	const persistenceTopN = 20
	if len(rows) > persistenceTopN {
		rows = rows[:persistenceTopN]
	}

	points := make([]chartTwoDimPoint, 0, len(rows))
	categories := make([]string, 0, len(rows))
	for _, r := range rows {
		points = append(points, chartTwoDimPoint{X: r.StationName, Y: float64(r.EmptyHours)})
		categories = append(categories, r.StationName)
	}

	c.JSON(http.StatusOK, chartTwoDimResponse{
		Status:     "success",
		Data:       []chartTwoDimSeries{{Name: "缺車時數（小時）", Data: points}},
		Categories: categories,
	})
}

// GetYouBikeImbalanceChart handles GET /api/v1/commute/youbike/imbalance.
//
// Returns the borrow/return-imbalance ranking (top 15 stations by absolute
// imbalance) for the requested city slice in the standard chart-data response
// shape. y is the *negated* imbalance — preserving the frontend convention
// where "outflow" reads as a positive bar going right.
func GetYouBikeImbalanceChart(c *gin.Context) {
	payload, status, errMsg := getYouBikeAggregatePayload(c.Request.Context())
	if status != 0 {
		c.JSON(status, gin.H{"message": errMsg})
		return
	}

	cityKey := resolveYouBikeAggregateCity(c)
	cityBlock := payload.Imbalance[cityKey]
	rows := cityBlock["absolute"]
	const imbalanceTopN = 15
	if len(rows) > imbalanceTopN {
		rows = rows[:imbalanceTopN]
	}

	points := make([]chartTwoDimPoint, 0, len(rows))
	categories := make([]string, 0, len(rows))
	for _, r := range rows {
		points = append(points, chartTwoDimPoint{X: r.StationName, Y: float64(-r.Imbalance)})
		categories = append(categories, r.StationName)
	}

	c.JSON(http.StatusOK, chartTwoDimResponse{
		Status:     "success",
		Data:       []chartTwoDimSeries{{Name: "估計淨流出量", Data: points}},
		Categories: categories,
	})
}
