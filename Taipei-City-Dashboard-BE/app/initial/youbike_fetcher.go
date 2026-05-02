package initial

import (
	"TaipeiCityDashboardBE/app/cache"
	"TaipeiCityDashboardBE/app/models"
	"TaipeiCityDashboardBE/logs"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/robfig/cron/v3"
)

const (
	YouBikeFetcherLockKey = "cron:youbike_fetcher_lock"
	youBikeFetcherURL     = "https://apis.youbike.com.tw/json/station-yb2.json"
	youBikeFetchTimeout   = 30 * time.Second
	youBikeJobTimeout     = 90 * time.Second

	youBikeCurrentTable = "youbike_immediate"
	youBikeHistoryTable = "youbike_immediate_history"

	youBikeBatchSize = 200
)

// City prefix → display name. Mirrors the Python fetcher's CITY_MAP and
// determines which stations get persisted (others are dropped).
var youBikeCityMap = map[string]string{
	"5001": "台北市",
	"5002": "新北市",
}

// Schema is created on first run; subsequent runs are no-ops thanks to
// IF NOT EXISTS. wkb_geometry uses PostGIS Point/4326 to match the existing
// dashboard DB conventions.
const youBikeCreateTableSQL = `
CREATE TABLE IF NOT EXISTS %s (
    sno                    VARCHAR(20),
    city                   VARCHAR(10),
    sna                    VARCHAR(100),
    snaen                  VARCHAR(200),
    sarea                  VARCHAR(50),
    sareaen                VARCHAR(100),
    addr                   VARCHAR(200),
    adren                  VARCHAR(200),
    status                 SMALLINT,
    data_time              TIMESTAMPTZ,
    total_bikes            INTEGER,
    available_rent_bikes   INTEGER,
    yb2_quantity           INTEGER,
    eyb_quantity           INTEGER,
    available_return_bikes INTEGER,
    longitude              NUMERIC(10, 6),
    latitude               NUMERIC(10, 6),
    wkb_geometry           GEOMETRY(Point, 4326)
);`

const youBikeCreateHistoryTableSQL = `
CREATE TABLE IF NOT EXISTS %s (
    id                     SERIAL PRIMARY KEY,
    sno                    VARCHAR(20),
    city                   VARCHAR(10),
    sna                    VARCHAR(100),
    snaen                  VARCHAR(200),
    sarea                  VARCHAR(50),
    sareaen                VARCHAR(100),
    addr                   VARCHAR(200),
    adren                  VARCHAR(200),
    status                 SMALLINT,
    data_time              TIMESTAMPTZ,
    total_bikes            INTEGER,
    available_rent_bikes   INTEGER,
    yb2_quantity           INTEGER,
    eyb_quantity           INTEGER,
    available_return_bikes INTEGER,
    longitude              NUMERIC(10, 6),
    latitude               NUMERIC(10, 6),
    wkb_geometry           GEOMETRY(Point, 4326)
);`

// youBikeStation holds the upstream JSON payload — only fields the writer
// actually persists are decoded. Numeric fields are decoded as json.Number
// because the upstream returns lat/lng as strings (and may flip other fields
// between string and number across releases).
type youBikeStation struct {
	StationNo             string      `json:"station_no"`
	NameTW                string      `json:"name_tw"`
	NameEN                string      `json:"name_en"`
	DistrictTW            string      `json:"district_tw"`
	DistrictEN            string      `json:"district_en"`
	AddressTW             string      `json:"address_tw"`
	AddressEN             string      `json:"address_en"`
	Status                json.Number `json:"status"`
	UpdatedAt             string      `json:"updated_at"`
	ParkingSpaces         json.Number `json:"parking_spaces"`
	AvailableSpaces       json.Number `json:"available_spaces"`
	EmptySpaces           json.Number `json:"empty_spaces"`
	Lat                   string      `json:"lat"`
	Lng                   string      `json:"lng"`
	AvailableSpacesDetail struct {
		YB2 json.Number `json:"yb2"`
		EYB json.Number `json:"eyb"`
	} `json:"available_spaces_detail"`
}

func ybNumInt(n json.Number) int {
	if n == "" {
		return 0
	}
	if v, err := n.Int64(); err == nil {
		return int(v)
	}
	if v, err := strconv.Atoi(strings.TrimSpace(string(n))); err == nil {
		return v
	}
	return 0
}

