package transcode

import (
	"context"
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
