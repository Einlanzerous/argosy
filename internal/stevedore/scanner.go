package stevedore

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"path"
	"regexp"
	"strings"
	"sync"

	"github.com/Einlanzerous/argosy/internal/mediasource"
	"github.com/Einlanzerous/argosy/internal/mediatool"
	"github.com/jackc/pgx/v5/pgxpool"
)

// mediaExts is the allowlist of file extensions treated as media.
var mediaExts = map[string]bool{
	".mkv": true, ".mp4": true, ".m4v": true, ".avi": true, ".mov": true,
	".webm": true, ".ts": true, ".m2ts": true, ".wmv": true, ".mpg": true, ".mpeg": true,
}

// episodeRe detects a season/episode marker (SxxEyy) anywhere in a filename.
var episodeRe = regexp.MustCompile(`(?i)s\d{1,2}e\d{1,3}`)

// Prober extracts technical metadata from a local file path.
type Prober func(ctx context.Context, path string) (mediatool.Probe, error)

// Scanner walks a library source and upserts media_items, enriching each with
// ffprobe technical metadata.
type Scanner struct {
	pool       *pgxpool.Pool
	logger     *slog.Logger
	probe      Prober
	workers    int
	artworkDir string // where local-poster overrides are cached ("" disables copying)
}

// NewScanner returns a Scanner using the real ffprobe-backed prober.
func NewScanner(pool *pgxpool.Pool, logger *slog.Logger, artworkDir string) *Scanner {
	return &Scanner{pool: pool, logger: logger, probe: mediatool.ProbeFile, workers: 4, artworkDir: artworkDir}
}

// Result summarizes a scan.
type Result struct {
	Scanned int
	Errors  int
	// Removed counts media_items pruned because their file vanished from disk
	// (e.g. renamed or deleted) since the previous sweep.
	Removed int
}

// Scan enumerates src, ingesting every media file into the library, then prunes
// any rows whose file no longer exists. It is idempotent: re-scanning updates
// existing rows (keyed on library_id+file_path) and reconciles deletions.
func (s *Scanner) Scan(ctx context.Context, libraryID string, src mediasource.Source) (Result, error) {
	var entries []mediasource.Entry
	if err := src.Walk(ctx, func(e mediasource.Entry) error {
		if mediaExts[strings.ToLower(path.Ext(e.Path))] {
			entries = append(entries, e)
		}
		return nil
	}); err != nil {
		return Result{}, err
	}

	var (
		wg   sync.WaitGroup
		mu   sync.Mutex
		res  Result
		jobs = make(chan mediasource.Entry)
	)
	worker := func() {
		defer wg.Done()
		for e := range jobs {
			err := s.ingest(ctx, libraryID, src, e)
			mu.Lock()
			if err != nil {
				s.logger.Warn("ingest failed", "path", e.Path, "err", err)
				res.Errors++
			} else {
				res.Scanned++
			}
			mu.Unlock()
		}
	}
	for range s.workers {
		wg.Add(1)
		go worker()
	}
	for _, e := range entries {
		select {
		case <-ctx.Done():
			close(jobs)
			wg.Wait()
			return res, ctx.Err()
		case jobs <- e:
		}
	}
	close(jobs)
	wg.Wait()

	// Group episodes into series/seasons and parse movie years (single-threaded).
	if err := s.Classify(ctx, libraryID); err != nil {
		return res, err
	}
	// Apply local NFO/sidecar + artwork overrides.
	if err := s.ApplyOverrides(ctx, libraryID, src); err != nil {
		return res, err
	}
	// Reconcile deletions: drop rows for files that vanished since last sweep.
	seen := make([]string, len(entries))
	for i, e := range entries {
		seen[i] = e.Path
	}
	removed, err := s.prune(ctx, libraryID, seen)
	if err != nil {
		return res, err
	}
	res.Removed = removed
	if removed > 0 {
		s.logger.Info("pruned missing media", "library", libraryID, "removed", removed)
	}
	return res, nil
}

