package stevedore

import (
	"context"
	"fmt"
	"path"
	"regexp"
	"strconv"
	"strings"
)

var (
	reSxxEyy    = regexp.MustCompile(`(?i)s(\d{1,2})[ ._-]?e(\d{1,3})`)
	reNxNN      = regexp.MustCompile(`(?i)\b(\d{1,2})x(\d{1,3})\b`)
	reSeasonDir = regexp.MustCompile(`(?i)^season[ ._-]*(\d+)$`)
	reYear      = regexp.MustCompile(`\b(?:19|20)\d{2}\b`)
)

// categoryDirs are top-level library buckets that should never be mistaken for a
// show name (anime is also surfaced as a tag, see tags.go).
var categoryDirs = map[string]bool{
	"movies": true, "movie": true, "films": true, "film": true,
	"shows": true, "show": true, "tv": true, "series": true, "anime": true,
}

type episodeInfo struct {
	show    string
	season  int
	episode int
}

// parseEpisode extracts show/season/episode from a relative media path using
// filename markers (SxxEyy, NxNN) and season-folder / show-folder structure.
func parseEpisode(filePath string) (episodeInfo, bool) {
	parts := strings.Split(filePath, "/")
	base := parts[len(parts)-1]
	name := strings.TrimSuffix(base, path.Ext(base))
	dirs := parts[:len(parts)-1]

	var season, episode int
	var markerIdx []int
	if m := reSxxEyy.FindStringSubmatch(name); m != nil {
		season, episode = atoi(m[1]), atoi(m[2])
		markerIdx = reSxxEyy.FindStringIndex(name)
	} else if m := reNxNN.FindStringSubmatch(name); m != nil {
		season, episode = atoi(m[1]), atoi(m[2])
		markerIdx = reNxNN.FindStringIndex(name)
	} else {
		return episodeInfo{}, false
	}

	// Show name: the ancestor dir closest to the file that isn't a
	// season/specials folder or a top-level category dir (movies/, shows/,
	// anime/, …); else the filename portion before the season/episode marker.
	// "Last wins" so e.g. shows/Cowboy Bebop/Season 1/… yields "Cowboy Bebop",
	// not the "shows" category folder.
	show := ""
	for _, d := range dirs {
		if reSeasonDir.MatchString(d) || strings.EqualFold(d, "specials") || categoryDirs[strings.ToLower(d)] {
			continue
		}
		show = d
	}
	if show == "" && markerIdx != nil {
		show = name[:markerIdx[0]]
	}
	show = cleanTitle(stripYear(show))

	// A season folder (or "Specials") overrides the filename's season number.
	for _, d := range dirs {
		if m := reSeasonDir.FindStringSubmatch(d); m != nil {
			season = atoi(m[1])
		} else if strings.EqualFold(d, "specials") {
			season = 0
		}
	}

	if show == "" {
		return episodeInfo{}, false
	}
	return episodeInfo{show: show, season: season, episode: episode}, true
}

// parseMovie returns a cleaned title and the release year if present.
func parseMovie(title string) (string, *int) {
	y := reYear.FindString(title)
	cleaned := cleanTitle(stripYear(title))
	if cleaned == "" {
		cleaned = title
	}
	if y == "" {
		return cleaned, nil
	}
	year := atoi(y)
	return cleaned, &year
}

// Classify builds the series/seasons/episodes hierarchy for a library and parses
// movie years. It runs single-threaded after the concurrent scan, so series
// upserts don't race. Items it can't place are flagged review_required.
func (s *Scanner) Classify(ctx context.Context, libraryID string) error {
	type item struct {
		id, kind, filePath, title string
	}
	rows, err := s.pool.Query(ctx,
		`SELECT id::text, kind, file_path, title FROM media_items WHERE library_id = $1`, libraryID)
	if err != nil {
		return err
	}
	var items []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.id, &it.kind, &it.filePath, &it.title); err != nil {
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
		if it.kind == "episode" {
			info, ok := parseEpisode(it.filePath)
			if !ok {
				if _, err := s.pool.Exec(ctx, `UPDATE media_items SET review_required = true WHERE id = $1`, it.id); err != nil {
					return err
				}
				continue
			}
			if err := s.linkEpisode(ctx, libraryID, info, it.id, it.title, deriveTags(it.filePath)); err != nil {
				return fmt.Errorf("link episode %s: %w", it.filePath, err)
			}
		} else {
			title, year := parseMovie(it.title)
			if _, err := s.pool.Exec(ctx,
				`UPDATE media_items SET title = $2, sort_title = $3, year = $4, review_required = false, updated_at = now() WHERE id = $1`,
				it.id, title, sortTitle(title), year); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Scanner) linkEpisode(ctx context.Context, libraryID string, info episodeInfo, mediaItemID, fallbackTitle string, tags []string) error {
	if tags == nil {
		tags = []string{}
	}
	var seriesID string
	// On conflict, union the episode's path-derived tags into the series so a
	// series picks up `anime` (etc.) from any of its episodes.
	if err := s.pool.QueryRow(ctx,
		`INSERT INTO series (library_id, title, sort_title, tags) VALUES ($1, $2, $3, $4)
		 ON CONFLICT (library_id, sort_title) DO UPDATE SET
			title = EXCLUDED.title,
			tags = (SELECT coalesce(array_agg(DISTINCT t), '{}') FROM unnest(series.tags || EXCLUDED.tags) AS t),
			updated_at = now()
		 RETURNING id::text`,
		libraryID, info.show, sortTitle(info.show), tags).Scan(&seriesID); err != nil {
		return err
	}
	var seasonID string
	if err := s.pool.QueryRow(ctx,
		`INSERT INTO seasons (series_id, season_number) VALUES ($1, $2)
		 ON CONFLICT (series_id, season_number) DO UPDATE SET season_number = EXCLUDED.season_number
		 RETURNING id::text`,
		seriesID, info.season).Scan(&seasonID); err != nil {
		return err
	}
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1, $2, $3, $4)
		 ON CONFLICT (season_id, episode_number) DO UPDATE SET media_item_id = EXCLUDED.media_item_id, title = EXCLUDED.title, updated_at = now()`,
		seasonID, info.episode, mediaItemID, fallbackTitle); err != nil {
		return err
	}
	_, err := s.pool.Exec(ctx, `UPDATE media_items SET review_required = false WHERE id = $1`, mediaItemID)
	return err
}

func cleanTitle(s string) string {
	s = strings.NewReplacer(".", " ", "_", " ").Replace(s)
	s = strings.ReplaceAll(s, "()", " ")
	s = strings.ReplaceAll(s, "[]", " ")
	s = strings.Trim(s, " -_(){}[]")
	return strings.Join(strings.Fields(s), " ")
}

func stripYear(s string) string {
	return reYear.ReplaceAllString(s, "")
}

func atoi(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
