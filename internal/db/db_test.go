package db

import (
	"context"
	"os"
	"testing"
)

// TestMigrate applies the schema against a real Postgres and checks the core
// invariants. It runs in CI (ARGOSY_TEST_DATABASE_URL points at the service)
// and is skipped locally when that variable is unset.
func TestMigrate(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run DB tests")
	}
	ctx := context.Background()

	if err := Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	// Idempotent: a second run is a no-op.
	if err := Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate (second run): %v", err)
	}

	pool, err := Open(ctx, dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer pool.Close()

	want := []string{
		"accounts", "users", "devices", "libraries", "media_items",
		"series", "seasons", "episodes", "play_state",
	}
	var count int
	if err := pool.QueryRow(ctx, `
		SELECT count(*) FROM information_schema.tables
		WHERE table_schema = 'public' AND table_name = ANY($1)`, want).Scan(&count); err != nil {
		t.Fatalf("count tables: %v", err)
	}
	if count != len(want) {
		t.Fatalf("expected %d core tables, found %d", len(want), count)
	}

	// play_state must be keyed on (user_id, media_item_id).
	var pk []string
	rows, err := pool.Query(ctx, `
		SELECT a.attname
		FROM pg_index i
		JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
		WHERE i.indrelid = 'play_state'::regclass AND i.indisprimary
		ORDER BY a.attname`)
	if err != nil {
		t.Fatalf("query pk: %v", err)
	}
	defer rows.Close()
	for rows.Next() {
		var col string
		if err := rows.Scan(&col); err != nil {
			t.Fatalf("scan: %v", err)
		}
		pk = append(pk, col)
	}
	if len(pk) != 2 || pk[0] != "media_item_id" || pk[1] != "user_id" {
		t.Fatalf("play_state PK = %v, want [media_item_id user_id]", pk)
	}
}
