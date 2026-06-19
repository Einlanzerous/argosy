package library

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/jackc/pgx/v5"
)

// Browser-friendly direct-play sets. Anything outside these needs the Phase 3
// transcoder (Ballast). Notably .mkv is excluded — browsers won't play the
// Matroska container even when it carries H.264/AAC.
var (
	directContainers = map[string]bool{".mp4": true, ".m4v": true, ".webm": true, ".mov": true}
	directVideo      = map[string]bool{"h264": true, "avc1": true, "vp8": true, "vp9": true, "av1": true}
	directAudio      = map[string]bool{"aac": true, "mp3": true, "opus": true, "vorbis": true, "flac": true}
)

// Playback decision methods, mirroring the PlaybackInfo.method enum.
const (
	methodDirect    = "direct"
	methodRemux     = "remux"
	methodTranscode = "transcode"
)

// decide picks the cheapest playable path for a (container ext, video, audio)
// tuple in a typical browser, with a human reason:
//   - direct: the file plays as-is.
//   - remux: codecs are fine, only the container is incompatible (copy, no
//     re-encode — e.g. H.264/AAC in Matroska).
//   - transcode: a codec needs re-encoding.
func decide(ext, videoCodec, audioCodec string) (method, reason string) {
	ext = strings.ToLower(ext)
	videoOK := videoCodec == "" || directVideo[strings.ToLower(videoCodec)]
	audioOK := audioCodec == "" || directAudio[strings.ToLower(audioCodec)]

	switch {
	case !videoOK:
		return methodTranscode, "the " + videoCodec + " video codec needs transcoding"
	case !audioOK:
		return methodTranscode, "the " + audioCodec + " audio codec needs transcoding"
	case directContainers[ext]:
		return methodDirect, "direct play"
	default:
		return methodRemux, "the " + strings.TrimPrefix(ext, ".") + " container will be remuxed"
	}
}

// codecsFromTechnical pulls the first video/audio codec names out of the stored
// ffprobe JSON.
func codecsFromTechnical(technical []byte) (video, audio string) {
	var t struct {
		Streams []struct {
			CodecType string `json:"codec_type"`
			CodecName string `json:"codec_name"`
		} `json:"streams"`
	}
	if len(technical) > 0 {
		_ = json.Unmarshal(technical, &t)
	}
	for _, s := range t.Streams {
		if s.CodecType == "video" && video == "" {
			video = s.CodecName
		}
		if s.CodecType == "audio" && audio == "" {
			audio = s.CodecName
		}
	}
	return video, audio
}

// Playback returns the direct-play decision for an item the account owns, or nil
// when the item isn't found (→ 404).
func (s *Store) Playback(ctx context.Context, accountID, itemID string) (*api.PlaybackInfo, error) {
	var filePath string
	var technical []byte
	err := s.pool.QueryRow(ctx,
		`SELECT mi.file_path, mi.technical
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&filePath, &technical)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	ext := strings.ToLower(filepath.Ext(filePath))
	video, audio := codecsFromTechnical(technical)
	method, reason := decide(ext, video, audio)

	info := &api.PlaybackInfo{
		DirectPlay: method == methodDirect,
		Method:     api.PlaybackInfoMethod(method),
		Container:  strings.TrimPrefix(ext, "."),
		Reason:     &reason,
	}
	if video != "" {
		info.VideoCodec = &video
	}
	if audio != "" {
		info.AudioCodec = &audio
	}
	return info, nil
}

func (h *handlers) getPlayback(w http.ResponseWriter, r *http.Request) {
	info, err := h.store.Playback(r.Context(), accountOf(r), r.PathValue("itemId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if info == nil {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	writeJSON(w, http.StatusOK, info)
}
