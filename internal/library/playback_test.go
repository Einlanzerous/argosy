package library

import "testing"

func TestDecide(t *testing.T) {
	cases := []struct {
		ext, video, audio string
		want              string
	}{
		{".mp4", "h264", "aac", methodDirect},
		{".webm", "vp9", "opus", methodDirect},
		{".m4v", "h264", "mp3", methodDirect},
		{".mp4", "", "", methodDirect},       // unknown codecs in a friendly container: optimistic
		{".mkv", "h264", "aac", methodRemux}, // only the container is incompatible → copy
		{".mov", "h264", "aac", methodDirect},
		{".avi", "h264", "mp3", methodRemux},
		{".mkv", "hevc", "aac", methodTranscode}, // video codec needs re-encode
		{".mp4", "hevc", "aac", methodTranscode},
		{".mp4", "h264", "ac3", methodTranscode}, // audio codec needs re-encode
		{".mkv", "h264", "dts", methodTranscode},
	}
	for _, c := range cases {
		got, reason := decide(c.ext, c.video, c.audio)
		if got != c.want {
			t.Errorf("decide(%q,%q,%q) = %v (%q), want %v", c.ext, c.video, c.audio, got, reason, c.want)
		}
	}
}

func TestCodecsFromTechnical(t *testing.T) {
	raw := []byte(`{"streams":[{"codec_type":"video","codec_name":"h264"},{"codec_type":"audio","codec_name":"aac"},{"codec_type":"subtitle","codec_name":"bin_data"}]}`)
	v, a := codecsFromTechnical(raw)
	if v != "h264" || a != "aac" {
		t.Errorf("codecs = (%q,%q), want (h264,aac)", v, a)
	}
	if v, a := codecsFromTechnical(nil); v != "" || a != "" {
		t.Errorf("empty technical = (%q,%q), want empty", v, a)
	}
}
