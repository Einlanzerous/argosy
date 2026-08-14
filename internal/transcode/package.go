package transcode

import (
	"context"
	"fmt"
)

// PackageName is the artifact an offline-package encode writes into its output
// directory (ARGY-49). Unlike an HLS session — a playlist plus a tree of
// segments — a package is exactly one progressive MP4, because the device that
// downloads it has to play it back from a plain file path with no server
// reachable.
const PackageName = "stow.mp4"

// PackageMaxHeight is the default resolution cap for an offline package. Stow
// exists for the phone-on-a-flight case, where storage is the binding
// constraint and the screen is not: 1080p is already generous, and it is also
// where the H.264 ladder tops out (see ladder).
const PackageMaxHeight = 1080

// PackageSpec describes a one-shot "pack this away for offline viewing" encode.
//
// The output is deliberately the most boring file we can produce: H.264 8-bit
// video in MP4 with AAC stereo audio. Every phone and tablet decodes that in
// hardware, which is the whole point — a stowed file has to play on a device
// that may have no network to fall back on, so this is the one encode in the
// codebase that optimizes for universality over fidelity. HEVC, 10-bit and
// surround are all deliberately given up here; the streaming path (planPlayback)
// is where those are preserved.
type PackageSpec struct {
	// Source is the absolute path to the source media file.
	Source string
	// OutputDir is the directory the MP4 is written into, as PackageName.
	OutputDir string
	// Encoder selects the backend (software/qsv/vaapi/nvenc), as for a session.
	Encoder string
	// SourceHeight is the source video height; 0 when unknown.
	SourceHeight int
	// MaxHeight caps the output height. 0 uses PackageMaxHeight.
	MaxHeight int
	// AudioTracks are the source's selectable audio streams. Every one is kept
	// (each re-encoded to AAC and tagged with its language), so the dub/sub
	// choice ARGY-126 added to streaming survives being taken offline.
	AudioTracks []AudioTrack
}

// packageRung picks the single bitrate-ladder rung an offline package encodes
// at: the widest H.264 rung that is no taller than the source or the cap,
// whichever is smaller. Reusing the ladder keeps offline sizing consistent with
// what the streaming path already produces, and never upscales.
func packageRung(sourceHeight, maxHeight int) rung {
	if maxHeight <= 0 {
		maxHeight = PackageMaxHeight
	}
	h := sourceHeight
	if h <= 0 || h > maxHeight {
		h = maxHeight
	}
	// rungsForCodec returns the applicable rungs widest-first, and handles the
	// sub-480p source case by synthesizing a rung at the source's own height.
	return rungsForCodec(h, CodecH264)[0]
}

// PackageArgs builds the ffmpeg arguments for an offline package: one MP4, one
// video stream, every audio track as AAC stereo. Paths are relative — ffmpeg
// runs with cwd == spec.OutputDir.
func PackageArgs(spec PackageSpec) []string {
	enc := encoderFor(spec.Encoder)
	r := packageRung(spec.SourceHeight, spec.MaxHeight)

	args := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}
	// Hardware backends inject device/hwaccel init before the input.
	args = append(args, enc.globalArgs()...)
	args = append(args, "-i", spec.Source)

	args = append(args, "-map", "0:v:0")
	args = append(args, packageAudioMaps(spec.AudioTracks)...)

	args = append(args, "-vf", enc.scale(r.height))
	args = append(args, enc.videoCodec(CodecH264)...)
	args = append(args, enc.rateControl(-1, r)...)
	args = append(args, "-c:a", "aac", "-b:a", audioBitrate, "-ac", "2")
	args = append(args, packageAudioMetadata(spec.AudioTracks)...)

	// +faststart relocates the moov atom to the front of the file in a second
	// pass. It costs one rewrite at the end of the encode and buys playback that
	// starts without seeking to the tail — which matters on a phone reading the
	// file off slow storage, and makes a partially-verified download inspectable.
	args = append(args, "-movflags", "+faststart")
	// -y so a retry after a failed or cancelled attempt overwrites the partial
	// file instead of blocking on ffmpeg's overwrite prompt (there is no stdin).
	return append(args, "-progress", "pipe:1", "-y", PackageName)
}

// packageAudioMaps maps every selectable source audio track into the package, in
// track order, so output stream a:i lines up with AudioTracks[i].
func packageAudioMaps(tracks []AudioTrack) []string {
	if len(tracks) == 0 {
		// Optional map (the `?` suffix): a source with no audio at all still
		// packages rather than failing the encode outright.
		return []string{"-map", "0:a?"}
	}
	out := make([]string, 0, len(tracks)*2)
	for _, t := range tracks {
		out = append(out, "-map", fmt.Sprintf("0:a:%d", t.Index))
	}
	return out
}

// packageAudioMetadata tags each output audio stream with its language and marks
// exactly one as the default, so an offline player's track picker shows the same
// labelled choices the streaming path does. Without this ffmpeg emits untagged
// streams and the picker reads "Track 1 / Track 2".
func packageAudioMetadata(tracks []AudioTrack) []string {
	if len(tracks) < 2 {
		return nil
	}
	out := make([]string, 0, len(tracks)*2+2)
	def := 0
	for i, t := range tracks {
		if t.Default {
			def = i
			break
		}
	}
	for i, t := range tracks {
		lang := t.Language
		if lang == "" {
			lang = "und"
		}
		out = append(out, fmt.Sprintf("-metadata:s:a:%d", i), "language="+lang)
	}
	return append(out, fmt.Sprintf("-disposition:a:%d", def), "default")
}

// Package runs an offline-package encode to completion, writing PackageName into
// spec.OutputDir and reporting progress as it goes. It blocks until ffmpeg
// exits, errors, or ctx is cancelled — a cancelled package leaves a partial file
// the caller is expected to purge along with the job.
func (b LocalFFmpeg) Package(ctx context.Context, spec PackageSpec, onProgress func(Progress)) error {
	return b.exec(ctx, spec.OutputDir, PackageArgs(spec), onProgress)
}
