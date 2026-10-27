package transcode

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

// TestBoundedRungsRuling4 is the ARGY-179 ruling-4 resolution table, both
// ladders: every example the ruling spells out plus the edge each hint can hit
// on its own. maxHeight caps (keeping the lowest rung when nothing fits under
// it), minHeight is soft, the result is never empty, and a client never needs
// to know the ladder.
func TestBoundedRungsRuling4(t *testing.T) {
	for _, tc := range []struct {
		name          string
		height        int
		codec         string
		minH, maxH    int
		want          []int
		exceedsMaxCap bool // the one legitimate "more than asked for" case
	}{
		// 1080p H.264 source: set 1080/720/480.
		{name: "h264 1080p unhinted", height: 1080, codec: CodecH264, want: []int{1080, 720, 480}},
		{name: "h264 1080p min=max above top (4K mode)", height: 1080, codec: CodecH264, minH: 2160, maxH: 2160, want: []int{1080}},
		{name: "h264 1080p min=max between rungs (800)", height: 1080, codec: CodecH264, minH: 800, maxH: 800, want: []int{720}},
		{name: "h264 1080p min=max below lowest (360): lowest kept", height: 1080, codec: CodecH264, minH: 360, maxH: 360, want: []int{480}, exceedsMaxCap: true},
		{name: "h264 1080p min=max on a rung", height: 1080, codec: CodecH264, minH: 1080, maxH: 1080, want: []int{1080}},
		{name: "h264 1080p min=max on the middle rung", height: 1080, codec: CodecH264, minH: 720, maxH: 720, want: []int{720}},
		{name: "h264 1080p max=720 alone", height: 1080, codec: CodecH264, maxH: 720, want: []int{720, 480}},
		{name: "h264 1080p min=1080 alone", height: 1080, codec: CodecH264, minH: 1080, want: []int{1080}},
		{name: "h264 1080p min=500 alone (soft floor between rungs)", height: 1080, codec: CodecH264, minH: 500, want: []int{1080, 720}},
		{name: "h264 1080p max=1440 alone (cap above the ladder)", height: 1080, codec: CodecH264, maxH: 1440, want: []int{1080, 720, 480}},
		// 4K HEVC source: set 2160/1080/720.
		{name: "hevc 4K unhinted", height: 2160, codec: CodecHEVC, want: []int{2160, 1080, 720}},
		{name: "hevc 4K min=max=2160 (the TV case)", height: 2160, codec: CodecHEVC, minH: 2160, maxH: 2160, want: []int{2160}},
		{name: "hevc 4K min=max=1440 (between rungs)", height: 2160, codec: CodecHEVC, minH: 1440, maxH: 1440, want: []int{1080}},
		{name: "hevc 4K max=1080 alone", height: 2160, codec: CodecHEVC, maxH: 1080, want: []int{1080, 720}},
		{name: "hevc 4K min=1080 alone", height: 2160, codec: CodecHEVC, minH: 1080, want: []int{2160, 1080}},
		{name: "hevc 4K min=max=480 (below lowest): lowest kept", height: 2160, codec: CodecHEVC, minH: 480, maxH: 480, want: []int{720}, exceedsMaxCap: true},
		{name: "hevc 4K min above top", height: 2160, codec: CodecHEVC, minH: 4320, want: []int{2160}},
		// 720p sources: min above everything undershoots to the highest surviving rung.
		{name: "h264 720p min=1080 alone (set 720/480)", height: 720, codec: CodecH264, minH: 1080, want: []int{720}},
		{name: "hevc 720p min=1080 alone (set 720)", height: 720, codec: CodecHEVC, minH: 1080, want: []int{720}},
		{name: "h264 720p min=max=2160", height: 720, codec: CodecH264, minH: 2160, maxH: 2160, want: []int{720}},
		// Unknown height: the single conservative 720 rung, whatever the codec.
		{name: "h264 unknown height min=max=2160", height: 0, codec: CodecH264, minH: 2160, maxH: 2160, want: []int{720}},
		{name: "hevc unknown height min=max=2160", height: 0, codec: CodecHEVC, minH: 2160, maxH: 2160, want: []int{720}},
		{name: "h264 unknown height max=480: lowest kept", height: 0, codec: CodecH264, maxH: 480, want: []int{720}, exceedsMaxCap: true},
		// Sub-ladder source: a synthesised rung at the source height.
		{name: "h264 360p source min=max=2160", height: 360, codec: CodecH264, minH: 2160, maxH: 2160, want: []int{360}},
		{name: "h264 360p source max=240: lowest kept", height: 360, codec: CodecH264, maxH: 240, want: []int{360}, exceedsMaxCap: true},
		// Empty codec resolves to H.264 like everywhere else.
		{name: "empty codec is h264", height: 1080, codec: "", maxH: 720, want: []int{720, 480}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := rungHeights(boundedRungs(tc.height, tc.codec, tc.minH, tc.maxH))
			if !slices.Equal(got, tc.want) {
				t.Fatalf("boundedRungs(%d, %q, min=%d, max=%d) = %v, want %v", tc.height, tc.codec, tc.minH, tc.maxH, got, tc.want)
			}
			if len(got) == 0 {
				t.Fatal("the resolved set must never be empty")
			}
			if tc.maxH > 0 && !tc.exceedsMaxCap {
				for _, h := range got {
					if h > tc.maxH {
						t.Errorf("rung %d exceeds maxHeight %d outside the lowest-rung exception", h, tc.maxH)
					}
				}
			}
			if tc.exceedsMaxCap && got[0] <= tc.maxH {
				t.Errorf("case is marked as the lowest-rung exception but %d does not exceed the cap %d", got[0], tc.maxH)
			}
			// Each surviving rung keeps its bitrate triple from the ladder: shaping
			// subsets the ladder, it never invents rungs the unbounded set lacks.
			full := rungsForCodec(tc.height, tc.codec)
			for _, r := range boundedRungs(tc.height, tc.codec, tc.minH, tc.maxH) {
				if !slices.Contains(full, r) {
					t.Errorf("rung %+v is not in the unbounded set %+v", r, full)
				}
			}
		})
	}
}

