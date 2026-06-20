package transcode

import (
	"strings"
	"testing"
)

func TestEncoderForResolution(t *testing.T) {
	// Implemented backends resolve to themselves; un-implemented ones (VAAPI/
	// NVENC, ARGY-61) and unknown names degrade to software rather than failing.
	cases := map[string]string{
		EncoderSoftware: EncoderSoftware,
		EncoderQSV:      EncoderQSV, // wired in ARGY-30
		EncoderVAAPI:    EncoderSoftware,
		EncoderNVENC:    EncoderSoftware,
		"nonsense":      EncoderSoftware,
		"":              EncoderSoftware,
	}
	for name, want := range cases {
		if got := ResolvedEncoder(name); got != want {
			t.Errorf("ResolvedEncoder(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestQSVEncoderPieces(t *testing.T) {
	enc := qsvEncoder{}
	// Encode-only: no hwaccel init, CPU/software scale shared with software, and
	// only the codec differs (h264_qsv).
	if enc.globalArgs() != nil {
		t.Errorf("qsv globalArgs = %v, want nil (encode-only, CPU decode)", enc.globalArgs())
	}
	if got := enc.scale(720); got != "scale=-2:720" {
		t.Errorf("qsv scale(720) = %q, want software scale", got)
	}
	if got := strings.Join(enc.videoCodec(), " "); !strings.Contains(got, "h264_qsv") {
		t.Errorf("qsv videoCodec = %q, want h264_qsv", got)
	}
}

func TestIsHardwareEncoder(t *testing.T) {
	if isHardwareEncoder(EncoderSoftware) || isHardwareEncoder("") {
		t.Error("software/empty should not be hardware")
	}
	if !isHardwareEncoder(EncoderQSV) || !isHardwareEncoder(EncoderNVENC) {
		t.Error("qsv/nvenc should be hardware")
	}
}

func TestSoftwareEncoderPieces(t *testing.T) {
	enc := softwareEncoder{}
	if enc.globalArgs() != nil {
		t.Errorf("software globalArgs = %v, want nil (no hwaccel)", enc.globalArgs())
	}
	if got := enc.scale(720); got != "scale=-2:720" {
		t.Errorf("scale(720) = %q", got)
	}
	if got := strings.Join(enc.videoCodec(), " "); !strings.Contains(got, "libx264") {
		t.Errorf("videoCodec = %q, want libx264", got)
	}

	r := rung{videoBitrate: "2800k", maxRate: "3000k", bufSize: "5600k"}
	// Single output: bare specifiers.
	if got := strings.Join(enc.rateControl(-1, r), " "); got != "-b:v 2800k -maxrate 3000k -bufsize 5600k" {
		t.Errorf("rateControl(-1) = %q", got)
	}
	// Ladder output 1: indexed specifiers.
	if got := strings.Join(enc.rateControl(1, r), " "); got != "-b:v:1 2800k -maxrate:v:1 3000k -bufsize:v:1 5600k" {
		t.Errorf("rateControl(1) = %q", got)
	}
}
