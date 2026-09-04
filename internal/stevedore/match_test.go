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

// mappingProvider models a provider whose ordering disagrees with the library's
// — TMDB against Sonarr's TVDB-shaped folders (ARGY-224). seasons and group are
// the two documents the resolver reads; the counters pin that each is fetched at
// most once per series.
type mappingProvider struct {
	fakeProvider
	seasons     []int
	group       metadata.GroupedEpisodes
	seasonErr   error
	groupErr    error
	seasonCalls int
	groupCalls  int
	epCalls     []int // provider season numbers SeasonEpisodes was asked for
}

func (p *mappingProvider) SeriesSeasons(_ context.Context, _ int64) ([]metadata.SeasonRef, error) {
	p.seasonCalls++
	if p.seasonErr != nil {
		return nil, p.seasonErr
	}
	out := make([]metadata.SeasonRef, 0, len(p.seasons))
	for _, n := range p.seasons {
		out = append(out, metadata.SeasonRef{Number: n})
	}
	return out, nil
}

func (p *mappingProvider) SeriesEpisodeGroup(_ context.Context, _ int64) (metadata.GroupedEpisodes, error) {
	p.groupCalls++
	if p.groupErr != nil {
		return nil, p.groupErr
	}
	return p.group, nil
}

// SeasonEpisodes returns episodes named for their provider coordinates, so a
// wrong season shows up as a wrong title rather than as an absence.
func (p *mappingProvider) SeasonEpisodes(_ context.Context, _ int64, season int) ([]metadata.EpisodeMeta, error) {
	p.epCalls = append(p.epCalls, season)
	eps := make([]metadata.EpisodeMeta, 0, 60)
	for n := 1; n <= 60; n++ {
		eps = append(eps, metadata.EpisodeMeta{
			Number: n, Name: fmt.Sprintf("s%de%d", season, n), Overview: "ov",
		})
	}
	return eps, nil
}

// grouped builds a GroupedEpisodes entry whose names record where each episode
// came from, so a mis-keyed season is visible in the title.
func grouped(label string, n int) []metadata.EpisodeMeta {
	eps := make([]metadata.EpisodeMeta, 0, n)
	for i := 1; i <= n; i++ {
		eps = append(eps, metadata.EpisodeMeta{
			Number: i, Name: fmt.Sprintf("%s-%d", label, i), Overview: "ov",
		})
	}
	return eps
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

func srcOf(source *string) string {
	if source == nil {
		return "<null>"
	}
	return *source
}

// TestMatchSeasonFromEpisodeGroup is ARGY-224's headline case: Bleach's
// Thousand-Year Blood War sits under Season 17 on disk (TVDB's numbering, which
// is Sonarr's) and is season 2 at TMDB. Asking for season 17 finds nothing, so
// every episode kept its filename. The provider's published TVDB ordering
// supplies the episodes directly.
func TestMatchSeasonFromEpisodeGroup(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{17}, 3)

	p := &mappingProvider{
		seasons: []int{0, 1, 2},
		group:   metadata.GroupedEpisodes{17: grouped("tybw", 3)},
	}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 3 || len(res.Unmapped) != 0 {
		t.Fatalf("res = %d episodes / %+v unmapped, want 3 / none", res.Episodes, res.Unmapped)
	}
	got := episodeTitles(t, pool, seriesID, 17)
	for n, want := range map[int]string{1: "tybw-1", 2: "tybw-2", 3: "tybw-3"} {
		if got[n] != want {
			t.Errorf("S17E%02d title = %q, want %q", n, got[n], want)
		}
	}
	// No per-season fetch at all: the ordering carried the metadata with it.
	if len(p.epCalls) != 0 {
		t.Errorf("SeasonEpisodes called for %v; the group supplied the episodes", p.epCalls)
	}
	// The verdict is recorded, and pins no provider season — the group's
	// episodes need not come from just one.
	provider, _, source := seasonMapping(t, pool, seriesID, 17)
	if provider != nil || srcOf(source) != "episode_group" {
		t.Errorf("season 17 = %v/%s, want NULL/episode_group", provider, srcOf(source))
	}
}

// TestMatchStraddlingSeasonResolves is the case the season+offset model could
// not express and the first implementation silently mis-titled: TVDB's One Piece
// season 11 draws from TMDB seasons 7, 8 and 9. Reading the episodes out of the
// ordering makes it unremarkable.
func TestMatchStraddlingSeasonResolves(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{11}, 3)

	// A group whose episodes span three provider seasons, already renumbered.
	p := &mappingProvider{
		seasons: []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
		group:   metadata.GroupedEpisodes{11: grouped("water7", 3)},
	}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 3 {
		t.Fatalf("res.Episodes = %d, want 3", res.Episodes)
	}
	got := episodeTitles(t, pool, seriesID, 11)
	if got[1] != "water7-1" || got[3] != "water7-3" {
		t.Errorf("S11 titles = %v, want the group's episodes", got)
	}
	// The provider *does* have a season 11 — identity would have matched by
	// number and written the wrong show's episodes. The ordering must win.
	if len(p.epCalls) != 0 {
		t.Errorf("fell through to a provider season fetch %v despite the ordering covering season 11", p.epCalls)
	}
}

