package stevedore

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/mediasource"
	"github.com/jackc/pgx/v5/pgxpool"
)

// fakeSource is an in-memory Source. LocalPath returns false so the scanner
// skips ffprobe (kept out of CI, which has no ffprobe binary).
type fakeSource struct{ files map[string][]byte }

func (f *fakeSource) Walk(_ context.Context, fn func(mediasource.Entry) error) error {
	for p, b := range f.files {
		if err := fn(mediasource.Entry{Path: p, Size: int64(len(b)), ModTime: time.Unix(0, 0)}); err != nil {
			return err
		}
	}
	return nil
}
func (f *fakeSource) LocalPath(string) (string, bool) { return "", false }
func (f *fakeSource) Open(_ context.Context, rel string) (io.ReadCloser, error) {
	return io.NopCloser(bytes.NewReader(f.files[rel])), nil
}

func TestScan(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run scanner tests")
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
	if err := pool.QueryRow(ctx,
		`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "scan_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1, $2, 'mixed', $3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	src := &fakeSource{files: map[string][]byte{
		"Some Movie (2021).mkv":         []byte("movie-bytes"),
		"Show/Season 1/Show S01E02.mp4": []byte("episode-bytes"),
		"anime/Akira (1988).mkv":        []byte("anime-film-bytes"), // film under anime/
		"poster.jpg":                    []byte("not-media"),        // ignored (extension)
	}}
	sc := NewScanner(pool, slog.New(slog.NewTextHandler(io.Discard, nil)), "")

	res, err := sc.Scan(ctx, libID, src)
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if res.Scanned != 3 || res.Errors != 0 {
		t.Fatalf("result = %+v, want 3 scanned / 0 errors", res)
	}

	// idempotent
	if _, err := sc.Scan(ctx, libID, src); err != nil {
		t.Fatalf("rescan: %v", err)
	}

	var total, movies, episodes, hashed int
	if err := pool.QueryRow(ctx, `
		SELECT count(*),
		       count(*) FILTER (WHERE kind = 'movie'),
		       count(*) FILTER (WHERE kind = 'episode'),
		       count(*) FILTER (WHERE content_hash IS NOT NULL)
		FROM media_items WHERE library_id = $1`, libID).Scan(&total, &movies, &episodes, &hashed); err != nil {
		t.Fatal(err)
	}
	if total != 3 || movies != 2 || episodes != 1 {
		t.Fatalf("rows total=%d movies=%d episodes=%d, want 3/2/1", total, movies, episodes)
	}
	if hashed != 3 {
		t.Fatalf("content_hash set on %d rows, want 3", hashed)
	}

	// The anime film stays a movie (a file under anime/ is not forced to series).
	var kind string
	if err := pool.QueryRow(ctx,
		`SELECT kind FROM media_items WHERE library_id = $1 AND file_path = $2`,
		libID, "anime/Akira (1988).mkv").Scan(&kind); err != nil {
		t.Fatal(err)
	}
	if kind != "movie" {
		t.Fatalf("anime film = kind %q, want movie", kind)
	}
}

// TestScanPrune covers reconciliation (ARGY-96): files that vanish between sweeps
// (renamed or deleted) are removed, along with the episodes/seasons/series and
// play_state they leave behind — and an empty source never wipes the library.
func TestScanPrune(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run scanner tests")
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
	var accID, userID, libID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "prune_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (account_id, name) VALUES ($1, $2) RETURNING id::text`, accID, "u_"+suffix).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1, $2, 'mixed', $3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	sc := NewScanner(pool, slog.New(slog.NewTextHandler(io.Discard, nil)), "")

	// Initial sweep: a movie and one series episode.
	first := &fakeSource{files: map[string][]byte{
		"Some Movie (2021).mkv":         []byte("movie-bytes"),
		"Show/Season 1/Show S01E02.mp4": []byte("episode-bytes"),
	}}
	if _, err := sc.Scan(ctx, libID, first); err != nil {
		t.Fatalf("first scan: %v", err)
	}

	// Record progress on the movie so we can prove play_state cascades on prune.
	var movieID string
	if err := pool.QueryRow(ctx,
		`SELECT id::text FROM media_items WHERE library_id = $1 AND file_path = $2`,
		libID, "Some Movie (2021).mkv").Scan(&movieID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO play_state (user_id, media_item_id, position_seconds) VALUES ($1, $2, 42)`,
		userID, movieID); err != nil {
		t.Fatal(err)
	}

	// Second sweep: the movie is renamed and the episode file is gone entirely.
	second := &fakeSource{files: map[string][]byte{
		"Some Movie (2021) [1080p].mkv": []byte("movie-bytes"),
	}}
	res, err := sc.Scan(ctx, libID, second)
	if err != nil {
		t.Fatalf("second scan: %v", err)
	}
	if res.Removed != 2 {
		t.Fatalf("removed = %d, want 2 (old movie + old episode)", res.Removed)
	}

	// Only the renamed movie remains; the stale movie + episode rows are gone.
	var items int
	var onlyPath string
	if err := pool.QueryRow(ctx,
		`SELECT count(*), coalesce(max(file_path), '') FROM media_items WHERE library_id = $1`,
		libID).Scan(&items, &onlyPath); err != nil {
		t.Fatal(err)
	}
	if items != 1 || onlyPath != "Some Movie (2021) [1080p].mkv" {
		t.Fatalf("media_items = %d (%q), want 1 renamed movie", items, onlyPath)
	}

	// The show's episode/season/series are all swept (no fileless leftovers).
	var eps, seasons, series int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM series WHERE library_id = $1`, libID).Scan(&series); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM seasons se JOIN series sr ON sr.id = se.series_id WHERE sr.library_id = $1`,
		libID).Scan(&seasons); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM episodes e JOIN seasons se ON se.id = e.season_id JOIN series sr ON sr.id = se.series_id WHERE sr.library_id = $1`,
		libID).Scan(&eps); err != nil {
		t.Fatal(err)
	}
	if series != 0 || seasons != 0 || eps != 0 {
		t.Fatalf("orphans left: series=%d seasons=%d episodes=%d, want 0/0/0", series, seasons, eps)
	}

	// Deleting the old movie cascaded its play_state.
	var ps int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM play_state WHERE user_id = $1`, userID).Scan(&ps); err != nil {
		t.Fatal(err)
	}
	if ps != 0 {
		t.Fatalf("play_state rows = %d, want 0 (cascade on prune)", ps)
	}

	// Safety guard: an empty sweep (e.g. an unmounted SMB root) must NOT wipe the
	// library — pruning is skipped when nothing was seen.
	empty := &fakeSource{files: map[string][]byte{}}
	guard, err := sc.Scan(ctx, libID, empty)
	if err != nil {
		t.Fatalf("empty scan: %v", err)
	}
	if guard.Removed != 0 {
		t.Fatalf("empty scan removed = %d, want 0 (guard)", guard.Removed)
	}
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM media_items WHERE library_id = $1`, libID).Scan(&items); err != nil {
		t.Fatal(err)
	}
	if items != 1 {
		t.Fatalf("after empty scan media_items = %d, want 1 (library preserved)", items)
	}
}
