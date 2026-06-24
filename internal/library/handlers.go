package library

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"strconv"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/ballast"
	"github.com/Einlanzerous/argosy/internal/beacon"
	"github.com/Einlanzerous/argosy/internal/presence"
	"github.com/Einlanzerous/argosy/internal/subtitle"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/jackc/pgx/v5/pgxpool"
)

type handlers struct {
	store    *Store
	logger   *slog.Logger
	tc       *transcode.Manager
	caps     transcode.Capabilities
	encoder  string
	cache    *ballast.Sweeper
	subs     *subtitle.Service
	presence *presence.Registry
	beacon   *beacon.Hub
}

// RegisterRoutes wires the auth-scoped browse endpoints and the public artwork
// file server onto mux. artworkDir == "" disables artwork serving. tc may be nil
// to disable the transcode (The Helm) endpoints; sweeper may be nil to disable
// the cache-stats endpoint.
func RegisterRoutes(mux *http.ServeMux, pool *pgxpool.Pool, authStore *auth.Store, artworkDir, artworkBase string, logger *slog.Logger, tc *transcode.Manager, caps transcode.Capabilities, encoder string, sweeper *ballast.Sweeper, subs *subtitle.Service, pres *presence.Registry, hub *beacon.Hub) {
	h := &handlers{store: NewStore(pool, artworkBase), logger: logger, tc: tc, caps: caps, encoder: encoder, cache: sweeper, subs: subs, presence: pres, beacon: hub}
	mw := auth.Middleware(authStore)

	mux.Handle("GET /api/v1/libraries", mw(http.HandlerFunc(h.listLibraries)))
	mux.Handle("POST /api/v1/libraries", mw(auth.RequireAdmin(http.HandlerFunc(h.createLibrary))))
	mux.Handle("DELETE /api/v1/libraries/{libraryId}", mw(auth.RequireAdmin(http.HandlerFunc(h.deleteLibrary))))
	mux.Handle("GET /api/v1/libraries/{libraryId}/movies", mw(http.HandlerFunc(h.listMovies)))
	mux.Handle("GET /api/v1/libraries/{libraryId}/series", mw(http.HandlerFunc(h.listSeries)))
	mux.Handle("GET /api/v1/series/{seriesId}", mw(http.HandlerFunc(h.getSeries)))
	mux.Handle("GET /api/v1/items/{itemId}", mw(http.HandlerFunc(h.getItem)))
	mux.Handle("GET /api/v1/continue", mw(http.HandlerFunc(h.listContinue)))
	mux.Handle("GET /api/v1/ondeck", mw(http.HandlerFunc(h.listOnDeck)))
	mux.Handle("GET /api/v1/recent", mw(http.HandlerFunc(h.listRecent)))
	mux.Handle("GET /api/v1/search", mw(http.HandlerFunc(h.search)))
	mux.Handle("GET /api/v1/facets", mw(http.HandlerFunc(h.listFacets)))

	// User labels (ARGY-73): the calling profile's custom tags on films + series.
	mux.Handle("GET /api/v1/labels", mw(http.HandlerFunc(h.listLabels)))
	mux.Handle("POST /api/v1/items/{itemId}/labels", mw(http.HandlerFunc(h.addItemLabel)))
	mux.Handle("DELETE /api/v1/items/{itemId}/labels/{label}", mw(http.HandlerFunc(h.removeItemLabel)))
	mux.Handle("POST /api/v1/series/{seriesId}/labels", mw(http.HandlerFunc(h.addSeriesLabel)))
	mux.Handle("DELETE /api/v1/series/{seriesId}/labels/{label}", mw(http.HandlerFunc(h.removeSeriesLabel)))

	// Vaults (ARGY-42): user-curated collections.
	mux.Handle("GET /api/v1/vaults", mw(http.HandlerFunc(h.listVaults)))
	mux.Handle("POST /api/v1/vaults", mw(http.HandlerFunc(h.createVault)))
	mux.Handle("GET /api/v1/vaults/{vaultId}", mw(http.HandlerFunc(h.getVault)))
	mux.Handle("PATCH /api/v1/vaults/{vaultId}", mw(http.HandlerFunc(h.updateVault)))
	mux.Handle("DELETE /api/v1/vaults/{vaultId}", mw(http.HandlerFunc(h.deleteVault)))
	mux.Handle("POST /api/v1/vaults/{vaultId}/items", mw(http.HandlerFunc(h.addVaultItem)))
	mux.Handle("DELETE /api/v1/vaults/{vaultId}/items/{entryId}", mw(http.HandlerFunc(h.removeVaultItem)))
	mux.Handle("PUT /api/v1/vaults/{vaultId}/order", mw(http.HandlerFunc(h.reorderVault)))
	if pres != nil {
		mux.Handle("GET /api/v1/sessions", mw(http.HandlerFunc(h.listSessions)))
	}
	// Beacon SSE authenticates inline (?token=), like streaming, since an
	// EventSource can't set the Authorization header.
	if hub != nil {
		mux.Handle("GET /api/v1/beacon", beaconHandler(authStore, hub))
	}
	mux.Handle("GET /api/v1/items/{itemId}/playback", mw(http.HandlerFunc(h.getPlayback)))
	mux.Handle("GET /api/v1/items/{itemId}/next-episode", mw(http.HandlerFunc(h.getNextEpisode)))
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
	// The server-side path is admin-only; hide it from viewers.
	if !isAdmin(r) {
		for i := range libs {
			libs[i].RootPath = nil
		}
	}
	writeJSON(w, http.StatusOK, libs)
}

