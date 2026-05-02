package models

import (
	"strings"
)

// StationGeo is a YouBike station's name + coordinate, suitable for
// fuzzy "user said a place name → where on the map" lookups.
type StationGeo struct {
	Name string
	Lat  float64
	Lng  float64
}

// AreaAvailability is a per-area aggregate of YouBike availability
// at a given hour×quarter, used by the AI Action insight feature.
type AreaAvailability struct {
	StationCount     int
	AvgAvailability  float64 // 0.0 - 100.0
	AvgAvailable     float64 // average bikes available
	AvgTotalDocks    float64
}

// AvailabilityNearby aggregates YouBike availability over all
// snapshots whose station falls inside the [lat±dLat, lng±dLng]
// bounding box and whose Taipei-local time matches hour×quarter.
// Returns (zero, false) on missing DB / no rows.
func AvailabilityNearby(centerLat, centerLng, dLat, dLng float64, hour, quarter int) (AreaAvailability, bool) {
	if DBHackathon == nil {
		return AreaAvailability{}, false
	}
	const sql = `
SELECT
  COUNT(DISTINCT station_uid)                                               AS n_stations,
  COALESCE(AVG(available_bikes::float / NULLIF(total_docks, 0)) * 100, 0)   AS avg_pct,
  COALESCE(AVG(available_bikes), 0)                                         AS avg_available,
  COALESCE(AVG(total_docks), 0)                                             AS avg_total
FROM youbike_snapshots
WHERE lat BETWEEN $1 AND $2
  AND lon BETWEEN $3 AND $4
  AND EXTRACT(HOUR FROM snapshot_at AT TIME ZONE 'Asia/Taipei') = $5
  AND (EXTRACT(MINUTE FROM snapshot_at AT TIME ZONE 'Asia/Taipei')::int / 15) = $6
`
	sqlDB, err := DBHackathon.DB()
	if err != nil {
		return AreaAvailability{}, false
	}
	row := sqlDB.QueryRow(sql,
		centerLat-dLat, centerLat+dLat,
		centerLng-dLng, centerLng+dLng,
		hour, quarter,
	)
	var out AreaAvailability
	if err := row.Scan(&out.StationCount, &out.AvgAvailability, &out.AvgAvailable, &out.AvgTotalDocks); err != nil {
		return AreaAvailability{}, false
	}
	if out.StationCount == 0 {
		return AreaAvailability{}, false
	}
	return out, true
}

// ListStationsByNameLike returns up to `limit` distinct stations whose
// `station_name` contains the query (case-insensitive). Returns an empty
// slice (not error) if the hackathon DB handle is unavailable or the
// trimmed query is empty — callers treat that as "0 matches" and fall
// through to other tiers.
func ListStationsByNameLike(query string, limit int) ([]StationGeo, error) {
	q := strings.TrimSpace(query)
	if q == "" || DBHackathon == nil {
		return nil, nil
	}
	if limit <= 0 {
		limit = 5
	}

	// Escape LIKE meta chars so user input stays literal.
	q = strings.ReplaceAll(q, `\`, `\\`)
	q = strings.ReplaceAll(q, "%", `\%`)
	q = strings.ReplaceAll(q, "_", `\_`)
	pattern := "%" + q + "%"

	const sql = `
SELECT station_name AS name,
       AVG(lat) AS lat,
       AVG(lon) AS lng
FROM youbike_snapshots
WHERE station_name ILIKE $1 ESCAPE '\'
GROUP BY station_name
ORDER BY (CASE WHEN station_name = $2 THEN 0 ELSE 1 END), station_name
LIMIT $3`

	sqlDB, err := DBHackathon.DB()
	if err != nil {
		return nil, err
	}
	rows, err := sqlDB.Query(sql, pattern, q, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]StationGeo, 0, limit)
	for rows.Next() {
		var s StationGeo
		if err := rows.Scan(&s.Name, &s.Lat, &s.Lng); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
