package library

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestPlayStateLifecycle(t *testing.T) {
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
	store := NewStore(pool, "/artwork")

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, userID, libID, itemID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ps_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Film',$2) RETURNING id::text`,
		libID, "film-"+suffix+".mkv").Scan(&itemID); err != nil {
		t.Fatal(err)
	}
	dur := 1000.0

	// Fresh item: zero progress, not watched.
	if ps, err := store.GetProgress(ctx, accID, userID, itemID); err != nil || ps == nil || ps.PositionSeconds != 0 || ps.Watched {
		t.Fatalf("initial progress = %+v (err %v), want zero/unwatched", ps, err)
	}

	// Report 100s of 1000s → in progress.
	ps, err := store.SetProgress(ctx, accID, userID, "", itemID, 100, &dur)
	if err != nil || ps == nil || ps.PositionSeconds != 100 || ps.Watched {
		t.Fatalf("after 100s = %+v (err %v), want pos 100 / unwatched", ps, err)
	}

	// Shows up in Continue Watching with ~10%.
	cont, err := store.ContinueWatching(ctx, accID, userID, "", 20)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, c := range cont {
		if c.Id.String() == itemID {
			found = true
			if c.Percent < 9 || c.Percent > 11 {
				t.Errorf("percent = %v, want ~10", c.Percent)
			}
		}
	}
	if !found {
		t.Fatalf("item not in Continue Watching")
	}

	// Past the threshold → auto-watched, drops off the rail.
	if ps, err := store.SetProgress(ctx, accID, userID, "", itemID, 980, &dur); err != nil || ps == nil || !ps.Watched {
		t.Fatalf("after 980s = %+v (err %v), want watched", ps, err)
	}
	cont, _ = store.ContinueWatching(ctx, accID, userID, "", 20)
	for _, c := range cont {
		if c.Id.String() == itemID {
			t.Fatalf("watched item still in Continue Watching")
		}
	}

	// Explicit unwatch.
	if ps, err := store.SetWatched(ctx, accID, userID, itemID, false); err != nil || ps == nil || ps.Watched {
		t.Fatalf("after unwatch = %+v (err %v), want unwatched", ps, err)
	}

	// Cross-account isolation: a different account can't touch this item.
	var otherAcc string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "psother_"+suffix).Scan(&otherAcc); err != nil {
		t.Fatal(err)
	}
	if ps, err := store.GetProgress(ctx, otherAcc, userID, itemID); err != nil || ps != nil {
		t.Fatalf("cross-account GetProgress = %+v (err %v), want nil", ps, err)
	}
}

// TestContinueWatchingDedup covers ARGY-97: a series with more than one
// in-progress episode collapses to a single Continue Watching entry (its
// most-recently-active episode), while a standalone movie keeps its own row.
func TestContinueWatchingDedup(t *testing.T) {
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
	store := NewStore(pool, "/artwork")

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, userID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "cw_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// Series → season → two episodes (each its own media_item).
	var seriesID, seasonID, ep1ID, ep2ID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Hill House','hill house') RETURNING id::text`, libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','S01E01',$2) RETURNING id::text`,
		libID, "hh1-"+suffix+".mkv").Scan(&ep1ID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','S01E02',$2) RETURNING id::text`,
		libID, "hh2-"+suffix+".mkv").Scan(&ep2ID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,1,$2,'Pilot'),($1,2,$3,'Open Casket')`, seasonID, ep1ID, ep2ID); err != nil {
		t.Fatal(err)
	}

	// A standalone movie, also in progress.
	var movieID string
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','A Film',$2) RETURNING id::text`,
		libID, "film-"+suffix+".mkv").Scan(&movieID); err != nil {
		t.Fatal(err)
	}

	// In-progress play_state for all three, with controlled recency: ep1 oldest,
	// ep2 newer (the series' resume point), movie newest.
	ip := func(itemID string, agoSecs int) {
		if _, err := pool.Exec(ctx,
			`INSERT INTO play_state (user_id, media_item_id, position_seconds, duration_seconds, watched, updated_at)
			 VALUES ($1,$2,300,1000,false, now() - make_interval(secs => $3))`,
			userID, itemID, agoSecs); err != nil {
			t.Fatalf("seed play_state: %v", err)
		}
	}
	ip(ep1ID, 3600)
	ip(ep2ID, 60)
	ip(movieID, 10)

	cont, err := store.ContinueWatching(ctx, accID, userID, "", 20)
	if err != nil {
		t.Fatal(err)
	}

	// One row for the series (its most-recent episode, ep2) + one for the movie.
	if len(cont) != 2 {
		t.Fatalf("Continue Watching = %d entries, want 2 (series collapsed + movie): %+v", len(cont), cont)
	}
	var seriesEntries int
	var sawMovie bool
	for _, c := range cont {
		switch {
		case c.SeriesId != nil:
			seriesEntries++
			if c.SeriesId.String() != seriesID {
				t.Errorf("series entry series_id = %s, want %s", c.SeriesId, seriesID)
			}
			if c.Id.String() != ep2ID {
				t.Errorf("series resume point = %s, want the most-recent episode ep2 %s", c.Id, ep2ID)
			}
		case c.Id.String() == movieID:
			sawMovie = true
		}
	}
	if seriesEntries != 1 {
		t.Errorf("series appeared %d times in Continue Watching, want exactly 1", seriesEntries)
	}
	if !sawMovie {
		t.Errorf("standalone movie missing from Continue Watching")
	}
}

