package transcode

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
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
//
// VAAPI outranks QSV. ffmpeg 7 dropped libmfx and reaches Intel GPUs only
// through the VPL runtime, which supports Gen12+ silicon, so on an older iGPU
// QSV is compiled in but cannot open a session while VAAPI drives the same chip
// fine (ARGY-183). On Gen12+ hardware both work and Probe offers both, so the
// order costs nothing there.
var DefaultPreference = []string{EncoderNVENC, EncoderVAAPI, EncoderQSV, EncoderSoftware}

// probeTimeout bounds one backend's trial encode. Generous: it only has to
// cover driver initialization on a cold GPU, and a backend that isn't there
// fails in milliseconds rather than waiting this out.
const probeTimeout = 15 * time.Second

// Capabilities reports which encoders this host supports and which one was
// selected by the configured preference order. It is surfaced to The Helm and
// drives encoder selection (the hardware paths are wired in ARGY-30).
type Capabilities struct {
	Available []string `json:"available"`
	Selected  string   `json:"selected"`
	// Device is the render node the selected backend resolved to, or empty for
	// software. Reported for logging — it is the one piece of the probe's
	// reasoning that isn't obvious from Available.
	Device string `json:"-"`
}

// Probe detects available encoders and selects the first available one in
// preference order. Software is always available as the floor.
//
// Availability means a real one-frame encode succeeded through that backend's
// own argument shape — not merely that ffmpeg was built with the encoder. The
// distinction is the whole point (ARGY-183): `h264_qsv` is compiled into every
// Debian ffmpeg, and /dev/dri exists on any box with a GPU, so the old
// built-plus-device test called QSV available on hardware whose runtime cannot
// open a session. That selected a backend which failed at the start of every
// session and fell back to software each time — slower than choosing software
// outright, and silent. CI cannot see any of this; it has no GPU.
//
// The cost is a few hundred milliseconds of ffmpeg invocations at startup, once.
func Probe(ctx context.Context, bin string, preference []string) Capabilities {
	if bin == "" {
		bin = "ffmpeg"
	}
	if len(preference) == 0 {
		preference = DefaultPreference
	}
	built := builtEncoders(ctx, bin)

	avail := []string{EncoderSoftware} // libx264 ships with every ffmpeg build we use
	device := ""
	for _, enc := range []string{EncoderQSV, EncoderVAAPI, EncoderNVENC} {
		// A backend counts as available when its H.264 encoder is built and a
		// trial encode through it succeeds; the HEVC variant ships alongside it
		// in the ffmpeg builds we use.
		if !built[ffmpegEncoder[enc][CodecH264]] {
			continue
		}
		dev, ok := hardwareWorks(ctx, bin, enc)
		if !ok {
			continue
		}
		avail = append(avail, enc)
		if enc == EncoderVAAPI {
			device = dev
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
	if selected != EncoderVAAPI {
		device = ""
	}
	return Capabilities{Available: avail, Selected: selected, Device: device}
}

// hardwareWorks reports whether enc can actually encode on this host, and for
// VAAPI which render node it settled on. VAAPI is the one backend with a choice
// to make: a box can carry several GPUs, and only some of them encode.
func hardwareWorks(ctx context.Context, bin, enc string) (string, bool) {
	switch enc {
	case EncoderVAAPI:
		for _, dev := range vaapiCandidates() {
			if encodeWorks(ctx, bin, vaapiEncoder{device: dev}) {
				// Commit the winner so the transcode path uses the node the
				// probe proved, not the default it started from.
				VAAPIDevice = dev
				return dev, true
			}
		}
		return "", false
	case EncoderNVENC:
		if !deviceExists("/dev/nvidia0") && !onPath("nvidia-smi") {
			return "", false
		}
		return "", encodeWorks(ctx, bin, encoderFor(enc))
	default:
		if !deviceExists("/dev/dri") {
			return "", false
		}
		return "", encodeWorks(ctx, bin, encoderFor(enc))
	}
}

// vaapiCandidates lists the DRM render nodes to try, in order. Sorted, so
// renderD128 — conventionally the first GPU the kernel enumerates, and the
// Intel iGPU on this box — is tried before a discrete card. That ordering is
// deliberate rather than incidental: preferring the iGPU keeps playback off
// whatever else is using the discrete GPU (here, an LLM on ROCm), so the two
// workloads don't contend. A host that wants the other card sets
// ARGOSY_VAAPI_DEVICE, which pins the choice and skips the search entirely.
func vaapiCandidates() []string {
	if vaapiPinned {
		return []string{VAAPIDevice}
	}
	nodes, err := filepath.Glob("/dev/dri/renderD*")
	if err != nil {
		return nil
	}
	sort.Strings(nodes)
	return nodes
}

// probeArgs builds the trial encode for enc: one frame of black through the
// backend's own globalArgs/scale/videoCodec. Deliberately the real pieces
// rather than a hand-written command — a probe that exercises a different
// pipeline than playback can pass while playback fails, which is the failure
// mode this replaced.
func probeArgs(enc videoEncoder) []string {
	args := []string{"-nostdin", "-hide_banner", "-loglevel", "error"}
	args = append(args, enc.globalArgs()...)
	args = append(args, "-f", "lavfi", "-i", "color=c=black:s=320x240:r=25:d=1")
	args = append(args, "-vf", enc.scale(240))
	args = append(args, enc.videoCodec(CodecH264)...)
	return append(args, "-frames:v", "1", "-f", "null", "-")
}

// encodeWorks runs probeArgs and reports whether ffmpeg exited cleanly.
func encodeWorks(ctx context.Context, bin string, enc videoEncoder) bool {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()
	return exec.CommandContext(ctx, bin, probeArgs(enc)...).Run() == nil
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
