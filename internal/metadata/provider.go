// Package metadata enriches the library with data from external providers
// (TMDB first). Implementations are kept behind the Provider interface so the
// matcher can be tested with a stub and providers swapped later (e.g. TVDB).
package metadata

import (
	"context"
	"errors"
	"fmt"
	"net/http"
)

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

// SeasonRef is one season as the provider models it. Used to decide whether a
// season on disk has a counterpart in the provider's numbering at all.
type SeasonRef struct {
	Number int
	Name   string
}

// SeasonMapping points one on-disk season at a provider season. It survives
// only for mappings an operator sets by hand: the automatic path reads episodes
// straight out of the provider's published ordering instead (see
// GroupedEpisodes), which needs no season arithmetic.
type SeasonMapping struct {
	// SeasonNumber is the provider season the episodes live in.
	SeasonNumber int
	// EpisodeOffset is added to the on-disk episode number to get the
	// provider's, for a season that starts partway into the provider's.
	EpisodeOffset int
}

// GroupedEpisodes is a provider's own translation of a series onto the library's
// numbering: on-disk season number -> that season's episodes.
//
// The episodes are already renumbered, so EpisodeMeta.Number is the number **on
// disk**, not the provider's. That is the whole point of this type. A season and
// an offset cannot express the common case — TVDB's One Piece season 11 draws
// from TMDB seasons 7, 8 and 9, and only 38% of that show's episodes sit in a
// group that is one contiguous run of one provider season — but a per-episode
// list needs no arithmetic and no special case, because every episode carries
// its own metadata (ARGY-224).
type GroupedEpisodes map[int][]EpisodeMeta

// SeasonMapper is implemented by providers whose ordering can disagree with the
// library's, and that publish enough to reconcile the two. Optional, like
// ImageDownloader: a provider that shares the library's numbering by
// construction (a TVDB-backed one, given the folders come from Sonarr) needs
// none of this, and the matcher falls back to the on-disk number directly.
type SeasonMapper interface {
	// SeriesSeasons returns the seasons the provider models for a series, so
	// the matcher can tell "we number this the same way" from "this season has
	// no counterpart at all".
	SeriesSeasons(ctx context.Context, tmdbID int64) ([]SeasonRef, error)
	// SeriesEpisodeGroup returns the provider's published translation of a
	// series onto the library's numbering, or a nil map (and no error) when it
	// publishes none — the common case, and not a failure.
	SeriesEpisodeGroup(ctx context.Context, tmdbID int64) (GroupedEpisodes, error)
}

// APIError is a provider HTTP failure that carries the status code, so a caller
// can tell an outage it should retry from an answer that will never change. A
// series whose tmdb_id was merged away 404s on every sweep forever; treating
// that as a transient failure hides it behind a warning nobody reads.
type APIError struct {
	Path   string
	Status int
}

func (e *APIError) Error() string { return fmt.Sprintf("tmdb %s: status %d", e.Path, e.Status) }

// Permanent reports whether retrying could ever succeed. 404 means the provider
// does not have this resource; 401/403 mean the credentials will not get it.
func (e *APIError) Permanent() bool {
	switch e.Status {
	case http.StatusNotFound, http.StatusUnauthorized, http.StatusForbidden:
		return true
	}
	return false
}

// IsPermanent reports whether err is an APIError that will never succeed.
func IsPermanent(err error) bool {
	var apiErr *APIError
	return errors.As(err, &apiErr) && apiErr.Permanent()
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
	// The first group counts the metadata API only (api.themoviedb.org).
	//
	// Requests counts HTTP round-trips actually sent, retries included.
	Requests int64
	// Retries counts round-trips that failed retryably (429, 5xx, transport)
	// and were tried again.
	Retries int64
	// Throttled counts 429 responses received. Note this is *not* a subset of
	// Retries: the final attempt of a request that exhausts its budget is
	// counted here but was never retried, so Throttled can exceed Retries.
	Throttled int64
	// Exhausted counts requests that used every retry and failed permanently —
	// each one is a title that did not get metadata.
	Exhausted int64

	// The second group counts the artwork CDN (image.tmdb.org), which is a
	// separate service with its own rate policy and, for an episode-bearing
	// library, the majority of a match run's requests. Kept apart so Exhausted
	// above means what it says: a lost still is not a title without metadata.
	ArtworkRequests  int64
	ArtworkRetries   int64
	ArtworkThrottled int64
	ArtworkExhausted int64
	// RateLimit is the limiter's *current* ceiling in req/s, shared by both
	// surfaces but steered only by the API's 429s. Adaptive throttling moves it
	// below ConfiguredRate while the API is pushing back. A run that got slow
	// shows up here as a number well under the configured one, which is
	// otherwise only visible by grepping logs (ARGY-170).
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