// TestContinueWatchingLastDevice covers ARGY-98: the cross-device pill is set
// only when a still-paired device owns the playhead AND it isn't the deck making
// the request. Reporting from another device surfaces the pill; requesting from
// that same device suppresses it; a revoked device drops the attribution.
func TestContinueWatchingLastDevice(t *testing.T) {
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
	store := NewStore(pool, "/artwork")

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, userID, libID, itemID, tvID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "dev_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Film',$2) RETURNING id::text`,
		libID, "film-"+suffix+".mkv").Scan(&itemID); err != nil {
		t.Fatal(err)
	}
	// The deck that owns the playhead — a TV in the living room.
	if err := pool.QueryRow(ctx, `INSERT INTO devices (account_id, user_id, name, token_hash, platform) VALUES ($1,$2,'Living Room TV',$3,'tv') RETURNING id::text`,
		accID, userID, "tok-"+suffix).Scan(&tvID); err != nil {
		t.Fatal(err)
	}

	dur := 1000.0
	if _, err := store.SetProgress(ctx, accID, userID, tvID, itemID, 100, &dur); err != nil {
		t.Fatalf("SetProgress: %v", err)
	}

	pill := func(currentDevice string) *string {
		t.Helper()
		cont, err := store.ContinueWatching(ctx, accID, userID, currentDevice, 20)
		if err != nil {
			t.Fatal(err)
		}
		for _, c := range cont {
			if c.Id.String() == itemID {
				if c.LastPlayedDevice == nil {
					return nil
				}
				name := c.LastPlayedDevice.Name
				return &name
			}
		}
		t.Fatalf("item not in Continue Watching")
		return nil
	}

	// From a phone (a different deck) the TV pill shows.
	if got := pill("11111111-1111-1111-1111-111111111111"); got == nil || *got != "Living Room TV" {
		t.Fatalf("pill from phone = %v, want \"Living Room TV\"", got)
	}
	// From the TV itself the pill is suppressed (you left off right here).
	if got := pill(tvID); got != nil {
		t.Fatalf("pill from owning deck = %v, want nil", *got)
	}
	// Revoking the device drops the attribution entirely.
	if _, err := pool.Exec(ctx, `UPDATE devices SET revoked_at = now() WHERE id = $1`, tvID); err != nil {
		t.Fatal(err)
	}
	if got := pill("11111111-1111-1111-1111-111111111111"); got != nil {
		t.Fatalf("pill after revoke = %v, want nil", *got)
	}
}

