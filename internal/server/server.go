// Package server wires the Argosy HTTP server: JSON API, health checks, and the
// embedded single-page web UI, all served from one mux on one origin.
package server

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/version"
)

// New builds the HTTP server. Routes here are deliberately minimal — the real
// API surface is generated from the OpenAPI spec in a later Phase 0 ticket.
func New(cfg config.Config, logger *slog.Logger) (*http.Server, error) {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", handleHealth)
	mux.HandleFunc("GET /api/v1/ping", handlePing)

	spa, err := newSPAHandler()
	if err != nil {
		return nil, err
	}
	mux.Handle("/", spa)

	return &http.Server{
		Addr:              cfg.Addr,
		Handler:           withLogging(logger, mux),
		ReadHeaderTimeout: 10 * time.Second,
	}, nil
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte("ok"))
}

func handlePing(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"service": "argosy",
		"status":  "ok",
		"version": version.Version,
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
