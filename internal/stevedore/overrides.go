package stevedore

import (
	"context"
	"encoding/json"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/Einlanzerous/argosy/internal/mediasource"
)

// ApplyOverrides reads sibling Kodi .nfo files and local artwork and stores them
// as the override layer (media_items.metadata / series.metadata). The browse
// layer overlays these on top of provider_metadata. Re-running is idempotent:
// overrides are recomputed from the files each scan.
func (s *Scanner) ApplyOverrides(ctx context.Context, libraryID string, src mediasource.Source) error {
	type item struct{ id, kind, filePath string }
	rows, err := s.pool.Query(ctx, `SELECT id::text, kind, file_path FROM media_items WHERE library_id = $1`, libraryID)
	if err != nil {
		return err
	}
	var items []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.id, &it.kind, &it.filePath); err != nil {
			rows.Close()
			return err
		}
		items = append(items, it)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, it := range items {
		dir := path.Dir(it.filePath)
		stem := strings.TrimSuffix(it.filePath, path.Ext(it.filePath))
		candidates := []string{stem + ".nfo"}
		if it.kind == "movie" {
			candidates = append(candidates, path.Join(dir, "movie.nfo"))
		}

		override := map[string]any{}
		for _, c := range candidates {
			data, err := readAll(ctx, src, c)
			if err != nil {
				continue
			}
			var parsed map[string]any
			if it.kind == "movie" {
				parsed, err = parseMovieNFO(data)
			} else {
				parsed, err = parseEpisodeNFO(data)
			}
			if err != nil {
				s.logger.Warn("nfo parse failed", "path", c, "err", err)
				continue
			}
			override = parsed
			break
		}
		if poster := s.copyLocalPoster(ctx, src, dir, stem, "overrides/"+it.id+".jpg"); poster != "" {
			override["poster"] = poster
		}
		if len(override) == 0 {
			continue
		}
		raw, err := json.Marshal(override)
		if err != nil {
			return err
		}
		if _, err := s.pool.Exec(ctx, `UPDATE media_items SET metadata = $2, updated_at = now() WHERE id = $1`, it.id, raw); err != nil {
			return err
		}
	}

	// Series: tvshow.nfo in the show directory (derived from a linked episode).
	srows, err := s.pool.Query(ctx, `
		SELECT r.id::text,
		       (SELECT mi.file_path FROM episodes e
		          JOIN seasons se ON se.id = e.season_id
		          JOIN media_items mi ON mi.id = e.media_item_id
		         WHERE se.series_id = r.id LIMIT 1)
		FROM series r WHERE r.library_id = $1`, libraryID)
	if err != nil {
		return err
	}
	type sitem struct {
		id         string
		samplePath *string
	}
	var series []sitem
	for srows.Next() {
		var si sitem
		if err := srows.Scan(&si.id, &si.samplePath); err != nil {
			srows.Close()
			return err
		}
		series = append(series, si)
	}
	srows.Close()
	if err := srows.Err(); err != nil {
		return err
	}
	for _, si := range series {
		if si.samplePath == nil {
			continue
		}
		data, err := readAll(ctx, src, path.Join(topDir(*si.samplePath), "tvshow.nfo"))
		if err != nil {
			continue
		}
		override, err := parseTVShowNFO(data)
		if err != nil || len(override) == 0 {
			continue
		}
		raw, err := json.Marshal(override)
		if err != nil {
			return err
		}
		if _, err := s.pool.Exec(ctx, `UPDATE series SET metadata = $2, updated_at = now() WHERE id = $1`, si.id, raw); err != nil {
			return err
		}
	}
	return nil
}

func (s *Scanner) copyLocalPoster(ctx context.Context, src mediasource.Source, dir, stem, destRel string) string {
	if s.artworkDir == "" {
		return ""
	}
	for _, c := range []string{stem + "-poster.jpg", path.Join(dir, "poster.jpg"), path.Join(dir, "folder.jpg")} {
		data, err := readAll(ctx, src, c)
		if err != nil {
			continue
		}
		dest := filepath.Join(s.artworkDir, filepath.FromSlash(destRel))
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return ""
		}
		if err := os.WriteFile(dest, data, 0o644); err != nil {
			return ""
		}
		return destRel
	}
	return ""
}

func readAll(ctx context.Context, src mediasource.Source, rel string) ([]byte, error) {
	rc, err := src.Open(ctx, rel)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rc.Close() }()
	return io.ReadAll(rc)
}

func topDir(p string) string {
	if i := strings.Index(p, "/"); i >= 0 {
		return p[:i]
	}
	return ""
}
