package metadata

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"golang.org/x/time/rate"
)

const (
	defaultTMDBBaseURL = "https://api.themoviedb.org/3"
	// imageBase has no size segment; sizes are appended per image type below.
	defaultTMDBImageBase = "https://image.tmdb.org/t/p"
	// posterSize is for portrait poster cards; backdropSize is the wider, higher-
	// res landscape art used for full-screen hero backgrounds (w1280 stays crisp
	// stretched across a desktop without pulling the multi-MB "original").
	posterSize   = "w780"
	backdropSize = "w1280"
	// stillSize is the per-episode 16:9 thumbnail; w300 is sharp at the small
	// sizes the episode rows render without pulling a multi-hundred-KB still.
	stillSize = "w300"
	// castLimit caps how many top-billed cast names we persist per title — enough
	// to make a search land the right film without bloating provider_metadata or
	// the search_vector with deep-bench extras.
	castLimit = 15
	// defaultTMDBRate is the sustained request ceiling (req/s) shared by every
	// caller, artwork downloads included. TMDB's practical limit is ~50 req/s;
	// 25 leaves headroom for other consumers of the same API key (ARGY-141).
	defaultTMDBRate = 25.0
	// tmdbMaxRetries is how many times a request is retried after a 429, 5xx,
	// or transport error before the item is failed.
	tmdbMaxRetries = 5
	// tmdbBaseBackoff seeds the exponential backoff used when the server sends
	// no Retry-After; tmdbMaxBackoff caps its growth.
	tmdbBaseBackoff = 500 * time.Millisecond
	tmdbMaxBackoff  = 30 * time.Second
)

// TMDBOptions tunes the shared client beyond credentials; zero values keep
// production defaults.
type TMDBOptions struct {
	// BaseURL overrides the API endpoint so tests and the matcher-scale stub
	// (ARGY-139) can stand in for the real service (env: TMDB_BASE_URL).
	BaseURL string
	// ImageBaseURL overrides the artwork CDN root (env: TMDB_IMAGE_BASE_URL).
	ImageBaseURL string
	// RequestsPerSecond caps the sustained request rate across all endpoints
	// and artwork downloads (env: ARGOSY_TMDB_RATE). Zero = defaultTMDBRate.
	RequestsPerSecond float64
	// Logger receives a Warn per retried request, the only operator-visible
	// signal that TMDB is throttling a run. Nil falls back to slog.Default().
	Logger *slog.Logger
}

// TMDB is a Provider backed by themoviedb.org. Auth uses the v4 read access
// token (Bearer) when set, otherwise the v3 api_key query parameter. Every
// request — API and artwork alike — goes through one shared token bucket and
// a 429/5xx retry envelope so a full-library match can't trip TMDB's rate
// limit into permanently failed items (ARGY-141).
type TMDB struct {
	readToken string
	apiKey    string
	baseURL   string
	imageBase string
	http      *http.Client
	imageHTTP *http.Client // longer timeout: images are bigger than JSON
	limiter   *rate.Limiter
	logger    *slog.Logger
	// retry knobs, private so tests can shrink the waits.
	retries     int
	baseBackoff time.Duration
	maxBackoff  time.Duration
}

// NewTMDB returns a TMDB provider. Either credential may be empty as long as
// the other is set.
func NewTMDB(readToken, apiKey string, opts TMDBOptions) *TMDB {
	baseURL := defaultTMDBBaseURL
	if opts.BaseURL != "" {
		baseURL = opts.BaseURL
	}
	imageBase := defaultTMDBImageBase
	if opts.ImageBaseURL != "" {
		imageBase = opts.ImageBaseURL
	}
	rps := defaultTMDBRate
	if opts.RequestsPerSecond > 0 {
		rps = opts.RequestsPerSecond
	}
	logger := opts.Logger
	if logger == nil {
		logger = slog.Default()
	}
	return &TMDB{
		readToken: readToken,
		apiKey:    apiKey,
		baseURL:   baseURL,
		imageBase: imageBase,
		http:      &http.Client{Timeout: 15 * time.Second},
		imageHTTP: &http.Client{Timeout: 30 * time.Second},
		// Burst of one second's tokens: brief spikes are fine, the sustained
		// rate is what TMDB actually polices.
		limiter:     rate.NewLimiter(rate.Limit(rps), int(max(rps, 1))),
		logger:      logger,
		retries:     tmdbMaxRetries,
		baseBackoff: tmdbBaseBackoff,
		maxBackoff:  tmdbMaxBackoff,
	}
}

