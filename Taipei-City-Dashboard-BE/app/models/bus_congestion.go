package models

import (
	"encoding/json"
	"time"

	"gorm.io/gorm"
)

// BusCongestionSegment is a row in bus_congestion_segments (dashboard DB)
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
	GeoJSON   string    `gorm:"column:geojson"`
	UpdatedAt time.Time `gorm:"column:updated_at;autoUpdateTime"`
}

// TableName returns the database table name for BusCongestionSegment
func (BusCongestionSegment) TableName() string {
	return "bus_congestion_segments"
}

// UpsertBusCongestionSegments truncates and re-inserts all segments
func UpsertBusCongestionSegments(fc interface{}) error {
	// fc is a GeoJSONCollection — use raw JSON marshaling to avoid import cycle
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

	return DBDashboard.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("TRUNCATE bus_congestion_segments").Error; err != nil {
			return err
		}
		for i, f := range geojson.Features {
			p := f.Properties
			featJSON, _ := json.Marshal(geojson.Features[i])
			seg := BusCongestionSegment{
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
				GeoJSON:   string(featJSON),
			}
			if err := tx.Create(&seg).Error; err != nil {
				return err
			}
		}
		return nil
	})
}
