package mediatool

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"time"
)

// Probe is the technical metadata extracted from a media file.
type Probe struct {
	Container       string          // ffprobe format_name
	DurationSeconds float64         // 0 if unknown
	Raw             json.RawMessage // full ffprobe JSON (stored in media_items.technical)
}

// ProbeFile runs ffprobe against path and parses the result.
func ProbeFile(ctx context.Context, path string) (Probe, error) {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()

	out, err := exec.CommandContext(ctx, "ffprobe",
		"-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", path).Output()
	if err != nil {
		return Probe{}, fmt.Errorf("ffprobe %s: %w", path, err)
	}
	return parseProbe(out)
}

func parseProbe(data []byte) (Probe, error) {
	var doc struct {
		Format struct {
			FormatName string `json:"format_name"`
			Duration   string `json:"duration"`
		} `json:"format"`
	}
	if err := json.Unmarshal(data, &doc); err != nil {
		return Probe{}, fmt.Errorf("parse ffprobe json: %w", err)
	}
	p := Probe{Container: doc.Format.FormatName, Raw: json.RawMessage(data)}
	if doc.Format.Duration != "" {
		if d, err := strconv.ParseFloat(doc.Format.Duration, 64); err == nil {
			p.DurationSeconds = d
		}
	}
	return p, nil
}