// Configured reports whether at least one credential is present.
func (t *TMDB) Configured() bool { return t.readToken != "" || t.apiKey != "" }

type tmdbResult struct {
	ID           int64   `json:"id"`
	Title        string  `json:"title"` // movies
	Name         string  `json:"name"`  // tv
	Overview     string  `json:"overview"`
	PosterPath   string  `json:"poster_path"`
	BackdropPath string  `json:"backdrop_path"`
	ReleaseDate  string  `json:"release_date"`   // movies
	FirstAirDate string  `json:"first_air_date"` // tv
	GenreIDs     []int   `json:"genre_ids"`
	VoteAverage  float64 `json:"vote_average"`
	VoteCount    int     `json:"vote_count"`
}

// SearchMovie returns the best movie match for title (and year, if known).
func (t *TMDB) SearchMovie(ctx context.Context, title string, year int) (*Match, error) {
	q := url.Values{"query": {title}, "include_adult": {"false"}}
	if year > 0 {
		q.Set("year", strconv.Itoa(year))
	}
	results, err := t.search(ctx, "/search/movie", q)
	if err != nil || len(results) == 0 {
		return nil, err
	}
	return t.toMatch(results[0], results[0].Title, results[0].ReleaseDate), nil
}

// SearchSeries returns the best TV-series match for title.
func (t *TMDB) SearchSeries(ctx context.Context, title string) (*Match, error) {
	results, err := t.search(ctx, "/search/tv", url.Values{"query": {title}, "include_adult": {"false"}})
	if err != nil || len(results) == 0 {
		return nil, err
	}
	return t.toMatch(results[0], results[0].Name, results[0].FirstAirDate), nil
}

// toMatch normalizes a raw TMDB result into a Match. title and date are passed
// explicitly because movies and TV use different field names for them.
func (t *TMDB) toMatch(r tmdbResult, title, date string) *Match {
	m := &Match{
		TMDBID:      r.ID,
		Title:       title,
		Overview:    r.Overview,
		GenreIDs:    r.GenreIDs,
		Genres:      GenreNames(r.GenreIDs),
		VoteAverage: r.VoteAverage,
		VoteCount:   r.VoteCount,
		Year:        yearOf(date),
	}
	if r.PosterPath != "" {
		m.PosterURL = t.imageBase + "/" + posterSize + r.PosterPath
	}
	if r.BackdropPath != "" {
		m.BackdropURL = t.imageBase + "/" + backdropSize + r.BackdropPath
	}
	return m
}

// SeasonEpisodes fetches per-episode metadata for one season via
// GET /tv/{id}/season/{n}. A missing season is reported by TMDB as 404, which
// surfaces here as an error; callers log and move on.
func (t *TMDB) SeasonEpisodes(ctx context.Context, tmdbID int64, seasonNumber int) ([]EpisodeMeta, error) {
	var body struct {
		Episodes []struct {
			EpisodeNumber int     `json:"episode_number"`
			Name          string  `json:"name"`
			Overview      string  `json:"overview"`
			StillPath     string  `json:"still_path"`
			VoteAverage   float64 `json:"vote_average"`
			VoteCount     int     `json:"vote_count"`
		} `json:"episodes"`
	}
	path := fmt.Sprintf("/tv/%d/season/%d", tmdbID, seasonNumber)
	if err := t.get(ctx, path, url.Values{}, &body); err != nil {
		return nil, err
	}
	out := make([]EpisodeMeta, 0, len(body.Episodes))
	for _, e := range body.Episodes {
		em := EpisodeMeta{Number: e.EpisodeNumber, Name: e.Name, Overview: e.Overview, VoteAverage: e.VoteAverage, VoteCount: e.VoteCount}
		if e.StillPath != "" {
			em.StillURL = t.imageBase + "/" + stillSize + e.StillPath
		}
		out = append(out, em)
	}
	return out, nil
}