// TestMatchIdentitySeasonUnchanged is the regression guard for every title whose
// numbering already agrees — SAO, Andor, Planet Earth II.
func TestMatchIdentitySeasonUnchanged(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{1, 2}, 2)

	p := &mappingProvider{seasons: []int{1, 2}} // publishes no TVDB ordering
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
	if p.groupCalls != 1 || p.seasonCalls != 1 {
		t.Errorf("provider lookups = %d orderings / %d season lists, want 1 each per series", p.groupCalls, p.seasonCalls)
	}
	provider, offset, source := seasonMapping(t, pool, seriesID, 2)
	if provider == nil || *provider != 2 || offset != 0 || srcOf(source) != "identity" {
		t.Errorf("season 2 = %v/%d/%s, want 2/0/identity", provider, offset, srcOf(source))
	}
}

// TestMatchIdentityReadBack pins that a recorded verdict is load-bearing: a
// season already settled as identity re-resolves without asking the provider
// anything, so new files landing in it get the same treatment as their siblings.
func TestMatchIdentityReadBack(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{2}, 1)
	if _, err := pool.Exec(ctx,
		`UPDATE seasons SET provider_season_number = 2, provider_episode_offset = 0,
		        provider_season_source = 'identity' WHERE series_id = $1`, seriesID); err != nil {
		t.Fatal(err)
	}

	p := &mappingProvider{seasons: []int{1, 2}}
	if _, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false); err != nil {
		t.Fatalf("match: %v", err)
	}
	if got := episodeTitles(t, pool, seriesID, 2); got[1] != "s2e1" {
		t.Errorf("S02E01 title = %q, want s2e1", got[1])
	}
	if p.groupCalls != 0 || p.seasonCalls != 0 {
		t.Errorf("provider consulted (%d orderings / %d season lists) for an already-settled season", p.groupCalls, p.seasonCalls)
	}
}

// TestMatchUnmappedSeasonReported is the other half of the bug: a season the
// provider genuinely has no counterpart for must be reported, not silently left
// empty — and the verdict must be persisted, so it survives a restart and an
// operator can tell it from a season nothing has looked at yet.
func TestMatchUnmappedSeasonReported(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{17}, 3)

	p := &mappingProvider{seasons: []int{0, 1, 2}} // no ordering published
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 0 || len(res.Unmapped) != 1 {
		t.Fatalf("res = %d episodes / %+v unmapped, want 0 / one season", res.Episodes, res.Unmapped)
	}
	u := res.Unmapped[0]
	if u.SeriesID != seriesID || u.SeriesTitle != "Bleach" || u.SeasonNumber != 17 || u.Episodes != 3 {
		t.Errorf("unmapped = %+v, want Bleach season 17 with 3 episodes", u)
	}
	if u.Reason == "" {
		t.Error("unmapped season carries no reason; every entry would read the same")
	}
	// Nothing was guessed: the filename fallback stands.
	if got := episodeTitles(t, pool, seriesID, 17); !strings.Contains(got[1], "S17E01") {
		t.Errorf("S17E01 title = %q, want the filename fallback left intact", got[1])
	}
	// Persisted, so "looked and found nothing" is distinguishable from
	// "never looked" after a restart.
	provider, _, source := seasonMapping(t, pool, seriesID, 17)
	if provider != nil || srcOf(source) != "unmapped" {
		t.Errorf("season 17 = %v/%s, want NULL/unmapped", provider, srcOf(source))
	}
}

// TestMatchManualSeasonMappingWins pins the operator escape hatch: a mapping set
// by hand is used as-is and never overwritten, even where the provider would
// have resolved the season differently.
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

	// The ordering would supply different episodes; the operator's pin must win.
	p := &mappingProvider{
		seasons: []int{0, 1, 2},
		group:   metadata.GroupedEpisodes{17: grouped("tybw", 2)},
	}
	if _, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false); err != nil {
		t.Fatalf("match: %v", err)
	}
	if got := episodeTitles(t, pool, seriesID, 17); got[1] != "s2e11" {
		t.Errorf("S17E01 title = %q, want s2e11 from the manual +10 offset", got[1])
	}
	provider, offset, source := seasonMapping(t, pool, seriesID, 17)
	if provider == nil || *provider != 2 || offset != 10 || srcOf(source) != "manual" {
		t.Errorf("mapping = %v/%d/%s, want the operator's 2/10/manual left alone", provider, offset, srcOf(source))
	}
	if p.seasonCalls != 0 || p.groupCalls != 0 {
		t.Errorf("provider consulted (%d/%d) for a hand-set mapping", p.seasonCalls, p.groupCalls)
	}
}

