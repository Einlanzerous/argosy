// Package subtitle resolves subtitles for media items through a priority chain
// (embedded text tracks first, then OpenSubtitles) and serves them as WebVTT.
package subtitle

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"
)

// hashChunk is the byte window read from each end of the file for the
// OpenSubtitles moviehash (64 KiB).
const hashChunk = 64 * 1024

// MovieHash computes the OpenSubtitles "moviehash" for a file: the 64-bit sum of
// the file size plus every little-endian uint64 in the first and last 64 KiB,
// rendered as 16 lowercase hex digits. It's the most accurate match key because
// it identifies the exact release, not just the title. Files smaller than two
// chunks are hashed over whatever bytes exist.
func MovieHash(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer func() { _ = f.Close() }()

	fi, err := f.Stat()
	if err != nil {
		return "", err
	}
	size := fi.Size()
	if size == 0 {
		return "", fmt.Errorf("moviehash: empty file %s", path)
	}

	hash := uint64(size)

	head := make([]byte, min64(hashChunk, size))
	if _, err := io.ReadFull(f, head); err != nil {
		return "", err
	}
	hash += sumChunk(head)

	// Tail: the last 64 KiB (or the whole file when it's shorter than a chunk).
	tailLen := min64(hashChunk, size)
	tail := make([]byte, tailLen)
	if _, err := f.ReadAt(tail, size-tailLen); err != nil && err != io.EOF {
		return "", err
	}
	hash += sumChunk(tail)

	return fmt.Sprintf("%016x", hash), nil
}

// sumChunk adds each whole little-endian uint64 in b into a wrapping accumulator.
// Trailing bytes that don't fill a uint64 are ignored, matching the reference
// implementation.
func sumChunk(b []byte) uint64 {
	var sum uint64
	for i := 0; i+8 <= len(b); i += 8 {
		sum += binary.LittleEndian.Uint64(b[i : i+8])
	}
	return sum
}

func min64(a, b int64) int64 {
	if a < b {
		return a
	}
	return b
}