// TestBoundedRungsUnhintedIsTheLadder: with no hints the bounded form is the
// unbounded one, so every existing caller's output is unchanged.
func TestBoundedRungsUnhintedIsTheLadder(t *testing.T) {
	for _, h := range []int{0, 360, 480, 720, 800, 1080, 1440, 2160} {
		for _, c := range []string{CodecH264, CodecHEVC} {
			if got, want := boundedRungs(h, c, 0, 0), rungsForCodec(h, c); !slices.Equal(got, want) {
				t.Errorf("height %d %s: bounded(0,0) = %v, want the ladder %v", h, c, got, want)
			}
		}
	}
}

// TestBuildTranscodeArgsEncodesOnlySurvivingRungs: the hints reach ffmpeg as
// fewer outputs, not as a post-hoc filter on the manifest. One surviving rung
// takes the single-output exit (a bare media playlist, stream_%05d.m4s); two
// take the ladder exit with exactly two variants.
func TestBuildTranscodeArgsEncodesOnlySurvivingRungs(t *testing.T) {
	base := Spec{Source: "/m/a.mkv", OutputDir: "/tmp/out", Method: MethodTranscode,
		Encoder: EncoderSoftware, SourceHeight: 1080}

	single := base
	single.MinRungHeight, single.MaxRungHeight = 1080, 1080
	joined := strings.Join(buildArgs(single), " ")
	for _, want := range []string{"-vf scale=-2:1080", "-hls_segment_filename stream_%05d.m4s"} {
		if !strings.Contains(joined, want) {
			t.Errorf("single-rung args missing %q\nargs: %s", want, joined)
		}
	}
	for _, reject := range []string{"split=", "-var_stream_map", "scale=-2:720", "scale=-2:480"} {
		if strings.Contains(joined, reject) {
			t.Errorf("single-rung args still carry %q — the dropped rungs are being encoded\nargs: %s", reject, joined)
		}
	}

	two := base
	two.MaxRungHeight = 720
	joined = strings.Join(buildArgs(two), " ")
	for _, want := range []string{"split=2[v0][v1]", "scale=-2:720", "scale=-2:480", "-var_stream_map v:0,a:0 v:1,a:1"} {
		if !strings.Contains(joined, want) {
			t.Errorf("two-rung args missing %q\nargs: %s", want, joined)
		}
	}
	if strings.Contains(joined, "scale=-2:1080") {
		t.Errorf("maxHeight=720 still encodes the 1080 rung\nargs: %s", joined)
	}

	// Burn-in × single rung: the overlay needs two filter inputs, so the
	// filter_complex branch with one output, not the ladder's split.
	burn := single
	burn.BurnInSubtitle = 3
	joined = strings.Join(buildArgs(burn), " ")
	if !strings.Contains(joined, "-filter_complex [0:v:0][0:3]overlay,scale=-2:1080,format=nv12[vout]") {
		t.Errorf("burn-in single rung must composite into one filter_complex output\nargs: %s", joined)
	}
	if strings.Contains(joined, "split=") || strings.Count(joined, "-map [v") != 1 {
		t.Errorf("burn-in single rung must have exactly one video output\nargs: %s", joined)
	}
}

