package library

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/beacon"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/presence"
	"github.com/jackc/pgx/v5"
)

// watchedThreshold: a title is "watched" once playback passes this fraction of
// its duration.
const watchedThreshold = 0.95

func (s *Store) itemInAccount(ctx context.Context, accountID, itemID string) (bool, error) {
	var ok bool
	err := s.pool.QueryRow(ctx,
		`SELECT exists(
		   SELECT 1 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		   WHERE mi.id = $1 AND l.account_id = $2)`,
		itemID, accountID).Scan(&ok)
	return ok, err
}

// GetProgress returns the play-state for (user, item), a zero state if none has
// been recorded, or nil when the item isn't in the account (→ 404).
func (s *Store) GetProgress(ctx context.Context, accountID, userID, itemID string) (*api.PlayState, error) {
	ok, err := s.itemInAccount(ctx, accountID, itemID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, nil
	}
	ps := &api.PlayState{}
	var pos float64
	var dur *float64
	var watched bool
	var upd *time.Time
	err = s.pool.QueryRow(ctx,
		`SELECT position_seconds, duration_seconds, watched, updated_at
		 FROM play_state WHERE user_id = $1 AND media_item_id = $2`,
		userID, itemID).Scan(&pos, &dur, &watched, &upd)
	if errors.Is(err, pgx.ErrNoRows) {
		return ps, nil // no row yet: zero position, not watched
	}
	if err != nil {
		return nil, err
	}
	ps.PositionSeconds = float32(pos)
	ps.Watched = watched
	ps.UpdatedAt = upd
	if dur != nil {
		d := float32(*dur)
		ps.DurationSeconds = &d
	}
	return ps, nil
}

// SetProgress upserts the resume position for (user, item), auto-flagging the
// item watched once it passes watchedThreshold. nil when the item isn't owned.
//
// Conflict policy (cross-device, ARGY-35): last-write-wins per (user, item).
// The single playhead reflects the user's most recent action, which correctly
// honors a deliberate rewind (a "furthest-progress" rule would not). Two of a
// user's devices playing the same item at once is rare (it's one person), and
// Beacon pushes every change to the other devices, so a write is never a silent
// clobber — the other device sees it within seconds.
func (s *Store) SetProgress(ctx context.Context, accountID, userID, deviceID, itemID string, pos float64, dur *float64) (*api.PlayState, error) {
	ok, err := s.itemInAccount(ctx, accountID, itemID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, nil
	}
	watched := dur != nil && *dur > 0 && pos >= *dur*watchedThreshold
	// device_id records which deck owns this playhead (ARGY-98). COALESCE on
	// conflict keeps the last known device when a write arrives without one
	// (e.g. an unauthenticated/legacy heartbeat) rather than blanking the pill.
	var devArg any
	if deviceID != "" {
		devArg = deviceID
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO play_state (user_id, media_item_id, position_seconds, duration_seconds, watched, device_id, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, now())
		 ON CONFLICT (user_id, media_item_id) DO UPDATE SET
		   position_seconds = EXCLUDED.position_seconds,
		   duration_seconds = COALESCE(EXCLUDED.duration_seconds, play_state.duration_seconds),
		   watched = EXCLUDED.watched,
		   device_id = COALESCE(EXCLUDED.device_id, play_state.device_id),
		   updated_at = now()`,
		userID, itemID, pos, dur, watched, devArg); err != nil {
		return nil, err
	}
	return s.GetProgress(ctx, accountID, userID, itemID)
}

// SetWatched flips the watched flag for (user, item), keeping any position.
func (s *Store) SetWatched(ctx context.Context, accountID, userID, itemID string, watched bool) (*api.PlayState, error) {
	ok, err := s.itemInAccount(ctx, accountID, itemID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, nil
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO play_state (user_id, media_item_id, position_seconds, watched, updated_at)
		 VALUES ($1, $2, 0, $3, now())
		 ON CONFLICT (user_id, media_item_id) DO UPDATE SET watched = EXCLUDED.watched, updated_at = now()`,
		userID, itemID, watched); err != nil {
		return nil, err
	}
	return s.GetProgress(ctx, accountID, userID, itemID)
}

