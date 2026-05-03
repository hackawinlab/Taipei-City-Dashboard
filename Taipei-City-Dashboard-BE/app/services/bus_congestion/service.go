package bus_congestion

import (
	"TaipeiCityDashboardBE/app/models"
	"TaipeiCityDashboardBE/global"
	"TaipeiCityDashboardBE/logs"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// BusCongestionService manages the bus congestion pipeline
type BusCongestionService struct {
	mu      sync.RWMutex
	records []ETARecord // rolling window

	stopsMu sync.RWMutex
	stops   map[string]StopInfo // StopID -> StopInfo
}

// Service is the shared singleton
var Service = &BusCongestionService{
	stops: make(map[string]StopInfo),
}

// Init loads stop data for both cities. Call once on startup.
func (s *BusCongestionService) Init(ctx context.Context) {
	logs.Info("[bus_congestion] loading stop metadata...")
	for _, city := range []string{"taipei", "newtaipei"} {
		cityStops, err := FetchStops(city)
		if err != nil {
			logs.FError("[bus_congestion] failed to load stops for %s: %v", city, err)
			continue
		}
		s.stopsMu.Lock()
		for k, v := range cityStops {
			s.stops[k] = v
		}
		s.stopsMu.Unlock()
	}
	logs.FInfo("[bus_congestion] loaded %d total stops", len(s.stops))
}

// Poll fetches one round of ETA data and adds to rolling window
func (s *BusCongestionService) Poll(ctx context.Context) {
	threshold := time.Now().Add(-windowHours * time.Hour)
	var newRecords []ETARecord

	// Taipei
	if records, err := FetchTaipeiETA(); err != nil {
		logs.FError("[bus_congestion] taipei ETA fetch failed: %v", err)
	} else {
		newRecords = append(newRecords, records...)
		logs.FInfo("[bus_congestion] taipei: %d ETA records", len(records))
	}

	// New Taipei
	if global.TDXClientID != "" {
		if records, err := FetchNewTaipeiETA(); err != nil {
			logs.FError("[bus_congestion] newtaipei ETA fetch failed: %v", err)
		} else {
			newRecords = append(newRecords, records...)
			logs.FInfo("[bus_congestion] newtaipei: %d ETA records", len(records))
		}
	}

	s.mu.Lock()
	// Append new records
	s.records = append(s.records, newRecords...)
	// Expire old records
	valid := s.records[:0]
	for _, r := range s.records {
		if r.Timestamp.After(threshold) {
			valid = append(valid, r)
		}
	}
	s.records = valid
	s.mu.Unlock()
}

// RefreshMap analyzes recent ETA data and writes GeoJSON + DB
func (s *BusCongestionService) RefreshMap(ctx context.Context) {
	s.mu.RLock()
	snapshot := make([]ETARecord, len(s.records))
	copy(snapshot, s.records)
	s.mu.RUnlock()

	s.stopsMu.RLock()
	stops := make(map[string]StopInfo, len(s.stops))
	for k, v := range s.stops {
		stops[k] = v
	}
	s.stopsMu.RUnlock()

	if len(snapshot) == 0 {
		logs.Info("[bus_congestion] no ETA data yet, skipping refresh")
		return
	}

	// Group by (StopID, GoBack, City)
	type key struct{ StopID, GoBack, City string }
	groups := make(map[key][]ETARecord)
	for _, r := range snapshot {
		k := key{r.StopID, r.GoBack, r.City}
		groups[k] = append(groups[k], r)
	}
	// Sort each group by timestamp
	for k := range groups {
		recs := groups[k]
		sort.Slice(recs, func(i, j int) bool {
			return recs[i].Timestamp.Before(recs[j].Timestamp)
		})
		groups[k] = recs
	}

	// Detect arrival events for all stops
	var allEvents []ArrivalEvent
	for _, pts := range groups {
		evs := analyzeStop(pts)
		allEvents = append(allEvents, evs...)
	}
	logs.FInfo("[bus_congestion] %d arrival events detected from %d records", len(allEvents), len(snapshot))

	if len(allEvents) == 0 {
		logs.Info("[bus_congestion] no arrival events yet, skipping GeoJSON write")
		return
	}

	// Compute stop EWMA errors and segment deltas
	stopEWMA := ComputeStopErrors(allEvents)
	deltas, meta := ComputeSegmentDeltas(allEvents, stops)

	// Build GeoJSON for both cities
	var absFeats, deltaFeats []GeoJSONFeature
	for _, city := range []struct{ key, label string }{{"taipei", "台北市"}, {"newtaipei", "新北市"}} {
		abs := BuildAbsGeoJSON(stopEWMA, stops, city.key, city.label)
		delta := BuildDeltaGeoJSON(deltas, meta, stopEWMA, stops, city.label)
		absFeats = append(absFeats, abs.Features...)
		deltaFeats = append(deltaFeats, delta.Features...)
	}

	absGJ := GeoJSONCollection{Type: "FeatureCollection", Features: absFeats}
	deltaGJ := GeoJSONCollection{Type: "FeatureCollection", Features: deltaFeats}

	logs.FInfo("[bus_congestion] GeoJSON: abs=%d features, delta=%d features",
		len(absFeats), len(deltaFeats))

	// Write GeoJSON files
	if fePublic := global.BusFEPublicDir; fePublic != "" {
		mapDataDir := filepath.Join(fePublic, "mapData")
		if err := os.MkdirAll(mapDataDir, 0755); err != nil {
			logs.FError("[bus_congestion] mkdir %s failed: %v", mapDataDir, err)
		} else {
			writeGJ := func(name string, gj GeoJSONCollection) {
				path := filepath.Join(mapDataDir, name)
				data, err := json.Marshal(gj)
				if err != nil {
					logs.FError("[bus_congestion] marshal %s failed: %v", name, err)
					return
				}
				if err := os.WriteFile(path, data, 0644); err != nil {
					logs.FError("[bus_congestion] write %s failed: %v", path, err)
					return
				}
				logs.FInfo("[bus_congestion] wrote %s (%d bytes)", path, len(data))
			}
			writeGJ("bus_congestion_abs.geojson", absGJ)
			writeGJ("bus_congestion_delta.geojson", deltaGJ)
		}
	}

	// Write to DB
	if err := models.UpsertBusCongestionSegments(deltaGJ); err != nil {
		logs.FError("[bus_congestion] DB write failed: %v", err)
	} else {
		logs.FInfo("[bus_congestion] DB updated with %d segments", len(deltaFeats))
	}
}

// RefreshStops re-fetches stop metadata (call daily)
func (s *BusCongestionService) RefreshStops(ctx context.Context) {
	s.Init(ctx)
}
