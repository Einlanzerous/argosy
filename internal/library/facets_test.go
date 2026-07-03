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

func TestFacets(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run facet store tests")
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

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "fa_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	n := 0
	mv := func(genres string) {
		t.Helper()
		n++
		if _, err := pool.Exec(ctx,
			`INSERT INTO media_items (library_id, kind, title, file_path, provider_metadata)
			 VALUES ($1,'movie','m',$2,$3::jsonb)`,
			libID, "m"+strconv.Itoa(n)+suffix, `{"genres":`+genres+`}`); err != nil {
			t.Fatal(err)
		}
	}
	mv(`["Action","Drama"]`)
	mv(`["Action"]`)

	// A series with a genre, plus an episode whose genres must NOT count.
	var seriesID, seasonID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, provider_metadata) VALUES ($1,'s',$2::jsonb) RETURNING id::text`,
		libID, `{"genres":["Drama"]}`).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	var epItem string
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','e',$2) RETURNING id::text`,
		libID, "ep"+suffix).Scan(&epItem); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id) VALUES ($1,1,$2)`, seasonID, epItem); err != nil {
		t.Fatal(err)
	}

	facets, err := NewStore(pool, "/artwork").Facets(ctx, accID, 20)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]int{}
	for _, f := range facets {
		got[string(f.Type)+":"+f.Value] = f.Count
	}
	// 2 movies + 1 series: Action on both movies (2), Drama on movie1 + series (2).
	want := map[string]int{"genre:Action": 2, "genre:Drama": 2}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("facet %s = %d, want %d (all: %v)", k, got[k], v, got)
		}
	}
	// Only genres are surfaced now — no tag facets.
	for k := range got {
		if len(k) >= 4 && k[:4] == "tag:" {
			t.Errorf("unexpected tag facet %q (all: %v)", k, got)
		}
	}
}
