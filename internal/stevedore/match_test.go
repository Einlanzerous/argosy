package stevedore

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/metadata"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

type fakeProvider struct{}

func (fakeProvider) SearchMovie(_ context.Context, title string, _ int) (*metadata.Match, error) {
	return &metadata.Match{TMDBID: 111, Title: "Matched " + title, Year: 2008, Overview: "ov", PosterURL: "http://x/p.jpg", GenreIDs: []int{16}}, nil
}
func (fakeProvider) SearchSeries(_ context.Context, title string) (*metadata.Match, error) {
	return &metadata.Match{TMDBID: 222, Title: "Matched " + title, Year: 2020, Overview: "sv"}, nil
}
func (fakeProvider) SeasonEpisodes(_ context.Context, _ int64, season int) ([]metadata.EpisodeMeta, error) {
	return []metadata.EpisodeMeta{
		{Number: 1, Name: "Pilot", Overview: "the first one", StillURL: "http://x/s" + strconv.Itoa(season) + "e1.jpg"},
		{Number: 2, Name: "The Second", Overview: "the next one"},
	}, nil
}
func (fakeProvider) MovieCredits(_ context.Context, _ int64) ([]string, error) {
	return []string{"Ada Lovelace", "Alan Turing"}, nil
}
func (fakeProvider) SeriesCredits(_ context.Context, _ int64) ([]string, error) {
	return []string{"Grace Hopper"}, nil
}

// downloadingProvider also implements metadata.ImageDownloader, recording
// what the matcher asks it to fetch.
type downloadingProvider struct {
	fakeProvider
	got []string
}

func (d *downloadingProvider) DownloadImage(_ context.Context, rawURL, _ string) error {
	d.got = append(d.got, rawURL)
	return nil
}

