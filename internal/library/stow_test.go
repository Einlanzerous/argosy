package library

import (
	"strings"
	"testing"
)

const gib = int64(1) << 30

// TestPlanStow pins the offline decision. The bias here is the opposite of
// planPlayback's: this asks what will certainly play on a device with no network
// to fall back on, not what the best achievable output would be.
func TestPlanStow(t *testing.T) {
	tests := []struct {
		name           string
		ext            string
		video, audio   string
		highBitDepth   bool
		size           int64
		clientHEVC     bool
		clientMatroska bool
		want           string
		reasonHas      string
	}{
		{
			name: "h264 aac mp4 passes through untouched",
			ext:  ".mp4", video: "h264", audio: "aac", size: gib,
			want: stowPassthrough,
		},
		{
			name: "h264 aac mkv passes through for a Matroska-capable client",
			ext:  ".mkv", video: "h264", audio: "aac", size: gib,
			clientMatroska: true, want: stowPassthrough,
		},
		{
			// The same file, on iOS. Most of a real library is mkv, so this single
			// answer decides whether stowing is instant or a long encode.
			name: "h264 aac mkv packages when the client can't open Matroska",
			ext:  ".mkv", video: "h264", audio: "aac", size: gib,
			clientMatroska: false, want: stowPackage, reasonHas: "Matroska",
		},
		{
			name: "HEVC passes through for a client that decodes it",
			ext:  ".mkv", video: "hevc", audio: "aac", size: 2 * gib,
			clientHEVC: true, clientMatroska: true, want: stowPassthrough,
		},
		{
			name: "HEVC packages for a client that doesn't",
			ext:  ".mkv", video: "hevc", audio: "aac", size: 2 * gib,
			clientHEVC: false, clientMatroska: true, want: stowPackage, reasonHas: "HEVC",
		},
		{
			// The case the whole feature exists for: a 4K remux is unusable on a
			// phone no matter how well the phone decodes it.
			name: "an oversized source packages even when every codec is fine",
			ext:  ".mkv", video: "h264", audio: "aac", size: 30 * gib,
			clientHEVC: true, clientMatroska: true, want: stowPackage, reasonHas: "30.0 GB",
		},
		{
			name: "10-bit H.264 packages even for an HEVC-capable client",
			ext:  ".mkv", video: "h264", audio: "aac", size: gib, highBitDepth: true,
			clientHEVC: true, clientMatroska: true, want: stowPackage, reasonHas: "10-bit",
		},
		{
			// 10-bit HEVC is Main 10, which mobile decodes in hardware — unlike
			// High 10 above. Kept, since re-encoding it costs resolution for nothing.
			name: "10-bit HEVC passes through for an HEVC-capable client",
			ext:  ".mkv", video: "hevc", audio: "aac", size: gib, highBitDepth: true,
			clientHEVC: true, clientMatroska: true, want: stowPassthrough,
		},
		{
			name: "DTS audio packages",
			ext:  ".mkv", video: "h264", audio: "dts", size: gib,
			clientMatroska: true, want: stowPackage, reasonHas: "dts",
		},
		{
			name: "AC-3 audio packages — device support is uneven",
			ext:  ".mkv", video: "h264", audio: "ac3", size: gib,
			clientMatroska: true, want: stowPackage, reasonHas: "ac3",
		},
		{
			name: "an exotic container packages",
			ext:  ".avi", video: "h264", audio: "aac", size: gib,
			want: stowPackage, reasonHas: "avi",
		},
		{
			name: "AV1 packages — decode support is still uneven on phones",
			ext:  ".mp4", video: "av1", audio: "aac", size: gib,
			clientHEVC: true, want: stowPackage, reasonHas: "av1",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := planStow(tt.ext, tt.video, tt.audio, tt.highBitDepth, tt.size,
				DefaultStowPassthroughMax, tt.clientHEVC, tt.clientMatroska)
			if got.method != tt.want {
				t.Errorf("method = %q, want %q (reason %q)", got.method, tt.want, got.reason)
			}
			if got.reason == "" {
				t.Error("reason is empty; the UI and the logs both surface it")
			}
			if tt.reasonHas != "" && !strings.Contains(got.reason, tt.reasonHas) {
				t.Errorf("reason = %q, want it to mention %q", got.reason, tt.reasonHas)
			}
		})
	}
}

// TestPlanStowUnlimitedPassthrough covers maxBytes <= 0, which disables the size
// ceiling rather than rejecting everything.
func TestPlanStowUnlimitedPassthrough(t *testing.T) {
	got := planStow(".mp4", "h264", "aac", false, 500*gib, 0, false, false)
	if got.method != stowPassthrough {
		t.Errorf("method = %q, want %q — maxBytes 0 means no ceiling", got.method, stowPassthrough)
	}
}

func TestHumanBytes(t *testing.T) {
	tests := []struct {
		in   int64
		want string
	}{
		{512, "512 B"},
		{2048, "2.0 KB"},
		{5 * 1024 * 1024, "5.0 MB"},
		{30 * gib, "30.0 GB"},
	}
	for _, tt := range tests {
		if got := humanBytes(tt.in); got != tt.want {
			t.Errorf("humanBytes(%d) = %q, want %q", tt.in, got, tt.want)
		}
	}
}
