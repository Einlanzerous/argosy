package metadata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/time/rate"
)

// throttlingStub is a server that actually enforces a ceiling: requests beyond
// serverRate req/s get a 429, like TMDB does. The ARGY-141 rig injected 429s on
// a fixed request count, which can't show convergence — the injection rate is
// the same however fast or slow the client goes. Convergence only means
// anything against a server whose 429s respond to the client's behaviour.
type throttlingStub struct {
	limiter *rate.Limiter

	mu       sync.Mutex
	total    int
	rejected int
}

func newThrottlingStub(serverRate float64) *throttlingStub {
	// Burst of one second's tokens, mirroring the client's own allowance. A
	// burst of 1 would be a server that rejects any two simultaneous requests,
	// which no real API is, and it would make the test measure burst collisions
	// rather than sustained rate.
	return &throttlingStub{limiter: rate.NewLimiter(rate.Limit(serverRate), int(serverRate))}
}

// reset zeroes the counters, so a measurement phase can exclude warm-up.
func (s *throttlingStub) reset() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.total, s.rejected = 0, 0
}

func (s *throttlingStub) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	s.mu.Lock()
	s.total++
	ok := s.limiter.Allow()
	if !ok {
		s.rejected++
	}
	s.mu.Unlock()
	if !ok {
		// Deliberately no Retry-After: the header short-circuits the backoff,
		// and a stub that sends "0" would make every retry instant, testing a
		// retry envelope with no spacing in it. Falling through to exponential
		// backoff is the harder and more realistic path.
		w.WriteHeader(http.StatusTooManyRequests)
		return
	}
	_, _ = w.Write([]byte(`{"results":[{"id":1,"title":"Ok"}]}`))
}

func (s *throttlingStub) counts() (total, rejected int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.total, s.rejected
}

// newAdaptiveTestTMDB is newTestTMDB with the AIMD timings shrunk so a
// convergence test runs in milliseconds rather than the tens of seconds the
// production cooldowns imply.
func newAdaptiveTestTMDB(srv *httptest.Server, configuredRate float64) *TMDB {
	tm := newTestTMDB(srv)
	tm.configuredRate = configuredRate
	tm.curRate = configuredRate
	tm.rateFloor = max(configuredRate/tmdbFloorDivisor, 1)
	tm.limiter = rate.NewLimiter(rate.Limit(configuredRate), int(configuredRate))
	tm.decreaseCooldown = 5 * time.Millisecond
	tm.recoverInterval = 20 * time.Millisecond
	return tm
}

// drive runs workers concurrent callers through perWorker logical searches each.
func drive(tm *TMDB, workers, perWorker int) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var wg sync.WaitGroup
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < perWorker; j++ {
				// A permanent failure is legitimate here (the server is hostile);
				// the counters are what the assertions read.
				_, _ = tm.SearchMovie(ctx, "Ok", 0)
			}
		}()
	}
	wg.Wait()
}

// runFixedWorkload drives a warm-up pass, discards its counters, then measures
// a second identical pass. The warm-up exists because the limiter starts with a
// full second of tokens: a short test would otherwise spend its whole life
// draining that burst and never reach the steady state being asserted about.
// A real ingest issues six figures of requests against a 25-token burst, so
// steady state is what it lives in.
//
// Client counters are monotonic, so the measured phase is a delta against a
// snapshot — the same trick the scheduler uses for per-sweep numbers.
func runFixedWorkload(tm *TMDB, stub *throttlingStub, workers, perWorker int) (share float64, delta RequestStats, elapsed time.Duration, ok bool) {
	drive(tm, workers, perWorker)

	before := tm.RequestStats()
	stub.reset()
	start := time.Now()
	drive(tm, workers, perWorker)
	elapsed = time.Since(start)

	total, rejected := stub.counts()
	if total == 0 {
		return 0, RequestStats{}, elapsed, false
	}
	after := tm.RequestStats()
	return float64(rejected) / float64(total), RequestStats{
		Requests:       after.Requests - before.Requests,
		Retries:        after.Retries - before.Retries,
		Throttled:      after.Throttled - before.Throttled,
		Exhausted:      after.Exhausted - before.Exhausted,
		RateLimit:      after.RateLimit,
		ConfiguredRate: after.ConfiguredRate,
	}, elapsed, true
}

