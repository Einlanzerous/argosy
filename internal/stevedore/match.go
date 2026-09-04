package stevedore

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"path"
	"path/filepath"
	"strconv"
	"time"

	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Matcher enriches movies and series with provider metadata (TMDB) + artwork.
type Matcher struct {
	pool       *pgxpool.Pool
	provider   metadata.Provider
	logger     *slog.Logger
	artworkDir string
	download   func(ctx context.Context, url, dest string) error
}

// NewMatcher returns a Matcher that downloads artwork into artworkDir.
func NewMatcher(pool *pgxpool.Pool, provider metadata.Provider, artworkDir string, logger *slog.Logger) *Matcher {
	// Artwork goes through the provider's own download path when it has one,
	// so image fetches share TMDB's rate limit + retry envelope (ARGY-141).
	client := &http.Client{Timeout: 30 * time.Second}
	download := func(ctx context.Context, url, dest string) error {
		return metadata.DownloadImage(ctx, client, url, dest)
	}
	if d, ok := provider.(metadata.ImageDownloader); ok {
		download = d.DownloadImage
	}
	return &Matcher{
		pool:       pool,
		provider:   provider,
		logger:     logger,
		artworkDir: artworkDir,
		download:   download,
	}
}

// MatchResult summarizes a match run.
type MatchResult struct {
	Movies   int
	Series   int
	Episodes int // episode rows enriched with per-episode TMDB metadata
	Credits  int // movies + series enriched with cast/people for search (ARGY-67)
	Misses   int
	// Unmapped lists seasons on disk the provider has no counterpart for, and
	// which therefore went without episode metadata. Reported rather than
	// swallowed: the series still matches, so the show looks half-populated
	// instead of unmatched, and nothing else in the system says why (ARGY-224).
	Unmapped []UnmappedSeason
}

// UnmappedSeason is one season whose number could not be translated onto the
// provider's numbering — neither directly nor through a published TVDB-ordered
// episode group. Its episodes keep their filename-derived titles.
type UnmappedSeason struct {
	SeriesID     string `json:"seriesId"`
	SeriesTitle  string `json:"seriesTitle"`
	SeasonNumber int    `json:"seasonNumber"`
	Episodes     int    `json:"episodes"` // episode rows left without provider metadata
	// Reason says which way it failed — no such season, no published ordering,
	// or the provider disowning the series outright. Without it every entry
	// reads the same and none of them suggests what to do next.
	Reason string `json:"reason,omitempty"`
}

type matchItem struct {
	id    string
	title string
	year  int
}

// MatchLibrary matches unmatched movies and series in a library (or all of them
// when force is true).
func (m *Matcher) MatchLibrary(ctx context.Context, libraryID string, force bool) (MatchResult, error) {
	var res MatchResult

	movieQ := `SELECT id::text, title, year FROM media_items WHERE library_id = $1 AND kind = 'movie'`
	if !force {
		movieQ += ` AND tmdb_id IS NULL`
	}
	movies, err := m.collect(ctx, movieQ, libraryID)
	if err != nil {
		return res, err
	}
	for _, it := range movies {
		match, err := m.provider.SearchMovie(ctx, it.title, it.year)
		if err != nil {
			m.logger.Warn("tmdb movie search failed", "title", it.title, "err", err)
			continue
		}
		if match == nil {
			res.Misses++
			continue
		}
		if err := m.store(ctx, "media_items", "movies", it.id, match); err != nil {
			return res, err
		}
		res.Movies++
	}

	seriesQ := `SELECT id::text, title, 0 FROM series WHERE library_id = $1`
	if !force {
		seriesQ += ` AND tmdb_id IS NULL`
	}
	seriesList, err := m.collect(ctx, seriesQ, libraryID)
	if err != nil {
		return res, err
	}
	for _, it := range seriesList {
		match, err := m.provider.SearchSeries(ctx, it.title)
		if err != nil {
			m.logger.Warn("tmdb series search failed", "title", it.title, "err", err)
			continue
		}
		if match == nil {
			res.Misses++
			continue
		}
		if err := m.store(ctx, "series", "series", it.id, match); err != nil {
			return res, err
		}
		res.Series++
	}

	// Per-episode metadata: now that series carry a tmdb_id, fill in each
	// episode's name/overview/still. Runs over every matched series (not just
	// the ones matched this pass) so episode files added after the series was
	// first matched get enriched too; cheap because it only touches episodes
	// still missing provider metadata unless force is set.
	n, unmapped, err := m.matchEpisodes(ctx, libraryID, force)
	// Recorded before the error check: a run that fails partway still resolved
	// (and failed to resolve) real seasons, and the scan status is the only
	// place that says so.
	res.Episodes = n
	res.Unmapped = unmapped
	if err != nil {
		return res, err
	}

	// People/cast (ARGY-67): backfill top-billed cast onto every matched movie +
	// series still missing it. Runs over all matched items (not just this pass),
	// so a plain `match` enriches the existing library, and the STORED
	// search_vector picks the names up on the write — no separate backfill job.
	c, err := m.matchCredits(ctx, libraryID, force)
	if err != nil {
		return res, err
	}
	res.Credits = c
	return res, nil
}

