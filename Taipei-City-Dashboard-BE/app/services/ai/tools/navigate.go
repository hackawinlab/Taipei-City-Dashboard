package tools

import (
	"TaipeiCityDashboardBE/app/models"
	"TaipeiCityDashboardBE/app/services/ai/control"
	"context"
	"fmt"

	"github.com/tmc/langchaingo/llms"
)

// NavigateToDashboardName is the canonical tool name used in the schema, registry, and system prompt.
const NavigateToDashboardName = "navigate_to_dashboard"

// NavigateToDashboardTool returns the llms.Tool descriptor for navigate_to_dashboard.
func NavigateToDashboardTool() llms.Tool {
	return llms.Tool{
		Type: "function",
		Function: &llms.FunctionDefinition{
			Name:        NavigateToDashboardName,
			Description: "Navigate the user's browser to a specific dashboard page. Call this when the user asks to view or switch to a dashboard.",
			Parameters: map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"index": map[string]interface{}{
						"type":        "string",
						"description": "The dashboard index identifier. Must be one of the indices listed in the catalogue. Do NOT invent indices.",
					},
					"city": map[string]interface{}{
						"type":        "string",
						"enum":        []string{"taipei", "metrotaipei"},
						"description": "City context: 'taipei' for 台北市; 'metrotaipei' for 雙北/新北市. Default 'taipei'.",
					},
				},
				"required": []string{"index", "city"},
			},
		},
	}
}

type navigateArgs struct {
	Index string `json:"index"`
	City  string `json:"city"`
}

// NavigateToDashboard validates the (index, city) pair and appends a navigate_to_dashboard
// control event to the context bag if valid.
func NavigateToDashboard(ctx context.Context, args string) (string, error) {
	var p navigateArgs
	if err := parseArgs(args, &p); err != nil {
		return "", fmt.Errorf("invalid args: %v", err)
	}
	p.City = control.DefaultCity(p.City)
	if control.HasEventOfAction(ctx, NavigateToDashboardName) {
		return "Already navigated once this turn. Do not call navigate_to_dashboard again.", nil
	}
	ok, err := models.IsValidDashboardForCity(p.Index, p.City)
	if err != nil {
		return fmt.Sprintf("Error: could not verify dashboard '%s' for city '%s': %v", p.Index, p.City, err), nil
	}
	if !ok {
		return fmt.Sprintf("Error: dashboard '%s' for city '%s' not found. Use only indices from the catalogue.", p.Index, p.City), nil
	}
	control.Append(ctx, control.Event{
		Action:  NavigateToDashboardName,
		Payload: map[string]string{"index": p.Index, "city": p.City},
	})
	return fmt.Sprintf("OK: navigated to %s (%s).", p.Index, p.City), nil
}
