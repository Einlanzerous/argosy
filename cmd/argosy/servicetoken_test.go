package main

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ARGY-325: mint shows the plaintext once, list never shows it or a hash, and
// revoke works by id and by label.
func TestServiceTokenCLI(t *testing.T) {
	dsn := testdb.DSN(t)
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	store := auth.NewStore(pool)
	run := func(args ...string) (string, error) {
		var out bytes.Buffer
		err := serviceTokenCmd(ctx, store, &out, "tester", args)
		return out.String(), err
	}

	out, err := run("mint", "-label", "cli-test", "-scope", "sessions:summary")
	if err != nil {
		t.Fatal(err)
	}
	var token string
	for _, line := range strings.Split(out, "\n") {
		if v, ok := strings.CutPrefix(line, "token: "); ok {
			token = v
		}
	}
	if !strings.HasPrefix(token, "ags_") {
		t.Fatalf("mint did not print a token: %q", out)
	}

	if _, err := run("mint", "-label", "cli-test", "-scope", "everything"); err == nil {
		t.Error("an unknown scope must be rejected")
	}

	listing, err := run("list")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(listing, token) || strings.Contains(listing, "token_hash") {
		t.Error("list leaked the token")
	}
	var hash string
	if err := pool.QueryRow(ctx, `SELECT token_hash FROM service_tokens WHERE consumer_label = 'cli-test' ORDER BY created_at DESC LIMIT 1`).Scan(&hash); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(listing, hash) {
		t.Error("list leaked a token hash")
	}
	for _, col := range []string{"ID", "LABEL", "SCOPE", "CREATED", "LAST USED", "REVOKED"} {
		if !strings.Contains(listing, col) {
			t.Errorf("list header lacks %s", col)
		}
	}

	if out, err = run("revoke", "-label", "cli-test"); err != nil || !strings.Contains(out, "revoked ") {
		t.Fatalf("revoke by label: %q %v", out, err)
	}
	if _, err := run("revoke", "-label", "cli-test"); err == nil {
		t.Error("revoking with nothing live must fail, not report success")
	}
	if _, err := run("bogus"); err == nil {
		t.Error("an unknown subcommand must fail")
	}
}