// SetSeriesWatched flips the watched flag for every backing file of a series'
// episodes (ARGY-109). Returns nil when the series isn't in the account (→ 404).
// Resume positions are left intact — only the watched flag is written — matching
// the single-item SetWatched. Combined rips (one file → several episodes) are
// deduped so a file is written once.
func (s *Store) SetSeriesWatched(ctx context.Context, accountID, userID, seriesID string, watched bool) (*api.WatchedBulkResult, error) {
	var ok bool
	if err := s.pool.QueryRow(ctx,
		`SELECT exists(
		   SELECT 1 FROM series sr JOIN libraries l ON l.id = sr.library_id
		   WHERE sr.id = $1 AND l.account_id = $2)`,
		seriesID, accountID).Scan(&ok); err != nil {
		return nil, err
	}
	if !ok {
		return nil, nil
	}
	tag, err := s.pool.Exec(ctx,
		`INSERT INTO play_state (user_id, media_item_id, position_seconds, watched, updated_at)
		 SELECT $1, mid, 0, $3, now() FROM (
		     SELECT DISTINCT e.media_item_id AS mid
		     FROM episodes e
		     JOIN seasons se ON se.id = e.season_id
		     WHERE se.series_id = $2 AND e.media_item_id IS NOT NULL
		 ) q
		 ON CONFLICT (user_id, media_item_id) DO UPDATE SET watched = EXCLUDED.watched, updated_at = now()`,
		userID, seriesID, watched)
	if err != nil {
		return nil, err
	}
	return &api.WatchedBulkResult{Updated: int(tag.RowsAffected())}, nil
}

// SetSeasonWatched is SetSeriesWatched scoped to a single season (ARGY-109).
func (s *Store) SetSeasonWatched(ctx context.Context, accountID, userID, seasonID string, watched bool) (*api.WatchedBulkResult, error) {
	var ok bool
	if err := s.pool.QueryRow(ctx,
		`SELECT exists(
		   SELECT 1 FROM seasons se
		   JOIN series sr ON sr.id = se.series_id
		   JOIN libraries l ON l.id = sr.library_id
		   WHERE se.id = $1 AND l.account_id = $2)`,
		seasonID, accountID).Scan(&ok); err != nil {
		return nil, err
	}
	if !ok {
		return nil, nil
	}
	tag, err := s.pool.Exec(ctx,
		`INSERT INTO play_state (user_id, media_item_id, position_seconds, watched, updated_at)
		 SELECT $1, mid, 0, $3, now() FROM (
		     SELECT DISTINCT e.media_item_id AS mid
		     FROM episodes e
		     WHERE e.season_id = $2 AND e.media_item_id IS NOT NULL
		 ) q
		 ON CONFLICT (user_id, media_item_id) DO UPDATE SET watched = EXCLUDED.watched, updated_at = now()`,
		userID, seasonID, watched)
	if err != nil {
		return nil, err
	}
	return &api.WatchedBulkResult{Updated: int(tag.RowsAffected())}, nil
}

