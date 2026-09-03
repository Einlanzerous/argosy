package stevedore

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"path"
	"path/filepath"
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
	if err != nil {
		return res, err
	}
	res.Episodes = n
	res.Unmapped = unmapped

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

// matchEpisodes fetches per-season episode lists from the provider for every
// matched series in the library and writes each episode's name + overview +
// still. Returns the number of episode rows enriched, plus the seasons whose
// numbering could not be translated onto the provider's (ARGY-224).
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
// whatever translation onto the provider's numbering is already recorded.
type localSeason struct {
	id       string
	number   int
	provider *int    // provider_season_number, NULL until resolved
	offset   int     // provider_episode_offset
	source   *string // identity | episode_group | manual
	episodes int     // episode rows still missing provider metadata
}

// seasonResolution distinguishes the two ways a season can end up without a
// provider mapping. Only one of them is worth telling an operator about: a
// failed lookup is transient and the next sweep retries it, while "the provider
// does not have this season" is a fact about the title that will not change on
// its own.
type seasonResolution int

const (
	seasonResolved    seasonResolution = iota // mapping usable
	seasonUnmapped                            // provider genuinely has no counterpart
	seasonUnavailable                         // provider lookup failed; retry next sweep
)

func (m *Matcher) matchSeriesEpisodes(ctx context.Context, s seriesRow, force bool) (int, []UnmappedSeason, error) {
	// Only the seasons with episodes still missing metadata (all of them when
	// force) — avoids re-hitting TMDB for already-enriched seasons on rescans.
	seasonQ := `SELECT se.id::text, se.season_number, se.provider_season_number,
	                   se.provider_episode_offset, se.provider_season_source, count(e.id)
	              FROM seasons se JOIN episodes e ON e.season_id = se.id
	             WHERE se.series_id = $1`
	if !force {
		seasonQ += ` AND e.provider_metadata = '{}'::jsonb`
	}
	seasonQ += ` GROUP BY se.id, se.season_number, se.provider_season_number,
	                      se.provider_episode_offset, se.provider_season_source`
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
	// Several on-disk seasons can land in the same provider season — TVDB splits
	// Bleach's first 366 episodes across sixteen of them, all of which are TMDB
	// season 1 — so the fetched episode list is cached per *provider* season.
	fetched := make(map[int][]metadata.EpisodeMeta)
	for _, ls := range seasons {
		mapping, status, err := resolve(ctx, ls)
		if err != nil {
			return count, unmapped, err
		}
		switch status {
		case seasonUnmapped:
			m.logger.Warn("season has no counterpart in the provider's numbering; episodes left without metadata",
				"series", s.title, "tmdb_id", s.tmdb, "season", ls.number, "episodes", ls.episodes)
			unmapped = append(unmapped, UnmappedSeason{
				SeriesID:     s.id,
				SeriesTitle:  s.title,
				SeasonNumber: ls.number,
				Episodes:     ls.episodes,
			})
			continue
		case seasonUnavailable:
			continue
		}

		eps, ok := fetched[mapping.SeasonNumber]
		if !ok {
			eps, err = m.provider.SeasonEpisodes(ctx, s.tmdb, mapping.SeasonNumber)
			if err != nil {
				m.logger.Warn("tmdb season fetch failed", "tmdb_id", s.tmdb, "season", mapping.SeasonNumber, "err", err)
				continue
			}
			fetched[mapping.SeasonNumber] = eps
		}
		byNum := make(map[int]metadata.EpisodeMeta, len(eps))
		for _, e := range eps {
			byNum[e.Number] = e
		}
		n, err := m.storeSeasonEpisodes(ctx, ls.id, s.tmdb, mapping, byNum, force)
		if err != nil {
			return count, unmapped, err
		}
		count += n
	}
	return count, unmapped, nil
}

