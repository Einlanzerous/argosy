// Package ballast manages the on-disk HLS segment cache and purges old segments
// so the server stays within its storage budget under transcode load (Phase 3).
//
// The transcode Manager namespaces each session's HLS output in its own
// subdirectory of the cache dir and removes it on stop/idle-reap. Ballast is the
// safety net on top of that: it reclaims orphaned subdirectories left by crashed
// sessions and, when the cache exceeds its high-water mark, evicts the
// least-recently-used non-live sessions until it's back under budget. A session
// the Manager still considers live is never purged.
//
// A second Sweeper instance (budget 0, long interval) reaps the subtitle VTT
// cache the same way (ARGY-155): there "live" means the media item still exists
// in the catalog, so extracted VTTs persist for the life of the item and are
// reclaimed once a delete or rescan retires its id.
package ballast

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"time"
)

// Live reports the session IDs currently in use; their cache directories must
// never be purged. The transcode Manager satisfies this.
type Live interface {
	LiveIDs() map[string]bool
}

// Stats is a snapshot of cache usage for The Helm / Drydock.
type Stats struct {
	TotalBytes  int64 `json:"totalBytes"`
	BudgetBytes int64 `json:"budgetBytes"`
	SessionDirs int   `json:"sessionDirs"`
	LiveDirs    int   `json:"liveDirs"`
}

// Sweeper periodically reclaims the transcode cache directory.
type Sweeper struct {
	dir         string
	budget      int64         // high-water mark in bytes; <=0 disables size eviction
	orphanGrace time.Duration // a non-live dir older than this is an orphan
	interval    time.Duration
	live        Live
	logger      *slog.Logger
	clock       func() time.Time
}

// NewSweeper builds a Sweeper. budget<=0 disables size-based eviction (orphan
// reclamation still runs). orphanGrace guards against racing a just-created dir.
// interval<=0 sweeps every minute.
func NewSweeper(dir string, budget int64, orphanGrace time.Duration, live Live, logger *slog.Logger, interval time.Duration) *Sweeper {
	if orphanGrace <= 0 {
		orphanGrace = 5 * time.Minute
	}
	if interval <= 0 {
		interval = time.Minute
	}
	return &Sweeper{
		dir:         dir,
		budget:      budget,
		orphanGrace: orphanGrace,
		interval:    interval,
		live:        live,
		logger:      logger,
		clock:       time.Now,
	}
}

// Run sweeps once immediately (reclaiming orphans from a previous run), then on
// a ticker until ctx is cancelled.
func (s *Sweeper) Run(ctx context.Context) {
	s.Sweep()
	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.Sweep()
		}
	}
}

type entry struct {
	id    string
	bytes int64
	mod   time.Time
}

// Sweep reclaims orphaned directories and, if over budget, evicts LRU non-live
// sessions until under budget. It returns the post-sweep cache stats.
func (s *Sweeper) Sweep() Stats {
	live := map[string]bool{}
	if s.live != nil {
		live = s.live.LiveIDs()
		// A nil live set means "unknown" (e.g. the DB-backed subtitle Live
		// couldn't query) — skip the pass rather than treat every dir as an
		// orphan and mass-purge the cache.
		if live == nil {
			s.logger.Warn("ballast: live set unavailable, skipping sweep", "dir", s.dir)
			return Stats{BudgetBytes: s.budget}
		}
	}
	dirents, err := os.ReadDir(s.dir)
	if err != nil {
		// The dir may not exist yet (no transcode has run) — not an error.
		if !os.IsNotExist(err) {
			s.logger.Warn("ballast: read cache dir failed", "dir", s.dir, "err", err)
		}
		return Stats{BudgetBytes: s.budget}
	}

	now := s.clock()
	var entries []entry
	liveCount := 0
	for _, de := range dirents {
		if !de.IsDir() {
			continue
		}
		id := de.Name()
		path := filepath.Join(s.dir, id)
		size, mod := dirSize(path)
		if live[id] {
			liveCount++
			entries = append(entries, entry{id, size, mod})
			continue
		}
		// Non-live dir: reclaim it once it's past the grace period (ended
		// sessions are usually already removed by the Manager; this catches
		// orphans left by a crash).
		if now.Sub(mod) >= s.orphanGrace {
			s.remove(id)
			continue
		}
		entries = append(entries, entry{id, size, mod})
	}

	// Budget pass: evict LRU non-live dirs until under the high-water mark.
	total := int64(0)
	for _, e := range entries {
		total += e.bytes
	}
	if s.budget > 0 && total > s.budget {
		sort.Slice(entries, func(i, j int) bool { return entries[i].mod.Before(entries[j].mod) })
		for _, e := range entries {
			if total <= s.budget {
				break
			}
			if live[e.id] {
				continue // never evict a live session
			}
			s.remove(e.id)
			total -= e.bytes
		}
		if total > s.budget {
			s.logger.Warn("ballast: over budget but only live sessions remain",
				"bytes", total, "budget", s.budget)
		}
	}

	// Recompute the surviving total/dir count for accurate stats.
	final := int64(0)
	dirs := 0
	for _, e := range entries {
		if _, err := os.Stat(filepath.Join(s.dir, e.id)); err == nil {
			final += e.bytes
			dirs++
		}
	}
	return Stats{TotalBytes: final, BudgetBytes: s.budget, SessionDirs: dirs, LiveDirs: liveCount}
}

// Stats reports current cache usage without evicting anything (for The Helm /
// Drydock to poll).
func (s *Sweeper) Stats() Stats {
	live := map[string]bool{}
	if s.live != nil {
		live = s.live.LiveIDs()
	}
	dirents, err := os.ReadDir(s.dir)
	if err != nil {
		return Stats{BudgetBytes: s.budget}
	}
	var total int64
	dirs, liveCount := 0, 0
	for _, de := range dirents {
		if !de.IsDir() {
			continue
		}
		size, _ := dirSize(filepath.Join(s.dir, de.Name()))
		total += size
		dirs++
		if live[de.Name()] {
			liveCount++
		}
	}
	return Stats{TotalBytes: total, BudgetBytes: s.budget, SessionDirs: dirs, LiveDirs: liveCount}
}

func (s *Sweeper) remove(id string) {
	if err := os.RemoveAll(filepath.Join(s.dir, id)); err != nil {
		s.logger.Warn("ballast: purge failed", "id", id, "err", err)
		return
	}
	s.logger.Info("ballast: reclaimed cache dir", "id", id)
}

// dirSize sums the file sizes under path and returns the newest mtime seen
// (so an actively-written session looks "recent" and sorts last for eviction).
func dirSize(path string) (int64, time.Time) {
	var total int64
	var newest time.Time
	_ = filepath.WalkDir(path, func(_ string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if fi, e := d.Info(); e == nil {
			total += fi.Size()
			if fi.ModTime().After(newest) {
				newest = fi.ModTime()
			}
		}
		return nil
	})
	if newest.IsZero() {
		if fi, err := os.Stat(path); err == nil {
			newest = fi.ModTime()
		}
	}
	return total, newest
}
