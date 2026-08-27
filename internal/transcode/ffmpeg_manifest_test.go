package transcode

import (
	"context"
	"encoding/binary"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// numericPlaylist matches the master + numeric variant playlists the library's
// transcodeFile allowlist serves. A name:-renamed variant (stream_English.m3u8)
// would fail this — and thus 404 in production — so the integration test asserts
// every emitted playlist satisfies it.
var numericPlaylist = regexp.MustCompile(`^(index|stream_\d+)\.m3u8$`)

// TestMultiAudioManifestIntegration runs the *actual* buildArgs output through a
// real ffmpeg against a synthesized 2-audio-track source and asserts the master
// playlist is playable: a video EXT-X-STREAM-INF that references the shared
// audio group, plus one EXT-X-MEDIA:TYPE=AUDIO rendition per track carrying the
// LANGUAGE clients label from. It guards two non-obvious ffmpeg behaviors this
// path depends on (ARGY-127): `name:` in var_stream_map renames output files
// (so we must not use it), and a copied video stream needs a -b:v hint or the
// muxer omits the video variant from the master entirely.
//
// Skipped under -short or when ffmpeg isn't installed, so it stays hermetic.
func TestMultiAudioManifestIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test needs ffmpeg")
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not on PATH")
	}
	dir := t.TempDir()
	src := filepath.Join(dir, "src.mkv")
	genMultiAudioSource(t, ffmpeg, src)

	for _, tc := range []struct {
		name     string
		spec     Spec
		wantVars int // expected video EXT-X-STREAM-INF entries
	}{
		{
			name: "remux copy", wantVars: 1,
			spec: Spec{Source: src, Method: MethodRemux, AudioTracks: dubSub},
		},
		{
			name: "transcode ladder", wantVars: 3,
			spec: Spec{Source: src, Encoder: EncoderSoftware, SourceHeight: 1080, AudioTracks: dubSub},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out := t.TempDir()
			spec := tc.spec
			spec.OutputDir = out
			run(t, ffmpeg, out, buildArgs(spec))

			master, err := os.ReadFile(filepath.Join(out, PlaylistName))
			if err != nil {
				t.Fatalf("read master: %v", err)
			}
			m := string(master)
			t.Logf("master:\n%s", m)

			for _, want := range []string{
				`TYPE=AUDIO`, `LANGUAGE="en"`, `LANGUAGE="ja"`, `DEFAULT=YES`, `AUDIO="group_aud"`,
			} {
				if !strings.Contains(m, want) {
					t.Errorf("master missing %q", want)
				}
			}
			if got := strings.Count(m, "EXT-X-STREAM-INF"); got != tc.wantVars {
				t.Errorf("video variants = %d, want %d", got, tc.wantVars)
			}
			// Every emitted playlist must be numerically named (allowlist-safe).
			plists, _ := filepath.Glob(filepath.Join(out, "*.m3u8"))
			for _, p := range plists {
				if !numericPlaylist.MatchString(filepath.Base(p)) {
					t.Errorf("playlist %q outside the numeric allowlist", filepath.Base(p))
				}
			}
		})
	}
}

