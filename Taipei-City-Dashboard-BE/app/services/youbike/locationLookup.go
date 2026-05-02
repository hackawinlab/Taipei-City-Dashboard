// Package youbike provides domain-level helpers for the YouBike
// component AI Action prototype. The current scope is multi-tier
// place-name resolution that the controller calls after the LLM has
// extracted a free-text place query.
package youbike

import (
	"strings"

	"TaipeiCityDashboardBE/app/models"
)

// LocationIntent is the resolved focus_location payload for the
// YouBike time-map. Source records which tier produced the hit so
// the summary can hint at the data origin.
type LocationIntent struct {
	Place        string
	Center       []float64 // [lng, lat]
	Zoom         float64
	Pitch        float64
	Bearing      float64
	Source       string // "catalog" | "station"
	StationCount int    // tier-2 only: number of stations matched
}

type locationCatalogEntry struct {
	Key     string
	Aliases []string
	Intent  LocationIntent
}

// ResolveLocation tries (1) the hand-curated catalog, then (2) a
// case-insensitive YouBike station-name LIKE lookup against the
// hackathon DB. Returns (zero, false) when both miss or the query is
// empty. Caller is expected to have already filtered out
// non-metro-Taipei queries.
func ResolveLocation(query string) (LocationIntent, bool) {
	if strings.TrimSpace(query) == "" {
		return LocationIntent{}, false
	}

	if intent, ok := resolveFromCatalog(query); ok {
		return intent, true
	}
	if intent, ok := resolveFromStations(query); ok {
		return intent, true
	}
	return LocationIntent{}, false
}

// CatalogPlaces returns the canonical display names of every catalog
// entry (used to seed example chips when the resolver misses).
func CatalogPlaces() []string {
	entries := locationCatalog()
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Intent.Place)
	}
	return out
}

func resolveFromCatalog(query string) (LocationIntent, bool) {
	normalized := normalizePlaceText(query)
	if normalized == "" {
		return LocationIntent{}, false
	}
	for _, entry := range locationCatalog() {
		candidates := append([]string{entry.Key, entry.Intent.Place}, entry.Aliases...)
		for _, c := range candidates {
			n := normalizePlaceText(c)
			if n == "" {
				continue
			}
			if strings.Contains(normalized, n) || strings.Contains(n, normalized) {
				intent := entry.Intent
				intent.Source = "catalog"
				return intent, true
			}
		}
	}
	return LocationIntent{}, false
}

func resolveFromStations(query string) (LocationIntent, bool) {
	q := strings.TrimSpace(query)
	if q == "" {
		return LocationIntent{}, false
	}
	stations, err := models.ListStationsByNameLike(q, 5)
	if err != nil || len(stations) == 0 {
		return LocationIntent{}, false
	}

	// Prefer the station whose name matches most cleanly. ListStations
	// already orders exact-name first, so [0] is the best display name.
	primary := stations[0]
	var sumLat, sumLng float64
	for _, s := range stations {
		sumLat += s.Lat
		sumLng += s.Lng
	}
	n := float64(len(stations))
	center := []float64{sumLng / n, sumLat / n}

	zoom, pitch := 16.0, 45.0
	if len(stations) > 1 {
		zoom = 14.5
	}

	place := cleanStationName(primary.Name, q)
	if len(stations) > 1 {
		place = place + "周邊"
	}

	return LocationIntent{
		Place:        place,
		Center:       center,
		Zoom:         zoom,
		Pitch:        pitch,
		Bearing:      0,
		Source:       "station",
		StationCount: len(stations),
	}, true
}

// cleanStationName strips the "YouBike2.0_" prefix and the trailing
// "(出口)" / "(街)" detail when the user's query is shorter than the
// full station name — keeps the user-facing label tidy.
func cleanStationName(name string, query string) string {
	cleaned := strings.TrimPrefix(name, "YouBike2.0_")
	cleaned = strings.TrimPrefix(cleaned, "YouBike1.0_")
	if idx := strings.Index(cleaned, "("); idx > 0 {
		head := cleaned[:idx]
		// Keep parenthetical only if the user explicitly asked for it.
		if !strings.Contains(query, "(") && !strings.Contains(query, "（") {
			cleaned = head
		}
	}
	return strings.TrimSpace(cleaned)
}

// normalizePlaceText lowercases, replaces 臺→台, and strips whitespace.
func normalizePlaceText(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "臺", "台")
	value = strings.ReplaceAll(value, " ", "")
	return value
}

