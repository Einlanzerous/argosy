package server

import (
	"bytes"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
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

// ARGY-216: the container probes /healthz every 30s and the delivery reconciler
// polls it too, so a successful health check must not be an Info line — but the
// degraded answer, the one worth finding in `docker logs`, must still be one.
func TestHealthzLoggingIsQuietOnlyWhenHealthy(t *testing.T) {
	cases := []struct {
		name      string
		path      string
		status    int
		wantQuiet bool
	}{
		{"healthy probe is demoted", "/healthz", http.StatusOK, true},
		{"degraded health stays visible", "/healthz", http.StatusServiceUnavailable, false},
		{"ordinary traffic is untouched", "/api/v1/ping", http.StatusOK, false},
		{"a 200 elsewhere is untouched", "/artwork/x.jpg", http.StatusOK, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var buf bytes.Buffer
			// Info threshold: a demoted line is simply absent.
			logger := slog.New(slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo}))
			h := withLogging(logger, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
				w.WriteHeader(tc.status)
			}))
			h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, tc.path, nil))

			logged := strings.Contains(buf.String(), tc.path)
			if tc.wantQuiet && logged {
				t.Errorf("%s %d was logged at Info: %s", tc.path, tc.status, buf.String())
			}
			if !tc.wantQuiet && !logged {
				t.Errorf("%s %d was NOT logged at Info; it must stay visible", tc.path, tc.status)
			}
		})
	}
}
