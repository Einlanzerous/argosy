package library

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/ballast"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/jackc/pgx/v5/pgxpool"
)

type handlers struct {
	store   *Store
	logger  *slog.Logger
	tc      *transcode.Manager
	caps    transcode.Capabilities
	encoder string
	cache   *ballast.Sweeper
	subs    *subtitle.Service
}

// RegisterRoutes wires the auth-scoped browse endpoints and the public artwork
// file server onto mux. artworkDir == "" disables artwork serving. tc may be nil
// to disable the transcode (The Helm) endpoints; sweeper may be nil to disable
// the cache-stats endpoint.
func RegisterRoutes(mux *http.ServeMux, pool *pgxpool.Pool, authStore *auth.Store, artworkDir, artworkBase string, logger *slog.Logger, tc *transcode.Manager, caps transcode.Capabilities, encoder string, sweeper *ballast.Sweeper, subs *subtitle.Service) {
	h := &handlers{store: NewStore(pool, artworkBase), logger: logger, tc: tc, caps: caps, encoder: encoder, cache: sweeper, subs: subs}
	mw := auth.Middleware(authStore)

	mux.Handle("GET /api/v1/libraries", mw(http.HandlerFunc(h.listLibraries)))
	mux.Handle("GET /api/v1/libraries/{libraryId}/movies", mw(http.HandlerFunc(h.listMovies)))
	mux.Handle("GET /api/v1/libraries/{libraryId}/series", mw(http.HandlerFunc(h.listSeries)))
	mux.Handle("GET /api/v1/series/{seriesId}", mw(http.HandlerFunc(h.getSeries)))
	mux.Handle("GET /api/v1/items/{itemId}", mw(http.HandlerFunc(h.getItem)))
	mux.Handle("GET /api/v1/continue", mw(http.HandlerFunc(h.listContinue)))
	mux.Handle("GET /api/v1/items/{itemId}/playback", mw(http.HandlerFunc(h.getPlayback)))
	mux.Handle("GET /api/v1/items/{itemId}/progress", mw(http.HandlerFunc(h.getProgress)))
	mux.Handle("PUT /api/v1/items/{itemId}/progress", mw(http.HandlerFunc(h.reportProgress)))
	mux.Handle("POST /api/v1/items/{itemId}/watched", mw(http.HandlerFunc(h.setWatched)))
	// Streaming authenticates inline (token may be a ?token= query param) since
	// an HTML5 <video> element can't set the Authorization header.
	mux.Handle("GET /api/v1/items/{itemId}/stream", streamHandler(h.store, authStore, logger))

	// Subtitles (ARGY-31): list tracks behind the bearer middleware; serve the
	// WebVTT file with inline auth (a <track> element can't set headers, so the
	// per-device token may arrive as ?token=).
	if subs != nil {
		mux.Handle("GET /api/v1/items/{itemId}/subtitles", mw(http.HandlerFunc(h.listSubtitles)))
		mux.Handle("GET /api/v1/items/{itemId}/subtitles/{trackId}", subtitleFileHandler(h.store, subs, authStore, logger))
	}

	// The Helm: transcode session orchestration + HLS delivery (ARGY-27).
	if tc != nil {
		mux.Handle("POST /api/v1/items/{itemId}/transcode", mw(http.HandlerFunc(h.startTranscode)))
		mux.Handle("GET /api/v1/transcode/sessions", mw(http.HandlerFunc(h.listTranscodeSessions)))
		mux.Handle("DELETE /api/v1/transcode/{sessionId}", mw(http.HandlerFunc(h.stopTranscode)))
		mux.Handle("GET /api/v1/transcode/capabilities", mw(http.HandlerFunc(h.transcodeCapabilities)))
		if sweeper != nil {
			mux.Handle("GET /api/v1/transcode/cache", mw(http.HandlerFunc(h.transcodeCache)))
		}
		mux.Handle("GET /api/v1/transcode/{sessionId}/{file}", mw(http.HandlerFunc(h.fileTranscode)))
	}

	if artworkDir != "" {
		mux.Handle("GET /artwork/", http.StripPrefix("/artwork/", http.FileServer(http.Dir(artworkDir))))
	}
}

func (h *handlers) listLibraries(w http.ResponseWriter, r *http.Request) {
	libs, err := h.store.ListLibraries(r.Context(), accountOf(r))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, libs)
}

func (h *handlers) listMovies(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	page, err := h.store.ListMovies(r.Context(), accountOf(r), r.PathValue("libraryId"), limit, offset, r.URL.Query().Get("sort"), r.URL.Query().Get("tag"))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (h *handlers) listSeries(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	page, err := h.store.ListSeries(r.Context(), accountOf(r), r.PathValue("libraryId"), limit, offset, r.URL.Query().Get("sort"), r.URL.Query().Get("tag"))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (h *handlers) getSeries(w http.ResponseWriter, r *http.Request) {
	d, err := h.store.GetSeries(r.Context(), accountOf(r), userOf(r), r.PathValue("seriesId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if d == nil {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	writeJSON(w, http.StatusOK, d)
}

func (h *handlers) getItem(w http.ResponseWriter, r *http.Request) {
	d, err := h.store.GetItem(r.Context(), accountOf(r), r.PathValue("itemId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if d == nil {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	writeJSON(w, http.StatusOK, d)
}

func accountOf(r *http.Request) string {
	sess, _ := auth.SessionFromContext(r.Context())
	return sess.AccountId.String()
}

func pagination(r *http.Request) (limit, offset int) {
	limit, offset = 50, 0
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil {
		limit = v
	}
	switch {
	case limit < 1:
		limit = 1
	case limit > 200:
		limit = 200
	}
	if v, err := strconv.Atoi(r.URL.Query().Get("offset")); err == nil && v >= 0 {
		offset = v
	}
	return limit, offset
}

func (h *handlers) fail(w http.ResponseWriter, err error) {
	h.logger.Error("browse query failed", "err", err)
	writeJSON(w, http.StatusInternalServerError, errorBody("internal error"))
}

func errorBody(msg string) map[string]string { return map[string]string{"error": msg} }

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
