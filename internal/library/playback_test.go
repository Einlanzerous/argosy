package library

import (
	"strings"
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
		clientHEVCHW   bool
		highBitDepth   bool
		height         int
		wantMethod     string
		wantCodec      string
		wantTransAudio bool
	}{
		// H.264 video is always copied; audio decides whether it's a clean remux
		// or a copy-video/transcode-audio.
		{"h264+aac remux", "h264", "aac", false, false, false, 1080, methodRemux, transcode.CodecH264, false},
		{"h264+ac3 copy-video", "h264", "ac3", false, false, false, 1080, methodRemux, transcode.CodecH264, true},
		// HEVC: only copyable when the client negotiated it → true 4K passthrough.
		{"hevc no-client transcodes to h264", "hevc", "aac", false, false, false, 2160, methodTranscode, transcode.CodecH264, false},
		{"hevc+truehd client copies video, transcodes audio", "hevc", "truehd", true, false, false, 2160, methodRemux, transcode.CodecHEVC, true},
		{"hevc+aac client clean copy", "hevc", "aac", true, false, false, 2160, methodRemux, transcode.CodecHEVC, false},
		// Re-encode path (mpeg2 isn't browser-playable): HEVC output only for
		// >1080p capable clients, H.264 otherwise.
		{"mpeg2 4k client → hevc encode", "mpeg2video", "aac", true, false, false, 2160, methodTranscode, transcode.CodecHEVC, false},
		{"mpeg2 1080 client → h264 encode", "mpeg2video", "aac", true, false, false, 1080, methodTranscode, transcode.CodecH264, false},
		{"mpeg2 4k no-client → h264 encode", "mpeg2video", "aac", false, false, false, 2160, methodTranscode, transcode.CodecH264, false},
		// High-bit-depth (10-bit) H.264/HEVC is never copied — re-encode to 8-bit
		// so clients hardware-decode it instead of stuttering (ARGY-150). Target
		// codec still follows the height/HEVC-client rule.
		{"hevc 10-bit 1080 client → h264 encode", "hevc", "aac", true, false, true, 1080, methodTranscode, transcode.CodecH264, false},
		{"hevc 10-bit 4k client → hevc encode (8-bit)", "hevc", "aac", true, false, true, 2160, methodTranscode, transcode.CodecHEVC, false},
		{"h264 10-bit client → h264 encode", "h264", "aac", true, false, true, 1080, methodTranscode, transcode.CodecH264, false},
		// A client reporting hardware decode keeps 10-bit and HDR *above 1080p*,
		// the one case with positive evidence (ARGY-178).
		{"hevc 10-bit 4k hw client copies", "hevc", "aac", true, true, true, 2160, methodRemux, transcode.CodecHEVC, false},
		// ...but not at or below 1080p. decodingInfo reports smooth/powerEfficient
		// by default until the device has recorded stats, so a "hardware" answer
		// can mean "never played one" — and 1080p 10-bit is the class the
		// unexplained ARGY-150 stutter belongs to. It keeps re-encoding.
		{"hevc 10-bit 1080 hw client still encodes", "hevc", "aac", true, true, true, 1080, methodTranscode, transcode.CodecH264, false},
		{"hevc 10-bit 720 hw client still encodes", "hevc", "aac", true, true, true, 720, methodTranscode, transcode.CodecH264, false},
		{"hevc 10-bit hw client still transcodes odd audio", "hevc", "truehd", true, true, true, 2160, methodRemux, transcode.CodecHEVC, true},
		// The hardware answer is about HEVC; it must not unblock 10-bit H.264,
		// where browser High 10 support is far thinner and the probe says nothing.
		{"h264 10-bit hw-hevc client still encodes", "h264", "aac", true, true, true, 1080, methodTranscode, transcode.CodecH264, false},
		// Hardware without the HEVC negotiation is meaningless — there is no copy
		// path to take.
		{"hevc 10-bit hw but no hevc client", "hevc", "aac", false, true, true, 2160, methodTranscode, transcode.CodecH264, false},
		// VP9 10-bit stays a copy — broadly hardware-decoded, not part of the gate.
		{"vp9 10-bit remux", "vp9", "opus", false, false, true, 2160, methodRemux, transcode.CodecH264, false},
	}
	for _, c := range cases {
		// Burn-in off throughout: this table is about codec and bit-depth
		// negotiation. TestPlanPlaybackBurnIn covers the override.
		p := planPlayback(c.video, c.audio, c.clientHEVC, c.clientHEVCHW, c.highBitDepth, false, c.height)
		if p.method != c.wantMethod || p.videoCodec != c.wantCodec || p.transcodeAudio != c.wantTransAudio {
			t.Errorf("%s: planPlayback(%q,%q,hevc=%v,hw=%v,10bit=%v,%d) = {%s %s audio=%v}, want {%s %s audio=%v}",
				c.name, c.video, c.audio, c.clientHEVC, c.clientHEVCHW, c.highBitDepth, c.height,
				p.method, p.videoCodec, p.transcodeAudio, c.wantMethod, c.wantCodec, c.wantTransAudio)
		}
	}
}

// TestPlanPlaybackBurnIn covers the ARGY-59 override: an image subtitle is drawn
// into the frames, so every case that would otherwise have been copied has to
// re-encode instead. These are exactly the rows of the table above that came
// back methodRemux — including the true-4K HEVC passthrough, which is the most
// expensive thing burn-in gives up and the one most worth stating outright.
func TestPlanPlaybackBurnIn(t *testing.T) {
	cases := []struct {
		name         string
		video, audio string
		clientHEVC   bool
		clientHEVCHW bool
		highBitDepth bool
		height       int
		wantCodec    string
	}{
		{"h264+aac, would have remuxed", "h264", "aac", false, false, false, 1080, transcode.CodecH264},
		{"hevc 4k client, would have copied at native res", "hevc", "aac", true, false, false, 2160, transcode.CodecHEVC},
		{"hevc 10-bit 4k hw client, would have kept HDR", "hevc", "aac", true, true, true, 2160, transcode.CodecHEVC},
		{"vp9 10-bit, would have remuxed", "vp9", "opus", false, false, true, 2160, transcode.CodecH264},
		// A source that was already being re-encoded is unaffected in method; the
		// burn-in just rides along on the encode it was getting anyway.
		{"mpeg2 4k client already encoding", "mpeg2video", "aac", true, false, false, 2160, transcode.CodecHEVC},
	}
	for _, c := range cases {
		p := planPlayback(c.video, c.audio, c.clientHEVC, c.clientHEVCHW, c.highBitDepth, true, c.height)
		if p.method != methodTranscode {
			t.Errorf("%s: method = %q, want %q (a burned-in subtitle rewrites the picture, so nothing can be copied)",
				c.name, p.method, methodTranscode)
		}
		if p.videoCodec != c.wantCodec {
			t.Errorf("%s: codec = %q, want %q", c.name, p.videoCodec, c.wantCodec)
		}
		if !strings.Contains(p.reason, "burning in") {
			t.Errorf("%s: reason = %q, want it to say why the copy was refused", c.name, p.reason)
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
