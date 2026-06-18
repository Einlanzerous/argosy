// Package server wires the Argosy HTTP server: JSON API, health checks, and the
// embedded single-page web UI, all served from one mux on one origin.
package server

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/version"
	"github.com/jackc/pgx/v5/pgxpool"
)

// New builds the HTTP server. Routes here are deliberately minimal — the real
// API surface is generated from the OpenAPI spec in a later Phase 0 ticket.
// pool may be nil when no database is configured.
func New(cfg config.Config, logger *slog.Logger, pool *pgxpool.Pool) (*http.Server, error) {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", healthHandler(pool))
	mux.HandleFunc("GET /api/v1/ping", handlePing)

	// The auth surface needs a database; without one the server is read-only.
	if pool != nil {
		auth.RegisterRoutes(mux, auth.NewStore(pool))
	}

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

// healthHandler reports readiness. When a database is configured, it pings it
// and returns 503 if it's unreachable.
func healthHandler(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if pool != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()
			if err := pool.Ping(ctx); err != nil {
				http.Error(w, "database unavailable", http.StatusServiceUnavailable)
				return
			}
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}
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
