package subtitle

import (
	"os"
	"path/filepath"
	"testing"
)

// For a 16-byte file (smaller than one 64 KiB chunk) head and tail both cover
// the whole file, so hash = size + 2*(uint64[0] + uint64[1]). With bytes
// 0x01..0x10: u0=0x0807060504030201, u1=0x100f0e0d0c0b0a09, sum=0x18161412100e0c0a,
// hash = 16 + 2*sum = 0x302c2824201c1824.
func TestMovieHashSmallFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tiny.bin")
	data := make([]byte, 16)
	for i := range data {
		data[i] = byte(i + 1)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := MovieHash(path)
	if err != nil {
		t.Fatalf("MovieHash: %v", err)
	}
	if want := "302c2824201c1824"; got != want {
		t.Errorf("MovieHash = %s, want %s", got, want)
	}
}

func TestMovieHashDeterministicAndLong(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "big.bin")
	// Larger than two chunks so head and tail are distinct windows.
	data := make([]byte, 200*1024)
	for i := range data {
		data[i] = byte(i)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
	a, err := MovieHash(path)
	if err != nil {
		t.Fatalf("MovieHash: %v", err)
	}
	b, err := MovieHash(path)
	if err != nil {
		t.Fatalf("MovieHash: %v", err)
	}
	if a != b {
		t.Errorf("non-deterministic: %s != %s", a, b)
	}
	if len(a) != 16 {
		t.Errorf("hash %q is not 16 hex digits", a)
	}
}

func TestMovieHashEmpty(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "empty.bin")
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := MovieHash(path); err == nil {
		t.Error("expected error for empty file")
	}
}
