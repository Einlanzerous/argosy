package library

import (
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/transcode"
	"github.com/google/uuid"
)

// segmentName guards the HLS segment path param against traversal: only the
// ffmpeg-produced segNNNNN.ts names are servable.
var segmentName = regexp.MustCompile(`^seg\d{1,8}\.ts$`)

// startTranscode begins (or joins) an HLS transcode session for an item and
// returns the session + its playlist URL.
func (h *handlers) startTranscode(w http.ResponseWriter, r *http.Request) {
	account := accountOf(r)
	itemID := r.PathValue("itemId")

	src, ok, err := h.store.ItemFilePath(r.Context(), account, itemID)
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
		ItemID:    itemID,
		AccountID: account,
		Source:    src,
		StartAt:   startAt,
		Encoder:   h.encoder,
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

// transcodePlaylist serves a session's HLS media playlist.
func (h *handlers) transcodePlaylist(w http.ResponseWriter, r *http.Request) {
	sess, ok := h.authedSession(w, r)
	if !ok {
		return
	}
	h.tc.Touch(sess.ID)
	path := filepath.Join(sess.OutputDir, transcode.PlaylistName)
	if _, err := os.Stat(path); err != nil {
		// ffmpeg hasn't written the first playlist yet — client should retry.
		writeJSON(w, http.StatusServiceUnavailable, errorBody("transcode starting"))
		return
	}
	w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
	http.ServeFile(w, r, path)
}

// transcodeSegment serves one HLS media segment for a session.
func (h *handlers) transcodeSegment(w http.ResponseWriter, r *http.Request) {
	seg := r.PathValue("segment")
	if !segmentName.MatchString(seg) {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	sess, ok := h.authedSession(w, r)
	if !ok {
		return
	}
	h.tc.Touch(sess.ID)
	path := filepath.Join(sess.OutputDir, seg)
	if _, err := os.Stat(path); err != nil {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	w.Header().Set("Content-Type", "video/mp2t")
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
