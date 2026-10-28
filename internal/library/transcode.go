package library

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/fileid"
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
//
// Mirrored at the public edge: construct-server's
// config/crowdsec/parsers/s02-enrich/argosy-hls-whitelist.yaml exempts
// successful fetches matching this set from CrowdSec's crawl detection
// (SERV-184). A player's segment burst otherwise reads as crawling and bans
// the viewer mid-episode. Change the two together. A new artifact this allows
// but the whitelist doesn't cover brings those bans back silently, for anyone
// watching off-LAN.
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

// highBitDepthFromTechnical reports whether the first video stream is >8-bit
// (10/12-bit), read from the stored ffprobe JSON. Bit depth drives the copy-vs-
// re-encode decision in planPlayback: clients that hardware-decode 8-bit fall
// back to software decode on 10-bit and stutter (ARGY-150).
func highBitDepthFromTechnical(technical []byte) bool {
	var t struct {
		Streams []struct {
			CodecType        string `json:"codec_type"`
			PixFmt           string `json:"pix_fmt"`
			Profile          string `json:"profile"`
			BitsPerRawSample string `json:"bits_per_raw_sample"`
		} `json:"streams"`
	}
	if len(technical) > 0 {
		_ = json.Unmarshal(technical, &t)
	}
	for _, s := range t.Streams {
		if s.CodecType == "video" {
			return isHighBitDepth(s.PixFmt, s.Profile, s.BitsPerRawSample)
		}
	}
	return false
}

// isHighBitDepth decides >8-bit from ffprobe's pix_fmt (authoritative, always
// present — e.g. yuv420p10le, p010le), with profile ("Main 10"/"High 10") and
// bits_per_raw_sample as fallbacks for the rare case pix_fmt is unhelpful.
func isHighBitDepth(pixFmt, profile, bitsPerRawSample string) bool {
	pf := strings.ToLower(pixFmt)
	for _, tag := range []string{"10le", "10be", "12le", "12be", "p010", "p012", "p016"} {
		if strings.Contains(pf, tag) {
			return true
		}
	}
	p := strings.ToLower(profile)
	if strings.Contains(p, "10") || strings.Contains(p, "12") {
		return true
	}
	return bitsPerRawSample != "" && bitsPerRawSample != "8"
}

