package library

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

// TestUnwatchPositionRules covers ARGY-322: a season or series unwatch clears
// saved positions, while a single-episode unwatch keeps its own.
func TestUnwatchPositionRules(t *testing.T) {
	dsn := testdb.DSN(t)
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
	var accID, userID, libID, seriesID, seasonID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "unw_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "unwlib_"+suffix, "/tmp/unw"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,$2,$2) RETURNING id::text`, libID, "Unw "+suffix).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	items := make([]string, 2)
	for i := range items {
		n := strconv.Itoa(i)
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
			libID, "E"+n, "unw-"+suffix+"-"+n+".mkv").Scan(&items[i]); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,'e')`, seasonID, i+1, items[i]); err != nil {
			t.Fatal(err)
		}
	}
	pos := func(item string) int {
		t.Helper()
		var p int
		if err := pool.QueryRow(ctx, `SELECT position_seconds FROM play_state WHERE user_id=$1 AND media_item_id=$2`, userID, item).Scan(&p); err != nil {
			t.Fatal(err)
		}
		return p
	}
	seed := func() {
		t.Helper()
		for _, it := range items {
			if _, err := store.SetProgress(ctx, accID, userID, "", it, 13, nil); err != nil {
				t.Fatal(err)
			}
		}
	}

	// Single-episode unwatch keeps the position.
	seed()
	if _, err := store.SetWatched(ctx, accID, userID, items[0], false); err != nil {
		t.Fatal(err)
	}
	if got := pos(items[0]); got != 13 {
		t.Errorf("single unwatch position = %d, want 13", got)
	}

	// Bulk mark-watched keeps positions; season unwatch resets them.
	if _, err := store.SetSeasonWatched(ctx, accID, userID, seasonID, true); err != nil {
		t.Fatal(err)
	}
	if got := pos(items[1]); got != 13 {
		t.Errorf("season watch position = %d, want 13", got)
	}
	if _, err := store.SetSeasonWatched(ctx, accID, userID, seasonID, false); err != nil {
		t.Fatal(err)
	}
	for _, it := range items {
		if got := pos(it); got != 0 {
			t.Errorf("season unwatch position = %d, want 0", got)
		}
	}

	// Series unwatch resets too.
	seed()
	if _, err := store.SetSeriesWatched(ctx, accID, userID, seriesID, false); err != nil {
		t.Fatal(err)
	}
	for _, it := range items {
		if got := pos(it); got != 0 {
			t.Errorf("series unwatch position = %d, want 0", got)
		}
	}
}
