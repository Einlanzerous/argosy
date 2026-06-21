package library

import (
	"context"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestOnDeck(t *testing.T) {
	dsn := os.Getenv("ARGOSY_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set ARGOSY_TEST_DATABASE_URL to run on-deck store tests")
	}
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
