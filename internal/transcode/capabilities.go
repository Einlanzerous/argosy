package transcode

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"time"
)

// Encoder identifies a hardware/software encode path. The ffmpeg H.264 encoder
// name for each is in encoderH264.
const (
	EncoderSoftware = "software"
	EncoderQSV      = "qsv"
	EncoderVAAPI    = "vaapi"
	EncoderNVENC    = "nvenc"
)

// DefaultPreference is the encoder fallback order used when none is configured.
var DefaultPreference = []string{EncoderNVENC, EncoderQSV, EncoderVAAPI, EncoderSoftware}

// Capabilities reports which encoders this host supports and which one was
// selected by the configured preference order. It is surfaced to The Helm and
// drives encoder selection (the hardware paths are wired in ARGY-30; today only
// the software path is actually used for encoding).
type Capabilities struct {
	Available []string `json:"available"`
	Selected  string   `json:"selected"`
}

// Probe detects available encoders by intersecting the ffmpeg build's encoder
// list with the hardware actually present, then selects the first available
// encoder in preference order. Software is always available as the floor.
func Probe(ctx context.Context, bin string, preference []string) Capabilities {
	if bin == "" {
		bin = "ffmpeg"
	}
	if len(preference) == 0 {
		preference = DefaultPreference
	}
	built := builtEncoders(ctx, bin)
	hasDRI := deviceExists("/dev/dri")
	hasNvidia := deviceExists("/dev/nvidia0") || onPath("nvidia-smi")

	avail := []string{EncoderSoftware} // libx264 ships with every ffmpeg build we use
	for _, enc := range []string{EncoderQSV, EncoderVAAPI, EncoderNVENC} {
		// A backend counts as available when its H.264 encoder is built; the HEVC
		// variant ships alongside it in the ffmpeg builds we use.
		if !built[ffmpegEncoder[enc][CodecH264]] {
			continue
		}
		switch enc {
		case EncoderQSV, EncoderVAAPI:
			if hasDRI {
				avail = append(avail, enc)
			}
		case EncoderNVENC:
			if hasNvidia {
				avail = append(avail, enc)
			}
		}
	}

	availSet := make(map[string]bool, len(avail))
	for _, e := range avail {
		availSet[e] = true
	}
	selected := EncoderSoftware
	for _, pref := range preference {
		if availSet[pref] {
			selected = pref
			break
		}
	}
	return Capabilities{Available: avail, Selected: selected}
}

func builtEncoders(ctx context.Context, bin string) map[string]bool {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, bin, "-hide_banner", "-encoders").Output()
	if err != nil {
		return nil
	}
	set := make(map[string]bool)
	for _, byCodec := range ffmpegEncoder {
		for _, name := range byCodec {
			if strings.Contains(string(out), name) {
				set[name] = true
			}
		}
	}
	return set
}

func deviceExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func onPath(bin string) bool {
	_, err := exec.LookPath(bin)
	return err == nil
}
