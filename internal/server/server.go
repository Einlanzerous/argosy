// Package server wires the Argosy HTTP server: JSON API, health checks, and the
// embedded single-page web UI, all served from one mux on one origin.
package server

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/ballast"
	"github.com/Einlanzerous/argosy/internal/beacon"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/library"
	"github.com/Einlanzerous/argosy/internal/presence"
	"github.com/Einlanzerous/argosy/internal/stevedore"
	"github.com/Einlanzerous/argosy/internal/stow"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/Einlanzerous/argosy/internal/version"
	"github.com/jackc/pgx/v5/pgxpool"
)

// New builds the HTTP server. Routes here are deliberately minimal — the real
// API surface is generated from the OpenAPI spec in a later Phase 0 ticket.
// pool may be nil when no database is configured; scheduler may be nil to
// disable the scan trigger/status endpoints.
func New(cfg config.Config, logger *slog.Logger, pool *pgxpool.Pool, scheduler *stevedore.Scheduler, tc *transcode.Manager, caps transcode.Capabilities, encoder string, sweeper *ballast.Sweeper, subs *subtitle.Service, pres *presence.Registry, hub *beacon.Hub, stowMgr *stow.Manager) (*http.Server, error) {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", healthHandler(pool))
	mux.HandleFunc("GET /api/v1/ping", handlePing)

	// The auth + browse surfaces need a database.
	if pool != nil {
		authStore := auth.NewStore(pool)
		auth.RegisterRoutes(mux, authStore)
		if cfg.ProvisionToken != "" {
			auth.RegisterProvisioning(mux, authStore, cfg.ProvisionToken)
		}
		library.RegisterRoutes(mux, pool, authStore, cfg.ArtworkDir, "/artwork", logger, tc, caps, encoder, sweeper, subs, pres, hub, cfg.PreferredLanguages, stowMgr, cfg.StowPassthroughMax)

		if scheduler != nil {
			mw := auth.Middleware(authStore)
			sh := &scanHandlers{sched: scheduler}
			// Triggering a re-scan re-reads the server's media roots, so it belongs
			// to the instance owner rather than to any household admin (ARGY-167).
			// Scan status names those roots, so it is owner-only too — a member has
			// no reason to see the server's library layout.
			mux.Handle("POST /api/v1/scan", mw(auth.RequireOwner(http.HandlerFunc(sh.trigger))))
			mux.Handle("GET /api/v1/scan/status", mw(auth.RequireOwner(http.HandlerFunc(sh.status))))
		}
	}

	spa, err := newSPAHandler()
	if err != nil {
		return nil, err
	}
	mux.Handle("/", spa)

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           withLogging(logger, mux),
		ReadHeaderTimeout: 10 * time.Second,
	}
	// Beacon streams are long-lived and therefore never idle, and Shutdown waits
	// for idle without cancelling request contexts — so without this a single
	// connected client held every shutdown to its full deadline (ARGY-194). The
	// hook runs at the *start* of Shutdown, which is exactly when the streams
	// need to be told to unwind.
	if hub != nil {
		srv.RegisterOnShutdown(hub.Close)
	}
	return srv, nil
}

// healthResponse is the body of `GET /healthz`, identical on the 200 and the
// 503 path.
//
// ── Why this stopped being text/plain (ARGY-213) ───────────────────────────
//
// Switchyard's delivery reconciler polls this endpoint and records what is
// actually running — the observed half of the estate's delivery ledger (SWY-192
// defines the contract; SERV-128 owns the rollout). It answered `ok` as
// text/plain, which the reconciler reads as "answered, reports no version": not
// a failure, but nothing it can record either. Its health-contract.ts names
// argosy explicitly as the reference case for that state.
//
// The identity rides BOTH branches, and argosy is the estate's clearest example
// of why the contract insists on that. This endpoint really does go 503 when
// Postgres is unreachable, and that is precisely the moment someone wants to
// know which build is running. /api/v1/ping has no 503 path at all, so pointing
// the ledger there instead — the cheaper option — would have reported a green
// identity for a service whose database was down.
//
//	version  bare semver ("0.25.1") or the literal "dev". Never a "v" prefix —
//	         compared with strict equality against the image's
//	         org.opencontainers.image.version label, which is stamped bare.
//	sha      the full 40-char commit, or JSON null. Never abbreviated.
type healthResponse struct {
	Status  string  `json:"status"`
	Version string  `json:"version"`
	SHA     *string `json:"sha"`
}

// healthHandler reports readiness and build identity. When a database is
// configured, it pings it and returns 503 if it's unreachable — with the same
// body shape, so the version stays readable on the failing path.
func healthHandler(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := version.Get()
		body := healthResponse{Status: "ok", Version: id.Version, SHA: id.SHA}

		if pool != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			defer cancel()
			if err := pool.Ping(ctx); err != nil {
				body.Status = "degraded"
				httpx.JSON(w, http.StatusServiceUnavailable, body)
				return
			}
		}
		httpx.JSON(w, http.StatusOK, body)
	}
}

func handlePing(w http.ResponseWriter, _ *http.Request) {
	httpx.JSON(w, http.StatusOK, map[string]string{
		"service": "argosy",
		"status":  "ok",
		"version": version.Get().Version,
	})
}
