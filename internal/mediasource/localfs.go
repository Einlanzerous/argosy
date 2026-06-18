package mediasource

import (
	"context"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// LocalFS is a Source backed by a local directory tree.
type LocalFS struct{ root string }

// NewLocalFS returns a Source rooted at dir.
func NewLocalFS(dir string) *LocalFS { return &LocalFS{root: dir} }

// Walk yields every regular file under the root.
func (l *LocalFS) Walk(ctx context.Context, fn func(Entry) error) error {
	return filepath.WalkDir(l.root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(l.root, p)
		if err != nil {
			return err
		}
		return fn(Entry{Path: filepath.ToSlash(rel), Size: info.Size(), ModTime: info.ModTime()})
	})
}

// LocalPath returns the absolute on-disk path for rel.
func (l *LocalFS) LocalPath(rel string) (string, bool) {
	return filepath.Join(l.root, filepath.FromSlash(rel)), true
}

// Open opens rel for reading.
func (l *LocalFS) Open(_ context.Context, rel string) (io.ReadCloser, error) {
	return os.Open(filepath.Join(l.root, filepath.FromSlash(rel)))
}
