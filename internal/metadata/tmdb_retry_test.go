package metadata

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/time/rate"
)

// newTestTMDB returns a client pointed at srv with retry waits shrunk so
// failure-path tests don't sleep for real.
func newTestTMDB(srv *httptest.Server) *TMDB {
	tm := NewTMDB("test-token", "", TMDBOptions{BaseURL: srv.URL, ImageBaseURL: srv.URL})
	tm.baseBackoff = time.Millisecond
	tm.maxBackoff = 5 * time.Millisecond
	return tm
}

func TestTMDBRetryOn429HonorsRetryAfter(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if calls.Add(1) <= 2 {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		_, _ = w.Write([]byte(`{"results":[{"id":1,"title":"Ok"}]}`))
	}))
	defer srv.Close()

	tm := newTestTMDB(srv)
	// A huge exponential backoff that Retry-After: 0 must override — if the
	// exponential path ran instead, this test would block for ~20s and fail
	// the elapsed check below.
	tm.baseBackoff = 10 * time.Second
	start := time.Now()
	m, err := tm.SearchMovie(context.Background(), "Ok", 0)
	if err != nil {
		t.Fatalf("search after 429s: %v", err)
	}
	if m == nil || m.TMDBID != 1 {
		t.Fatalf("match = %+v", m)
	}
	if got := calls.Load(); got != 3 {
		t.Errorf("server saw %d requests, want 3 (2 429s + success)", got)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Errorf("took %v; Retry-After: 0 should have preempted the exponential backoff", elapsed)
	}
}

func TestTMDBRetryOn5xx(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if calls.Add(1) == 1 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		_, _ = w.Write([]byte(`{"results":[{"id":2,"title":"Ok"}]}`))
	}))
	defer srv.Close()

	m, err := newTestTMDB(srv).SearchMovie(context.Background(), "Ok", 0)
	if err != nil {
		t.Fatalf("search after 502: %v", err)
	}
	if m == nil || m.TMDBID != 2 {
		t.Fatalf("match = %+v", m)
	}
	if got := calls.Load(); got != 2 {
		t.Errorf("server saw %d requests, want 2", got)
	}
}

func TestTMDBRetryExhausted(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()

	tm := newTestTMDB(srv)
	tm.retries = 2
	if _, err := tm.SearchMovie(context.Background(), "Nope", 0); err == nil {
		t.Fatal("expected an error after exhausting retries")
	}
	if got := calls.Load(); got != 3 {
		t.Errorf("server saw %d requests, want retries+1 = 3", got)
	}
}

func TestTMDBNonRetryableStatusNotRetried(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	if _, err := newTestTMDB(srv).SeasonEpisodes(context.Background(), 1, 99); err == nil {
		t.Fatal("expected a status error")
	}
	if got := calls.Load(); got != 1 {
		t.Errorf("server saw %d requests, want 1 (404 must not be retried)", got)
	}
}

func TestTMDBRequestsArePaced(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"results":[]}`))
	}))
	defer srv.Close()

	tm := newTestTMDB(srv)
	// 100 req/s with no burst headroom: 10 sequential requests must take at
	// least 9 inter-request gaps of 10ms.
	tm.limiter = rate.NewLimiter(100, 1)
	start := time.Now()
	for i := 0; i < 10; i++ {
		if _, err := tm.SearchMovie(context.Background(), "Anything", 0); err != nil {
			t.Fatalf("search %d: %v", i, err)
		}
	}
	if elapsed := time.Since(start); elapsed < 90*time.Millisecond {
		t.Errorf("10 requests at 100 req/s took %v, want ≥ 90ms", elapsed)
	}
}

func TestTMDBDownloadImageRetriesAndShares429Handling(t *testing.T) {
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if calls.Add(1) == 1 {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		_, _ = w.Write([]byte("jpeg-bytes"))
	}))
	defer srv.Close()

	dest := filepath.Join(t.TempDir(), "sub", "poster.jpg")
	if err := newTestTMDB(srv).DownloadImage(context.Background(), srv.URL+"/w780/poster.jpg", dest); err != nil {
		t.Fatalf("download: %v", err)
	}
	b, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read dest: %v", err)
	}
	if string(b) != "jpeg-bytes" {
		t.Errorf("dest = %q", b)
	}
	if got := calls.Load(); got != 2 {
		t.Errorf("server saw %d requests, want 2", got)
	}
}

// TestTMDBMatchRunAgainst429Stub is the ARGY-141 acceptance check: a full
// search + credits + artwork pass against a stub that injects a 429 on every
// 4th request completes with zero permanently-failed items, and the observed
// request rate stays under the configured ceiling.
func TestTMDBMatchRunAgainst429Stub(t *testing.T) {
	var (
		mu          sync.Mutex
		calls       int
		first, last time.Time
	)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		calls++
		now := time.Now()
		if first.IsZero() {
			first = now
		}
		last = now
		inject := calls%4 == 0
		mu.Unlock()
		if inject {
			w.Header().Set("Retry-After", "0")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		switch r.URL.Path {
		case "/search/movie":
			_, _ = w.Write([]byte(`{"results":[{"id":7,"title":"Stub Film","poster_path":"/p.jpg"}]}`))
		case "/movie/7/credits":
			_, _ = w.Write([]byte(`{"cast":[{"name":"Someone"}]}`))
		default: // artwork
			_, _ = w.Write([]byte("img"))
		}
	}))
	defer srv.Close()

	tm := newTestTMDB(srv)
	const ceiling = 200.0
	tm.limiter = rate.NewLimiter(rate.Limit(ceiling), 10)

	dir := t.TempDir()
	const items = 40
	for i := 0; i < items; i++ {
		m, err := tm.SearchMovie(context.Background(), "Stub Film", 0)
		if err != nil {
			t.Fatalf("item %d: search permanently failed: %v", i, err)
		}
		if _, err := tm.MovieCredits(context.Background(), m.TMDBID); err != nil {
			t.Fatalf("item %d: credits permanently failed: %v", i, err)
		}
		dest := filepath.Join(dir, "posters", filepath.Base(m.PosterURL))
		if err := tm.DownloadImage(context.Background(), m.PosterURL, dest); err != nil {
			t.Fatalf("item %d: artwork permanently failed: %v", i, err)
		}
	}

	mu.Lock()
	total, window := calls, last.Sub(first)
	mu.Unlock()
	if total <= items*3 {
		t.Fatalf("stub saw %d requests for %d items — 429 injection never triggered retries?", total, items)
	}
	if window > 0 {
		observed := float64(total-1) / window.Seconds()
		// Small tolerance: the limiter's burst allowance front-loads a few
		// requests, and the measurement window starts at the first one.
		if observed > ceiling*1.15 {
			t.Errorf("observed %.0f req/s, configured ceiling %.0f", observed, ceiling)
		}
	}
}
