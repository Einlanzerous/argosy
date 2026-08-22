package server

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/beacon"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/transcode"
)

func TestHandlePing(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/ping", nil)
	rec := httptest.NewRecorder()

	handlePing(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body["service"] != "argosy" {
		t.Errorf("service = %q, want %q", body["service"], "argosy")
	}
	if body["status"] != "ok" {
		t.Errorf("status = %q, want %q", body["status"], "ok")
	}
}

func TestHealthHandlerNoDB(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	// nil pool => no database configured => always healthy.
	healthHandler(nil)(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if rec.Body.String() != "ok" {
		t.Errorf("body = %q, want %q", rec.Body.String(), "ok")
	}
}

// TestShutdownDrainsBeaconHub guards the wiring, not the primitive: New must
// hand hub.Close to RegisterOnShutdown, or Beacon streams never learn the
// server is stopping and Shutdown burns its full deadline (ARGY-194). Easy to
// drop by accident when the http.Server literal is next edited.
func TestShutdownDrainsBeaconHub(t *testing.T) {
	hub := beacon.NewHub(nil, slog.New(slog.NewTextHandler(io.Discard, nil)))

	srv, err := New(config.Config{}, slog.New(slog.NewTextHandler(io.Discard, nil)),
		nil, nil, nil, transcode.Capabilities{}, "", nil, nil, nil, hub, nil)
	if err != nil {
		t.Fatalf("New: %v", err)
	}

	select {
	case <-hub.Drain():
		t.Fatal("hub drained before Shutdown was called")
	default:
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		t.Fatalf("Shutdown: %v", err)
	}

	select {
	case <-hub.Drain():
	case <-time.After(5 * time.Second):
		t.Fatal("Shutdown did not drain the hub — the RegisterOnShutdown hook is missing")
	}
}