// prune reconciles the library against what's currently on disk: it removes
// media_items whose file_path wasn't seen this sweep (renamed or deleted files),
// then the episodes/seasons/series those deletions leave empty. Deleting a
// media_item cascades its play_state / vault / label rows and NULLs the owning
// episode's media_item_id (FK ON DELETE SET NULL), so the orphan sweep that
// follows clears those now-fileless episodes.
//
// It is a deliberate no-op when nothing was seen: the media root is an SMB mount,
// and a transient unmount makes Walk yield zero entries — pruning then would wipe
// the entire library. (Walk errors already abort the scan before we reach here;
// this guards the "mounted but empty" case.)
func (s *Scanner) prune(ctx context.Context, libraryID string, seen []string) (int, error) {
	if len(seen) == 0 {
		return 0, nil
	}
	tag, err := s.pool.Exec(ctx,
		`DELETE FROM media_items WHERE library_id = $1 AND file_path <> ALL($2)`,
		libraryID, seen)
	if err != nil {
		return 0, err
	}
	removed := int(tag.RowsAffected())

	// Episodes orphaned by the deletes above (media_item_id NULLed), scoped to
	// this library via their season → series chain.
	if _, err := s.pool.Exec(ctx,
		`DELETE FROM episodes e
		  WHERE e.media_item_id IS NULL
		    AND e.season_id IN (
		      SELECT se.id FROM seasons se
		      JOIN series sr ON sr.id = se.series_id
		      WHERE sr.library_id = $1
		    )`, libraryID); err != nil {
		return removed, err
	}
	// Seasons, then series, left with no children.
	if _, err := s.pool.Exec(ctx,
		`DELETE FROM seasons se
		  WHERE se.series_id IN (SELECT id FROM series WHERE library_id = $1)
		    AND NOT EXISTS (SELECT 1 FROM episodes e WHERE e.season_id = se.id)`,
		libraryID); err != nil {
		return removed, err
	}
	if _, err := s.pool.Exec(ctx,
		`DELETE FROM series sr
		  WHERE sr.library_id = $1
		    AND NOT EXISTS (SELECT 1 FROM seasons se WHERE se.series_id = sr.id)`,
		libraryID); err != nil {
		return removed, err
	}
	return removed, nil
}

func (s *Scanner) ingest(ctx context.Context, libraryID string, src mediasource.Source, e mediasource.Entry) error {
	kind := "movie"
	if episodeRe.MatchString(path.Base(e.Path)) {
		kind = "episode"
	}
	title := titleFromPath(e.Path)

	technical := json.RawMessage("{}")
	var container any
	var duration any
	if local, ok := src.LocalPath(e.Path); ok {
		if p, err := s.probe(ctx, local); err != nil {
			s.logger.Warn("probe failed", "path", e.Path, "err", err)
		} else {
			if len(p.Raw) > 0 {
				technical = p.Raw
			}
			if p.Container != "" {
				container = p.Container
			}
			if p.DurationSeconds > 0 {
				duration = p.DurationSeconds
			}
		}
	}

	var contentHash any
	if h, err := partialHash(ctx, src, e.Path); err == nil {
		contentHash = h
	}

	_, err := s.pool.Exec(ctx, `
		INSERT INTO media_items
			(library_id, kind, title, sort_title, file_path, container, duration_seconds, content_hash, technical)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (library_id, file_path) DO UPDATE SET
			kind = EXCLUDED.kind,
			title = EXCLUDED.title,
			sort_title = EXCLUDED.sort_title,
			container = EXCLUDED.container,
			duration_seconds = EXCLUDED.duration_seconds,
			content_hash = EXCLUDED.content_hash,
			technical = EXCLUDED.technical,
			updated_at = now()`,
		libraryID, kind, title, sortTitle(title), e.Path, container, duration, contentHash, technical)
	return err
}

// partialHash hashes the first 1 MiB of a file — a cheap, stable signature for
// dedup/identity across mirrors without reading entire media files.
func partialHash(ctx context.Context, src mediasource.Source, rel string) (string, error) {
	rc, err := src.Open(ctx, rel)
	if err != nil {
		return "", err
	}
	defer func() { _ = rc.Close() }()
	h := sha256.New()
	if _, err := io.CopyN(h, rc, 1<<20); err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func titleFromPath(p string) string {
	base := path.Base(p)
	base = strings.TrimSuffix(base, path.Ext(base))
	base = strings.NewReplacer(".", " ", "_", " ").Replace(base)
	return strings.Join(strings.Fields(base), " ")
}

func sortTitle(title string) string {
	t := strings.ToLower(title)
	for _, prefix := range []string{"the ", "a ", "an "} {
		if rest, ok := strings.CutPrefix(t, prefix); ok {
			return rest
		}
	}
	return t
}
