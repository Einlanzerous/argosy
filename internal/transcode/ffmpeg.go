package transcode

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// PlaylistName is the HLS master playlist ffmpeg writes and clients fetch first;
// it references the per-variant playlists (stream_N.m3u8).
const PlaylistName = "index.m3u8"

// LocalFFmpeg runs transcodes with the local ffmpeg binary. It is the default
// Backend; a remote-worker backend (ARGY-57) can implement the same interface.
type LocalFFmpeg struct {
	// Bin is the ffmpeg binary; defaults to "ffmpeg" when empty.
	Bin string
}

// Name identifies this backend.
func (LocalFFmpeg) Name() string { return "local-ffmpeg" }

func (b LocalFFmpeg) bin() string {
	if b.Bin != "" {
		return b.Bin
	}
	return "ffmpeg"
}

// Run builds the HLS ffmpeg invocation for spec, runs it from spec.OutputDir
// (so every artifact lands there), and streams progress. The process is killed
// (SIGTERM then forced after WaitDelay) when ctx is cancelled, so no ffmpeg is
// orphaned on stop/seek/shutdown.
func (b LocalFFmpeg) Run(ctx context.Context, spec Spec, onProgress func(Progress)) error {
	cmd := exec.CommandContext(ctx, b.bin(), buildArgs(spec)...)
	cmd.Dir = spec.OutputDir
	// Graceful stop: SIGTERM lets ffmpeg flush, then CommandContext force-kills
	// after WaitDelay if it ignores the signal.
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGTERM) }
	cmd.WaitDelay = 5 * time.Second

	progress, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	if onProgress != nil {
		go parseProgress(progress, onProgress)
	} else {
		go func() { _, _ = io.Copy(io.Discard, progress) }()
	}
	return cmd.Wait()
}

// rung is one rendition of the adaptive bitrate ladder.
type rung struct {
	height       int
	videoBitrate string
	maxRate      string
	bufSize      string
}

// ladder is the H.264 bitrate ladder, widest first. It tops out at 1080p:
// H.264 at 2160p needs impractical bitrates, so true-4K output uses hevcLadder.
var ladder = []rung{
	{1080, "6M", "6400k", "12M"},
	{720, "3M", "3200k", "6M"},
	{480, "1500k", "1600k", "3M"},
}

// hevcLadder is the HEVC bitrate ladder. HEVC reaches similar quality at ~40%
// less bitrate than H.264, so it carries a viable 2160p rung for true 4K. Only
// used when the client negotiated HEVC and we must re-encode a >1080p source
// (the common 4K case is remux-copy, which never touches this).
var hevcLadder = []rung{
	{2160, "16M", "18M", "32M"},
	{1080, "4M", "4400k", "8M"},
	{720, "2M", "2200k", "4M"},
}

const audioBitrate = "128k"

// rungsForCodec returns the bitrate-ladder rungs for a source of the given
// height in the given output codec: every rung at or below the source height
// (never upscale). A source smaller than the smallest rung encodes at its own
// height; an unknown height collapses to a single conservative 720p rung.
func rungsForCodec(sourceHeight int, codec string) []rung {
	l := ladder
	if resolveCodec(codec) == CodecHEVC {
		l = hevcLadder
	}
	if sourceHeight <= 0 {
		// Unknown source: one conservative 720p rung (the 720 entry in either ladder).
		for _, r := range l {
			if r.height == 720 {
				return []rung{r}
			}
		}
		return []rung{l[len(l)-1]}
	}
	var out []rung
	for _, r := range l {
		if r.height <= sourceHeight {
			out = append(out, r)
		}
	}
	if len(out) == 0 {
		out = []rung{{sourceHeight, "1500k", "1600k", "3M"}}
	}
	return out
}

// buildArgs builds the ffmpeg arguments for an HLS encode, dispatching on the
// decision engine's choice: a remux copies the existing codecs into fMP4 (no
// re-encode), while a transcode re-encodes through the bitrate ladder. Paths
// are relative — ffmpeg runs with cwd == spec.OutputDir.
func buildArgs(spec Spec) []string {
	if spec.Method == MethodRemux {
		return buildRemuxArgs(spec)
	}
	return buildTranscodeArgs(spec)
}

// buildRemuxArgs copies the source video into a single-variant CMAF HLS without
// re-encoding — the cheap path when the video codec is browser-playable but the
// container isn't (e.g. H.264/AAC in Matroska), or when a client can play the
// source codec natively (e.g. HEVC/4K). The video stream is always copied
// (preserving resolution, bit depth, and HDR — this is what makes true 4K
// possible). Audio is copied too, unless spec.TranscodeAudio is set, in which
// case only the audio is re-encoded to stereo AAC (e.g. TrueHD/DTS → AAC while
// the 4K HEVC video passes through untouched).
func buildRemuxArgs(spec Spec) []string {
	// Remux copies the video (no re-encode), so the encoder backend is
	// irrelevant; software contributes no hwaccel flags.
	args := inputArgs(spec, softwareEncoder{})
	args = append(args, "-map", "0:v:0", "-map", "0:a:0", "-c:v", "copy")
	if resolveCodec(spec.VideoCodec) == CodecHEVC {
		// Copied HEVC needs the hvc1 sample-entry tag for fMP4/MSE playback.
		args = append(args, "-tag:v", "hvc1")
	}
	if spec.TranscodeAudio {
		args = append(args, "-c:a", "aac", "-b:a", audioBitrate, "-ac", "2")
	} else {
		args = append(args, "-c:a", "copy")
	}
	return append(args, singleOutputTail()...)
}

