package transcode

import (
	"context"
	"os/exec"
	"slices"
	"strings"
	"testing"
)

// TestProbeArgsUsesTheBackendsOwnPipeline is the guard on the probe's whole
// premise (ARGY-183): it must exercise the same arguments playback will, or it
// can pass on a backend that then fails at the start of every session. If
// vaapiEncoder grows a hardware init or changes its upload filter, the probe
// has to inherit it — which it does only because it calls the encoder rather
// than hand-writing a command.
func TestProbeArgsUsesTheBackendsOwnPipeline(t *testing.T) {
	for _, tc := range []struct {
		name  string
		enc   videoEncoder
		codec string
		want  []string
	}{
		{
			name: "vaapi carries the device init and the hwupload",
			enc:  vaapiEncoder{device: "/dev/dri/renderD129"}, codec: CodecH264,
			want: []string{"-vaapi_device /dev/dri/renderD129", "hwupload", "h264_vaapi"},
		},
		{
			name: "vaapi hevc probes the hevc encoder", enc: vaapiEncoder{}, codec: CodecHEVC,
			want: []string{"hevc_vaapi", "-vaapi_device"},
		},
		{
			name: "qsv has no device init but pins nv12", enc: qsvEncoder{}, codec: CodecH264,
			want: []string{"format=nv12", "h264_qsv"},
		},
		{
			name: "software needs no hardware anything", enc: softwareEncoder{}, codec: CodecH264,
			want: []string{"libx264"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := strings.Join(probeArgs(tc.enc, tc.codec), " ")
			for _, want := range tc.want {
				if !strings.Contains(got, want) {
					t.Errorf("probeArgs = %q, missing %q", got, want)
				}
			}
			// Rate control must be exercised too: a VAAPI driver without VBR
			// accepts a bare CQP encode and rejects -b:v/-maxrate/-bufsize, so
			// omitting these would pass a backend whose every rung then fails.
			r := probeRung(tc.codec)
			for _, want := range []string{"-b:v " + r.videoBitrate, "-maxrate " + r.maxRate, "-bufsize " + r.bufSize} {
				if !strings.Contains(got, want) {
					t.Errorf("probeArgs = %q, missing rate control %q", got, want)
				}
			}
			// One frame, discarded: a probe that wrote a file or ran for the
			// full duration would add startup latency for no extra signal.
			if !strings.Contains(got, "-frames:v 1") || !strings.Contains(got, "-f null") {
				t.Errorf("probeArgs = %q, want a one-frame encode to null", got)
			}
		})
	}
}

// TestProbeRungNeverUpscales keeps the trial encode shaped like a real session:
// the probe source is 720p, so every rung it picks must scale down.
func TestProbeRungNeverUpscales(t *testing.T) {
	for _, codec := range []string{CodecH264, CodecHEVC} {
		if h := probeRung(codec).height; h > 720 {
			t.Errorf("probeRung(%q).height = %d, want <= the 720p probe source", codec, h)
		}
	}
}

// TestVAAPICandidatesHonoursAPin covers the ARGOSY_VAAPI_DEVICE path: an
// operator naming a GPU means "use this one", not "start here and wander off
// to another card if it doesn't answer".
func TestVAAPICandidatesHonoursAPin(t *testing.T) {
	origDev, origPinned := VAAPIDevice, vaapiPinned
	t.Cleanup(func() { VAAPIDevice, vaapiPinned = origDev, origPinned })

	PinVAAPIDevice("/dev/dri/renderD129")
	got := vaapiCandidates()
	if len(got) != 1 || got[0] != "/dev/dri/renderD129" {
		t.Errorf("vaapiCandidates() = %v, want exactly the pinned device", got)
	}
}

// TestVAAPICandidatesAreOrdered checks the unpinned search order. Sorting puts
// renderD128 first, which is the iGPU on hosts that have one — deliberate, so
// transcode stays off a discrete card another workload may be using.
func TestVAAPICandidatesAreOrdered(t *testing.T) {
	origDev, origPinned := VAAPIDevice, vaapiPinned
	t.Cleanup(func() { VAAPIDevice, vaapiPinned = origDev, origPinned })
	vaapiPinned = false

	got := vaapiCandidates()
	if !slices.IsSorted(got) {
		t.Errorf("vaapiCandidates() = %v, want sorted so the first-enumerated GPU is tried first", got)
	}
	for _, dev := range got {
		if !strings.HasPrefix(dev, "/dev/dri/renderD") {
			t.Errorf("vaapiCandidates() = %v, want only DRM render nodes", got)
		}
	}
}

// TestProbeRejectsBackendsThatCannotEncode is the regression guard for the bug
// this replaced: availability used to mean "ffmpeg was built with the encoder
// and /dev/dri exists", which is true of h264_qsv on hardware whose runtime
// can't open a session. Probing against a binary that always fails must yield
// software alone — if a hardware backend can survive a failing encode, the
// probe is back to trusting the encoder list.
func TestProbeRejectsBackendsThatCannotEncode(t *testing.T) {
	if _, err := exec.LookPath("false"); err != nil {
		t.Skip("no /bin/false to stand in for a failing ffmpeg")
	}
	// "false" exits non-zero for both -encoders and every trial encode, so no
	// backend can be built *or* proven. Probe must still return a usable floor.
	caps := Probe(context.Background(), "false", nil)
	if caps.Selected != EncoderSoftware {
		t.Errorf("Selected = %q, want software when nothing encodes", caps.Selected)
	}
	if !slices.Equal(caps.Available, []string{EncoderSoftware}) {
		t.Errorf("Available = %v, want [software] when nothing encodes", caps.Available)
	}
	if caps.Device != "" {
		t.Errorf("Device = %q, want empty when no hardware was selected", caps.Device)
	}
}

// TestProbeMatchesReality runs the real probe against the real ffmpeg and
// asserts the part CI cannot: that whatever it reports available actually
// encodes. Skipped without ffmpeg, so it stays hermetic — but on a GPU host it
// is the only check that the selected backend is not about to fail every
// session and fall back to software.
func TestProbeMatchesReality(t *testing.T) {
	if testing.Short() {
		t.Skip("integration test needs ffmpeg")
	}
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not on PATH")
	}
	caps := Probe(context.Background(), ffmpeg, nil)
	t.Logf("available=%v selected=%q device=%q", caps.Available, caps.Selected, caps.Device)

	if !slices.Contains(caps.Available, EncoderSoftware) {
		t.Errorf("Available = %v, want software as the floor", caps.Available)
	}
	if !slices.Contains(caps.Available, caps.Selected) {
		t.Errorf("Selected %q is not in Available %v", caps.Selected, caps.Available)
	}
	// Everything offered must encode *both* codecs — planPlayback routes >1080p
	// to HEVC, so an H.264-only pass would still fail every 4K session.
	for _, enc := range caps.Available {
		if !encodeWorks(context.Background(), ffmpeg, encoderFor(enc), []string{CodecH264, CodecHEVC}) {
			t.Errorf("Probe offered %q but a trial encode through it fails", enc)
		}
	}
	if caps.Selected == EncoderVAAPI && caps.Device == "" {
		t.Error("VAAPI selected but no render node reported")
	}
}
