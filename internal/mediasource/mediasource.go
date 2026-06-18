// Package mediasource abstracts where media listings and bytes come from, so the
// ingestion layer is independent of the storage backend. A local-filesystem
// implementation ships now; a Pydio Cells / TrueNAS backend will be added as
// another implementation once the storage approach is settled (see ARGY-53).
package mediasource

import (
	"context"
	"io"
	"time"
)

// Entry is a single regular file discovered under a source root. Path is
// relative to the root and uses "/" separators.
type Entry struct {
	Path    string
	Size    int64
	ModTime time.Time
}

// Source enumerates and reads media files from a backend.
type Source interface {
	// Walk calls fn for every regular file under the root.
	Walk(ctx context.Context, fn func(Entry) error) error
	// LocalPath returns a filesystem path that ffprobe/ffmpeg can read directly,
	// or ("", false) when the backend cannot provide one (callers fall back to Open).
	LocalPath(rel string) (string, bool)
	// Open opens a file for reading.
	Open(ctx context.Context, rel string) (io.ReadCloser, error)
}
