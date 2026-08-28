package transcode

import (
	"encoding/binary"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestBuildArgsBurnInSingleRung pins the single-output burn-in shape: the
// overlay needs two filter inputs, so -vf can't express it and the video comes
// out of a filter_complex label instead of the source stream.
func TestBuildArgsBurnInSingleRung(t *testing.T) {
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode,
		SourceHeight: 480, BurnInSubtitle: 3,
	})
	joined := strings.Join(args, " ")
	for _, want := range []string{
		"-filter_complex [0:v:0][0:3]overlay,scale=-2:480,format=nv12[vout]",
		"-map [vout]",
		"libx264",
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("burn-in args missing %q\nargs: %s", want, joined)
		}
	}
	// The source video must not also be mapped directly, or ffmpeg encodes two
	// video streams and the second one has no subtitle on it.
	if strings.Contains(joined, "-map 0:v:0") {
		t.Errorf("burn-in must map the filter output, not the source stream\nargs: %s", joined)
	}
	if strings.Contains(joined, "-vf ") {
		t.Errorf("burn-in must build the graph with -filter_complex, not -vf\nargs: %s", joined)
	}
}

// TestBuildArgsBurnInLadder composites once, ahead of the split, so a 3-rung
// ladder decodes and overlays the subtitle a single time rather than three.
func TestBuildArgsBurnInLadder(t *testing.T) {
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode,
		SourceHeight: 1080, Encoder: EncoderSoftware, BurnInSubtitle: 4,
	})
	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "[0:v:0][0:4]overlay,split=3[v0][v1][v2]") {
		t.Errorf("ladder must overlay once before the split\nargs: %s", joined)
	}
	if strings.Count(joined, "overlay") != 1 {
		t.Errorf("overlay applied %d times, want once\nargs: %s", strings.Count(joined, "overlay"), joined)
	}
	for _, want := range []string{"scale=-2:1080", "scale=-2:480", "-var_stream_map v:0,a:0 v:1,a:1 v:2,a:2"} {
		if !strings.Contains(joined, want) {
			t.Errorf("ladder args missing %q\nargs: %s", want, joined)
		}
	}
}

// TestBuildArgsBurnInRefusesRemux is the belt to the decision engine's braces.
// planPlayback already routes a burn-in to the transcode path; if some future
// caller hands the backend a remux anyway, the copy must not win — a copied
// stream is the source's pixels, with no subtitle drawn on them, so the viewer
// would get a session that looks healthy and shows nothing.
func TestBuildArgsBurnInRefusesRemux(t *testing.T) {
	args := buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodRemux,
		SourceHeight: 1080, Encoder: EncoderSoftware, BurnInSubtitle: 2,
	})
	joined := strings.Join(args, " ")
	if strings.Contains(joined, "-c:v copy") {
		t.Errorf("a burn-in spec must never copy the video\nargs: %s", joined)
	}
	if !strings.Contains(joined, "overlay") {
		t.Errorf("a burn-in spec must draw the subtitle\nargs: %s", joined)
	}
}

// TestBuildArgsWithoutBurnInUnchanged guards the other direction: every session
// that isn't burning anything in must build exactly the arguments it built
// before ARGY-59, with no filtergraph rewrite and no stray subtitle input.
func TestBuildArgsWithoutBurnInUnchanged(t *testing.T) {
	for _, spec := range []Spec{
		{Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodRemux},
		{Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode, SourceHeight: 480},
		{Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode, SourceHeight: 1080, Encoder: EncoderSoftware},
	} {
		joined := strings.Join(buildArgs(spec), " ")
		if strings.Contains(joined, "overlay") {
			t.Errorf("non-burn-in spec %+v grew an overlay\nargs: %s", spec, joined)
		}
	}
	// The ladder head is the one shared string between the two paths.
	plain := strings.Join(buildArgs(Spec{
		Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode,
		SourceHeight: 1080, Encoder: EncoderSoftware,
	}), " ")
	if !strings.Contains(plain, "-filter_complex [0:v]split=3") {
		t.Errorf("plain ladder graph changed shape\nargs: %s", plain)
	}
}

// TestSessionIDScopedToBurnIn: turning captions on has to start its own encode.
// Sessions are joined by id, so if the burned-in track weren't part of the key,
// selecting a subtitle at the position you're already watching would return the
// running session — the one without subtitles — and nothing would appear.
func TestSessionIDScopedToBurnIn(t *testing.T) {
	base := StartRequest{ItemID: "i", AccountID: "acct-1", Encoder: "software"}
	burned := base
	burned.BurnInSubtitle = 3
	other := base
	other.BurnInSubtitle = 4

	if sessionID(base) == sessionID(burned) {
		t.Error("a burned-in session shares its id with the plain one")
	}
	if sessionID(burned) == sessionID(other) {
		t.Error("two different burned-in tracks share one session id")
	}
	// Determinism itself is TestSessionIDDeterministicAndScoped's job; what
	// matters here is only that the burned track separates the keys.
}

