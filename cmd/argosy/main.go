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

	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/mediatool"
	"github.com/Einlanzerous/argosy/internal/server"
	"github.com/Einlanzerous/argosy/internal/version"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	cfg := config.Load()
	logger.Info("starting argosy", "version", version.Version, "addr", cfg.Addr)

	// Best-effort: log the media toolchain so its absence is obvious at startup.
	mediatool.LogVersions(context.Background(), logger)

	srv, err := server.New(cfg, logger)
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
