// Package youbike_aggregate computes the YouBike shortage analysis payload
// from the hackathon-DB youbike_snapshots table. It is consumed by
// controllers/commute.GetYouBikePersistenceChart and
// controllers/commute.GetYouBikeImbalanceChart via getYouBikeAggregatePayload.
// load-ubike-data.sh seeds the table once; the dashboard fetches API endpoints
// from then on.
//
// Logic is a stdlib-only Go port of the original
// data/aggregate_youbike_hourly.py. Four blocks are computed
// (timeline_low, bar_persistence, heatmap, imbalance); the frontend currently
// reads bar_persistence and imbalance only.
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
	topNPersistence   = 25
	topNImbalance     = 15
)

// taipeiLoc localises every snapshot_at the moment we read it from
// youbike_snapshots (TIMESTAMPTZ → Go time defaults to UTC). Hour bucketing
// must land on the Taipei wall clock to match commute.go's
// `AT TIME ZONE 'Asia/Taipei'` SQL convention.
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

// Payload is the aggregator output read by controllers/commute.go's
// GetYouBikePersistenceChart and GetYouBikeImbalanceChart.
type Payload struct {
	BarPersistence map[string][]PersistenceEntry        `json:"bar_persistence"`
	Imbalance      map[string]map[string][]ImbalanceRow `json:"imbalance"`
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

// BuildPayload runs the aggregation pipeline against an in-memory slice of
// snapshots and returns the persistence + imbalance blocks the dashboard reads.
func BuildPayload(snapshots []Snapshot) Payload {
	cities := []string{"All", "Taipei", "NewTaipei"}
	byStation := aggregateByStation(snapshots)

	return Payload{
		BarPersistence: buildBarPersistence(byStation, cities),
		Imbalance:      computeImbalance(snapshots, cities),
	}
}
