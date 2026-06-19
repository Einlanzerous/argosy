package ballast

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func discardLogger() *slog.Logger { return slog.New(slog.NewTextHandler(io.Discard, nil)) }

type fakeLive struct{ ids map[string]bool }

func (f fakeLive) LiveIDs() map[string]bool { return f.ids }

// mkSession creates a session dir with one file of the given size and mtime.
func mkSession(t *testing.T, root, id string, size int64, age time.Duration) {
	t.Helper()
	dir := filepath.Join(root, id)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(dir, "stream_00000.m4s")
	if err := os.WriteFile(f, make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}
	mod := time.Now().Add(-age)
	for _, p := range []string{f, dir} {
		if err := os.Chtimes(p, mod, mod); err != nil {
			t.Fatal(err)
		}
	}
}

func exists(root, id string) bool {
	_, err := os.Stat(filepath.Join(root, id))
	return err == nil
}

func TestSweepReclaimsOrphans(t *testing.T) {
	root := t.TempDir()
	mkSession(t, root, "orphan", 1000, 10*time.Minute) // old, not live
	mkSession(t, root, "fresh", 1000, 0)               // recent, not live → within grace
	mkSession(t, root, "live", 1000, 10*time.Minute)   // old but live → protected

	s := NewSweeper(root, 0, time.Minute, fakeLive{ids: map[string]bool{"live": true}}, discardLogger())
	s.Sweep()

	if exists(root, "orphan") {
		t.Error("old non-live orphan not reclaimed")
	}
	if !exists(root, "fresh") {
		t.Error("recent dir reclaimed before grace period")
	}
	if !exists(root, "live") {
		t.Error("live session dir was purged")
	}
}

func TestSweepEvictsLRUOverBudget(t *testing.T) {
	root := t.TempDir()
	// All within grace (so orphan reclaim leaves them); total 3000 > budget 2500,
	// so evicting just the single LRU dir (1000) brings it under.
	mkSession(t, root, "oldest", 1000, 30*time.Second)
	mkSession(t, root, "middle", 1000, 20*time.Second)
	mkSession(t, root, "newest", 1000, 10*time.Second)

	s := NewSweeper(root, 2500, time.Minute, fakeLive{ids: map[string]bool{}}, discardLogger())
	stats := s.Sweep()

	if exists(root, "oldest") {
		t.Error("LRU 'oldest' should have been evicted")
	}
	if !exists(root, "newest") || !exists(root, "middle") {
		t.Error("evicted more than necessary to get under budget")
	}
	if stats.TotalBytes > 2500 {
		t.Errorf("post-sweep total %d still over budget 2500", stats.TotalBytes)
	}
}

func TestSweepNeverEvictsLiveEvenOverBudget(t *testing.T) {
	root := t.TempDir()
	mkSession(t, root, "live1", 2000, 30*time.Second)
	mkSession(t, root, "live2", 2000, 20*time.Second)

	s := NewSweeper(root, 1000, time.Minute,
		fakeLive{ids: map[string]bool{"live1": true, "live2": true}}, discardLogger())
	s.Sweep()

	if !exists(root, "live1") || !exists(root, "live2") {
		t.Error("a live session was evicted to satisfy the budget")
	}
}

func TestSweepMissingDirIsNoError(t *testing.T) {
	s := NewSweeper(filepath.Join(t.TempDir(), "does-not-exist"), 1000, time.Minute, fakeLive{}, discardLogger())
	if got := s.Sweep(); got.SessionDirs != 0 {
		t.Errorf("expected empty stats for missing dir, got %+v", got)
	}
}
