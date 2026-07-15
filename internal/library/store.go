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

// Whitelisted ORDER BY clauses (never interpolate user input directly). The
// rating clause reads the effective rating (override blob over provider blob).
var movieSort = map[string]string{
	"title":  "mi.sort_title ASC NULLS LAST, mi.title ASC",
	"added":  "mi.added_at DESC",
	"year":   "mi.year DESC NULLS LAST, mi.title ASC",
	"rating": "(COALESCE(mi.metadata->>'vote_average', mi.provider_metadata->>'vote_average'))::numeric DESC NULLS LAST, mi.sort_title ASC NULLS LAST, mi.title ASC",
}

var seriesSort = map[string]string{
	"title":  "r.sort_title ASC NULLS LAST, r.title ASC",
	"year":   "r.year DESC NULLS LAST, r.title ASC",
	"rating": "(COALESCE(r.metadata->>'vote_average', r.provider_metadata->>'vote_average'))::numeric DESC NULLS LAST, r.sort_title ASC NULLS LAST, r.title ASC",
}

// ListLibraries returns the account's libraries. rootPath is populated here; the
// handler strips it for non-admins.
func (s *Store) ListLibraries(ctx context.Context, accountID string) ([]api.Library, error) {
	rows, err := s.pool.Query(ctx, `SELECT id::text, name, kind, root_path FROM libraries WHERE account_id = $1 ORDER BY name`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.Library{}
	for rows.Next() {
		var id, name, kind, rootPath string
		if err := rows.Scan(&id, &name, &kind, &rootPath); err != nil {
			return nil, err
		}
		rp := rootPath
		out = append(out, api.Library{Id: parseUUID(id), Name: name, Kind: kind, RootPath: &rp})
	}
	return out, rows.Err()
}

// CreateLibrary registers a new media library under the account.
func (s *Store) CreateLibrary(ctx context.Context, accountID, name, path, kind string) (api.Library, error) {
	var id string
	if err := s.pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,$3,$4) RETURNING id::text`,
		accountID, name, kind, path).Scan(&id); err != nil {
		return api.Library{}, err
	}
	rp := path
	return api.Library{Id: parseUUID(id), Name: name, Kind: kind, RootPath: &rp}, nil
}

// DeleteLibrary removes a library (its media cascades). Reports whether a row went.
func (s *Store) DeleteLibrary(ctx context.Context, accountID, libraryID string) (bool, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM libraries WHERE id = $1 AND account_id = $2`, libraryID, accountID)
	return tag.RowsAffected() > 0, err
}

// ListMovies returns a paginated page of movies in a library, narrowed by the
// given facet filter (tag, genres, rating, year range, and the per-user watched
// state — hence userID).
func (s *Store) ListMovies(ctx context.Context, accountID, libraryID, userID string, limit, offset int, sort string, f browseFilter) (api.MediaItemPage, error) {
	order := movieSort[sort]
	if order == "" {
		order = movieSort["title"]
	}
	page := api.MediaItemPage{Items: []api.MediaItemSummary{}, Limit: limit, Offset: offset}
	a := &sqlArgs{}
	acc, lib := a.add(accountID), a.add(libraryID)
	watchJoin, watchWhere := f.movieWatched(a, userID)
	from := ` FROM media_items mi JOIN libraries l ON l.id = mi.library_id` + watchJoin +
		` WHERE l.account_id = ` + acc + ` AND mi.library_id = ` + lib + ` AND mi.kind = 'movie'` +
		f.common("mi", a) + watchWhere
	if err := s.pool.QueryRow(ctx, `SELECT count(*)`+from, a.vals...).Scan(&page.Total); err != nil {
		return page, err
	}
	lim, off := a.add(limit), a.add(offset)
	rows, err := s.pool.Query(ctx,
		`SELECT mi.id::text, mi.kind, mi.title, mi.year, mi.provider_metadata, mi.metadata`+
			from+` ORDER BY `+order+` LIMIT `+lim+` OFFSET `+off,
		a.vals...)
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

// ListSeries returns a paginated page of series in a library, narrowed by the
// given facet filter. Watched state aggregates over each series' episodes.
func (s *Store) ListSeries(ctx context.Context, accountID, libraryID, userID string, limit, offset int, sort string, f browseFilter) (api.SeriesPage, error) {
	order := seriesSort[sort]
	if order == "" {
		order = seriesSort["title"]
	}
	page := api.SeriesPage{Items: []api.SeriesSummary{}, Limit: limit, Offset: offset}
	a := &sqlArgs{}
	acc, lib := a.add(accountID), a.add(libraryID)
	from := ` FROM series r JOIN libraries l ON l.id = r.library_id` +
		` WHERE l.account_id = ` + acc + ` AND r.library_id = ` + lib +
		f.common("r", a) + f.seriesWatched(a, userID)
	if err := s.pool.QueryRow(ctx, `SELECT count(*)`+from, a.vals...).Scan(&page.Total); err != nil {
		return page, err
	}
	lim, off := a.add(limit), a.add(offset)
	rows, err := s.pool.Query(ctx,
		`SELECT r.id::text, r.title, r.year, r.provider_metadata, r.metadata`+
			from+` ORDER BY `+order+` LIMIT `+lim+` OFFSET `+off,
		a.vals...)
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
		page.Items = append(page.Items, s.seriesSummary(id, title, year, prov, over))
	}
	return page, rows.Err()
}

