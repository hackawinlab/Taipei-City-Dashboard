// Package youbike_aggregate computes the YouBike shortage analysis dashboard
// payload from the hackathon-DB youbike_snapshots table. It is consumed
// directly by controllers/commute.GetYouBikeShortageAnalysis — there is no
// CSV input or static JSON output any more; load-ubike-data.sh seeds the
// table once and the dashboard fetches an API endpoint from then on.
//
// Logic is a stdlib-only Go port of the original
// data/aggregate_youbike_hourly.py. Only the four blocks the frontend reads
// (timeline_low, bar_persistence, heatmap, imbalance) are computed.
package youbike_aggregate

import (
	"context"
	"database/sql"
	"math"
	"sort"
	"strings"
	"time"
)

const (
	emptyThreshold    = 1.0
	lowRatioThreshold = 0.2
	burstThreshold    = 5
	heatmapMinDocks   = 30
	topNPersistence   = 25
	topNHeatmap       = 25
	topNImbalance     = 15
)

// taipeiLoc localises every snapshot_at the moment we read it from
// youbike_snapshots (TIMESTAMPTZ → Go time defaults to UTC). All hour-bucket
// labels and timeline X axes need to land on the Taipei wall clock to match
// commute.go's `AT TIME ZONE 'Asia/Taipei'` SQL convention.
var taipeiLoc = func() *time.Location {
	loc, err := time.LoadLocation("Asia/Taipei")
	if err != nil {
		return time.FixedZone("Asia/Taipei", 8*3600)
	}
	return loc
}()

// Snapshot is one row of the hackathon youbike_snapshots table.
type Snapshot struct {
	SnapshotAt     time.Time
	Hour           time.Time
	City           string
	StationUID     string
	StationName    string
	Lat, Lon       float64
	AvailableBikes float64
	TotalDocks     int
	ElectricBikes  float64
}

// stationHour is a per-(hour, station) bucket — internal only.
type stationHour struct {
	Hour              time.Time
	City              string
	StationUID        string
	StationName       string
	AvgAvailableBikes float64
	TotalDocks        int
	FillRatio         float64 // NaN when total_docks == 0
	IsEmpty, IsLow    bool
}

// hourCity is a per-(hour, city) summary used to build the timeline_low block.
type hourCity struct {
	Hour          time.Time
	City          string
	StationCount  int
	EmptyStations int
	LowStations   int
}

// Payload mirrors the subset of the original aggregator JSON that the dashboard
// reads. The two new chart endpoints (controllers/commute.go's GetYouBikePersistenceChart,
// GetYouBikeImbalanceChart) consume only BarPersistence and Imbalance. TimelineLow
// and Heatmap remain in the struct because the legacy /commute/youbike/shortage-analysis
// endpoint still serves the full payload; once that route is retired they can be
// dropped (tracked in CLAUDE.md "遺留" note).
type Payload struct {
	TimelineLow    []TimelineSeries                     `json:"timeline_low"`
	BarPersistence map[string][]PersistenceEntry        `json:"bar_persistence"`
	Heatmap        map[string]HeatmapBlock              `json:"heatmap"`
	Imbalance      map[string]map[string][]ImbalanceRow `json:"imbalance"`
}

// TimelineSeries is one line in the low-bike-ratio chart (one per city).
type TimelineSeries struct {
	Name string          `json:"name"`
	Data []TimelinePoint `json:"data"`
}

type TimelinePoint struct {
	X string  `json:"x"`
	Y float64 `json:"y"`
}

// PersistenceEntry is one row of the chronic-shortage bar block.
type PersistenceEntry struct {
	StationName    string  `json:"station_name"`
	City           string  `json:"city"`
	EmptyHours     int     `json:"empty_hours"`
	LowHours       int     `json:"low_hours"`
	HoursObserved  int     `json:"hours_observed"`
	EmptyHourRatio float64 `json:"empty_hour_ratio"`
	LowHourRatio   float64 `json:"low_hour_ratio"`
	AvgFillRatio   float64 `json:"avg_fill_ratio"`
	TotalDocks     int     `json:"total_docks"`
}

