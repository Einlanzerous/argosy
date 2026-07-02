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