// TestContinueWatchingAbandoned covers ARGY-182 and ARGY-176 together, since both
// hang off the same query: a barely-started item ages off the rail, and episodes
// carry their own identity so a card needn't fall back to the filename-derived
// media-item title.
func TestContinueWatchingAbandoned(t *testing.T) {
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
	store := NewStore(pool, "/artwork")

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	var accID, userID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ab_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "viewer").Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// One series, three episodes — each gets its own play_state below. The
	// media_item titles carry the filename shape that ARGY-176 is about.
	var seriesID, seasonID string
	if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Sword Art Online','sword art online') RETURNING id::text`, libID).Scan(&seriesID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
		t.Fatal(err)
	}
	episode := func(n int, epTitle string) string {
		var itemID string
		if err := pool.QueryRow(ctx,
			`INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
			libID, "Sword Art Online - S01E0"+strconv.Itoa(n)+" - "+epTitle+" Bluray-1080p",
			"sao"+strconv.Itoa(n)+"-"+suffix+".mkv").Scan(&itemID); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
			seasonID, n, itemID, epTitle); err != nil {
			t.Fatal(err)
		}
		return itemID
	}
	// Separate series so each row can be asserted independently (the rail
	// collapses per series).
	freshID := episode(1, "The World of Swords")
	var staleID, recentID string
	{
		var s2, se2 string
		if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Stale Show','stale show') RETURNING id::text`, libID).Scan(&s2); err != nil {
			t.Fatal(err)
		}
		if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,2) RETURNING id::text`, s2).Scan(&se2); err != nil {
			t.Fatal(err)
		}
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode','Stale S02E05',$2) RETURNING id::text`,
			libID, "stale-"+suffix+".mkv").Scan(&staleID); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,5,$2,'Old Ground')`, se2, staleID); err != nil {
			t.Fatal(err)
		}
		if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'movie','Recent Sample',$2) RETURNING id::text`,
			libID, "recent-"+suffix+".mkv").Scan(&recentID); err != nil {
			t.Fatal(err)
		}
	}

	seed := func(itemID string, pos float64, agoSecs int) {
		if _, err := pool.Exec(ctx,
			`INSERT INTO play_state (user_id, media_item_id, position_seconds, duration_seconds, watched, updated_at)
			 VALUES ($1,$2,$3,1440,false, now() - make_interval(secs => $4))`,
			userID, itemID, pos, agoSecs); err != nil {
			t.Fatalf("seed play_state: %v", err)
		}
	}
	seed(freshID, 600, 3600)    // properly under way — stays regardless of age
	seed(staleID, 19, 60*60*30) // 19s, untouched for 30h — the reported case
	seed(recentID, 19, 60*30)   // 19s but only 30m ago — too soon to judge

	cont, err := store.ContinueWatching(ctx, accID, userID, "", 20)
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]api.ContinueItem{}
	for _, c := range cont {
		seen[c.Id.String()] = c
	}

	if _, ok := seen[staleID]; ok {
		t.Errorf("a 19s partial untouched for 30h is still on the rail — that is the ARGY-182 case")
	}
	if _, ok := seen[recentID]; !ok {
		t.Errorf("a 19s partial from 30m ago was dropped; the staleness window should protect a same-day start")
	}
	got, ok := seen[freshID]
	if !ok {
		t.Fatalf("a well-progressed episode fell off the rail: %+v", cont)
	}

	// ARGY-176: the card can name the episode without reaching for mi.title.
	if got.SeasonNumber == nil || *got.SeasonNumber != 1 {
		t.Errorf("seasonNumber = %v, want 1", got.SeasonNumber)
	}
	if got.EpisodeNumber == nil || *got.EpisodeNumber != 1 {
		t.Errorf("episodeNumber = %v, want 1", got.EpisodeNumber)
	}
	if got.EpisodeTitle == nil || *got.EpisodeTitle != "The World of Swords" {
		t.Errorf("episodeTitle = %v, want %q", got.EpisodeTitle, "The World of Swords")
	}
	// The media-item title is still the filename-derived string; the point is that
	// clients no longer have to render it.
	if got.Title == "" || got.SeriesTitle == nil || *got.SeriesTitle != "Sword Art Online" {
		t.Errorf("seriesTitle = %v, title = %q", got.SeriesTitle, got.Title)
	}
}
