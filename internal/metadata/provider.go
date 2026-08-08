// Package metadata enriches the library with data from external providers
// (TMDB first). Implementations are kept behind the Provider interface so the
// matcher can be tested with a stub and providers swapped later (e.g. TVDB).
package metadata

import "context"

// Match is a normalized provider result.
type Match struct {
	TMDBID      int64
	Title       string
	Year        int
	Overview    string
	PosterURL   string // full poster (portrait) image URL, or "" when none
	BackdropURL string // full backdrop (landscape) image URL, or "" when none
	GenreIDs    []int
	Genres      []string // GenreIDs resolved to names (TMDB's fixed list)
	VoteAverage float64  // provider rating, 0–10 (0 when unrated/unknown)
	VoteCount   int      // number of votes behind VoteAverage
	Cast        []string // top-billed cast (+ key crew) names, for people search
}

// EpisodeMeta is a normalized per-episode result for a single season, used to
// fill in episode names/overviews/stills after a series matches.
type EpisodeMeta struct {
	Number      int
	Name        string
	Overview    string
	StillURL    string  // full still (16:9 landscape) image URL, or "" when none
	VoteAverage float64 // provider rating, 0–10 (0 when unrated/unknown)
	VoteCount   int     // number of votes behind VoteAverage
}

// ImageDownloader is implemented by providers that fetch artwork through
// their own paced, retrying HTTP path (TMDB, ARGY-141). The matcher prefers
// it over a plain client so image downloads share the API's token bucket.
type ImageDownloader interface {
	DownloadImage(ctx context.Context, rawURL, dest string) error
}

// RequestStats is a provider's cumulative view of its own HTTP traffic, for
// operators watching a long ingest. Counters are monotonic for the life of the
// client; callers wanting per-run numbers snapshot at the start and subtract
// (see stevedore.Scheduler), which is race-free without a reset.
type RequestStats struct {
	// Requests counts HTTP round-trips actually sent, retries included.
	Requests int64
	// Retries counts round-trips that failed retryably (429, 5xx, transport)
	// and were tried again. Throttled is the 429-only subset.
	Retries   int64
	Throttled int64
	// Exhausted counts requests that used every retry and failed permanently —
	// each one is a title that did not get metadata.
	Exhausted int64
	// RateLimit is the limiter's *current* ceiling in req/s, which adaptive
	// throttling moves below ConfiguredRate while the provider is pushing back.
	// A run that got slow shows up here as a number well under the configured
	// one, which is otherwise only visible by grepping logs (ARGY-170).
	RateLimit      float64
	ConfiguredRate float64
}

// RequestStatser is implemented by providers that track the above. The
// scheduler type-asserts for it, so a provider without pacing (or a test stub)
// needs no stats surface at all.
type RequestStatser interface {
	RequestStats() RequestStats
}

// Provider looks up metadata for films and series.
type Provider interface {
	SearchMovie(ctx context.Context, title string, year int) (*Match, error)
	SearchSeries(ctx context.Context, title string) (*Match, error)
	// SeasonEpisodes returns per-episode metadata for one season of a matched
	// series. Returns an empty slice (not an error) when the season is unknown.
	SeasonEpisodes(ctx context.Context, tmdbID int64, seasonNumber int) ([]EpisodeMeta, error)
	// MovieCredits / SeriesCredits return top-billed cast (and, for movies, the
	// director) names for a matched title, for people/cast search (ARGY-67).
	MovieCredits(ctx context.Context, tmdbID int64) ([]string, error)
	SeriesCredits(ctx context.Context, tmdbID int64) ([]string, error)
}