// matchCredits writes top-billed cast names into provider_metadata.cast for the
// matched movies + series of a library, so people/cast become searchable. Without
// force it only touches rows that don't yet carry a `cast` key, making it cheap
// and idempotent across rescans; the credits key is always set (even to an empty
// array) once fetched so a cast-less title isn't re-queried every run. Returns
// the number of rows enriched.
func (m *Matcher) matchCredits(ctx context.Context, libraryID string, force bool) (int, error) {
	credits := func(table, kind string, fetch func(context.Context, int64) ([]string, error)) (int, error) {
		q := `SELECT id::text, tmdb_id FROM ` + table + ` WHERE library_id = $1 AND tmdb_id IS NOT NULL`
		if kind != "" {
			q += ` AND kind = '` + kind + `'`
		}
		if !force {
			q += ` AND NOT (provider_metadata ? 'cast')`
		}
		rows, err := m.pool.Query(ctx, q, libraryID)
		if err != nil {
			return 0, err
		}
		type row struct {
			id   string
			tmdb int64
		}
		var items []row
		for rows.Next() {
			var r row
			if err := rows.Scan(&r.id, &r.tmdb); err != nil {
				rows.Close()
				return 0, err
			}
			items = append(items, r)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return 0, err
		}

		count := 0
		for _, it := range items {
			cast, err := fetch(ctx, it.tmdb)
			if err != nil {
				m.logger.Warn("tmdb credits fetch failed", "table", table, "tmdb_id", it.tmdb, "err", err)
				continue
			}
			raw, err := json.Marshal(cast)
			if err != nil {
				return count, err
			}
			if _, err := m.pool.Exec(ctx,
				`UPDATE `+table+` SET provider_metadata = jsonb_set(provider_metadata, '{cast}', $2::jsonb, true), updated_at = now() WHERE id = $1`,
				it.id, raw); err != nil {
				return count, err
			}
			count++
		}
		return count, nil
	}

	movies, err := credits("media_items", "movie", m.provider.MovieCredits)
	if err != nil {
		return 0, err
	}
	series, err := credits("series", "", m.provider.SeriesCredits)
	if err != nil {
		return movies, err
	}
	return movies + series, nil
}

// matchEpisodes fills in per-episode metadata for every matched series in the
// library. Returns the number of episode rows enriched, plus the seasons whose
// numbering could not be reconciled with the provider's (ARGY-224).
func (m *Matcher) matchEpisodes(ctx context.Context, libraryID string, force bool) (int, []UnmappedSeason, error) {
	rows, err := m.pool.Query(ctx,
		`SELECT id::text, title, tmdb_id FROM series WHERE library_id = $1 AND tmdb_id IS NOT NULL`, libraryID)
	if err != nil {
		return 0, nil, err
	}
	var seriesList []seriesRow
	for rows.Next() {
		var s seriesRow
		if err := rows.Scan(&s.id, &s.title, &s.tmdb); err != nil {
			rows.Close()
			return 0, nil, err
		}
		seriesList = append(seriesList, s)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, nil, err
	}

	total := 0
	var unmapped []UnmappedSeason
	for _, s := range seriesList {
		n, u, err := m.matchSeriesEpisodes(ctx, s, force)
		if err != nil {
			return total, unmapped, err
		}
		total += n
		unmapped = append(unmapped, u...)
	}
	return total, unmapped, nil
}

// seriesRow is a matched series the episode pass works over.
type seriesRow struct {
	id    string
	title string
	tmdb  int64
}