// TestMatcherPrefersProviderDownloader pins the ARGY-141 wiring: when the
// provider can download artwork itself (paced + retried), the matcher must
// route image fetches through it instead of its own plain client.
func TestMatcherPrefersProviderDownloader(t *testing.T) {
	p := &downloadingProvider{}
	m := NewMatcher(nil, p, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	if err := m.download(context.Background(), "http://x/p.jpg", "/dev/null"); err != nil {
		t.Fatalf("download: %v", err)
	}
	if len(p.got) != 1 || p.got[0] != "http://x/p.jpg" {
		t.Errorf("provider downloader saw %v, want the requested URL", p.got)
	}
}

func TestMatchLibrary(t *testing.T) {
	dsn := testdb.DSN(t)
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "mat_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO media_items (library_id, kind, title, year, file_path) VALUES ($1,'movie','Big Buck Bunny',2008,$2)`,
		libID, "bbb-"+suffix+".mkv"); err != nil {
		t.Fatal(err)
	}
	var seriesID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'My Show','my show') RETURNING id::text`, libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	// A season with two episodes, both backed by one combined file (shared
	// media_item) — each number should still get its own TMDB metadata.
	var seasonID, comboItem string
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','My Show S01E01-E02',$2) RETURNING id::text`,
		libID, "combo-"+suffix+".mkv").Scan(&comboItem); err != nil {
		t.Fatal(err)
	}
	for _, n := range []int{1, 2} {
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
			seasonID, n, comboItem, "My Show S01E0"+strconv.Itoa(n)); err != nil {
			t.Fatal(err)
		}
	}

	m := NewMatcher(pool, fakeProvider{}, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	m.download = func(context.Context, string, string) error { return nil } // no network

	res, err := m.MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Movies != 1 || res.Series != 1 {
		t.Fatalf("result = %+v, want 1 movie / 1 series", res)
	}

	var movieTMDB *int64
	var pm []byte
	if err := pool.QueryRow(ctx, `SELECT tmdb_id, provider_metadata FROM media_items WHERE library_id=$1 AND kind='movie'`, libID).Scan(&movieTMDB, &pm); err != nil {
		t.Fatal(err)
	}
	if movieTMDB == nil || *movieTMDB != 111 {
		t.Fatalf("movie tmdb_id = %v, want 111", movieTMDB)
	}
	var meta map[string]any
	if err := json.Unmarshal(pm, &meta); err != nil {
		t.Fatalf("provider_metadata not valid json: %v", err)
	}
	if meta["source"] != "tmdb" || meta["title"] != "Matched Big Buck Bunny" || meta["poster"] != "movies/111.jpg" {
		t.Fatalf("provider_metadata = %v", meta)
	}
	// Cast was backfilled for people search (ARGY-67).
	if res.Credits != 2 {
		t.Fatalf("res.Credits = %d, want 2 (movie + series)", res.Credits)
	}
	cast, _ := meta["cast"].([]any)
	if len(cast) != 2 || cast[0] != "Ada Lovelace" {
		t.Fatalf("movie cast = %v, want [Ada Lovelace Alan Turing]", meta["cast"])
	}
	// The cast names are searchable: the STORED search_vector matched on a query
	// (weight B, like genres) and ranks below a title hit (weight A).
	var hits int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM media_items WHERE library_id=$1 AND search_vector @@ to_tsquery('simple', 'lovelace:*')`,
		libID).Scan(&hits); err != nil {
		t.Fatal(err)
	}
	if hits != 1 {
		t.Fatalf("cast search hits = %d, want 1", hits)
	}

	var seriesTMDB *int64
	if err := pool.QueryRow(ctx, `SELECT tmdb_id FROM series WHERE library_id=$1`, libID).Scan(&seriesTMDB); err != nil {
		t.Fatal(err)
	}
	if seriesTMDB == nil || *seriesTMDB != 222 {
		t.Fatalf("series tmdb_id = %v, want 222", seriesTMDB)
	}

	// Per-episode metadata: both numbers of the combined file enriched, each
	// with its own name + provider_metadata overview.
	if res.Episodes != 2 {
		t.Fatalf("res.Episodes = %d, want 2", res.Episodes)
	}
	for n, wantTitle := range map[int]string{1: "Pilot", 2: "The Second"} {
		var title string
		var epm []byte
		if err := pool.QueryRow(ctx, `SELECT e.title, e.provider_metadata FROM episodes e JOIN seasons se ON se.id=e.season_id WHERE se.series_id=$1 AND e.episode_number=$2`,
			seriesID, n).Scan(&title, &epm); err != nil {
			t.Fatal(err)
		}
		if title != wantTitle {
			t.Fatalf("episode %d title = %q, want %q", n, title, wantTitle)
		}
		var em map[string]any
		if err := json.Unmarshal(epm, &em); err != nil {
			t.Fatalf("episode %d provider_metadata not json: %v", n, err)
		}
		if em["source"] != "tmdb" || em["overview"] == nil {
			t.Fatalf("episode %d provider_metadata = %v", n, em)
		}
	}

	// idempotent (no force): already matched, so nothing re-matched and no
	// episodes re-enriched (provider_metadata already populated).
	res2, err := m.MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatal(err)
	}
	if res2.Movies != 0 || res2.Series != 0 || res2.Episodes != 0 || res2.Credits != 0 {
		t.Fatalf("second run matched %+v, want 0/0/0/0 (already matched + cast cached)", res2)
	}
}

// mappingProvider models a provider whose season numbering disagrees with the
// library's — TMDB against Sonarr's TVDB-shaped folders (ARGY-224). Seasons and
// alt are the two documents the resolver reads; the call counters pin that each
// is fetched at most once per series.
type mappingProvider struct {
	fakeProvider
	seasons     []int
	alt         map[int]metadata.SeasonMapping
	seasonCalls int
	altCalls    int
	epCalls     []int // provider season numbers SeasonEpisodes was asked for
}

func (p *mappingProvider) SeriesSeasons(_ context.Context, _ int64) ([]metadata.SeasonRef, error) {
	p.seasonCalls++
	out := make([]metadata.SeasonRef, 0, len(p.seasons))
	for _, n := range p.seasons {
		out = append(out, metadata.SeasonRef{Number: n})
	}
	return out, nil
}

func (p *mappingProvider) AlternateSeasonMap(_ context.Context, _ int64) (map[int]metadata.SeasonMapping, error) {
	p.altCalls++
	return p.alt, nil
}

// SeasonEpisodes returns 60 episodes named for their provider coordinates, so a
// wrong season or a dropped offset shows up as a wrong title rather than as an
// absence.
func (p *mappingProvider) SeasonEpisodes(_ context.Context, _ int64, season int) ([]metadata.EpisodeMeta, error) {
	p.epCalls = append(p.epCalls, season)
	eps := make([]metadata.EpisodeMeta, 0, 60)
	for n := 1; n <= 60; n++ {
		eps = append(eps, metadata.EpisodeMeta{
			Number:   n,
			Name:     fmt.Sprintf("s%de%d", season, n),
			Overview: "ov",
		})
	}
	return eps, nil
}

// mappingFixture builds a library with one matched series and the given on-disk
// seasons, each holding episodes 1..episodesPerSeason.
func mappingFixture(t *testing.T, pool *pgxpool.Pool, seasonNums []int, episodesPerSeason int) (libID, seriesID string) {
	t.Helper()
	ctx := context.Background()
	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "map_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'show',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	// Already matched at the series level: that is the shape of the bug — the
	// show has a tmdb_id and full artwork, and only its episodes are empty.
	if err := pool.QueryRow(ctx,
		`INSERT INTO series (library_id, title, sort_title, tmdb_id) VALUES ($1,'Bleach','bleach',30984) RETURNING id::text`,
		libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	for _, sn := range seasonNums {
		var seasonID string
		if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,$2) RETURNING id::text`,
			seriesID, sn).Scan(&seasonID); err != nil {
			t.Fatal(err)
		}
		for n := 1; n <= episodesPerSeason; n++ {
			var itemID string
			if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
				libID, fmt.Sprintf("Bleach - S%02dE%02d - THE BLOOD WARFARE Bluray-1080p", sn, n),
				fmt.Sprintf("bleach-%s-s%de%d.mkv", suffix, sn, n)).Scan(&itemID); err != nil {
				t.Fatal(err)
			}
			if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
				seasonID, n, itemID, fmt.Sprintf("Bleach - S%02dE%02d - THE BLOOD WARFARE Bluray-1080p", sn, n)); err != nil {
				t.Fatal(err)
			}
		}
	}
	return libID, seriesID
}

func mappingPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := testdb.DSN(t)
	ctx := context.Background()
	if err := db.Migrate(ctx, dsn); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func newMappingMatcher(t *testing.T, pool *pgxpool.Pool, p metadata.Provider) *Matcher {
	t.Helper()
	m := NewMatcher(pool, p, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	m.download = func(context.Context, string, string) error { return nil }
	return m
}

// episodeTitles reads back the on-disk episode numbers and their titles for one
// on-disk season.
func episodeTitles(t *testing.T, pool *pgxpool.Pool, seriesID string, seasonNum int) map[int]string {
	t.Helper()
	rows, err := pool.Query(context.Background(),
		`SELECT e.episode_number, e.title FROM episodes e JOIN seasons se ON se.id = e.season_id
		  WHERE se.series_id = $1 AND se.season_number = $2`, seriesID, seasonNum)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	out := map[int]string{}
	for rows.Next() {
		var n int
		var title string
		if err := rows.Scan(&n, &title); err != nil {
			t.Fatal(err)
		}
		out[n] = title
	}
	return out
}

func seasonMapping(t *testing.T, pool *pgxpool.Pool, seriesID string, seasonNum int) (provider *int, offset int, source *string) {
	t.Helper()
	if err := pool.QueryRow(context.Background(),
		`SELECT provider_season_number, provider_episode_offset, provider_season_source
		   FROM seasons WHERE series_id = $1 AND season_number = $2`, seriesID, seasonNum).
		Scan(&provider, &offset, &source); err != nil {
		t.Fatal(err)
	}
	return provider, offset, source
}

// TestMatchSeasonTranslatedThroughEpisodeGroup is ARGY-224's headline case:
// Bleach's Thousand-Year Blood War sits under Season 17 on disk (TVDB's
// numbering, which is Sonarr's) and is season 2 at TMDB. Asking for season 17
// finds nothing, so every episode kept its filename. The provider's own
// TVDB-ordered episode group supplies the translation.
func TestMatchSeasonTranslatedThroughEpisodeGroup(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{17}, 3)

	p := &mappingProvider{
		seasons: []int{0, 1, 2},
		alt:     map[int]metadata.SeasonMapping{17: {SeasonNumber: 2, EpisodeOffset: 0}},
	}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 3 {
		t.Fatalf("res.Episodes = %d, want 3", res.Episodes)
	}
	if len(res.Unmapped) != 0 {
		t.Fatalf("res.Unmapped = %+v, want none", res.Unmapped)
	}
	got := episodeTitles(t, pool, seriesID, 17)
	for n, want := range map[int]string{1: "s2e1", 2: "s2e2", 3: "s2e3"} {
		if got[n] != want {
			t.Errorf("S17E%02d title = %q, want %q", n, got[n], want)
		}
	}
	// The translation is persisted, so it is stable and inspectable rather than
	// re-derived (and re-charged to TMDB) on every sweep.
	provider, offset, source := seasonMapping(t, pool, seriesID, 17)
	if provider == nil || *provider != 2 || offset != 0 || source == nil || *source != "episode_group" {
		t.Errorf("season 17 mapping = %v/%d/%v, want 2/0/episode_group", provider, offset, source)
	}
	// The episode list was fetched for the *provider's* season, not ours.
	if len(p.epCalls) != 1 || p.epCalls[0] != 2 {
		t.Errorf("SeasonEpisodes calls = %v, want [2]", p.epCalls)
	}
}