// TestHEVCManifestCodecs is the ARGY-174 regression guard. Any master playlist
// carrying an HEVC variant advertises a CODECS attribute the browser gates on,
// and ffmpeg writes a malformed constraint byte into it ("hvc1.1.4.L120.B01")
// that every strict codec-string parser rejects — so hls.js drops the variant
// and fails the manifest before requesting a segment.
//
// Every HEVC shape now emits a master, and all three are covered here: the
// multi-audio remux that surfaced the bug, the multi-rung ladder (which emits a
// master for a *single*-audio source too), and the single-audio remux.
//
// That last one used to escape into a lone-variant media playlist carrying no
// CODECS at all. Escaping this bug did not make it play — it made it fail
// earlier and less legibly: with nothing declared, hls.js falls back to parsing
// the init segment, cannot read an HEVC codec out of it, and asks for a bare
// "hvc1" SourceBuffer that browsers refuse (ARGY-218). It is on the master path
// now precisely so it has a CODECS string to declare, which is what puts it
// under this test.
//
// The assertion is on the bytes a client actually receives: what ffmpeg wrote,
// run through NormalizePlaylist the way fileTranscode serves it.
func TestHEVCManifestCodecs(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test needs ffmpeg")
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not on PATH")
	}
	if !hasEncoder(ffmpeg, "libx265") {
		t.Skip("ffmpeg built without libx265")
	}
	dir := t.TempDir()
	src := filepath.Join(dir, "src.mkv")
	genHEVCMultiAudioSource(t, ffmpeg, src)

	for _, tc := range []struct {
		name string
		spec Spec
	}{
		{
			name: "multi-audio remux",
			spec: Spec{
				Source: src, Method: MethodRemux, VideoCodec: CodecHEVC,
				TranscodeAudio: true, SourceHeight: 240, AudioTracks: dubSub,
			},
		},
		{
			// One audio track, so the master exists purely because the ladder has
			// more than one rung. Same broken codec string, no multi-audio in sight.
			name: "single-audio hevc ladder",
			spec: Spec{
				Source: src, Encoder: EncoderSoftware, VideoCodec: CodecHEVC, SourceHeight: 1080,
			},
		},
		{
			// The ARGY-218 case. Before the fix this wrote a media playlist with no
			// CODECS at all, so codecsAttr finds nothing and the test fails here —
			// which is the regression this case exists to catch.
			name: "single-audio hevc remux",
			spec: Spec{
				Source: src, Method: MethodRemux, VideoCodec: CodecHEVC,
				TranscodeAudio: true, SourceHeight: 240,
				AudioTracks: []AudioTrack{{Index: 0, Language: "en", Default: true}},
			},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out := t.TempDir()
			spec := tc.spec
			spec.OutputDir = out
			run(t, ffmpeg, out, buildArgs(spec))

			master, err := os.ReadFile(filepath.Join(out, PlaylistName))
			if err != nil {
				t.Fatalf("read master: %v", err)
			}
			t.Logf("master as ffmpeg wrote it:\n%s", master)

			raw := codecsAttr(t, string(master))
			served := codecsAttr(t, string(NormalizePlaylist(master)))
			for _, codec := range strings.Split(served, ",") {
				if !strings.HasPrefix(codec, "hvc1") && !strings.HasPrefix(codec, "hev1") {
					continue
				}
				if !validHEVCCodecString(codec) {
					t.Errorf("served CODECS %q contains %q, which a browser codec parser rejects", served, codec)
				}
			}
			// Catch a normalization that silently stops matching. Phrased so that a
			// future ffmpeg emitting a well-formed string is fine (nothing to fix)
			// rather than a build break: only an unchanged *invalid* string fails.
			if raw == served && !validHEVCCodecString(strings.Split(raw, ",")[0]) {
				t.Errorf("CODECS %q left as-is and still invalid — NormalizePlaylist no longer matches "+
					"what ffmpeg writes", raw)
			}
			if raw == served {
				t.Logf("ffmpeg wrote a valid codec string (%q) — upstream may have fixed this; "+
					"NormalizePlaylist is now a no-op here", raw)
			}
		})
	}
}

// codecsAttr pulls the CODECS value off the master playlist's video variant.
func codecsAttr(t *testing.T, master string) string {
	t.Helper()
	m := regexp.MustCompile(`#EXT-X-STREAM-INF:.*CODECS="([^"]+)"`).FindStringSubmatch(master)
	if m == nil {
		t.Fatalf("no video variant with a CODECS attribute in master:\n%s", master)
	}
	return m[1]
}

func hasEncoder(ffmpeg, name string) bool {
	out, err := exec.CommandContext(context.Background(), ffmpeg, "-hide_banner", "-encoders").Output()
	return err == nil && strings.Contains(string(out), name)
}

// genHEVCMultiAudioSource writes the ARGY-174 shape: 8-bit HEVC Main video with
// two audio tracks, the combination the remux path copies through with a hvc1
// tag and a master playlist.
func genHEVCMultiAudioSource(t *testing.T, ffmpeg, path string) {
	t.Helper()
	run(t, ffmpeg, filepath.Dir(path), []string{
		"-y", "-nostdin", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=24",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=2",
		"-f", "lavfi", "-i", "sine=frequency=880:duration=2",
		"-map", "0:v", "-map", "1:a", "-map", "2:a",
		"-c:v", "libx265", "-preset", "ultrafast", "-x265-params", "log-level=none",
		"-pix_fmt", "yuv420p", "-c:a", "aac",
		"-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=jpn",
		"-disposition:a:0", "default", path,
	})
}