// localSeason is one season on disk still needing provider metadata, carrying
// whatever verdict a previous sweep reached about it.
type localSeason struct {
	id       string
	number   int
	provider *int    // provider_season_number, NULL unless a season was pinned
	offset   int     // provider_episode_offset
	source   *string // identity | episode_group | manual | unmapped; NULL = never looked
	episodes int     // episode rows still missing provider metadata
}

// seasonResolution is how a season's episodes will be obtained, or why they
// won't be.
type seasonResolution int

const (
	// seasonFromGroup: the provider's published ordering supplied the episodes
	// outright, already numbered as the files on disk are.
	seasonFromGroup seasonResolution = iota
	// seasonFromProviderSeason: fetch a provider season and translate.
	seasonFromProviderSeason
	// seasonUnmapped: looked, and there is no counterpart. Reported.
	seasonUnmapped
	// seasonUnavailable: could not ask. Not reported — "we could not look" is
	// not "there is nothing there" — and retried on the next sweep.
	seasonUnavailable
	// seasonLeftAlone: an operator pinned this season as having no counterpart.
	seasonLeftAlone
)

// seasonPlan is the resolver's answer for one on-disk season.
type seasonPlan struct {
	status   seasonResolution
	episodes []metadata.EpisodeMeta // seasonFromGroup: on-disk numbering
	mapping  metadata.SeasonMapping // seasonFromProviderSeason
	source   string                 // what to record; "" records nothing
	reason   string                 // seasonUnmapped: what to tell the operator
}

func (m *Matcher) matchSeriesEpisodes(ctx context.Context, s seriesRow, force bool) (int, []UnmappedSeason, error) {
	// Only the seasons with episodes still missing metadata (all of them when
	// force) — avoids re-hitting the provider for already-enriched seasons.
	seasonQ := `SELECT se.id::text, se.season_number, se.provider_season_number,
	                   se.provider_episode_offset, se.provider_season_source, count(e.id)
	              FROM seasons se JOIN episodes e ON e.season_id = se.id
	             WHERE se.series_id = $1`
	if !force {
		seasonQ += ` AND e.provider_metadata = '{}'::jsonb`
	}
	seasonQ += ` GROUP BY se.id, se.season_number, se.provider_season_number,
	                      se.provider_episode_offset, se.provider_season_source
	             ORDER BY se.season_number`
	rows, err := m.pool.Query(ctx, seasonQ, s.id)
	if err != nil {
		return 0, nil, err
	}
	var seasons []localSeason
	for rows.Next() {
		var ls localSeason
		if err := rows.Scan(&ls.id, &ls.number, &ls.provider, &ls.offset, &ls.source, &ls.episodes); err != nil {
			rows.Close()
			return 0, nil, err
		}
		seasons = append(seasons, ls)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, nil, err
	}

	resolve := m.seasonResolver(s)
	count := 0
	var unmapped []UnmappedSeason
	// Provider seasons fetched for this series, successes and failures alike:
	// several on-disk seasons can point at one provider season, and a failure
	// that isn't remembered is re-requested (and re-warned) once per season.
	fetched := make(map[int][]metadata.EpisodeMeta)
	failedSeasons := make(map[int]bool)

	for _, ls := range seasons {
		plan := resolve(ctx, ls)

		var byNum map[int]metadata.EpisodeMeta
		switch plan.status {
		case seasonUnmapped:
			m.logger.Warn("season has no counterpart in the provider's ordering; episodes left without metadata",
				"series", s.title, "tmdb_id", s.tmdb, "season", ls.number,
				"episodes", ls.episodes, "reason", plan.reason)
			unmapped = append(unmapped, UnmappedSeason{
				SeriesID:     s.id,
				SeriesTitle:  s.title,
				SeasonNumber: ls.number,
				Episodes:     ls.episodes,
				Reason:       plan.reason,
			})
			if err := m.storeSeasonMapping(ctx, ls.id, nil, 0, "unmapped"); err != nil {
				return count, unmapped, err
			}
			continue
		case seasonUnavailable, seasonLeftAlone:
			continue
		case seasonFromGroup:
			// Already numbered as the files are; no translation to do.
			byNum = make(map[int]metadata.EpisodeMeta, len(plan.episodes))
			for _, e := range plan.episodes {
				byNum[e.Number] = e
			}
		case seasonFromProviderSeason:
			ps := plan.mapping.SeasonNumber
			eps, ok := fetched[ps]
			if !ok {
				if failedSeasons[ps] {
					continue
				}
				eps, err = m.provider.SeasonEpisodes(ctx, s.tmdb, ps)
				if err != nil {
					m.logger.Warn("tmdb season fetch failed", "tmdb_id", s.tmdb, "season", ps, "err", err)
					failedSeasons[ps] = true
					continue
				}
				fetched[ps] = eps
			}
			// Key by the on-disk number so the write path never has to know
			// which of the two routes the metadata arrived by.
			byNum = make(map[int]metadata.EpisodeMeta, len(eps))
			for _, e := range eps {
				byNum[e.Number-plan.mapping.EpisodeOffset] = e
			}
		}

		if plan.source != "" {
			var pin *int
			if plan.status == seasonFromProviderSeason {
				n := plan.mapping.SeasonNumber
				pin = &n
			}
			if err := m.storeSeasonMapping(ctx, ls.id, pin, plan.mapping.EpisodeOffset, plan.source); err != nil {
				return count, unmapped, err
			}
		}
		n, err := m.storeSeasonEpisodes(ctx, ls.id, s.tmdb, ls.number, byNum, force)
		if err != nil {
			return count, unmapped, err
		}
		count += n
	}
	return count, unmapped, nil
}

