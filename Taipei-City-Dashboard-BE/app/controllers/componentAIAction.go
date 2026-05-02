package controllers

import (
	"TaipeiCityDashboardBE/app/services/ai"
	"TaipeiCityDashboardBE/app/services/youbike"
	"TaipeiCityDashboardBE/logs"
	"context"
	"encoding/json"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/tmc/langchaingo/llms"
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

type youbikeTimeIntent struct {
	Slot    int
	Hour    int
	Quarter int
	Label   string
	Reason  string
}

type youbikeActionPlan struct {
	TimeIntent     youbikeTimeIntent
	HasTime        bool
	LocationIntent youbike.LocationIntent
	HasLocation    bool
	Clarification  string
	IntentKind     string // "control" | "analytical" | "out_of_scope"
	Source         string // "llm" | "fallback"
	Followups      []ComponentAIFollowup
}

type youbikeLLMIntent struct {
	IntentKind string `json:"intent_kind"`
	Time       *struct {
		Hour   *int   `json:"hour"`
		Minute *int   `json:"minute"`
		Reason string `json:"reason"`
	} `json:"time"`
	Location *struct {
		Query         string `json:"query"`
		InMetroTaipei bool   `json:"in_metro_taipei"`
	} `json:"location"`
	Clarification string   `json:"clarification"`
	Followups     []string `json:"followups"`
}

// ComponentAIAction handles POST /api/v1/ai/component-action.
// Prototype scope: LLM-assisted YouBike time and map location controls.
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
			Summary:       "目前 AI 操作 prototype 只支援 Youbike 時序統計。",
			UIEvents:      []ComponentAIUIEvent{},
			Insights:      []interface{}{},
			Followups:     defaultYouBikeFollowups(),
		})
		return
	}

	message := strings.TrimSpace(input.UserMessage + " " + input.QuickAction)
	if message == "" {
		c.JSON(http.StatusOK, ComponentAIActionResponse{
			SchemaVersion: componentAIActionSchemaVersion,
			ComponentID:   componentID,
			Mode:          "clarify",
			Summary:       "請輸入想切換的時間或地點，例如「公館晚高峰」、「移到淡江大學」。",
			UIEvents:      []ComponentAIUIEvent{},
			Insights:      []interface{}{},
			Followups:     defaultYouBikeFollowups(),
		})
		return
	}

	plan, ok := parseYouBikeActionPlanWithLLM(c.Request.Context(), message, input.ComponentState)
	if !ok {
		plan = parseYouBikeActionPlanDeterministic(message)
	}

	events := make([]ComponentAIUIEvent, 0, 2)
	if plan.HasTime {
		events = append(events, ComponentAIUIEvent{
			ComponentID: componentID,
			Action:      "set_time_slot",
			Payload: map[string]interface{}{
				"slot":    plan.TimeIntent.Slot,
				"hour":    plan.TimeIntent.Hour,
				"quarter": plan.TimeIntent.Quarter,
				"label":   plan.TimeIntent.Label,
				"reason":  plan.TimeIntent.Reason,
			},
		})
	}
	if plan.HasLocation {
		events = append(events, ComponentAIUIEvent{
			ComponentID: componentID,
			Action:      "focus_location",
			Payload: map[string]interface{}{
				"place":         plan.LocationIntent.Place,
				"center":        plan.LocationIntent.Center,
				"zoom":          plan.LocationIntent.Zoom,
				"pitch":         plan.LocationIntent.Pitch,
				"bearing":       plan.LocationIntent.Bearing,
				"source":        plan.LocationIntent.Source,
				"station_count": plan.LocationIntent.StationCount,
			},
		})
	}

	mode := "action"
	if len(events) == 0 {
		mode = "clarify"
	}
	summary := composeYouBikePlanSummary(plan, len(events) > 0)
	followups := plan.Followups
	if len(followups) == 0 {
		followups = defaultYouBikeFollowups()
	}

	insights := buildYouBikeInsights(plan, input.ComponentState)
	if len(insights) > 0 {
		if phrasing := firstInsightPhrasing(insights); phrasing != "" {
			summary = strings.TrimSpace(summary) + " " + phrasing
		}
		// Attach radius + verdict to focus_location so the FE can draw a
		// matching highlight circle on the map.
		if first, ok := insights[0].(map[string]interface{}); ok {
			for i := range events {
				if events[i].Action == "focus_location" {
					if r, ok := first["radius_meters"]; ok {
						events[i].Payload["radius_meters"] = r
					}
					if v, ok := first["verdict"]; ok {
						events[i].Payload["verdict"] = v
					}
					if n, ok := first["station_count"]; ok {
						events[i].Payload["insight_station_count"] = n
					}
				}
			}
		}
	}

	c.JSON(http.StatusOK, ComponentAIActionResponse{
		SchemaVersion: componentAIActionSchemaVersion,
		ComponentID:   componentID,
		Mode:          mode,
		Summary:       summary,
		UIEvents:      events,
		Insights:      insights,
		Followups:     followups,
	})
}

