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
