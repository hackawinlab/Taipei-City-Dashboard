// Package control collects UI control events emitted by tools during an
// AI chat turn. Tools call Append; the controller installs a bag via
// WithBag before invoking the AI service and reads it back to put into
// the JSON response.
package control

import "context"

type Event struct {
	Action  string      `json:"action"`
	Payload interface{} `json:"payload"`
}

// MapLayerEntry is one entry in the available-map-layers list sent by the frontend.
type MapLayerEntry struct {
	Index string `json:"index"`
	City  string `json:"city"`
	Name  string `json:"name"`
}

// OpenLayer identifies a currently visible map layer by (index, city).
type OpenLayer struct {
	Index string `json:"index"`
	City  string `json:"city"`
}

// PageContext carries the frontend's current page state so tools and
// instruction injection can adapt to where the user actually is.
type PageContext struct {
	Route              string          `json:"route"`
	City               string          `json:"city"`
	OpenLayers         []OpenLayer     `json:"open_layers"`
	AvailableMapLayers []MapLayerEntry `json:"available_map_layers"`
}

type availLayersKey struct{}

func WithAvailableLayers(ctx context.Context, layers []MapLayerEntry) context.Context {
	return context.WithValue(ctx, availLayersKey{}, layers)
}

func GetAvailableLayers(ctx context.Context) []MapLayerEntry {
	v, _ := ctx.Value(availLayersKey{}).([]MapLayerEntry)
	return v
}

// DefaultCity returns the city, or "taipei" if empty.
func DefaultCity(city string) string {
	if city == "" {
		return "taipei"
	}
	return city
}

type ctxKey struct{}

func WithBag(ctx context.Context, bag *[]Event) context.Context {
	return context.WithValue(ctx, ctxKey{}, bag)
}

func Append(ctx context.Context, e Event) {
	if bag, ok := ctx.Value(ctxKey{}).(*[]Event); ok && bag != nil {
		*bag = append(*bag, e)
	}
}

func getBag(ctx context.Context) *[]Event {
	bag, ok := ctx.Value(ctxKey{}).(*[]Event)
	if !ok || bag == nil {
		return nil
	}
	return bag
}

// HasEvents reports whether any events have been appended to the bag in ctx.
func HasEvents(ctx context.Context) bool {
	bag := getBag(ctx)
	return bag != nil && len(*bag) > 0
}

// HasEventOfAction reports whether an event with the given action has already
// been appended. Tools use this to prevent duplicate events in one turn.
func HasEventOfAction(ctx context.Context, action string) bool {
	bag := getBag(ctx)
	if bag == nil {
		return false
	}
	for _, e := range *bag {
		if e.Action == action {
			return true
		}
	}
	return false
}

// HasEventOfActionWithPayload reports whether an event with the given action
// and all specified payload key-value pairs has already been appended.
// Used by toggle_map_layer to dedup (index, city, action) triples.
func HasEventOfActionWithPayload(ctx context.Context, action string, payload map[string]string) bool {
	bag := getBag(ctx)
	if bag == nil {
		return false
	}
	for _, e := range *bag {
		if e.Action != action {
			continue
		}
		ep, ok := e.Payload.(map[string]string)
		if !ok {
			continue
		}
		match := true
		for k, v := range payload {
			if ep[k] != v {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}
