package library

import (
	"context"
	"errors"
	"strconv"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ownerAccountID returns the account that owns this instance — the one whose
// libraries every client browses (ARGY-167). Media fixtures must hang off it: a
// library parked under a fresh unrelated account is invisible to the handlers by
// design, which is the whole point of the ticket. Claims ownership for a new
// account when the test database has none yet (a fresh CI database), retrying
// once in case a sibling package won the claim concurrently.
func ownerAccountID(ctx context.Context, t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	for range 2 {
		var id string
		err := pool.QueryRow(ctx, `SELECT id::text FROM accounts WHERE is_owner LIMIT 1`).Scan(&id)
		if err == nil {
			return id
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			t.Fatalf("look up owner account: %v", err)
		}
		suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
		var fresh string
		if err := pool.QueryRow(ctx,
			`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "owner_"+suffix).Scan(&fresh); err != nil {
			t.Fatalf("create owner account: %v", err)
		}
		// A concurrent claim loses to accounts_single_owner; the next pass reads
		// whichever account actually won.
		_, _ = pool.Exec(ctx,
			`UPDATE accounts SET is_owner = true
			 WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM accounts WHERE is_owner)`, fresh)
	}
	t.Fatal("could not resolve an instance-owner account")
	return ""
}
