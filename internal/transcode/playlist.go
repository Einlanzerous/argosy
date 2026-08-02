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
// reject. Every playlist goes through it on the way out; anything else that
// grows a second consumer of these files should call it too, because ffmpeg's
// output on disk stays as ffmpeg wrote it.
//
// Today that is one thing: the malformed HEVC constraint byte above. Per
// ISO/IEC 14496-15 Annex E every element after the tier/level is a single
// hex-encoded byte, so "B01" decodes to 0xB01 — out of range. Parsers that
// validate it (Chrome's and Firefox's included) reject the whole codec string,
// so MediaSource.isTypeSupported answers false for HEVC the browser can
// actually decode; hls.js then drops the only variant and fails the manifest
// with MANIFEST_INCOMPATIBLE_CODECS_ERROR before requesting a single segment
// (ARGY-174).
//
// We emit ".B0" — 0xB0, the byte ffmpeg means, and the form Apple's own HLS
// manifests carry. Dropping the element entirely would also be valid (trailing
// constraint bytes are optional) and would assert nothing about a source we
// never inspect; ".B0" does claim progressive / non-packed / frame-only, which
// would be wrong for interlaced HEVC. We keep ".B0" because it is the string
// verified end-to-end against the browser this bug was reported on, and
// because interlaced HEVC does not survive the remux path for other reasons.
// Revisit if a source ever turns up that this misdescribes.
//
// It applies wherever ffmpeg writes a master playlist, which is a wider set
// than the multi-audio path that surfaced the bug: the multi-rung ladder emits
// one for single-audio sources too, and it carries the same broken string when
// the ladder encodes HEVC. Media playlists declare no CODECS at all and pass
// through untouched — which is exactly why single-audio remuxes were the only
// HEVC that ever played.
func NormalizePlaylist(b []byte) []byte {
	if !bytes.Contains(b, hevcConstraintSuffix) {
		return b
	}
	return ffmpegHEVCConstraint.ReplaceAll(b, []byte("${1}.B0"))
}
