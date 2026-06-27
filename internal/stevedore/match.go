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
	Movies   int
	Series   int
	Episodes int // episode rows enriched with per-episode TMDB metadata
	Credits  int // movies + series enriched with cast/people for search (ARGY-67)
	Misses   int
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

	// Per-episode metadata: now that series carry a tmdb_id, fill in each
	// episode's name/overview/still. Runs over every matched series (not just
	// the ones matched this pass) so episode files added after the series was
	// first matched get enriched too; cheap because it only touches episodes
	// still missing provider metadata unless force is set.
	n, err := m.matchEpisodes(ctx, libraryID, force)
	if err != nil {
		return res, err
	}
	res.Episodes = n

	// People/cast (ARGY-67): backfill top-billed cast onto every matched movie +
	// series still missing it. Runs over all matched items (not just this pass),
	// so a plain `match` enriches the existing library, and the STORED
	// search_vector picks the names up on the write — no separate backfill job.
	c, err := m.matchCredits(ctx, libraryID, force)
	if err != nil {
		return res, err
	}
	res.Credits = c
	return res, nil
}

// matchCredits writes top-billed cast names into provider_metadata.cast for the
// matched movies + series of a library, so people/cast become searchable. Without
// force it only touches rows that don't yet carry a `cast` key, making it cheap
// and idempotent across rescans; the credits key is always set (even to an empty
// array) once fetched so a cast-less title isn't re-queried every run. Returns
// the number of rows enriched.
func (m *Matcher) matchCredits(ctx context.Context, libraryID string, force bool) (int, error) {
	credits := func(table, kind string, fetch func(context.Context, int64) ([]string, error)) (int, error) {
		q := `SELECT id::text, tmdb_id FROM ` + table + ` WHERE library_id = $1 AND tmdb_id IS NOT NULL`
		if kind != "" {
			q += ` AND kind = '` + kind + `'`
		}
		if !force {
			q += ` AND NOT (provider_metadata ? 'cast')`
		}
		rows, err := m.pool.Query(ctx, q, libraryID)
		if err != nil {
			return 0, err
		}
		type row struct {
			id   string
			tmdb int64
		}
		var items []row
		for rows.Next() {
			var r row
			if err := rows.Scan(&r.id, &r.tmdb); err != nil {
				rows.Close()
				return 0, err
			}
			items = append(items, r)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return 0, err
		}

		count := 0
		for _, it := range items {
			cast, err := fetch(ctx, it.tmdb)
			if err != nil {
				m.logger.Warn("tmdb credits fetch failed", "table", table, "tmdb_id", it.tmdb, "err", err)
				continue
			}
			raw, err := json.Marshal(cast)
			if err != nil {
				return count, err
			}
			if _, err := m.pool.Exec(ctx,
				`UPDATE `+table+` SET provider_metadata = jsonb_set(provider_metadata, '{cast}', $2::jsonb, true), updated_at = now() WHERE id = $1`,
				it.id, raw); err != nil {
				return count, err
			}
			count++
		}
		return count, nil
	}

	movies, err := credits("media_items", "movie", m.provider.MovieCredits)
	if err != nil {
		return 0, err
	}
	series, err := credits("series", "", m.provider.SeriesCredits)
	if err != nil {
		return movies, err
	}
	return movies + series, nil
}

