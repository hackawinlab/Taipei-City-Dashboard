package bus_congestion

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"
)

func errorToColor(errSecs float64) string {
	switch {
	case errSecs <= 0:
		return "#2ecc71"
	case errSecs <= 30:
		return "#f1c40f"
	case errSecs <= 60:
		return "#e67e22"
	case errSecs <= 120:
		return "#e74c3c"
	default:
		return "#8e1010"
	}
}

func errorToLabel(errSecs float64) string {
	switch {
	case errSecs <= 0:
		return "暢通(≤0s)"
	case errSecs <= 30:
		return "輕微(+1~30s)"
	case errSecs <= 60:
		return "中度(+31~60s)"
	case errSecs <= 120:
		return "嚴重(+61~120s)"
	default:
		return "極嚴重(>120s)"
	}
}

// haversineKm returns approximate distance in km between two lat/lon points
func haversineKm(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371.0
	dlat := (lat2 - lat1) * math.Pi / 180
	dlon := (lon2 - lon1) * math.Pi / 180
	a := math.Sin(dlat/2)*math.Sin(dlat/2) +
		math.Cos(lat1*math.Pi/180)*math.Cos(lat2*math.Pi/180)*
			math.Sin(dlon/2)*math.Sin(dlon/2)
	return R * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}

// GeoJSONFeature represents a single GeoJSON feature
type GeoJSONFeature struct {
	Type       string                 `json:"type"`
	Geometry   map[string]interface{} `json:"geometry"`
	Properties map[string]interface{} `json:"properties"`
}

// GeoJSONCollection represents a GeoJSON FeatureCollection
type GeoJSONCollection struct {
	Type     string           `json:"type"`
	Features []GeoJSONFeature `json:"features"`
}

// BuildAbsGeoJSON builds the absolute error GeoJSON (one segment per stop, connecting to next)
func BuildAbsGeoJSON(
	stopEWMA map[string]float64,
	stops map[string]StopInfo,
	city string,
	cityLabel string,
) GeoJSONCollection {
	var features []GeoJSONFeature

	// Group stops by route+direction, sort by seq, draw stop-to-stop segments
	type routeDir struct{ RouteUID, GoBack string }
	byRoute := make(map[routeDir][]StopInfo)
	for _, s := range stops {
		if s.City != city {
			continue
		}
		k := routeDir{s.RouteUID, "0"} // simplified: use all stops
		byRoute[k] = append(byRoute[k], s)
	}

	for _, stopList := range byRoute {
		// Sort by seq
		sortedStops := make([]StopInfo, len(stopList))
		copy(sortedStops, stopList)
		sort.Slice(sortedStops, func(i, j int) bool {
			return sortedStops[i].Seq < sortedStops[j].Seq
		})

		for i := 0; i < len(sortedStops)-1; i++ {
			a, b := sortedStops[i], sortedStops[i+1]
			if a.Lat == 0 || b.Lat == 0 {
				continue
			}
			if haversineKm(a.Lat, a.Lon, b.Lat, b.Lon) > maxSegKm {
				continue
			}

			key := a.StopID + ":0"
			errSecs, hasData := stopEWMA[key]
			color := "#bbbbbb"
			label := "無資料"
			if hasData {
				color = errorToColor(errSecs)
				label = errorToLabel(errSecs)
			}

			features = append(features, GeoJSONFeature{
				Type: "Feature",
				Geometry: map[string]interface{}{
					"type":        "LineString",
					"coordinates": [][]float64{{a.Lon, a.Lat}, {b.Lon, b.Lat}},
				},
				Properties: map[string]interface{}{
					"stop_id":   a.StopID,
					"stop_name": a.Name,
					"direction": "0",
					"error_s":   errSecs,
					"color":     color,
					"label":     label,
					"n_samples": 1,
					"city":      cityLabel,
				},
			})
		}
	}
	return GeoJSONCollection{Type: "FeatureCollection", Features: features}
}

// BuildDeltaGeoJSON builds the segment delta error GeoJSON
func BuildDeltaGeoJSON(
	deltas map[SegmentKey][]float64,
	meta map[SegmentKey]SegmentMeta,
	stopEWMA map[string]float64,
	stops map[string]StopInfo,
	cityLabel string,
) GeoJSONCollection {
	var features []GeoJSONFeature

	for k, dList := range deltas {
		m, ok := meta[k]
		if !ok {
			continue
		}
		stopA, okA := stops[k.SidA]
		stopB, okB := stops[k.SidB]
		if !okA || !okB {
			continue
		}
		if stopA.Lat == 0 || stopB.Lat == 0 {
			continue
		}
		if haversineKm(stopA.Lat, stopA.Lon, stopB.Lat, stopB.Lon) > maxSegKm {
			continue
		}

		// Mean delta
		sum := 0.0
		for _, d := range dList {
			sum += d
		}
		mean := 0.0
		hasD := true
		if len(dList) > 0 {
			mean = sum / float64(len(dList))
		} else {
			hasD = false
			ewmaKey := k.SidA + ":" + k.GoBack
			if v, ok2 := stopEWMA[ewmaKey]; ok2 {
				mean = v
			}
		}

		color := errorToColor(mean)
		label := errorToLabel(mean)

		features = append(features, GeoJSONFeature{
			Type: "Feature",
			Geometry: map[string]interface{}{
				"type":        "LineString",
				"coordinates": [][]float64{{stopA.Lon, stopA.Lat}, {stopB.Lon, stopB.Lat}},
			},
			Properties: map[string]interface{}{
				"seg_id":    fmt.Sprintf("%s:%s:%s", k.GoBack, k.SidA, k.SidB),
				"from_name": m.NameA,
				"to_name":   m.NameB,
				"direction": k.GoBack,
				"seg_err":   mean,
				"color":     color,
				"label":     label,
				"has_delta": hasD,
				"n_samples": len(dList),
				"city":      cityLabel,
			},
		})
	}
	return GeoJSONCollection{Type: "FeatureCollection", Features: features}
}

// MarshalGeoJSON serializes a GeoJSONCollection to JSON bytes
func MarshalGeoJSON(fc GeoJSONCollection) ([]byte, error) {
	return json.Marshal(fc)
}
