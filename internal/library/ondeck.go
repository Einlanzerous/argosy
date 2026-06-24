package library

import (
	"context"
	"errors"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/jackc/pgx/v5"
)

// OnDeck returns each series' next "up next" episode for the user: the earliest
// episode after the furthest one they've watched, that they haven't started yet.
// In-progress episodes are intentionally excluded — those belong to Continue
// Watching (/continue) — so the two home rows never show the same item. Series
// are ordered by most-recent watch activity. Episode art falls back to the
// series' poster/backdrop.
func (s *Store) OnDeck(ctx context.Context, accountID, userID string, limit int) ([]api.OnDeckItem, error) {
	switch {
	case limit < 1:
		limit = 20
	case limit > 50:
		limit = 50
	}
	const q = `
WITH engaged AS (
	-- Episodes the user has engaged with (finished or started), with their ordinal
	-- (season*1000 + episode) and progress state.
	SELECT sr.id AS series_id,
	       (sea.season_number * 1000 + e.episode_number) AS pos,
	       ps.watched, ps.updated_at
	FROM play_state ps
	JOIN media_items mi ON mi.id = ps.media_item_id
	JOIN libraries l ON l.id = mi.library_id
	JOIN episodes e ON e.media_item_id = mi.id
	JOIN seasons sea ON sea.id = e.season_id
	JOIN series sr ON sr.id = sea.series_id
	WHERE l.account_id = $1 AND ps.user_id = $2 AND (ps.watched = true OR ps.position_seconds > 0)
),
frontier AS (
	-- The latest episode engaged per series, whether it was finished, and the
	-- series' most recent activity. Only finished frontiers yield an on-deck pick;
	-- an in-progress last episode is Continue Watching's job, not On Deck's.
	SELECT DISTINCT ON (series_id) series_id, pos, watched,
	       (SELECT max(updated_at) FROM engaged e2 WHERE e2.series_id = engaged.series_id) AS last_watched
	FROM engaged
	ORDER BY series_id, pos DESC
),
candidates AS (
	SELECT sr.id AS series_id, sr.title AS series_title,
	       sr.provider_metadata AS sprov, sr.metadata AS sover,
	       sea.season_number, e.episode_number, e.title AS ep_title,
	       mi.id AS item_id, mi.duration_seconds,
	       (sea.season_number * 1000 + e.episode_number) AS pos,
	       COALESCE(ps.watched, false) AS watched, COALESCE(ps.position_seconds, 0) AS position
	FROM series sr
	JOIN libraries l ON l.id = sr.library_id
	JOIN seasons sea ON sea.series_id = sr.id
	JOIN episodes e ON e.season_id = sea.id
	JOIN media_items mi ON mi.id = e.media_item_id
	LEFT JOIN play_state ps ON ps.media_item_id = mi.id AND ps.user_id = $2
	WHERE l.account_id = $1
)
SELECT item_id, series_id, series_title, sprov, sover, season_number, episode_number, ep_title, duration_seconds
FROM (
	SELECT DISTINCT ON (c.series_id)
	       c.item_id::text AS item_id, c.series_id::text AS series_id, c.series_title,
	       c.sprov, c.sover, c.season_number, c.episode_number, c.ep_title, c.duration_seconds,
	       f.last_watched
	FROM candidates c
	JOIN frontier f ON f.series_id = c.series_id AND f.watched = true
	WHERE c.pos > f.pos AND c.watched = false AND c.position = 0
	ORDER BY c.series_id, c.pos ASC
) nextup
ORDER BY last_watched DESC
LIMIT $3`
	rows, err := s.pool.Query(ctx, q, accountID, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.OnDeckItem{}
	for rows.Next() {
		var itemID, seriesID, seriesTitle string
		var seasonNum, epNum int
		var epTitle *string
		var sprov, sover []byte
		var dur *float64
		if err := rows.Scan(&itemID, &seriesID, &seriesTitle, &sprov, &sover, &seasonNum, &epNum, &epTitle, &dur); err != nil {
			return nil, err
		}
		sp, so := decodeMap(sprov), decodeMap(sover)
		item := api.OnDeckItem{
			Id:            parseUUID(itemID),
			SeriesId:      parseUUID(seriesID),
			SeriesTitle:   effectiveTitle(so, sp, seriesTitle),
			SeasonNumber:  seasonNum,
			EpisodeNumber: epNum,
			Title:         epTitle,
			PosterUrl:     posterURL(s.artworkBase, so, sp),
			BackdropUrl:   backdropURL(s.artworkBase, so, sp),
		}
		if dur != nil {
			d := float32(*dur)
			item.DurationSeconds = &d
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

// NextEpisode returns the next playable episode after itemID within its series —
// the next episode in the season, or the first episode of the next season once a
// season runs out. It skips episodes with no linked media file and returns nil
// when itemID is the last episode of the series (or isn't a series episode at
// all, e.g. a film). Episode art falls back to the series' poster/backdrop, like
// OnDeck. Account-scoped; resume position is intentionally not consulted here —
// the player fetches the next episode's own progress when it loads it.
func (s *Store) NextEpisode(ctx context.Context, accountID, itemID string) (*api.OnDeckItem, error) {
	const q = `
WITH cur AS (
	-- The current episode's series and its ordinal (season*1000 + episode).
	SELECT sea.series_id, (sea.season_number * 1000 + e.episode_number) AS pos
	FROM episodes e
	JOIN seasons sea ON sea.id = e.season_id
	JOIN media_items mi ON mi.id = e.media_item_id
	JOIN libraries l ON l.id = mi.library_id
	WHERE l.account_id = $1 AND e.media_item_id = $2
)
SELECT mi.id::text, sr.id::text, sr.title, sr.provider_metadata, sr.metadata,
       sea.season_number, e.episode_number, e.title, mi.duration_seconds
FROM cur
JOIN series sr ON sr.id = cur.series_id
JOIN seasons sea ON sea.series_id = sr.id
JOIN episodes e ON e.season_id = sea.id
JOIN media_items mi ON mi.id = e.media_item_id
WHERE (sea.season_number * 1000 + e.episode_number) > cur.pos
ORDER BY sea.season_number, e.episode_number
LIMIT 1`
	var itemIDOut, seriesID, seriesTitle string
	var seasonNum, epNum int
	var epTitle *string
	var sprov, sover []byte
	var dur *float64
	err := s.pool.QueryRow(ctx, q, accountID, itemID).
		Scan(&itemIDOut, &seriesID, &seriesTitle, &sprov, &sover, &seasonNum, &epNum, &epTitle, &dur)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	sp, so := decodeMap(sprov), decodeMap(sover)
	item := api.OnDeckItem{
		Id:            parseUUID(itemIDOut),
		SeriesId:      parseUUID(seriesID),
		SeriesTitle:   effectiveTitle(so, sp, seriesTitle),
		SeasonNumber:  seasonNum,
		EpisodeNumber: epNum,
		Title:         epTitle,
		PosterUrl:     posterURL(s.artworkBase, so, sp),
		BackdropUrl:   backdropURL(s.artworkBase, so, sp),
	}
	if dur != nil {
		d := float32(*dur)
		item.DurationSeconds = &d
	}
	return &item, nil
}
