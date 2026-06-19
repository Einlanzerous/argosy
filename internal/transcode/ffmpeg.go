package transcode

import (
	"bufio"
	"context"
	"io"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// PlaylistName is the per-session HLS media playlist ffmpeg writes and clients
// fetch. Segments sit alongside it as seg00000.ts, seg00001.ts, …
const PlaylistName = "index.m3u8"

const segmentPattern = "seg%05d.ts"

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

// Run builds the HLS ffmpeg invocation for spec, runs it, and streams progress.
// The process is killed (SIGTERM then forced after WaitDelay) when ctx is
// cancelled, so no ffmpeg is orphaned on stop/seek/shutdown.
func (b LocalFFmpeg) Run(ctx context.Context, spec Spec, onProgress func(Progress)) error {
	cmd := exec.CommandContext(ctx, b.bin(), buildArgs(spec)...)
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

// buildArgs builds the ffmpeg arguments for a single-variant HLS encode. The
// proper CMAF bitrate ladder + master playlist lands in ARGY-28; the encoder
// switch (qsv/vaapi/nvenc) lands in ARGY-30 — today everything encodes with the
// software libx264/aac path.
func buildArgs(spec Spec) []string {
	args := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}
	// Input seek before -i is fast (keyframe granularity) — fine for a start
	// offset; accurate seek can come later if needed.
	if spec.StartAt > 0 {
		args = append(args, "-ss", strconv.FormatFloat(spec.StartAt, 'f', 3, 64))
	}
	args = append(args,
		"-i", spec.Source,
		"-map", "0:v:0", "-map", "0:a:0?",
		// Software H.264; 2s keyframe cadence aligns with the 4s segments.
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
		"-maxrate", "6M", "-bufsize", "12M",
		"-g", "48", "-keyint_min", "48", "-sc_threshold", "0",
		"-c:a", "aac", "-b:a", "160k", "-ac", "2",
		"-f", "hls", "-hls_time", "4", "-hls_playlist_type", "event",
		"-hls_segment_type", "mpegts",
		"-hls_flags", "independent_segments",
		"-hls_segment_filename", filepath.Join(spec.OutputDir, segmentPattern),
		"-progress", "pipe:1",
		filepath.Join(spec.OutputDir, PlaylistName),
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
