package transcode

import (
	"bytes"
	"regexp"
)

// NormalizePlaylist rewrites the parts of ffmpeg's HLS output that clients
// reject or misread. Every playlist goes through it on the way out; anything
// else that grows a second consumer of these files should call it too, because
// ffmpeg's output on disk stays as ffmpeg wrote it.
//
// Today that is two things: media playlists get their start position pinned to
// the top of the session (pinStart, ARGY-228), and master playlists get the
// malformed HEVC constraint byte repaired (fixHEVCConstraint, ARGY-174).
func NormalizePlaylist(b []byte) []byte {
	return fixHEVCConstraint(pinStart(b))
}

// startPin is the line pinStart inserts. TIME-OFFSET=0 is the HLS timeline's
// origin, PRECISE=YES says to start exactly there rather than at the nearest
// segment boundary (the same place here, but stated so no parser has to guess).
var startPin = []byte("#EXT-X-START:TIME-OFFSET=0,PRECISE=YES\n")

var (
	m3uHeader         = []byte("#EXTM3U")
	tagTargetDuration = []byte("#EXT-X-TARGETDURATION")
	tagStart          = []byte("#EXT-X-START")
)

// pinStart inserts an EXT-X-START tag pinning playback to the top of a media
// playlist. Master playlists (no EXT-X-TARGETDURATION) and playlists that
// already declare a start pass through untouched, so the result is idempotent.
//
// The encoder writes an `event` playlist — no EXT-X-ENDLIST until ffmpeg
// finishes — because the session is still growing while the client plays it.
// Without a declared start, every HLS client reads a playlist with no ENDLIST
// as live and joins it at the live edge: hls.js by default, ExoPlayer via
// HlsMediaSource's default window position, AVPlayer likewise. For a real
// encode the edge is seconds in and nobody notices. A remux-copy runs at disk
// speed, so by the time the first media playlist is parsed the edge is most
// of the episode — Archer S4 opened ~70% in on the Android TV, twice in a row
// (ARGY-228). The web player had already hit the same thing and pinned
// `startPosition: 0` in its hls.js config (ARGY-103); this is the equivalent
// for every other client, put where all of them read it.
//
// Zero is right for every session, not just a fresh play: ffmpeg is started
// *from* the requested offset, so HLS-timeline 0 is baseOffset in the media
// for a resume and a seek-restart alike. hls.js only consults EXT-X-START when
// its startPosition is -1, so the web player's explicit 0 wins there and this
// changes nothing for it.
//
// The tag goes on the media playlists rather than the master because that is
// where ExoPlayer's parser reads it (HlsPlaylistParser.parseMediaPlaylist);
// the master parser ignores it. It sits right after #EXTM3U, the one line the
// spec fixes in place.
func pinStart(b []byte) []byte {
	if !bytes.Contains(b, tagTargetDuration) || bytes.Contains(b, tagStart) {
		return b
	}
	if !bytes.HasPrefix(b, m3uHeader) {
		return b
	}
	nl := bytes.IndexByte(b, '\n')
	if nl < 0 {
		return b
	}
	out := make([]byte, 0, len(b)+len(startPin))
	out = append(out, b[:nl+1]...)
	out = append(out, startPin...)
	return append(out, b[nl+1:]...)
}

// ffmpegHEVCConstraint matches the constraint-byte element ffmpeg's HLS muxer
// hardcodes onto every HEVC codec string it writes into a master playlist's
// CODECS list: write_codec_attr formats "hvc1.<profile>.4.L<level>.B01" with the
// trailing ".B01" as a literal, whatever the stream actually declares.
var ffmpegHEVCConstraint = regexp.MustCompile(`((?:hvc1|hev1)(?:\.[0-9A-Za-z]+){3})\.B01`)

// hevcConstraintSuffix is the cheap pre-check that keeps the regexp off the
// media playlists, which carry no CODECS and grow to hundreds of lines.
var hevcConstraintSuffix = []byte(".B01")

// fixHEVCConstraint repairs the malformed HEVC constraint byte above. Per
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
func fixHEVCConstraint(b []byte) []byte {
	if !bytes.Contains(b, hevcConstraintSuffix) {
		return b
	}
	return ffmpegHEVCConstraint.ReplaceAll(b, []byte("${1}.B0"))
}
