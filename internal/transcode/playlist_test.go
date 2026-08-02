package transcode

import (
	"strconv"
	"strings"
	"testing"
)

func TestNormalizePlaylistHEVCConstraintByte(t *testing.T) {
	for _, tc := range []struct {
		name, in, want string
	}{
		{
			name: "master with hevc video and aac audio",
			in:   `#EXT-X-STREAM-INF:BANDWIDTH=8940800,RESOLUTION=1920x1080,CODECS="hvc1.1.4.L120.B01,mp4a.40.2",AUDIO="group_aud"`,
			want: `#EXT-X-STREAM-INF:BANDWIDTH=8940800,RESOLUTION=1920x1080,CODECS="hvc1.1.4.L120.B0,mp4a.40.2",AUDIO="group_aud"`,
		},
		{
			name: "main 10 at a different level",
			in:   `CODECS="hvc1.2.4.L153.B01"`,
			want: `CODECS="hvc1.2.4.L153.B0"`,
		},
		{
			name: "hev1 sample entry",
			in:   `CODECS="hev1.1.4.L93.B01,mp4a.40.2"`,
			want: `CODECS="hev1.1.4.L93.B0,mp4a.40.2"`,
		},
		{
			name: "ladder: every variant is rewritten",
			in: "#EXT-X-STREAM-INF:CODECS=\"hvc1.1.4.L120.B01\"\nstream_0.m3u8\n" +
				"#EXT-X-STREAM-INF:CODECS=\"hvc1.1.4.L93.B01\"\nstream_1.m3u8\n",
			want: "#EXT-X-STREAM-INF:CODECS=\"hvc1.1.4.L120.B0\"\nstream_0.m3u8\n" +
				"#EXT-X-STREAM-INF:CODECS=\"hvc1.1.4.L93.B0\"\nstream_1.m3u8\n",
		},
		{
			name: "h264 is left alone",
			in:   `CODECS="avc1.640028,mp4a.40.2"`,
			want: `CODECS="avc1.640028,mp4a.40.2"`,
		},
		{
			name: "single-audio media playlist declares no codecs",
			in:   "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4.000,\nstream_00000.m4s\n",
			want: "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4.000,\nstream_00000.m4s\n",
		},
		{
			name: "an already-valid constraint byte is untouched",
			in:   `CODECS="hvc1.1.4.L120.B0"`,
			want: `CODECS="hvc1.1.4.L120.B0"`,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := string(NormalizePlaylist([]byte(tc.in))); got != tc.want {
				t.Errorf("NormalizePlaylist()\n got %q\nwant %q", got, tc.want)
			}
		})
	}
}

// validHEVCCodecString applies the parse rules a browser's
// MediaSource.isTypeSupported enforces on an HEVC codec string (ISO/IEC
// 14496-15 Annex E): a sample-entry prefix, profile, compatibility flags, tier
// + level, then up to six constraint *bytes*. It is deliberately independent of
// the rewrite under test — a codec string that fails this is one Chrome and
// Firefox both reject, whatever else the manifest looks like.
func validHEVCCodecString(codec string) bool {
	elems := strings.Split(codec, ".")
	if len(elems) < 4 || len(elems) > 10 {
		return false
	}
	if elems[0] != "hvc1" && elems[0] != "hev1" {
		return false
	}
	profile := strings.TrimLeft(elems[1], "ABC")
	if _, err := strconv.ParseUint(profile, 10, 8); err != nil {
		return false
	}
	if _, err := strconv.ParseUint(elems[2], 16, 32); err != nil {
		return false
	}
	if len(elems[3]) < 2 || (elems[3][0] != 'L' && elems[3][0] != 'H') {
		return false
	}
	if _, err := strconv.ParseUint(elems[3][1:], 10, 8); err != nil {
		return false
	}
	// Each remaining element is one byte: at most two hex digits, ≤ 0xFF.
	// ffmpeg's hardcoded "B01" is 0xB01, which is what fails here.
	for _, e := range elems[4:] {
		if len(e) > 2 {
			return false
		}
		if _, err := strconv.ParseUint(e, 16, 8); err != nil {
			return false
		}
	}
	return true
}

func TestValidHEVCCodecString(t *testing.T) {
	for codec, want := range map[string]bool{
		"hvc1.1.4.L120.B0":  true,
		"hvc1.2.4.L153.B0":  true, // what supportsHevc() probes in the web client
		"hev1.1.6.L93.B0":   true,
		"hvc1.1.4.L120":     true, // constraint bytes are optional
		"hvc1.1.4.L120.B01": false,
		"hvc1.1.4.120.B0":   false,
		"avc1.640028":       false,
	} {
		if got := validHEVCCodecString(codec); got != want {
			t.Errorf("validHEVCCodecString(%q) = %v, want %v", codec, got, want)
		}
	}
}
