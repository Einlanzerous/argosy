// Command argosy is the single Argosy server binary: it serves the JSON API,
// streams media, and serves the embedded Vue web UI — all from one process.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/mediatool"
	"github.com/Einlanzerous/argosy/internal/server"
	"github.com/Einlanzerous/argosy/internal/version"
	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	cfg := config.Load()

	// Subcommands run and exit instead of serving.
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "scan":
			runScan(cfg, logger, os.Args[2:])
			return
		case "match":
			runMatch(cfg, logger, os.Args[2:])
			return
		}
	}

	logger.Info("starting argosy", "version", version.Version, "addr", cfg.Addr)

	// Best-effort: log the media toolchain so its absence is obvious at startup.
	mediatool.LogVersions(context.Background(), logger)

	var pool *pgxpool.Pool
	if cfg.DatabaseURL != "" {
		if err := db.Migrate(context.Background(), cfg.DatabaseURL); err != nil {
			logger.Error("database migration failed", "err", err)
			os.Exit(1)
		}
		p, err := db.Open(context.Background(), cfg.DatabaseURL)
		if err != nil {
			logger.Error("database connection failed", "err", err)
			os.Exit(1)
		}
		pool = p
		defer pool.Close()
		logger.Info("database connected and migrated")

		if cfg.AdminUsername != "" && cfg.AdminPassword != "" {
			store := auth.NewStore(pool)
			switch exists, err := store.AccountExists(context.Background(), cfg.AdminUsername); {
			case err != nil:
				logger.Error("admin bootstrap check failed", "err", err)
			case exists:
				// already provisioned
			default:
				if _, err := store.CreateAccount(context.Background(), cfg.AdminUsername, cfg.AdminPassword, cfg.AdminUsername); err != nil {
					logger.Error("admin bootstrap failed", "err", err)
				} else {
					logger.Info("bootstrapped admin account", "username", cfg.AdminUsername)
				}
			}
		}
	} else {
		logger.Warn("no database configured; set ARGOSY_DATABASE_URL or ARGOSY_DB_HOST")
	}

	srv, err := server.New(cfg, logger, pool)
	if err != nil {
		logger.Error("failed to build server", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		logger.Info("listening", "addr", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server error", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	logger.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("graceful shutdown failed", "err", err)
		os.Exit(1)
	}
	logger.Info("stopped")
}
