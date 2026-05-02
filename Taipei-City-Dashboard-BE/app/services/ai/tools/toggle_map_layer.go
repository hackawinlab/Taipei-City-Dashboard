package tools

import (
	"TaipeiCityDashboardBE/app/services/ai/control"
	"context"
	"fmt"

	"github.com/tmc/langchaingo/llms"
)

const (
	ToggleMapLayerName = "toggle_map_layer"
	ActionShow         = "show"
	ActionHide         = "hide"
)

func ToggleMapLayerTool() llms.Tool {
	return llms.Tool{
		Type: "function",
		Function: &llms.FunctionDefinition{
			Name:        ToggleMapLayerName,
			Description: "Show or hide a map layer on the cross-comparison map view. Call this when the user asks to open, close, or toggle a map layer while on the map view page.",
			Parameters: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"index": map[string]interface{}{
						"type":        "string",
						"description": "The component index of the map layer. Must be one of the indices listed in the map layer catalogue. Do NOT invent indices.",
					},
					"city": map[string]interface{}{
						"type":        "string",
						"enum":        []string{"taipei", "metrotaipei"},
						"description": "City context: 'taipei' for 台北市; 'metrotaipei' for 雙北/新北市.",
					},
					"action": map[string]interface{}{
						"type":        "string",
						"enum":        []string{ActionShow, ActionHide},
						"description": "Whether to show or hide the layer. Default 'show'.",
					},
				},
				"required": []string{"index", "city"},
			},
		},
	}
}

type toggleMapLayerArgs struct {
	Index  string `json:"index"`
	City   string `json:"city"`
	Action string `json:"action"`
}

// ToggleMapLayer validates the (index, city) against AvailableMapLayers from
// the page context and appends a toggle_map_layer event. Tool is gated upstream
// (ui_tools.go) so the available layers are guaranteed non-empty here.
func ToggleMapLayer(ctx context.Context, args string) (string, error) {
	var p toggleMapLayerArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid args: %v", err)
	}
	p.City = control.DefaultCity(p.City)
	if p.Action != ActionShow && p.Action != ActionHide {
		p.Action = ActionShow
	}

	dedup := map[string]string{"index": p.Index, "city": p.City, "action": p.Action}
	if control.HasEventOfActionWithPayload(ctx, ToggleMapLayerName, dedup) {
		return fmt.Sprintf("Already toggled layer '%s' (%s) this turn. Do not call toggle_map_layer again for the same layer.", p.Index, p.Action), nil
	}

	available := control.GetAvailableLayers(ctx)
	found := false
	for _, l := range available {
		if l.Index == p.Index && l.City == p.City {
			found = true
			break
		}
	}
	if !found {
		return fmt.Sprintf("Error: layer '%s' for city '%s' not found. Use only indices from the map layer catalogue.", p.Index, p.City), nil
	}

	control.Append(ctx, control.Event{
		Action:  ToggleMapLayerName,
		Payload: map[string]string{"index": p.Index, "city": p.City, "action": p.Action},
	})

	verb := "開啟"
	if p.Action == ActionHide {
		verb = "關閉"
	}
	return fmt.Sprintf("OK: %s了 %s 圖層（%s）。", verb, p.Index, p.City), nil
}