// ContinueWatching returns the profile's in-progress items (not watched, started),
// most-recent first — the home "Continue Watching" rail.
//
// Collapsed to at most one entry per series (ARGY-97): a show with several
// in-progress episodes shows up once, as its most-recently-active episode.
// Movies are keyed by their own item id, so each stays a standalone row. The
// LATERAL pins one series per item, so a combined multi-episode file (one
// media_item linked to several episodes, ARGY-69) can't fan out into duplicates.
// currentDeviceID is the requesting deck; the cross-device pill is suppressed for
// any item whose last-played device is that same deck (showing "you left off here"
// would be noise — ARGY-98).
func (s *Store) ContinueWatching(ctx context.Context, accountID, userID, currentDeviceID string, limit int) ([]api.ContinueItem, error) {
	rows, err := s.pool.Query(ctx,
		`WITH in_progress AS (
		     SELECT ps.media_item_id, ps.position_seconds, ps.duration_seconds, ps.updated_at,
		            ps.device_id, ep.series_id
		     FROM play_state ps
		     JOIN media_items mi ON mi.id = ps.media_item_id
		     JOIN libraries l ON l.id = mi.library_id
		     LEFT JOIN LATERAL (
		         SELECT sea.series_id
		         FROM episodes e
		         JOIN seasons sea ON sea.id = e.season_id
		         WHERE e.media_item_id = ps.media_item_id
		         LIMIT 1
		     ) ep ON true
		     WHERE l.account_id = $1 AND ps.user_id = $2
		       AND ps.watched = false AND ps.position_seconds > 0
		 ),
		 picked AS (
		     SELECT DISTINCT ON (COALESCE(series_id, media_item_id))
		            media_item_id, position_seconds, duration_seconds, updated_at, series_id, device_id
		     FROM in_progress
		     ORDER BY COALESCE(series_id, media_item_id), updated_at DESC
		 )
		 SELECT mi.id::text, mi.kind, mi.title, mi.year, mi.provider_metadata, mi.metadata,
		        p.position_seconds, p.duration_seconds,
		        sr.id::text, sr.title, sr.provider_metadata, sr.metadata,
		        d.id::text, d.name, d.platform
		 FROM picked p
		 JOIN media_items mi ON mi.id = p.media_item_id
		 LEFT JOIN series sr ON sr.id = p.series_id
		 LEFT JOIN devices d ON d.id = p.device_id AND d.revoked_at IS NULL
		 ORDER BY p.updated_at DESC LIMIT $3`,
		accountID, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []api.ContinueItem{}
	for rows.Next() {
		var id, kind, title string
		var year *int
		var prov, over []byte
		var pos float64
		var dur *float64
		var seriesID, seriesTitle *string
		var sprov, sover []byte
		var devID, devName, devPlatform *string
		if err := rows.Scan(&id, &kind, &title, &year, &prov, &over, &pos, &dur, &seriesID, &seriesTitle, &sprov, &sover, &devID, &devName, &devPlatform); err != nil {
			return nil, err
		}
		p, o := decodeMap(prov), decodeMap(over)
		ci := api.ContinueItem{
			Id:              parseUUID(id),
			Kind:            kind,
			Title:           effectiveTitle(o, p, title),
			Year:            effectiveYear(o, p, year),
			PositionSeconds: float32(pos),
		}
		poster := posterURL(s.artworkBase, o, p)
		backdrop := backdropURL(s.artworkBase, o, p)
		if seriesID != nil { // episode without its own art → fall back to series art
			so, sp := decodeMap(sover), decodeMap(sprov)
			if poster == nil {
				poster = posterURL(s.artworkBase, so, sp)
			}
			if backdrop == nil {
				backdrop = backdropURL(s.artworkBase, so, sp)
			}
		}
		ci.PosterUrl = poster
		ci.BackdropUrl = backdrop
		if dur != nil {
			d := float32(*dur)
			ci.DurationSeconds = &d
			if *dur > 0 {
				ci.Percent = float32(pos / *dur * 100)
			}
		}
		if seriesID != nil {
			u := parseUUID(*seriesID)
			ci.SeriesId = &u
		}
		ci.SeriesTitle = seriesTitle
		// Cross-device "left off on" pill: only when a known, still-paired device
		// owns the playhead AND it isn't the deck making this request (ARGY-98).
		if devID != nil && devName != nil && *devID != currentDeviceID {
			ci.LastPlayedDevice = &api.DeviceRef{
				Id:       parseUUID(*devID),
				Name:     *devName,
				Platform: devPlatform,
			}
		}
		out = append(out, ci)
	}
	return out, rows.Err()
}

// ---- handlers ----

func (h *handlers) getProgress(w http.ResponseWriter, r *http.Request) {
	ps, err := h.store.GetProgress(r.Context(), accountOf(r), userOf(r), r.PathValue("itemId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if ps == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	httpx.JSON(w, http.StatusOK, ps)
}

func (h *handlers) reportProgress(w http.ResponseWriter, r *http.Request) {
	var body api.ProgressUpdate
	if !decodeJSON(w, r, &body) {
		return
	}
	var dur *float64
	if body.DurationSeconds != nil {
		d := float64(*body.DurationSeconds)
		dur = &d
	}
	itemID := r.PathValue("itemId")
	sess, _ := auth.SessionFromContext(r.Context())
	ps, err := h.store.SetProgress(r.Context(), accountOf(r), userOf(r), sess.DeviceId.String(), itemID, float64(body.PositionSeconds), dur)
	if err != nil {
		h.fail(w, err)
		return
	}
	if ps == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	// The heartbeat is also a transcode liveness signal (ARGY-94): a client
	// buffered far ahead stops fetching segments but keeps reporting progress,
	// so keep its session alive while it's actually playing — otherwise the
	// idle reaper kills the transcode and the next segment 404s on drain.
	if h.tc != nil {
		h.tc.TouchItem(accountOf(r), itemID)
	}
	// The heartbeat doubles as a presence beat (ARGY-34) + a Beacon publish
	// (ARGY-36): refresh this device's live session, and broadcast the new
	// position to the user's other devices for cross-device resume.
	var durf float64
	if dur != nil {
		durf = *dur
	}
	if h.presence != nil {
		h.presence.Heartbeat(presence.Session{
			AccountID:       sess.AccountId.String(),
			UserID:          sess.UserId.String(),
			DeviceID:        sess.DeviceId.String(),
			ItemID:          itemID,
			PositionSeconds: float64(body.PositionSeconds),
			DurationSeconds: durf,
		})
	}
	h.publishBeacon(r, sess, itemID, float64(body.PositionSeconds), durf, ps.Watched)
	httpx.JSON(w, http.StatusOK, ps)
}

// publishBeacon broadcasts a play-state change to the user's other devices.
// OriginDeviceID lets the writing device ignore the echo of its own update.
func (h *handlers) publishBeacon(r *http.Request, sess api.Session, itemID string, pos, dur float64, watched bool) {
	if h.beacon == nil {
		return
	}
	if err := h.beacon.Publish(r.Context(), beacon.Event{
		UserID:          sess.UserId.String(),
		ItemID:          itemID,
		PositionSeconds: pos,
		DurationSeconds: dur,
		Watched:         watched,
		OriginDeviceID:  sess.DeviceId.String(),
		UpdatedAt:       time.Now(),
	}); err != nil {
		h.logger.Warn("beacon: publish failed", "err", err)
	}
}

func (h *handlers) setWatched(w http.ResponseWriter, r *http.Request) {
	var body api.WatchedUpdate
	if !decodeJSON(w, r, &body) {
		return
	}
	itemID := r.PathValue("itemId")
	ps, err := h.store.SetWatched(r.Context(), accountOf(r), userOf(r), itemID, body.Watched)
	if err != nil {
		h.fail(w, err)
		return
	}
	if ps == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	// Broadcast the watched-state change so other devices update live.
	sess, _ := auth.SessionFromContext(r.Context())
	var durf float64
	if ps.DurationSeconds != nil {
		durf = float64(*ps.DurationSeconds)
	}
	h.publishBeacon(r, sess, itemID, float64(ps.PositionSeconds), durf, ps.Watched)
	httpx.JSON(w, http.StatusOK, ps)
}

func (h *handlers) setSeriesWatched(w http.ResponseWriter, r *http.Request) {
	var body api.WatchedUpdate
	if !decodeJSON(w, r, &body) {
		return
	}
	res, err := h.store.SetSeriesWatched(r.Context(), accountOf(r), userOf(r), r.PathValue("seriesId"), body.Watched)
	if err != nil {
		h.fail(w, err)
		return
	}
	if res == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	httpx.JSON(w, http.StatusOK, res)
}

func (h *handlers) setSeasonWatched(w http.ResponseWriter, r *http.Request) {
	var body api.WatchedUpdate
	if !decodeJSON(w, r, &body) {
		return
	}
	res, err := h.store.SetSeasonWatched(r.Context(), accountOf(r), userOf(r), r.PathValue("seasonId"), body.Watched)
	if err != nil {
		h.fail(w, err)
		return
	}
	if res == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	httpx.JSON(w, http.StatusOK, res)
}

func (h *handlers) listContinue(w http.ResponseWriter, r *http.Request) {
	items, err := h.store.ContinueWatching(r.Context(), accountOf(r), userOf(r), deviceOf(r), 20)
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, items)
}

func (h *handlers) listOnDeck(w http.ResponseWriter, r *http.Request) {
	limit := 20
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 {
		limit = v
	}
	items, err := h.store.OnDeck(r.Context(), accountOf(r), userOf(r), limit)
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, items)
}

// getNextEpisode powers the player's auto-advance: it returns the episode that
// follows the requested one in its series, or 404 when there's nothing after it
// (last episode, or the item isn't a series episode).
func (h *handlers) getNextEpisode(w http.ResponseWriter, r *http.Request) {
	next, err := h.store.NextEpisode(r.Context(), accountOf(r), r.PathValue("itemId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if next == nil {
		httpx.Error(w, http.StatusNotFound, "no next episode")
		return
	}
	httpx.JSON(w, http.StatusOK, next)
}

func userOf(r *http.Request) string {
	sess, _ := auth.SessionFromContext(r.Context())
	return sess.UserId.String()
}

func deviceOf(r *http.Request) string {
	sess, _ := auth.SessionFromContext(r.Context())
	return sess.DeviceId.String()
}

func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid request body")
		return false
	}
	return true
}
