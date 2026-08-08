package stevedore

import (
	"context"
	"io"
	"log/slog"
	"testing"

	"github.com/Einlanzerous/argosy/internal/metadata"
)

// statsProvider is a Provider that also reports request stats, standing in for
// the TMDB client. Only the stats surface is exercised here; the lookup methods
// exist to satisfy the interface.
type statsProvider struct{ stats metadata.RequestStats }

func (p *statsProvider) RequestStats() metadata.RequestStats { return p.stats }

func (p *statsProvider) SearchMovie(context.Context, string, int) (*metadata.Match, error) {
	return nil, nil
}
func (p *statsProvider) SearchSeries(context.Context, string) (*metadata.Match, error) {
	return nil, nil
}
func (p *statsProvider) SeasonEpisodes(context.Context, int64, int) ([]metadata.EpisodeMeta, error) {
	return nil, nil
}
func (p *statsProvider) MovieCredits(context.Context, int64) ([]string, error)  { return nil, nil }
func (p *statsProvider) SeriesCredits(context.Context, int64) ([]string, error) { return nil, nil }

// plainProvider implements Provider without the stats surface — any future
// non-TMDB provider, and every test stub in this package.
type plainProvider struct{}

func (p *plainProvider) SearchMovie(context.Context, string, int) (*metadata.Match, error) {
	return nil, nil
}
func (p *plainProvider) SearchSeries(context.Context, string) (*metadata.Match, error) {
	return nil, nil
}
func (p *plainProvider) SeasonEpisodes(context.Context, int64, int) ([]metadata.EpisodeMeta, error) {
	return nil, nil
}
func (p *plainProvider) MovieCredits(context.Context, int64) ([]string, error)  { return nil, nil }
func (p *plainProvider) SeriesCredits(context.Context, int64) ([]string, error) { return nil, nil }

func testScheduler(p metadata.Provider) *Scheduler {
	return NewScheduler(nil, slog.New(slog.NewTextHandler(io.Discard, nil)), "", p, 0)
}

// The status must survive a provider that tracks nothing, and one that isn't
// there at all — the ordinary configuration for anyone without TMDB credentials.
func TestSnapshotOmitsTMDBStatsWithoutAStatser(t *testing.T) {
	if got := testScheduler(nil).Snapshot().TMDB; got != nil {
		t.Errorf("nil provider produced stats %+v, want none", got)
	}
	if got := testScheduler(&plainProvider{}).Snapshot().TMDB; got != nil {
		t.Errorf("provider without a stats surface produced %+v, want none", got)
	}
}

// The counters answer "what has this sweep cost", so they must be a delta
// against the sweep's start. Reporting the client's lifetime totals would make
// the second sweep of a long-running server look catastrophic while telling an
// operator nothing about the run they are watching.
func TestSnapshotReportsPerSweepDelta(t *testing.T) {
	p := &statsProvider{stats: metadata.RequestStats{
		Requests: 1000, Retries: 200, Throttled: 150, Exhausted: 7,
		RateLimit: 25, ConfiguredRate: 25,
	}}
	s := testScheduler(p)

	// Baseline as a sweep would take it, then more traffic during the sweep.
	s.baseline = p.stats
	p.stats = metadata.RequestStats{
		Requests: 1030, Retries: 205, Throttled: 152, Exhausted: 8,
		RateLimit: 12.5, ConfiguredRate: 25,
	}

	got := s.Snapshot().TMDB
	if got == nil {
		t.Fatal("no stats on the snapshot")
	}
	if got.Requests != 30 || got.Retries != 5 || got.Throttled != 2 || got.Exhausted != 1 {
		t.Errorf("deltas = %+v, want requests 30, retries 5, throttled 2, exhausted 1", got)
	}
	// Rates are levels, not deltas — subtracting them would be meaningless.
	if got.RateLimit != 12.5 || got.ConfiguredRate != 25 {
		t.Errorf("rates = %.1f/%.1f, want the current 12.5/25", got.RateLimit, got.ConfiguredRate)
	}
}

// Snapshot reads the provider live rather than returning what was stored at the
// last sweep boundary. Without this an operator polling during a six-hour
// ingest sees zeros until it finishes, which is when the numbers stop being
// actionable.
func TestSnapshotReadsStatsLiveMidSweep(t *testing.T) {
	p := &statsProvider{}
	s := testScheduler(p)
	s.baseline = p.stats

	first := s.Snapshot().TMDB
	if first == nil || first.Requests != 0 {
		t.Fatalf("initial stats = %+v, want zeroed", first)
	}

	// Traffic accrues with no sweep boundary crossed.
	p.stats = metadata.RequestStats{Requests: 42, Throttled: 9, RateLimit: 12.5, ConfiguredRate: 25}

	second := s.Snapshot().TMDB
	if second == nil || second.Requests != 42 || second.Throttled != 9 {
		t.Errorf("stats = %+v, want them to have climbed to 42 requests / 9 throttled", second)
	}
	if second.RateLimit != 12.5 {
		t.Errorf("rateLimit = %.1f, want the live 12.5", second.RateLimit)
	}
}
