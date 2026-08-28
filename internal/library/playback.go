package library

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/transcode"
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

// hevcNames are the ffprobe/codec spellings for H.265.
var hevcNames = map[string]bool{"hevc": true, "h265": true, "hvc1": true, "hev1": true}

func isHEVC(codec string) bool { return hevcNames[strings.ToLower(codec)] }

// transcodePlan is the resolved recipe for an HLS session: copy vs re-encode the
// video, which output codec, and whether the audio needs re-encoding.
type transcodePlan struct {
	method         string // methodRemux (copy video) or methodTranscode (re-encode)
	videoCodec     string // transcode.CodecH264 / CodecHEVC — output or copied codec
	transcodeAudio bool   // remux path: re-encode audio to AAC instead of copying
	reason         string
}

// planPlayback picks the cheapest HLS recipe given the source codecs, the source
// height, whether the client can play HEVC, and whether the source is high bit
// depth (10/12-bit). The video stream is copied whenever the client can play it
// as-is — H.264 always, HEVC when the client negotiated it (clientHEVC) — which
// preserves native resolution/HDR (true 4K) and avoids a video re-encode; only
// the audio is transcoded if it isn't browser-friendly. Re-encodes target HEVC
// for >1080p capable clients (H.264's 4K bitrate is impractical) and H.264
// otherwise.
//
// Exception: high-bit-depth H.264/HEVC is not copied, except for HEVC above
// 1080p when the client also reports hardware decode. That exception is
// deliberately narrow, because the evidence underneath it is thin on both sides.
//
// ARGY-150 blocked every 10-bit copy, reasoning that MediaSource.isTypeSupported
// reports Main 10 "supported" for a stream the client will software-decode and
// stutter on. Bit depth stood in for "will this decode in hardware" — but it
// separates nothing: the title that stuttered (1080p Main 10, ~4.8 Mbps) and the
// titles that played smoothly (2160p Main 10, ~62 Mbps) are both 10-bit, and the
// *cheaper* file is the one that stuttered. Whatever went wrong there, decode
// cost does not describe it, and the rule cost every 4K HDR title its resolution
// and its HDR (ARGY-178).
//
// clientHEVCHardware carries MediaCapabilities' `powerEfficient`/`smooth`, which
// is a better question than bit depth but a weak answer: browsers report a
// supported configuration as smooth and powerEfficient *until stats have been
// recorded on the device*, so a true can simply mean "never played this". It is
// therefore treated as a veto rather than a guarantee — false withholds the copy,
// true only permits it — and paired with the one condition we have positive
// evidence for: >1080p, where 4K HDR was observed playing smoothly on a copy.
// At 1080p and below, 10-bit keeps re-encoding exactly as ARGY-150 left it, which
// is the class the unexplained stutter belongs to.
//
// 10-bit H.264 stays blocked outright: an HEVC probe says nothing about High 10,
// and browser hardware support for it is far thinner. VP9/AV1 10-bit stay
// copyable — those are broadly hardware-decoded.
//
// burnIn — the viewer selected an image subtitle track — overrides all of it.
// PGS/VOBSUB are bitmaps with no text form, so the only way to show them is to
// paint them into the frames, and a stream with something painted onto it is by
// definition not the stream that was there to copy (ARGY-59).
func planPlayback(videoCodec, audioCodec string, clientHEVC, clientHEVCHardware, highBitDepth, burnIn bool, height int) transcodePlan {
	v := strings.ToLower(videoCodec)
	audioOK := audioCodec == "" || directAudio[strings.ToLower(audioCodec)]
	hevcTenBitOK := isHEVC(v) && clientHEVC && clientHEVCHardware && height > 1080
	highDepthBlocked := highBitDepth && !hevcTenBitOK && (isHEVC(v) || v == "h264" || v == "avc1")
	copyVideo := !burnIn && !highDepthBlocked && (directVideo[v] || (clientHEVC && isHEVC(v)))

	if copyVideo {
		p := transcodePlan{method: methodRemux, videoCodec: transcode.CodecH264, transcodeAudio: !audioOK}
		if isHEVC(v) {
			p.videoCodec = transcode.CodecHEVC
		}
		switch {
		case isHEVC(v) && p.transcodeAudio:
			p.reason = "copying HEVC video at native resolution; transcoding " + audioCodec + " audio"
		case isHEVC(v):
			p.reason = "copying HEVC video at native resolution (direct 4K)"
		case p.transcodeAudio:
			p.reason = "copying video; transcoding " + audioCodec + " audio"
		default:
			p.reason = "remuxing into a browser-friendly container"
		}
		return p
	}

	// Video must be re-encoded.
	p := transcodePlan{method: methodTranscode, videoCodec: transcode.CodecH264}
	if clientHEVC && height > 1080 {
		p.videoCodec = transcode.CodecHEVC
		p.reason = "re-encoding " + videoCodec + " to HEVC (4K)"
	} else {
		p.reason = "re-encoding " + videoCodec + " to H.264"
	}
	if highDepthBlocked {
		p.reason = "re-encoding 10-bit " + videoCodec + " to 8-bit " + p.videoCodec + " for reliable client decode"
	}
	if burnIn {
		// Stated last because it is the reason the copy was refused, whatever
		// the other flags would have allowed on their own.
		p.reason += "; burning in the selected image subtitle track"
	}
	return p
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
	info, err := h.store.Playback(r.Context(), catalogOf(r), r.PathValue("itemId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if info == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	info.PreferredLanguages = &h.preferredLangs
	httpx.JSON(w, http.StatusOK, info)
}
