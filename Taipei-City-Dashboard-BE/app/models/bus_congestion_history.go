package models

import (
	"time"

	"github.com/lib/pq"
)

// BusCongestionTimelinePoint is one (snapshot_time × label) aggregate row
// from bus_congestion_history_segments.
type BusCongestionTimelinePoint struct {
	SnapshotTime time.Time
	Label        string
	SegmentCount int64
	AvgSegErr    float64
	TotalSamples int64
}

// busCongestionCityCondition maps the public city scope to the PostgreSQL
// city values stored in bus_congestion_segments. taipei → ['台北市'];
// metrotaipei → ['台北市','新北市']. Caller passes the result through
// pq.Array so SQL can use `city = ANY($N)`.
//
// Note: 台 is U+53F0 (not 臺 / U+81FA) — verified by
//
//	SELECT DISTINCT city FROM bus_congestion_segments;
func busCongestionCityCondition(city string) []string {
	switch city {
	case "taipei":
		return []string{"台北市"}
	case "metrotaipei":
		return []string{"台北市", "新北市"}
	default:
		return nil
	}
}

// ListBusCongestionRoutes returns distinct route_name values for a city
// scope, sourced from bus_congestion_segments (the full latest set, not the
// matview — the matview is taipei-edges-only and would hide all 新北市
// routes including frequently-asked ones like "275"). Returns empty (not
// error) when the dashboard DB handle is unavailable or the city scope
// is unsupported.
func ListBusCongestionRoutes(city string) ([]string, error) {
	if DBDashboard == nil {
		return []string{}, nil
	}
	cities := busCongestionCityCondition(city)
	if len(cities) == 0 {
		return []string{}, nil
	}

	const sql = `
SELECT DISTINCT route_name
FROM public.bus_congestion_segments
WHERE city = ANY($1)
  AND route_name IS NOT NULL
  AND route_name <> ''
ORDER BY route_name`

	sqlDB, err := DBDashboard.DB()
	if err != nil {
		return nil, err
	}
	rows, err := sqlDB.Query(sql, pq.Array(cities))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]string, 0, 600)
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}

// GetBusCongestionTimeline returns one (snapshot_time × label) aggregate row
// per pair, optionally restricted to a single route. Excludes the 「無資料」
// label by default — it dominates the matview (~75% of rows) and visually
// drowns the meaningful congestion levels in a stacked chart.
//
// The matview currently only contains 台北市 edges, so metrotaipei + a 新北
// route returns an empty slice. The controller surfaces that gap via a
// `data_note` field on the response.
func GetBusCongestionTimeline(city, routeName string) ([]BusCongestionTimelinePoint, error) {
	if DBDashboard == nil {
		return []BusCongestionTimelinePoint{}, nil
	}
	cities := busCongestionCityCondition(city)
	if len(cities) == 0 {
		return []BusCongestionTimelinePoint{}, nil
	}

	const sql = `
SELECT snapshot_time,
       label,
       COUNT(*)                       AS segment_count,
       COALESCE(AVG(seg_err), 0)      AS avg_seg_err,
       COALESCE(SUM(n_samples), 0)    AS total_samples
FROM public.bus_congestion_history_segments
WHERE city = ANY($1)
  AND label <> '無資料'
  AND ($2 = '' OR route_name = $2)
GROUP BY snapshot_time, label
ORDER BY snapshot_time, label`

	sqlDB, err := DBDashboard.DB()
	if err != nil {
		return nil, err
	}
	rows, err := sqlDB.Query(sql, pq.Array(cities), routeName)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]BusCongestionTimelinePoint, 0, 80)
	for rows.Next() {
		var p BusCongestionTimelinePoint
		if err := rows.Scan(&p.SnapshotTime, &p.Label, &p.SegmentCount, &p.AvgSegErr, &p.TotalSamples); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}
