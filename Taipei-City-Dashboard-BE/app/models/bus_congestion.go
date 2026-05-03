package models

import (
	"encoding/json"
	"time"

	"gorm.io/gorm"
)

// BusCongestionSegment is a row in bus_congestion_segments (dashboard DB).
// route_id / route_uid / route_name / sub_route_* columns are populated only
// by the demo dump (test-update-bus/bus_congestion_dump.sql); the live BE
// pipeline leaves them NULL.
type BusCongestionSegment struct {
	ID        int       `gorm:"column:id;primaryKey;autoIncrement"`
	SegID     string    `gorm:"column:seg_id;not null"`
	FromName  string    `gorm:"column:from_name"`
	ToName    string    `gorm:"column:to_name"`
	Direction string    `gorm:"column:direction"`
	City      string    `gorm:"column:city"`
	SegErr    float64   `gorm:"column:seg_err"`
	Color     string    `gorm:"column:color"`
	Label     string    `gorm:"column:label"`
	HasDelta  bool      `gorm:"column:has_delta;default:false"`
	NSamples  int       `gorm:"column:n_samples;default:0"`
	UpdatedAt time.Time `gorm:"column:updated_at;autoUpdateTime"`
}

// TableName returns the database table name for BusCongestionSegment
func (BusCongestionSegment) TableName() string {
	return "bus_congestion_segments"
}

// UpsertBusCongestionSegments truncates and re-inserts all segments.
// fc is the bus_congestion service's GeoJSONCollection — passed as interface{}
// to avoid an import cycle.
func UpsertBusCongestionSegments(fc interface{}) error {
	data, err := json.Marshal(fc)
	if err != nil {
		return err
	}

	var geojson struct {
		Features []struct {
			Properties struct {
				SegID     string  `json:"seg_id"`
				FromName  string  `json:"from_name"`
				ToName    string  `json:"to_name"`
				Direction string  `json:"direction"`
				City      string  `json:"city"`
				SegErr    float64 `json:"seg_err"`
				Color     string  `json:"color"`
				Label     string  `json:"label"`
				HasDelta  bool    `json:"has_delta"`
				NSamples  int     `json:"n_samples"`
			} `json:"properties"`
		} `json:"features"`
	}
	if err := json.Unmarshal(data, &geojson); err != nil {
		return err
	}

	segs := make([]BusCongestionSegment, 0, len(geojson.Features))
	for _, f := range geojson.Features {
		p := f.Properties
		segs = append(segs, BusCongestionSegment{
			SegID:     p.SegID,
			FromName:  p.FromName,
			ToName:    p.ToName,
			Direction: p.Direction,
			City:      p.City,
			SegErr:    p.SegErr,
			Color:     p.Color,
			Label:     p.Label,
			HasDelta:  p.HasDelta,
			NSamples:  p.NSamples,
		})
	}

	return DBDashboard.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("TRUNCATE bus_congestion_segments").Error; err != nil {
			return err
		}
		if len(segs) == 0 {
			return nil
		}
		return tx.CreateInBatches(segs, 1000).Error
	})
}