func ybStrFloat(s string) float64 {
	v, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if err != nil {
		return 0
	}
	return v
}

// stationRow is the post-transform shape that gets bulk-inserted.
type stationRow struct {
	sno, city, sna, snaen, sarea, sareaen, addr, adren string
	status                                             int
	dataTime                                           sql.NullTime
	totalBikes, availRent, yb2, eyb, availReturn       int
	longitude, latitude                                float64
}

// RegisterYouBikeFetcherJob schedules a 1-minute YouBike scrape against
// the dashboard DB. Off by default — opt in with YOUBIKE_FETCHER_ENABLED=true.
//
// Replaces the standalone Python fetcher (docker/youbike-fetcher/fetch_ubike.py)
// so we don't pull in `requests` / `psycopg2-binary` outside of v3.1.9 deps.
func RegisterYouBikeFetcherJob(c *cron.Cron) {
	if !youBikeFetcherEnabled() {
		logs.Info("YouBike fetcher cron skipped (YOUBIKE_FETCHER_ENABLED is not true)")
		return
	}

	if _, err := c.AddFunc("@every 1m", runYouBikeFetcher); err != nil {
		logs.Error("Failed to add YouBike fetcher cron job:", err)
		return
	}
	logs.Info("YouBike fetcher cron registered (@every 1m).")
}

func youBikeFetcherEnabled() bool {
	v, _ := strconv.ParseBool(strings.TrimSpace(os.Getenv("YOUBIKE_FETCHER_ENABLED")))
	return v
}

func runYouBikeFetcher() {
	ctx, cancel := context.WithTimeout(context.Background(), youBikeJobTimeout)
	defer cancel()

	token := uuid.New().String()
	lockAcquired, err := cache.Redis.SetNX(YouBikeFetcherLockKey, token, 5*time.Minute).Result()
	if err != nil {
		logs.Error("YouBike fetcher: lock error:", err)
		return
	}
	if !lockAcquired {
		logs.Info("YouBike fetcher: lock held by another instance, skipping.")
		return
	}
	defer func() {
		cmd := cache.Redis.Eval(ReleaseLockScript, []string{YouBikeFetcherLockKey}, token)
		if cmd.Err() != nil {
			logs.Error("YouBike fetcher: lock release error:", cmd.Err())
		}
	}()

	if models.DBDashboard == nil {
		logs.Warn("YouBike fetcher: dashboard DB not connected, skipping cycle.")
		return
	}

	stations, err := fetchYouBikeStations(ctx)
	if err != nil {
		logs.Error("YouBike fetcher: upstream fetch failed:", err)
		return
	}

	rows := transformYouBikeStations(stations)
	if len(rows) == 0 {
		logs.Warn("YouBike fetcher: upstream returned no stations matching CITY_MAP.")
		return
	}

	if err := writeYouBikeRows(ctx, rows); err != nil {
		logs.Error("YouBike fetcher: write failed:", err)
		return
	}

	logs.FInfo("YouBike fetcher: persisted %d stations.", len(rows))
}

func fetchYouBikeStations(ctx context.Context) ([]youBikeStation, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, youBikeFetcherURL, nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	// Upstream rejects unknown UAs, mirror the Python fetcher's headers.
	req.Header.Set("User-Agent", "Mozilla/5.0 (compatible; TaipeiCityDashboard/1.0)")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Referer", "https://www.youbike.com.tw/")

	client := &http.Client{Timeout: youBikeFetchTimeout}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("upstream status %d", resp.StatusCode)
	}

	var stations []youBikeStation
	if err := json.NewDecoder(resp.Body).Decode(&stations); err != nil {
		return nil, fmt.Errorf("decode: %w", err)
	}
	return stations, nil
}

