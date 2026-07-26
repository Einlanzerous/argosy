// Package testdb centralizes access to the integration-test database so every
// DB-backed test goes through the same safety check.
package testdb

import (
	"os"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
)

// DSN returns ARGOSY_TEST_DATABASE_URL, skipping the test when it is unset.
// It refuses — fails, not skips — any database whose name does not end in
// "_test": the suites seed throwaway accounts and media rows, and a stray env
// var once left ~50 test_* accounts in the dev database (ARGY-169).
func DSN(t testing.TB) string {
	t.Helper()
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run DB-backed tests")
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		t.Fatalf("testdb: parse ARGOSY_TEST_DATABASE_URL: %v", err)
	}
	if !strings.HasSuffix(cfg.Database, "_test") {
		t.Fatalf("testdb: refusing to run against database %q — ARGOSY_TEST_DATABASE_URL must name a *_test database", cfg.Database)
	}
	return dsn
}
