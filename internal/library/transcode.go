package library

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// transcodeFile is the allowlist of servable per-session artifacts, covering
// both the single-output layout (index.m3u8 + init.mp4 + stream_NNNNN.m4s) and
// the multi-variant ladder (master + stream_N.m3u8 + init_N.mp4 +
// stream_N_NNNNN.m4s). It doubles as the traversal guard for the {file} param.
var transcodeFile = regexp.MustCompile(`^(index\.m3u8|stream_\d+\.m3u8|init\.mp4|init_\d+\.mp4|stream_\d+\.m4s|stream_\d+_\d+\.m4s)$`)

func transcodeContentType(name string) string {
	switch filepath.Ext(name) {
	case ".m3u8":
		return "application/vnd.apple.mpegurl"
	case ".m4s", ".mp4":
		return "video/mp4"
	default:
		return "application/octet-stream"
	}
}

// videoHeightFromTechnical pulls the first video stream's height out of the
// stored ffprobe JSON; 0 when unknown.
func videoHeightFromTechnical(technical []byte) int {
	var t struct {
		Streams []struct {
			CodecType string `json:"codec_type"`
			Height    int    `json:"height"`
		} `json:"streams"`
	}
	if len(technical) > 0 {
		_ = json.Unmarshal(technical, &t)
	}
	for _, s := range t.Streams {
		if s.CodecType == "video" && s.Height > 0 {
			return s.Height
		}
	}
	return 0
}

// transcodeSource is the resolved input for a transcode/remux decision.
type transcodeSource struct {
	path         string
	height       int
	video, audio string
}

