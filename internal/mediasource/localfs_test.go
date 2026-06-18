package mediasource

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"testing"
)

func TestLocalFSWalk(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, filepath.Join(root, "Movie (2020).mkv"), "a")
	mustWrite(t, filepath.Join(root, "Show", "Season 1", "Show S01E01.mkv"), "bb")

	var got []string
	if err := NewLocalFS(root).Walk(context.Background(), func(e Entry) error {
		got = append(got, e.Path)
		return nil
	}); err != nil {
		t.Fatalf("walk: %v", err)
	}
	sort.Strings(got)
	want := []string{"Movie (2020).mkv", "Show/Season 1/Show S01E01.mkv"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Fatalf("walk paths = %v, want %v", got, want)
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
