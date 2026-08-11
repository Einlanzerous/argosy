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

// TestGetItemEpisodeContext covers the now-playing header source (ARGY-134):
// GetItem must surface series title + season/episode number + episode title for
// an episode-backed media item, pick the first episode of a combined rip, and
// leave all four nil for a standalone film.
func TestGetItemEpisodeContext(t *testing.T) {
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

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "gi_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	mkItem := func(kind, title string) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,$2,$3,$4) RETURNING id::text`,
			libID, kind, title, title+suffix).Scan(&id); err != nil {
			t.Fatal(err)
		}
		return id
	}
	var seriesID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,$2,$2) RETURNING id::text`, libID, "The Good Place").Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	var seasonID string
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	mkEp := func(num int, mediaItem string, title string) {
		t.Helper()
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
			seasonID, num, mediaItem, title); err != nil {
			t.Fatal(err)
		}
	}

	// A normal single-episode file, a combined rip backing E2+E3, and a film.
	e1 := mkItem("episode", "The Good Place S01E01")
	combo := mkItem("episode", "The Good Place S01E02-E03")
	film := mkItem("movie", "Some Film")
	mkEp(1, e1, "Everything Is Fine")
	mkEp(2, combo, "Flying")
	mkEp(3, combo, "Tahani Al-Jamil") // same file — combined rip
	// Note: the film gets no episode row.

	store := NewStore(pool, "/artwork")

	// Single episode: full context, real episode title.
	d, err := store.GetItem(ctx, accID, e1)
	if err != nil || d == nil {
		t.Fatalf("GetItem(e1) = %+v, %v", d, err)
	}
	if d.SeriesTitle == nil || *d.SeriesTitle != "The Good Place" {
		t.Errorf("SeriesTitle = %v, want The Good Place", d.SeriesTitle)
	}
	if d.SeasonNumber == nil || *d.SeasonNumber != 1 {
		t.Errorf("SeasonNumber = %v, want 1", d.SeasonNumber)
	}
	if d.EpisodeNumber == nil || *d.EpisodeNumber != 1 {
		t.Errorf("EpisodeNumber = %v, want 1", d.EpisodeNumber)
	}
	if d.EpisodeTitle == nil || *d.EpisodeTitle != "Everything Is Fine" {
		t.Errorf("EpisodeTitle = %v, want Everything Is Fine", d.EpisodeTitle)
	}

	// Combined rip: the header should read as the FIRST episode of the span.
	d, err = store.GetItem(ctx, accID, combo)
	if err != nil || d == nil {
		t.Fatalf("GetItem(combo) = %+v, %v", d, err)
	}
	if d.EpisodeNumber == nil || *d.EpisodeNumber != 2 {
		t.Errorf("combined EpisodeNumber = %v, want 2 (first of E2-E3)", d.EpisodeNumber)
	}
	if d.EpisodeTitle == nil || *d.EpisodeTitle != "Flying" {
		t.Errorf("combined EpisodeTitle = %v, want Flying", d.EpisodeTitle)
	}

	// Film: no episode context at all.
	d, err = store.GetItem(ctx, accID, film)
	if err != nil || d == nil {
		t.Fatalf("GetItem(film) = %+v, %v", d, err)
	}
	if d.SeriesTitle != nil || d.SeasonNumber != nil || d.EpisodeNumber != nil || d.EpisodeTitle != nil {
		t.Errorf("film episode context = (%v,%v,%v,%v), want all nil",
			d.SeriesTitle, d.SeasonNumber, d.EpisodeNumber, d.EpisodeTitle)
	}
}

// TestGetItemEpisodeArtworkInheritsSeries covers ARGY-87: TMDB hangs poster and
// backdrop off the *series*, so an episode's own row has neither (its per-episode
// art is a still, which lives on the episode row and isn't loaded here). A client
// playing an episode has nowhere else to look for artwork, which left Android's
// lock-screen media panel with an empty black background. GetItem must inherit
// the series' art — without clobbering art the episode does have.
func TestGetItemEpisodeArtworkInheritsSeries(t *testing.T) {
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

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ga_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// The series carries the artwork, exactly as the TMDB match writes it.
	var seriesID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO series (library_id, title, sort_title, provider_metadata)
		 VALUES ($1,$2,$2,'{"poster":"s/p.jpg","backdrop":"s/b.jpg"}'::jsonb) RETURNING id::text`,
		libID, "Futurama").Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	var seasonID string
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	mkEpisode := func(num int, title, provJSON string) string {
		t.Helper()
		var id string
		if err := pool.QueryRow(ctx,
			`INSERT INTO media_items (library_id, kind, title, file_path, provider_metadata)
			 VALUES ($1,'episode',$2,$3,$4::jsonb) RETURNING id::text`,
			libID, title, title+suffix, provJSON).Scan(&id); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
			seasonID, num, id, title); err != nil {
			t.Fatal(err)
		}
		return id
	}

	bare := mkEpisode(1, "Futurama s01e01", `{}`)
	own := mkEpisode(2, "Futurama s01e02", `{"poster":"e/own.jpg","backdrop":"e/ownb.jpg"}`)

	store := NewStore(pool, "/artwork")

	// The real-world shape: no art of its own, so it shows the series'.
	d, err := store.GetItem(ctx, accID, bare)
	if err != nil || d == nil {
		t.Fatalf("GetItem(bare) = %+v, %v", d, err)
	}
	if d.PosterUrl == nil || *d.PosterUrl != "/artwork/s/p.jpg" {
		t.Errorf("PosterUrl = %v, want /artwork/s/p.jpg", d.PosterUrl)
	}
	if d.BackdropUrl == nil || *d.BackdropUrl != "/artwork/s/b.jpg" {
		t.Errorf("BackdropUrl = %v, want /artwork/s/b.jpg", d.BackdropUrl)
	}

	// An episode with its own art keeps it — the series is a fallback, not an
	// override.
	d, err = store.GetItem(ctx, accID, own)
	if err != nil || d == nil {
		t.Fatalf("GetItem(own) = %+v, %v", d, err)
	}
	if d.PosterUrl == nil || *d.PosterUrl != "/artwork/e/own.jpg" {
		t.Errorf("PosterUrl = %v, want the episode's own /artwork/e/own.jpg", d.PosterUrl)
	}
	if d.BackdropUrl == nil || *d.BackdropUrl != "/artwork/e/ownb.jpg" {
		t.Errorf("BackdropUrl = %v, want the episode's own /artwork/e/ownb.jpg", d.BackdropUrl)
	}
}
