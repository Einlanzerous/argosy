package subtitle

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"slices"
	"testing"

	"github.com/Einlanzerous/argosy/internal/fileid"
)

// TestVTTCacheDirIsKeyedByFileIdentity: captions are cached per item *and*
// file, in one flat directory, so a replaced file's captions are never served
// for the file that replaced it (ARGY-238).
func TestVTTCacheDirIsKeyedByFileIdentity(t *testing.T) {
	cache := t.TempDir()
	s := NewService(nil, cache, []string{"en"}, slog.New(slog.NewTextHandler(io.Discard, nil)))

	// An os: track with OpenSubtitles unconfigured fails after its directory is
	// made — enough to see where VTT writes, with no ffmpeg and no network.
	for _, identity := range []string{"hash-1", "hash-2"} {
		if _, err := s.VTT(context.Background(), Target{ItemID: "item", Identity: identity}, "os:1"); err == nil {
			t.Fatal("VTT fetched an external track with OpenSubtitles unconfigured")
		}
	}

	entries, err := os.ReadDir(cache)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, e := range entries {
		names = append(names, e.Name())
	}
	slices.Sort(names)
	want := []string{fileid.ItemKey("item", "hash-1"), fileid.ItemKey("item", "hash-2")}
	if !slices.Equal(names, want) {
		t.Errorf("cache dirs = %v, want one top-level dir per file %v", names, want)
	}
}

// TestSearchCacheIsKeyedByFileIdentity: the OpenSubtitles search matches by the
// file's MovieHash, so a replaced file searches again rather than reusing the
// old file's results for the rest of the hour.
func TestSearchCacheIsKeyedByFileIdentity(t *testing.T) {
	s, hits := osTestService(t, []string{"en"}, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, osSearchBody("en"))
	})
	first := Target{ItemID: "item5", Identity: "hash-1", TMDBID: 42}
	s.List(context.Background(), first)
	s.List(context.Background(), first)
	if *hits != 1 {
		t.Fatalf("search calls for one file = %d, want 1 (cached)", *hits)
	}

	replaced := first
	replaced.Identity = "hash-2"
	s.List(context.Background(), replaced)
	if *hits != 2 {
		t.Errorf("search calls after a replacement = %d, want 2", *hits)
	}
}
