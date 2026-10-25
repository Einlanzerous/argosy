package server

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/auth"
)

// ARGY-262: every request line says who, from which client, with a request id
// that is also echoed to the caller; unauthenticated requests log device=-.
func TestWithLoggingIdentity(t *testing.T) {
	run := func(mutate func(*http.Request), handler http.HandlerFunc) (string, *httptest.ResponseRecorder) {
		var buf bytes.Buffer
		logger := slog.New(slog.NewTextHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo}))
		rr := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/api/v1/items", nil)
		mutate(req)
		withLogging(logger, handler).ServeHTTP(rr, req)
		return buf.String(), rr
	}

	t.Run("authenticated", func(t *testing.T) {
		ua := "Mozilla/5.0 " + strings.Repeat("x", 200)
		out, rr := run(func(r *http.Request) {
			r.Header.Set("User-Agent", ua)
			r.Header.Set(auth.ClientHeader, "argosy-web/dev")
		}, func(_ http.ResponseWriter, r *http.Request) {
			// Stand-in for auth resolving the bearer token.
			auth.TraceFromContext(r.Context()).SetIdentity("acct0001-the-rest-is-hidden", "device-one", "Living Room TV")
		})
		for _, want := range []string{`device="Living Room TV"`, "account=acct0001", "client=argosy-web/dev", "method=GET"} {
			if !strings.Contains(out, want) {
				t.Errorf("log missing %s: %s", want, out)
			}
		}
		if strings.Contains(out, "the-rest-is-hidden") {
			t.Errorf("full account id leaked: %s", out)
		}
		if strings.Contains(out, strings.Repeat("x", 100)) {
			t.Errorf("UA was not trimmed: %s", out)
		}
		id := rr.Header().Get("X-Request-Id")
		if len(id) != 8 || !strings.Contains(out, "req="+id) {
			t.Errorf("request id %q not echoed in log: %s", id, out)
		}
	})

	t.Run("unauthenticated", func(t *testing.T) {
		out, rr := run(func(*http.Request) {}, func(http.ResponseWriter, *http.Request) {})
		for _, want := range []string{"device=-", "account=-", "client=-", "ua=-"} {
			if !strings.Contains(out, want) {
				t.Errorf("log missing %s: %s", want, out)
			}
		}
		if rr.Header().Get("X-Request-Id") == "" {
			t.Error("no X-Request-Id on an unauthenticated response")
		}
	})
}