// seasonResolver returns a per-series function deciding where each on-disk
// season's metadata comes from.
//
// Order is: an operator's pin, then a mapping already recorded as identity, then
// the provider's published ordering, then the provider's own season numbers,
// then reported as unmapped.
//
// The published ordering comes *before* matching season numbers deliberately. A
// season number existing on both sides does not mean it means the same thing —
// TMDB numbers Bleach {0,1,2}, so on-disk season 2 (TVDB's "The Entry" arc,
// which is TMDB S1 E21-E41) matches by number and would otherwise be handed
// Thousand-Year Blood War's episodes.
//
// Both provider lookups are memoized for the life of the closure, successes and
// failures alike, and the season list stays lazy behind the ordering — so a show
// the ordering fully covers never fetches one, and sixteen seasons of an
// unreachable series make one request and log one warning, not sixteen.
func (m *Matcher) seasonResolver(s seriesRow) func(context.Context, localSeason) seasonPlan {
	mapper, canMap := m.provider.(metadata.SeasonMapper)
	var (
		group         metadata.GroupedEpisodes
		groupLoaded   bool
		groupFailed   bool
		seasons       map[int]bool
		seasonsLoaded bool
		seasonsFailed bool
		goneReason    string // set when the provider permanently disowns the series
	)

	// load runs one provider lookup once, classifying a permanent answer (the
	// tmdb_id was merged away, the key was revoked) apart from an outage. A
	// permanent failure repeated every sweep forever is not something to keep
	// retrying quietly; it is something to report.
	load := func(what string, fn func() error) (ok bool, failed bool) {
		if err := fn(); err != nil {
			if metadata.IsPermanent(err) {
				goneReason = "the provider no longer has this series (" + err.Error() + ")"
				m.logger.Warn("tmdb permanently rejects this series",
					"series", s.title, "tmdb_id", s.tmdb, "lookup", what, "err", err)
				return false, true
			}
			m.logger.Warn("tmdb lookup failed", "series", s.title, "tmdb_id", s.tmdb, "lookup", what, "err", err)
			return false, true
		}
		return true, false
	}

	return func(ctx context.Context, ls localSeason) seasonPlan {
		src := ""
		if ls.source != nil {
			src = *ls.source
		}
		// An operator's pin is the last word. A pin with no provider season is
		// meaningful rather than incomplete: it is how "there is no counterpart,
		// leave the filenames alone" is expressed, and it must stop the resolver
		// rather than fall through to it.
		if src == "manual" {
			if ls.provider == nil {
				return seasonPlan{status: seasonLeftAlone}
			}
			return seasonPlan{
				status:  seasonFromProviderSeason,
				mapping: metadata.SeasonMapping{SeasonNumber: *ls.provider, EpisodeOffset: ls.offset},
			}
		}
		identity := seasonPlan{
			status:  seasonFromProviderSeason,
			mapping: metadata.SeasonMapping{SeasonNumber: ls.number},
			source:  "identity",
		}
		// A provider that can't describe its own ordering is one we have no way
		// to check — use the on-disk number directly, as this code did before
		// ARGY-224, and record nothing.
		if !canMap {
			return seasonPlan{status: seasonFromProviderSeason,
				mapping: metadata.SeasonMapping{SeasonNumber: ls.number}}
		}
		// A season already settled as identity needs no provider lookups to
		// settle again: new files landing in it get the same treatment as their
		// siblings, which is what makes the recorded mapping worth recording.
		if src == "identity" && ls.provider != nil {
			return seasonPlan{
				status:  seasonFromProviderSeason,
				mapping: metadata.SeasonMapping{SeasonNumber: *ls.provider, EpisodeOffset: ls.offset},
			}
		}

		if !groupLoaded && !groupFailed {
			var ok bool
			ok, groupFailed = load("episode_groups", func() error {
				g, err := mapper.SeriesEpisodeGroup(ctx, s.tmdb)
				group = g
				return err
			})
			groupLoaded = ok
		}
		if goneReason != "" {
			return seasonPlan{status: seasonUnmapped, reason: goneReason}
		}
		if groupFailed {
			return seasonPlan{status: seasonUnavailable}
		}
		if eps, ok := group[ls.number]; ok {
			return seasonPlan{status: seasonFromGroup, episodes: eps, source: "episode_group"}
		}

		// Nothing published for this season, so the provider's own numbering is
		// the only claim left, and matching numbers are all there is to go on.
		if !seasonsLoaded && !seasonsFailed {
			var ok bool
			ok, seasonsFailed = load("series_detail", func() error {
				refs, err := mapper.SeriesSeasons(ctx, s.tmdb)
				if err != nil {
					return err
				}
				seasons = make(map[int]bool, len(refs))
				for _, r := range refs {
					seasons[r.Number] = true
				}
				return nil
			})
			seasonsLoaded = ok
		}
		if goneReason != "" {
			return seasonPlan{status: seasonUnmapped, reason: goneReason}
		}
		if seasonsFailed {
			return seasonPlan{status: seasonUnavailable}
		}
		if seasons[ls.number] {
			return identity
		}
		reason := "the provider has no season " + strconv.Itoa(ls.number)
		if len(group) > 0 {
			reason += " and its published ordering does not cover one"
		} else {
			reason += " and it publishes no TVDB ordering"
		}
		return seasonPlan{status: seasonUnmapped, reason: reason}
	}
}

