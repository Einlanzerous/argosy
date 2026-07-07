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
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/subtitle"
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
	// audioTracks are the source's selectable audio streams (dub/sub); passed to
	// the transcoder to emit multi-rendition HLS when there's more than one.
	audioTracks []transcode.AudioTrack
}

// audioTracksFromTechnical enumerates the source's audio streams from the stored
// ffprobe JSON (ARGY-126), preserving order so a track's position doubles as its
// `0:a:<index>` map target. Language codes share the subtitle package's table so
// they match the per-device audioLanguage preference for client auto-select.
func audioTracksFromTechnical(technical []byte) []transcode.AudioTrack {
	var doc struct {
		Streams []struct {
			CodecType string `json:"codec_type"`
			Tags      struct {
				Language string `json:"language"`
			} `json:"tags"`
			Disposition struct {
				Default int `json:"default"`
			} `json:"disposition"`
		} `json:"streams"`
	}
	if len(technical) == 0 {
		return nil
	}
	if err := json.Unmarshal(technical, &doc); err != nil {
		return nil
	}
	var out []transcode.AudioTrack
	ai := 0
	for _, st := range doc.Streams {
		if st.CodecType != "audio" {
			continue
		}
		out = append(out, transcode.AudioTrack{
			Index:    ai,
			Language: subtitle.LangCode(st.Tags.Language),
			Default:  st.Disposition.Default == 1,
		})
		ai++
	}
	return out
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
	return transcodeSource{
		path:        abs,
		height:      videoHeightFromTechnical(technical),
		video:       video,
		audio:       audio,
		audioTracks: audioTracksFromTechnical(technical),
	}, true, nil
}

// startTranscode begins (or joins) an HLS transcode session for an item and
// returns the session + its playlist URL.
func (h *handlers) startTranscode(w http.ResponseWriter, r *http.Request) {
	account := accountOf(r)
	itemID := r.PathValue("itemId")

	src, ok, err := h.store.itemSource(r.Context(), account, itemID)
	if errors.Is(err, ErrPathTraversal) {
		httpx.Error(w, http.StatusForbidden, "forbidden")
		return
	}
	if err != nil {
		h.fail(w, err)
		return
	}
	if !ok {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}

	// Body is optional; it carries the seek offset and whether the client can
	// play HEVC (so a 4K HEVC source can be copied at native resolution rather
	// than re-encoded down to H.264 1080p).
	var body api.TranscodeStartRequest
	if r.Body != nil {
		_ = json.NewDecoder(r.Body).Decode(&body)
	}
	clientHEVC := body.Hevc != nil && *body.Hevc

	// Decide the cheapest playable recipe: copy the video whenever the client can
	// play it (true 4K for HEVC clients), transcoding only the audio if needed;
	// otherwise re-encode (to HEVC for >1080p capable clients, else H.264).
	plan := planPlayback(src.video, src.audio, clientHEVC, src.height)
	mode := transcode.MethodTranscode
	if plan.method != methodTranscode {
		mode = transcode.MethodRemux
	}
	h.logger.Info("transcode decision", "item", itemID, "method", mode, "codec", plan.videoCodec,
		"transcodeAudio", plan.transcodeAudio, "reason", plan.reason, "container", filepath.Ext(src.path),
		"video", src.video, "audio", src.audio, "height", src.height, "clientHevc", clientHEVC)

	var startAt float64
	if body.StartAt != nil && *body.StartAt > 0 {
		startAt = *body.StartAt
	}

	sess, err := h.tc.Start(transcode.StartRequest{
		ItemID:         itemID,
		AccountID:      account,
		Source:         src.path,
		StartAt:        startAt,
		Encoder:        h.encoder,
		SourceHeight:   src.height,
		Method:         mode,
		VideoCodec:     plan.videoCodec,
		TranscodeAudio: plan.transcodeAudio,
		AudioTracks:    src.audioTracks,
	})
	if errors.Is(err, transcode.ErrAtCapacity) {
		httpx.Error(w, http.StatusServiceUnavailable, "server at transcode capacity, try again shortly")
		return
	}
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusAccepted, toAPISession(sess))
}

// fileTranscode serves a session's HLS artifacts: the master playlist
// (index.m3u8), variant playlists, fMP4 init segments, and media segments.
func (h *handlers) fileTranscode(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("file")
	if !transcodeFile.MatchString(name) {
		httpx.Error(w, http.StatusNotFound, "not found")
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
			httpx.Error(w, http.StatusServiceUnavailable, "transcode starting")
			return
		}
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	w.Header().Set("Content-Type", transcodeContentType(name))
	// HLS playlists grow while ffmpeg encodes, so they must never be cached or
	// conditionally 304'd. http.ServeFile answers If-Modified-Since from the
	// file's ModTime at 1-second granularity; a fast remux writes the partial
	// and the final (ENDLIST) playlist within the same second, so a client that
	// fetched a partial playlist gets a stale 304 on reload and never sees the
	// segments appended afterward — wedging playback at that boundary (ARGY-106).
	// Serve playlists with no validators and no-store; segments/init are
	// immutable, so they stay cacheable via ServeFile.
	if filepath.Ext(name) == ".m3u8" {
		w.Header().Set("Cache-Control", "no-store")
		data, err := os.ReadFile(path)
		if err != nil {
			httpx.Error(w, http.StatusNotFound, "not found")
			return
		}
		_, _ = w.Write(data)
		return
	}
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
	httpx.JSON(w, http.StatusOK, out)
}

// transcodeCache reports transcode cache usage (Ballast) for The Helm/Drydock.
func (h *handlers) transcodeCache(w http.ResponseWriter, _ *http.Request) {
	st := h.cache.Stats()
	httpx.JSON(w, http.StatusOK, api.TranscodeCacheStats{
		TotalBytes:  st.TotalBytes,
		BudgetBytes: st.BudgetBytes,
		SessionDirs: st.SessionDirs,
		LiveDirs:    st.LiveDirs,
	})
}

// transcodeCapabilities reports the encoders available on this host.
func (h *handlers) transcodeCapabilities(w http.ResponseWriter, _ *http.Request) {
	httpx.JSON(w, http.StatusOK, api.TranscodeCapabilities{
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
		httpx.Error(w, http.StatusNotFound, "not found")
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
