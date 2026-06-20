package transcode

import (
	"strings"
	"testing"
)

func TestEncoderForFallsBackToSoftware(t *testing.T) {
	// Software resolves to itself; un-implemented hardware backends (and unknown
	// names) degrade to software rather than failing.
	for _, name := range []string{EncoderSoftware, EncoderQSV, EncoderVAAPI, EncoderNVENC, "nonsense", ""} {
		if got := ResolvedEncoder(name); got != EncoderSoftware {
			t.Errorf("ResolvedEncoder(%q) = %q, want %q (until the backend is wired)", name, got, EncoderSoftware)
		}
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