// buildTranscodeArgs re-encodes the source. A single rung emits one media
// playlist (index.m3u8) directly; multiple rungs emit a master playlist + one
// variant playlist/init/segments per rung for adaptive streaming. The video
// codec/scale/hwaccel flags come from the selected encoder backend (software
// today; qsv/vaapi/nvenc in ARGY-30/61).
func buildTranscodeArgs(spec Spec) []string {
	enc := encoderFor(spec.Encoder)
	codec := resolveCodec(spec.VideoCodec)
	rungs := rungsForCodec(spec.SourceHeight, codec)
	if len(rungs) == 1 {
		return buildSingleTranscodeArgs(spec, enc, codec, rungs[0])
	}
	return buildLadderArgs(spec, enc, codec, rungs)
}

func buildSingleTranscodeArgs(spec Spec, enc videoEncoder, codec string, r rung) []string {
	args := inputArgs(spec, enc)
	args = append(args, "-map", "0:v:0", "-map", "0:a:0", "-vf", enc.scale(r.height))
	args = append(args, enc.videoCodec(codec)...)
	args = append(args, enc.rateControl(-1, r)...)
	args = append(args, "-c:a", "aac", "-b:a", audioBitrate, "-ac", "2")
	return append(args, singleOutputTail()...)
}

func buildLadderArgs(spec Spec, enc videoEncoder, codec string, rungs []rung) []string {
	n := len(rungs)
	args := inputArgs(spec, enc)

	// Split the video once and scale each branch to its rung height (-2 keeps
	// the width even and preserves aspect ratio).
	var fc strings.Builder
	fmt.Fprintf(&fc, "[0:v]split=%d", n)
	for i := range rungs {
		fmt.Fprintf(&fc, "[v%d]", i)
	}
	for i, r := range rungs {
		fmt.Fprintf(&fc, ";[v%d]%s[v%do]", i, enc.scale(r.height), i)
	}
	args = append(args, "-filter_complex", fc.String())

	for i := range rungs {
		args = append(args, "-map", fmt.Sprintf("[v%do]", i))
	}
	for range rungs {
		args = append(args, "-map", "0:a:0")
	}

	args = append(args, enc.videoCodec(codec)...)
	for i, r := range rungs {
		args = append(args, enc.rateControl(i, r)...)
	}
	args = append(args, "-c:a", "aac", "-b:a", audioBitrate, "-ac", "2")

	var vsm strings.Builder
	for i := range rungs {
		if i > 0 {
			vsm.WriteByte(' ')
		}
		fmt.Fprintf(&vsm, "v:%d,a:%d", i, i)
	}

	args = append(args,
		"-f", "hls", "-hls_time", "4", "-hls_playlist_type", "event",
		"-hls_segment_type", "fmp4", "-hls_flags", "independent_segments",
		"-hls_fmp4_init_filename", "init_%v.mp4",
		"-master_pl_name", PlaylistName,
		"-var_stream_map", vsm.String(),
		"-hls_segment_filename", "stream_%v_%05d.m4s",
		"-progress", "pipe:1",
		"stream_%v.m3u8",
	)
	return args
}

func inputArgs(spec Spec, enc videoEncoder) []string {
	args := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}
	// Hardware backends inject device/hwaccel init here, before the input.
	args = append(args, enc.globalArgs()...)
	if spec.StartAt > 0 {
		args = append(args, "-ss", strconv.FormatFloat(spec.StartAt, 'f', 3, 64))
	}
	return append(args, "-i", spec.Source)
}

// singleOutputTail writes one media playlist directly at index.m3u8 (no master,
// no %v variant substitution — which ffmpeg does not expand in the init
// filename for a lone variant).
func singleOutputTail() []string {
	return []string{
		"-f", "hls", "-hls_time", "4", "-hls_playlist_type", "event",
		"-hls_segment_type", "fmp4", "-hls_flags", "independent_segments",
		"-hls_fmp4_init_filename", "init.mp4",
		"-hls_segment_filename", "stream_%05d.m4s",
		"-progress", "pipe:1",
		PlaylistName,
	}
}

// parseProgress reads ffmpeg's -progress key=value stream and reports a Progress
// snapshot at each "progress=" boundary (ffmpeg emits one per stats interval).
func parseProgress(r io.Reader, onProgress func(Progress)) {
	sc := bufio.NewScanner(r)
	var cur Progress
	for sc.Scan() {
		key, val, ok := strings.Cut(sc.Text(), "=")
		if !ok {
			continue
		}
		switch strings.TrimSpace(key) {
		case "out_time_us":
			if v, err := strconv.ParseInt(strings.TrimSpace(val), 10, 64); err == nil {
				cur.OutTimeMS = v / 1000
			}
		case "fps":
			if v, err := strconv.ParseFloat(strings.TrimSpace(val), 64); err == nil {
				cur.FPS = v
			}
		case "speed":
			// e.g. "2.53x"
			if v, err := strconv.ParseFloat(strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(val), "x")), 64); err == nil {
				cur.Speed = v
			}
		case "progress":
			onProgress(cur)
		}
	}
}
