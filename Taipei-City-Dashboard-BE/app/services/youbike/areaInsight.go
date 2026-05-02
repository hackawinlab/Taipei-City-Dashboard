package youbike

import (
	"fmt"
	"math"

	"TaipeiCityDashboardBE/app/models"
)

// AreaInsight is a human-readable summary of "好借 vs 不好借" at a
// specific (location, time) for the YouBike component AI panel.
type AreaInsight struct {
	StationCount       int     `json:"station_count"`
	AvgAvailabilityPct float64 `json:"avg_availability_pct"`
	AvgAvailable       float64 `json:"avg_available"`
	AvgTotalDocks      float64 `json:"avg_total_docks"`
	RadiusMeters       int     `json:"radius_meters"`
	Verdict            string  `json:"verdict"` // "easy" | "balanced" | "tight"
	Phrasing           string  `json:"phrasing"`
}

// SummarizeArea aggregates availability around a center point at a
// given hour×quarter. Tries 500m first, expands to 1500m if no stations
// land in the tight box. Returns (zero, false) when DB has nothing
// nearby for the requested time slot.
func SummarizeArea(centerLng, centerLat float64, hour, quarter int) (AreaInsight, bool) {
	if hour < 0 || hour > 23 || quarter < 0 || quarter > 3 {
		return AreaInsight{}, false
	}

	for _, radius := range []int{300, 1000} {
		dLat := metersToLatDelta(float64(radius))
		dLng := metersToLngDelta(float64(radius), centerLat)
		stats, ok := models.AvailabilityNearby(centerLat, centerLng, dLat, dLng, hour, quarter)
		if !ok {
			continue
		}
		insight := AreaInsight{
			StationCount:       stats.StationCount,
			AvgAvailabilityPct: round1(stats.AvgAvailability),
			AvgAvailable:       round1(stats.AvgAvailable),
			AvgTotalDocks:      round1(stats.AvgTotalDocks),
			RadiusMeters:       radius,
		}
		insight.Verdict, insight.Phrasing = verdictFor(insight, hour, quarter)
		return insight, true
	}
	return AreaInsight{}, false
}

func verdictFor(a AreaInsight, hour, quarter int) (string, string) {
	timeLabel := fmt.Sprintf("%02d:%02d", hour, quarter*15)
	switch {
	case a.AvgAvailabilityPct >= 50:
		return "easy", fmt.Sprintf(
			"%s 這附近 %d 站平均有 %.0f 輛車可借（可用率 %.0f%%），算好借。",
			timeLabel, a.StationCount, a.AvgAvailable, a.AvgAvailabilityPct,
		)
	case a.AvgAvailabilityPct >= 25:
		return "balanced", fmt.Sprintf(
			"%s 這附近 %d 站平均約 %.0f 輛車（可用率 %.0f%%），借車要碰運氣。",
			timeLabel, a.StationCount, a.AvgAvailable, a.AvgAvailabilityPct,
		)
	default:
		return "tight", fmt.Sprintf(
			"%s 這附近 %d 站平均只有 %.0f 輛車（可用率 %.0f%%），不太好借，建議改時段或地點。",
			timeLabel, a.StationCount, a.AvgAvailable, a.AvgAvailabilityPct,
		)
	}
}

const earthMetersPerDegLat = 111_000.0

func metersToLatDelta(meters float64) float64 {
	return meters / earthMetersPerDegLat
}

func metersToLngDelta(meters, lat float64) float64 {
	cosLat := math.Cos(lat * math.Pi / 180)
	if cosLat < 0.01 {
		cosLat = 0.01
	}
	return meters / (earthMetersPerDegLat * cosLat)
}

func round1(v float64) float64 {
	return math.Round(v*10) / 10
}
