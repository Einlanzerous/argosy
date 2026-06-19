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

// ladder is the full bitrate ladder, widest first. rungsFor trims it to the
// source so we never upscale.
var ladder = []rung{
	{1080, "6M", "6400k", "12M"},
	{720, "3M", "3200k", "6M"},
	{480, "1500k", "1600k", "3M"},
}

const audioBitrate = "128k"

// rungsFor returns the ladder rungs appropriate for a source of the given
// height: every rung at or below the source height (never upscale). A source
// smaller than the smallest rung encodes at its own height; an unknown height
// collapses to a single conservative 720p rung.
func rungsFor(sourceHeight int) []rung {
	if sourceHeight <= 0 {
		return []rung{{720, "3M", "3200k", "6M"}}
	}
	var out []rung
	for _, r := range ladder {
		if r.height <= sourceHeight {
			out = append(out, r)
		}
	}
	if len(out) == 0 {
		out = []rung{{sourceHeight, "1500k", "1600k", "3M"}}
	}
	return out
}

// buildArgs builds the ffmpeg arguments for a CMAF (fMP4) HLS encode with a
// source-derived bitrate ladder: a master playlist (index.m3u8) plus one
// variant playlist + init segment + media segments per rung. Paths are
// relative — ffmpeg runs with cwd == spec.OutputDir. The encoder switch
// (qsv/vaapi/nvenc) lands in ARGY-30; today everything is software libx264/aac.
func buildArgs(spec Spec) []string {
	rungs := rungsFor(spec.SourceHeight)
	n := len(rungs)

	args := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}
	if spec.StartAt > 0 {
		args = append(args, "-ss", strconv.FormatFloat(spec.StartAt, 'f', 3, 64))
	}
	args = append(args, "-i", spec.Source)

	// Split the video once and scale each branch to its rung height (-2 keeps
	// the width even and preserves aspect ratio).
	var fc strings.Builder
	fmt.Fprintf(&fc, "[0:v]split=%d", n)
	for i := range rungs {
		fmt.Fprintf(&fc, "[v%d]", i)
	}
	for i, r := range rungs {
		fmt.Fprintf(&fc, ";[v%d]scale=-2:%d[v%do]", i, r.height, i)
	}
	args = append(args, "-filter_complex", fc.String())

	for i := range rungs {
		args = append(args, "-map", fmt.Sprintf("[v%do]", i))
	}
	for range rungs {
		args = append(args, "-map", "0:a:0")
	}

	args = append(args, "-c:v", "libx264", "-preset", "veryfast",
		"-g", "48", "-keyint_min", "48", "-sc_threshold", "0")
	for i, r := range rungs {
		args = append(args,
			fmt.Sprintf("-b:v:%d", i), r.videoBitrate,
			fmt.Sprintf("-maxrate:v:%d", i), r.maxRate,
			fmt.Sprintf("-bufsize:v:%d", i), r.bufSize)
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
