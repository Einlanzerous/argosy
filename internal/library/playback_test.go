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
		highBitDepth   bool
		height         int
		wantMethod     string
		wantCodec      string
		wantTransAudio bool
	}{
		// H.264 video is always copied; audio decides whether it's a clean remux
		// or a copy-video/transcode-audio.
		{"h264+aac remux", "h264", "aac", false, false, 1080, methodRemux, transcode.CodecH264, false},
		{"h264+ac3 copy-video", "h264", "ac3", false, false, 1080, methodRemux, transcode.CodecH264, true},
		// HEVC: only copyable when the client negotiated it → true 4K passthrough.
		{"hevc no-client transcodes to h264", "hevc", "aac", false, false, 2160, methodTranscode, transcode.CodecH264, false},
		{"hevc+truehd client copies video, transcodes audio", "hevc", "truehd", true, false, 2160, methodRemux, transcode.CodecHEVC, true},
		{"hevc+aac client clean copy", "hevc", "aac", true, false, 2160, methodRemux, transcode.CodecHEVC, false},
		// Re-encode path (mpeg2 isn't browser-playable): HEVC output only for
		// >1080p capable clients, H.264 otherwise.
		{"mpeg2 4k client → hevc encode", "mpeg2video", "aac", true, false, 2160, methodTranscode, transcode.CodecHEVC, false},
		{"mpeg2 1080 client → h264 encode", "mpeg2video", "aac", true, false, 1080, methodTranscode, transcode.CodecH264, false},
		{"mpeg2 4k no-client → h264 encode", "mpeg2video", "aac", false, false, 2160, methodTranscode, transcode.CodecH264, false},
		// High-bit-depth (10-bit) H.264/HEVC is never copied — re-encode to 8-bit
		// so clients hardware-decode it instead of stuttering (ARGY-150). Target
		// codec still follows the height/HEVC-client rule.
		{"hevc 10-bit 1080 client → h264 encode", "hevc", "aac", true, true, 1080, methodTranscode, transcode.CodecH264, false},
		{"hevc 10-bit 4k client → hevc encode (8-bit)", "hevc", "aac", true, true, 2160, methodTranscode, transcode.CodecHEVC, false},
		{"h264 10-bit client → h264 encode", "h264", "aac", true, true, 1080, methodTranscode, transcode.CodecH264, false},
		// VP9 10-bit stays a copy — broadly hardware-decoded, not part of the gate.
		{"vp9 10-bit remux", "vp9", "opus", false, true, 2160, methodRemux, transcode.CodecH264, false},
	}
	for _, c := range cases {
		p := planPlayback(c.video, c.audio, c.clientHEVC, c.highBitDepth, c.height)
		if p.method != c.wantMethod || p.videoCodec != c.wantCodec || p.transcodeAudio != c.wantTransAudio {
			t.Errorf("%s: planPlayback(%q,%q,hevc=%v,10bit=%v,%d) = {%s %s audio=%v}, want {%s %s audio=%v}",
				c.name, c.video, c.audio, c.clientHEVC, c.highBitDepth, c.height,
				p.method, p.videoCodec, p.transcodeAudio, c.wantMethod, c.wantCodec, c.wantTransAudio)
		}
	}
}

func TestHighBitDepthFromTechnical(t *testing.T) {
	cases := []struct {
		name string
		raw  string
		want bool
	}{
		{"10-bit hevc (24)", `{"streams":[{"codec_type":"video","codec_name":"hevc","profile":"Main 10","pix_fmt":"yuv420p10le"}]}`, true},
		{"8-bit hevc (peaky)", `{"streams":[{"codec_type":"video","codec_name":"hevc","profile":"Main","pix_fmt":"yuv420p"}]}`, false},
		{"8-bit h264", `{"streams":[{"codec_type":"video","codec_name":"h264","profile":"High","pix_fmt":"yuv420p"}]}`, false},
		{"10-bit via profile only", `{"streams":[{"codec_type":"video","codec_name":"h264","profile":"High 10","pix_fmt":""}]}`, true},
		{"p010 pix_fmt", `{"streams":[{"codec_type":"video","pix_fmt":"p010le"}]}`, true},
		{"audio stream ignored", `{"streams":[{"codec_type":"audio","pix_fmt":"yuv420p10le"},{"codec_type":"video","pix_fmt":"yuv420p"}]}`, false},
		{"empty", ``, false},
	}
	for _, c := range cases {
		if got := highBitDepthFromTechnical([]byte(c.raw)); got != c.want {
			t.Errorf("%s: highBitDepthFromTechnical = %v, want %v", c.name, got, c.want)
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

func TestAudioTracksFromTechnical(t *testing.T) {
	// Two audio streams (English dub tagged default + Japanese), interleaved with
	// video/subtitle streams. Audio index is relative to audio streams, not the
	// absolute ffprobe stream index; ISO 639-2 tags normalize to short codes.
	raw := []byte(`{"streams":[
		{"codec_type":"video","codec_name":"h264"},
		{"codec_type":"audio","codec_name":"aac","tags":{"language":"eng"},"disposition":{"default":1}},
		{"codec_type":"audio","codec_name":"aac","tags":{"language":"jpn","title":"Original"}},
		{"codec_type":"subtitle","codec_name":"subrip"}
	]}`)
	got := audioTracksFromTechnical(raw)
	want := []transcode.AudioTrack{
		{Index: 0, Language: "en", Default: true},
		{Index: 1, Language: "ja"},
	}
	if len(got) != len(want) {
		t.Fatalf("got %d tracks, want %d: %+v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("track %d = %+v, want %+v", i, got[i], want[i])
		}
	}

	// A single audio stream still enumerates (the builders decide single vs
	// multi); no audio streams and empty input both yield nothing.
	if one := audioTracksFromTechnical([]byte(`{"streams":[{"codec_type":"audio","codec_name":"aac"}]}`)); len(one) != 1 {
		t.Errorf("single audio stream = %d tracks, want 1", len(one))
	}
	if none := audioTracksFromTechnical([]byte(`{"streams":[{"codec_type":"video"}]}`)); len(none) != 0 {
		t.Errorf("no audio streams = %d tracks, want 0", len(none))
	}
	if nilTracks := audioTracksFromTechnical(nil); nilTracks != nil {
		t.Errorf("nil technical = %+v, want nil", nilTracks)
	}
}