// TestMatchSeasonOffsetIntoProviderSeason covers the case a season number alone
// cannot express: TVDB splits Bleach's first 366 episodes across sixteen
// seasons that TMDB keeps as one. On-disk S03E01 is TMDB S01E42, and several
// on-disk seasons resolve to the same provider season — which must be fetched
// once, not once each.
func TestMatchSeasonOffsetIntoProviderSeason(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{3, 4}, 2)

	p := &mappingProvider{
		seasons: []int{0, 1, 2},
		alt: map[int]metadata.SeasonMapping{
			3: {SeasonNumber: 1, EpisodeOffset: 41},
			4: {SeasonNumber: 1, EpisodeOffset: 43},
		},
	}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 4 {
		t.Fatalf("res.Episodes = %d, want 4", res.Episodes)
	}
	s3 := episodeTitles(t, pool, seriesID, 3)
	if s3[1] != "s1e42" || s3[2] != "s1e43" {
		t.Errorf("S03 titles = %v, want E01=s1e42 E02=s1e43", s3)
	}
	s4 := episodeTitles(t, pool, seriesID, 4)
	if s4[1] != "s1e44" || s4[2] != "s1e45" {
		t.Errorf("S04 titles = %v, want E01=s1e44 E02=s1e45", s4)
	}
	if len(p.epCalls) != 1 || p.epCalls[0] != 1 {
		t.Errorf("SeasonEpisodes calls = %v, want a single fetch of provider season 1", p.epCalls)
	}
	// One episode-group fetch for the series, and no season list at all: the
	// group covered every season, so nothing had to fall back to identity.
	if p.altCalls != 1 || p.seasonCalls != 0 {
		t.Errorf("provider lookups = %d episode groups / %d season lists, want 1 / 0", p.altCalls, p.seasonCalls)
	}
}

