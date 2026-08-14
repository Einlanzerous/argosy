package transcode

import (
	"slices"
	"strings"
	"testing"
)

// argValue returns the value following flag in args, or "" if absent.
func argValue(args []string, flag string) string {
	for i, a := range args {
		if a == flag && i+1 < len(args) {
			return args[i+1]
		}
	}
	return ""
}

// TestPackageArgsShape pins the parts of the offline package that make it
// playable on any device: one H.264 8-bit video stream, AAC stereo audio, a
// faststart MP4, and no HLS machinery at all.
func TestPackageArgsShape(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/film.mkv", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
		SourceHeight: 2160,
	})

	if got := argValue(args, "-i"); got != "/media/film.mkv" {
		t.Errorf("input = %q, want the source path", got)
	}
	if got := argValue(args, "-c:v"); got != "libx264" {
		t.Errorf("video codec = %q, want libx264 — a package is H.264 for universality", got)
	}
	if got := argValue(args, "-c:a"); got != "aac" {
		t.Errorf("audio codec = %q, want aac", got)
	}
	if got := argValue(args, "-ac"); got != "2" {
		t.Errorf("channels = %q, want 2 (stereo downmix for headphones)", got)
	}
	if got := argValue(args, "-movflags"); got != "+faststart" {
		t.Errorf("movflags = %q, want +faststart", got)
	}
	if args[len(args)-1] != PackageName {
		t.Errorf("output = %q, want %q", args[len(args)-1], PackageName)
	}
	if !slices.Contains(args, "-y") {
		t.Error("missing -y: a retry after a cancelled attempt must overwrite the partial file, and there is no stdin to answer the prompt")
	}
	if !slices.Contains(args, "-progress") {
		t.Error("missing -progress: the job's percentage comes from it")
	}
	// A 4K source must come down to the cap, not encode at native height.
	if vf := argValue(args, "-vf"); !strings.Contains(vf, "scale=-2:1080") {
		t.Errorf("-vf = %q, want a scale to the 1080p cap", vf)
	}
	// HLS flags belong to sessions, not packages.
	for _, flag := range []string{"-hls_time", "-hls_segment_type", "-master_pl_name", "-var_stream_map"} {
		if slices.Contains(args, flag) {
			t.Errorf("%s leaked into a package; the output is one progressive MP4", flag)
		}
	}
}

// TestPackageArgsNeverUpscales guards the case a small source would otherwise be
// blown up to the cap, costing bytes for no picture.
func TestPackageArgsNeverUpscales(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/ep.mkv", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
		SourceHeight: 720,
	})
	if vf := argValue(args, "-vf"); !strings.Contains(vf, "scale=-2:720") {
		t.Errorf("-vf = %q, want the source's own 720p height", vf)
	}
}

// TestPackageArgsSubCapHeight covers a source below the smallest ladder rung: it
// encodes at its own height rather than being pushed up to 480p.
func TestPackageArgsSubCapHeight(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/old.avi", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
		SourceHeight: 360,
	})
	if vf := argValue(args, "-vf"); !strings.Contains(vf, "scale=-2:360") {
		t.Errorf("-vf = %q, want the source's own 360p height", vf)
	}
}

// TestPackageArgsUnknownHeight covers height 0 (ffprobe told us nothing).
func TestPackageArgsUnknownHeight(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/x.mkv", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
	})
	if vf := argValue(args, "-vf"); !strings.Contains(vf, "scale=-2:1080") {
		t.Errorf("-vf = %q, want the cap when the source height is unknown", vf)
	}
}

// TestPackageArgsMaxHeightOverride covers a caller asking for a smaller package
// than the default cap.
func TestPackageArgsMaxHeightOverride(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/film.mkv", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
		SourceHeight: 2160, MaxHeight: 720,
	})
	if vf := argValue(args, "-vf"); !strings.Contains(vf, "scale=-2:720") {
		t.Errorf("-vf = %q, want the requested 720p cap", vf)
	}
}

// TestPackageArgsKeepsEveryAudioTrack checks that the dub/sub choice ARGY-126
// added to streaming survives being taken offline: every track is mapped,
// language-tagged, and exactly one is marked default.
func TestPackageArgsKeepsEveryAudioTrack(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/anime.mkv", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
		SourceHeight: 1080,
		AudioTracks: []AudioTrack{
			{Index: 0, Language: "en"},
			{Index: 1, Language: "ja", Default: true},
		},
	})
	joined := strings.Join(args, " ")
	for _, want := range []string{"0:a:0", "0:a:1"} {
		if !strings.Contains(joined, want) {
			t.Errorf("missing audio map %q in %q", want, joined)
		}
	}
	if got := argValue(args, "-metadata:s:a:0"); got != "language=en" {
		t.Errorf("track 0 language = %q, want language=en", got)
	}
	if got := argValue(args, "-metadata:s:a:1"); got != "language=ja" {
		t.Errorf("track 1 language = %q, want language=ja", got)
	}
	// The source's default disposition decides, not track order.
	if got := argValue(args, "-disposition:a:1"); got != "default" {
		t.Errorf("default disposition = %q on track 1, want it to follow the source", got)
	}
	if slices.Contains(args, "-disposition:a:0") {
		t.Error("two default audio tracks; exactly one must be default or players pick arbitrarily")
	}
}

// TestPackageArgsSilentSource covers a source with no audio at all: it must
// package rather than fail on an unsatisfiable stream map.
func TestPackageArgsSilentSource(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/silent.mkv", OutputDir: "/tmp/job", Encoder: EncoderSoftware,
		SourceHeight: 1080,
	})
	if got := argValue(args, "-map"); got != "0:v:0" {
		t.Fatalf("first map = %q, want the video stream", got)
	}
	if !slices.Contains(args, "0:a?") {
		t.Error("audio map is not optional; a source with no audio track would fail the encode")
	}
}

// TestPackageArgsHardwareEncoder checks a GPU backend contributes its device
// init and upload, so packaging isn't silently software-only on a box with a GPU.
func TestPackageArgsHardwareEncoder(t *testing.T) {
	args := PackageArgs(PackageSpec{
		Source: "/media/film.mkv", OutputDir: "/tmp/job", Encoder: EncoderVAAPI,
		SourceHeight: 1080,
	})
	if !slices.Contains(args, "-vaapi_device") {
		t.Error("VAAPI package is missing its device init")
	}
	if got := argValue(args, "-c:v"); got != "h264_vaapi" {
		t.Errorf("video codec = %q, want h264_vaapi", got)
	}
	if vf := argValue(args, "-vf"); !strings.Contains(vf, "hwupload") {
		t.Errorf("-vf = %q, want the VAAPI surface upload", vf)
	}
	// Device init must precede -i, or ffmpeg has no device when it opens the input.
	if slices.Index(args, "-vaapi_device") > slices.Index(args, "-i") {
		t.Error("-vaapi_device must come before -i")
	}
}
