package library

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/jackc/pgx/v5"
)

// subtitleTarget resolves everything the subtitle service needs for an item the
// account owns: the absolute media path plus the identifiers used to match
// external subtitles (movie tmdb, or series tmdb + season/episode). ok is false
// when the item isn't found.
func (s *Store) subtitleTarget(ctx context.Context, accountID, itemID string) (subtitle.Target, bool, error) {
	var root, rel string
	var technical []byte
	var movieTMDB, seriesTMDB *int64
	var season, episode *int
	err := s.pool.QueryRow(ctx,
		`SELECT l.root_path, mi.file_path, mi.technical, mi.tmdb_id,
		        s.tmdb_id, se.season_number, e.episode_number
		 FROM media_items mi
		 JOIN libraries l ON l.id = mi.library_id
		 LEFT JOIN episodes e ON e.media_item_id = mi.id
		 LEFT JOIN seasons se ON se.id = e.season_id
		 LEFT JOIN series s ON s.id = se.series_id
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&root, &rel, &technical, &movieTMDB, &seriesTMDB, &season, &episode)
	if errors.Is(err, pgx.ErrNoRows) {
		return subtitle.Target{}, false, nil
	}
	if err != nil {
		return subtitle.Target{}, false, err
	}
	abs, err := resolveWithinRoot(root, rel)
	if err != nil {
		return subtitle.Target{}, false, err
	}
	t := subtitle.Target{
		ItemID:    itemID,
		Path:      abs,
		Technical: technical,
	}
	if movieTMDB != nil {
		t.TMDBID = *movieTMDB
	}
	if seriesTMDB != nil {
		t.ParentTMDBID = *seriesTMDB
	}
	if season != nil {
		t.Season = *season
	}
	if episode != nil {
		t.Episode = *episode
	}
	return t, true, nil
}

// listSubtitles returns the available subtitle tracks for an item (embedded text
// tracks + OpenSubtitles candidates).
func (h *handlers) listSubtitles(w http.ResponseWriter, r *http.Request) {
	t, ok, err := h.store.subtitleTarget(r.Context(), accountOf(r), r.PathValue("itemId"))
	if errors.Is(err, ErrPathTraversal) {
		writeJSON(w, http.StatusForbidden, errorBody("forbidden"))
		return
	}
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	writeJSON(w, http.StatusOK, h.subs.List(r.Context(), t))
}

// subtitleFileHandler serves a track's WebVTT file. Like the stream endpoint it
// authenticates inline, since a <track> element can't send an Authorization
// header (the token may arrive as ?token=).
func subtitleFileHandler(store *Store, subs *subtitle.Service, authStore *auth.Store, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := streamToken(r)
		if token == "" {
			writeJSON(w, http.StatusUnauthorized, errorBody("missing token"))
			return
		}
		sess, err := authStore.AuthenticateDevice(r.Context(), token)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, errorBody("invalid or revoked token"))
			return
		}
		t, ok, err := store.subtitleTarget(r.Context(), sess.AccountId.String(), r.PathValue("itemId"))
		if errors.Is(err, ErrPathTraversal) {
			writeJSON(w, http.StatusForbidden, errorBody("forbidden"))
			return
		}
		if err != nil {
			logger.Error("subtitle: resolve target failed", "err", err)
			writeJSON(w, http.StatusInternalServerError, errorBody("internal error"))
			return
		}
		if !ok {
			writeJSON(w, http.StatusNotFound, errorBody("not found"))
			return
		}

		path, err := subs.VTT(r.Context(), t, r.PathValue("trackId"))
		if err != nil {
			logger.Error("subtitle: produce vtt failed", "item", t.ItemID, "track", r.PathValue("trackId"), "err", err)
			writeJSON(w, http.StatusBadGateway, errorBody("subtitle unavailable"))
			return
		}
		w.Header().Set("Content-Type", "text/vtt; charset=utf-8")
		http.ServeFile(w, r, path)
	}
}
