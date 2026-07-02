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

// TestBulkWatched covers ARGY-109's season/series bulk marking: marking a season
// watched flips every episode's backing file (deduping combined rips), leaves
// other seasons untouched, drops the marked episodes off Continue Watching, and
// unwatching clears the flag again. Series-level marking spans all seasons.
func TestBulkWatched(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run bulk-watched tests")
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
	var accID, userID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "bw_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// Series with two seasons. Season 1 has a combined rip (E1+E2 share one file)
	// plus a standalone E3; season 2 has a single episode.
	var seriesID, s1, s2, combined, ep3, s2ep string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Show','show') RETURNING id::text`, libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&s1); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,2) RETURNING id::text`, seriesID).Scan(&s2); err != nil {
		t.Fatal(err)
	}
	mk := func(title string) string {
		var id string
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
			libID, title, title+"-"+suffix+".mkv").Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	combined, ep3, s2ep = mk("S01E01E02"), mk("S01E03"), mk("S02E01")
	// E1 and E2 both point at the combined file.
	if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id) VALUES ($1,1,$2),($1,2,$2),($1,3,$3)`, s1, combined, ep3); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id) VALUES ($1,1,$2)`, s2, s2ep); err != nil {
		t.Fatal(err)
	}

	watched := func(itemID string) bool {
		ps, err := store.GetProgress(ctx, accID, userID, itemID)
		if err != nil || ps == nil {
			t.Fatalf("GetProgress(%s) = %+v (err %v)", itemID, ps, err)
		}
		return ps.Watched
	}

	// Mark season 1 watched. The combined file counts once → 2 files (combined, ep3).
	res, err := store.SetSeasonWatched(ctx, accID, userID, s1, true)
	if err != nil || res == nil {
		t.Fatalf("SetSeasonWatched = %+v (err %v)", res, err)
	}
	if res.Updated != 2 {
		t.Errorf("season-1 updated = %d, want 2 (combined rip deduped)", res.Updated)
	}
	if !watched(combined) || !watched(ep3) {
		t.Errorf("season-1 episodes not watched after bulk mark")
	}
	if watched(s2ep) {
		t.Errorf("season-2 episode watched by a season-1 mark")
	}

	// Series-level unwatch clears every season.
	res, err = store.SetSeriesWatched(ctx, accID, userID, seriesID, false)
	if err != nil || res == nil {
		t.Fatalf("SetSeriesWatched = %+v (err %v)", res, err)
	}
	if res.Updated != 3 {
		t.Errorf("series updated = %d, want 3 (combined + ep3 + s2ep)", res.Updated)
	}
	if watched(combined) || watched(ep3) || watched(s2ep) {
		t.Errorf("episodes still watched after series unwatch")
	}

	// Cross-account isolation: another account can't bulk-mark this series/season.
	var otherAcc string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "bwother_"+suffix).Scan(&otherAcc); err != nil {
		t.Fatal(err)
	}
	if res, err := store.SetSeriesWatched(ctx, otherAcc, userID, seriesID, true); err != nil || res != nil {
		t.Fatalf("cross-account SetSeriesWatched = %+v (err %v), want nil (404)", res, err)
	}
	if res, err := store.SetSeasonWatched(ctx, otherAcc, userID, s1, true); err != nil || res != nil {
		t.Fatalf("cross-account SetSeasonWatched = %+v (err %v), want nil (404)", res, err)
	}
}
