package library

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestPlayStateLifecycle(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run play-state tests")
	}
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	store := NewStore(pool, "/artwork")

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, userID, libID, itemID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ps_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Film',$2) RETURNING id::text`,
		libID, "film-"+suffix+".mkv").Scan(&itemID); err != nil {
		t.Fatal(err)
	}
	dur := 1000.0

	// Fresh item: zero progress, not watched.
	if ps, err := store.GetProgress(ctx, accID, userID, itemID); err != nil || ps == nil || ps.PositionSeconds != 0 || ps.Watched {
		t.Fatalf("initial progress = %+v (err %v), want zero/unwatched", ps, err)
	}

	// Report 100s of 1000s → in progress.
	ps, err := store.SetProgress(ctx, accID, userID, itemID, 100, &dur)
	if err != nil || ps == nil || ps.PositionSeconds != 100 || ps.Watched {
		t.Fatalf("after 100s = %+v (err %v), want pos 100 / unwatched", ps, err)
	}

	// Shows up in Continue Watching with ~10%.
	cont, err := store.ContinueWatching(ctx, accID, userID, 20)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, c := range cont {
		if c.Id.String() == itemID {
			found = true
			if c.Percent < 9 || c.Percent > 11 {
				t.Errorf("percent = %v, want ~10", c.Percent)
			}
		}
	}
	if !found {
		t.Fatalf("item not in Continue Watching")
	}

	// Past the threshold → auto-watched, drops off the rail.
	if ps, err := store.SetProgress(ctx, accID, userID, itemID, 980, &dur); err != nil || ps == nil || !ps.Watched {
		t.Fatalf("after 980s = %+v (err %v), want watched", ps, err)
	}
	cont, _ = store.ContinueWatching(ctx, accID, userID, 20)
	for _, c := range cont {
		if c.Id.String() == itemID {
			t.Fatalf("watched item still in Continue Watching")
		}
	}

	// Explicit unwatch.
	if ps, err := store.SetWatched(ctx, accID, userID, itemID, false); err != nil || ps == nil || ps.Watched {
		t.Fatalf("after unwatch = %+v (err %v), want unwatched", ps, err)
	}

	// Cross-account isolation: a different account can't touch this item.
	var otherAcc string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "psother_"+suffix).Scan(&otherAcc); err != nil {
		t.Fatal(err)
	}
	if ps, err := store.GetProgress(ctx, otherAcc, userID, itemID); err != nil || ps != nil {
		t.Fatalf("cross-account GetProgress = %+v (err %v), want nil", ps, err)
	}
}
