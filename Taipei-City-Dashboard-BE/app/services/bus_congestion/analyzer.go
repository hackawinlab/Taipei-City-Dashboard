package bus_congestion

import (
	"math"
	"sort"
	"time"
)

// analyzeStop detects clean arrival events for one stop's ETA time series.
// pts must be sorted by Timestamp ascending.
func analyzeStop(pts []ETARecord) []ArrivalEvent {
	var results []ArrivalEvent
	if len(pts) < 2 {
		return results
	}

	busStartIdx := 0
	cleanPolls := 0
	dirty := false

	for i := 1; i < len(pts); i++ {
		prev := pts[i-1]
		t := classifyTransition(prev.ETASecs, pts[i].ETASecs)

		switch t {
		case "arrival":
			if !dirty && cleanPolls >= minCleanPolls {
				// Collect predicted arrival times for median
				predTimes := make([]float64, 0, i-busStartIdx)
				for j := busStartIdx; j < i; j++ {
					predTimes = append(predTimes, float64(pts[j].Timestamp.Unix())+float64(pts[j].ETASecs))
				}
				sort.Float64s(predTimes)
				predicted := predTimes[len(predTimes)/2]
				actual := float64(prev.Timestamp.Unix()) + float64(prev.ETASecs)
				results = append(results, ArrivalEvent{
					SID:          prev.StopID,
					GoBack:       prev.GoBack,
					RouteUID:     pts[busStartIdx].RouteUID,
					ErrorSecs:    actual - predicted,
					BusStartTime: pts[busStartIdx].Timestamp,
				})
			}
			busStartIdx = i
			cleanPolls = 0
			dirty = false

		case "swap":
			busStartIdx = i
			cleanPolls = 0
			dirty = false

		case "freeze":
			dirty = true

		case "normal":
			cleanPolls++
		}
	}
	return results
}

func classifyTransition(prevETA, curETA int) string {
	delta := curETA - prevETA
	if delta == 0 {
		return "freeze"
	}
	if delta > 0 {
		if prevETA < arrLow && curETA > arrHigh {
			return "arrival"
		}
		if prevETA > minETAForSwap && float64(delta)/float64(prevETA) > swapRiseRatio {
			return "swap"
		}
		return "normal"
	}
	if -delta > swapDropS {
		return "swap"
	}
	return "normal"
}

// ComputeStopErrors groups arrival events by (StopID, GoBack) and returns
// the EWMA error for each stop.
func ComputeStopErrors(events []ArrivalEvent) map[string]float64 {
	// key: "StopID:GoBack"
	stopErrs := make(map[string][]float64)
	for _, ev := range events {
		key := ev.SID + ":" + ev.GoBack
		stopErrs[key] = append(stopErrs[key], ev.ErrorSecs)
	}
	ewma := make(map[string]float64)
	for key, errs := range stopErrs {
		// EWMA over the slice (treat as time series in order)
		v := errs[0]
		for _, e := range errs[1:] {
			v = ewmaAlpha*e + (1-ewmaAlpha)*v
		}
		ewma[key] = v
	}
	return ewma
}

// ComputeSegmentDeltas computes per-segment Δerror from arrival events,
// using stop metadata for sequence info.
func ComputeSegmentDeltas(
	events []ArrivalEvent,
	stops map[string]StopInfo,
) (map[SegmentKey][]float64, map[SegmentKey]SegmentMeta) {
	type tripKey struct {
		GoBack   string
		RouteUID string
		BusStart time.Time
	}
	trips := make(map[tripKey][]ArrivalEvent)
	for _, ev := range events {
		k := tripKey{ev.GoBack, ev.RouteUID, ev.BusStartTime}
		trips[k] = append(trips[k], ev)
	}

	deltas := make(map[SegmentKey][]float64)
	meta := make(map[SegmentKey]SegmentMeta)

	for _, evs := range trips {
		if len(evs) < 2 {
			continue
		}
		// Dedupe by seq (keep smallest absolute error)
		bySeq := make(map[int]ArrivalEvent)
		for _, ev := range evs {
			info, ok := stops[ev.SID]
			if !ok {
				continue
			}
			ev.Seq = info.Seq
			ev.Name = info.Name
			existing, found := bySeq[info.Seq]
			if !found || math.Abs(ev.ErrorSecs) < math.Abs(existing.ErrorSecs) {
				bySeq[info.Seq] = ev
			}
		}
		// Sort by seq
		ordered := make([]ArrivalEvent, 0, len(bySeq))
		for _, ev := range bySeq {
			ordered = append(ordered, ev)
		}
		sort.Slice(ordered, func(i, j int) bool { return ordered[i].Seq < ordered[j].Seq })

		for i := 0; i < len(ordered)-1; i++ {
			a, b := ordered[i], ordered[i+1]
			gap := b.Seq - a.Seq
			if gap <= 0 || gap > maxSeqGap {
				continue
			}
			k := SegmentKey{GoBack: a.GoBack, SidA: a.SID, SidB: b.SID}
			deltas[k] = append(deltas[k], b.ErrorSecs-a.ErrorSecs)
			if _, exists := meta[k]; !exists {
				meta[k] = SegmentMeta{
					GoBack: a.GoBack,
					SeqA:   a.Seq, SeqB: b.Seq,
					NameA: a.Name, NameB: b.Name,
					SidA: a.SID, SidB: b.SID,
				}
			}
		}
	}
	return deltas, meta
}
