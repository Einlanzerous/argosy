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

	s := NewSweeper(root, 0, time.Minute, fakeLive{ids: map[string]bool{"live": true}}, discardLogger(), 0)
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

	s := NewSweeper(root, 2500, time.Minute, fakeLive{ids: map[string]bool{}}, discardLogger(), 0)
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
		fakeLive{ids: map[string]bool{"live1": true, "live2": true}}, discardLogger(), 0)
	s.Sweep()

	if !exists(root, "live1") || !exists(root, "live2") {
		t.Error("a live session was evicted to satisfy the budget")
	}
}

func TestSweepMissingDirIsNoError(t *testing.T) {
	s := NewSweeper(filepath.Join(t.TempDir(), "does-not-exist"), 1000, time.Minute,
		fakeLive{ids: map[string]bool{}}, discardLogger(), 0)
	if got := s.Sweep(); got.SessionDirs != 0 {
		t.Errorf("expected empty stats for missing dir, got %+v", got)
	}
}

// A nil live set means "unknown" (the DB-backed subtitle Live failed to query);
// the sweep must skip rather than treat every dir as an orphan (ARGY-155).
func TestSweepSkipsWhenLiveSetUnknown(t *testing.T) {
	root := t.TempDir()
	mkSession(t, root, "would-be-orphan", 1000, 10*time.Minute)

	s := NewSweeper(root, 0, time.Minute, fakeLive{ids: nil}, discardLogger(), 0)
	s.Sweep()

	if !exists(root, "would-be-orphan") {
		t.Error("sweep purged a dir while the live set was unknown")
	}
}

// Stats is memoized for statsTTL (ARGY-197): within the window a repeat call
// answers from the memo without walking the tree, and once it lapses the next
// call walks again.
func TestStatsMemoizedWithinTTL(t *testing.T) {
	root := t.TempDir()
	mkSession(t, root, "a", 1000, 0)

	now := time.Now()
	s := NewSweeper(root, 0, time.Minute, fakeLive{ids: map[string]bool{"a": true}}, discardLogger(), 0)
	s.clock = func() time.Time { return now }

	first := s.Stats()
	if first.TotalBytes != 1000 || first.SessionDirs != 1 || first.LiveDirs != 1 {
		t.Fatalf("first Stats = %+v, want 1000 bytes / 1 dir / 1 live", first)
	}

	// A new session lands; inside the TTL the memo still answers.
	mkSession(t, root, "b", 500, 0)
	now = now.Add(statsTTL - time.Millisecond)
	if got := s.Stats(); got != first {
		t.Fatalf("Stats inside TTL = %+v, want memoized %+v", got, first)
	}

	// Past the TTL the tree is walked again and the new dir is counted.
	now = now.Add(2 * time.Millisecond)
	if got := s.Stats(); got.TotalBytes != 1500 || got.SessionDirs != 2 || got.LiveDirs != 1 {
		t.Fatalf("Stats after TTL = %+v, want 1500 bytes / 2 dirs / 1 live", got)
	}
}

// Sweep must not leave Stats reporting bytes it just reclaimed: an eviction
// drops the memo so the next Stats reflects the post-sweep tree.
func TestSweepInvalidatesStatsMemo(t *testing.T) {
	root := t.TempDir()
	mkSession(t, root, "oldest", 1000, 30*time.Second)
	mkSession(t, root, "newest", 1000, 10*time.Second)

	s := NewSweeper(root, 1500, time.Minute, fakeLive{ids: map[string]bool{}}, discardLogger(), 0)

	if got := s.Stats(); got.TotalBytes != 2000 {
		t.Fatalf("pre-sweep Stats = %+v, want 2000 bytes", got)
	}
	s.Sweep() // over budget: evicts "oldest"
	if exists(root, "oldest") {
		t.Fatal("sweep did not evict the LRU dir")
	}
	if got := s.Stats(); got.TotalBytes != 1000 || got.SessionDirs != 1 {
		t.Fatalf("post-sweep Stats = %+v, want 1000 bytes / 1 dir (memo should have been dropped)", got)
	}
}