// genMultiAudioSource writes a short mkv with one H.264 video and two AAC audio
// tracks (English default + Japanese), the ARGY-126 dub/sub shape.
func genMultiAudioSource(t *testing.T, ffmpeg, path string) {
	t.Helper()
	run(t, ffmpeg, filepath.Dir(path), []string{
		"-y", "-nostdin", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=duration=4:size=320x240:rate=24",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=4",
		"-f", "lavfi", "-i", "sine=frequency=880:duration=4",
		"-map", "0:v", "-map", "1:a", "-map", "2:a",
		"-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac",
		"-metadata:s:a:0", "language=eng", "-metadata:s:a:1", "language=jpn",
		"-disposition:a:0", "default", path,
	})
}

func run(t *testing.T, ffmpeg, dir string, args []string) {
	t.Helper()
	cmd := exec.CommandContext(context.Background(), ffmpeg, args...)
	cmd.Dir = dir
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("ffmpeg %s\nfailed: %v\n%s", strings.Join(args, " "), err, b)
	}
}

// TestHEVCInitSegmentDecoderConfig is the ARGY-222 regression guard. A copied
// HEVC stream is tagged hvc1, which declares that the parameter sets
// (VPS/SPS/PPS) live in the sample entry's hvcC rather than in the bitstream.
// ffmpeg satisfies that by copying the source's decoder config through — and a
// source is allowed not to have one: a Matroska CodecPrivate can be a bare
// 23-byte configuration record with numOfArrays = 0, keeping the parameter sets
// in-band. Given one of those, ffmpeg writes an *empty* hvcC (an 8-byte box, no
// payload) and says nothing at any log level.
//
// What ships then is undecodable rather than merely mislabelled: with no
// lengthSizeMinusOne the samples cannot be split into NAL units at all. It
// reaches the browser looking like a codec-string bug, because hls.js finds
// nothing to parse, falls back to the bare "hvc1" 4CC, and substitutes its
// hardcoded hvc1.1.6.L120.90 placeholder — so the console blames a profile/level
// mismatch for a stream that has no decoder configuration at all.
//
// 15 files in the household library had this shape. The assertion is on the
// bytes in the init segment, not on ffmpeg's arguments, because the argument
// (hevcParamSetBSF) is only worth anything if the hvcC comes out complete.
func TestHEVCInitSegmentDecoderConfig(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test needs ffmpeg")
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not on PATH")
	}
	if !hasEncoder(ffmpeg, "libx265") {
		t.Skip("ffmpeg built without libx265")
	}
	dir := t.TempDir()
	src := filepath.Join(dir, "src.mkv")
	genHEVCInBandParamSetSource(t, ffmpeg, src)

	out := t.TempDir()
	run(t, ffmpeg, out, buildArgs(Spec{
		Source: src, OutputDir: out, Method: MethodRemux, VideoCodec: CodecHEVC,
		TranscodeAudio: true, SourceHeight: 240, AudioTracks: oneTrack,
	}))

	// The master path names the video variant's init segment init_0.mp4.
	init, err := os.ReadFile(filepath.Join(out, "init_0.mp4"))
	if err != nil {
		t.Fatalf("read init segment: %v", err)
	}
	hvcc := hvcCRecord(t, init)

	// hls.js reads profile/tier/level out of bytes 1..12 and gives up below that,
	// which is how an empty record becomes a bare "hvc1" and then a placeholder.
	if len(hvcc) < 23 {
		t.Fatalf("hvcC is %d bytes, want a full 23-byte configuration record — "+
			"a client cannot derive a codec string from this", len(hvcc))
	}
	// ...and a record without parameter-set arrays is what hvc1 must never be:
	// the decoder gets no VPS/SPS/PPS, so it configures and then fails.
	if hvcc[22] == 0 {
		t.Errorf("hvcC declares numOfArrays = 0: the hvc1 tag promises in-band "+
			"parameter sets were moved into the sample entry, and they were not "+
			"(record header: % x)", hvcc[:23])
	}
	t.Logf("hvcC: %d bytes, profile_idc=%d level_idc=%d numOfArrays=%d",
		len(hvcc), hvcc[1]&0x1f, hvcc[12], hvcc[22])
}

