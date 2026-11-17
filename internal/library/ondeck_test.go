package library

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestOnDeck(t *testing.T) {
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
	var accID, userID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "od_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "u_"+suffix).Scan(&userID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	// One series, one season, three episodes. Returns the episode media-item ids.
	mkSeries := func(title string) (string, []string) {
		t.Helper()
		var seriesID, seasonID string
		if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,$2,$2) RETURNING id::text`, libID, title).Scan(&seriesID); err != nil {
			t.Fatal(err)
		}
		if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,1) RETURNING id::text`, seriesID).Scan(&seasonID); err != nil {
			t.Fatal(err)
		}
		var eps []string
		for i := 1; i <= 3; i++ {
			var ep string
			if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
				libID, title+" E"+strconv.Itoa(i), title+"-"+strconv.Itoa(i)+suffix).Scan(&ep); err != nil {
				t.Fatal(err)
			}
			if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
				seasonID, i, ep, "Ep "+strconv.Itoa(i)); err != nil {
				t.Fatal(err)
			}
			eps = append(eps, ep)
		}
		return seriesID, eps
	}
	watch := func(item string, watched bool, pos float64) {
		t.Helper()
		if _, err := pool.Exec(ctx, `INSERT INTO play_state (user_id, media_item_id, watched, position_seconds) VALUES ($1,$2,$3,$4)`,
			userID, item, watched, pos); err != nil {
			t.Fatal(err)
		}
	}

	_, aEps := mkSeries("Alpha") // finished E1 → on deck E2
	watch(aEps[0], true, 0)
	_, bEps := mkSeries("Bravo") // E1 watched, E2 in progress → Continue's job, NOT on deck
	watch(bEps[0], true, 0)
	watch(bEps[1], false, 300)
	_, cEps := mkSeries("Charlie") // all watched → no on-deck
	for _, e := range cEps {
		watch(e, true, 0)
	}
	mkSeries("Delta") // never started → not on deck

	s := NewStore(pool, "/artwork")
	deck, err := s.OnDeck(ctx, accID, userID, 20)
	if err != nil {
		t.Fatal(err)
	}

	got := map[string]string{} // series title -> episode number
	for _, d := range deck {
		got[d.SeriesTitle] = strconv.Itoa(d.EpisodeNumber)
	}
	if len(deck) != 1 || got["Alpha"] != "2" {
		t.Fatalf("on deck = %+v, want only Alpha E2", deck)
	}
	// The on-deck item points at Alpha's E2 media-item (playable).
	if deck[0].Id.String() != aEps[1] {
		t.Errorf("on-deck id = %s, want Alpha E2 %s", deck[0].Id, aEps[1])
	}
	if _, ok := got["Bravo"]; ok {
		t.Error("Bravo (E2 in progress) must not be on deck — it's Continue Watching")
	}
	if _, ok := got["Charlie"]; ok {
		t.Error("Charlie (fully watched) must not be on deck")
	}

	// Finishing Bravo E2 promotes Bravo's E3 onto the deck.
	if _, err := pool.Exec(ctx, `UPDATE play_state SET watched = true WHERE user_id=$1 AND media_item_id=$2`, userID, bEps[1]); err != nil {
		t.Fatal(err)
	}
	deck, _ = s.OnDeck(ctx, accID, userID, 20)
	got = map[string]string{}
	for _, d := range deck {
		got[d.SeriesTitle] = strconv.Itoa(d.EpisodeNumber)
	}
	if got["Bravo"] != "3" {
		t.Errorf("after finishing Bravo E2, on deck = %+v, want Bravo E3", deck)
	}
}

