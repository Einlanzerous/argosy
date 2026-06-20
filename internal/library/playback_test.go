package library

import (
	"testing"

	"github.com/Einlanzerous/argosy/internal/transcode"
)

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

func TestPlanPlayback(t *testing.T) {
	cases := []struct {
		name           string
		video, audio   string
		clientHEVC     bool
		height         int
		wantMethod     string
		wantCodec      string
		wantTransAudio bool
	}{
		// H.264 video is always copied; audio decides whether it's a clean remux
		// or a copy-video/transcode-audio.
		{"h264+aac remux", "h264", "aac", false, 1080, methodRemux, transcode.CodecH264, false},
		{"h264+ac3 copy-video", "h264", "ac3", false, 1080, methodRemux, transcode.CodecH264, true},
		// HEVC: only copyable when the client negotiated it → true 4K passthrough.
		{"hevc no-client transcodes to h264", "hevc", "aac", false, 2160, methodTranscode, transcode.CodecH264, false},
		{"hevc+truehd client copies video, transcodes audio", "hevc", "truehd", true, 2160, methodRemux, transcode.CodecHEVC, true},
		{"hevc+aac client clean copy", "hevc", "aac", true, 2160, methodRemux, transcode.CodecHEVC, false},
		// Re-encode path (mpeg2 isn't browser-playable): HEVC output only for
		// >1080p capable clients, H.264 otherwise.
		{"mpeg2 4k client → hevc encode", "mpeg2video", "aac", true, 2160, methodTranscode, transcode.CodecHEVC, false},
		{"mpeg2 1080 client → h264 encode", "mpeg2video", "aac", true, 1080, methodTranscode, transcode.CodecH264, false},
		{"mpeg2 4k no-client → h264 encode", "mpeg2video", "aac", false, 2160, methodTranscode, transcode.CodecH264, false},
	}
	for _, c := range cases {
		p := planPlayback(c.video, c.audio, c.clientHEVC, c.height)
		if p.method != c.wantMethod || p.videoCodec != c.wantCodec || p.transcodeAudio != c.wantTransAudio {
			t.Errorf("%s: planPlayback(%q,%q,hevc=%v,%d) = {%s %s audio=%v}, want {%s %s audio=%v}",
				c.name, c.video, c.audio, c.clientHEVC, c.height,
				p.method, p.videoCodec, p.transcodeAudio, c.wantMethod, c.wantCodec, c.wantTransAudio)
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