// matchEpisodes fetches per-season episode lists from the provider for every
// matched series in the library and writes each episode's name + overview +
// still. Returns the number of episode rows enriched.
func (m *Matcher) matchEpisodes(ctx context.Context, libraryID string, force bool) (int, error) {
	rows, err := m.pool.Query(ctx,
		`SELECT id::text, tmdb_id FROM series WHERE library_id = $1 AND tmdb_id IS NOT NULL`, libraryID)
	if err != nil {
		return 0, err
	}
	type ser struct {
		id   string
		tmdb int64
	}
	var seriesList []ser
	for rows.Next() {
		var s ser
		if err := rows.Scan(&s.id, &s.tmdb); err != nil {
			rows.Close()
			return 0, err
		}
		seriesList = append(seriesList, s)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	total := 0
	for _, s := range seriesList {
		n, err := m.matchSeriesEpisodes(ctx, s.id, s.tmdb, force)
		if err != nil {
			return total, err
		}
		total += n
	}
	return total, nil
}

func (m *Matcher) matchSeriesEpisodes(ctx context.Context, seriesID string, tmdbID int64, force bool) (int, error) {
	// Only the seasons with episodes still missing metadata (all of them when
	// force) — avoids re-hitting TMDB for already-enriched seasons on rescans.
	seasonQ := `SELECT DISTINCT se.season_number FROM seasons se JOIN episodes e ON e.season_id = se.id WHERE se.series_id = $1`
	if !force {
		seasonQ += ` AND e.provider_metadata = '{}'::jsonb`
	}
	rows, err := m.pool.Query(ctx, seasonQ, seriesID)
	if err != nil {
		return 0, err
	}
	var seasons []int
	for rows.Next() {
		var n int
		if err := rows.Scan(&n); err != nil {
			rows.Close()
			return 0, err
		}
		seasons = append(seasons, n)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	count := 0
	for _, seasonNum := range seasons {
		eps, err := m.provider.SeasonEpisodes(ctx, tmdbID, seasonNum)
		if err != nil {
			m.logger.Warn("tmdb season fetch failed", "tmdb_id", tmdbID, "season", seasonNum, "err", err)
			continue
		}
		byNum := make(map[int]metadata.EpisodeMeta, len(eps))
		for _, e := range eps {
			byNum[e.Number] = e
		}
		n, err := m.storeSeasonEpisodes(ctx, seriesID, tmdbID, seasonNum, byNum, force)
		if err != nil {
			return count, err
		}
		count += n
	}
	return count, nil
}

// storeSeasonEpisodes writes provider metadata onto the episode rows of one
// season, matching on episode_number. Each combined-file row (several numbers
// sharing one media_item) is matched independently, so E01 and E02 of a merged
// rip each get their own name/overview/still.
func (m *Matcher) storeSeasonEpisodes(ctx context.Context, seriesID string, tmdbID int64, seasonNum int, byNum map[int]metadata.EpisodeMeta, force bool) (int, error) {
	epQ := `SELECT e.id::text, e.episode_number FROM episodes e JOIN seasons se ON se.id = e.season_id
	        WHERE se.series_id = $1 AND se.season_number = $2`
	if !force {
		epQ += ` AND e.provider_metadata = '{}'::jsonb`
	}
	rows, err := m.pool.Query(ctx, epQ, seriesID, seasonNum)
	if err != nil {
		return 0, err
	}
	type epRow struct {
		id  string
		num int
	}
	var epRows []epRow
	for rows.Next() {
		var e epRow
		if err := rows.Scan(&e.id, &e.num); err != nil {
			rows.Close()
			return 0, err
		}
		epRows = append(epRows, e)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	count := 0
	for _, e := range epRows {
		meta, ok := byNum[e.num]
		if !ok {
			continue
		}

		stillRel := ""
		if meta.StillURL != "" {
			stillRel = path.Join("episodes", fmt.Sprintf("%d-s%de%d.jpg", tmdbID, seasonNum, e.num))
			dest := filepath.Join(m.artworkDir, filepath.FromSlash(stillRel))
			if err := m.download(ctx, meta.StillURL, dest); err != nil {
				m.logger.Warn("episode still download failed", "url", meta.StillURL, "err", err)
				stillRel = ""
			}
		}

		pm := map[string]any{"source": "tmdb"}
		if meta.Overview != "" {
			pm["overview"] = meta.Overview
		}
		if stillRel != "" {
			pm["still"] = stillRel
		}
		raw, err := json.Marshal(pm)
		if err != nil {
			return count, err
		}

		// Replace the SxxExx filename fallback with the real episode name; keep
		// the existing title when TMDB has no name so we never blank it out.
		if _, err := m.pool.Exec(ctx,
			`UPDATE episodes SET title = COALESCE(NULLIF($2, ''), title), provider_metadata = $3, updated_at = now() WHERE id = $1`,
			e.id, meta.Name, raw); err != nil {
			return count, err
		}
		count++
	}
	return count, nil
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