// tmdbCredits is the shape of /movie/{id}/credits and /tv/{id}/credits. Cast
// arrives in billing order; crew carries job titles (we pluck "Director").
type tmdbCredits struct {
	Cast []struct {
		Name string `json:"name"`
	} `json:"cast"`
	Crew []struct {
		Name string `json:"name"`
		Job  string `json:"job"`
	} `json:"crew"`
}

// MovieCredits returns top-billed cast plus the director for a movie.
func (t *TMDB) MovieCredits(ctx context.Context, tmdbID int64) ([]string, error) {
	return t.credits(ctx, fmt.Sprintf("/movie/%d/credits", tmdbID), "Director")
}

// SeriesCredits returns top-billed cast for a series. TV "creators" live on the
// details endpoint rather than credits, so crew is skipped here.
func (t *TMDB) SeriesCredits(ctx context.Context, tmdbID int64) ([]string, error) {
	return t.credits(ctx, fmt.Sprintf("/tv/%d/credits", tmdbID), "")
}

// credits fetches a credits document and returns up to castLimit top-billed cast
// names, optionally followed by the named crew job (e.g. the director), deduped.
func (t *TMDB) credits(ctx context.Context, path, crewJob string) ([]string, error) {
	var body tmdbCredits
	if err := t.get(ctx, path, url.Values{}, &body); err != nil {
		return nil, err
	}
	names := make([]string, 0, castLimit+1)
	seen := make(map[string]bool)
	add := func(name string) {
		if name == "" || seen[name] {
			return
		}
		seen[name] = true
		names = append(names, name)
	}
	for _, c := range body.Cast {
		if len(names) >= castLimit {
			break
		}
		add(c.Name)
	}
	if crewJob != "" {
		for _, c := range body.Crew {
			if c.Job == crewJob {
				add(c.Name)
			}
		}
	}
	return names, nil
}

func (t *TMDB) search(ctx context.Context, path string, q url.Values) ([]tmdbResult, error) {
	var body struct {
		Results []tmdbResult `json:"results"`
	}
	if err := t.get(ctx, path, q, &body); err != nil {
		return nil, err
	}
	return body.Results, nil
}

