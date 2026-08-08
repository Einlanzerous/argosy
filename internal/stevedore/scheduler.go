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

// TMDBStats is the metadata provider's traffic for the current (or last) sweep:
// counters are deltas against a baseline taken when the sweep started, so they
// answer "what has this run cost" rather than "what has the process ever done".
// Rates are levels, not deltas — RateLimit below ConfiguredRate is the provider
// actively throttling us, and is the first thing to look at when an ingest is
// slower than expected (ARGY-170).
type TMDBStats struct {
	Requests         int64   `json:"requests"`
	Retries          int64   `json:"retries"`
	Throttled        int64   `json:"throttled"`
	Exhausted        int64   `json:"exhausted"`
	ArtworkRequests  int64   `json:"artworkRequests"`
	ArtworkRetries   int64   `json:"artworkRetries"`
	ArtworkThrottled int64   `json:"artworkThrottled"`
	ArtworkExhausted int64   `json:"artworkExhausted"`
	RateLimit        float64 `json:"rateLimit"`
	ConfiguredRate   float64 `json:"configuredRate"`
}

// Status is an observable snapshot of the scheduler — "the state of the
// Manifest": whether a sweep is running and the last cycle's per-library counts.
type Status struct {
	Running    bool          `json:"running"`
	StartedAt  *time.Time    `json:"startedAt,omitempty"`
	FinishedAt *time.Time    `json:"finishedAt,omitempty"`
	Libraries  []LibraryScan `json:"libraries"`
	// TMDB is nil when no provider is configured, or when the configured one
	// doesn't track request stats (any non-TMDB provider, and test stubs).
	TMDB *TMDBStats `json:"tmdb,omitempty"`
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
	// statser is provider when it tracks request stats, else nil. Resolved once
	// here rather than per-Snapshot so the type assertion isn't on the read path.
	statser metadata.RequestStatser

	mu       sync.Mutex
	status   Status
	baseline metadata.RequestStats // provider counters as of the current sweep's start
}

// NewScheduler builds a Scheduler. interval <= 0 disables periodic sweeps but
// leaves on-demand Trigger working. provider may be nil to skip metadata matching.
func NewScheduler(pool *pgxpool.Pool, logger *slog.Logger, artworkDir string, provider metadata.Provider, interval time.Duration) *Scheduler {
	s := &Scheduler{
		pool:       pool,
		logger:     logger,
		artworkDir: artworkDir,
		provider:   provider,
		interval:   interval,
		trigger:    make(chan struct{}, 1),
	}
	// A nil interface fails this assertion on its own, so no nil guard is
	// needed. (One wouldn't help anyway: an interface holding a typed nil is
	// itself non-nil, so `provider != nil` passes and the assertion still
	// succeeds — callers must not hand us one. `main.go` doesn't: it leaves
	// the interface unset unless the client is Configured().)
	if st, ok := provider.(metadata.RequestStatser); ok {
		s.statser = st
	}
	return s
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

// Snapshot returns the current scheduler status. Provider stats are computed
// here rather than stored, so polling mid-sweep shows a run's retry and 429
// counts climbing live — the point of the endpoint during a bulk ingest, where
// waiting for the sweep to finish to learn it was being throttled is useless.
func (s *Scheduler) Snapshot() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Copy the slice so callers can't mutate our state.
	out := s.status
	out.Libraries = append([]LibraryScan(nil), s.status.Libraries...)
	out.TMDB = s.tmdbStatsLocked()
	return out
}

// tmdbStatsLocked returns provider traffic for the current sweep as a delta
// against the baseline captured at its start. Caller holds s.mu.
func (s *Scheduler) tmdbStatsLocked() *TMDBStats {
	if s.statser == nil {
		return nil
	}
	cur := s.statser.RequestStats()
	return &TMDBStats{
		Requests:         cur.Requests - s.baseline.Requests,
		Retries:          cur.Retries - s.baseline.Retries,
		Throttled:        cur.Throttled - s.baseline.Throttled,
		Exhausted:        cur.Exhausted - s.baseline.Exhausted,
		ArtworkRequests:  cur.ArtworkRequests - s.baseline.ArtworkRequests,
		ArtworkRetries:   cur.ArtworkRetries - s.baseline.ArtworkRetries,
		ArtworkThrottled: cur.ArtworkThrottled - s.baseline.ArtworkThrottled,
		ArtworkExhausted: cur.ArtworkExhausted - s.baseline.ArtworkExhausted,
		RateLimit:        cur.RateLimit,
		ConfiguredRate:   cur.ConfiguredRate,
	}
}

// scanOnce runs one full sweep across every library. Per-library failures are
// recorded and do not abort the cycle.
func (s *Scheduler) scanOnce(ctx context.Context) Status {
	start := time.Now()
	s.mu.Lock()
	s.status = Status{Running: true, StartedAt: &start, Libraries: []LibraryScan{}}
	if s.statser != nil {
		s.baseline = s.statser.RequestStats()
	}
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
	snapshot.TMDB = s.tmdbStatsLocked()
	s.mu.Unlock()
	if t := snapshot.TMDB; t != nil && t.Requests > 0 {
		s.logger.Info("scan sweep: tmdb traffic",
			"requests", t.Requests, "retries", t.Retries, "throttled", t.Throttled,
			"exhausted", t.Exhausted, "rate", t.RateLimit, "configured", t.ConfiguredRate)
	}
	return snapshot
}

type libraryRow struct{ id, name, root string }

// libraries returns every library root on the instance. This is deliberately
// NOT scoped to the owner (ARGY-167): a sweep's job is to keep the database
// consistent with what's on disk, and scanning a stray non-owner library is
// harmless — nothing browses it, since every client resolves the catalog to the
// owner's account. Scoping it here would instead add a silent-failure mode where
// a missing ownership row quietly stops all scanning and the catalog goes stale.
// The cross-account exposure the old query enabled is closed at the routes
// instead: both POST /scan and GET /scan/status are owner-only.
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