// The acceptance criterion for ARGY-170's first half, stated as the comparison
// it actually claims: against a server that 429s above N req/s, a *parallel*
// caller that adapts wastes materially less of the run on rejected requests
// than the same caller holding the configured rate.
//
// This is deliberately a controlled comparison rather than an absolute
// threshold. AIMD oscillates by design — it probes upward until it draws a 429,
// so a steady-state rejection rate of zero would mean it had stopped looking
// for headroom. What matters is the size of the waste against the alternative.
func TestTMDBAdaptiveBeatsHammering(t *testing.T) {
	const (
		serverRate = 200.0 // what the stub will actually accept
		configured = 800.0 // what the operator asked for — 4x too high
		workers    = 8     // stand-in for a parallel matcher (ARGY-139/140)
		perWorker  = 25
	)
	// The floor has to sit below what the server accepts or the client cannot
	// converge — it would pin at the floor and the test would "pass" on a
	// number adaptation never chose. Guard it so a change to tmdbFloorDivisor
	// can't quietly turn this into a tautology.
	if floor := configured / tmdbFloorDivisor; floor >= serverRate {
		t.Fatalf("test is degenerate: floor %.0f >= server rate %.0f", floor, serverRate)
	}

	run := func(adaptive bool) (share float64, st RequestStats, elapsed time.Duration) {
		stub := newThrottlingStub(serverRate)
		srv := httptest.NewServer(stub)
		defer srv.Close()
		tm := newAdaptiveTestTMDB(srv, configured)
		if !adaptive {
			// Pinning the floor at the ceiling makes throttleDown a no-op, which
			// is exactly the pre-ARGY-170 client: retries, but no rate response.
			tm.rateFloor = configured
		}
		share, st, elapsed, ok := runFixedWorkload(tm, stub, workers, perWorker)
		if !ok {
			t.Fatal("stub saw no requests")
		}
		return share, st, elapsed
	}

	hammerShare, hammerStats, hammerElapsed := run(false)
	adaptShare, adaptStats, adaptElapsed := run(true)

	t.Logf("hammering: %.0f%% of %d round-trips rejected, %d exhausted, %v",
		hammerShare*100, hammerStats.Requests, hammerStats.Exhausted, hammerElapsed)
	t.Logf("adaptive:  %.0f%% of %d round-trips rejected, %d exhausted, %v, settled at %.0f req/s",
		adaptShare*100, adaptStats.Requests, adaptStats.Exhausted, adaptElapsed, adaptStats.RateLimit)

	// The headline claim, in the units the ticket uses: "hammering + retrying".
	// Both arms do the identical logical workload, so round-trips per logical
	// request is retry amplification — how much of the run is spent re-sending
	// requests the server already refused. Rejection share is a weaker measure
	// here because a fixed burst allowance lands in every window regardless.
	const logical = workers * perWorker
	hammerAmp := float64(hammerStats.Requests) / logical
	adaptAmp := float64(adaptStats.Requests) / logical
	t.Logf("retry amplification: hammering %.2f round-trips/request, adaptive %.2f", hammerAmp, adaptAmp)
	if adaptAmp >= hammerAmp*0.8 {
		t.Errorf("adaptation did not materially reduce retry amplification: %.2f vs %.2f round-trips per request",
			adaptAmp, hammerAmp)
	}
	if adaptShare >= hammerShare {
		t.Errorf("adaptation did not reduce the rejected share: %.0f%% vs %.0f%%", adaptShare*100, hammerShare*100)
	}
	// It converged: off the configured ceiling, toward what the server accepts,
	// without collapsing through the floor.
	if adaptStats.RateLimit >= configured {
		t.Errorf("rate never left the configured ceiling: %.1f", adaptStats.RateLimit)
	}
	if adaptStats.RateLimit > serverRate*2 {
		t.Errorf("rate did not converge toward the server: %.1f req/s vs %.1f accepted", adaptStats.RateLimit, serverRate)
	}
	if adaptStats.RateLimit < configured/tmdbFloorDivisor {
		t.Errorf("rate collapsed through its floor: %.1f < %.1f", adaptStats.RateLimit, configured/tmdbFloorDivisor)
	}
	// ARGY-141's guarantee — zero permanently-failed items — must not be worse
	// for having adapted. In practice this is the largest effect: against this
	// stub the non-adaptive arm permanently fails a majority of the workload.
	//
	// Which is also why the non-adaptive arm posts a *shorter* wall time above,
	// and why that number is not a regression: giving up on half the run is
	// quick. Wall-time gains from adapting show up against a server like the
	// real TMDB, which spaces its refusals with Retry-After rather than
	// rejecting instantly (ARGY-141 measured 40 req/s finishing behind 25).
	if adaptStats.Exhausted > hammerStats.Exhausted {
		t.Errorf("adaptation made permanent failures worse: %d vs %d", adaptStats.Exhausted, hammerStats.Exhausted)
	}
	if adaptStats.Exhausted*2 > hammerStats.Exhausted {
		t.Errorf("expected adaptation to cut permanent failures substantially: %d vs %d",
			adaptStats.Exhausted, hammerStats.Exhausted)
	}
}

