package library

import "testing"

func TestDecideDirectPlay(t *testing.T) {
	cases := []struct {
		ext, video, audio string
		want              bool
	}{
		{".mp4", "h264", "aac", true},
		{".webm", "vp9", "opus", true},
		{".m4v", "h264", "mp3", true},
		{".mkv", "h264", "aac", false}, // container browsers won't play
		{".avi", "mpeg4", "mp3", false},
		{".mp4", "hevc", "aac", false}, // codec needs transcoding
		{".mp4", "h264", "ac3", false}, // audio needs transcoding
		{".mp4", "", "", true},         // unknown codecs in a friendly container: optimistic
	}
	for _, c := range cases {
		got, reason := decideDirectPlay(c.ext, c.video, c.audio)
		if got != c.want {
			t.Errorf("decideDirectPlay(%q,%q,%q) = %v (%q), want %v", c.ext, c.video, c.audio, got, reason, c.want)
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
