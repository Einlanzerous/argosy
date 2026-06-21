package stevedore

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"path"
	"path/filepath"
	"time"

	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Matcher enriches movies and series with provider metadata (TMDB) + artwork.
type Matcher struct {
	pool       *pgxpool.Pool
	provider   metadata.Provider
	logger     *slog.Logger
	artworkDir string
	download   func(ctx context.Context, url, dest string) error
}

// NewMatcher returns a Matcher that downloads artwork into artworkDir.
func NewMatcher(pool *pgxpool.Pool, provider metadata.Provider, artworkDir string, logger *slog.Logger) *Matcher {
	client := &http.Client{Timeout: 30 * time.Second}
	return &Matcher{
		pool:       pool,
		provider:   provider,
		logger:     logger,
		artworkDir: artworkDir,
		download: func(ctx context.Context, url, dest string) error {
			return metadata.DownloadImage(ctx, client, url, dest)
		},
	}
}

// MatchResult summarizes a match run.
type MatchResult struct {
	Movies int
	Series int
	Misses int
}

type matchItem struct {
	id    string
	title string
	year  int
}

// MatchLibrary matches unmatched movies and series in a library (or all of them
// when force is true).
func (m *Matcher) MatchLibrary(ctx context.Context, libraryID string, force bool) (MatchResult, error) {
	var res MatchResult

	movieQ := `SELECT id::text, title, year FROM media_items WHERE library_id = $1 AND kind = 'movie'`
	if !force {
		movieQ += ` AND tmdb_id IS NULL`
	}
	movies, err := m.collect(ctx, movieQ, libraryID)
	if err != nil {
		return res, err
	}
	for _, it := range movies {
		match, err := m.provider.SearchMovie(ctx, it.title, it.year)
		if err != nil {
			m.logger.Warn("tmdb movie search failed", "title", it.title, "err", err)
			continue
		}
		if match == nil {
			res.Misses++
			continue
		}
		if err := m.store(ctx, "media_items", "movies", it.id, match); err != nil {
			return res, err
		}
		res.Movies++
	}

	seriesQ := `SELECT id::text, title, 0 FROM series WHERE library_id = $1`
	if !force {
		seriesQ += ` AND tmdb_id IS NULL`
	}
	seriesList, err := m.collect(ctx, seriesQ, libraryID)
	if err != nil {
		return res, err
	}
	for _, it := range seriesList {
		match, err := m.provider.SearchSeries(ctx, it.title)
		if err != nil {
			m.logger.Warn("tmdb series search failed", "title", it.title, "err", err)
			continue
		}
		if match == nil {
			res.Misses++
			continue
		}
		if err := m.store(ctx, "series", "series", it.id, match); err != nil {
			return res, err
		}
		res.Series++
	}
	return res, nil
}

func (m *Matcher) collect(ctx context.Context, query, libraryID string) ([]matchItem, error) {
	rows, err := m.pool.Query(ctx, query, libraryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []matchItem
	for rows.Next() {
		var it matchItem
		var year *int
		if err := rows.Scan(&it.id, &it.title, &year); err != nil {
			return nil, err
		}
		if year != nil {
			it.year = *year
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (m *Matcher) store(ctx context.Context, table, artworkSub, id string, match *metadata.Match) error {
	posterRel := ""
	if match.PosterURL != "" {
		posterRel = path.Join(artworkSub, fmt.Sprintf("%d.jpg", match.TMDBID))
		dest := filepath.Join(m.artworkDir, filepath.FromSlash(posterRel))
		if err := m.download(ctx, match.PosterURL, dest); err != nil {
			m.logger.Warn("poster download failed", "url", match.PosterURL, "err", err)
			posterRel = ""
		}
	}

	backdropRel := ""
	if match.BackdropURL != "" {
		backdropRel = path.Join(artworkSub, fmt.Sprintf("%d-backdrop.jpg", match.TMDBID))
		dest := filepath.Join(m.artworkDir, filepath.FromSlash(backdropRel))
		if err := m.download(ctx, match.BackdropURL, dest); err != nil {
			m.logger.Warn("backdrop download failed", "url", match.BackdropURL, "err", err)
			backdropRel = ""
		}
	}

	pm := map[string]any{
		"source":    "tmdb",
		"tmdb_id":   match.TMDBID,
		"title":     match.Title,
		"year":      match.Year,
		"overview":  match.Overview,
		"genre_ids": match.GenreIDs,
	}
	// genres (names) and rating power the genre + rating filters; omit when absent
	// so unmatched/unrated items don't carry empty facets.
	if len(match.Genres) > 0 {
		pm["genres"] = match.Genres
	}
	if match.VoteCount > 0 {
		pm["vote_average"] = match.VoteAverage
		pm["vote_count"] = match.VoteCount
	}
	if posterRel != "" {
		pm["poster"] = posterRel
	}
	if backdropRel != "" {
		pm["backdrop"] = backdropRel
	}
	raw, err := json.Marshal(pm)
	if err != nil {
		return err
	}

	var query string
	switch table {
	case "media_items":
		query = `UPDATE media_items SET tmdb_id = $2, provider_metadata = $3, year = COALESCE($4, year), updated_at = now() WHERE id = $1`
	case "series":
		query = `UPDATE series SET tmdb_id = $2, provider_metadata = $3, year = COALESCE($4, year), updated_at = now() WHERE id = $1`
	default:
		return fmt.Errorf("unknown table %q", table)
	}

	var yearArg any
	if match.Year > 0 {
		yearArg = match.Year
	}
	_, err = m.pool.Exec(ctx, query, id, match.TMDBID, raw, yearArg)
	return err
}
