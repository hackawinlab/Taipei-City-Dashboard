package controllers

import (
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

const componentAIActionSchemaVersion = "component_ai_action.v1"

type ComponentAIActionRequest struct {
	SessionID      string                 `json:"session_id"`
	ComponentID    string                 `json:"component_id" binding:"required"`
	UserMessage    string                 `json:"user_message"`
	QuickAction    string                 `json:"quick_action"`
	ComponentState map[string]interface{} `json:"component_state"`
}

type ComponentAIUIEvent struct {
	ComponentID string                 `json:"component_id"`
	Action      string                 `json:"action"`
	Payload     map[string]interface{} `json:"payload"`
}

type ComponentAIFollowup struct {
	Label       string `json:"label"`
	QuickAction string `json:"quick_action"`
}

type ComponentAIActionResponse struct {
	SchemaVersion string                `json:"schema_version"`
	ComponentID   string                `json:"component_id"`
	Mode          string                `json:"mode"`
	Summary       string                `json:"summary"`
	UIEvents      []ComponentAIUIEvent  `json:"ui_events"`
	Insights      []interface{}         `json:"insights"`
	Followups     []ComponentAIFollowup `json:"followups"`
}

type youbikeLocationIntent struct {
	Place   string
	Center  []float64
	Zoom    float64
	Pitch   float64
	Bearing float64
}

type youbikeTimeIntent struct {
	Slot    int
	Hour    int
	Quarter int
	Label   string
	Reason  string
}

// ComponentAIAction handles POST /api/v1/ai/component-action.
// Prototype scope: deterministic YouBike time and map location controls.
func ComponentAIAction(c *gin.Context) {
	var input ComponentAIActionRequest
	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"status": "error", "message": err.Error()})
		return
	}

	componentID := normalizeComponentID(input.ComponentID)
	if componentID != "youbike_timemap" {
		c.JSON(http.StatusBadRequest, ComponentAIActionResponse{
			SchemaVersion: componentAIActionSchemaVersion,
			ComponentID:   input.ComponentID,
			Mode:          "clarify",
			Summary:       "目前 AI 操作 prototype 只支援 YouBike 一日可用率動態地圖。",
			UIEvents:      []ComponentAIUIEvent{},
			Insights:      []interface{}{},
			Followups:     []ComponentAIFollowup{},
		})
		return
	}

	message := strings.TrimSpace(input.UserMessage + " " + input.QuickAction)
	timeIntent, hasTime := parseYouBikeTimeIntent(message)
	locationIntent, hasLocation := parseYouBikeLocationIntent(message)

	events := make([]ComponentAIUIEvent, 0, 2)
	if hasTime {
		events = append(events, ComponentAIUIEvent{
			ComponentID: componentID,
			Action:      "set_time_slot",
			Payload: map[string]interface{}{
				"slot":    timeIntent.Slot,
				"hour":    timeIntent.Hour,
				"quarter": timeIntent.Quarter,
				"label":   timeIntent.Label,
				"reason":  timeIntent.Reason,
			},
		})
	}
	if hasLocation {
		events = append(events, ComponentAIUIEvent{
			ComponentID: componentID,
			Action:      "focus_location",
			Payload: map[string]interface{}{
				"place":   locationIntent.Place,
				"center":  locationIntent.Center,
				"zoom":    locationIntent.Zoom,
				"pitch":   locationIntent.Pitch,
				"bearing": locationIntent.Bearing,
			},
		})
	}

	if len(events) == 0 {
		c.JSON(http.StatusOK, ComponentAIActionResponse{
			SchemaVersion: componentAIActionSchemaVersion,
			ComponentID:   componentID,
			Mode:          "clarify",
			Summary:       "我目前可以幫你切換 YouBike 時段或移動地圖。可以試試「看公館晚高峰」或「切到早上八點」。",
			UIEvents:      []ComponentAIUIEvent{},
			Insights:      []interface{}{},
			Followups:     defaultYouBikeFollowups(),
		})
		return
	}

	c.JSON(http.StatusOK, ComponentAIActionResponse{
		SchemaVersion: componentAIActionSchemaVersion,
		ComponentID:   componentID,
		Mode:          "action",
		Summary:       composeYouBikeActionSummary(timeIntent, hasTime, locationIntent, hasLocation),
		UIEvents:      events,
		Insights:      []interface{}{},
		Followups:     defaultYouBikeFollowups(),
	})
}

func normalizeComponentID(componentID string) string {
	switch strings.TrimSpace(componentID) {
	case "youbike_timemap", "youbike-availability-map", "youbike_time_map":
		return "youbike_timemap"
	default:
		return strings.TrimSpace(componentID)
	}
}

func parseYouBikeTimeIntent(message string) (youbikeTimeIntent, bool) {
	normalized := strings.ToLower(strings.TrimSpace(message))
	if normalized == "" {
		return youbikeTimeIntent{}, false
	}

	if hour, minute, ok := parseExplicitTime(normalized); ok {
		return buildYouBikeTimeIntent(hour, minute, "指定時間"), true
	}

	presets := []struct {
		Keywords []string
		Hour     int
		Minute   int
		Reason   string
	}{
		{[]string{"晚高峰", "下班", "傍晚尖峰", "晚尖峰", "evening"}, 18, 0, "晚高峰"},
		{[]string{"早高峰", "上班", "上午尖峰", "早尖峰", "morning"}, 8, 0, "早高峰"},
		{[]string{"中午", "午餐", "noon"}, 12, 0, "中午"},
		{[]string{"下午"}, 15, 0, "下午"},
		{[]string{"晚上"}, 19, 0, "晚上"},
		{[]string{"凌晨"}, 0, 0, "凌晨"},
	}

	for _, preset := range presets {
		for _, keyword := range preset.Keywords {
			if strings.Contains(normalized, keyword) {
				return buildYouBikeTimeIntent(preset.Hour, preset.Minute, preset.Reason), true
			}
		}
	}

	return youbikeTimeIntent{}, false
}

