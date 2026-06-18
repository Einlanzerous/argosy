package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"os"

	"github.com/Einlanzerous/argosy/internal/config"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/mediasource"
	"github.com/Einlanzerous/argosy/internal/stevedore"
	"github.com/jackc/pgx/v5"
)

// runScan implements `argosy scan -name <name> -path <dir>`: it ensures a
// library exists under the (first) account and ingests its files. This is the
// manual trigger until the live file-watch lands in ARGY-15.
func runScan(cfg config.Config, logger *slog.Logger, args []string) {
	fset := flag.NewFlagSet("scan", flag.ExitOnError)
	name := fset.String("name", "", "library name")
	root := fset.String("path", "", "library root directory")
	kind := fset.String("kind", "mixed", "library kind: movie|show|mixed")
	_ = fset.Parse(args)

	if *name == "" || *root == "" {
		logger.Error("scan requires -name and -path")
		os.Exit(2)
	}
	if cfg.DatabaseURL == "" {
		logger.Error("no database configured (set ARGOSY_DATABASE_URL or ARGOSY_DB_HOST)")
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
		logger.Error("no account found; bootstrap one with ARGOSY_ADMIN_USERNAME/PASSWORD first", "err", err)
		os.Exit(1)
	}

	var libraryID string
	err = pool.QueryRow(ctx,
		`SELECT id::text FROM libraries WHERE account_id = $1 AND root_path = $2`, accountID, *root).Scan(&libraryID)
	if errors.Is(err, pgx.ErrNoRows) {
		err = pool.QueryRow(ctx,
			`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1, $2, $3, $4) RETURNING id::text`,
			accountID, *name, *kind, *root).Scan(&libraryID)
	}
	if err != nil {
		logger.Error("resolve library failed", "err", err)
		os.Exit(1)
	}

	res, err := stevedore.NewScanner(pool, logger).Scan(ctx, libraryID, mediasource.NewLocalFS(*root))
	if err != nil {
		logger.Error("scan failed", "err", err)
		os.Exit(1)
	}
	logger.Info("scan complete", "library", *name, "scanned", res.Scanned, "errors", res.Errors)
}
