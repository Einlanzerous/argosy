package mediatool

import "testing"

func TestParseProbe(t *testing.T) {
	sample := []byte(`{
		"streams": [
			{"codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080},
			{"codec_type": "audio", "codec_name": "aac", "channels": 6}
		],
		"format": {"format_name": "matroska,webm", "duration": "1380.5", "bit_rate": "4500000"}
	}`)

	p, err := parseProbe(sample)
	if err != nil {
		t.Fatalf("parseProbe: %v", err)
	}
	if p.Container != "matroska,webm" {
		t.Errorf("container = %q, want matroska,webm", p.Container)
	}
	if p.DurationSeconds != 1380.5 {
		t.Errorf("duration = %v, want 1380.5", p.DurationSeconds)
	}
	if len(p.Raw) == 0 {
		t.Error("expected raw json to be retained")
	}
}

func TestParseProbeMissingDuration(t *testing.T) {
	p, err := parseProbe([]byte(`{"format": {"format_name": "mov,mp4"}}`))
	if err != nil {
		t.Fatalf("parseProbe: %v", err)
	}
	if p.DurationSeconds != 0 {
		t.Errorf("duration = %v, want 0", p.DurationSeconds)
	}
}
