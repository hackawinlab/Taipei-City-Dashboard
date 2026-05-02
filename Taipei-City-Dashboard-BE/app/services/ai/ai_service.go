package ai

import (
	"TaipeiCityDashboardBE/app/models"
	"TaipeiCityDashboardBE/app/services/ai/control"
	"TaipeiCityDashboardBE/app/services/ai/providers/twcc"
	"TaipeiCityDashboardBE/app/services/ai/tools"
	"TaipeiCityDashboardBE/global"
	"TaipeiCityDashboardBE/logs"
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/tmc/langchaingo/llms"
	"golang.org/x/sync/semaphore"
)

var (
	// aiSemaphore limits the number of concurrent AI requests
	aiSemaphore *semaphore.Weighted
	twccModel   llms.Model
)

func init() {
	aiSemaphore = semaphore.NewWeighted(int64(global.TWCC.MaxConcurrent))
	twccModel = twcc.New(
		global.TWCC.ApiKey,
		global.TWCC.ApiUrl,
		global.TWCC.Model,
		global.TWCC.Timeout,
	)
}

type AIChatRequest struct {
	SessionID   string                 `json:"session"`
	UserID      string                 `json:"user_id"`
	IPAddress   string                 `json:"ip_address"`
	Messages    []llms.MessageContent  `json:"messages"`
	Params      map[string]interface{} `json:"params"`
	PageContext control.PageContext    `json:"page_context"`
}

// ChatWithTWCC handles the AI conversation logic including retries, tool calling loop, and logging.
func ChatWithTWCC(ctx context.Context, req AIChatRequest, options ...llms.CallOption) (*models.AIChatLog, error) {
	if err := aiSemaphore.Acquire(ctx, 1); err != nil {
		return nil, fmt.Errorf("server too busy: %v", err)
	}
	defer aiSemaphore.Release(1)

	session := newSession(req, options...)
	return session.run(ctx)
}

// GenerateWithTWCC runs a single model request without the chat tool-execution
// loop. Component-level AI actions use this for structured intent parsing; the
// caller still validates any returned actions before applying UI events.
func GenerateWithTWCC(ctx context.Context, messages []llms.MessageContent, options ...llms.CallOption) (*llms.ContentResponse, error) {
	if err := aiSemaphore.Acquire(ctx, 1); err != nil {
		return nil, fmt.Errorf("server too busy: %v", err)
	}
	defer aiSemaphore.Release(1)

	return twccModel.GenerateContent(ctx, messages, options...)
}

func newSession(req AIChatRequest, options ...llms.CallOption) *aiSession {
	s := &aiSession{
		req:             req,
		options:         options,
		currentMessages: make([]llms.MessageContent, 0),
		startTime:       time.Now(),
	}
	for _, opt := range options {
		opt(&s.callOpts)
	}
	s.injectInstructions()
	return s
}

type aiSession struct {
	req             AIChatRequest
	options         []llms.CallOption
	callOpts        llms.CallOptions
	currentMessages []llms.MessageContent
	totalInput      int
	totalOutput     int
	toolUsed        bool
	executedTools   []string
	lastResp        *llms.ContentResponse
	lastErr         error
	startTime       time.Time
}

func (s *aiSession) run(ctx context.Context) (*models.AIChatLog, error) {
	maxLoops := 5
	s.executedTools = make([]string, 0)
	for i := 0; i < maxLoops; i++ {
		s.sendHeartbeat(ctx)

		if err := s.generate(ctx); err != nil {
			break
		}

		toolCalls := s.extractToolCalls()
		if len(toolCalls) == 0 {
			break
		}

		s.toolUsed = true
		logs.FInfo("Loop %d: Processing %d tool calls", i, len(toolCalls))
		if err := s.executeTools(ctx, toolCalls); err != nil {
			break
		}
		// UI control events are fire-and-done; stop looping so the LLM
		// cannot call the same tool again in subsequent iterations.
		if control.HasEvents(ctx) {
			break
		}
	}

	// If tools were used but the final LLM response has no text (e.g. the loop
	// was exhausted while the LLM was still emitting tool calls), strip tools
	// from options and generate once more to force a plain-text summary.
	if s.lastErr == nil && s.toolUsed && s.lastTextContent() == "" {
		s.options = append(s.options, llms.WithTools(nil))
		s.sendHeartbeat(ctx)
		s.generate(ctx)
	}

	return s.finalize()
}

func (s *aiSession) lastTextContent() string {
	if s.lastResp == nil || len(s.lastResp.Choices) == 0 {
		return ""
	}
	return s.lastResp.Choices[0].Content
}

func (s *aiSession) sendHeartbeat(ctx context.Context) {
	if s.callOpts.StreamingFunc != nil {
		s.callOpts.StreamingFunc(ctx, []byte(": heartbeat\n\n"))
	}
}

