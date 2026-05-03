package ai

import (
	"TaipeiCityDashboardBE/app/services/ai/control"
	"TaipeiCityDashboardBE/app/services/ai/tools"

	"github.com/tmc/langchaingo/llms"
)

// WithUIControlTools appends UI control tools to options based on the current page context.
// navigate_to_dashboard is always included; toggle_map_layer is included only when the
// user is on /mapview AND there is at least one controllable map layer.
func WithUIControlTools(options []llms.CallOption, pageCtx control.PageContext) []llms.CallOption {
	var existing llms.CallOptions
	for _, opt := range options {
		opt(&existing)
	}
	merged := append(existing.Tools, tools.NavigateToDashboardTool())
	if pageCtx.Route == "/mapview" && len(pageCtx.AvailableMapLayers) > 0 {
		merged = append(merged, tools.ToggleMapLayerTool())
	}
	return append(options, llms.WithTools(merged))
}