// ListRecent returns a unified "newly arrived" feed across the account: films
// and series, newest first. A film's arrival is its own added_at; a series'
// arrival is the most recent of its episodes' added_at (so a series surfaces
// once, when any episode lands, rather than once per episode). Series rows carry
// kind "series"; films keep "movie".
func (s *Store) ListRecent(ctx context.Context, accountID string, limit int) ([]api.MediaItemSummary, error) {
	if limit < 1 {
		limit = 24
	}
	rows, err := s.pool.Query(ctx,
		`SELECT id, kind, title, year, prov, over FROM (
			SELECT mi.id::text AS id, mi.kind AS kind, mi.title AS title, mi.year AS year,
			       mi.provider_metadata AS prov, mi.metadata AS over,
			       mi.added_at AS added_at
			FROM media_items mi JOIN libraries l ON l.id = mi.library_id
			WHERE l.account_id = $1 AND mi.kind = 'movie'
			UNION ALL
			SELECT r.id::text, 'series', r.title, r.year, r.provider_metadata, r.metadata,
			       max(mi.added_at) AS added_at
			FROM series r
			JOIN libraries l ON l.id = r.library_id
			JOIN seasons se ON se.series_id = r.id
			JOIN episodes e ON e.season_id = se.id
			JOIN media_items mi ON mi.id = e.media_item_id
			WHERE l.account_id = $1
			GROUP BY r.id
		) feed
		ORDER BY added_at DESC NULLS LAST
		LIMIT $2`,
		accountID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.MediaItemSummary{}
	for rows.Next() {
		var id, kind, title string
		var year *int
		var prov, over []byte
		if err := rows.Scan(&id, &kind, &title, &year, &prov, &over); err != nil {
			return nil, err
		}
		out = append(out, s.summary(id, kind, title, year, prov, over))
	}
	return out, rows.Err()
}

// GetItem returns a single media item's detail, or nil if not found/not owned.
func (s *Store) GetItem(ctx context.Context, accountID, itemID string) (*api.MediaItemDetail, error) {
	var id, kind, title, filePath string
	var year *int
	var container *string
	var duration *float64
	var reviewRequired bool
	var prov, over []byte
	// Episode context (nullable): populated by the lateral join only when this
	// media item backs one or more episodes. A combined rip backs several episode
	// rows sharing this media_item — ORDER BY season, episode + LIMIT 1 picks the
	// first of the span so the header reads as its opening episode (ARGY-134).
	var seasonNum, epNum *int
	var epTitle, seriesTitle *string
	var seriesProv, seriesOver []byte
	err := s.pool.QueryRow(ctx,
		`SELECT mi.id::text, mi.kind, mi.title, mi.year, mi.container, mi.duration_seconds,
		        mi.file_path, mi.review_required, mi.provider_metadata, mi.metadata,
		        ep.season_number, ep.episode_number, ep.episode_title,
		        ep.series_title, ep.series_provider_metadata, ep.series_metadata
		 FROM media_items mi
		 JOIN libraries l ON l.id = mi.library_id
		 LEFT JOIN LATERAL (
		     SELECT sea.season_number, e.episode_number, e.title AS episode_title,
		            sr.title AS series_title,
		            sr.provider_metadata AS series_provider_metadata,
		            sr.metadata AS series_metadata
		     FROM episodes e
		     JOIN seasons sea ON sea.id = e.season_id
		     JOIN series sr ON sr.id = sea.series_id
		     WHERE e.media_item_id = mi.id
		     ORDER BY sea.season_number, e.episode_number
		     LIMIT 1
		 ) ep ON true
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&id, &kind, &title, &year, &container, &duration, &filePath, &reviewRequired, &prov, &over,
		&seasonNum, &epNum, &epTitle, &seriesTitle, &seriesProv, &seriesOver)
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
		BackdropUrl:    backdropURL(s.artworkBase, o, p),
		Container:      container,
		FilePath:       filePath,
		ReviewRequired: reviewRequired,
		Rating:         f32(effectiveRating(o, p)),
		Cast:           effectiveCast(o, p),
	}
	if duration != nil {
		f := float32(*duration)
		d.DurationSeconds = &f
	}
	if seriesTitle != nil {
		sp, so := decodeMap(seriesProv), decodeMap(seriesOver)
		st := effectiveTitle(so, sp, *seriesTitle)
		d.SeriesTitle = &st
		d.SeasonNumber = seasonNum
		d.EpisodeNumber = epNum
		d.EpisodeTitle = epTitle
	}
	return &d, nil
}

// GetSeries returns a series with its seasons/episodes (including each episode's
// runtime and the given user's resume progress), or nil if not found.
func (s *Store) GetSeries(ctx context.Context, accountID, userID, seriesID string) (*api.SeriesDetail, error) {
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
		Id:          parseUUID(id),
		Title:       effectiveTitle(o, p, title),
		Year:        effectiveYear(o, p, year),
		Overview:    effectiveOverview(o, p),
		PosterUrl:   posterURL(s.artworkBase, o, p),
		BackdropUrl: backdropURL(s.artworkBase, o, p),
		Seasons:     []api.SeasonSummary{},
		Cast:        effectiveCast(o, p),
	}

	rows, err := s.pool.Query(ctx,
		`SELECT se.id::text, se.season_number, se.title,
		        e.id::text, e.episode_number, e.title, e.media_item_id::text,
		        e.provider_metadata, e.metadata,
		        mi.duration_seconds, ps.position_seconds, ps.watched
		 FROM seasons se
		 LEFT JOIN episodes e ON e.season_id = se.id
		 LEFT JOIN media_items mi ON mi.id = e.media_item_id
		 LEFT JOIN play_state ps ON ps.media_item_id = e.media_item_id AND ps.user_id = $2
		 WHERE se.series_id = $1
		 ORDER BY se.season_number, e.episode_number`, seriesID, userID)
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
		var epProv, epOver []byte
		var epDuration, epPosition *float64
		var epWatched *bool
		if err := rows.Scan(&seasonID, &seasonNum, &seasonTitle, &epID, &epNum, &epTitle, &epMediaItem,
			&epProv, &epOver, &epDuration, &epPosition, &epWatched); err != nil {
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
			epP, epO := decodeMap(epProv), decodeMap(epOver)
			ep.Overview = effectiveOverview(epO, epP)
			ep.StillUrl = stillURL(s.artworkBase, epO, epP)
			ep.Rating = f32(effectiveRating(epO, epP))
			if epMediaItem != nil {
				u := parseUUID(*epMediaItem)
				ep.MediaItemId = &u
			}
			if epDuration != nil {
				f := float32(*epDuration)
				ep.DurationSeconds = &f
			}
			if epPosition != nil {
				f := float32(*epPosition)
				ep.PositionSeconds = &f
			}
			ep.Watched = epWatched
			detail.Seasons[i].Episodes = append(detail.Seasons[i].Episodes, ep)
		}
	}
	return &detail, rows.Err()
}

func (s *Store) seriesSummary(id, title string, year *int, prov, over []byte) api.SeriesSummary {
	p, o := decodeMap(prov), decodeMap(over)
	return api.SeriesSummary{
		Id:          parseUUID(id),
		Title:       effectiveTitle(o, p, title),
		Year:        effectiveYear(o, p, year),
		PosterUrl:   posterURL(s.artworkBase, o, p),
		BackdropUrl: backdropURL(s.artworkBase, o, p),
		Rating:      f32(effectiveRating(o, p)),
	}
}

func (s *Store) summary(id, kind, title string, year *int, prov, over []byte) api.MediaItemSummary {
	p, o := decodeMap(prov), decodeMap(over)
	return api.MediaItemSummary{
		Id:          parseUUID(id),
		Kind:        kind,
		Title:       effectiveTitle(o, p, title),
		Year:        effectiveYear(o, p, year),
		PosterUrl:   posterURL(s.artworkBase, o, p),
		BackdropUrl: backdropURL(s.artworkBase, o, p),
		Rating:      f32(effectiveRating(o, p)),
	}
}
