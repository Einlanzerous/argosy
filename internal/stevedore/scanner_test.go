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
		"poster.jpg":                    []byte("not-media"), // ignored (extension)
	}}
	sc := NewScanner(pool, slog.New(slog.NewTextHandler(io.Discard, nil)), "")

	res, err := sc.Scan(ctx, libID, src)
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	if res.Scanned != 2 || res.Errors != 0 {
		t.Fatalf("result = %+v, want 2 scanned / 0 errors", res)
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
	if total != 2 || movies != 1 || episodes != 1 {
		t.Fatalf("rows total=%d movies=%d episodes=%d, want 2/1/1", total, movies, episodes)
	}
	if hashed != 2 {
		t.Fatalf("content_hash set on %d rows, want 2", hashed)
	}
}