// TestBurnInIntegration runs the real buildArgs output through a real ffmpeg
// against a source carrying a real PGS subtitle stream, and checks the pixels.
//
// Everything cheaper than this only asserts that we asked ffmpeg for an overlay.
// What actually has to hold is that ffmpeg's sub2video path turns a bitmap
// subtitle stream into frames the overlay filter can composite — behaviour of
// the pinned binary, not of this package — and that the result is visible in the
// segments a client would fetch. The source is black and the subtitle is white,
// so "did it draw" is decidable from luma alone: bright frames while the
// subtitle is up, none once it clears.
func TestBurnInIntegration(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test needs ffmpeg")
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not on PATH")
	}
	dir := t.TempDir()
	src := filepath.Join(dir, "src.mkv")
	genPGSSource(t, ffmpeg, src)

	// The synthesized source is 320x240 video, audio, then the PGS stream, so
	// the subtitle's absolute index — what a burn:N track id carries — is 2.
	const pgsStream = 2

	for _, tc := range []struct {
		name      string
		burnIn    int
		wantBurnt bool
	}{
		{name: "subtitle burned in", burnIn: pgsStream, wantBurnt: true},
		{name: "no subtitle selected", burnIn: 0, wantBurnt: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out := t.TempDir()
			run(t, ffmpeg, out, buildArgs(Spec{
				Source: src, OutputDir: out, Method: MethodTranscode,
				Encoder: EncoderSoftware, SourceHeight: 240, BurnInSubtitle: tc.burnIn,
			}))

			bright := brightFrames(t, ffmpeg, out, filepath.Join(out, PlaylistName))
			switch {
			case tc.wantBurnt && bright == 0:
				t.Error("no frame carries the subtitle: the overlay drew nothing")
			case !tc.wantBurnt && bright > 0:
				t.Errorf("%d frames are lit without a subtitle selected", bright)
			}
		})
	}
}

// brightFrames decodes an HLS playlist to raw 8-bit grayscale and counts the
// frames containing a near-white pixel.
func brightFrames(t *testing.T, ffmpeg, dir, playlist string) int {
	t.Helper()
	raw := filepath.Join(dir, "frames.gray")
	run(t, ffmpeg, dir, []string{
		"-y", "-nostdin", "-hide_banner", "-loglevel", "error",
		"-i", playlist, "-pix_fmt", "gray", "-f", "rawvideo", raw,
	})
	b, err := os.ReadFile(raw)
	if err != nil {
		t.Fatalf("read decoded frames: %v", err)
	}
	const frameSize = 320 * 240
	if len(b) < frameSize {
		t.Fatalf("decoded %d bytes, less than one 320x240 frame", len(b))
	}
	lit := 0
	for i := 0; i+frameSize <= len(b); i += frameSize {
		for _, px := range b[i : i+frameSize] {
			// The subtitle is drawn at Y=235; black is 0. Anything this bright
			// can only be the overlay, and the margin swallows encoder ringing.
			if px > 200 {
				lit++
				break
			}
		}
	}
	return lit
}

// genPGSSource writes a 4-second 320x240 black video with one audio track and a
// real hdmv_pgs_subtitle stream — the codec every Blu-ray rip in the library
// carries, and the one ARGY-59 exists for.
//
// The subtitle is copied in from a hand-built .sup rather than encoded, because
// ffmpeg cannot make one: it refuses text→bitmap subtitle conversion ("Subtitle
// encoding currently only possible from text to text or bitmap to bitmap"), so
// there is no way to turn an .srt into PGS on the fly. Writing the display sets
// directly is the only way to keep this test hermetic.
func genPGSSource(t *testing.T, ffmpeg, path string) {
	t.Helper()
	dir := filepath.Dir(path)
	sup := filepath.Join(dir, "sub.sup")
	if err := os.WriteFile(sup, buildPGS(), 0o644); err != nil {
		t.Fatalf("write sup: %v", err)
	}
	run(t, ffmpeg, dir, []string{
		"-y", "-nostdin", "-hide_banner", "-loglevel", "error",
		"-f", "lavfi", "-i", "color=c=black:s=320x240:d=4:r=24",
		"-f", "lavfi", "-i", "sine=frequency=440:duration=4",
		"-i", sup,
		"-map", "0:v", "-map", "1:a", "-map", "2:s",
		"-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", "-c:s", "copy",
		path,
	})
}

