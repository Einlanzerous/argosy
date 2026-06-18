package stevedore

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSchedulerScanOnce(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run scheduler tests")
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

	// A library rooted at a temp dir with one media file. ffprobe is absent in
	// CI, so probing warns and continues — the row is still ingested.
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "Big Buck Bunny (2008).mkv"), []byte("not-real-media"), 0o644); err != nil {
		t.Fatal(err)
	}

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "sched_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, dir).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// interval 0 + nil provider: a pure on-demand sweep with no TMDB calls.
	sched := NewScheduler(pool, slog.New(slog.NewTextHandler(io.Discard, nil)), "", nil, 0)
	st := sched.scanOnce(ctx)

	if st.Running || st.FinishedAt == nil {
		t.Fatalf("post-sweep status = %+v, want finished and not running", st)
	}
	// The sweep covers every library; find ours. (Other libraries left by
	// sibling tests may have stale roots and surface errors — that's the
	// graceful per-library handling, and must not abort the sweep.)
	var mine *LibraryScan
	for i := range st.Libraries {
		if st.Libraries[i].LibraryID == libID {
			mine = &st.Libraries[i]
		}
	}
	if mine == nil || mine.Scanned < 1 || mine.Error != "" {
		t.Fatalf("my library result = %+v, want >=1 scanned and no error", mine)
	}
	if sched.Snapshot().Running {
		t.Errorf("snapshot still running")
	}
	if !sched.Trigger() {
		t.Errorf("Trigger() = false when idle, want true")
	}

	var rows int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM media_items WHERE library_id=$1`, libID).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Fatalf("media_items = %d, want 1", rows)
	}
}