// HeatmapBlock is one city's heatmap (top-N volatile stations × hour-of-day).
type HeatmapBlock struct {
	Categories []string        `json:"categories"`
	Series     []HeatmapSeries `json:"series"`
}

type HeatmapSeries struct {
	Name string         `json:"name"`
	Data []HeatmapPoint `json:"data"`
}

type HeatmapPoint struct {
	X string   `json:"x"`
	Y *float64 `json:"y"`
}

// ImbalanceRow is one row of the borrow/return-imbalance ranking.
type ImbalanceRow struct {
	StationName        string  `json:"station_name"`
	City               string  `json:"city"`
	EstBorrow          int     `json:"est_borrow"`
	EstReturn          int     `json:"est_return"`
	EstReturnBurst     int     `json:"est_return_burst"`
	EstReturnSteady    int     `json:"est_return_steady"`
	Imbalance          int     `json:"imbalance"`
	ImbalancePerDock   float64 `json:"imbalance_per_dock"`
	DispatchDependency float64 `json:"dispatch_dependency"`
	TotalDocks         int     `json:"total_docks"`
}

// LoadFromDB pulls every snapshot out of the hackathon youbike_snapshots
// table. The dataset is small (~130k rows) so a single full scan is fine —
// hackathon snapshots stop growing once load-ubike-data.sh finishes.
func LoadFromDB(ctx context.Context, db *sql.DB) ([]Snapshot, error) {
	rows, err := db.QueryContext(ctx, `
SELECT snapshot_at, city, station_uid, station_name,
       lat, lon, available_bikes, total_docks, electric_bikes
FROM youbike_snapshots`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []Snapshot
	for rows.Next() {
		var (
			s             Snapshot
			ts            time.Time
			availableBikes sql.NullFloat64
			electricBikes  sql.NullFloat64
			totalDocks     sql.NullInt64
		)
		if err := rows.Scan(
			&ts, &s.City, &s.StationUID, &s.StationName,
			&s.Lat, &s.Lon, &availableBikes, &totalDocks, &electricBikes,
		); err != nil {
			return nil, err
		}
		s.SnapshotAt = ts.In(taipeiLoc)
		s.Hour = floorHour(s.SnapshotAt)
		s.AvailableBikes = availableBikes.Float64
		s.ElectricBikes = electricBikes.Float64
		s.TotalDocks = int(totalDocks.Int64)
		out = append(out, s)
	}
	return out, rows.Err()
}

// stripPrefix matches the Python helper that drops the YouBike2.0_ chrome
// from station names so chart labels read better.
func stripPrefix(name string) string {
	for _, p := range []string{"YouBike2.0_", "YouBike2_", "YouBike_"} {
		if strings.HasPrefix(name, p) {
			return name[len(p):]
		}
	}
	return name
}

func roundTo(v float64, digits int) float64 {
	if math.IsNaN(v) || math.IsInf(v, 0) {
		return v
	}
	scale := math.Pow10(digits)
	return math.Round(v*scale) / scale
}

func floorHour(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), 0, 0, 0, t.Location())
}

func hourLabelHHMM(t time.Time) string { return t.Format("15:04") }
func hourISO(t time.Time) string       { return t.Format("2006-01-02T15:04:05") }

type stationKey struct {
	hour       time.Time
	stationUID string
}

func aggregateByStation(snapshots []Snapshot) []stationHour {
	type acc struct {
		city, stationUID, stationName string
		hour                          time.Time
		sumBikes                      float64
		maxTotalDocks                 int
		samples                       int
	}
	buckets := map[stationKey]*acc{}
	for _, s := range snapshots {
		k := stationKey{s.Hour, s.StationUID}
		a, ok := buckets[k]
		if !ok {
			a = &acc{
				city:        s.City,
				stationUID:  s.StationUID,
				stationName: s.StationName,
				hour:        s.Hour,
			}
			buckets[k] = a
		}
		a.sumBikes += s.AvailableBikes
		if s.TotalDocks > a.maxTotalDocks {
			a.maxTotalDocks = s.TotalDocks
		}
		a.samples++
	}

	out := make([]stationHour, 0, len(buckets))
	for _, a := range buckets {
		avgBikes := a.sumBikes / float64(a.samples)
		var fillRatio float64
		if a.maxTotalDocks > 0 {
			fillRatio = avgBikes / float64(a.maxTotalDocks)
		} else {
			fillRatio = math.NaN()
		}
		out = append(out, stationHour{
			Hour:              a.hour,
			City:              a.city,
			StationUID:        a.stationUID,
			StationName:       a.stationName,
			AvgAvailableBikes: roundTo(avgBikes, 2),
			TotalDocks:        a.maxTotalDocks,
			FillRatio:         roundTo(fillRatio, 4),
			IsEmpty:           avgBikes < emptyThreshold,
			IsLow:             !math.IsNaN(fillRatio) && fillRatio < lowRatioThreshold,
		})
	}
	return out
}