// Recovery matters as much as the cut: a rate that decays and never returns
// turns one bad minute into an ingest that runs at an eighth speed until
// restart.
func TestTMDBAdaptiveRecoversWhenThrottlingStops(t *testing.T) {
	var throttling = true
	var mu sync.Mutex
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		on := throttling
		mu.Unlock()
		if on {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		_, _ = w.Write([]byte(`{"results":[{"id":1,"title":"Ok"}]}`))
	}))
	defer srv.Close()

	const configured = 100.0
	tm := newAdaptiveTestTMDB(srv, configured)

	// Drive it down: each call eats its retries against a server that only 429s.
	for i := 0; i < 6; i++ {
		_, _ = tm.SearchMovie(context.Background(), "Ok", 0)
		time.Sleep(6 * time.Millisecond) // clear the decrease cooldown
	}
	dropped := tm.RequestStats().RateLimit
	if dropped >= configured {
		t.Fatalf("rate never dropped under sustained 429s: %.1f", dropped)
	}

	mu.Lock()
	throttling = false
	mu.Unlock()

	// Clean responses should walk it back to the configured ceiling.
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := tm.SearchMovie(context.Background(), "Ok", 0); err != nil {
			t.Fatalf("unexpected failure after throttling stopped: %v", err)
		}
		if tm.RequestStats().RateLimit >= configured {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Errorf("rate stuck at %.1f, never recovered to configured %.1f",
		tm.RequestStats().RateLimit, configured)
}

// A burst of simultaneous 429s is one signal, not N. Without the cooldown, six
// in-flight requests failing together would halve the rate six times and slam
// straight to the floor on a single hiccup.
func TestTMDBDecreaseCooldownCollapsesBurst(t *testing.T) {
	const configured = 64.0
	tm := NewTMDB("t", "", TMDBOptions{})
	tm.configuredRate = configured
	tm.curRate = configured
	tm.rateFloor = configured / tmdbFloorDivisor
	tm.decreaseCooldown = time.Hour // nothing after the first cut may land

	now := time.Now()
	for i := 0; i < 6; i++ {
		tm.throttleDown(now)
	}
	if got, want := tm.RequestStats().RateLimit, configured*tmdbDecreaseFactor; got != want {
		t.Errorf("burst of 6 cut the rate to %.1f, want a single cut to %.1f", got, want)
	}
}

// The floor bounds how far a sustained outage can slow the ingest.
func TestTMDBAdaptiveHonorsFloor(t *testing.T) {
	const configured = 64.0
	tm := NewTMDB("t", "", TMDBOptions{})
	tm.configuredRate = configured
	tm.curRate = configured
	tm.rateFloor = configured / tmdbFloorDivisor
	tm.decreaseCooldown = 0

	for i := 0; i < 50; i++ {
		tm.throttleDown(time.Now())
	}
	if got := tm.RequestStats().RateLimit; got != tm.rateFloor {
		t.Errorf("rate settled at %.1f, want the floor %.1f", got, tm.rateFloor)
	}
}

// A 5xx is the provider being broken, not the provider asking for less load.
// Throttling on it would slow an ingest over an outage it cannot influence.
func TestTMDBServerErrorDoesNotThrottle(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer srv.Close()

	tm := newAdaptiveTestTMDB(srv, 50)
	_, _ = tm.SearchMovie(context.Background(), "Ok", 0)

	st := tm.RequestStats()
	if st.RateLimit != 50 {
		t.Errorf("5xx moved the rate to %.1f, want it left at 50", st.RateLimit)
	}
	if st.Throttled != 0 {
		t.Errorf("5xx counted as throttling: %d", st.Throttled)
	}
	if st.Retries == 0 {
		t.Error("5xx should still have been retried")
	}
}