// PGS segment types (HDMV Presentation Graphic Stream).
const (
	pgsPDS = 0x14 // palette definition
	pgsODS = 0x15 // object definition (the bitmap)
	pgsPCS = 0x16 // presentation composition
	pgsWDS = 0x17 // window definition
	pgsEND = 0x80 // end of display set
)

// buildPGS produces a raw PGS stream with two display sets: one that shows a
// white rectangle at 1s, one that clears it at 3s. ffmpeg's `sup` demuxer reads
// this format directly, so it can be muxed into Matroska with -c:s copy.
func buildPGS() []byte {
	const (
		videoW, videoH = 320, 240
		objW, objH     = 120, 40
		objX, objY     = 100, 100
	)

	// seg wraps a payload in the PGS segment header: magic, PTS and DTS in a
	// 90kHz clock, the type, then the payload length.
	seg := func(kind byte, ptsSeconds float64, payload []byte) []byte {
		b := []byte{'P', 'G'}
		b = binary.BigEndian.AppendUint32(b, uint32(ptsSeconds*90000))
		b = binary.BigEndian.AppendUint32(b, 0) // DTS
		b = append(b, kind)
		b = binary.BigEndian.AppendUint16(b, uint16(len(payload)))
		return append(b, payload...)
	}

	// composition describes the frame and, when showing, where the object goes.
	composition := func(show bool) []byte {
		b := binary.BigEndian.AppendUint16(nil, videoW)
		b = binary.BigEndian.AppendUint16(b, videoH)
		b = append(b, 0x10) // frame rate (fixed by the spec)
		if !show {
			b = binary.BigEndian.AppendUint16(b, 1) // composition number
			return append(b, 0x00, 0x00, 0x00, 0x00)
		}
		b = binary.BigEndian.AppendUint16(b, 0) // composition number
		b = append(b, 0x80,                     // epoch start
			0x00, // no palette update
			0x00, // palette id
			0x01) // one composition object
		b = binary.BigEndian.AppendUint16(b, 0) // object id
		b = append(b, 0x00,                     // window id
			0x00) // not cropped
		b = binary.BigEndian.AppendUint16(b, objX)
		return binary.BigEndian.AppendUint16(b, objY)
	}

	window := func() []byte {
		b := []byte{0x01, 0x00} // one window, id 0
		b = binary.BigEndian.AppendUint16(b, objX)
		b = binary.BigEndian.AppendUint16(b, objY)
		b = binary.BigEndian.AppendUint16(b, objW)
		return binary.BigEndian.AppendUint16(b, objH)
	}

	// Two entries: 0 is transparent, 1 is opaque white. Y/Cr/Cb/alpha.
	palette := []byte{
		0x00, 0x00, // palette id, version
		0, 16, 128, 128, 0,
		1, 235, 128, 128, 255,
	}

	// object is the bitmap: objH lines of objW pixels in colour 1. PGS runs are
	// "00 80|n cc" for n<64 pixels of colour cc, and "00 00" ends a line.
	object := func() []byte {
		var rle []byte
		for range objH {
			for left := objW; left > 0; {
				n := min(left, 63)
				rle = append(rle, 0x00, 0x80|byte(n), 0x01)
				left -= n
			}
			rle = append(rle, 0x00, 0x00)
		}
		data := binary.BigEndian.AppendUint16(nil, objW)
		data = binary.BigEndian.AppendUint16(data, objH)
		data = append(data, rle...)

		b := binary.BigEndian.AppendUint16(nil, 0) // object id
		b = append(b, 0x00,                        // version
			0xC0) // first and last fragment
		// Length is 24-bit and covers the width, height and RLE that follow.
		l := binary.BigEndian.AppendUint32(nil, uint32(len(data)))
		b = append(b, l[1:]...)
		return append(b, data...)
	}

	var out []byte
	out = append(out, seg(pgsPCS, 1, composition(true))...)
	out = append(out, seg(pgsWDS, 1, window())...)
	out = append(out, seg(pgsPDS, 1, palette)...)
	out = append(out, seg(pgsODS, 1, object())...)
	out = append(out, seg(pgsEND, 1, nil)...)

	out = append(out, seg(pgsPCS, 3, composition(false))...)
	out = append(out, seg(pgsWDS, 3, window())...)
	return append(out, seg(pgsEND, 3, nil)...)
}