func aggregateByHourCity(byStation []stationHour) []hourCity {
	type acc struct {
		hour       time.Time
		city       string
		stations   map[string]struct{}
		empty, low int
	}
	type key struct {
		hour time.Time
		city string
	}
	buckets := map[key]*acc{}
	for _, s := range byStation {
		k := key{s.Hour, s.City}
		a, ok := buckets[k]
		if !ok {
			a = &acc{hour: s.Hour, city: s.City, stations: map[string]struct{}{}}
			buckets[k] = a
		}
		a.stations[s.StationUID] = struct{}{}
		if s.IsEmpty {
			a.empty++
		}
		if s.IsLow {
			a.low++
		}
	}
	out := make([]hourCity, 0, len(buckets))
	for _, a := range buckets {
		out = append(out, hourCity{
			Hour:          a.hour,
			City:          a.city,
			StationCount:  len(a.stations),
			EmptyStations: a.empty,
			LowStations:   a.low,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if !out[i].Hour.Equal(out[j].Hour) {
			return out[i].Hour.Before(out[j].Hour)
		}
		return out[i].City < out[j].City
	})
	return out
}

func computeImbalance(snapshots []Snapshot, cities []string) map[string]map[string][]ImbalanceRow {
	byStation := map[string][]Snapshot{}
	docksLookup := map[string]int{}
	for _, s := range snapshots {
		byStation[s.StationUID] = append(byStation[s.StationUID], s)
		if _, ok := docksLookup[s.StationUID]; !ok {
			docksLookup[s.StationUID] = s.TotalDocks
		}
	}

	type acc struct {
		city, stationUID, stationName               string
		estBorrow, estReturn                        float64
		estReturnBurst, estReturnSteady             float64
	}
	buckets := map[string]*acc{}
	for uid, snaps := range byStation {
		sort.Slice(snaps, func(i, j int) bool { return snaps[i].SnapshotAt.Before(snaps[j].SnapshotAt) })
		for i := 1; i < len(snaps); i++ {
			delta := snaps[i].AvailableBikes - snaps[i-1].AvailableBikes
			a, ok := buckets[uid]
			if !ok {
				a = &acc{
					city:        snaps[i].City,
					stationUID:  uid,
					stationName: snaps[i].StationName,
				}
				buckets[uid] = a
			}
			switch {
			case delta < 0:
				a.estBorrow += -delta
			case delta >= burstThreshold:
				a.estReturn += delta
				a.estReturnBurst += delta
			case delta > 0:
				a.estReturn += delta
				a.estReturnSteady += delta
			}
		}
	}

	rows := make([]ImbalanceRow, 0, len(buckets))
	for _, a := range buckets {
		imbalance := a.estReturn - a.estBorrow
		dockCount := docksLookup[a.stationUID]
		clipReturn := a.estReturn
		if clipReturn < 1 {
			clipReturn = 1
		}
		clipDocks := dockCount
		if clipDocks < 1 {
			clipDocks = 1
		}
		rows = append(rows, ImbalanceRow{
			StationName:        stripPrefix(a.stationName),
			City:               a.city,
			EstBorrow:          int(math.Round(a.estBorrow)),
			EstReturn:          int(math.Round(a.estReturn)),
			EstReturnBurst:     int(math.Round(a.estReturnBurst)),
			EstReturnSteady:    int(math.Round(a.estReturnSteady)),
			Imbalance:          int(math.Round(imbalance)),
			ImbalancePerDock:   roundTo(imbalance/float64(clipDocks), 4),
			DispatchDependency: roundTo(a.estReturnBurst/clipReturn, 3),
			TotalDocks:         dockCount,
		})
	}

	out := map[string]map[string][]ImbalanceRow{}
	for _, city := range cities {
		var view []ImbalanceRow
		if city == "All" {
			view = append(view, rows...)
		} else {
			for _, r := range rows {
				if r.City == city {
					view = append(view, r)
				}
			}
		}

		absView := make([]ImbalanceRow, len(view))
		copy(absView, view)
		sort.Slice(absView, func(i, j int) bool { return absView[i].Imbalance < absView[j].Imbalance })
		if len(absView) > topNImbalance {
			absView = absView[:topNImbalance]
		}

		perDock := []ImbalanceRow{}
		for _, r := range view {
			if r.TotalDocks >= 10 {
				perDock = append(perDock, r)
			}
		}
		sort.Slice(perDock, func(i, j int) bool {
			return perDock[i].ImbalancePerDock < perDock[j].ImbalancePerDock
		})
		if len(perDock) > topNImbalance {
			perDock = perDock[:topNImbalance]
		}

		out[city] = map[string][]ImbalanceRow{
			"absolute": absView,
			"per_dock": perDock,
		}
	}
	return out
}

func buildBarPersistence(byStation []stationHour, cities []string) map[string][]PersistenceEntry {
	type acc struct {
		city, stationName string
		hours             map[time.Time]struct{}
		empty, low        int
		fillSum           float64
		fillCount         int
		totalDocks        int
	}
	buckets := map[string]*acc{}
	for _, s := range byStation {
		a, ok := buckets[s.StationUID]
		if !ok {
			a = &acc{
				city:        s.City,
				stationName: s.StationName,
				hours:       map[time.Time]struct{}{},
			}
			buckets[s.StationUID] = a
		}
		a.hours[s.Hour] = struct{}{}
		if s.IsEmpty {
			a.empty++
		}
		if s.IsLow {
			a.low++
		}
		if !math.IsNaN(s.FillRatio) {
			a.fillSum += s.FillRatio
			a.fillCount++
		}
		if s.TotalDocks > a.totalDocks {
			a.totalDocks = s.TotalDocks
		}
	}

	all := make([]PersistenceEntry, 0, len(buckets))
	for _, a := range buckets {
		hours := len(a.hours)
		avgFill := 0.0
		if a.fillCount > 0 {
			avgFill = a.fillSum / float64(a.fillCount)
		}
		all = append(all, PersistenceEntry{
			StationName:    stripPrefix(a.stationName),
			City:           a.city,
			EmptyHours:     a.empty,
			LowHours:       a.low,
			HoursObserved:  hours,
			EmptyHourRatio: roundTo(float64(a.empty)/float64(hours), 4),
			LowHourRatio:   roundTo(float64(a.low)/float64(hours), 4),
			AvgFillRatio:   roundTo(avgFill, 4),
			TotalDocks:     a.totalDocks,
		})
	}

	out := map[string][]PersistenceEntry{}
	for _, city := range cities {
		view := []PersistenceEntry{}
		for _, r := range all {
			if city == "All" || r.City == city {
				view = append(view, r)
			}
		}
		sort.Slice(view, func(i, j int) bool {
			if view[i].EmptyHourRatio != view[j].EmptyHourRatio {
				return view[i].EmptyHourRatio > view[j].EmptyHourRatio
			}
			if view[i].LowHourRatio != view[j].LowHourRatio {
				return view[i].LowHourRatio > view[j].LowHourRatio
			}
			return view[i].TotalDocks > view[j].TotalDocks
		})
		if len(view) > topNPersistence {
			view = view[:topNPersistence]
		}
		out[city] = view
	}
	return out
}

func buildHeatmap(byStation []stationHour, cities []string) map[string]HeatmapBlock {
	// Per-station total_docks, station name, and the slice of fill_ratio
	// observations needed to compute the std-dev rank.
	type fillAcc struct {
		city        string
		stationName string
		totalDocks  int
		fillValues  []float64
	}
	fillBuckets := map[string]*fillAcc{}
	for _, s := range byStation {
		if math.IsNaN(s.FillRatio) {
			continue
		}
		a, ok := fillBuckets[s.StationUID]
		if !ok {
			a = &fillAcc{city: s.City, stationName: s.StationName}
			fillBuckets[s.StationUID] = a
		}
		if s.TotalDocks > a.totalDocks {
			a.totalDocks = s.TotalDocks
		}
		a.fillValues = append(a.fillValues, s.FillRatio)
	}

	stdOf := func(values []float64) float64 {
		if len(values) <= 1 {
			return 0
		}
		var mean float64
		for _, v := range values {
			mean += v
		}
		mean /= float64(len(values))
		var sumSq float64
		for _, v := range values {
			d := v - mean
			sumSq += d * d
		}
		// pandas DataFrame.std defaults to ddof=1 (sample std).
		return math.Sqrt(sumSq / float64(len(values)-1))
	}

	type fillStat struct {
		stationUID string
		city       string
		std        float64
	}
	stats := []fillStat{}
	stationNames := map[string]string{}
	for uid, a := range fillBuckets {
		if a.totalDocks < heatmapMinDocks {
			continue
		}
		stationNames[uid] = a.stationName
		stats = append(stats, fillStat{
			stationUID: uid,
			city:       a.city,
			std:        stdOf(a.fillValues),
		})
	}

	type hourStation struct{ uid, label string }
	hourStationFill := map[hourStation]float64{}
	hourLabels := map[string]struct{}{}
	for _, s := range byStation {
		if math.IsNaN(s.FillRatio) {
			continue
		}
		hl := hourLabelHHMM(s.Hour)
		hourLabels[hl] = struct{}{}
		hourStationFill[hourStation{s.StationUID, hl}] = s.FillRatio
	}
	categories := make([]string, 0, len(hourLabels))
	for h := range hourLabels {
		categories = append(categories, h)
	}
	sort.Strings(categories)

	out := map[string]HeatmapBlock{}
	for _, city := range cities {
		view := []fillStat{}
		for _, r := range stats {
			if city == "All" || r.city == city {
				view = append(view, r)
			}
		}
		sort.Slice(view, func(i, j int) bool { return view[i].std > view[j].std })
		if len(view) > topNHeatmap {
			view = view[:topNHeatmap]
		}

		series := make([]HeatmapSeries, 0, len(view))
		for _, r := range view {
			pts := make([]HeatmapPoint, 0, len(categories))
			for _, hl := range categories {
				pt := HeatmapPoint{X: hl}
				if v, ok := hourStationFill[hourStation{r.stationUID, hl}]; ok {
					rounded := roundTo(v*100, 1)
					pt.Y = &rounded
				}
				pts = append(pts, pt)
			}
			series = append(series, HeatmapSeries{
				Name: stripPrefix(stationNames[r.stationUID]),
				Data: pts,
			})
		}
		out[city] = HeatmapBlock{Categories: categories, Series: series}
	}
	return out
}

func buildTimelineLow(summary []hourCity) []TimelineSeries {
	out := []TimelineSeries{}
	for _, city := range []string{"Taipei", "NewTaipei"} {
		pts := []TimelinePoint{}
		for _, r := range summary {
			if r.City != city {
				continue
			}
			ratio := 0.0
			if r.StationCount > 0 {
				ratio = float64(r.LowStations) / float64(r.StationCount) * 100
			}
			pts = append(pts, TimelinePoint{X: hourISO(r.Hour), Y: roundTo(ratio, 2)})
		}
		out = append(out, TimelineSeries{Name: city, Data: pts})
	}
	return out
}

// BuildPayload runs the full aggregation pipeline against an in-memory slice
// of snapshots and returns the four blocks the dashboard frontend reads.
func BuildPayload(snapshots []Snapshot) Payload {
	cities := []string{"All", "Taipei", "NewTaipei"}
	byStation := aggregateByStation(snapshots)
	summary := aggregateByHourCity(byStation)

	return Payload{
		TimelineLow:    buildTimelineLow(summary),
		BarPersistence: buildBarPersistence(byStation, cities),
		Heatmap:        buildHeatmap(byStation, cities),
		Imbalance:      computeImbalance(snapshots, cities),
	}
}