func (h *handlers) createLibrary(w http.ResponseWriter, r *http.Request) {
	var req api.CreateLibraryRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Name == "" || req.Path == "" {
		writeJSON(w, http.StatusBadRequest, errorBody("name and path are required"))
		return
	}
	if info, err := os.Stat(req.Path); err != nil || !info.IsDir() {
		writeJSON(w, http.StatusBadRequest, errorBody("path must be an existing directory on the server"))
		return
	}
	kind := "mixed"
	if req.Kind != nil {
		kind = string(*req.Kind)
	}
	lib, err := h.store.CreateLibrary(r.Context(), accountOf(r), req.Name, req.Path, kind)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, lib)
}

func (h *handlers) deleteLibrary(w http.ResponseWriter, r *http.Request) {
	removed, err := h.store.DeleteLibrary(r.Context(), accountOf(r), r.PathValue("libraryId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if !removed {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handlers) listMovies(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	page, err := h.store.ListMovies(r.Context(), accountOf(r), r.PathValue("libraryId"), userOf(r), limit, offset, r.URL.Query().Get("sort"), parseFilter(r))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (h *handlers) listSeries(w http.ResponseWriter, r *http.Request) {
	limit, offset := pagination(r)
	page, err := h.store.ListSeries(r.Context(), accountOf(r), r.PathValue("libraryId"), userOf(r), limit, offset, r.URL.Query().Get("sort"), parseFilter(r))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

func (h *handlers) listRecent(w http.ResponseWriter, r *http.Request) {
	limit := 24
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 {
		limit = v
	}
	if limit > 100 {
		limit = 100
	}
	items, err := h.store.ListRecent(r.Context(), accountOf(r), limit)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (h *handlers) search(w http.ResponseWriter, r *http.Request) {
	limit := 8
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 {
		limit = v
	}
	res, err := h.store.Search(r.Context(), accountOf(r), r.URL.Query().Get("q"), limit)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (h *handlers) listFacets(w http.ResponseWriter, r *http.Request) {
	limit := 8
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 {
		limit = v
	}
	facets, err := h.store.Facets(r.Context(), accountOf(r), limit)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, facets)
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
	if labels, err := h.store.SeriesLabels(r.Context(), userOf(r), r.PathValue("seriesId")); err == nil {
		d.Labels = &labels
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
	if labels, err := h.store.ItemLabels(r.Context(), userOf(r), r.PathValue("itemId")); err == nil {
		d.Labels = &labels
	}
	writeJSON(w, http.StatusOK, d)
}

func accountOf(r *http.Request) string {
	sess, _ := auth.SessionFromContext(r.Context())
	return sess.AccountId.String()
}

func isAdmin(r *http.Request) bool {
	sess, _ := auth.SessionFromContext(r.Context())
	return sess.Role == api.Admin
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

// parseFilter extracts the optional browse facet filters from the query string.
// Unknown/zero values mean "no constraint".
func parseFilter(r *http.Request) browseFilter {
	q := r.URL.Query()
	f := browseFilter{Tag: q.Get("tag"), Label: q.Get("label"), Genres: q["genre"], Watched: q.Get("watched")}
	if v, err := strconv.ParseFloat(q.Get("rating_min"), 64); err == nil {
		f.RatingMin = v
	}
	if v, err := strconv.Atoi(q.Get("year_from")); err == nil {
		f.YearFrom = v
	}
	if v, err := strconv.Atoi(q.Get("year_to")); err == nil {
		f.YearTo = v
	}
	// Reject an unrecognized watched value so it doesn't fall through to a state
	// that filters everything out.
	switch f.Watched {
	case "watched", "unwatched", "in_progress":
	default:
		f.Watched = ""
	}
	return f
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