// fallbackBackend fails its first Run when handed a hardware encoder and
// records every spec it saw, so the hardware→software retry can be observed.
type fallbackBackend struct {
	mu    sync.Mutex
	specs []Spec
}

func (*fallbackBackend) Name() string { return "fallback" }

func (b *fallbackBackend) Run(ctx context.Context, spec Spec, _ func(Progress)) error {
	b.mu.Lock()
	b.specs = append(b.specs, spec)
	b.mu.Unlock()
	if isHardwareEncoder(spec.Encoder) {
		return errors.New("vaapi: failed to open session")
	}
	<-ctx.Done()
	return ctx.Err()
}

func (b *fallbackBackend) count() int {
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.specs)
}

// TestFallbackReResolvesRungs: a TV's min=max=2160 HEVC request plans {2160};
// when the hardware encoder fails at startup the retry swaps to the H.264
// ladder, where the same hints resolve to {1080}. Session.Rungs follows, a
// second log line says so, and the session id — which the client already
// holds — is unchanged.
func TestFallbackReResolvesRungs(t *testing.T) {
	var buf bytes.Buffer
	be := &fallbackBackend{}
	m := NewManager(be, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))

	req := StartRequest{ItemID: "item-4k", AccountID: "acct-1", Source: "/m/4k.mkv", SourceIdentity: "fid",
		Encoder: EncoderVAAPI, SourceHeight: 2160, Method: MethodTranscode, VideoCodec: CodecHEVC,
		MinRungHeight: 2160, MaxRungHeight: 2160}
	s, err := m.Start(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { m.Stop(s.ID) })
	if !slices.Equal(s.Rungs, []int{2160}) {
		t.Fatalf("planned Rungs = %v, want [2160] before the fallback", s.Rungs)
	}

	waitFor(t, func() bool { return be.count() == 2 })
	waitFor(t, func() bool {
		after, _ := m.Get(s.ID)
		return slices.Equal(after.Rungs, []int{1080})
	})
	after, ok := m.Get(s.ID)
	if !ok {
		t.Fatal("session vanished across the fallback — the id must be kept")
	}
	if after.Encoder != EncoderSoftware {
		t.Errorf("Encoder = %q after the fallback, want %q", after.Encoder, EncoderSoftware)
	}
	be.mu.Lock()
	retry := be.specs[1]
	be.mu.Unlock()
	if retry.VideoCodec != CodecH264 || retry.MinRungHeight != 2160 || retry.MaxRungHeight != 2160 {
		t.Errorf("retry spec = codec %q min %d max %d; want h264 with the hints preserved", retry.VideoCodec, retry.MinRungHeight, retry.MaxRungHeight)
	}
	if got := rungHeights(boundedRungs(retry.SourceHeight, retry.VideoCodec, retry.MinRungHeight, retry.MaxRungHeight)); !slices.Equal(got, []int{1080}) {
		t.Errorf("the retry encodes %v, want [1080]", got)
	}

	log := buf.String()
	line := ""
	for _, l := range strings.Split(log, "\n") {
		if strings.Contains(l, "transcode fallback") {
			line = l
		}
	}
	if line == "" {
		t.Fatalf("no 'transcode fallback' line in the log:\n%s", log)
	}
	for _, want := range []string{"id=" + s.ID, "encoder=software", "codec=h264", "rungs=1080"} {
		if !strings.Contains(line, want) {
			t.Errorf("fallback line missing %q: %s", want, line)
		}
	}
}

