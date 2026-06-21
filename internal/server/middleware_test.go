package server

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

// flushRecorder is an httptest.ResponseRecorder that also records Flush calls,
// so we can prove the logging wrapper forwards flushing rather than swallowing it.
type flushRecorder struct {
	*httptest.ResponseRecorder
	flushed bool
}

func (f *flushRecorder) Flush() { f.flushed = true }

// The request-logging wrapper must preserve http.Flusher — Beacon's SSE handler
// does `w.(http.Flusher)`, so a wrapper that hides it turns the stream into a 500.
func TestWithLoggingPreservesFlusher(t *testing.T) {
	fr := &flushRecorder{ResponseRecorder: httptest.NewRecorder()}

	handler := withLogging(slog.New(slog.NewTextHandler(io.Discard, nil)),
		http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			f, ok := w.(http.Flusher)
			if !ok {
				t.Error("handler did not receive an http.Flusher through withLogging")
				return
			}
			w.WriteHeader(http.StatusOK)
			f.Flush()
		}))

	handler.ServeHTTP(fr, httptest.NewRequest(http.MethodGet, "/api/v1/beacon", nil))

	if !fr.flushed {
		t.Error("Flush did not reach the underlying ResponseWriter")
	}
}