// itemSource resolves the absolute, traversal-safe media path plus the source
// video height and codecs for an item the account owns. ok is false when the
// item isn't found.
func (s *Store) itemSource(ctx context.Context, accountID, itemID string) (src transcodeSource, ok bool, err error) {
	var root, rel string
	var technical []byte
	e := s.pool.QueryRow(ctx,
		`SELECT l.root_path, mi.file_path, mi.technical
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&root, &rel, &technical)
	if errors.Is(e, pgx.ErrNoRows) {
		return transcodeSource{}, false, nil
	}
	if e != nil {
		return transcodeSource{}, false, e
	}
	abs, e := resolveWithinRoot(root, rel)
	if e != nil {
		return transcodeSource{}, false, e
	}
	video, audio := codecsFromTechnical(technical)
	return transcodeSource{path: abs, height: videoHeightFromTechnical(technical), video: video, audio: audio}, true, nil
}

// startTranscode begins (or joins) an HLS transcode session for an item and
// returns the session + its playlist URL.
func (h *handlers) startTranscode(w http.ResponseWriter, r *http.Request) {
	account := accountOf(r)
	itemID := r.PathValue("itemId")

	src, ok, err := h.store.itemSource(r.Context(), account, itemID)
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

	// Decide the cheapest re-packaging: remux (copy codecs) when only the
	// container is incompatible, full transcode when a codec needs re-encoding.
	// A direct-playable item that still hit this endpoint just gets a cheap remux.
	method, reason := decide(filepath.Ext(src.path), src.video, src.audio)
	mode := transcode.MethodTranscode
	if method != methodTranscode {
		mode = transcode.MethodRemux
	}
	h.logger.Info("transcode decision", "item", itemID, "method", mode, "reason", reason,
		"container", filepath.Ext(src.path), "video", src.video, "audio", src.audio)

	// Body is optional; it only carries the seek offset.
	var body api.TranscodeStartRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}
	var startAt float64
	if body.StartAt != nil && *body.StartAt > 0 {
		startAt = *body.StartAt
	}

	sess, err := h.tc.Start(transcode.StartRequest{
		ItemID:       itemID,
		AccountID:    account,
		Source:       src.path,
		StartAt:      startAt,
		Encoder:      h.encoder,
		SourceHeight: src.height,
		Method:       mode,
	})
	if errors.Is(err, transcode.ErrAtCapacity) {
		writeJSON(w, http.StatusServiceUnavailable, errorBody("server at transcode capacity, try again shortly"))
		return
	}
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusAccepted, toAPISession(sess))
}

// fileTranscode serves a session's HLS artifacts: the master playlist
// (index.m3u8), variant playlists, fMP4 init segments, and media segments.
func (h *handlers) fileTranscode(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("file")
	if !transcodeFile.MatchString(name) {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	sess, ok := h.authedSession(w, r)
	if !ok {
		return
	}
	h.tc.Touch(sess.ID)
	path := filepath.Join(sess.OutputDir, name)
	if _, err := os.Stat(path); err != nil {
		// The master playlist may not be written yet — tell the client to retry.
		if name == transcode.PlaylistName {
			writeJSON(w, http.StatusServiceUnavailable, errorBody("transcode starting"))
			return
		}
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	w.Header().Set("Content-Type", transcodeContentType(name))
	http.ServeFile(w, r, path)
}

// stopTranscode kills a session's ffmpeg process and purges its output.
func (h *handlers) stopTranscode(w http.ResponseWriter, r *http.Request) {
	sess, ok := h.authedSession(w, r)
	if !ok {
		return
	}
	h.tc.Stop(sess.ID)
	w.WriteHeader(http.StatusNoContent)
}

// listTranscodeSessions returns the live sessions owned by the current account
// (The Helm). A cross-account, admin-only view can come with role checks later.
func (h *handlers) listTranscodeSessions(w http.ResponseWriter, r *http.Request) {
	account := accountOf(r)
	out := []api.TranscodeSession{}
	for _, s := range h.tc.List() {
		if s.AccountID == account {
			out = append(out, toAPISession(s))
		}
	}
	writeJSON(w, http.StatusOK, out)
}

// transcodeCache reports transcode cache usage (Ballast) for The Helm/Drydock.
func (h *handlers) transcodeCache(w http.ResponseWriter, _ *http.Request) {
	st := h.cache.Stats()
	writeJSON(w, http.StatusOK, api.TranscodeCacheStats{
		TotalBytes:  st.TotalBytes,
		BudgetBytes: st.BudgetBytes,
		SessionDirs: st.SessionDirs,
		LiveDirs:    st.LiveDirs,
	})
}

// transcodeCapabilities reports the encoders available on this host.
func (h *handlers) transcodeCapabilities(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, api.TranscodeCapabilities{
		Available: h.caps.Available,
		Selected:  h.caps.Selected,
	})
}

// authedSession resolves the {sessionId} path param to a session the requesting
// account owns; it writes a 404 (not leaking other accounts' sessions) and
// returns ok=false otherwise.
func (h *handlers) authedSession(w http.ResponseWriter, r *http.Request) (transcode.Session, bool) {
	sess, ok := h.tc.Get(r.PathValue("sessionId"))
	if !ok || sess.AccountID != accountOf(r) {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return transcode.Session{}, false
	}
	return sess, true
}

func toAPISession(s transcode.Session) api.TranscodeSession {
	itemUUID, _ := uuid.Parse(s.ItemID)
	out := api.TranscodeSession{
		Id:          s.ID,
		ItemId:      itemUUID,
		Encoder:     s.Encoder,
		Method:      api.TranscodeSessionMethod(s.Method),
		State:       api.TranscodeSessionState(s.State),
		StartAt:     s.StartAt,
		StartedAt:   s.StartedAt,
		PlaylistUrl: "/api/v1/transcode/" + s.ID + "/" + transcode.PlaylistName,
		Progress: api.TranscodeProgress{
			OutTimeMs: s.Progress.OutTimeMS,
			Speed:     s.Progress.Speed,
			Fps:       s.Progress.FPS,
		},
	}
	if s.Err != "" {
		out.Error = &s.Err
	}
	return out
}