// TestFallbackOnRemuxKeepsRungsEmpty: a copy has no ladder to re-resolve, so
// the fallback leaves Rungs empty and writes no rungs line.
func TestFallbackOnRemuxKeepsRungsEmpty(t *testing.T) {
	var buf bytes.Buffer
	be := &fallbackBackend{}
	m := NewManager(be, t.TempDir(), time.Minute, 4, slog.New(slog.NewTextHandler(&buf, nil)))

	s, err := m.Start(StartRequest{ItemID: "item-copy", AccountID: "acct-1", Source: "/m/c.mkv",
		Encoder: EncoderVAAPI, SourceHeight: 2160, Method: MethodRemux, VideoCodec: CodecHEVC,
		MinRungHeight: 2160, MaxRungHeight: 2160})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { m.Stop(s.ID) })
	if len(s.Rungs) != 0 {
		t.Errorf("remux Rungs = %v, want empty", s.Rungs)
	}
	waitFor(t, func() bool { return be.count() == 2 })
	after, _ := m.Get(s.ID)
	if len(after.Rungs) != 0 {
		t.Errorf("remux Rungs after fallback = %v, want empty", after.Rungs)
	}
	if strings.Contains(buf.String(), "transcode fallback") {
		t.Errorf("a remux fallback must not claim a re-resolved ladder:\n%s", buf.String())
	}
}

// TestSessionRungsFollowTheHints: Session.Rungs is the planned set for a
// transcode and empty for a remux, and FormatRungs renders both for the
// decision line.
func TestSessionRungsFollowTheHints(t *testing.T) {
	be := &blockingBackend{}
	m := NewManager(be, t.TempDir(), time.Minute, 4, discardLogger())
	t.Cleanup(func() {
		for _, s := range m.List() {
			m.Stop(s.ID)
		}
	})

	tr, err := m.Start(StartRequest{ItemID: "a", AccountID: "acct", Source: "/m/a.mkv", Encoder: EncoderSoftware,
		SourceHeight: 1080, MaxRungHeight: 720})
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(tr.Rungs, []int{720, 480}) || FormatRungs(tr.Rungs) != "720,480" {
		t.Errorf("transcode Rungs = %v (%q), want [720 480] / \"720,480\"", tr.Rungs, FormatRungs(tr.Rungs))
	}
	full, err := m.Start(StartRequest{ItemID: "b", AccountID: "acct", Source: "/m/b.mkv", Encoder: EncoderSoftware,
		SourceHeight: 1080})
	if err != nil {
		t.Fatal(err)
	}
	if FormatRungs(full.Rungs) != "1080,720,480" {
		t.Errorf("unhinted Rungs = %q, want \"1080,720,480\"", FormatRungs(full.Rungs))
	}
	cp, err := m.Start(StartRequest{ItemID: "c", AccountID: "acct", Source: "/m/c.mkv", Encoder: EncoderSoftware,
		SourceHeight: 2160, Method: MethodRemux, VideoCodec: CodecHEVC, MinRungHeight: 2160, MaxRungHeight: 2160})
	if err != nil {
		t.Fatal(err)
	}
	if len(cp.Rungs) != 0 || FormatRungs(cp.Rungs) != "copy" {
		t.Errorf("remux Rungs = %v (%q), want empty / \"copy\"", cp.Rungs, FormatRungs(cp.Rungs))
	}
}