// seasonResolver returns a per-series function that translates an on-disk season
// onto the provider's numbering, persisting what it works out so the mapping is
// stable and inspectable afterwards.
//
// The provider-side lookups are lazy and memoized across the closure's lifetime:
// a library whose numbering already agrees with the provider's — which is most of
// them — costs one extra request per series, and the episode-group fetch happens
// only for a series that actually has a season needing translation.
func (m *Matcher) seasonResolver(s seriesRow) func(context.Context, localSeason) (metadata.SeasonMapping, seasonResolution, error) {
	mapper, canMap := m.provider.(metadata.SeasonMapper)
	var providerSeasons map[int]bool
	var altMap map[int]metadata.SeasonMapping
	var altFetched bool

	return func(ctx context.Context, ls localSeason) (metadata.SeasonMapping, seasonResolution, error) {
		// An operator's mapping is the last word — the automatic pass never
		// overwrites it, and never second-guesses it either.
		if ls.source != nil && *ls.source == "manual" && ls.provider != nil {
			return metadata.SeasonMapping{SeasonNumber: *ls.provider, EpisodeOffset: ls.offset}, seasonResolved, nil
		}
		identity := metadata.SeasonMapping{SeasonNumber: ls.number, EpisodeOffset: 0}
		// A provider that can't describe its own season list is one whose
		// numbering we have no way to check — use the on-disk number directly,
		// exactly as this code did before ARGY-224, and record nothing.
		if !canMap {
			return identity, seasonResolved, nil
		}

		if providerSeasons == nil {
			refs, err := mapper.SeriesSeasons(ctx, s.tmdb)
			if err != nil {
				m.logger.Warn("tmdb season list fetch failed", "series", s.title, "tmdb_id", s.tmdb, "err", err)
				return metadata.SeasonMapping{}, seasonUnavailable, nil
			}
			providerSeasons = make(map[int]bool, len(refs))
			for _, r := range refs {
				providerSeasons[r.Number] = true
			}
		}
		if providerSeasons[ls.number] {
			return identity, seasonResolved, m.storeSeasonMapping(ctx, ls.id, identity, "identity")
		}

		// No counterpart at the same number: ask the provider for its TVDB-ordered
		// translation, which is the numbering the folders on disk actually came in.
		if !altFetched {
			altFetched = true
			var err error
			if altMap, err = mapper.AlternateSeasonMap(ctx, s.tmdb); err != nil {
				m.logger.Warn("tmdb episode-group fetch failed", "series", s.title, "tmdb_id", s.tmdb, "err", err)
				altMap = nil
				altFetched = false
				return metadata.SeasonMapping{}, seasonUnavailable, nil
			}
		}
		if mp, ok := altMap[ls.number]; ok {
			return mp, seasonResolved, m.storeSeasonMapping(ctx, ls.id, mp, "episode_group")
		}
		return metadata.SeasonMapping{}, seasonUnmapped, nil
	}
}

// storeSeasonMapping records how an on-disk season maps onto the provider's
// numbering. The manual guard is belt-and-braces — the resolver already returns
// early on an operator-set row — so that no future caller can quietly overwrite
// a hand-fixed mapping.
func (m *Matcher) storeSeasonMapping(ctx context.Context, seasonID string, mp metadata.SeasonMapping, source string) error {
	_, err := m.pool.Exec(ctx,
		`UPDATE seasons SET provider_season_number = $2, provider_episode_offset = $3,
		        provider_season_source = $4, updated_at = now()
		  WHERE id = $1 AND provider_season_source IS DISTINCT FROM 'manual'`,
		seasonID, mp.SeasonNumber, mp.EpisodeOffset, source)
	return err
}

// storeSeasonEpisodes writes provider metadata onto the episode rows of one
// season, matching each on-disk episode number to the provider's through the
// season's mapping. Each combined-file row (several numbers sharing one
// media_item) is matched independently, so E01 and E02 of a merged rip each get
// their own name/overview/still.
func (m *Matcher) storeSeasonEpisodes(ctx context.Context, seasonID string, tmdbID int64, mapping metadata.SeasonMapping, byNum map[int]metadata.EpisodeMeta, force bool) (int, error) {
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
		providerNum := e.num + mapping.EpisodeOffset
		meta, ok := byNum[providerNum]
		if !ok {
			continue
		}

		stillRel := ""
		if meta.StillURL != "" {
			// Named by the *provider's* coordinates, so two on-disk seasons
			// folded into one provider season can't collide, and an identity
			// mapping keeps writing to exactly the path it always has.
			stillRel = path.Join("episodes", fmt.Sprintf("%d-s%de%d.jpg", tmdbID, mapping.SeasonNumber, providerNum))
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
		// the existing title when TMDB has no name so we never blank it out.
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
