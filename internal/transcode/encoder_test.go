package transcode

import (
	"strings"
	"testing"
)

func TestEncoderForResolution(t *testing.T) {
	// Implemented backends resolve to themselves; unknown names degrade to
	// software rather than failing.
	cases := map[string]string{
		EncoderSoftware: EncoderSoftware,
		EncoderQSV:      EncoderQSV,   // wired in ARGY-30
		EncoderVAAPI:    EncoderVAAPI, // wired in ARGY-61
		EncoderNVENC:    EncoderNVENC, // wired in ARGY-61
		"nonsense":      EncoderSoftware,
		"":              EncoderSoftware,
	}
	for name, want := range cases {
		if got := ResolvedEncoder(name); got != want {
			t.Errorf("ResolvedEncoder(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestVAAPIEncoderPieces(t *testing.T) {
	enc := vaapiEncoder{}
	// VAAPI needs the device initialized before the input and frames uploaded to
	// a GPU surface (unlike QSV's internal upload).
	if got := strings.Join(enc.globalArgs(), " "); !strings.Contains(got, "-vaapi_device") {
		t.Errorf("vaapi globalArgs = %q, want -vaapi_device", got)
	}
	if got := enc.scale(720); got != "scale=-2:720,format=nv12,hwupload" {
		t.Errorf("vaapi scale(720) = %q, want CPU scale + hwupload", got)
	}
	if got := strings.Join(enc.videoCodec(CodecH264), " "); !strings.Contains(got, "h264_vaapi") {
		t.Errorf("vaapi videoCodec(h264) = %q, want h264_vaapi", got)
	}
	if got := strings.Join(enc.videoCodec(CodecHEVC), " "); !strings.Contains(got, "hevc_vaapi") {
		t.Errorf("vaapi videoCodec(hevc) = %q, want hevc_vaapi", got)
	}
}

func TestNVENCEncoderPieces(t *testing.T) {
	enc := nvencEncoder{}
	// Encode-only like QSV: no hwaccel init, internal frame upload.
	if enc.globalArgs() != nil {
		t.Errorf("nvenc globalArgs = %v, want nil (encode-only)", enc.globalArgs())
	}
	if got := enc.scale(720); got != "scale=-2:720,format=nv12" {
		t.Errorf("nvenc scale(720) = %q", got)
	}
	if got := strings.Join(enc.videoCodec(CodecHEVC), " "); !strings.Contains(got, "hevc_nvenc") {
		t.Errorf("nvenc videoCodec(hevc) = %q, want hevc_nvenc", got)
	}
}

func TestQSVEncoderPieces(t *testing.T) {
	enc := qsvEncoder{}
	// Encode-only: no hwaccel init, CPU/software scale shared with software, and
	// only the codec differs (h264_qsv).
	if enc.globalArgs() != nil {
		t.Errorf("qsv globalArgs = %v, want nil (encode-only, CPU decode)", enc.globalArgs())
	}
	if got := enc.scale(720); got != "scale=-2:720,format=nv12" {
		t.Errorf("qsv scale(720) = %q, want nv12 conversion for 8-bit h264_qsv input", got)
	}
	if got := strings.Join(enc.videoCodec(CodecH264), " "); !strings.Contains(got, "h264_qsv") {
		t.Errorf("qsv videoCodec(h264) = %q, want h264_qsv", got)
	}
	hevc := strings.Join(enc.videoCodec(CodecHEVC), " ")
	if !strings.Contains(hevc, "hevc_qsv") || !strings.Contains(hevc, "-tag:v hvc1") {
		t.Errorf("qsv videoCodec(hevc) = %q, want hevc_qsv + hvc1 tag", hevc)
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
	if got := enc.scale(720); got != "scale=-2:720,format=nv12" {
		t.Errorf("scale(720) = %q", got)
	}
	if got := strings.Join(enc.videoCodec(CodecH264), " "); !strings.Contains(got, "libx264") {
		t.Errorf("videoCodec(h264) = %q, want libx264", got)
	}
	if got := strings.Join(enc.videoCodec(CodecHEVC), " "); !strings.Contains(got, "libx265") {
		t.Errorf("videoCodec(hevc) = %q, want libx265", got)
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
