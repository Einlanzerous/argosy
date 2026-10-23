package webui

import (
	"os"
	"regexp"
	"testing"
)

// The credits window that opens "Up Next" is a heuristic copied into two
// clients (ARGY-259). Nothing else ties them together, so this fails when one
// moves without the other.
func TestCreditsLeadMatchesAcrossClients(t *testing.T) {
	grab := func(path, pattern string) string {
		t.Helper()
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		m := regexp.MustCompile(pattern).FindSubmatch(b)
		if m == nil {
			t.Fatalf("%s: constant not found (pattern %q); update this test if it was renamed", path, pattern)
		}
		return string(m[1])
	}
	web := grab("../../web/src/views/PlayerView.vue", `const CREDITS_LEAD_SECONDS\s*=\s*(\d+)`)
	dart := grab("../../mobile/argosy/lib/features/player/playback_controller.dart", `static const upNextLeadSeconds\s*=\s*(\d+)`)
	if web != dart {
		t.Fatalf("CREDITS_LEAD_SECONDS (web) = %s but upNextLeadSeconds (Dart) = %s", web, dart)
	}
}
