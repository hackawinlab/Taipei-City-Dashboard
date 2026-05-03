package bus_congestion

import "time"

const (
	ewmaAlpha     = 0.35
	swapDropS     = 135
	swapRiseRatio = 0.5
	minETAForSwap = 30
	arrLow        = 120
	arrHigh       = 200
	minCleanPolls = 2
	maxSeqGap     = 6
	windowHours   = 3
	maxSegKm      = 2.0
)

// ETARecord is one row of ETA snapshot data
type ETARecord struct {
	Timestamp time.Time
	StopID    string
	RouteUID  string // RouteUID or RouteID (numeric string for Taipei)
	GoBack    string
	ETASecs   int
	City      string
}

// StopInfo holds stop metadata
type StopInfo struct {
	StopID   string
	Name     string
	Lat      float64
	Lon      float64
	Seq      int
	RouteUID string
	City     string
}

// ArrivalEvent records one detected bus arrival
type ArrivalEvent struct {
	SID          string
	GoBack       string
	RouteUID     string
	ErrorSecs    float64
	BusStartTime time.Time
	Seq          int
	Name         string
}

// SegmentKey identifies a route segment
type SegmentKey struct {
	GoBack string
	SidA   string
	SidB   string
}

// SegmentMeta holds segment metadata
type SegmentMeta struct {
	GoBack string
	SeqA   int
	SeqB   int
	NameA  string
	NameB  string
	SidA   string
	SidB   string
}
