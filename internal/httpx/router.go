package httpx

import (
	"net/http"
	"sync"
)

// Router is the slice of *http.ServeMux that route registration needs. The
// Register* functions take this instead of the concrete mux so the whole live
// surface can be enumerated by a RouteRecorder.
type Router interface {
	Handle(pattern string, handler http.Handler)
	HandleFunc(pattern string, handler func(http.ResponseWriter, *http.Request))
}

// RouteRecorder wraps a ServeMux and remembers every pattern registered through
// it. Go's mux cannot list its own patterns, and the service-token route-class
// test (ARGY-325) needs the live set rather than a hand-kept copy that drifts:
// a route added without being classified must fail a test, not slip through.
type RouteRecorder struct {
	Mux *http.ServeMux

	mu       sync.Mutex
	patterns []string
}

// NewRouteRecorder returns a recorder over a fresh mux.
func NewRouteRecorder() *RouteRecorder { return &RouteRecorder{Mux: http.NewServeMux()} }

func (r *RouteRecorder) record(pattern string) {
	r.mu.Lock()
	r.patterns = append(r.patterns, pattern)
	r.mu.Unlock()
}

// Handle registers and records pattern.
func (r *RouteRecorder) Handle(pattern string, h http.Handler) {
	r.record(pattern)
	r.Mux.Handle(pattern, h)
}

// HandleFunc registers and records pattern.
func (r *RouteRecorder) HandleFunc(pattern string, h func(http.ResponseWriter, *http.Request)) {
	r.record(pattern)
	r.Mux.HandleFunc(pattern, h)
}

// Patterns returns the recorded patterns in registration order.
func (r *RouteRecorder) Patterns() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.patterns...)
}
