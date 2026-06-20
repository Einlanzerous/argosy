package subtitle

import (
	"strings"
	"testing"
)

func TestSRTToVTT(t *testing.T) {
	srt := "1\r\n00:00:01,000 --> 00:00:04,000\r\nHello, world\r\n\r\n" +
		"2\r\n00:00:05,500 --> 00:00:08,250\r\n<i>Second line</i>\r\n"
	var b strings.Builder
	if err := SRTToVTT(strings.NewReader(srt), &b); err != nil {
		t.Fatalf("SRTToVTT: %v", err)
	}
	got := b.String()

	if !strings.HasPrefix(got, "WEBVTT\n\n") {
		t.Errorf("missing WEBVTT header, got:\n%s", got)
	}
	if !strings.Contains(got, "00:00:01.000 --> 00:00:04.000") {
		t.Errorf("cue timing comma not converted to period:\n%s", got)
	}
	// Commas inside dialogue must be left alone.
	if !strings.Contains(got, "Hello, world") {
		t.Errorf("dialogue comma was mangled:\n%s", got)
	}
	// CR must be stripped.
	if strings.Contains(got, "\r") {
		t.Errorf("carriage returns survived conversion")
	}
	if !strings.Contains(got, "<i>Second line</i>") {
		t.Errorf("inline tags dropped:\n%s", got)
	}
}

func TestSRTToVTTStripsBOM(t *testing.T) {
	srt := "\ufeff1\n00:00:01,000 --> 00:00:02,000\nHi\n"
	var b strings.Builder
	if err := SRTToVTT(strings.NewReader(srt), &b); err != nil {
		t.Fatalf("SRTToVTT: %v", err)
	}
	if strings.Contains(b.String(), "\ufeff") {
		t.Errorf("BOM survived conversion: %q", b.String())
	}
}
