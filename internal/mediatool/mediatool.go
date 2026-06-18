// Package mediatool wraps the external media toolchain (ffmpeg/ffprobe).
// Argosy shells out for all media work; this package is the seam later phases
// build on (probing, transcode-session orchestration, etc.).
package mediatool

import (
	"context"
	"log/slog"
	"os/exec"
	"strings"
	"time"
)

// LogVersions logs the ffmpeg/ffprobe versions if they are on PATH. It never
// fails: a missing toolchain is logged as a warning so it is obvious at startup.
func LogVersions(ctx context.Context, logger *slog.Logger) {
	for _, bin := range []string{"ffmpeg", "ffprobe"} {
		if v, err := version(ctx, bin); err != nil {
			logger.Warn("media tool not available", "tool", bin, "err", err)
		} else {
			logger.Info("media tool", "tool", bin, "version", v)
		}
	}
}

func version(ctx context.Context, bin string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, bin, "-version").Output()
	if err != nil {
		return "", err
	}
	line, _, _ := strings.Cut(string(out), "\n")
	return strings.TrimSpace(line), nil
}
