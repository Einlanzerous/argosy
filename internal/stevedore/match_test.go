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
	if _, err := pool.Exec(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'My Show','my show')`, libID); err != nil {
		t.Fatal(err)
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

	var seriesTMDB *int64
	if err := pool.QueryRow(ctx, `SELECT tmdb_id FROM series WHERE library_id=$1`, libID).Scan(&seriesTMDB); err != nil {
		t.Fatal(err)
	}
	if seriesTMDB == nil || *seriesTMDB != 222 {
		t.Fatalf("series tmdb_id = %v, want 222", seriesTMDB)
	}

	// idempotent (no force): already matched, so nothing re-matched.
	res2, err := m.MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatal(err)
	}
	if res2.Movies != 0 || res2.Series != 0 {
		t.Fatalf("second run matched %+v, want 0/0 (already matched)", res2)
	}
}