// get performs an authenticated GET against the TMDB API and decodes the JSON
// body into out.
func (t *TMDB) get(ctx context.Context, path string, q url.Values, out any) error {
	if t.readToken == "" && t.apiKey != "" {
		q.Set("api_key", t.apiKey)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, t.baseURL+path+"?"+q.Encode(), nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	if t.readToken != "" {
		req.Header.Set("Authorization", "Bearer "+t.readToken)
	}
	resp, err := t.doPaced(t.http, req)
	if err != nil {
		return fmt.Errorf("tmdb %s: %w", path, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("tmdb %s: status %d", path, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("decode tmdb response: %w", err)
	}
	return nil
}

// doPaced sends req through the shared token bucket, retrying 429 (honoring
// Retry-After when present), 5xx, and transport errors with exponential
// backoff + jitter. Other statuses (404, 401, …) are returned to the caller
// as-is — retrying them would never succeed. Caller owns resp.Body on success.
func (t *TMDB) doPaced(client *http.Client, req *http.Request) (*http.Response, error) {
	ctx := req.Context()
	var lastErr error
	var delay time.Duration
	for attempt := 0; attempt <= t.retries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(delay):
			}
		}
		if err := t.limiter.Wait(ctx); err != nil {
			return nil, err
		}
		resp, err := client.Do(req.Clone(ctx))
		if err != nil {
			if ctx.Err() != nil {
				return nil, err
			}
			lastErr = err
			delay = t.backoffDelay(attempt)
			t.logger.Warn("tmdb request failed, retrying", "url", req.URL.Path, "attempt", attempt+1, "delay", delay, "err", err)
			continue
		}
		if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
			// Cap Retry-After at maxBackoff: match runs are strictly sequential,
			// so honoring an hour-long value from a misbehaving CDN would park
			// the whole ingest, not one item. Burning a retry early is cheaper.
			delay = t.backoffDelay(attempt)
			if ra := retryAfter(resp.Header.Get("Retry-After")); ra >= 0 {
				delay = min(ra, t.maxBackoff)
			}
			// Drain fully (within reason) so the transport can reuse the
			// connection; proxy 5xx pages can run to a few tens of KB.
			_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
			_ = resp.Body.Close()
			lastErr = fmt.Errorf("status %d", resp.StatusCode)
			t.logger.Warn("tmdb request throttled/failed, retrying", "url", req.URL.Path, "status", resp.StatusCode, "attempt", attempt+1, "delay", delay)
			continue
		}
		return resp, nil
	}
	return nil, fmt.Errorf("giving up after %d attempts: %w", t.retries+1, lastErr)
}

// backoffDelay returns the exponential backoff for a (0-based) failed attempt,
// capped at maxBackoff, with up to 50% random jitter shaved off so a fleet of
// stalled requests doesn't retry in lockstep.
func (t *TMDB) backoffDelay(attempt int) time.Duration {
	d := min(t.baseBackoff<<attempt, t.maxBackoff)
	// The shift overflows int64 around attempt 34, making d negative and
	// rand.N panic. Unreachable at today's retry cap, but guard it so a
	// future configurable retry count can't turn it into a footgun.
	if d <= 0 {
		d = t.maxBackoff
	}
	return d/2 + rand.N(d/2+1)
}

// retryAfter parses a Retry-After header in delta-seconds form (the only form
// TMDB sends). The RFC 7231 HTTP-date form returns -1 like any unparsable
// value, so callers fall back to exponential backoff.
func retryAfter(v string) time.Duration {
	if v == "" {
		return -1
	}
	secs, err := strconv.Atoi(strings.TrimSpace(v))
	if err != nil || secs < 0 {
		return -1
	}
	return time.Duration(secs) * time.Second
}

func yearOf(date string) int {
	if len(date) < 4 {
		return 0
	}
	y, err := strconv.Atoi(date[:4])
	if err != nil {
		return 0
	}
	return y
}

// DownloadImage fetches url into dest through the shared token bucket and
// retry envelope, creating parent directories. Artwork fetches dominate a full
// match run (poster + backdrop per title, a still per episode), so they must
// share the API's pacing rather than run unthrottled beside it.
func (t *TMDB) DownloadImage(ctx context.Context, rawURL, dest string) error {
	if strings.TrimSpace(rawURL) == "" {
		return nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return err
	}
	resp, err := t.doPaced(t.imageHTTP, req)
	if err != nil {
		return fmt.Errorf("download %s: %w", rawURL, err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download %s: status %d", rawURL, resp.StatusCode)
	}
	return saveImage(resp.Body, dest)
}

// DownloadImage is the plain, unpaced fallback for providers without their
// own download path — no limiter, no retries. TMDB artwork goes through the
// method above instead.
func DownloadImage(ctx context.Context, client *http.Client, rawURL, dest string) error {
	if strings.TrimSpace(rawURL) == "" {
		return nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download %s: status %d", rawURL, resp.StatusCode)
	}
	return saveImage(resp.Body, dest)
}

// saveImage streams body into dest, creating parent directories.
func saveImage(body io.Reader, dest string) error {
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	_, err = io.Copy(f, body)
	return err
}