// TestMatchIdentitySeasonUnchanged is the regression guard for every title whose
// numbering already agrees — SAO, Andor, Planet Earth II. They must keep going
// straight to their own season number, and must not cost an episode-group fetch.
func TestMatchIdentitySeasonUnchanged(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{1, 2}, 2)

	p := &mappingProvider{seasons: []int{1, 2}}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 4 || len(res.Unmapped) != 0 {
		t.Fatalf("res = %d episodes / %+v unmapped, want 4 / none", res.Episodes, res.Unmapped)
	}
	if got := episodeTitles(t, pool, seriesID, 2); got[1] != "s2e1" {
		t.Errorf("S02E01 title = %q, want s2e1", got[1])
	}
	// The group is consulted first now (it is the authoritative table), so it is
	// fetched exactly once and found to publish nothing; identity then applies.
	if p.altCalls != 1 || p.seasonCalls != 1 {
		t.Errorf("provider lookups = %d episode groups / %d season lists, want 1 each per series", p.altCalls, p.seasonCalls)
	}
	provider, offset, source := seasonMapping(t, pool, seriesID, 2)
	if provider == nil || *provider != 2 || offset != 0 || source == nil || *source != "identity" {
		t.Errorf("season 2 mapping = %v/%d/%v, want 2/0/identity", provider, offset, source)
	}
}

// TestMatchUnmappedSeasonReported is the other half of the bug: a season the
// provider genuinely has no counterpart for must be *reported*, not silently
// left empty. The series still matches, so nothing else in the system would say
// why the episodes are blank.
func TestMatchUnmappedSeasonReported(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{17}, 3)

	p := &mappingProvider{seasons: []int{0, 1, 2}} // no episode group published
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 0 {
		t.Fatalf("res.Episodes = %d, want 0", res.Episodes)
	}
	if len(res.Unmapped) != 1 {
		t.Fatalf("res.Unmapped = %+v, want exactly one season", res.Unmapped)
	}
	u := res.Unmapped[0]
	if u.SeriesID != seriesID || u.SeriesTitle != "Bleach" || u.SeasonNumber != 17 || u.Episodes != 3 {
		t.Errorf("unmapped = %+v, want Bleach season 17 with 3 episodes", u)
	}
	// Nothing was guessed: the filename fallback stands rather than being
	// overwritten with a plausible-looking wrong title.
	if got := episodeTitles(t, pool, seriesID, 17); !strings.Contains(got[1], "S17E01") {
		t.Errorf("S17E01 title = %q, want the filename fallback left intact", got[1])
	}
	provider, _, source := seasonMapping(t, pool, seriesID, 17)
	if provider != nil || source != nil {
		t.Errorf("unmapped season recorded %v/%v, want both NULL", provider, source)
	}
}

// TestMatchManualSeasonMappingWins pins the operator escape hatch: a mapping set
// by hand is used as-is and never overwritten by the automatic pass, even when
// the provider would have resolved the season differently.
func TestMatchManualSeasonMappingWins(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{17}, 2)
	if _, err := pool.Exec(ctx,
		`UPDATE seasons SET provider_season_number = 2, provider_episode_offset = 10,
		        provider_season_source = 'manual' WHERE series_id = $1 AND season_number = 17`,
		seriesID); err != nil {
		t.Fatal(err)
	}

	// The provider would map season 17 at no offset; the operator's +10 must win.
	p := &mappingProvider{
		seasons: []int{0, 1, 2},
		alt:     map[int]metadata.SeasonMapping{17: {SeasonNumber: 2, EpisodeOffset: 0}},
	}
	if _, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false); err != nil {
		t.Fatalf("match: %v", err)
	}
	if got := episodeTitles(t, pool, seriesID, 17); got[1] != "s2e11" {
		t.Errorf("S17E01 title = %q, want s2e11 from the manual +10 offset", got[1])
	}
	provider, offset, source := seasonMapping(t, pool, seriesID, 17)
	if provider == nil || *provider != 2 || offset != 10 || source == nil || *source != "manual" {
		t.Errorf("mapping = %v/%d/%v, want the operator's 2/10/manual left alone", provider, offset, source)
	}
	// A manual mapping is trusted without asking the provider anything.
	if p.seasonCalls != 0 || p.altCalls != 0 {
		t.Errorf("provider consulted (%d/%d) for a hand-set mapping", p.seasonCalls, p.altCalls)
	}
}

