package subtitle

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// assFixture is a minimal typeset script carrying the two shapes ffmpeg's
// WebVTT encoder mishandles (ARGY-286): a \N\N paragraph break inside one
// event, and a {\p1} vector drawing.
const assFixture = `[Script Info]
ScriptType: v4.00+
PlayResX: 1920
PlayResY: 1080

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:02.34,0:00:11.78,Default,,0,0,0,,{\p1}m 442 308 l 1450 308 1450 1028 442 1028{\p0}
Dialogue: 0,0:00:03.00,0:00:05.00,Default,,0,0,0,,Come with me!
Dialogue: 0,0:22:30.00,0:22:40.00,Default,,0,0,0,,To defend his family,\Nhe overcame battles.\N\NHaving overcome despair,\Nhe defended the world.
Dialogue: 0,0:22:41.00,0:22:42.00,Default,,0,0,0,,After.
`

func TestExtractEmbeddedRepairsTypesetASS(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not on PATH")
	}
	dir := t.TempDir()
	src := filepath.Join(dir, "typeset.ass")
	if err := os.WriteFile(src, []byte(assFixture), 0o644); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(dir, "out.vtt")
	if err := (&Service{}).extractEmbedded(context.Background(), src, "0", dest); err != nil {
		t.Fatalf("extractEmbedded: %v", err)
	}
	b, err := os.ReadFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	if n := untimedBlocks(got); n != 0 {
		t.Errorf("%d blocks without a timing line:\n%s", n, got)
	}
	if strings.Contains(got, "1450 308") {
		t.Errorf("drawing survived as text:\n%s", got)
	}
	for _, s := range []string{"Come with me!", "Having overcome despair,", "After."} {
		if !strings.Contains(got, s) {
			t.Errorf("dialogue %q missing:\n%s", s, got)
		}
	}
	if _, err := os.Stat(dest + ".raw"); !os.IsNotExist(err) {
		t.Errorf("raw ffmpeg output left behind (stat err %v)", err)
	}
}