// transcodeSource is the resolved input for a transcode/remux decision.
type transcodeSource struct {
	path string
	// identity is the fileid identity of path, read in the same query so the two
	// describe one file. Sessions and stow jobs key on it because an item keeps
	// its id when its file is replaced (ARGY-238).
	identity     string
	height       int
	highBitDepth bool // source is >8-bit (10/12); blocks the H.264/HEVC copy path
	video, audio string
	// audioTracks are the source's selectable audio streams (dub/sub); passed to
	// the transcoder to emit multi-rendition HLS when there's more than one.
	audioTracks []transcode.AudioTrack
	// technical is the stored ffprobe JSON, kept so a requested burn-in subtitle
	// can be resolved against this item's own streams rather than trusted
	// (ARGY-59).
	technical []byte
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
	var contentHash *string
	var fileSize *int64
	e := s.pool.QueryRow(ctx,
		`SELECT l.root_path, mi.file_path, mi.technical, mi.content_hash, mi.file_size
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&root, &rel, &technical, &contentHash, &fileSize)
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
		path:         abs,
		identity:     fileid.Identity(contentHash, fileSize),
		height:       videoHeightFromTechnical(technical),
		highBitDepth: highBitDepthFromTechnical(technical),
		video:        video,
		audio:        audio,
		audioTracks:  audioTracksFromTechnical(technical),
		technical:    technical,
	}, true, nil
}

// errBadLadderHint is the 400 for a minHeight/maxHeight that is present but not
// a positive integer. A malformed hint is refused, not ignored: it is a client
// bug, and reading the zero Go left behind as "absent" would hide it.
const errBadLadderHint = "minHeight/maxHeight must be a positive integer"

// decodeTranscodeBody reads the optional POST transcode body and validates the
// ladder hints (ARGY-179). The decode error is kept, and what encoding/json does
// with the generated pointer struct decides the outcome:
//
//   - An empty body, a non-JSON body or a syntax error (including a truncated
//     object) decodes nothing; the body is treated as empty — today's
//     behaviour: no hints, hevc=false. Older clients send no hints and read as
//     "full ladder".
//   - A *json.UnmarshalTypeError allocates the offending field's pointer to
//     zero and decodes every other field. On minHeight/maxHeight ("abc",
//     1080.5) it is a 400. Go reports only the FIRST type error, so
//     {"hevc":"yes","minHeight":"abc"} surfaces Field="hevc" with minHeight
//     left at 0 — the "<= 0" rule below refuses it, which is why that rule
//     stays and the checks are not reordered. A type error on another field
//     alone ("hevc":"yes") leaves it zero and the hints are honoured. A
//     top-level non-object ([1,2]) is a type error with an empty Field and
//     nothing decoded: 200, no hints.
//   - A JSON null hint (what the generated Dart client sends for every unset
//     field) decodes to nil with no error and reads as absent.
//   - minHeight > maxHeight as sent, both present, is a 400 — raw values, so
//     the rule is well-defined, and before the method decision, so a request
//     that would have remuxed is still refused for inconsistent hints.
//
// errMsg is non-empty for a 400; min/max are 0 when absent.
func decodeTranscodeBody(r io.Reader) (body api.TranscodeStartRequest, minHeight, maxHeight int, errMsg string) {
	if r == nil {
		return body, 0, 0, ""
	}
	if err := json.NewDecoder(r).Decode(&body); err != nil {
		var typeErr *json.UnmarshalTypeError
		if !errors.As(err, &typeErr) {
			return api.TranscodeStartRequest{}, 0, 0, ""
		}
		if typeErr.Field == "minHeight" || typeErr.Field == "maxHeight" {
			return body, 0, 0, errBadLadderHint
		}
	}
	if body.MinHeight != nil {
		if *body.MinHeight <= 0 {
			return body, 0, 0, errBadLadderHint
		}
		minHeight = *body.MinHeight
	}
	if body.MaxHeight != nil {
		if *body.MaxHeight <= 0 {
			return body, 0, 0, errBadLadderHint
		}
		maxHeight = *body.MaxHeight
	}
	if minHeight > 0 && maxHeight > 0 && minHeight > maxHeight {
		return body, 0, 0, "minHeight must not exceed maxHeight"
	}
	return body, minHeight, maxHeight, ""
}

// startTranscode begins (or joins) an HLS transcode session for an item and
// returns the session + its playlist URL.
func (h *handlers) startTranscode(w http.ResponseWriter, r *http.Request) {
	// Two different scopes: the item is resolved against the server's catalog
	// (the owner's libraries), while the session is owned by the caller's own
	// household so one member can't list or kill another's transcode.
	account := accountOf(r)
	itemID := r.PathValue("itemId")

	src, ok, err := h.store.itemSource(r.Context(), catalogOf(r), itemID)
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

	// Body is optional; it carries the seek offset, whether the client can play
	// HEVC (so a 4K HEVC source can be copied at native resolution rather than
	// re-encoded down to H.264 1080p), and the ladder hints (ARGY-179).
	body, minHeight, maxHeight, hintErr := decodeTranscodeBody(r.Body)
	if hintErr != "" {
		httpx.Error(w, http.StatusBadRequest, hintErr)
		return
	}
	clientHEVC := body.Hevc != nil && *body.Hevc
	// Whether the client hardware-decodes 10-bit HEVC. Absent on every client
	// that predates ARGY-178, which reads as false and keeps the old behaviour.
	clientHEVCHardware := body.HevcHardware != nil && *body.HevcHardware

	// An image subtitle the viewer picked explicitly, to be drawn into the video
	// (ARGY-59). Resolved against this item's own streams: the index reaches an
	// ffmpeg filtergraph, so a bad one has to be refused here rather than
	// discovered as a session that fails to start.
	burnIn := 0
	if body.BurnInSubtitle != nil && *body.BurnInSubtitle != "" {
		idx, ok := subtitle.BurnInStream(src.technical, *body.BurnInSubtitle)
		if !ok {
			httpx.Error(w, http.StatusBadRequest, "no such image subtitle track on this item")
			return
		}
		burnIn = idx
	}

	// Decide the cheapest playable recipe: copy the video whenever the client can
	// play it (true 4K for HEVC clients), transcoding only the audio if needed;
	// otherwise re-encode (to HEVC for >1080p capable clients, else H.264). A
	// burn-in rules the copy out — the overlay changes the picture.
	plan := planPlayback(src.video, src.audio, clientHEVC, clientHEVCHardware, src.highBitDepth,
		burnIn > 0, src.height)
	mode := transcode.MethodTranscode
	// The hints that reach the transcoder. A copy has one variant by
	// construction, so on a remux the ladder hints have nothing to shape: they
	// are dropped here so a hinted and an unhinted remux derive the same session
	// and join one copy (ARGY-235 owns giving a remux a ladder). The raw values
	// stay in minHeight/maxHeight for the decision line, so a TV that sent
	// min=max=2160 for a title that copies is still distinguishable in the log
	// from a client that sent nothing.
	rungMin, rungMax := minHeight, maxHeight
	if plan.method != methodTranscode {
		mode = transcode.MethodRemux
		rungMin, rungMax = 0, 0
	}
	var startAt float64
	if body.StartAt != nil && *body.StartAt > 0 {
		startAt = *body.StartAt
	}

	req := transcode.StartRequest{
		ItemID:         itemID,
		AccountID:      account,
		Source:         src.path,
		SourceIdentity: src.identity,
		StartAt:        startAt,
		Encoder:        h.encoder,
		SourceHeight:   src.height,
		Method:         mode,
		VideoCodec:     plan.videoCodec,
		TranscodeAudio: plan.transcodeAudio,
		AudioTracks:    src.audioTracks,
		BurnInSubtitle: burnIn,
		MinRungHeight:  rungMin,
		MaxRungHeight:  rungMax,
	}
	sess, err := h.tc.Start(req)
	// One line per start carries the decision AND who asked for which session at
	// which offset, so a seek burst reads from the log alone (ARGY-262). On a
	// failed start there is no session id, but the decision is still worth having.
	// minHeight=/maxHeight= are the hints as the client sent them (0 = absent),
	// even on a remux where they were dropped; rungs= is the *planned* ladder
	// after the hints ("copy" on a remux); a hardware→software fallback that
	// changes it logs its own line (ARGY-179).
	rungs := transcode.PlannedRungs(req)
	if err == nil {
		rungs = sess.Rungs
	}
	decision := []any{"item", itemID, "device", auth.DeviceLabel(r.Context()),
		"startAt", startAt, "method", mode, "codec", plan.videoCodec,
		"transcodeAudio", plan.transcodeAudio, "reason", plan.reason, "container", filepath.Ext(src.path),
		"video", src.video, "audio", src.audio, "height", src.height, "clientHevc", clientHEVC,
		"clientHevcHardware", clientHEVCHardware, "highBitDepth", src.highBitDepth,
		"burnInSubtitle", burnIn, "minHeight", minHeight, "maxHeight", maxHeight,
		"rungs", transcode.FormatRungs(rungs)}
	if err != nil {
		h.logger.Info("transcode decision", decision...)
	} else {
		h.logger.Info("transcode decision", append(decision, "session", sess.ID)...)
	}
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
	// Touch on every request, including the ones answered below with a 503 or a
	// 404: a client retrying a not-yet-written manifest is alive and must not be
	// reaped. Whether anything was *served* is recorded further down, once it
	// has actually gone out.
	h.tc.Touch(sess.ID)
	isSegment := filepath.Ext(name) != ".m3u8"
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
	if !isSegment {
		w.Header().Set("Cache-Control", "no-store")
		data, err := os.ReadFile(path)
		if err != nil {
			httpx.Error(w, http.StatusNotFound, "not found")
			return
		}
		// Reading it into memory is also the interception point for the codec
		// strings ffmpeg writes into the master playlist (ARGY-174) and for the
		// start pin every media playlist leaves with (ARGY-228).
		_, _ = w.Write(transcode.NormalizePlaylist(data))
		h.tc.MarkServed(sess.ID, false)
		return
	}
	http.ServeFile(w, r, path)
	// A segment (or init) fetch is the client's signal that it accepted the
	// manifest and started buffering (ARGY-174).
	h.tc.MarkServed(sess.ID, true)
}

// stopTranscode kills a session's ffmpeg process and purges its output.
func (h *handlers) stopTranscode(w http.ResponseWriter, r *http.Request) {
	sess, ok := h.authedSession(w, r)
	if !ok {
		return
	}
	h.logger.Info("transcode stop", "session", sess.ID, "device", auth.DeviceLabel(r.Context()))
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
	// The planned rung set as of this snapshot (ARGY-282). Nil on a remux,
	// which copies the source's one variant. A hardware→software fallback
	// re-resolves it after Start has answered (setRungs), so a later snapshot
	// can read a different set from the start response.
	if len(s.Rungs) > 0 {
		rungs := slices.Clone(s.Rungs)
		out.Rungs = &rungs
	}
	return out
}