func (s *aiSession) generate(ctx context.Context) error {
	maxRetry := global.TWCC.MaxRetry
	if s.callOpts.StreamingFunc != nil {
		maxRetry = 0
	}

	for i := 0; i <= maxRetry; i++ {
		s.lastResp, s.lastErr = twccModel.GenerateContent(ctx, s.currentMessages, s.options...)
		if s.lastErr == nil {
			s.updateTokens()
			return nil
		}
		logs.FError("Attempt %d failed: %v", i+1, s.lastErr)
		if i < maxRetry {
			time.Sleep(500 * time.Millisecond)
		}
	}
	return s.lastErr
}

func (s *aiSession) extractToolCalls() []llms.ToolCall {
	if s.lastResp == nil || len(s.lastResp.Choices) == 0 {
		return nil
	}
	tc, _ := s.lastResp.Choices[0].GenerationInfo["tool_calls"].([]llms.ToolCall)
	return tc
}

func (s *aiSession) updateTokens() {
	if s.lastResp == nil || len(s.lastResp.Choices) == 0 {
		return
	}
	if usage, ok := s.lastResp.Choices[0].GenerationInfo["usage"].(map[string]interface{}); ok {
		s.totalInput += parseUsageInt(usage["input_tokens"])
		s.totalOutput += parseUsageInt(usage["output_tokens"])
	}
}

func (s *aiSession) executeTools(ctx context.Context, toolCalls []llms.ToolCall) error {
	choice := s.lastResp.Choices[0]
	
	// Add Assistant's intent
	s.currentMessages = append(s.currentMessages, llms.MessageContent{
		Role:  llms.ChatMessageTypeAI,
		Parts: append([]llms.ContentPart{llms.TextContent{Text: choice.Content}}, toolsToParts(toolCalls)...),
	})

	for _, tc := range toolCalls {
		s.executedTools = append(s.executedTools, tc.FunctionCall.Name)
		result, err := tools.Execute(ctx, tc.FunctionCall.Name, tc.FunctionCall.Arguments)
		if err != nil {
			result = fmt.Sprintf("Error: %v. Please verify arguments.", err)
			logs.FError("Tool Error: %v", err)
		}

		s.currentMessages = append(s.currentMessages, llms.MessageContent{
			Role: llms.ChatMessageTypeTool,
			Parts: []llms.ContentPart{llms.ToolCallResponse{
				ToolCallID: tc.ID, Name: tc.FunctionCall.Name, Content: result,
			}},
		})
	}
	return nil
}

func (s *aiSession) injectInstructions() {
	toolNames := ""
	for i, t := range s.callOpts.Tools {
		if i > 0 { toolNames += ", " }
		toolNames += t.Function.Name
	}

	instruction := fmt.Sprintf("\nSystem Instruction:\n1. Use ONLY: [%s].\n2. NEVER nest tool calls \n3. Arguments MUST be literal values (strings, integers, etc.), never function calls \n4. For dependent tasks, call tools sequentially in separate turns.\n5. If stuck, respond with text.", toolNames)

	for _, t := range s.callOpts.Tools {
		if t.Function == nil {
			continue
		}
		switch t.Function.Name {
		case tools.NavigateToDashboardName:
			catalogue := DashboardCatalogueMarkdown()
			if catalogue != "" {
				instruction += "\n\nYou can suggest the user to navigate to a dashboard by calling navigate_to_dashboard.\nRules:\n- Call navigate_to_dashboard AT MOST ONCE per user message.\n- After the tool call succeeds, ALWAYS reply in Traditional Chinese with one sentence suggesting which dashboard to check, e.g. \"建議您查看「XXX」儀表板，可點擊下方按鈕切換。\" (A button will appear below the message for the user to click.)\n- Do NOT call navigate_to_dashboard again after you have already called it in this turn.\n- Do NOT invent indices; use only indices from the catalogue below.\nCity rule: 台北 / 北市 / 台北市 → \"taipei\"; 雙北 / 新北 / 新北市 → \"metrotaipei\". If unclear, default \"taipei\".\n\nAvailable dashboards:\n" + catalogue
			}
		case tools.ToggleMapLayerName:
			instruction += buildToggleMapLayerInstruction(s.req.PageContext)
		}
	}

	s.currentMessages = make([]llms.MessageContent, 0)
	merged := false
	for _, m := range s.req.Messages {
		if m.Role == llms.ChatMessageTypeSystem && !merged {
			s.currentMessages = append(s.currentMessages, mergeSystemMsg(m, instruction))
			merged = true
		} else {
			s.currentMessages = append(s.currentMessages, m)
		}
	}
	
	if !merged {
		s.currentMessages = append([]llms.MessageContent{{
			Role:  llms.ChatMessageTypeSystem,
			Parts: []llms.ContentPart{llms.TextContent{Text: instruction}},
		}}, s.currentMessages...)
	}
}

