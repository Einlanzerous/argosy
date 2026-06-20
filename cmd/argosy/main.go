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
	"github.com/Einlanzerous/argosy/internal/ballast"
	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/mediatool"
	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/Einlanzerous/argosy/internal/presence"
	"github.com/Einlanzerous/argosy/internal/server"
	"github.com/Einlanzerous/argosy/internal/stevedore"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/Einlanzerous/argosy/internal/transcode"
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

	// Stevedore's scan scheduler keeps the Manifest current; it also backs the
	// scan trigger/status API. Only available with a database.
	var scheduler *stevedore.Scheduler
	if pool != nil {
		var provider metadata.Provider
		if tmdb := metadata.NewTMDB(cfg.TMDBReadToken, cfg.TMDBAPIKey); tmdb.Configured() {
			provider = tmdb
		}
		scheduler = stevedore.NewScheduler(pool, logger, cfg.ArtworkDir, provider, cfg.ScanInterval)
	}

	// The Helm: transcode session orchestration. Only with a database (it serves
	// authenticated, account-scoped items).
	var tcManager *transcode.Manager
	var caps transcode.Capabilities
	// The probe reports what hardware is available (QSV/VAAPI/NVENC + software)
	// and selects by preference order; encoding resolves that to the backend
	// actually wired up. An unknown selection degrades to software. "selected"
	// vs "encoding" in the log make that explicit.
	encoder := transcode.EncoderSoftware
	if pool != nil {
		// Per-host VAAPI GPU override (e.g. /dev/dri/renderD129 for a discrete card).
		if dev := os.Getenv("ARGOSY_VAAPI_DEVICE"); dev != "" {
			transcode.VAAPIDevice = dev
		}
		caps = transcode.Probe(context.Background(), "", cfg.EncoderPreference)
		if cfg.ForceSoftware {
			caps.Selected = transcode.EncoderSoftware
		}
		encoder = transcode.ResolvedEncoder(caps.Selected)
		tcManager = transcode.NewManager(transcode.LocalFFmpeg{}, cfg.TranscodeDir, cfg.TranscodeIdleTimeout, cfg.MaxTranscodeSessions, logger)
		logger.Info("transcode ready", "available", caps.Available, "selected", caps.Selected, "encoding", encoder, "workDir", cfg.TranscodeDir)
	}

	// Ballast: keep the transcode cache within budget and reclaim orphans.
	var sweeper *ballast.Sweeper
	if tcManager != nil {
		budget := cfg.TranscodeCacheBudget
		if budget == 0 {
			budget = 10 << 30 // 10 GiB default high-water mark
		}
		sweeper = ballast.NewSweeper(cfg.TranscodeDir, budget, cfg.TranscodeIdleTimeout, tcManager, logger)
	}

	// Subtitle pipeline: embedded text tracks + OpenSubtitles, served as WebVTT.
	var subs *subtitle.Service
	if pool != nil {
		osClient := subtitle.NewOpenSubtitles(cfg.OpenSubtitlesAPIKey, cfg.OpenSubtitlesUsername, cfg.OpenSubtitlesPassword)
		if osClient.Configured() {
			logger.Info("subtitles: OpenSubtitles enabled", "langs", cfg.SubtitleLanguages)
		} else if cfg.OpenSubtitlesAPIKey != "" {
			logger.Warn("subtitles: OpenSubtitles disabled — needs OPEN_SUBTITLES_USERNAME + OPEN_SUBTITLES_PASSWORD (download is quota'd per user)")
		}
		subs = subtitle.NewService(osClient, cfg.SubtitleDir, cfg.SubtitleLanguages, logger)
	}

	// Presence: live playback sessions (who's watching what, where, now) — driven
	// by the progress heartbeat, reaped on idle (ARGY-34). Feeds resume + Beacon.
	var pres *presence.Registry
	if pool != nil {
		pres = presence.NewRegistry(0) // default TTL (~45s, a few missed beats)
	}

	srv, err := server.New(cfg, logger, pool, scheduler, tcManager, caps, encoder, sweeper, subs, pres)
	if err != nil {
		logger.Error("failed to build server", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if scheduler != nil {
		go scheduler.Run(ctx)
	}
	if tcManager != nil {
		go tcManager.Run(ctx)
	}
	if sweeper != nil {
		go sweeper.Run(ctx)
	}
	if pres != nil {
		go pres.Run(ctx)
	}

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
