package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/config"
)

// A container serving with no database configured answers /healthz with a
// perfectly healthy 200 — healthHandler skips the ping when there is no pool —
// while server.New has left the whole auth/library/browse surface unregistered.
// The probe has to refuse that, and it has to refuse it WITHOUT asking, which is
// what this pins: the endpoint below would answer "ok" if it were consulted.
func TestHealthcheckRefusesAConfiglessContainerWithoutProbing(t *testing.T) {
	probed := false
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		probed = true
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok","version":"0.27.2","sha":null}`))
	}))
	defer srv.Close()

	cfg := config.Config{Addr: strings.TrimPrefix(srv.URL, "http://"), DatabaseURL: ""}
	if code := runHealthcheck(cfg); code != 1 {
		t.Errorf("exit = %d, want 1 — a container with no database is not healthy", code)
	}
	if probed {
		t.Error("the probe was sent despite no database being configured; the config guard must short-circuit")
	}
}

// The guard must not swallow the normal path: with a database configured, the
// verdict comes from the endpoint as usual.
func TestHealthcheckProbesWhenADatabaseIsConfigured(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok","version":"0.27.2","sha":null}`))
	}))
	defer srv.Close()

	cfg := config.Config{
		Addr:        strings.TrimPrefix(srv.URL, "http://"),
		DatabaseURL: "postgres://argosy@db:5432/argosy?sslmode=disable",
	}
	if code := runHealthcheck(cfg); code != 0 {
		t.Errorf("exit = %d, want 0 — a configured, answering server is healthy", code)
	}
}

// And a configured database whose server is degraded still fails, so the new
// guard has not become the only thing that can fail.
func TestHealthcheckStillFailsOnDegraded(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`{"status":"degraded","version":"0.27.2","sha":null}`))
	}))
	defer srv.Close()

	cfg := config.Config{
		Addr:        strings.TrimPrefix(srv.URL, "http://"),
		DatabaseURL: "postgres://argosy@db:5432/argosy?sslmode=disable",
	}
	if code := runHealthcheck(cfg); code != 1 {
		t.Errorf("exit = %d, want 1 — a degraded database must still read as unhealthy", code)
	}
}