// locationCatalog is the curated tier-1 list. Each entry has a
// per-place zoom/pitch/bearing so the camera lands well-framed.
func locationCatalog() []locationCatalogEntry {
	return []locationCatalogEntry{
		{"gongguan", []string{"公館", "台大", "臺大", "台灣大學", "臺灣大學"}, LocationIntent{Place: "公館", Center: []float64{121.5339, 25.0143}, Zoom: 15.5, Pitch: 45, Bearing: 0}},
		{"taipei_main_station", []string{"台北車站", "臺北車站", "北車", "台北站"}, LocationIntent{Place: "台北車站", Center: []float64{121.5171, 25.0478}, Zoom: 15.5, Pitch: 45, Bearing: 0}},
		{"taipei_city_hall", []string{"市政府", "台北市政府", "臺北市政府", "信義區"}, LocationIntent{Place: "台北市政府", Center: []float64{121.5647, 25.0408}, Zoom: 15.5, Pitch: 45, Bearing: 0}},
		{"taipei_101", []string{"台北101", "臺北101", "101", "世貿"}, LocationIntent{Place: "台北101", Center: []float64{121.5654, 25.0337}, Zoom: 15.7, Pitch: 45, Bearing: 0}},
		{"east_district", []string{"東區", "忠孝復興", "忠孝敦化"}, LocationIntent{Place: "東區", Center: []float64{121.5568, 25.0387}, Zoom: 14.5, Pitch: 35, Bearing: 67}},
		{"daan", []string{"大安", "大安站", "大安森林公園"}, LocationIntent{Place: "大安", Center: []float64{121.5433, 25.0278}, Zoom: 15.3, Pitch: 45, Bearing: 0}},
		{"ximen", []string{"西門", "西門町", "西門站"}, LocationIntent{Place: "西門町", Center: []float64{121.5079, 25.0421}, Zoom: 15.5, Pitch: 45, Bearing: 0}},
		{"shilin", []string{"士林", "劍潭", "士林夜市"}, LocationIntent{Place: "士林", Center: []float64{121.5250, 25.0850}, Zoom: 15.2, Pitch: 45, Bearing: 0}},
		{"dadaocheng", []string{"大稻埕", "迪化街"}, LocationIntent{Place: "大稻埕", Center: []float64{121.5101, 25.0558}, Zoom: 16, Pitch: 50, Bearing: 60}},
		{"expo_park", []string{"花博", "花博公園", "圓山"}, LocationIntent{Place: "花博公園", Center: []float64{121.5229, 25.0685}, Zoom: 15.75, Pitch: 60, Bearing: 130}},
		{"yangmingshan", []string{"陽明山"}, LocationIntent{Place: "陽明山", Center: []float64{121.5518, 25.1290}, Zoom: 13.25, Pitch: 60, Bearing: 0}},
		{"nangang", []string{"南港", "南港車站"}, LocationIntent{Place: "南港車站", Center: []float64{121.6070, 25.0521}, Zoom: 15.3, Pitch: 45, Bearing: 0}},
		{"neihu", []string{"內湖", "西湖", "內科", "內湖科技園區"}, LocationIntent{Place: "內湖", Center: []float64{121.5677, 25.0820}, Zoom: 14.6, Pitch: 45, Bearing: 0}},
		{"banqiao", []string{"板橋", "板橋車站", "新北市政府"}, LocationIntent{Place: "板橋", Center: []float64{121.4648, 25.0140}, Zoom: 15.2, Pitch: 45, Bearing: 0}},
		{"xinzhuang", []string{"新莊", "新莊站"}, LocationIntent{Place: "新莊", Center: []float64{121.4523, 25.0360}, Zoom: 14.8, Pitch: 45, Bearing: 0}},
		{"sanchong", []string{"三重", "三重站"}, LocationIntent{Place: "三重", Center: []float64{121.4881, 25.0615}, Zoom: 14.8, Pitch: 45, Bearing: 0}},
		{"yonghe", []string{"永和", "頂溪"}, LocationIntent{Place: "永和", Center: []float64{121.5155, 25.0137}, Zoom: 15.0, Pitch: 45, Bearing: 0}},
		{"zhonghe", []string{"中和", "景安"}, LocationIntent{Place: "中和", Center: []float64{121.5051, 24.9930}, Zoom: 14.8, Pitch: 45, Bearing: 0}},
		{"xindian", []string{"新店", "七張", "新店區公所"}, LocationIntent{Place: "新店", Center: []float64{121.5418, 24.9675}, Zoom: 14.8, Pitch: 45, Bearing: 0}},
		{"tamsui", []string{"淡水", "淡水站"}, LocationIntent{Place: "淡水", Center: []float64{121.4452, 25.1677}, Zoom: 14.2, Pitch: 45, Bearing: 0}},
	}
}
