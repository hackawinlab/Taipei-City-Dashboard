package bus_congestion

import (
	"TaipeiCityDashboardBE/logs"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const (
	taipeiEtaURL      = "https://tcgbusfs.blob.core.windows.net/blobbus/GetEstimateTime.gz"
	newTaipeiEtaURL   = "https://tdx.transportdata.tw/api/basic/v2/Bus/EstimatedTimeOfArrival/City/NewTaipei?$format=JSON"
	taipeiStopsURL    = "https://tdx.transportdata.tw/api/basic/v2/Bus/Stop/City/Taipei?$format=JSON&$top=10000"
	newTaipeiStopsURL = "https://tdx.transportdata.tw/api/basic/v2/Bus/Stop/City/NewTaipei?$format=JSON&$top=10000"
)

// FetchTaipeiETA fetches all Taipei bus ETA from the blob
func FetchTaipeiETA() ([]ETARecord, error) {
	req, _ := http.NewRequest("GET", taipeiEtaURL, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	gr, err := gzip.NewReader(resp.Body)
	if err != nil {
		return nil, err
	}
	defer gr.Close()
	body, _ := io.ReadAll(gr)

	var data struct {
		BusInfo []struct {
			StopID       string `json:"StopID"`
			RouteID      string `json:"RouteID"`
			GoBack       string `json:"GoBack"`
			EstimateTime string `json:"EstimateTime"`
		} `json:"BusInfo"`
	}
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, err
	}

	now := time.Now()
	var records []ETARecord
	for _, e := range data.BusInfo {
		var eta int
		if _, err := fmt.Sscanf(e.EstimateTime, "%d", &eta); err != nil || eta < 0 {
			continue
		}
		if e.StopID == "" {
			continue
		}
		records = append(records, ETARecord{
			Timestamp: now,
			StopID:    e.StopID,
			RouteUID:  e.RouteID,
			GoBack:    e.GoBack,
			ETASecs:   eta,
			City:      "taipei",
		})
	}
	return records, nil
}

// FetchNewTaipeiETA fetches all New Taipei bus ETA from TDX
func FetchNewTaipeiETA() ([]ETARecord, error) {
	token, err := getTDXToken()
	if err != nil {
		return nil, err
	}

	req, _ := http.NewRequest("GET", newTaipeiEtaURL, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept-Encoding", "gzip")
	req.Header.Set("User-Agent", "Mozilla/5.0")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var bodyReader io.Reader = resp.Body
	if resp.Header.Get("Content-Encoding") == "gzip" {
		gr, _ := gzip.NewReader(resp.Body)
		defer gr.Close()
		bodyReader = gr
	}
	body, _ := io.ReadAll(bodyReader)

	var data []struct {
		StopID       string `json:"StopID"`
		RouteUID     string `json:"RouteUID"`
		Direction    int    `json:"Direction"`
		EstimateTime *int   `json:"EstimateTime"`
	}
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, err
	}

	now := time.Now()
	var records []ETARecord
	for _, e := range data {
		if e.EstimateTime == nil || *e.EstimateTime < 0 {
			continue
		}
		if e.StopID == "" {
			continue
		}
		records = append(records, ETARecord{
			Timestamp: now,
			StopID:    e.StopID,
			RouteUID:  e.RouteUID,
			GoBack:    fmt.Sprintf("%d", e.Direction),
			ETASecs:   *e.EstimateTime,
			City:      "newtaipei",
		})
	}
	return records, nil
}

// FetchStops fetches stop metadata (lat/lon/name/seq) for a city via TDX
func FetchStops(city string) (map[string]StopInfo, error) {
	stopsURL := taipeiStopsURL
	if city == "newtaipei" {
		stopsURL = newTaipeiStopsURL
	}

	token, err := getTDXToken()
	if err != nil {
		return nil, err
	}

	req, _ := http.NewRequest("GET", stopsURL, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Accept-Encoding", "gzip")
	req.Header.Set("User-Agent", "Mozilla/5.0")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var bodyReader io.Reader = resp.Body
	if resp.Header.Get("Content-Encoding") == "gzip" {
		gr, _ := gzip.NewReader(resp.Body)
		defer gr.Close()
		bodyReader = gr
	}
	body, _ := io.ReadAll(bodyReader)

	var data []struct {
		StopID   string `json:"StopID"`
		StopName struct {
			ZhTw string `json:"Zh_tw"`
		} `json:"StopName"`
		StopSequence int    `json:"StopSequence"`
		RouteUID     string `json:"RouteUID"`
		StopPosition struct {
			PositionLat float64 `json:"PositionLat"`
			PositionLon float64 `json:"PositionLon"`
		} `json:"StopPosition"`
	}
	if err := json.Unmarshal(body, &data); err != nil {
		return nil, fmt.Errorf("parse stops for %s: %w", city, err)
	}

	stops := make(map[string]StopInfo, len(data))
	for _, s := range data {
		stops[s.StopID] = StopInfo{
			StopID:   s.StopID,
			Name:     s.StopName.ZhTw,
			Lat:      s.StopPosition.PositionLat,
			Lon:      s.StopPosition.PositionLon,
			Seq:      s.StopSequence,
			RouteUID: s.RouteUID,
			City:     city,
		}
	}
	logs.FInfo("[bus_congestion] loaded %d stops for %s", len(stops), city)
	return stops, nil
}
