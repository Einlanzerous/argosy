package health

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestURLResolvesWildcardBinds(t *testing.T) {
	cases := []struct {
		name string
		addr string
		want string
	}{
		// The default from config.Load, and therefore the case that matters.
		{"bare port", ":8096", "http://127.0.0.1:8096/healthz"},
		{"explicit wildcard", "0.0.0.0:8096", "http://127.0.0.1:8096/healthz"},
		{"ipv6 wildcard", "[::]:8096", "http://127.0.0.1:8096/healthz"},
		{"explicit host", "127.0.0.1:9000", "http://127.0.0.1:9000/healthz"},
		{"named host", "localhost:8096", "http://localhost:8096/healthz"},
		// Neither is a legal ARGOSY_ADDR, but a probe that panics or builds a
		// nonsense URL on a typo is worse than one that tries the default.
		{"port only, no colon", "8096", "http://127.0.0.1:8096/healthz"},
		{"host only, no port", "argosy", "http://argosy:8096/healthz"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := URL(tc.addr); got != tc.want {
				t.Errorf("URL(%q) = %q, want %q", tc.addr, got, tc.want)
			}
		})
	}
}

func serve(t *testing.T, code int, body string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(code)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestProbeAcceptsOnlyAnOKAnswer(t *testing.T) {
	srv := serve(t, http.StatusOK, `{"status":"ok","version":"0.27.2","sha":null}`)

	rep, err := Probe(context.Background(), srv.Client(), srv.URL+"/healthz")
	if err != nil {
		t.Fatalf("Probe on a healthy server: %v", err)
	}
	if rep.Version != "0.27.2" {
		t.Errorf("version = %q, want 0.27.2 — the probe reports the build that answered", rep.Version)
	}
}

// The case the whole ticket is about: argosy's 503 branch really fires, and the
// probe has to vote unhealthy on it while still reading the identity off the
// degraded body (ARGY-213 puts it on both paths for exactly this moment).
func TestProbeRejectsDegraded(t *testing.T) {
	srv := serve(t, http.StatusServiceUnavailable, `{"status":"degraded","version":"0.27.2","sha":null}`)

	rep, err := Probe(context.Background(), srv.Client(), srv.URL+"/healthz")
	if err == nil {
		t.Fatal("Probe returned nil error for a 503 — a degraded database must read as unhealthy")
	}
	if !strings.Contains(err.Error(), "degraded") || !strings.Contains(err.Error(), "503") {
		t.Errorf("error = %q, want it to name both the 503 and the degraded status", err)
	}
	if rep.Version != "0.27.2" {
		t.Errorf("version = %q on the failing path, want 0.27.2", rep.Version)
	}
}

// Everything a probe cannot make sense of is unhealthy. This is the direction
// that matters: the failure mode worth engineering against is a check that
// exits 0 when it has learned nothing, not one that cries wolf.
func TestProbeFailsClosed(t *testing.T) {
	cases := []struct {
		name string
		code int
		body string
	}{
		{"200 with an empty body", http.StatusOK, ``},
		{"200 with HTML — a proxy or an SPA fallback answering", http.StatusOK, `<!doctype html>`},
		{"200 with the pre-ARGY-213 text/plain ok", http.StatusOK, `ok`},
		{"200 naming a status nobody has defined yet", http.StatusOK, `{"status":"starting"}`},
		{"200 with the status field missing entirely", http.StatusOK, `{"version":"0.27.2"}`},
		{"500 from something upstream", http.StatusInternalServerError, `oops`},
		{"404 — probing a path that moved", http.StatusNotFound, ``},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			srv := serve(t, tc.code, tc.body)
			if _, err := Probe(context.Background(), srv.Client(), srv.URL+"/healthz"); err == nil {
				t.Errorf("Probe returned healthy for %s — uncertainty must read as unhealthy", tc.name)
			}
		})
	}
}

// A dead process is the other half of what a healthcheck is for.
func TestProbeFailsOnRefusedConnection(t *testing.T) {
	srv := serve(t, http.StatusOK, `{"status":"ok"}`)
	url := srv.URL + "/healthz"
	srv.Close() // nothing listening now

	if _, err := Probe(context.Background(), nil, url); err == nil {
		t.Fatal("Probe returned healthy against a closed listener")
	}
}

// The deadline is the caller's, so a hung server cannot hang the probe past it.
func TestProbeHonoursContextDeadline(t *testing.T) {
	block := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		select {
		case <-block:
		case <-r.Context().Done():
		}
	}))
	t.Cleanup(func() { close(block); srv.Close() })

	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := Probe(ctx, srv.Client(), srv.URL+"/healthz"); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want it to wrap context.Canceled", err)
	}
}
