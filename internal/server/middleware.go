package server

import (
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"

	"github.com/Einlanzerous/argosy/internal/auth"
)

// maxLoggedUA bounds the User-Agent written to the log.
const maxLoggedUA = 80

// requestID returns 8 hex chars, enough to quote from a client-side report.
func requestID() string {
	var b [4]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

func trimUA(ua string) string {
	ua = auth.SanitizeClient(ua)
	if ua == "" {
		return "-"
	}
	if len(ua) > maxLoggedUA {
		ua = ua[:maxLoggedUA]
	}
	return ua
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

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
// Each line carries who made it (ARGY-262): device, a short account id and the
// client build, resolved by the auth layer through a auth.Trace on the context
// and read after the handler returns. Emails never appear; the account is the
// first 8 characters of its id. Every response also gets an X-Request-Id, the
// same 8 hex chars as req=, so a client-side error report can quote it.
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
		reqID := requestID()
		w.Header().Set("X-Request-Id", reqID)
		trace := &auth.Trace{Client: auth.SanitizeClient(r.Header.Get(auth.ClientHeader))}
		r = r.WithContext(auth.WithTrace(r.Context(), trace))
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		level := slog.LevelInfo
		if r.URL.Path == "/healthz" && rec.status == http.StatusOK {
			level = slog.LevelDebug
		}
		accountID, _, _ := trace.Identity()
		device := auth.DeviceLabel(r.Context())
		account := "-"
		if accountID != "" {
			account = accountID[:min(8, len(accountID))]
		}
		logger.Log(r.Context(), level, "request",
			"req", reqID,
			"device", device,
			"account", account,
			"client", orDash(trace.Client),
			"ua", trimUA(r.Header.Get("User-Agent")),
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"dur", time.Since(start).String(),
		)
	})
}
