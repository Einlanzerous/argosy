package main

import (
	"context"
	"flag"
	"log/slog"
	"os"

	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/Einlanzerous/argosy/internal/stevedore"
)

// runMatch implements `argosy match [-library <name>] [-force]`: it enriches
// movies and series with TMDB metadata + artwork.
func runMatch(cfg config.Config, logger *slog.Logger, args []string) {
	fset := flag.NewFlagSet("match", flag.ExitOnError)
	force := fset.Bool("force", false, "re-match items that already have a tmdb_id")
	library := fset.String("library", "", "library name (default: all libraries)")
	_ = fset.Parse(args)

	if cfg.DatabaseURL == "" {
		logger.Error("no database configured")
		os.Exit(1)
	}
	provider := metadata.NewTMDB(cfg.TMDBReadToken, cfg.TMDBAPIKey)
	if !provider.Configured() {
		logger.Error("no TMDB credentials (set TMDB_API_READ_ACCESS_KEY or TMDB_API_KEY)")
		os.Exit(1)
	}

	ctx := context.Background()
	if err := db.Migrate(ctx, cfg.DatabaseURL); err != nil {
		logger.Error("migrate failed", "err", err)
		os.Exit(1)
	}
	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("database connection failed", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	var accountID string
	if err := pool.QueryRow(ctx, `SELECT id::text FROM accounts ORDER BY created_at LIMIT 1`).Scan(&accountID); err != nil {
		logger.Error("no account found", "err", err)
		os.Exit(1)
	}

	query := `SELECT id::text, name FROM libraries WHERE account_id = $1`
	qargs := []any{accountID}
	if *library != "" {
		query += ` AND name = $2`
		qargs = append(qargs, *library)
	}
	rows, err := pool.Query(ctx, query, qargs...)
	if err != nil {
		logger.Error("list libraries failed", "err", err)
		os.Exit(1)
	}
	type lib struct{ id, name string }
	var libs []lib
	for rows.Next() {
		var l lib
		if err := rows.Scan(&l.id, &l.name); err != nil {
			rows.Close()
			logger.Error("scan library failed", "err", err)
			os.Exit(1)
		}
		libs = append(libs, l)
	}
	rows.Close()

	matcher := stevedore.NewMatcher(pool, provider, cfg.ArtworkDir, logger)
	for _, l := range libs {
		res, err := matcher.MatchLibrary(ctx, l.id, *force)
		if err != nil {
			logger.Error("match failed", "library", l.name, "err", err)
			os.Exit(1)
		}
		logger.Info("match complete", "library", l.name, "movies", res.Movies, "series", res.Series, "episodes", res.Episodes, "credits", res.Credits, "misses", res.Misses)
	}
}