func parseExplicitTime(message string) (int, int, bool) {
	colonRe := regexp.MustCompile(`(\d{1,2})\s*[:：]\s*(\d{1,2})`)
	if matches := colonRe.FindStringSubmatch(message); len(matches) == 3 {
		hour, _ := strconv.Atoi(matches[1])
		minute, _ := strconv.Atoi(matches[2])
		if validHourMinute(hour, minute) {
			return hour, minute, true
		}
	}

	hourRe := regexp.MustCompile(`(\d{1,2})\s*(點|时|時)半?`)
	if matches := hourRe.FindStringSubmatch(message); len(matches) >= 2 {
		hour, _ := strconv.Atoi(matches[1])
		minute := 0
		if strings.Contains(matches[0], "半") {
			minute = 30
		}
		if strings.Contains(message, "下午") || strings.Contains(message, "晚上") || strings.Contains(message, "晚間") {
			if hour >= 1 && hour <= 11 {
				hour += 12
			}
		}
		if validHourMinute(hour, minute) {
			return hour, minute, true
		}
	}

	chineseHours := map[string]int{
		"零": 0, "〇": 0, "一": 1, "二": 2, "兩": 2, "三": 3, "四": 4,
		"五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10,
		"十一": 11, "十二": 12,
	}
	for textHour, hour := range chineseHours {
		if strings.Contains(message, textHour+"點") || strings.Contains(message, textHour+"時") {
			minute := 0
			if strings.Contains(message, textHour+"點半") || strings.Contains(message, textHour+"時半") {
				minute = 30
			}
			if strings.Contains(message, "下午") || strings.Contains(message, "晚上") || strings.Contains(message, "晚間") {
				if hour >= 1 && hour <= 11 {
					hour += 12
				}
			}
			return hour, minute, true
		}
	}

	return 0, 0, false
}

func validHourMinute(hour int, minute int) bool {
	return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
}

func buildYouBikeTimeIntent(hour int, minute int, reason string) youbikeTimeIntent {
	quarter := int(math.Round(float64(minute) / 15.0))
	if quarter > 3 {
		quarter = 3
	}
	slot := hour*4 + quarter
	labelMinute := quarter * 15
	return youbikeTimeIntent{
		Slot:    slot,
		Hour:    hour,
		Quarter: quarter,
		Label:   twoDigit(hour) + ":" + twoDigit(labelMinute),
		Reason:  reason,
	}
}

func twoDigit(value int) string {
	if value < 10 {
		return "0" + strconv.Itoa(value)
	}
	return strconv.Itoa(value)
}

func parseYouBikeLocationIntent(message string) (youbikeLocationIntent, bool) {
	locations := []struct {
		Aliases []string
		Intent  youbikeLocationIntent
	}{
		{[]string{"公館", "台大", "臺大", "台灣大學", "臺灣大學"}, youbikeLocationIntent{"公館", []float64{121.5339, 25.0143}, 15.5, 45, 0}},
		{[]string{"台北車站", "臺北車站", "北車"}, youbikeLocationIntent{"台北車站", []float64{121.5171, 25.0478}, 15.5, 45, 0}},
		{[]string{"市政府", "台北市政府", "臺北市政府"}, youbikeLocationIntent{"台北市政府", []float64{121.5647, 25.0408}, 15.5, 45, 0}},
		{[]string{"東區", "忠孝復興"}, youbikeLocationIntent{"東區", []float64{121.5568, 25.0387}, 14.5, 35, 67}},
		{[]string{"大安", "大安站"}, youbikeLocationIntent{"大安", []float64{121.5433, 25.0278}, 15.3, 45, 0}},
		{[]string{"大稻埕"}, youbikeLocationIntent{"大稻埕", []float64{121.5101, 25.0558}, 16, 50, 60}},
		{[]string{"花博", "花博公園"}, youbikeLocationIntent{"花博公園", []float64{121.5229, 25.0685}, 15.75, 60, 130}},
		{[]string{"陽明山"}, youbikeLocationIntent{"陽明山", []float64{121.5518, 25.1290}, 13.25, 60, 0}},
	}

	for _, location := range locations {
		for _, alias := range location.Aliases {
			if strings.Contains(message, alias) {
				return location.Intent, true
			}
		}
	}

	return youbikeLocationIntent{}, false
}

func composeYouBikeActionSummary(timeIntent youbikeTimeIntent, hasTime bool, locationIntent youbikeLocationIntent, hasLocation bool) string {
	parts := make([]string, 0, 2)
	if hasTime {
		parts = append(parts, "切到"+timeIntent.Label)
	}
	if hasLocation {
		parts = append(parts, "移到"+locationIntent.Place+"周邊")
	}
	if len(parts) == 0 {
		return "已完成 YouBike 地圖操作。"
	}
	return "已" + strings.Join(parts, "，並") + "。"
}

func defaultYouBikeFollowups() []ComponentAIFollowup {
	return []ComponentAIFollowup{
		{Label: "公館晚高峰", QuickAction: "公館 晚高峰"},
		{Label: "台北車站早高峰", QuickAction: "台北車站 早高峰"},
		{Label: "市政府晚上八點", QuickAction: "市政府 晚上8點"},
	}
}