// storeSeasonMapping records how an on-disk season was resolved. providerSeason
// is nil for a verdict that pins no season — episodes taken from the published
// ordering, or none found at all.
//
// The manual guard is belt-and-braces: the resolver already returns early on an
// operator-set row, so that no future caller can quietly overwrite a hand-fixed
// mapping.
func (m *Matcher) storeSeasonMapping(ctx context.Context, seasonID string, providerSeason *int, offset int, source string) error {
	_, err := m.pool.Exec(ctx,
		`UPDATE seasons SET provider_season_number = $2, provider_episode_offset = $3,
		        provider_season_source = $4, updated_at = now()
		  WHERE id = $1 AND provider_season_source IS DISTINCT FROM 'manual'`,
		seasonID, providerSeason, offset, source)
	return err
}

// storeSeasonEpisodes writes provider metadata onto the episode rows of one
// season. byNum is keyed by the episode number **on disk**, whichever route the
// metadata arrived by, so nothing here needs to know about provider numbering.
// Each combined-file row (several numbers sharing one media_item) is matched
// independently, so E01 and E02 of a merged rip each get their own metadata.
func (m *Matcher) storeSeasonEpisodes(ctx context.Context, seasonID string, tmdbID int64, seasonNum int, byNum map[int]metadata.EpisodeMeta, force bool) (int, error) {
	epQ := `SELECT id::text, episode_number FROM episodes WHERE season_id = $1`
	if !force {
		epQ += ` AND provider_metadata = '{}'::jsonb`
	}
	rows, err := m.pool.Query(ctx, epQ, seasonID)
	if err != nil {
		return 0, err
	}
	type epRow struct {
		id  string
		num int
	}
	var epRows []epRow
	for rows.Next() {
		var e epRow
		if err := rows.Scan(&e.id, &e.num); err != nil {
			rows.Close()
			return 0, err
		}
		epRows = append(epRows, e)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}

	count := 0
	for _, e := range epRows {
		meta, ok := byNum[e.num]
		if !ok {
			continue
		}

		stillRel := ""
		if meta.StillURL != "" {
			// Named by the season and episode **on disk**. Provider coordinates
			// would be the obvious choice but aren't stable across a re-resolve,
			// and for the identity case — every library that predates ARGY-224 —
			// on-disk coordinates are the path the artwork already lives at.
			stillRel = path.Join("episodes", fmt.Sprintf("%d-s%de%d.jpg", tmdbID, seasonNum, e.num))
			dest := filepath.Join(m.artworkDir, filepath.FromSlash(stillRel))
			if err := m.download(ctx, meta.StillURL, dest); err != nil {
				m.logger.Warn("episode still download failed", "url", meta.StillURL, "err", err)
				stillRel = ""
			}
		}

		pm := map[string]any{"source": "tmdb"}
		if meta.Overview != "" {
			pm["overview"] = meta.Overview
		}
		if stillRel != "" {
			pm["still"] = stillRel
		}
		// rating powers the per-episode ⭐ on series detail (ARGY-118); omit when
		// the provider has no votes so unrated episodes don't carry a bogus 0.
		if meta.VoteCount > 0 {
			pm["vote_average"] = meta.VoteAverage
			pm["vote_count"] = meta.VoteCount
		}
		raw, err := json.Marshal(pm)
		if err != nil {
			return count, err
		}

		// Replace the SxxExx filename fallback with the real episode name; keep
		// the existing title when the provider has no name so we never blank it.
		if _, err := m.pool.Exec(ctx,
			`UPDATE episodes SET title = COALESCE(NULLIF($2, ''), title), provider_metadata = $3, updated_at = now() WHERE id = $1`,
			e.id, meta.Name, raw); err != nil {
			return count, err
		}
		count++
	}
	return count, nil
}