// genHEVCInBandParamSetSource writes the ARGY-222 shape: HEVC whose parameter
// sets are in the bitstream and whose container-level decoder config claims none.
//
// x265's repeat-headers puts VPS/SPS/PPS ahead of every keyframe, but ffmpeg
// still writes a complete CodecPrivate alongside them, so the second step edits
// that record's numOfArrays to 0 — an in-place, same-length patch, which is all
// it takes to reproduce the sources this bug came from.
func genHEVCInBandParamSetSource(t *testing.T, ffmpeg, path string) {
	t.Helper()
	run(t, ffmpeg, filepath.Dir(path), []string{
		"-y", "-nostdin", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=duration=2:size=320x240:rate=24",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=2",
		"-map", "0:v", "-map", "1:a",
		"-c:v", "libx265", "-preset", "ultrafast",
		"-x265-params", "log-level=none:repeat-headers=1",
		"-pix_fmt", "yuv420p", "-c:a", "aac",
		"-metadata:s:a:0", "language=eng", "-disposition:a:0", "default", path,
	})
	blankCodecPrivateParamSets(t, path)
}

// blankCodecPrivateParamSets rewrites the Matroska CodecPrivate (element 0x63A2)
// holding an HEVCDecoderConfigurationRecord so it declares zero parameter-set
// arrays. Length is preserved, so no parent element size needs fixing: a reader
// stops after numOfArrays and never looks at the bytes that follow.
func blankCodecPrivateParamSets(t *testing.T, path string) {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read source: %v", err)
	}
	for i := 0; i+3 < len(b); i++ {
		if b[i] != 0x63 || b[i+1] != 0xa2 {
			continue
		}
		size, n := ebmlSize(b[i+2:])
		if n == 0 {
			continue
		}
		payload := i + 2 + n
		// configurationVersion 1 identifies the record; 23 bytes is its minimum.
		if size < 23 || payload+size > len(b) || b[payload] != 0x01 {
			continue
		}
		b[payload+22] = 0
		if err := os.WriteFile(path, b, 0o644); err != nil {
			t.Fatalf("write patched source: %v", err)
		}
		return
	}
	t.Fatalf("no HEVC CodecPrivate found in %s — cannot build the ARGY-222 shape", path)
}

// ebmlSize decodes an EBML variable-size integer, returning its value and the
// number of bytes it occupied (0 when the leading byte is not a valid marker).
func ebmlSize(b []byte) (int, int) {
	if len(b) == 0 {
		return 0, 0
	}
	mask, width := byte(0x80), 1
	for width <= 8 && b[0]&mask == 0 {
		mask >>= 1
		width++
	}
	if width > 8 || len(b) < width {
		return 0, 0
	}
	v := int(b[0] & (mask - 1))
	for i := 1; i < width; i++ {
		v = v<<8 | int(b[i])
	}
	return v, width
}

// hvcCRecord returns the HEVCDecoderConfigurationRecord out of an fMP4 init
// segment: moov/trak/mdia/minf/stbl/stsd/(hvc1|hev1)/hvcC, per ISO/IEC 14496-12.
func hvcCRecord(t *testing.T, init []byte) []byte {
	t.Helper()
	for _, trak := range mp4Boxes(mp4Box(init, "moov", 0), "trak", 0) {
		stsd := mp4Box(mp4Box(mp4Box(mp4Box(trak, "mdia", 0), "minf", 0), "stbl", 0), "stsd", 0)
		// stsd carries a 4-byte version/flags and a 4-byte entry count before its
		// sample entries; a VisualSampleEntry carries 78 bytes before its children.
		for _, tag := range []string{"hvc1", "hev1"} {
			if entry := mp4Box(stsd, tag, 8); entry != nil {
				if hvcc := mp4Box(entry, "hvcC", 78); hvcc != nil {
					return hvcc
				}
				t.Fatalf("%s sample entry carries no hvcC box at all", tag)
			}
		}
	}
	t.Fatal("no HEVC sample entry in the init segment")
	return nil
}

// mp4Box returns the payload of the first child box named typ inside a container
// box's contents, skipping skip bytes of fixed fields first. Nil when absent.
func mp4Box(contents []byte, typ string, skip int) []byte {
	all := mp4Boxes(contents, typ, skip)
	if len(all) == 0 {
		return nil
	}
	return all[0]
}

// mp4Boxes returns the payloads of every child box named typ, in order.
func mp4Boxes(contents []byte, typ string, skip int) [][]byte {
	var out [][]byte
	for o := skip; o+8 <= len(contents); {
		size := int(binary.BigEndian.Uint32(contents[o:]))
		if size < 8 || o+size > len(contents) {
			return out
		}
		if string(contents[o+4:o+8]) == typ {
			out = append(out, contents[o+8:o+size])
		}
		o += size
	}
	return out
}