// buildYouBikeInsights returns a single area-availability insight for
// the focused location at the resolved hour×quarter. Hour/quarter come
// from the time intent if present, otherwise from the component state's
// current_slot. Returns empty when there is no location to anchor on
// or DB has nothing for that slot.
func buildYouBikeInsights(plan youbikeActionPlan, state map[string]interface{}) []interface{} {
	if !plan.HasLocation || len(plan.LocationIntent.Center) != 2 {
		return nil
	}

	hour, quarter, ok := resolveInsightTime(plan, state)
	if !ok {
		return nil
	}

	insight, found := youbike.SummarizeArea(
		plan.LocationIntent.Center[0], // lng
		plan.LocationIntent.Center[1], // lat
		hour,
		quarter,
	)
	if !found {
		return nil
	}
	return []interface{}{
		map[string]interface{}{
			"kind":                 "area_availability",
			"station_count":        insight.StationCount,
			"avg_availability_pct": insight.AvgAvailabilityPct,
			"avg_available":        insight.AvgAvailable,
			"avg_total_docks":      insight.AvgTotalDocks,
			"radius_meters":        insight.RadiusMeters,
			"verdict":              insight.Verdict,
			"phrasing":             insight.Phrasing,
			"hour":                 hour,
			"quarter":              quarter,
		},
	}
}

func resolveInsightTime(plan youbikeActionPlan, state map[string]interface{}) (int, int, bool) {
	if plan.HasTime {
		return plan.TimeIntent.Hour, plan.TimeIntent.Quarter, true
	}
	if state == nil {
		return 0, 0, false
	}
	if slot, ok := numberFromState(state["current_slot"]); ok {
		s := int(slot)
		if s >= 0 && s < 96 {
			return s / 4, s % 4, true
		}
	}
	return 0, 0, false
}

func numberFromState(v interface{}) (float64, bool) {
	switch n := v.(type) {
	case float64:
		return n, true
	case int:
		return float64(n), true
	case int64:
		return float64(n), true
	}
	return 0, false
}