// TestOnDeckRecency covers ARGY-306: the frontier is the most recently engaged
// episode (not the furthest), and an unfinished row only counts as engaged once
// it is abandonedSeconds in. Everything goes through the real Store writers; where
// ordering matters, updated_at is set explicitly via ago().
func TestOnDeckRecency(t *testing.T) {
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
	s := NewStore(pool, "/artwork")
	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)

	var accID, libID string
	if err := pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "odr_"+suffix).Scan(&accID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "odrlib_"+suffix, "/tmp/odr"+suffix).Scan(&libID); err != nil {
		t.Fatal(err)
	}

	type fixture struct {
		userID   string
		seriesID string
		seasons  map[int]string    // season number -> season id
		items    map[string]string // "S2E4" -> media item id
		label    map[string]string // media item id -> "S2E4"
	}
	// newFixture builds one series with the given episodes per season and a fresh
	// profile.
	newFixture := func(t *testing.T, layout map[int]int) *fixture {
		t.Helper()
		f := &fixture{seasons: map[int]string{}, items: map[string]string{}, label: map[string]string{}}
		n := strconv.FormatInt(time.Now().UnixNano(), 36)
		if err := pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "u_"+n).Scan(&f.userID); err != nil {
			t.Fatal(err)
		}
		title := "Series " + n
		if err := pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,$2,$2) RETURNING id::text`, libID, title).Scan(&f.seriesID); err != nil {
			t.Fatal(err)
		}
		for sn, count := range layout {
			var seasonID string
			if err := pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,$2) RETURNING id::text`, f.seriesID, sn).Scan(&seasonID); err != nil {
				t.Fatal(err)
			}
			f.seasons[sn] = seasonID
			for ep := 1; ep <= count; ep++ {
				key := "S" + strconv.Itoa(sn) + "E" + strconv.Itoa(ep)
				var item string
				if err := pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
					libID, key, key+"-"+n).Scan(&item); err != nil {
					t.Fatal(err)
				}
				if _, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`,
					seasonID, ep, item, key); err != nil {
					t.Fatal(err)
				}
				f.items[key] = item
				f.label[item] = key
			}
		}
		return f
	}
	finish := func(t *testing.T, f *fixture, key string) {
		t.Helper()
		if _, err := s.SetWatched(ctx, accID, f.userID, f.items[key], true); err != nil {
			t.Fatal(err)
		}
	}
	unwatch := func(t *testing.T, f *fixture, key string) {
		t.Helper()
		if _, err := s.SetWatched(ctx, accID, f.userID, f.items[key], false); err != nil {
			t.Fatal(err)
		}
	}
	progress := func(t *testing.T, f *fixture, key string, pos float64) {
		t.Helper()
		if _, err := s.SetProgress(ctx, accID, f.userID, "", f.items[key], pos, nil); err != nil {
			t.Fatal(err)
		}
	}
	// ago pins the row's updated_at to d in the past.
	ago := func(t *testing.T, f *fixture, key string, d time.Duration) {
		t.Helper()
		if _, err := pool.Exec(ctx, `UPDATE play_state SET updated_at = now() - make_interval(secs => $3) WHERE user_id=$1 AND media_item_id=$2`,
			f.userID, f.items[key], d.Seconds()); err != nil {
			t.Fatal(err)
		}
	}
	// pick returns the series' On Deck episode label ("" when absent). It also
	// enforces criterion 7: no single episode is in both On Deck and Continue Watching.
	pick := func(t *testing.T, f *fixture) string {
		t.Helper()
		deck, err := s.OnDeck(ctx, accID, f.userID, 50)
		if err != nil {
			t.Fatal(err)
		}
		cw, err := s.ContinueWatching(ctx, accID, f.userID, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		inCW := map[string]bool{}
		for _, c := range cw {
			inCW[c.Id.String()] = true
		}
		got, n := "", 0
		for _, d := range deck {
			if inCW[d.Id.String()] {
				t.Errorf("episode %s is in both On Deck and Continue Watching", f.label[d.Id.String()])
			}
			if d.SeriesId.String() == f.seriesID {
				got = f.label[d.Id.String()]
				n++
			}
		}
		if n > 1 {
			t.Errorf("series appears %d times on deck", n)
		}
		return got
	}
	want := func(t *testing.T, f *fixture, exp string) {
		t.Helper()
		if got := pick(t, f); got != exp {
			t.Fatalf("on deck = %q, want %q", got, exp)
		}
	}
	h := time.Hour

	t.Run("c0 stray in far season does not outrank later S2 progress", func(t *testing.T) {
		f := newFixture(t, map[int]int{2: 5, 8: 3})
		progress(t, f, "S8E1", 30)
		ago(t, f, "S8E1", 5*h)
		for i, k := range []string{"S2E1", "S2E2", "S2E3"} {
			finish(t, f, k)
			ago(t, f, k, time.Duration(3-i)*h/2)
		}
		want(t, f, "S2E4")
	})

	t.Run("c1 recency wins between a finished S8E1 and S2", func(t *testing.T) {
		f := newFixture(t, map[int]int{2: 5, 8: 3})
		finish(t, f, "S8E1")
		ago(t, f, "S8E1", 72*h)
		for _, k := range []string{"S2E1", "S2E2", "S2E3"} {
			finish(t, f, k)
			ago(t, f, k, 2*h)
		}
		want(t, f, "S2E4")
		ago(t, f, "S8E1", 1*h) // finished later than S2E3
		want(t, f, "S8E2")
	})

	t.Run("c2 fresh sub-threshold stray neither moves the frontier nor drops the series", func(t *testing.T) {
		f := newFixture(t, map[int]int{2: 5, 8: 3})
		finish(t, f, "S2E1")
		ago(t, f, "S2E1", 2*h)
		progress(t, f, "S8E1", abandonedSeconds-1) // updated_at = now
		want(t, f, "S2E2")
		// A year-old and a fresh sample are treated alike: age is irrelevant.
		ago(t, f, "S8E1", 24*365*h)
		want(t, f, "S2E2")
	})

	t.Run("c3 unwatching a sampled stray restores the pre-stray result", func(t *testing.T) {
		f := newFixture(t, map[int]int{2: 5, 8: 3})
		finish(t, f, "S2E1")
		ago(t, f, "S2E1", 2*h)
		before := pick(t, f)
		finish(t, f, "S8E1") // stray mark-watched...
		progress(t, f, "S8E1", 20)
		unwatch(t, f, "S8E1") // ...unwatched: position 20 s kept, updated_at = now
		if after := pick(t, f); after != before || after != "S2E2" {
			t.Fatalf("after unwatch on deck = %q, before = %q, want S2E2 both", after, before)
		}
	})

	t.Run("c4 unwatched stray past the threshold hides On Deck until S2 is really played", func(t *testing.T) {
		f := newFixture(t, map[int]int{2: 5, 8: 3})
		finish(t, f, "S2E1")
		ago(t, f, "S2E1", 2*h)
		progress(t, f, "S8E1", abandonedSeconds+60)
		finish(t, f, "S8E1")
		unwatch(t, f, "S8E1") // position kept, now the newest engaged row
		want(t, f, "")
		// A sub-threshold S2 sample is not engagement, so it cannot heal.
		progress(t, f, "S2E2", 30)
		want(t, f, "")
		// Finishing an S2 episode (or passing 120 s) makes S2 the frontier again.
		finish(t, f, "S2E2")
		want(t, f, "S2E3")
	})

	t.Run("c4b passing the threshold in S2 takes the frontier back (Continue Watching's)", func(t *testing.T) {
		f := newFixture(t, map[int]int{2: 5, 8: 3})
		progress(t, f, "S8E1", abandonedSeconds+60)
		unwatch(t, f, "S8E1")
		progress(t, f, "S2E2", abandonedSeconds+10) // newest, unfinished -> CW's, not On Deck's
		want(t, f, "")
		finish(t, f, "S2E2")
		want(t, f, "S2E3")
	})

	t.Run("c5 rewatching an early episode resolves to the first unwatched after it", func(t *testing.T) {
		f := newFixture(t, map[int]int{1: 3, 2: 3})
		finish(t, f, "S1E1")
		finish(t, f, "S1E2")
		finish(t, f, "S2E1")
		ago(t, f, "S1E1", 3*h)
		ago(t, f, "S1E2", 3*h)
		ago(t, f, "S2E1", 2*h)
		finish(t, f, "S1E1") // rewatched most recently
		want(t, f, "S1E3")
	})

	t.Run("c6 bulk season watched lands on the furthest episode of the batch", func(t *testing.T) {
		f := newFixture(t, map[int]int{1: 3, 2: 3, 3: 2})
		if _, err := s.SetSeasonWatched(ctx, accID, f.userID, f.seasons[2], true); err != nil {
			t.Fatal(err)
		}
		want(t, f, "S3E1")
	})

	t.Run("c6b combined rip resolves to its last episode", func(t *testing.T) {
		f := newFixture(t, map[int]int{1: 4})
		// E1 and E2 are one file: point E2's episode row at E1's media item.
		if _, err := pool.Exec(ctx, `UPDATE episodes SET media_item_id = $1 WHERE media_item_id = $2`, f.items["S1E1"], f.items["S1E2"]); err != nil {
			t.Fatal(err)
		}
		finish(t, f, "S1E1")
		want(t, f, "S1E3")
	})

	t.Run("c7 per-series overlap is by series, never by episode", func(t *testing.T) {
		f := newFixture(t, map[int]int{1: 5})
		progress(t, f, "S1E1", 300) // older, live, unfinished: Continue Watching's
		ago(t, f, "S1E1", 3*h)
		finish(t, f, "S1E3") // newest engaged, finished
		want(t, f, "S1E4")   // pick() also asserts the two rows share no episode
		cw, err := s.ContinueWatching(ctx, accID, f.userID, "", 50)
		if err != nil || len(cw) != 1 || cw[0].Id.String() != f.items["S1E1"] {
			t.Fatalf("continue watching = %+v, %v; want only S1E1", cw, err)
		}
	})

	t.Run("bulk series unwatch promotes the furthest row that kept >= 120 s (accepted)", func(t *testing.T) {
		// Accepted behaviour (plan review thread on ARGY-293): bulk unwatch keeps
		// position_seconds and stamps one updated_at on every row, so the furthest
		// row at or past the threshold becomes the frontier. It is unfinished, so
		// it is Continue Watching's and the series leaves On Deck until something
		// newer is really played.
		f := newFixture(t, map[int]int{1: 3, 2: 3})
		progress(t, f, "S1E2", 200)
		progress(t, f, "S2E2", 300)
		if _, err := s.SetSeriesWatched(ctx, accID, f.userID, f.seriesID, true); err != nil {
			t.Fatal(err)
		}
		if _, err := s.SetSeriesWatched(ctx, accID, f.userID, f.seriesID, false); err != nil {
			t.Fatal(err)
		}
		want(t, f, "")
		// Really playing something newer heals it.
		finish(t, f, "S1E3")
		want(t, f, "S2E1")
	})

	t.Run("bulk unwatch of a far season with sub-threshold strays does not move the frontier (ARGY-304 shape)", func(t *testing.T) {
		f := newFixture(t, map[int]int{1: 2, 3: 4, 8: 4})
		// Low seasons: finished E1-E2 of S3 (one marked watched without playing,
		// so it keeps a tiny position), then S3E3 in progress past the threshold.
		finish(t, f, "S1E1")
		finish(t, f, "S1E2")
		finish(t, f, "S3E1")
		progress(t, f, "S3E2", 5) // sub-threshold position...
		finish(t, f, "S3E2")      // ...but finished rows always count
		progress(t, f, "S3E3", abandonedSeconds+127)
		for _, k := range []string{"S1E1", "S1E2", "S3E1", "S3E2", "S3E3"} {
			ago(t, f, k, 2*h)
		}
		// Far season: two sampled strays, then a bulk mark-watched / unwatch that
		// stamps every row with one fresh updated_at.
		progress(t, f, "S8E2", 13)
		progress(t, f, "S8E4", 8)
		if _, err := s.SetSeasonWatched(ctx, accID, f.userID, f.seasons[8], true); err != nil {
			t.Fatal(err)
		}
		if _, err := s.SetSeasonWatched(ctx, accID, f.userID, f.seasons[8], false); err != nil {
			t.Fatal(err)
		}
		// S3E3 (unfinished, past the threshold) is the real frontier: Continue
		// Watching's, so the series is not on deck. S8 did not take it over: the
		// moment S3E3 is finished On Deck follows it (below).
		want(t, f, "")
		// Finishing it puts On Deck at the next S3 episode, not in S8.
		finish(t, f, "S3E3")
		want(t, f, "S3E4")
	})
}
