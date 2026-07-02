package metadata

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
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
)

// TMDB is a Provider backed by themoviedb.org. Auth uses the v4 read access
// token (Bearer) when set, otherwise the v3 api_key query parameter.
type TMDB struct {
	readToken string
	apiKey    string
	baseURL   string
	imageBase string
	http      *http.Client
}

// NewTMDB returns a TMDB provider. Either credential may be empty as long as
// the other is set.
func NewTMDB(readToken, apiKey string) *TMDB {
	return &TMDB{
		readToken: readToken,
		apiKey:    apiKey,
		baseURL:   defaultTMDBBaseURL,
		imageBase: defaultTMDBImageBase,
		http:      &http.Client{Timeout: 15 * time.Second},
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
	resp, err := t.http.Do(req)
	if err != nil {
		return err
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

// DownloadImage fetches url into dest, creating parent directories.
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
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	_, err = io.Copy(f, resp.Body)
	return err
}