func firstInsightPhrasing(insights []interface{}) string {
	if len(insights) == 0 {
		return ""
	}
	m, ok := insights[0].(map[string]interface{})
	if !ok {
		return ""
	}
	s, _ := m["phrasing"].(string)
	return s
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

func parseYouBikeActionPlanDeterministic(message string) youbikeActionPlan {
	plan := youbikeActionPlan{
		IntentKind: "control",
		Source:     "fallback",
	}
	if timeIntent, ok := parseYouBikeTimeIntent(message); ok {
		plan.TimeIntent = timeIntent
		plan.HasTime = true
	}
	if locationIntent, ok := youbike.ResolveLocation(extractLocationGuess(message)); ok {
		plan.LocationIntent = locationIntent
		plan.HasLocation = true
	}
	return plan
}

// extractLocationGuess strips obvious time keywords from the raw message
// so the deterministic fallback's tier-2 station LIKE doesn't get
// poisoned by phrases like "晚高峰". Only used in the no-LLM path.
func extractLocationGuess(message string) string {
	cleaned := message
	for _, kw := range []string{"晚高峰", "早高峰", "下班", "上班", "中午", "午餐", "凌晨", "晚上", "下午", "傍晚尖峰", "晚尖峰", "上午尖峰", "早尖峰", "evening", "morning", "noon"} {
		cleaned = strings.ReplaceAll(cleaned, kw, " ")
	}
	cleaned = regexp.MustCompile(`\d+\s*[:：]\s*\d+`).ReplaceAllString(cleaned, " ")
	cleaned = regexp.MustCompile(`\d+\s*(點|時)半?`).ReplaceAllString(cleaned, " ")
	cleaned = regexp.MustCompile(`(看|看看|幫我看|幫我|移到|移動到|去|前往|切到|切換到|跳到)`).ReplaceAllString(cleaned, " ")
	return strings.TrimSpace(cleaned)
}

func parseYouBikeActionPlanWithLLM(ctx context.Context, message string, componentState map[string]interface{}) (youbikeActionPlan, bool) {
	if strings.TrimSpace(message) == "" {
		return youbikeActionPlan{}, false
	}

	ctx, cancel := context.WithTimeout(ctx, 12*time.Second)
	defer cancel()

	stateJSON, _ := json.Marshal(componentState)
	messages := []llms.MessageContent{
		{
			Role: llms.ChatMessageTypeSystem,
			Parts: []llms.ContentPart{llms.TextContent{
				Text: youbikeIntentSystemPrompt(),
			}},
		},
		{
			Role: llms.ChatMessageTypeHuman,
			Parts: []llms.ContentPart{llms.TextContent{
				Text: "使用者訊息：" + message + "\n目前組件狀態：" + string(stateJSON),
			}},
		},
	}
	resp, err := ai.GenerateWithTWCC(
		ctx,
		messages,
		llms.WithMetadata(map[string]interface{}{
			"max_new_tokens": 450,
			"temperature":    0.1,
			"top_p":          0.2,
		}),
	)
	if err != nil || resp == nil || len(resp.Choices) == 0 {
		logs.FInfo("component AI: LLM fallback (err=%v)", err)
		return youbikeActionPlan{}, false
	}

	var intent youbikeLLMIntent
	if err := json.Unmarshal([]byte(extractJSONObject(resp.Choices[0].Content)), &intent); err != nil {
		logs.FInfo("component AI: LLM JSON parse failed: %v", err)
		return youbikeActionPlan{}, false
	}

	plan := youbikeActionPlan{
		Clarification: strings.TrimSpace(intent.Clarification),
		IntentKind:    strings.TrimSpace(intent.IntentKind),
		Source:        "llm",
		Followups:     stringFollowupsToObjects(intent.Followups),
	}

	switch plan.IntentKind {
	case "out_of_scope":
		// LLM already explained why; nothing to apply.
		if plan.Clarification == "" {
			plan.Clarification = "目前這個 AI 只能操作雙北 YouBike 一日可用率地圖。"
		}
		return plan, true
	case "analytical":
		if plan.Clarification == "" {
			plan.Clarification = "目前 prototype 可以幫你切時間或移動地圖；想看分析請開啟組件下方的「組件資訊」。"
		}
		return plan, true
	}

	// intent_kind == "control" (or empty / unknown — treat as control attempt)
	if intent.Time != nil && intent.Time.Hour != nil {
		minute := 0
		if intent.Time.Minute != nil {
			minute = *intent.Time.Minute
		}
		if validHourMinute(*intent.Time.Hour, minute) {
			plan.TimeIntent = buildYouBikeTimeIntent(*intent.Time.Hour, minute, defaultReason(intent.Time.Reason, "指定時間"))
			plan.HasTime = true
		} else if plan.Clarification == "" {
			plan.Clarification = "時間請在 00:00 ~ 23:45 之間，例如「早上 8 點」、「18:30」。"
		}
	}

	if intent.Location != nil {
		query := strings.TrimSpace(intent.Location.Query)
		if query != "" && !intent.Location.InMetroTaipei {
			plan.Clarification = unsupportedLocationMessage(query)
		} else if query != "" {
			if locationIntent, ok := youbike.ResolveLocation(query); ok {
				plan.LocationIntent = locationIntent
				plan.HasLocation = true
			} else if plan.Clarification == "" {
				plan.Clarification = unknownLocationMessage(query)
			}
		}
	}

	// Safety net: if the LLM returned no usable intents but the raw message
	// matches a deterministic time/location, recover instead of dropping.
	if !plan.HasTime {
		if timeIntent, ok := parseYouBikeTimeIntent(message); ok {
			plan.TimeIntent = timeIntent
			plan.HasTime = true
		}
	}
	if !plan.HasLocation && plan.Clarification == "" {
		if locationIntent, ok := youbike.ResolveLocation(extractLocationGuess(message)); ok {
			plan.LocationIntent = locationIntent
			plan.HasLocation = true
		}
	}

	return plan, true
}

func defaultReason(value string, fallback string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallback
	}
	return value
}

func extractJSONObject(text string) string {
	text = strings.TrimSpace(text)
	text = strings.TrimPrefix(text, "```json")
	text = strings.TrimPrefix(text, "```")
	text = strings.TrimSuffix(text, "```")
	start := strings.Index(text, "{")
	end := strings.LastIndex(text, "}")
	if start >= 0 && end > start {
		return text[start : end+1]
	}
	return text
}

func stringFollowupsToObjects(items []string) []ComponentAIFollowup {
	out := make([]ComponentAIFollowup, 0, len(items))
	for _, raw := range items {
		s := strings.TrimSpace(raw)
		if s == "" {
			continue
		}
		out = append(out, ComponentAIFollowup{Label: s, QuickAction: s})
	}
	return out
}

