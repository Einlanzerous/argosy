package server

import (
	"log/slog"
	"net/http"
	"time"
)

// statusRecorder captures the response status code for request logging.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// Flush forwards to the underlying writer. Without it, wrapping the
// ResponseWriter would hide the http.Flusher the SSE/streaming handlers depend
// on (e.g. Beacon's `w.(http.Flusher)`), turning live streams into 500s.
func (r *statusRecorder) Flush() {
	if f, ok := r.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// Unwrap exposes the wrapped writer to http.ResponseController so future
// streaming code can reach the underlying Flusher/Hijacker too.
func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

// withLogging logs one structured line per request.
//
// A SUCCESSFUL /healthz drops to Debug (ARGY-216). The container probes itself
// every 30s and Switchyard's delivery reconciler polls the same endpoint, so at
// Info the two together bury `docker logs argosy` under thousands of
// `path=/healthz status=200` lines a day — and the whole point of adding a
// healthcheck was to make this container's state easier to see, not harder.
//
// Only the 200 is quietened. A /healthz that answers anything else is the
// degraded database branch, which is exactly the line someone wants to find
// when they go looking, so it stays at Info alongside every other request.
func withLogging(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		level := slog.LevelInfo
		if r.URL.Path == "/healthz" && rec.status == http.StatusOK {
			level = slog.LevelDebug
		}
		logger.Log(r.Context(), level, "request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"dur", time.Since(start).String(),
		)
	})
}