func buildToggleMapLayerInstruction(pageCtx control.PageContext) string {
	if len(pageCtx.AvailableMapLayers) == 0 {
		return ""
	}

	nameLookup := make(map[string]string, len(pageCtx.AvailableMapLayers))
	var catalogue strings.Builder
	for _, l := range pageCtx.AvailableMapLayers {
		fmt.Fprintf(&catalogue, "- index=`%s` city=`%s` name=\"%s\"\n", l.Index, l.City, l.Name)
		nameLookup[l.Index+"|"+l.City] = l.Name
	}

	openLayersDesc := "（目前沒有開啟任何圖層）"
	if len(pageCtx.OpenLayers) > 0 {
		descs := make([]string, 0, len(pageCtx.OpenLayers))
		for _, ol := range pageCtx.OpenLayers {
			name := nameLookup[ol.Index+"|"+ol.City]
			if name == "" {
				name = ol.Index
			}
			descs = append(descs, fmt.Sprintf("「%s」(index=%s, city=%s)", name, ol.Index, ol.City))
		}
		openLayersDesc = strings.Join(descs, ", ")
	}

	return fmt.Sprintf(
		"\n\n## 地圖圖層工具 (toggle_map_layer)\n"+
			"使用者目前在地圖交叉對比頁面，預設 city: %s\n\n"+
			"可用圖層（請只使用以下 (index, city) 組合）：\n%s\n"+
			"目前已開啟的圖層: %s\n\n"+
			"何時呼叫工具：\n"+
			"- 使用者明確要求「開啟/打開/顯示/show」某圖層 → action='show'\n"+
			"- 使用者明確要求「關閉/隱藏/拿掉/hide」某圖層 → action='hide'\n\n"+
			"何時「不要」呼叫工具，直接用文字回答：\n"+
			"- 使用者問「有哪些圖層」「可以控制什麼」「有什麼可以開」之類**列表查詢** → 用繁體中文列出上方「可用圖層」的 name，不要呼叫工具。\n"+
			"- 使用者問「現在開了哪些」「目前有什麼是開的」之類**狀態查詢** → 用繁體中文列出上方「目前已開啟的圖層」的 name，不要呼叫工具。\n"+
			"- 使用者只是聊天、確認、追問前一輪內容 → 用文字回答，不要呼叫工具。\n\n"+
			"其他規則：\n"+
			"- 呼叫工具時 city 必須跟可用圖層清單裡列出的 city 一致，不要自行替換。\n"+
			"- 同一輪請求不要重複呼叫相同 (index, city, action)。\n"+
			"- 工具呼叫成功後，請用繁體中文一句話確認操作，例如「已為您開啟「老年人口分布」圖層。」\n",
		control.DefaultCity(pageCtx.City), catalogue.String(), openLayersDesc,
	)
}

func (s *aiSession) finalize() (*models.AIChatLog, error) {
	log := &models.AIChatLog{
		SessionID: s.req.SessionID, UserID: s.req.UserID, IPAddress: s.req.IPAddress,
		Provider: "twcc", Model: global.TWCC.Model, LatencyMS: int(time.Since(s.startTime).Milliseconds()),
		Status: "success", Tools: "[]", CreatedAt: s.startTime,
	}

	if len(s.req.Messages) > 0 {
		log.Question = extractText(s.req.Messages[len(s.req.Messages)-1])
	}

	if s.lastErr != nil {
		log.Status, log.ErrorCode, log.ErrorMessage = "error", "MODEL_ERROR", s.lastErr.Error()
		models.CreateAIChatLog(log)
		return log, s.lastErr
	}

	if s.lastResp != nil && len(s.lastResp.Choices) > 0 {
		log.Answer = s.lastResp.Choices[0].Content
		log.InputTokens, log.OutputTokens = s.totalInput, s.totalOutput
		log.TotalTokens = s.totalInput + s.totalOutput
		if s.toolUsed {
			log.ToolUsed = true
			if toolJSON, err := json.Marshal(s.executedTools); err == nil {
				log.Tools = string(toolJSON)
			}
		}
	}

	if err := models.CreateAIChatLog(log); err != nil {
		logs.FError("DB Log Error: %v", err)
	}
	return log, nil
}

func toolsToParts(calls []llms.ToolCall) []llms.ContentPart {
	parts := make([]llms.ContentPart, len(calls))
	for i, c := range calls { parts[i] = c }
	return parts
}

func mergeSystemMsg(m llms.MessageContent, instruction string) llms.MessageContent {
	newParts := make([]llms.ContentPart, len(m.Parts))
	for i, p := range m.Parts {
		if tp, ok := p.(llms.TextContent); ok {
			newParts[i] = llms.TextContent{Text: tp.Text + instruction}
		} else {
			newParts[i] = p
		}
	}
	return llms.MessageContent{Role: m.Role, Parts: newParts}
}

func extractText(m llms.MessageContent) string {
	for _, p := range m.Parts {
		if t, ok := p.(llms.TextContent); ok { return t.Text }
	}
	return ""
}

func parseUsageInt(val interface{}) int {
	switch v := val.(type) {
	case int: return v
	case float64: return int(v)
	default: return 0
	}
}
