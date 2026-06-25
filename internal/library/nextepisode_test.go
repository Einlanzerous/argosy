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

// TestNextEpisode covers series auto-advance's source of truth (ARGY-89): the
// next playable episode after a given one, across season boundaries, skipping
// episodes with no linked media file, and stopping at the end of the series.
func TestNextEpisode(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run next-episode store tests")
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
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ne_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// A media item; returns its id. linked=false leaves the episode without a file.
	mkItem := func(title string) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
			libID, title, title+suffix).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	var seriesID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,$2,$2) RETURNING id::text`, libID, "Show").Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	mkSeason := func(num int) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,$2) RETURNING id::text`, seriesID, num).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	mkEp := func(seasonID string, num int, mediaItem *string) {
		t.Helper()
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
			seasonID, num, mediaItem, "Ep "+strconv.Itoa(num)); err != nil {
			t.Fatal(err)
		}
	}

	// Season 1: E1, E2, E3 (E3 has no linked file).
	// Season 2: E1, then a COMBINED file backing E2+E3, then E4.
	s1 := mkSeason(1)
	s1e1, s1e2 := mkItem("S1E1"), mkItem("S1E2")
	s2 := mkSeason(2)
	s2e1 := mkItem("S2E1")
	s2combo := mkItem("S2E2-E3") // one file backs E2 and E3
	s2e4 := mkItem("S2E4")
	mkEp(s1, 1, &s1e1)
	mkEp(s1, 2, &s1e2)
	mkEp(s1, 3, nil) // unlinked: must be skipped, not returned
	mkEp(s2, 1, &s2e1)
	mkEp(s2, 2, &s2combo)
	mkEp(s2, 3, &s2combo) // same file as E2 — combined rip
	mkEp(s2, 4, &s2e4)

	store := NewStore(pool, "/artwork")

	// Mid-season: S1E1 → S1E2.
	next, err := store.NextEpisode(ctx, accID, s1e1)
	if err != nil {
		t.Fatal(err)
	}
	if next == nil || next.Id.String() != s1e2 {
		t.Fatalf("after S1E1 = %+v, want S1E2 %s", next, s1e2)
	}
	if next.SeasonNumber != 1 || next.EpisodeNumber != 2 {
		t.Errorf("after S1E1 got S%dE%d, want S1E2", next.SeasonNumber, next.EpisodeNumber)
	}

	// Season boundary: S1E2's next is S2E1 (the unlinked S1E3 is skipped).
	next, err = store.NextEpisode(ctx, accID, s1e2)
	if err != nil {
		t.Fatal(err)
	}
	if next == nil || next.Id.String() != s2e1 {
		t.Fatalf("after S1E2 = %+v, want S2E1 %s (skipping unlinked S1E3)", next, s2e1)
	}
	if next.SeasonNumber != 2 || next.EpisodeNumber != 1 {
		t.Errorf("after S1E2 got S%dE%d, want S2E1", next.SeasonNumber, next.EpisodeNumber)
	}

	// Into a combined rip: S2E1 → S2E2 (the combined file's first number).
	next, err = store.NextEpisode(ctx, accID, s2e1)
	if err != nil {
		t.Fatal(err)
	}
	if next == nil || next.Id.String() != s2combo {
		t.Fatalf("after S2E1 = %+v, want combined S2E2 %s", next, s2combo)
	}

	// Out of a combined rip: finishing S2E2-E3 advances to S2E4, NOT back to E3
	// (the same file — that would replay-loop). Regression for ARGY-69 auto-advance.
	next, err = store.NextEpisode(ctx, accID, s2combo)
	if err != nil {
		t.Fatal(err)
	}
	if next == nil || next.Id.String() != s2e4 {
		t.Fatalf("after combined S2E2-E3 = %+v, want S2E4 %s (not a replay of the combined file)", next, s2e4)
	}
	if next.SeasonNumber != 2 || next.EpisodeNumber != 4 {
		t.Errorf("after combined got S%dE%d, want S2E4", next.SeasonNumber, next.EpisodeNumber)
	}

	// Last episode of the series: nothing after S2E4.
	next, err = store.NextEpisode(ctx, accID, s2e4)
	if err != nil {
		t.Fatal(err)
	}
	if next != nil {
		t.Errorf("after last episode = %+v, want nil", next)
	}

	// A standalone film (no episode row) has no next episode.
	film := mkItem("A Film")
	next, err = store.NextEpisode(ctx, accID, film)
	if err != nil {
		t.Fatal(err)
	}
	if next != nil {
		t.Errorf("film next-episode = %+v, want nil", next)
	}

	// Account isolation: another account can't see this series' episodes.
	var otherAcc string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ne2_"+suffix).Scan(&otherAcc); err != nil {
		t.Fatal(err)
	}
	next, err = store.NextEpisode(ctx, otherAcc, s1e1)
	if err != nil {
		t.Fatal(err)
	}
	if next != nil {
		t.Errorf("cross-account next-episode = %+v, want nil", next)
	}
}
