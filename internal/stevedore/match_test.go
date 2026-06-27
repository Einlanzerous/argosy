package stevedore

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/jackc/pgx/v5/pgxpool"
)

type fakeProvider struct{}

func (fakeProvider) SearchMovie(_ context.Context, title string, _ int) (*metadata.Match, error) {
	return &metadata.Match{TMDBID: 111, Title: "Matched " + title, Year: 2008, Overview: "ov", PosterURL: "http://x/p.jpg", GenreIDs: []int{16}}, nil
}
func (fakeProvider) SearchSeries(_ context.Context, title string) (*metadata.Match, error) {
	return &metadata.Match{TMDBID: 222, Title: "Matched " + title, Year: 2020, Overview: "sv"}, nil
}
func (fakeProvider) SeasonEpisodes(_ context.Context, _ int64, season int) ([]metadata.EpisodeMeta, error) {
	return []metadata.EpisodeMeta{
		{Number: 1, Name: "Pilot", Overview: "the first one", StillURL: "http://x/s" + strconv.Itoa(season) + "e1.jpg"},
		{Number: 2, Name: "The Second", Overview: "the next one"},
	}, nil
}
func (fakeProvider) MovieCredits(_ context.Context, _ int64) ([]string, error) {
	return []string{"Ada Lovelace", "Alan Turing"}, nil
}
func (fakeProvider) SeriesCredits(_ context.Context, _ int64) ([]string, error) {
	return []string{"Grace Hopper"}, nil
}

func TestMatchLibrary(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run matcher tests")
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
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "mat_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO media_items (library_id, kind, title, year, file_path) VALUES ($1,'movie','Big Buck Bunny',2008,$2)`,
		libID, "bbb-"+suffix+".mkv"); err != nil {
		t.Fatal(err)
	}
	var seriesID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'My Show','my show') RETURNING id::text`, libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	// A season with two episodes, both backed by one combined file (shared
	// media_item) — each number should still get its own TMDB metadata.
	var seasonID, comboItem string
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','My Show S01E01-E02',$2) RETURNING id::text`,
		libID, "combo-"+suffix+".mkv").Scan(&comboItem); err != nil {
		t.Fatal(err)
	}
	for _, n := range []int{1, 2} {
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
			seasonID, n, comboItem, "My Show S01E0"+strconv.Itoa(n)); err != nil {
			t.Fatal(err)
		}
	}

	m := NewMatcher(pool, fakeProvider{}, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	m.download = func(context.Context, string, string) error { return nil } // no network

	res, err := m.MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Movies != 1 || res.Series != 1 {
		t.Fatalf("result = %+v, want 1 movie / 1 series", res)
	}

	var movieTMDB *int64
	var pm []byte
	if err := pool.QueryRow(ctx, `SELECT tmdb_id, provider_metadata FROM media_items WHERE library_id=$1 AND kind='movie'`, libID).Scan(&movieTMDB, &pm); err != nil {
		t.Fatal(err)
	}
	if movieTMDB == nil || *movieTMDB != 111 {
		t.Fatalf("movie tmdb_id = %v, want 111", movieTMDB)
	}
	var meta map[string]any
	if err := json.Unmarshal(pm, &meta); err != nil {
		t.Fatalf("provider_metadata not valid json: %v", err)
	}
	if meta["source"] != "tmdb" || meta["title"] != "Matched Big Buck Bunny" || meta["poster"] != "movies/111.jpg" {
		t.Fatalf("provider_metadata = %v", meta)
	}
	// Cast was backfilled for people search (ARGY-67).
	if res.Credits != 2 {
		t.Fatalf("res.Credits = %d, want 2 (movie + series)", res.Credits)
	}
	cast, _ := meta["cast"].([]any)
	if len(cast) != 2 || cast[0] != "Ada Lovelace" {
		t.Fatalf("movie cast = %v, want [Ada Lovelace Alan Turing]", meta["cast"])
	}
	// The cast names are searchable: the STORED search_vector matched on a query
	// (weight B, like genres) and ranks below a title hit (weight A).
	var hits int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM media_items WHERE library_id=$1 AND search_vector @@ to_tsquery('simple', 'lovelace:*')`,
		libID).Scan(&hits); err != nil {
		t.Fatal(err)
	}
	if hits != 1 {
		t.Fatalf("cast search hits = %d, want 1", hits)
	}

	var seriesTMDB *int64
	if err := pool.QueryRow(ctx, `SELECT tmdb_id FROM series WHERE library_id=$1`, libID).Scan(&seriesTMDB); err != nil {
		t.Fatal(err)
	}
	if seriesTMDB == nil || *seriesTMDB != 222 {
		t.Fatalf("series tmdb_id = %v, want 222", seriesTMDB)
	}

	// Per-episode metadata: both numbers of the combined file enriched, each
	// with its own name + provider_metadata overview.
	if res.Episodes != 2 {
		t.Fatalf("res.Episodes = %d, want 2", res.Episodes)
	}
	for n, wantTitle := range map[int]string{1: "Pilot", 2: "The Second"} {
		var title string
		var epm []byte
		if err := pool.QueryRow(ctx, `SELECT e.title, e.provider_metadata FROM episodes e JOIN seasons se ON se.id=e.season_id WHERE se.series_id=$1 AND e.episode_number=$2`,
			seriesID, n).Scan(&title, &epm); err != nil {
			t.Fatal(err)
		}
		if title != wantTitle {
			t.Fatalf("episode %d title = %q, want %q", n, title, wantTitle)
		}
		var em map[string]any
		if err := json.Unmarshal(epm, &em); err != nil {
			t.Fatalf("episode %d provider_metadata not json: %v", n, err)
		}
		if em["source"] != "tmdb" || em["overview"] == nil {
			t.Fatalf("episode %d provider_metadata = %v", n, em)
		}
	}

	// idempotent (no force): already matched, so nothing re-matched and no
	// episodes re-enriched (provider_metadata already populated).
	res2, err := m.MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatal(err)
	}
	if res2.Movies != 0 || res2.Series != 0 || res2.Episodes != 0 || res2.Credits != 0 {
		t.Fatalf("second run matched %+v, want 0/0/0/0 (already matched + cast cached)", res2)
	}
}
