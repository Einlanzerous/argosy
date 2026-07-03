package library

import (
	"strconv"
	"strings"
)

// browseFilter holds the optional facet filters shared by the movie and series
// browse endpoints. Zero values mean "no constraint", so an empty browseFilter
// is the unfiltered listing.
type browseFilter struct {
	Genres    []string // any-of: effective genres must include at least one
	RatingMin float64  // effective rating >= this (0 disables)
	Watched   string   // per-user state: "watched" | "unwatched" | "in_progress"
	YearFrom  int      // effective year >= this (0 disables)
	YearTo    int      // effective year <= this (0 disables)
}

// sqlArgs accumulates positional query args and hands out $N placeholders, so a
// dynamically-assembled WHERE clause stays injection-safe (user values are only
// ever passed as bound parameters, never interpolated).
type sqlArgs struct{ vals []any }

func (a *sqlArgs) add(v any) string {
	a.vals = append(a.vals, v)
	return "$" + strconv.Itoa(len(a.vals))
}

// common renders the entity-agnostic facet predicates (genres, rating, year
// range) for the given column alias ("mi" or "r"). Genres and rating read the
// effective value — the override blob (metadata) wins over the provider blob,
// matching effectiveGenres/effectiveRating.
func (f browseFilter) common(alias string, a *sqlArgs) string {
	var b strings.Builder
	if len(f.Genres) > 0 {
		b.WriteString(" AND jsonb_exists_any(COALESCE(" +
			alias + ".metadata->'genres', " + alias + ".provider_metadata->'genres', '[]'::jsonb), " +
			a.add(f.Genres) + ")")
	}
	if f.RatingMin > 0 {
		b.WriteString(" AND (COALESCE(" +
			alias + ".metadata->>'vote_average', " + alias + ".provider_metadata->>'vote_average'" +
			"))::numeric >= " + a.add(f.RatingMin))
	}
	if f.YearFrom > 0 {
		b.WriteString(" AND " + alias + ".year >= " + a.add(f.YearFrom))
	}
	if f.YearTo > 0 {
		b.WriteString(" AND " + alias + ".year <= " + a.add(f.YearTo))
	}
	return b.String()
}

// movieWatched returns an extra JOIN and WHERE fragment implementing the per-user
// watched-state filter for films, keyed on the user's play_state row.
func (f browseFilter) movieWatched(a *sqlArgs, userID string) (join, where string) {
	if f.Watched == "" {
		return "", ""
	}
	u := a.add(userID)
	join = " LEFT JOIN play_state ps ON ps.media_item_id = mi.id AND ps.user_id = " + u
	switch f.Watched {
	case "watched":
		where = " AND ps.watched = true"
	case "unwatched":
		where = " AND (ps.media_item_id IS NULL OR (ps.watched = false AND COALESCE(ps.position_seconds, 0) = 0))"
	case "in_progress":
		where = " AND ps.watched = false AND COALESCE(ps.position_seconds, 0) > 0"
	}
	return join, where
}

// seriesWatched implements the watched-state filter for series by aggregating
// over the series' episodes (via play_state for this user):
//   - watched: has episodes and none is left unwatched
//   - unwatched: no episode has been started or finished
//   - in_progress: some progress exists but not every episode is watched
func (f browseFilter) seriesWatched(a *sqlArgs, userID string) string {
	if f.Watched == "" {
		return ""
	}
	u := a.add(userID)
	from := "FROM seasons se JOIN episodes e ON e.season_id = se.id JOIN media_items emi ON emi.id = e.media_item_id"
	withPS := from + " LEFT JOIN play_state ps ON ps.media_item_id = emi.id AND ps.user_id = " + u
	started := "(ps.watched IS TRUE OR COALESCE(ps.position_seconds, 0) > 0)"
	switch f.Watched {
	case "watched":
		return " AND EXISTS (SELECT 1 " + from + " WHERE se.series_id = r.id)" +
			" AND NOT EXISTS (SELECT 1 " + withPS + " WHERE se.series_id = r.id AND ps.watched IS NOT TRUE)"
	case "unwatched":
		return " AND NOT EXISTS (SELECT 1 " + withPS + " WHERE se.series_id = r.id AND " + started + ")"
	case "in_progress":
		return " AND EXISTS (SELECT 1 " + withPS + " WHERE se.series_id = r.id AND " + started + ")" +
			" AND EXISTS (SELECT 1 " + withPS + " WHERE se.series_id = r.id AND ps.watched IS NOT TRUE)"
	}
	return ""
}
