package models

import (
	"time"
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

// 臺北市 is the only city currently present in bus_congestion_history_segments
// (the matview filters seg_id LIKE '%-%' and the local edge history is taipei-only).
// Kept as a helper rather than scattering the literal across the package.
func busCongestionCityZH(city string) string {
	// Matview rows actually use 台 (U+53F0), not 臺 (U+81FA) — verified by
	// `SELECT DISTINCT city FROM bus_congestion_history_segments`.
	switch city {
	case "taipei":
		return "台北市"
	case "metrotaipei":
		// metrotaipei intentionally falls back to taipei: only edge history
		// for 台北市 is enriched in the local matview. Callers can still
		// use the city param for sidebar/filter UX.
		return "台北市"
	default:
		return ""
	}
}

// ListBusCongestionRoutes returns distinct route_name values for a city,
// from bus_congestion_history_segments. Returns empty (not error) when the
// dashboard DB handle is unavailable or the city is unsupported.
func ListBusCongestionRoutes(city string) ([]string, error) {
	if DBDashboard == nil {
		return []string{}, nil
	}
	cityZH := busCongestionCityZH(city)
	if cityZH == "" {
		return []string{}, nil
	}

	const sql = `
SELECT DISTINCT route_name
FROM public.bus_congestion_history_segments
WHERE city = $1
  AND route_name IS NOT NULL
  AND route_name <> ''
ORDER BY route_name`

	sqlDB, err := DBDashboard.DB()
	if err != nil {
		return nil, err
	}
	rows, err := sqlDB.Query(sql, cityZH)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]string, 0, 300)
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
func GetBusCongestionTimeline(city, routeName string) ([]BusCongestionTimelinePoint, error) {
	if DBDashboard == nil {
		return []BusCongestionTimelinePoint{}, nil
	}
	cityZH := busCongestionCityZH(city)
	if cityZH == "" {
		return []BusCongestionTimelinePoint{}, nil
	}

	const sql = `
SELECT snapshot_time,
       label,
       COUNT(*)                       AS segment_count,
       COALESCE(AVG(seg_err), 0)      AS avg_seg_err,
       COALESCE(SUM(n_samples), 0)    AS total_samples
FROM public.bus_congestion_history_segments
WHERE city = $1
  AND label <> '無資料'
  AND ($2 = '' OR route_name = $2)
GROUP BY snapshot_time, label
ORDER BY snapshot_time, label`

	sqlDB, err := DBDashboard.DB()
	if err != nil {
		return nil, err
	}
	rows, err := sqlDB.Query(sql, cityZH, routeName)
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
