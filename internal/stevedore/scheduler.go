package stevedore

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"github.com/Einlanzerous/argosy/internal/mediasource"
	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/jackc/pgx/v5/pgxpool"
)

// LibraryScan is the per-library outcome of one scan cycle.
type LibraryScan struct {
	LibraryID string `json:"libraryId"`
	Name      string `json:"name"`
	Scanned   int    `json:"scanned"`
	Errors    int    `json:"errors"`
	Error     string `json:"error,omitempty"`
}

// Status is an observable snapshot of the scheduler — "the state of the
// Manifest": whether a sweep is running and the last cycle's per-library counts.
type Status struct {
	Running    bool          `json:"running"`
	StartedAt  *time.Time    `json:"startedAt,omitempty"`
	FinishedAt *time.Time    `json:"finishedAt,omitempty"`
	Libraries  []LibraryScan `json:"libraries"`
}

// Scheduler keeps the Manifest current by periodically re-running the
// (idempotent) scan over every library. fsnotify is unreliable over the SMB
// mount Argosy reads from (ARGY-53), so a scheduled rescan is the watch
// strategy. A single loop owns scanning, so cycles never overlap.
type Scheduler struct {
	pool       *pgxpool.Pool
	logger     *slog.Logger
	artworkDir string
	provider   metadata.Provider // optional: enrich newly-scanned items with TMDB
	interval   time.Duration     // 0 disables the periodic sweep (on-demand still works)

	trigger chan struct{}

	mu     sync.Mutex
	status Status
}

// NewScheduler builds a Scheduler. interval <= 0 disables periodic sweeps but
// leaves on-demand Trigger working. provider may be nil to skip metadata matching.
func NewScheduler(pool *pgxpool.Pool, logger *slog.Logger, artworkDir string, provider metadata.Provider, interval time.Duration) *Scheduler {
	return &Scheduler{
		pool:       pool,
		logger:     logger,
		artworkDir: artworkDir,
		provider:   provider,
		interval:   interval,
		trigger:    make(chan struct{}, 1),
	}
}

// Run drives the scheduler until ctx is cancelled. When a periodic interval is
// configured it runs an initial sweep on startup, then on every tick; an
// on-demand Trigger runs a sweep regardless of interval.
func (s *Scheduler) Run(ctx context.Context) {
	var tick <-chan time.Time
	if s.interval > 0 {
		t := time.NewTicker(s.interval)
		defer t.Stop()
		tick = t.C
		s.logger.Info("scan scheduler started", "interval", s.interval.String())
		s.scanOnce(ctx)
	} else {
		s.logger.Info("scan scheduler started", "interval", "on-demand only")
	}
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick: // nil channel blocks forever when periodic sweeps are disabled
			s.scanOnce(ctx)
		case <-s.trigger:
			s.scanOnce(ctx)
		}
	}
}

// Trigger requests an immediate sweep. It returns false if one is already
// running or already queued (the request is dropped, not stacked).
func (s *Scheduler) Trigger() bool {
	select {
	case s.trigger <- struct{}{}:
		return true
	default:
		return false
	}
}

// Snapshot returns the current scheduler status.
func (s *Scheduler) Snapshot() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Copy the slice so callers can't mutate our state.
	out := s.status
	out.Libraries = append([]LibraryScan(nil), s.status.Libraries...)
	return out
}

// scanOnce runs one full sweep across every library. Per-library failures are
// recorded and do not abort the cycle.
func (s *Scheduler) scanOnce(ctx context.Context) Status {
	start := time.Now()
	s.mu.Lock()
	s.status = Status{Running: true, StartedAt: &start, Libraries: []LibraryScan{}}
	s.mu.Unlock()

	libs, err := s.libraries(ctx)
	if err != nil {
		s.logger.Error("scan sweep: list libraries failed", "err", err)
	}

	scanner := NewScanner(s.pool, s.logger, s.artworkDir)
	var matcher *Matcher
	if s.provider != nil {
		matcher = NewMatcher(s.pool, s.provider, s.artworkDir, s.logger)
	}

	results := make([]LibraryScan, 0, len(libs))
	for _, l := range libs {
		if ctx.Err() != nil {
			break
		}
		ls := LibraryScan{LibraryID: l.id, Name: l.name}
		res, err := scanner.Scan(ctx, l.id, mediasource.NewLocalFS(l.root))
		ls.Scanned, ls.Errors = res.Scanned, res.Errors
		if err != nil {
			ls.Error = err.Error()
			s.logger.Warn("scan sweep: library failed", "library", l.name, "err", err)
		} else if matcher != nil {
			if _, err := matcher.MatchLibrary(ctx, l.id, false); err != nil {
				s.logger.Warn("scan sweep: match failed", "library", l.name, "err", err)
			}
		}
		s.logger.Info("rebuilt the Manifest", "library", l.name, "scanned", ls.Scanned, "errors", ls.Errors)
		results = append(results, ls)
	}

	end := time.Now()
	s.mu.Lock()
	s.status = Status{Running: false, StartedAt: &start, FinishedAt: &end, Libraries: results}
	snapshot := s.status
	s.mu.Unlock()
	return snapshot
}

type libraryRow struct{ id, name, root string }

func (s *Scheduler) libraries(ctx context.Context) ([]libraryRow, error) {
	rows, err := s.pool.Query(ctx, `SELECT id::text, name, root_path FROM libraries ORDER BY created_at`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []libraryRow
	for rows.Next() {
		var l libraryRow
		if err := rows.Scan(&l.id, &l.name, &l.root); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}