func youbikeIntentSystemPrompt() string {
	return `你是 Taipei City Dashboard Youbike 時序統計的 intent parser。
你的工作是把使用者請求拆成可執行的 UI 動作。

請只回傳一個 JSON object，不要 markdown，不要解釋文字：
{
  "intent_kind": "control" | "analytical" | "out_of_scope",
  "time":     {"hour": 0-23 整數, "minute": 0|15|30|45, "reason": "晚高峰"} 或 null,
  "location": {"query": "使用者提到的地名原字串", "in_metro_taipei": true 或 false} 或 null,
  "clarification": "若 intent_kind 不是 control，用一句繁體中文告訴使用者；否則空字串",
  "followups": ["最多 3 個下一步建議的 quick_action 字串"]
}

規則：
- intent_kind = "control" 表示想切時間或移動地圖；"analytical" 表示想要分析或摘要；"out_of_scope" 表示和此地圖無關。
- 早高峰/上班 = 08:00；晚高峰/下班 = 18:00；中午/午餐 = 12:00；凌晨 = 00:00；晚上若沒指定時間視為 19:00。
- 「下午 X 點」「晚上 X 點」要轉成 24 小時制（X+12，若 X=12 則保持 12）。
- 地名只 echo 使用者原字串到 location.query，不要做任何 catalog 查表（後端會處理）。
- in_metro_taipei：台北市 / 新北市 任何地點都 true；外縣市、外國、虛構地名 = false。
- followups 範例：「公館晚高峰」「移到淡水」「切到 12:00」「板橋早上 8 點」。挑與當前對話相關的 2-3 個。
- 沒有 time 就回 null；沒有 location 就回 null。同一句可以同時有 time 和 location。
- 如果使用者只是打招呼或閒聊，intent_kind = "out_of_scope"，clarification 提示這個 AI 的能力。`
}

func composeYouBikePlanSummary(plan youbikeActionPlan, hasEvents bool) string {
	if !hasEvents {
		if plan.Clarification != "" {
			return plan.Clarification
		}
		return "我目前可以幫你切換 YouBike 時段或移動地圖。可以試試「公館晚高峰」、「切到早上 8 點」，或「移到淡水」。"
	}

	parts := make([]string, 0, 2)
	if plan.HasTime {
		parts = append(parts, "切到 "+plan.TimeIntent.Label)
	}
	if plan.HasLocation {
		parts = append(parts, "把地圖移到 "+plan.LocationIntent.Place)
	}
	summary := "已" + strings.Join(parts, "，並") + "。"

	if plan.HasLocation && plan.LocationIntent.Source == "station" {
		if plan.LocationIntent.StationCount > 1 {
			summary += "（從 YouBike 站名命中 " + strconv.Itoa(plan.LocationIntent.StationCount) + " 站，取中心點）"
		} else {
			summary += "（依 YouBike 站名定位）"
		}
	}

	if plan.HasTime && plan.HasLocation {
		summary += " 你可以接著拖時間軸看不同時段紅點分布。"
	} else if plan.HasTime {
		summary += " 想再移動地圖，例如「移到淡水」也可以。"
	} else if plan.HasLocation {
		summary += " 想看尖峰時段，可以再說「晚高峰」或「早高峰」。"
	}

	if plan.Clarification != "" {
		summary += " " + plan.Clarification
	}
	return summary
}

func unsupportedLocationMessage(place string) string {
	if place == "" {
		return "我看得懂你想移動地圖，但這個 YouBike 地圖目前只支援雙北。可以試試「公館」、「板橋」、「淡水」。"
	}
	return "我看得懂你想看「" + place + "」，但這個 YouBike 地圖目前只支援雙北。可以試試「公館」、「板橋」、「淡水」。"
}

func unknownLocationMessage(place string) string {
	if place == "" {
		return "我沒抓到具體地點，可以試試「公館」、「淡江大學」、「板橋車站」。"
	}
	return "我在 YouBike 站名裡找不到「" + place + "」。可以試試附近的捷運站、學校或地標，例如「公館」、「淡江大學」、「板橋車站」。"
}

func defaultYouBikeFollowups() []ComponentAIFollowup {
	return []ComponentAIFollowup{
		{Label: "公館晚高峰", QuickAction: "公館 晚高峰"},
		{Label: "淡江大學早高峰", QuickAction: "淡江大學 早高峰"},
		{Label: "板橋晚上 8 點", QuickAction: "板橋 晚上8點"},
	}
}