// TestMatchEpisodeGroupBeatsIdentity guards the ordering: a season number that
// exists on both sides does not mean it means the same thing, so the published
// TVDB-ordered translation must be consulted before falling back to identity.
//
// Bleach is the counterexample in its own right. TMDB numbers it {0,1,2}, so
// on-disk season 2 — TVDB's "The Entry" arc, which is TMDB S1 E21-E41 — matches
// a provider season *by number*. Resolving identity first would hand it
// Thousand-Year Blood War's episodes, which is precisely the confidently-wrong
// metadata this ticket exists to prevent.
func TestMatchEpisodeGroupBeatsIdentity(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{2, 3}, 2)

	p := &mappingProvider{
		seasons: []int{0, 1, 2}, // on-disk season 2 collides with the provider's
		alt: map[int]metadata.SeasonMapping{
			2: {SeasonNumber: 1, EpisodeOffset: 20},
			3: {SeasonNumber: 1, EpisodeOffset: 41},
		},
	}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 4 || len(res.Unmapped) != 0 {
		t.Fatalf("res = %d episodes / %+v unmapped, want 4 / none", res.Episodes, res.Unmapped)
	}
	s2 := episodeTitles(t, pool, seriesID, 2)
	if s2[1] != "s1e21" || s2[2] != "s1e22" {
		t.Errorf("S02 titles = %v, want E01=s1e21 E02=s1e22 (the group's answer, not provider season 2)", s2)
	}
	provider, offset, source := seasonMapping(t, pool, seriesID, 2)
	if provider == nil || *provider != 1 || offset != 20 || source == nil || *source != "episode_group" {
		t.Errorf("season 2 mapping = %v/%d/%v, want 1/20/episode_group", provider, offset, source)
	}
	// The provider's own season list is never needed for a season the group
	// covers, so it is not fetched at all.
	if p.seasonCalls != 0 {
		t.Errorf("season list fetched %d times; the group covered every season", p.seasonCalls)
	}
}

// failingMapper fails both provider-side lookups, standing in for TMDB being
// unreachable mid-sweep.
type failingMapper struct {
	fakeProvider
	seasonCalls int
	altCalls    int
}

func (p *failingMapper) SeriesSeasons(_ context.Context, _ int64) ([]metadata.SeasonRef, error) {
	p.seasonCalls++
	return nil, errors.New("tmdb unreachable")
}

func (p *failingMapper) AlternateSeasonMap(_ context.Context, _ int64) (map[int]metadata.SeasonMapping, error) {
	p.altCalls++
	return nil, errors.New("tmdb unreachable")
}

// TestMatchProviderUnavailableAsksOnce covers the difference between "the
// provider has no such season" and "we could not ask". A failed lookup must not
// be reported as unmapped — that would tell an operator a fact about the title
// that isn't true — and must not be retried once per season of the series.
func TestMatchProviderUnavailableAsksOnce(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{1, 2, 3}, 1)

	p := &failingMapper{}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 0 {
		t.Fatalf("res.Episodes = %d, want 0", res.Episodes)
	}
	if len(res.Unmapped) != 0 {
		t.Fatalf("res.Unmapped = %+v; a failed lookup is not a missing season", res.Unmapped)
	}
	if p.altCalls != 1 {
		t.Errorf("episode groups fetched %d times across 3 seasons, want 1", p.altCalls)
	}
	// Nothing was recorded, so the next sweep retries from scratch.
	provider, _, source := seasonMapping(t, pool, seriesID, 1)
	if provider != nil || source != nil {
		t.Errorf("recorded %v/%v for an unreachable provider, want both NULL", provider, source)
	}
}