// TestMatchManualUnmappedLeavesFilenames covers the other way an operator uses
// the pin: 'manual' with no provider season says "there is no counterpart, stop
// trying". It must halt the resolver rather than fall through to it — falling
// through would overwrite the titles the operator chose to keep.
func TestMatchManualUnmappedLeavesFilenames(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{2}, 2)
	if _, err := pool.Exec(ctx,
		`UPDATE seasons SET provider_season_number = NULL, provider_season_source = 'manual'
		  WHERE series_id = $1`, seriesID); err != nil {
		t.Fatal(err)
	}

	// The provider has a season 2 and would happily fill it in.
	p := &mappingProvider{seasons: []int{1, 2}}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if res.Episodes != 0 {
		t.Fatalf("res.Episodes = %d, want 0 — the operator said leave it alone", res.Episodes)
	}
	if got := episodeTitles(t, pool, seriesID, 2); !strings.Contains(got[1], "S02E01") {
		t.Errorf("S02E01 title = %q, want the filename left as the operator chose", got[1])
	}
	if len(res.Unmapped) != 0 {
		t.Errorf("res.Unmapped = %+v; an operator-pinned season is already known about", res.Unmapped)
	}
	_, _, source := seasonMapping(t, pool, seriesID, 2)
	if srcOf(source) != "manual" {
		t.Errorf("source = %s, want manual left intact", srcOf(source))
	}
	if p.seasonCalls != 0 || p.groupCalls != 0 {
		t.Errorf("provider consulted (%d/%d) for a season pinned as having no counterpart", p.seasonCalls, p.groupCalls)
	}
}

// TestMatchProviderUnavailableAsksOnce covers the difference between "the
// provider has no such season" and "we could not ask". A transient failure must
// not be reported as unmapped, must not be persisted as a verdict, and must not
// be retried once per season of the series.
func TestMatchProviderUnavailableAsksOnce(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{1, 2, 3}, 1)

	p := &mappingProvider{groupErr: errors.New("tmdb unreachable")}
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
	if p.groupCalls != 1 {
		t.Errorf("ordering fetched %d times across 3 seasons, want 1", p.groupCalls)
	}
	// Nothing recorded, so the next sweep retries from scratch.
	provider, _, source := seasonMapping(t, pool, seriesID, 1)
	if provider != nil || source != nil {
		t.Errorf("recorded %v/%v for an unreachable provider, want both NULL", provider, srcOf(source))
	}
}

// TestMatchPermanentProviderFailureReported separates a permanent answer from an
// outage. A series whose tmdb_id was merged away 404s on every sweep forever;
// retrying it quietly means the operator never learns the id is dead.
func TestMatchPermanentProviderFailureReported(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, _ := mappingFixture(t, pool, []int{1, 2}, 1)

	p := &mappingProvider{groupErr: &metadata.APIError{Path: "/tv/30984/episode_groups", Status: 404}}
	res, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false)
	if err != nil {
		t.Fatalf("match: %v", err)
	}
	if len(res.Unmapped) != 2 {
		t.Fatalf("res.Unmapped = %+v, want both seasons reported", res.Unmapped)
	}
	if !strings.Contains(res.Unmapped[0].Reason, "no longer has this series") {
		t.Errorf("reason = %q, want it to name the permanent failure", res.Unmapped[0].Reason)
	}
	if p.groupCalls != 1 {
		t.Errorf("ordering fetched %d times, want 1", p.groupCalls)
	}
}

// TestMatchSharedProviderSeasonFetchedOnce guards the per-season fetch cache,
// failures included: several on-disk seasons can point at one provider season,
// and a failure that isn't remembered is re-requested once per season.
func TestMatchSharedProviderSeasonFetchedOnce(t *testing.T) {
	pool := mappingPool(t)
	ctx := context.Background()
	libID, seriesID := mappingFixture(t, pool, []int{1, 2}, 1)
	// Both on-disk seasons pinned at the same provider season.
	if _, err := pool.Exec(ctx,
		`UPDATE seasons SET provider_season_number = 1, provider_episode_offset = season_number - 1,
		        provider_season_source = 'manual' WHERE series_id = $1`, seriesID); err != nil {
		t.Fatal(err)
	}

	p := &mappingProvider{}
	if _, err := newMappingMatcher(t, pool, p).MatchLibrary(ctx, libID, false); err != nil {
		t.Fatalf("match: %v", err)
	}
	if len(p.epCalls) != 1 || p.epCalls[0] != 1 {
		t.Errorf("SeasonEpisodes calls = %v, want a single fetch of provider season 1", p.epCalls)
	}
}
