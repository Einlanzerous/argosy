package subtitle

import (
	"strings"
	"testing"
)

func TestSRTToVTT(t *testing.T) {
	srt := "1\r\n00:00:01,000 --> 00:00:04,000\r\nHello, world\r\n\r\n" +
		"2\r\n00:00:05,500 --> 00:00:08,250\r\n<i>Second line</i>\r\n"
	var b strings.Builder
	if err := SRTToVTT(strings.NewReader(srt), &b); err != nil {
		t.Fatalf("SRTToVTT: %v", err)
	}
	got := b.String()

	if !strings.HasPrefix(got, "WEBVTT\n\n") {
		t.Errorf("missing WEBVTT header, got:\n%s", got)
	}
	if !strings.Contains(got, "00:00:01.000 --> 00:00:04.000") {
		t.Errorf("cue timing comma not converted to period:\n%s", got)
	}
	// Commas inside dialogue must be left alone.
	if !strings.Contains(got, "Hello, world") {
		t.Errorf("dialogue comma was mangled:\n%s", got)
	}
	// CR must be stripped.
	if strings.Contains(got, "\r") {
		t.Errorf("carriage returns survived conversion")
	}
	if !strings.Contains(got, "<i>Second line</i>") {
		t.Errorf("inline tags dropped:\n%s", got)
	}
}

func TestSRTToVTTStripsBOM(t *testing.T) {
	srt := "\ufeff1\n00:00:01,000 --> 00:00:02,000\nHi\n"
	var b strings.Builder
	if err := SRTToVTT(strings.NewReader(srt), &b); err != nil {
		t.Fatalf("SRTToVTT: %v", err)
	}
	if strings.Contains(b.String(), "\ufeff") {
		t.Errorf("BOM survived conversion: %q", b.String())
	}
}

func repair(t *testing.T, in string) string {
	t.Helper()
	var b strings.Builder
	if err := RepairVTT(strings.NewReader(in), &b); err != nil {
		t.Fatalf("RepairVTT: %v", err)
	}
	return b.String()
}

// untimedBlocks counts blocks after the header that carry no timing line —
// the shape that aborted the mobile client's parser (ARGY-286).
func untimedBlocks(vtt string) int {
	n := 0
	for i, b := range splitBlocks(vtt) {
		if i > 0 && !hasTiming(strings.Split(b, "\n")) && !isMetaBlock(strings.Split(b, "\n")[0]) {
			n++
		}
	}
	return n
}

func TestRepairVTTJoinsOrphanBlocksToTheirCue(t *testing.T) {
	// ffmpeg's rendering of one ASS event holding two \N\N paragraph breaks.
	in := "WEBVTT\n\n" +
		"00:01.000 --> 00:02.000\nBefore.\n\n" +
		"22:30.000 --> 22:40.000\nTo defend his family,\nhe overcame battles.\n\n" +
		"Having overcome despair,\nhe defended the world\nthey live in.\n\n" +
		"A third paragraph.\n\n" +
		"22:41.000 --> 22:42.000\nAfter.\n"
	got := repair(t, in)
	if n := untimedBlocks(got); n != 0 {
		t.Fatalf("%d untimed blocks survived:\n%s", n, got)
	}
	want := "22:30.000 --> 22:40.000\nTo defend his family,\nhe overcame battles.\n" +
		"Having overcome despair,\nhe defended the world\nthey live in.\nA third paragraph.\n"
	if !strings.Contains(got, want) {
		t.Errorf("orphans not joined onto their cue in order; got:\n%s", got)
	}
	for _, s := range []string{"Before.", "After."} {
		if !strings.Contains(got, s) {
			t.Errorf("neighbouring cue %q lost:\n%s", s, got)
		}
	}
}

func TestRepairVTTDropsDrawingCommands(t *testing.T) {
	in := "WEBVTT\n\n" +
		"00:02.340 --> 00:11.780\nm 442 308 l 1450 308 1450 1028 442 1028\n\n" +
		"00:05.000 --> 00:06.000\nm -1.5 2 b 3 4 5 6 7 8\nEven without a form,\n\n" +
		"00:07.000 --> 00:08.000\nm 5 people walked in.\n"
	got := repair(t, in)
	if strings.Contains(got, "1450 308") || strings.Contains(got, "b 3 4") {
		t.Errorf("drawing commands survived:\n%s", got)
	}
	if strings.Contains(got, "00:02.340") {
		t.Errorf("a cue holding only a drawing should be dropped:\n%s", got)
	}
	if !strings.Contains(got, "00:05.000 --> 00:06.000\nEven without a form,") {
		t.Errorf("dialogue sharing a cue with a drawing was lost:\n%s", got)
	}
	// Dialogue that merely starts with "m" and a number is not a drawing.
	if !strings.Contains(got, "m 5 people walked in.") {
		t.Errorf("ordinary dialogue was treated as a drawing:\n%s", got)
	}
}

func TestRepairVTTKeepsMetaBlocksAndIdentifiers(t *testing.T) {
	in := "WEBVTT - title\r\n\r\nNOTE produced by ffmpeg\r\n\r\nSTYLE\r\n::cue { color: white }\r\n\r\n" +
		"intro\r\n00:00:01.000 --> 00:00:02.000 align:start\r\nHello\r\n"
	got := repair(t, in)
	for _, s := range []string{"WEBVTT - title\n", "NOTE produced by ffmpeg\n", "STYLE\n::cue { color: white }\n",
		"intro\n00:00:01.000 --> 00:00:02.000 align:start\nHello\n"} {
		if !strings.Contains(got, s) {
			t.Errorf("missing %q in:\n%s", s, got)
		}
	}
	if strings.Contains(got, "\r") {
		t.Errorf("carriage returns survived")
	}
}

func TestRepairVTTLeavesAWellFormedFileAlone(t *testing.T) {
	in := "WEBVTT\n\n00:01.000 --> 00:02.000\nOne\n\n00:03.000 --> 00:04.000\nTwo\nlines\n"
	if got := repair(t, in); got != in {
		t.Errorf("well-formed input changed:\n got %q\nwant %q", got, in)
	}
}
