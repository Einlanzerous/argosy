// Package library serves the read-only browse API ("The Manifest"): libraries,
// movies, series with seasons/episodes, and item detail with effective metadata.
package library

import (
	"context"
	"errors"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Store runs the account-scoped browse queries.
type Store struct {
	pool        *pgxpool.Pool
	artworkBase string // URL prefix for cached artwork, e.g. "/artwork"
}

// NewStore returns a browse Store.
func NewStore(pool *pgxpool.Pool, artworkBase string) *Store {
	return &Store{pool: pool, artworkBase: artworkBase}
}

// Whitelisted ORDER BY clauses (never interpolate user input directly).
var movieSort = map[string]string{
	"title": "mi.sort_title ASC NULLS LAST, mi.title ASC",
	"added": "mi.added_at DESC",
	"year":  "mi.year DESC NULLS LAST, mi.title ASC",
}

var seriesSort = map[string]string{
	"title": "r.sort_title ASC NULLS LAST, r.title ASC",
	"year":  "r.year DESC NULLS LAST, r.title ASC",
}

// ListLibraries returns the account's libraries.
func (s *Store) ListLibraries(ctx context.Context, accountID string) ([]api.Library, error) {
	rows, err := s.pool.Query(ctx, `SELECT id::text, name, kind FROM libraries WHERE account_id = $1 ORDER BY name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.Library{}
	for rows.Next() {
		var id, name, kind string
		if err := rows.Scan(&id, &name, &kind); err != nil {
			return nil, err
		}
		out = append(out, api.Library{Id: parseUUID(id), Name: name, Kind: kind})
	}
	return out, rows.Err()
}

// ListMovies returns a paginated page of movies in a library.
func (s *Store) ListMovies(ctx context.Context, accountID, libraryID string, limit, offset int, sort string) (api.MediaItemPage, error) {
	order := movieSort[sort]
	if order == "" {
		order = movieSort["title"]
	}
	page := api.MediaItemPage{Items: []api.MediaItemSummary{}, Limit: limit, Offset: offset}
	if err := s.pool.QueryRow(ctx,
		`SELECT count(*) FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.library_id = $2 AND mi.kind = 'movie'`,
		accountID, libraryID).Scan(&page.Total); err != nil {
		return page, err
	}
	rows, err := s.pool.Query(ctx,
		`SELECT mi.id::text, mi.kind, mi.title, mi.year, mi.provider_metadata, mi.metadata
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.library_id = $2 AND mi.kind = 'movie'
		 ORDER BY `+order+` LIMIT $3 OFFSET $4`,
		accountID, libraryID, limit, offset)
	if err != nil {
		return page, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, kind, title string
		var year *int
		var prov, over []byte
		if err := rows.Scan(&id, &kind, &title, &year, &prov, &over); err != nil {
			return page, err
		}
		page.Items = append(page.Items, s.summary(id, kind, title, year, prov, over))
	}
	return page, rows.Err()
}

// ListSeries returns a paginated page of series in a library.
func (s *Store) ListSeries(ctx context.Context, accountID, libraryID string, limit, offset int, sort string) (api.SeriesPage, error) {
	order := seriesSort[sort]
	if order == "" {
		order = seriesSort["title"]
	}
	page := api.SeriesPage{Items: []api.SeriesSummary{}, Limit: limit, Offset: offset}
	if err := s.pool.QueryRow(ctx,
		`SELECT count(*) FROM series r JOIN libraries l ON l.id = r.library_id
		 WHERE l.account_id = $1 AND r.library_id = $2`,
		accountID, libraryID).Scan(&page.Total); err != nil {
		return page, err
	}
	rows, err := s.pool.Query(ctx,
		`SELECT r.id::text, r.title, r.year, r.provider_metadata, r.metadata
		 FROM series r JOIN libraries l ON l.id = r.library_id
		 WHERE l.account_id = $1 AND r.library_id = $2
		 ORDER BY `+order+` LIMIT $3 OFFSET $4`,
		accountID, libraryID, limit, offset)
	if err != nil {
		return page, err
	}
	defer rows.Close()
	for rows.Next() {
		var id, title string
		var year *int
		var prov, over []byte
		if err := rows.Scan(&id, &title, &year, &prov, &over); err != nil {
			return page, err
		}
		p, o := decodeMap(prov), decodeMap(over)
		item := api.SeriesSummary{Id: parseUUID(id), Title: effectiveTitle(o, p, title), Year: effectiveYear(o, p, year), PosterUrl: posterURL(s.artworkBase, o, p)}
		page.Items = append(page.Items, item)
	}
	return page, rows.Err()
}

// GetItem returns a single media item's detail, or nil if not found/not owned.
func (s *Store) GetItem(ctx context.Context, accountID, itemID string) (*api.MediaItemDetail, error) {
	var id, kind, title, filePath string
	var year *int
	var container *string
	var duration *float64
	var reviewRequired bool
	var prov, over []byte
	err := s.pool.QueryRow(ctx,
		`SELECT mi.id::text, mi.kind, mi.title, mi.year, mi.container, mi.duration_seconds,
		        mi.file_path, mi.review_required, mi.provider_metadata, mi.metadata
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&id, &kind, &title, &year, &container, &duration, &filePath, &reviewRequired, &prov, &over)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	p, o := decodeMap(prov), decodeMap(over)
	d := api.MediaItemDetail{
		Id:             parseUUID(id),
		Kind:           kind,
		Title:          effectiveTitle(o, p, title),
		Year:           effectiveYear(o, p, year),
		Overview:       effectiveOverview(o, p),
		Genres:         effectiveGenres(o, p),
		PosterUrl:      posterURL(s.artworkBase, o, p),
		Container:      container,
		FilePath:       filePath,
		ReviewRequired: reviewRequired,
	}
	if duration != nil {
		f := float32(*duration)
		d.DurationSeconds = &f
	}
	return &d, nil
}

// GetSeries returns a series with its seasons/episodes, or nil if not found.
func (s *Store) GetSeries(ctx context.Context, accountID, seriesID string) (*api.SeriesDetail, error) {
	var id, title string
	var year *int
	var prov, over []byte
	err := s.pool.QueryRow(ctx,
		`SELECT r.id::text, r.title, r.year, r.provider_metadata, r.metadata
		 FROM series r JOIN libraries l ON l.id = r.library_id
		 WHERE l.account_id = $1 AND r.id = $2`,
		accountID, seriesID).Scan(&id, &title, &year, &prov, &over)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	p, o := decodeMap(prov), decodeMap(over)
	detail := api.SeriesDetail{
		Id:        parseUUID(id),
		Title:     effectiveTitle(o, p, title),
		Year:      effectiveYear(o, p, year),
		Overview:  effectiveOverview(o, p),
		PosterUrl: posterURL(s.artworkBase, o, p),
		Seasons:   []api.SeasonSummary{},
	}

	rows, err := s.pool.Query(ctx,
		`SELECT se.id::text, se.season_number, se.title,
		        e.id::text, e.episode_number, e.title, e.media_item_id::text
		 FROM seasons se
		 LEFT JOIN episodes e ON e.season_id = se.id
		 WHERE se.series_id = $1
		 ORDER BY se.season_number, e.episode_number`, seriesID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	idx := map[string]int{} // season id -> index in detail.Seasons
	for rows.Next() {
		var seasonID string
		var seasonNum int
		var seasonTitle *string
		var epID, epTitle, epMediaItem *string
		var epNum *int
		if err := rows.Scan(&seasonID, &seasonNum, &seasonTitle, &epID, &epNum, &epTitle, &epMediaItem); err != nil {
			return nil, err
		}
		i, ok := idx[seasonID]
		if !ok {
			detail.Seasons = append(detail.Seasons, api.SeasonSummary{
				Id: parseUUID(seasonID), SeasonNumber: seasonNum, Title: seasonTitle, Episodes: []api.EpisodeSummary{},
			})
			i = len(detail.Seasons) - 1
			idx[seasonID] = i
		}
		if epID != nil && epNum != nil {
			ep := api.EpisodeSummary{Id: parseUUID(*epID), EpisodeNumber: *epNum, Title: epTitle}
			if epMediaItem != nil {
				u := parseUUID(*epMediaItem)
				ep.MediaItemId = &u
			}
			detail.Seasons[i].Episodes = append(detail.Seasons[i].Episodes, ep)
		}
	}
	return &detail, rows.Err()
}

func (s *Store) summary(id, kind, title string, year *int, prov, over []byte) api.MediaItemSummary {
	p, o := decodeMap(prov), decodeMap(over)
	return api.MediaItemSummary{
		Id:        parseUUID(id),
		Kind:      kind,
		Title:     effectiveTitle(o, p, title),
		Year:      effectiveYear(o, p, year),
		PosterUrl: posterURL(s.artworkBase, o, p),
	}
}
