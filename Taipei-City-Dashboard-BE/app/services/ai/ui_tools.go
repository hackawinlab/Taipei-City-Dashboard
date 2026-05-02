package ai

import (
	"TaipeiCityDashboardBE/app/services/ai/tools"

	"github.com/tmc/langchaingo/llms"
)

// WithUIControlTools appends the navigate_to_dashboard tool to any tools already present
// in options, ensuring it is available for every AI chat turn regardless of what the FE sends.
func WithUIControlTools(options []llms.CallOption) []llms.CallOption {
	var existing llms.CallOptions
	for _, opt := range options {
		opt(&existing)
	}
	merged := append(existing.Tools, tools.NavigateToDashboardTool())
	return append(options, llms.WithTools(merged))
}