func transformYouBikeStations(stations []youBikeStation) []stationRow {
	rows := make([]stationRow, 0, len(stations))
	for _, s := range stations {
		if len(s.StationNo) < 4 {
			continue
		}
		city, ok := youBikeCityMap[s.StationNo[:4]]
		if !ok {
			continue
		}
		rows = append(rows, stationRow{
			sno:         s.StationNo,
			city:        city,
			sna:         s.NameTW,
			snaen:       s.NameEN,
			sarea:       s.DistrictTW,
			sareaen:     s.DistrictEN,
			addr:        s.AddressTW,
			adren:       s.AddressEN,
			status:      ybNumInt(s.Status),
			dataTime:    parseTaipeiTime(s.UpdatedAt),
			totalBikes:  ybNumInt(s.ParkingSpaces),
			availRent:   ybNumInt(s.AvailableSpaces),
			yb2:         ybNumInt(s.AvailableSpacesDetail.YB2),
			eyb:         ybNumInt(s.AvailableSpacesDetail.EYB),
			availReturn: ybNumInt(s.EmptySpaces),
			longitude:   ybStrFloat(s.Lng),
			latitude:    ybStrFloat(s.Lat),
		})
	}
	return rows
}

func parseTaipeiTime(s string) sql.NullTime {
	if strings.TrimSpace(s) == "" {
		return sql.NullTime{}
	}
	loc, err := time.LoadLocation("Asia/Taipei")
	if err != nil {
		loc = time.FixedZone("Asia/Taipei", 8*60*60)
	}
	t, err := time.ParseInLocation("2006-01-02 15:04:05", s, loc)
	if err != nil {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: t, Valid: true}
}

func writeYouBikeRows(ctx context.Context, rows []stationRow) error {
	sqlDB, err := models.DBDashboard.DB()
	if err != nil {
		return fmt.Errorf("get sql.DB: %w", err)
	}

	tx, err := sqlDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if _, err = tx.ExecContext(ctx, fmt.Sprintf(youBikeCreateTableSQL, youBikeCurrentTable)); err != nil {
		return fmt.Errorf("create current table: %w", err)
	}
	if _, err = tx.ExecContext(ctx, fmt.Sprintf(youBikeCreateHistoryTableSQL, youBikeHistoryTable)); err != nil {
		return fmt.Errorf("create history table: %w", err)
	}

	if _, err = tx.ExecContext(ctx, fmt.Sprintf("DELETE FROM %s", youBikeCurrentTable)); err != nil {
		return fmt.Errorf("truncate current: %w", err)
	}

	if err = bulkInsertYouBike(ctx, tx, youBikeCurrentTable, rows); err != nil {
		return fmt.Errorf("insert current: %w", err)
	}
	if err = bulkInsertYouBike(ctx, tx, youBikeHistoryTable, rows); err != nil {
		return fmt.Errorf("insert history: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

func bulkInsertYouBike(ctx context.Context, tx *sql.Tx, table string, rows []stationRow) error {
	// 17 actual columns + 2 extra params for ST_MakePoint(longitude, latitude).
	// We pass longitude/latitude twice so PG resolves NUMERIC and float8 contexts
	// to independent placeholders, avoiding "inconsistent types deduced" errors.
	const colsPerRow = 19

	for start := 0; start < len(rows); start += youBikeBatchSize {
		end := start + youBikeBatchSize
		if end > len(rows) {
			end = len(rows)
		}
		batch := rows[start:end]

		placeholders := make([]string, 0, len(batch))
		args := make([]interface{}, 0, len(batch)*colsPerRow)

		for i, r := range batch {
			base := i * colsPerRow
			placeholders = append(placeholders, fmt.Sprintf(
				"($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,ST_SetSRID(ST_MakePoint($%d,$%d),4326))",
				base+1, base+2, base+3, base+4, base+5, base+6, base+7, base+8,
				base+9, base+10, base+11, base+12, base+13, base+14, base+15,
				base+16, base+17, base+18, base+19,
			))
			args = append(args,
				r.sno, r.city, r.sna, r.snaen, r.sarea, r.sareaen, r.addr, r.adren,
				r.status, r.dataTime,
				r.totalBikes, r.availRent, r.yb2, r.eyb, r.availReturn,
				r.longitude, r.latitude,
				r.longitude, r.latitude,
			)
		}

		stmt := fmt.Sprintf(`INSERT INTO %s (
            sno, city, sna, snaen, sarea, sareaen, addr, adren,
            status, data_time, total_bikes, available_rent_bikes,
            yb2_quantity, eyb_quantity, available_return_bikes,
            longitude, latitude, wkb_geometry
        ) VALUES %s`, table, strings.Join(placeholders, ","))

		if _, err := tx.ExecContext(ctx, stmt, args...); err != nil {
			return err
		}
	}
	return nil
}
