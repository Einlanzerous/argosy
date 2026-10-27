package transcode

import "testing"

// TestSessionIDScopedToSourceIdentity: an item keeps its id when its file is
// replaced (ARGY-238), so a start after the replacement must not join a live
// encode of the old file — even when the replacement kept its filename.
func TestSessionIDScopedToSourceIdentity(t *testing.T) {
	base := StartRequest{ItemID: "i", AccountID: "acct-1", Source: "/m/Show S01E02.mkv",
		SourceIdentity: "hash-1", Encoder: EncoderSoftware}

	replaced := base
	replaced.SourceIdentity = "hash-2"
	if sessionID(base) == sessionID(replaced) {
		t.Error("a request for a replaced file (same path, new identity) joins the old file's session")
	}

	same := base
	if sessionID(base) != sessionID(same) {
		t.Error("identical requests no longer share a session")
	}
}

// goldenUnhinted is a fixed unhinted request whose derived ids were recorded
// from the code before the ladder hints existed (ARGY-179). An unhinted key
// must stay byte-identical so sessions in flight across the deploy are
// rejoined rather than duplicated (ARGY-239).
var goldenUnhinted = StartRequest{ItemID: "item-golden", AccountID: "acct-golden", Source: "/m/Film.mkv",
	SourceIdentity: "fid-golden", StartAt: 90.7, Encoder: EncoderSoftware, SourceHeight: 1080,
	VideoCodec: CodecH264, AudioTracks: []AudioTrack{{Index: 0, Language: "en", Default: true}}}

// TestSessionIDGoldenUnhinted pins the pre-hint ids: one with the raw Method
// left empty (what the key sees before Start normalises it) and one with
// MethodTranscode, plus a remux and a hardware HEVC 4K transcode for good
// measure. Recorded from main @ 4ecc15a.
func TestSessionIDGoldenUnhinted(t *testing.T) {
	transcodeReq := goldenUnhinted
	transcodeReq.Method = MethodTranscode
	remux := goldenUnhinted
	remux.Method = MethodRemux
	remux.VideoCodec = CodecHEVC
	vaapi := goldenUnhinted
	vaapi.Encoder = EncoderVAAPI
	vaapi.SourceHeight = 2160
	vaapi.VideoCodec = CodecHEVC
	vaapi.Method = MethodTranscode

	for _, tc := range []struct {
		name string
		req  StartRequest
		want string
	}{
		{"raw Method empty", goldenUnhinted, "02a722b249f03116"},
		{"Method transcode", transcodeReq, "2fcf4b7202ee96f7"},
		{"Method remux hevc", remux, "f4df1b74ef1e4c3b"},
		{"vaapi hevc 2160 transcode", vaapi, "ad82f011b9e944b0"},
	} {
		if got := sessionID(tc.req); got != tc.want {
			t.Errorf("%s: sessionID = %s, want the pre-hint golden %s", tc.name, got, tc.want)
		}
	}
}

// TestSessionIDKeysOnEffectiveRungs: the key takes the rung set the hints
// resolve to, not the raw values, so clients whose hints land on the same rungs
// share one encode — and hints that resolve to the full ladder join the
// unhinted session.
func TestSessionIDKeysOnEffectiveRungs(t *testing.T) {
	base := goldenUnhinted
	base.Method = MethodTranscode

	with := func(minH, maxH int) StartRequest {
		r := base
		r.MinRungHeight, r.MaxRungHeight = minH, maxH
		return r
	}

	// Both resolve to {1080} on a 1080p H.264 source: a 4K mode and a 1080p mode
	// asking for their own height.
	if sessionID(with(2160, 2160)) != sessionID(with(1080, 1080)) {
		t.Error("min=max=2160 and min=max=1080 resolve to the same rung set but derive different ids")
	}
	// min=1080 alone is also {1080}.
	if sessionID(with(1080, 0)) != sessionID(with(1080, 1080)) {
		t.Error("min=1080 alone and min=max=1080 resolve to {1080} but derive different ids")
	}
	// A different effective set is a different session.
	if sessionID(with(0, 720)) == sessionID(base) {
		t.Error("max=720 ({720,480}) joined the full-ladder session")
	}
	if sessionID(with(0, 720)) == sessionID(with(1080, 1080)) {
		t.Error("{720,480} and {1080} derive the same id")
	}
	// Hints that leave the ladder whole are the unhinted key.
	for _, r := range []StartRequest{with(480, 0), with(0, 1080), with(480, 1080), with(1, 4320)} {
		if sessionID(r) != sessionID(base) {
			t.Errorf("hints min=%d max=%d resolve to the full ladder but derive a different id", r.MinRungHeight, r.MaxRungHeight)
		}
	}
}

// TestSessionIDRemuxDropsHints: a copy has one variant, so the hints must not
// split one remux into several sessions. The key reads the raw Method.
func TestSessionIDRemuxDropsHints(t *testing.T) {
	remux := goldenUnhinted
	remux.Method = MethodRemux
	remux.VideoCodec = CodecHEVC
	remux.SourceHeight = 2160

	hinted := remux
	hinted.MinRungHeight, hinted.MaxRungHeight = 2160, 2160
	if sessionID(hinted) != sessionID(remux) {
		t.Error("a hinted remux derives a different id from the unhinted one")
	}
	if PlannedRungs(hinted) != nil {
		t.Errorf("PlannedRungs on a remux = %v, want nil", PlannedRungs(hinted))
	}

	// ...whereas the same hints on a transcode of the same source do shape the key.
	tr := hinted
	tr.Method = MethodTranscode
	unhintedTr := remux
	unhintedTr.Method = MethodTranscode
	if sessionID(tr) == sessionID(unhintedTr) {
		t.Error("min=max=2160 on a 4K HEVC transcode ({2160}) joined the full-ladder session")
	}
}