// The artwork CDN shares the token bucket (ARGY-141) but must not steer it:
// image.tmdb.org and api.themoviedb.org are separate services with separate
// rate policies, and for an episode-bearing library artwork is most of the
// traffic — so letting it drive would mean the CDN usually deciding how fast we
// may talk to the API, on a signal the API never sent.
func TestTMDBArtworkDoesNotSteerTheRate(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/search") {
			_, _ = w.Write([]byte(`{"results":[{"id":1,"title":"Ok","poster_path":"/p.jpg"}]}`))
			return
		}
		w.WriteHeader(http.StatusTooManyRequests) // every artwork fetch is refused
	}))
	defer srv.Close()

	const configured = 100.0
	tm := newAdaptiveTestTMDB(srv, configured)

	dir := t.TempDir()
	for i := 0; i < 4; i++ {
		m, err := tm.SearchMovie(context.Background(), "Ok", 0)
		if err != nil {
			t.Fatalf("search %d failed: %v", i, err)
		}
		// Expected to fail — the stub refuses all artwork.
		_ = tm.DownloadImage(context.Background(), m.PosterURL, filepath.Join(dir, "p", strconv.Itoa(i)+".jpg"))
		time.Sleep(6 * time.Millisecond) // clear any decrease cooldown
	}

	st := tm.RequestStats()
	if st.RateLimit != configured {
		t.Errorf("artwork 429s moved the shared rate to %.1f, want it left at %.1f", st.RateLimit, configured)
	}
	// The counters must land on the right side of the split, or an operator
	// reads lost stills as titles without metadata.
	if st.Throttled != 0 || st.Exhausted != 0 {
		t.Errorf("artwork failures charged to the API: throttled=%d exhausted=%d", st.Throttled, st.Exhausted)
	}
	if st.ArtworkThrottled == 0 || st.ArtworkExhausted != 4 {
		t.Errorf("artwork counters = throttled %d / exhausted %d, want non-zero and 4",
			st.ArtworkThrottled, st.ArtworkExhausted)
	}
	if st.Requests != 4 {
		t.Errorf("API requests = %d, want the 4 searches only", st.Requests)
	}
}

// The counters are what makes a slow ingest diagnosable from the scan status
// instead of by grepping logs, so pin what each one means.
func TestTMDBRequestStatsCounters(t *testing.T) {
	var n int
	var mu sync.Mutex
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		n++
		i := n
		mu.Unlock()
		if i <= 2 { // two 429s, then success: 1 logical request, 3 round-trips
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		_, _ = w.Write([]byte(`{"results":[{"id":1,"title":"Ok"}]}`))
	}))
	defer srv.Close()

	tm := newAdaptiveTestTMDB(srv, 100)
	if _, err := tm.SearchMovie(context.Background(), "Ok", 0); err != nil {
		t.Fatalf("search failed: %v", err)
	}

	st := tm.RequestStats()
	if st.Requests != 3 {
		t.Errorf("Requests = %d, want 3 round-trips", st.Requests)
	}
	if st.Retries != 2 {
		t.Errorf("Retries = %d, want 2", st.Retries)
	}
	if st.Throttled != 2 {
		t.Errorf("Throttled = %d, want 2", st.Throttled)
	}
	if st.Exhausted != 0 {
		t.Errorf("Exhausted = %d, want 0 — the request succeeded", st.Exhausted)
	}
	if st.ConfiguredRate != 100 {
		t.Errorf("ConfiguredRate = %.1f, want 100", st.ConfiguredRate)
	}
}

// Exhausted is the number that matters after an ingest: each one is a title
// with no metadata.
func TestTMDBRequestStatsCountsExhaustion(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Retry-After", "0")
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()

	tm := newAdaptiveTestTMDB(srv, 100)
	if _, err := tm.SearchMovie(context.Background(), "Ok", 0); err == nil {
		t.Fatal("expected a permanent failure against an always-429 server")
	}

	st := tm.RequestStats()
	if st.Exhausted != 1 {
		t.Errorf("Exhausted = %d, want 1", st.Exhausted)
	}
	if want := int64(tmdbMaxRetries + 1); st.Requests != want {
		t.Errorf("Requests = %d, want %d (initial attempt + %d retries)", st.Requests, want, tmdbMaxRetries)
	}
	if st.Retries != int64(tmdbMaxRetries) {
		t.Errorf("Retries = %d, want %d", st.Retries, tmdbMaxRetries)
	}
	// Throttled is NOT a subset of Retries, and the contract says so: the final
	// attempt drew a 429 but was never retried. An operator computing
	// "5xx retries = retries - throttled" on the old wording would get -1.
	if want := int64(tmdbMaxRetries + 1); st.Throttled != want {
		t.Errorf("Throttled = %d, want %d — every attempt drew a 429", st.Throttled, want)
	}
	if st.Throttled <= st.Retries {
		t.Errorf("throttled (%d) should exceed retries (%d) when the last attempt 429s",
			st.Throttled, st.Retries)
	}
}

// TMDB must satisfy the optional interface the scheduler asserts for, or the
// stats silently never reach the scan status.
var _ RequestStatser = (*TMDB)(nil)
