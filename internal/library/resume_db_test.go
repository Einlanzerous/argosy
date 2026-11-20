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

// ARGY-320: finishing E1 and E2 with a stale 13s stray on E3. The detail's
// resumeItemId, On Deck and Continue Watching must agree it is E3, and E3 must
// appear in exactly one home row.
func TestResumeAgreesWithHomeOnStaleStray(t *testing.T) {
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
	var accID, userID, libID, seriesID, seasonID string
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(pool.QueryRow(ctx, `INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "rs_"+suffix).Scan(&accID))
	must(pool.QueryRow(ctx, `INSERT INTO users (account_id, name) VALUES ($1,$2) RETURNING id::text`, accID, "u_"+suffix).Scan(&userID))
	must(pool.QueryRow(ctx, `INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1,$2,'mixed',$3) RETURNING id::text`,
		accID, "lib_"+suffix, "/tmp/rs"+suffix).Scan(&libID))
	must(pool.QueryRow(ctx, `INSERT INTO series (library_id, title, sort_title) VALUES ($1,'Scrubs','Scrubs') RETURNING id::text`, libID).Scan(&seriesID))
	must(pool.QueryRow(ctx, `INSERT INTO seasons (series_id, season_number) VALUES ($1,8) RETURNING id::text`, seriesID).Scan(&seasonID))
	var eps []string
	for i := 1; i <= 4; i++ {
		var ep string
		must(pool.QueryRow(ctx, `INSERT INTO media_items (library_id, kind, title, file_path) VALUES ($1,'episode',$2,$3) RETURNING id::text`,
			libID, "E"+strconv.Itoa(i), "rs-"+strconv.Itoa(i)+suffix).Scan(&ep))
		_, err := pool.Exec(ctx, `INSERT INTO episodes (season_id, episode_number, media_item_id, title) VALUES ($1,$2,$3,$4)`, seasonID, i, ep, "Ep")
		must(err)
		eps = append(eps, ep)
	}
	play := func(item string, watched bool, pos float64, ago time.Duration) {
		_, err := pool.Exec(ctx, `INSERT INTO play_state (user_id, media_item_id, watched, position_seconds, updated_at) VALUES ($1,$2,$3,$4,now() - $5::interval)`,
			userID, item, watched, pos, strconv.Itoa(int(ago.Seconds()))+" seconds")
		must(err)
	}
	play(eps[0], true, 0, 3*time.Hour)
	play(eps[1], true, 0, 2*time.Hour)
	play(eps[2], false, 13, 20*24*time.Hour) // stale stray from a bulk unwatch

	s := NewStore(pool, "/artwork")
	detail, err := s.GetSeries(ctx, accID, userID, seriesID)
	must(err)
	if detail.ResumeItemId == nil || detail.ResumeItemId.String() != eps[2] {
		t.Fatalf("resumeItemId = %v, want E3 %s", detail.ResumeItemId, eps[2])
	}
	deck, err := s.OnDeck(ctx, accID, userID, 20)
	must(err)
	if len(deck) != 1 || deck[0].Id.String() != eps[2] {
		t.Fatalf("on deck = %+v, want E3", deck)
	}
	cont, err := s.ContinueWatching(ctx, accID, userID, "", 20)
	must(err)
	for _, c := range cont {
		if c.Id.String() == eps[2] {
			t.Fatal("E3 is in both On Deck and Continue Watching")
		}
	}

	// A fresh sample on E3 belongs to Continue Watching only, not On Deck.
	_, err = pool.Exec(ctx, `UPDATE play_state SET updated_at = now() WHERE user_id=$1 AND media_item_id=$2`, userID, eps[2])
	must(err)
	deck, _ = s.OnDeck(ctx, accID, userID, 20)
	for _, d := range deck {
		if d.Id.String() == eps[2] {
			t.Fatal("fresh in-progress E3 must not be on deck")
		}
	}
	cont, err = s.ContinueWatching(ctx, accID, userID, "", 20)
	must(err)
	found := false
	for _, c := range cont {
		found = found || c.Id.String() == eps[2]
	}
	if !found {
		t.Fatal("fresh in-progress E3 should be in Continue Watching")
	}
}
