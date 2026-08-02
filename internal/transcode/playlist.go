package transcode

import (
	"bytes"
	"regexp"
)

// ffmpegHEVCConstraint matches the constraint-byte element ffmpeg's HLS muxer
// hardcodes onto every HEVC codec string it writes into a master playlist's
// CODECS list: write_codec_attr formats "hvc1.<profile>.4.L<level>.B01" with the
// trailing ".B01" as a literal, whatever the stream actually declares.
var ffmpegHEVCConstraint = regexp.MustCompile(`((?:hvc1|hev1)(?:\.[0-9A-Za-z]+){3})\.B01`)

// hevcConstraintSuffix is the cheap pre-check that keeps the regexp off the
// media playlists, which carry no CODECS and grow to hundreds of lines.
var hevcConstraintSuffix = []byte(".B01")

// NormalizePlaylist rewrites the parts of ffmpeg's HLS output that clients
// reject, and is applied to every playlist on the way out to a client.
//
// Today that is one thing: the malformed HEVC constraint byte above. Per
// ISO/IEC 14496-15 Annex E every element after the tier/level is a single
// hex-encoded byte, so "B01" decodes to 0xB01 — out of range. Parsers that
// validate it (Chrome's and Firefox's included) reject the whole codec string,
// so MediaSource.isTypeSupported answers false for HEVC the browser can
// actually decode; hls.js then drops the only variant and fails the manifest
// with MANIFEST_INCOMPATIBLE_CODECS_ERROR before requesting a single segment
// (ARGY-174). We emit ".B0" instead — 0xB0, the progressive / non-packed /
// frame-only byte ffmpeg means, and the canonical form Apple's own HLS
// manifests carry.
//
// Only the master playlist declares CODECS, so single-audio sessions (a bare
// media playlist) pass through untouched — which is exactly why they were the
// only HEVC that ever played.
func NormalizePlaylist(b []byte) []byte {
	if !bytes.Contains(b, hevcConstraintSuffix) {
		return b
	}
	return ffmpegHEVCConstraint.ReplaceAll(b, []byte("${1}.B0"))
}