func (m *Matcher) collect(ctx context.Context, query, libraryID string) ([]matchItem, error) {
	rows, err := m.pool.Query(ctx, query, libraryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []matchItem
	for rows.Next() {
		var it matchItem
		var year *int
		if err := rows.Scan(&it.id, &it.title, &year); err != nil {
			return nil, err
		}
		if year != nil {
			it.year = *year
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func (m *Matcher) store(ctx context.Context, table, artworkSub, id string, match *metadata.Match) error {
	posterRel := ""
	if match.PosterURL != "" {
		posterRel = path.Join(artworkSub, fmt.Sprintf("%d.jpg", match.TMDBID))
		dest := filepath.Join(m.artworkDir, filepath.FromSlash(posterRel))
		if err := m.download(ctx, match.PosterURL, dest); err != nil {
			m.logger.Warn("poster download failed", "url", match.PosterURL, "err", err)
			posterRel = ""
		}
	}

	backdropRel := ""
	if match.BackdropURL != "" {
		backdropRel = path.Join(artworkSub, fmt.Sprintf("%d-backdrop.jpg", match.TMDBID))
		dest := filepath.Join(m.artworkDir, filepath.FromSlash(backdropRel))
		if err := m.download(ctx, match.BackdropURL, dest); err != nil {
			m.logger.Warn("backdrop download failed", "url", match.BackdropURL, "err", err)
			backdropRel = ""
		}
	}

	pm := map[string]any{
		"source":    "tmdb",
		"tmdb_id":   match.TMDBID,
		"title":     match.Title,
		"year":      match.Year,
		"overview":  match.Overview,
		"genre_ids": match.GenreIDs,
	}
	// genres (names) and rating power the genre + rating filters; omit when absent
	// so unmatched/unrated items don't carry empty facets.
	if len(match.Genres) > 0 {
		pm["genres"] = match.Genres
	}
	if match.VoteCount > 0 {
		pm["vote_average"] = match.VoteAverage
		pm["vote_count"] = match.VoteCount
	}
	if posterRel != "" {
		pm["poster"] = posterRel
	}
	if backdropRel != "" {
		pm["backdrop"] = backdropRel
	}
	raw, err := json.Marshal(pm)
	if err != nil {
		return err
	}

	var query string
	switch table {
	case "media_items":
		query = `UPDATE media_items SET tmdb_id = $2, provider_metadata = $3, year = COALESCE($4, year), updated_at = now() WHERE id = $1`
	case "series":
		query = `UPDATE series SET tmdb_id = $2, provider_metadata = $3, year = COALESCE($4, year), updated_at = now() WHERE id = $1`
	default:
		return fmt.Errorf("unknown table %q", table)
	}

	var yearArg any
	if match.Year > 0 {
		yearArg = match.Year
	}
	_, err = m.pool.Exec(ctx, query, id, match.TMDBID, raw, yearArg)
	return err
}
