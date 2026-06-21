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

func (t *TMDB) search(ctx context.Context, path string, q url.Values) ([]tmdbResult, error) {
	if t.readToken == "" && t.apiKey != "" {
		q.Set("api_key", t.apiKey)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, t.baseURL+path+"?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	if t.readToken != "" {
		req.Header.Set("Authorization", "Bearer "+t.readToken)
	}
	resp, err := t.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tmdb %s: status %d", path, resp.StatusCode)
	}
	var body struct {
		Results []tmdbResult `json:"results"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("decode tmdb response: %w", err)
	}
	return body.Results, nil
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
