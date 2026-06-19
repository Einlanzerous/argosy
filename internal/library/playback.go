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

// decideDirectPlay reports whether a (container ext, video, audio) tuple can play
// natively in a typical browser, with a human reason when it can't.
func decideDirectPlay(ext, videoCodec, audioCodec string) (bool, string) {
	ext = strings.ToLower(ext)
	if !directContainers[ext] {
		return false, "the " + strings.TrimPrefix(ext, ".") + " container needs transcoding"
	}
	if videoCodec != "" && !directVideo[strings.ToLower(videoCodec)] {
		return false, "the " + videoCodec + " video codec needs transcoding"
	}
	if audioCodec != "" && !directAudio[strings.ToLower(audioCodec)] {
		return false, "the " + audioCodec + " audio codec needs transcoding"
	}
	return true, "direct play"
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
	directPlay, reason := decideDirectPlay(ext, video, audio)

	info := &api.PlaybackInfo{
		DirectPlay: directPlay,
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
