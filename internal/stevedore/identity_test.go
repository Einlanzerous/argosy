package stevedore

// Identity across file replacement (ARGY-238): a file that replaces one which
// vanished takes over the vanished row, so the item keeps its id — and with it
// every profile's play_state and every stowed copy.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/Einlanzerous/argosy/internal/db"
	"github.com/Einlanzerous/argosy/internal/fileid"
	"github.com/Einlanzerous/argosy/internal/mediasource"
	"github.com/Einlanzerous/argosy/internal/mediatool"
	"github.com/Einlanzerous/argosy/internal/stow"
	"github.com/Einlanzerous/argosy/internal/testdb"
	"github.com/jackc/pgx/v5/pgxpool"
)

const mib = 1 << 20

// blob is size bytes whose content — including the first MiB, which is what
// the partial hash reads — differs for every seed.
func blob(seed byte, size int) []byte {
	b := make([]byte, size)
	for i := range b {
		b[i] = byte(i) ^ seed
	}
	return b
}

// testSource is fakeSource with the two knobs these tests need: files ffprobe
// can "see" (so a stub prober runs), and reads that fail.
type testSource struct {
	files    map[string][]byte
	local    bool
	failOpen map[string]bool
}

func (s *testSource) Walk(_ context.Context, fn func(mediasource.Entry) error) error {
	for p, b := range s.files {
		if err := fn(mediasource.Entry{Path: p, Size: int64(len(b)), ModTime: time.Unix(0, 0)}); err != nil {
			return err
		}
	}
	return nil
}

func (s *testSource) LocalPath(p string) (string, bool) { return p, s.local }

func (s *testSource) Open(_ context.Context, rel string) (io.ReadCloser, error) {
	if s.failOpen[rel] {
		return nil, errors.New("read failed")
	}
	return io.NopCloser(bytes.NewReader(s.files[rel])), nil
}

// logBuffer collects the scanner's log lines; ingest runs on several workers.
type logBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *logBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *logBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

type identityFixture struct {
	t       *testing.T
	ctx     context.Context
	pool    *pgxpool.Pool
	sc      *Scanner
	logs    *logBuffer
	account string
	user    string
	lib     string
}

func newIdentityFixture(t *testing.T) *identityFixture {
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

	suffix := strconv.FormatInt(time.Now().UnixNano(), 36)
	f := &identityFixture{t: t, ctx: ctx, pool: pool, logs: &logBuffer{}}
	if err := pool.QueryRow(ctx,
		`INSERT INTO accounts (name) VALUES ($1) RETURNING id::text`, "ident_"+suffix).Scan(&f.account); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(context.Background(), `DELETE FROM accounts WHERE id = $1`, f.account)
	})
	if err := pool.QueryRow(ctx,
		`INSERT INTO users (account_id, name) VALUES ($1, $2) RETURNING id::text`, f.account, "u_"+suffix).Scan(&f.user); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`INSERT INTO libraries (account_id, name, kind, root_path) VALUES ($1, $2, 'mixed', $3) RETURNING id::text`,
		f.account, "lib_"+suffix, "/tmp/"+suffix).Scan(&f.lib); err != nil {
		t.Fatal(err)
	}
	f.sc = NewScanner(pool, slog.New(slog.NewTextHandler(f.logs, nil)), "")
	return f
}

func (f *identityFixture) scan(files map[string][]byte) Result {
	f.t.Helper()
	return f.scanSrc(&testSource{files: files})
}

func (f *identityFixture) scanSrc(src mediasource.Source) Result {
	f.t.Helper()
	res, err := f.sc.Scan(f.ctx, f.lib, src)
	if err != nil {
		f.t.Fatalf("scan: %v", err)
	}
	return res
}

// idOf is the id of the row at path, or "" when there is none.
func (f *identityFixture) idOf(path string) string {
	f.t.Helper()
	var id string
	err := f.pool.QueryRow(f.ctx,
		`SELECT coalesce((SELECT id::text FROM media_items WHERE library_id = $1 AND file_path = $2), '')`,
		f.lib, path).Scan(&id)
	if err != nil {
		f.t.Fatal(err)
	}
	return id
}

func (f *identityFixture) mustID(path string) string {
	f.t.Helper()
	id := f.idOf(path)
	if id == "" {
		f.t.Fatalf("no media item at %q", path)
	}
	return id
}

func (f *identityFixture) count(query string, args ...any) int {
	f.t.Helper()
	var n int
	if err := f.pool.QueryRow(f.ctx, query, args...).Scan(&n); err != nil {
		f.t.Fatal(err)
	}
	return n
}

func (f *identityFixture) exec(query string, args ...any) {
	f.t.Helper()
	if _, err := f.pool.Exec(f.ctx, query, args...); err != nil {
		f.t.Fatal(err)
	}
}

func (f *identityFixture) watch(itemID string, position float64, watched bool) {
	f.t.Helper()
	f.exec(`INSERT INTO play_state (user_id, media_item_id, position_seconds, duration_seconds, watched)
	        VALUES ($1, $2, $3, 1400, $4)`, f.user, itemID, position, watched)
}

func (f *identityFixture) playState(itemID string) (position float64, watched, ok bool) {
	f.t.Helper()
	err := f.pool.QueryRow(f.ctx,
		`SELECT position_seconds, watched FROM play_state WHERE user_id = $1 AND media_item_id = $2`,
		f.user, itemID).Scan(&position, &watched)
	if err != nil {
		return 0, false, false
	}
	return position, watched, true
}

// episode returns an episode row's id and the item it links to ("" when NULL).
func (f *identityFixture) episode(show string, season, number int) (episodeID, itemID string, ok bool) {
	f.t.Helper()
	err := f.pool.QueryRow(f.ctx,
		`SELECT e.id::text, coalesce(e.media_item_id::text, '')
		   FROM episodes e JOIN seasons se ON se.id = e.season_id JOIN series sr ON sr.id = se.series_id
		  WHERE sr.library_id = $1 AND sr.title = $2 AND se.season_number = $3 AND e.episode_number = $4`,
		f.lib, show, season, number).Scan(&episodeID, &itemID)
	if err != nil {
		return "", "", false
	}
	return episodeID, itemID, true
}

// TestCarrySameSlotUpgradeKeepsIdentity is the Bleach S17 case: Sonarr swaps an
// episode for a better release under a new name. The item keeps its id, every
// profile's progress and watched state, and its episode row — title and TMDB
// metadata included, which a vanished row claiming the slot used to cost.
func TestCarrySameSlotUpgradeKeepsIdentity(t *testing.T) {
	f := newIdentityFixture(t)
	oldPath := "Show/Season 1/Show S01E02 HDTV.mkv"
	newPath := "Show/Season 1/Show S01E02 WEBDL-1080p.mkv"

	f.scan(map[string][]byte{oldPath: blob(1, 2*mib)})
	id := f.mustID(oldPath)
	f.watch(id, 600, true)
	episodeID, _, ok := f.episode("Show", 1, 2)
	if !ok {
		t.Fatal("first sweep made no episode row")
	}
	f.exec(`UPDATE episodes SET title = 'The Real Title', provider_metadata = '{"name":"The Real Title"}' WHERE id = $1`, episodeID)

	res := f.scan(map[string][]byte{newPath: blob(2, 3*mib)})
	if res.Carried != 1 || res.Removed != 0 {
		t.Fatalf("result = %+v, want 1 carried / 0 removed", res)
	}
	if got := f.idOf(newPath); got != id {
		t.Fatalf("replacement is item %q, want the original %q", got, id)
	}
	if n := f.count(`SELECT count(*) FROM media_items WHERE library_id = $1`, f.lib); n != 1 {
		t.Fatalf("media_items = %d, want 1 (no row minted for the replacement)", n)
	}
	if pos, watched, ok := f.playState(id); !ok || pos != 600 || !watched {
		t.Errorf("play_state = (%v, %v, present %v), want (600, watched)", pos, watched, ok)
	}
	if n := f.count(`SELECT file_size FROM media_items WHERE id = $1`, id); n != 3*mib {
		t.Errorf("file_size = %d, want the new file's %d", n, 3*mib)
	}

	afterID, linked, ok := f.episode("Show", 1, 2)
	if !ok || afterID != episodeID || linked != id {
		t.Fatalf("episode row = (%q → %q), want the same row %q linked to %q", afterID, linked, episodeID, id)
	}
	var title, name string
	if err := f.pool.QueryRow(f.ctx,
		`SELECT title, provider_metadata->>'name' FROM episodes WHERE id = $1`, episodeID).Scan(&title, &name); err != nil {
		t.Fatal(err)
	}
	if title != "The Real Title" || name != "The Real Title" {
		t.Errorf("episode metadata = (%q, %q), want the TMDB title kept", title, name)
	}
	if logs := f.logs.String(); !strings.Contains(logs, "carried item identity") || !strings.Contains(logs, "episode_slot") {
		t.Errorf("no carry logged with its method:\n%s", logs)
	}
}

// TestCarryByContent: a rename or move that keeps the bytes carries by content,
// whatever the paths say.
func TestCarryByContent(t *testing.T) {
	f := newIdentityFixture(t)
	film := blob(3, 2*mib)
	f.scan(map[string][]byte{"Film A.mkv": film})
	id := f.mustID("Film A.mkv")
	f.watch(id, 100, false)

	res := f.scan(map[string][]byte{"Archive/Film A (Director's Cut).mkv": film})
	if res.Carried != 1 {
		t.Fatalf("result = %+v, want the rename carried", res)
	}
	if got := f.idOf("Archive/Film A (Director's Cut).mkv"); got != id {
		t.Fatalf("renamed film is item %q, want %q", got, id)
	}
	if _, _, ok := f.playState(id); !ok {
		t.Error("the rename lost its play_state")
	}
	if !strings.Contains(f.logs.String(), "content_hash") {
		t.Errorf("carry not logged as a content match:\n%s", f.logs.String())
	}
}

// TestSubMiBFilesNeverCarryByContent: below 1 MiB the partial hash is the whole
// file, so every empty placeholder shares one — and one size. An empty E05
// vanishing while an empty E06 arrives must not hand E05's id to E06.
func TestSubMiBFilesNeverCarryByContent(t *testing.T) {
	f := newIdentityFixture(t)
	keep := blob(7, 2*mib)
	f.scan(map[string][]byte{
		"Show/Season 1/Show S01E05.mkv": {},
		"Show/Season 1/Show S01E01.mkv": keep,
	})
	e05 := f.mustID("Show/Season 1/Show S01E05.mkv")

	res := f.scan(map[string][]byte{
		"Show/Season 1/Show S01E06.mkv": {},
		"Show/Season 1/Show S01E01.mkv": keep,
	})
	if res.Carried != 0 {
		t.Fatalf("result = %+v, want nothing carried", res)
	}
	if got := f.idOf("Show/Season 1/Show S01E06.mkv"); got == "" || got == e05 {
		t.Fatalf("E06 is item %q; want a new row, not E05's %q", got, e05)
	}
	if f.idOf("Show/Season 1/Show S01E05.mkv") != "" {
		t.Error("E05's row survived with no file")
	}
}

// TestSlotChangingCarry: content can move a file to another slot — a renumber,
// a move into another show. The item's old episode link has to go, or the old
// slot points at it forever and is never swept.
func TestSlotChangingCarry(t *testing.T) {
	f := newIdentityFixture(t)
	e20 := blob(4, 2*mib)
	alpha := blob(5, 2*mib)
	e19 := blob(6, 2*mib)
	f.scan(map[string][]byte{
		"Show/Season 1/Show S01E19.mkv":   e19,
		"Show/Season 1/Show S01E20.mkv":   e20,
		"Alpha/Season 1/Alpha S01E01.mkv": alpha,
	})
	renumbered := f.mustID("Show/Season 1/Show S01E20.mkv")
	moved := f.mustID("Alpha/Season 1/Alpha S01E01.mkv")

	res := f.scan(map[string][]byte{
		"Show/Season 1/Show S01E19.mkv": e19,
		"Show/Season 1/Show S01E21.mkv": e20,
		"Beta/Season 1/Beta S01E01.mkv": alpha,
	})
	if res.Carried != 2 {
		t.Fatalf("result = %+v, want both carried", res)
	}

	if got := f.idOf("Show/Season 1/Show S01E21.mkv"); got != renumbered {
		t.Fatalf("renumbered file is item %q, want %q", got, renumbered)
	}
	if _, _, ok := f.episode("Show", 1, 20); ok {
		t.Error("the old E20 row survived the renumber")
	}
	if _, linked, ok := f.episode("Show", 1, 21); !ok || linked != renumbered {
		t.Errorf("E21 links %q, want %q", linked, renumbered)
	}
	if n := f.count(`SELECT count(*) FROM episodes WHERE media_item_id = $1`, renumbered); n != 1 {
		t.Errorf("item backs %d episode rows, want 1", n)
	}

	if got := f.idOf("Beta/Season 1/Beta S01E01.mkv"); got != moved {
		t.Fatalf("moved file is item %q, want %q", got, moved)
	}
	if n := f.count(`SELECT count(*) FROM series WHERE library_id = $1 AND title = 'Alpha'`, f.lib); n != 0 {
		t.Error("Alpha's series survived with nothing in it")
	}
	if _, linked, ok := f.episode("Beta", 1, 1); !ok || linked != moved {
		t.Errorf("Beta S01E01 links %q, want %q", linked, moved)
	}
	if !strings.Contains(f.logs.String(), "slot_changed=true") {
		t.Errorf("slot change not logged:\n%s", f.logs.String())
	}
}

// TestCarryMovieOwnFolderOnly: a Radarr upgrade inside the film's own folder
// carries. The same change at the library root, or in a folder that still holds
// another film, can't be told from a different film and doesn't.
func TestCarryMovieOwnFolderOnly(t *testing.T) {
	f := newIdentityFixture(t)
	f.scan(map[string][]byte{
		"Some Movie (2021)/Some Movie (2021).mkv": blob(10, 2*mib),
		"Flat Movie (2020).mkv":                   blob(11, 2*mib),
		"Collection/Alpha (2001).mkv":             blob(12, 2*mib),
		"Collection/Bravo (2002).mkv":             blob(13, 2*mib),
	})
	own := f.mustID("Some Movie (2021)/Some Movie (2021).mkv")
	flat := f.mustID("Flat Movie (2020).mkv")
	bravo := f.mustID("Collection/Bravo (2002).mkv")

	res := f.scan(map[string][]byte{
		"Some Movie (2021)/Some Movie (2021) [1080p].mkv": blob(14, 2*mib),
		"Flat Movie (2020) [1080p].mkv":                   blob(15, 2*mib),
		"Collection/Alpha (2001).mkv":                     blob(12, 2*mib),
		"Collection/Bravo (2002) [1080p].mkv":             blob(16, 2*mib),
	})
	if res.Carried != 1 {
		t.Fatalf("result = %+v, want only the own-folder upgrade carried", res)
	}
	if got := f.idOf("Some Movie (2021)/Some Movie (2021) [1080p].mkv"); got != own {
		t.Errorf("own-folder upgrade is item %q, want %q", got, own)
	}
	if got := f.idOf("Flat Movie (2020) [1080p].mkv"); got == flat {
		t.Error("a film at the library root inherited another file's id")
	}
	if got := f.idOf("Collection/Bravo (2002) [1080p].mkv"); got == bravo {
		t.Error("a film in a shared folder inherited another file's id")
	}
}

// TestAmbiguousReplacementsCarryNothing: when a key has more than one file on
// either side, nothing is guessed. The rows prune as before — but the episode
// row itself survives, because only seen rows claim a slot now.
func TestAmbiguousReplacementsCarryNothing(t *testing.T) {
	f := newIdentityFixture(t)
	f.scan(map[string][]byte{
		"Show/Season 1/Show S01E03 A.mkv":   blob(20, 2*mib),
		"Show/Season 1/Show S01E03 B.mkv":   blob(21, 2*mib),
		"Show/Season 1/Show S01E04 X.mkv":   blob(22, 2*mib),
		"Show/Season 1/Show S01E07-E08.mkv": blob(23, 2*mib),
	})
	a := f.mustID("Show/Season 1/Show S01E03 A.mkv")
	b := f.mustID("Show/Season 1/Show S01E03 B.mkv")
	x := f.mustID("Show/Season 1/Show S01E04 X.mkv")
	combined := f.mustID("Show/Season 1/Show S01E07-E08.mkv")
	e03, _, ok := f.episode("Show", 1, 3)
	if !ok {
		t.Fatal("no E03 row")
	}
	f.exec(`UPDATE episodes SET provider_metadata = '{"name":"Kept"}' WHERE id = $1`, e03)

	res := f.scan(map[string][]byte{
		"Show/Season 1/Show S01E03 C.mkv": blob(24, 2*mib),
		"Show/Season 1/Show S01E04 Y.mkv": blob(25, 2*mib),
		"Show/Season 1/Show S01E04 Z.mkv": blob(26, 2*mib),
		"Show/Season 1/Show S01E07.mkv":   blob(27, 2*mib),
		"Show/Season 1/Show S01E08.mkv":   blob(28, 2*mib),
	})
	if res.Carried != 0 {
		t.Fatalf("result = %+v, want nothing carried", res)
	}
	for name, id := range map[string]string{"E03 A": a, "E03 B": b, "E04 X": x, "E07-E08": combined} {
		if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1`, id); n != 0 {
			t.Errorf("%s kept its row through an ambiguous replacement", name)
		}
	}
	if n := strings.Count(f.logs.String(), "replacement ambiguous"); n != 3 {
		t.Errorf("ambiguous warnings = %d, want 3 (A, B, X):\n%s", n, f.logs.String())
	}

	after, linked, ok := f.episode("Show", 1, 3)
	if !ok || after != e03 || linked != f.mustID("Show/Season 1/Show S01E03 C.mkv") {
		t.Errorf("E03 row = (%q → %q), want %q kept and linked to C", after, linked, e03)
	}
	if n := f.count(`SELECT count(*) FROM episodes WHERE id = $1 AND provider_metadata->>'name' = 'Kept'`, e03); n != 1 {
		t.Error("E03 lost its provider metadata")
	}
}

// TestContestedSlotIsHeldByTheOlderRow: with two files for one episode on disk,
// the slot stays on the older row every sweep instead of flipping between them.
func TestContestedSlotIsHeldByTheOlderRow(t *testing.T) {
	f := newIdentityFixture(t)
	older := "Show/Season 1/Show S01E09 HDTV.mkv"
	younger := "Show/Season 1/Show S01E09 WEB.mkv"
	f.scan(map[string][]byte{older: blob(29, 2*mib)})
	olderID := f.mustID(older)

	for sweep := 1; sweep <= 3; sweep++ {
		f.scan(map[string][]byte{older: blob(29, 2*mib), younger: blob(30, 2*mib)})
		if _, linked, ok := f.episode("Show", 1, 9); !ok || linked != olderID {
			t.Fatalf("sweep %d: E09 links %q, want the older %q", sweep, linked, olderID)
		}
	}
}

// TestFailedCarryIsHeldBackAndRetried: a carry that fails writes nothing, keeps
// the vanished row (and its state) out of prune, and skips the new path so the
// next sweep retries the carry rather than inserting beside it.
func TestFailedCarryIsHeldBackAndRetried(t *testing.T) {
	f := newIdentityFixture(t)
	oldPath := "Show/Season 1/Show S01E10 HDTV.mkv"
	newPath := "Show/Season 1/Show S01E10 WEB.mkv"
	f.scan(map[string][]byte{oldPath: blob(31, 2*mib)})
	id := f.mustID(oldPath)
	f.watch(id, 50, true)

	f.sc.identityHook = func(string) error { return errors.New("injected carry failure") }
	res := f.scan(map[string][]byte{newPath: blob(32, 2*mib)})
	if res.Carried != 0 || res.Errors != 1 || res.Removed != 0 {
		t.Fatalf("failed sweep = %+v, want 0 carried / 1 error / 0 removed", res)
	}
	if got := f.idOf(oldPath); got != id {
		t.Fatalf("vanished row gone after a failed carry (item at old path %q)", got)
	}
	if f.idOf(newPath) != "" {
		t.Fatal("the new path was inserted beside a failed carry; the next sweep can't retry it")
	}
	if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1 AND carry_held_since IS NOT NULL`, id); n != 1 {
		t.Error("failed carry did not set carry_held_since")
	}
	if _, _, ok := f.playState(id); !ok {
		t.Error("failed carry lost the item's play_state")
	}
	if !strings.Contains(f.logs.String(), "carry failed, held back from prune") {
		t.Errorf("hold-back not logged:\n%s", f.logs.String())
	}

	f.sc.identityHook = nil
	res = f.scan(map[string][]byte{newPath: blob(32, 2*mib)})
	if res.Carried != 1 {
		t.Fatalf("retry sweep = %+v, want the carry to land", res)
	}
	if got := f.idOf(newPath); got != id {
		t.Fatalf("retried carry made item %q, want %q", got, id)
	}
	if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1 AND carry_held_since IS NULL`, id); n != 1 {
		t.Error("a successful carry left carry_held_since set")
	}
}

// TestCarryThatKeepsFailingIsPrunedAfterTheHour: the hold-back is bounded. A
// carry still failing an hour after its first failure is pruned as before, and
// its file then ingests as a new row.
func TestCarryThatKeepsFailingIsPrunedAfterTheHour(t *testing.T) {
	f := newIdentityFixture(t)
	oldPath := "Show/Season 1/Show S01E11 HDTV.mkv"
	newPath := "Show/Season 1/Show S01E11 WEB.mkv"
	f.scan(map[string][]byte{oldPath: blob(33, 2*mib)})
	id := f.mustID(oldPath)

	f.sc.identityHook = func(string) error { return errors.New("injected carry failure") }
	f.scan(map[string][]byte{newPath: blob(34, 2*mib)})
	f.exec(`UPDATE media_items SET carry_held_since = now() - interval '2 hours' WHERE id = $1`, id)

	res := f.scan(map[string][]byte{newPath: blob(34, 2*mib)})
	if res.Removed != 1 {
		t.Fatalf("sweep past the hour = %+v, want the held row pruned", res)
	}
	if f.idOf(oldPath) != "" {
		t.Fatal("a carry failing for over an hour is still held back")
	}
	if !strings.Contains(f.logs.String(), "carry failed repeatedly, pruning") {
		t.Errorf("expired hold-back not logged:\n%s", f.logs.String())
	}

	f.sc.identityHook = nil
	f.scan(map[string][]byte{newPath: blob(34, 2*mib)})
	if got := f.idOf(newPath); got == "" || got == id {
		t.Fatalf("after the prune the file is item %q; want a new row", got)
	}
}

// TestSeenRowClearsCarryHold: a row whose file is seen again loses any hold-back
// mark, so a later failure starts a fresh hour.
func TestSeenRowClearsCarryHold(t *testing.T) {
	f := newIdentityFixture(t)
	p := "Film C.mkv"
	f.scan(map[string][]byte{p: blob(35, 2*mib)})
	id := f.mustID(p)
	f.exec(`UPDATE media_items SET carry_held_since = now() - interval '30 minutes' WHERE id = $1`, id)

	f.scan(map[string][]byte{p: blob(35, 2*mib)})
	if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1 AND carry_held_since IS NULL`, id); n != 1 {
		t.Error("a row seen again kept its carry hold-back mark")
	}
}

// TestCarryWritesTheNewFilesProbe: the carry is the new file's ingest, so the
// row gets the new file's technical metadata with its new path. A probe that
// fails still carries, with empty metadata, exactly as a plain ingest would.
func TestCarryWritesTheNewFilesProbe(t *testing.T) {
	f := newIdentityFixture(t)
	f.sc.probe = func(_ context.Context, p string) (mediatool.Probe, error) {
		if strings.Contains(p, "BROKEN") {
			return mediatool.Probe{}, errors.New("ffprobe: invalid data")
		}
		raw, _ := json.Marshal(map[string]any{"format": map[string]any{"filename": p}})
		return mediatool.Probe{Raw: raw, Container: "matroska", DurationSeconds: 1400}, nil
	}
	first := "Show/Season 1/Show S01E12 HDTV.mkv"
	second := "Show/Season 1/Show S01E12 WEB.mkv"
	broken := "Show/Season 1/Show S01E12 BROKEN.mkv"

	f.scanSrc(&testSource{local: true, files: map[string][]byte{first: blob(36, 2*mib)}})
	id := f.mustID(first)

	f.scanSrc(&testSource{local: true, files: map[string][]byte{second: blob(37, 2*mib)}})
	var probed string
	if err := f.pool.QueryRow(f.ctx,
		`SELECT technical->'format'->>'filename' FROM media_items WHERE id = $1`, id).Scan(&probed); err != nil {
		t.Fatal(err)
	}
	if probed != second {
		t.Errorf("carried row's technical describes %q, want the new file %q", probed, second)
	}

	res := f.scanSrc(&testSource{local: true, files: map[string][]byte{broken: blob(38, 2*mib)}})
	if res.Carried != 1 || f.idOf(broken) != id {
		t.Fatalf("result = %+v; a probe failure must not stop the carry", res)
	}
	if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1 AND technical = '{}'::jsonb`, id); n != 1 {
		t.Error("a carry whose probe failed kept the previous file's technical")
	}
}

// TestHashReadFailureKeepsIdentity: one failed read of an unchanged file must
// not flip its identity — that would fail its ready stow package and orphan its
// caption cache. A failed read of a file whose size changed keeps nothing.
func TestHashReadFailureKeepsIdentity(t *testing.T) {
	f := newIdentityFixture(t)
	p := "Film B.mkv"
	data := blob(40, 2*mib)
	f.scan(map[string][]byte{p: data})
	id := f.mustID(p)

	identity := func() string {
		var hash *string
		var size *int64
		if err := f.pool.QueryRow(f.ctx,
			`SELECT content_hash, file_size FROM media_items WHERE id = $1`, id).Scan(&hash, &size); err != nil {
			t.Fatal(err)
		}
		return fileid.Identity(hash, size)
	}
	before := identity()
	if strings.HasPrefix(before, "s") || before == fileid.Unknown {
		t.Fatalf("first sweep left no hash (identity %q)", before)
	}

	mgr := stow.New(f.pool, nil, t.TempDir(), "software", 1, 0, slog.New(slog.NewTextHandler(io.Discard, nil)))
	var jobID string
	if err := f.pool.QueryRow(f.ctx,
		`INSERT INTO stow_jobs (account_id, item_id, state, source_identity, output_bytes, ready_at)
		 VALUES ($1, $2, 'ready', $3, 10, now()) RETURNING id::text`, f.account, id, before).Scan(&jobID); err != nil {
		t.Fatal(err)
	}

	f.scanSrc(&testSource{files: map[string][]byte{p: data}, failOpen: map[string]bool{p: true}})
	if got := identity(); got != before {
		t.Fatalf("identity after a failed read = %q, want it kept as %q", got, before)
	}
	job, ok, err := mgr.Get(f.ctx, f.account, jobID)
	if err != nil || !ok || job.State != stow.StateReady || job.Stale {
		t.Errorf("ready stow job after a failed read = %+v (ok %v, err %v), want still ready", job, ok, err)
	}
	if !strings.Contains(f.logs.String(), "hash read failed, kept previous hash") {
		t.Errorf("kept hash not logged:\n%s", f.logs.String())
	}

	f.scanSrc(&testSource{files: map[string][]byte{p: blob(41, 3*mib)}, failOpen: map[string]bool{p: true}})
	if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1 AND content_hash IS NULL`, id); n != 1 {
		t.Error("a failed read of a resized file kept the old hash")
	}
}

// TestAdoptionKeepsTheOlderID: both files for an episode were indexed, then one
// left. Whichever is older survives — it is the id stows and queued progress
// hold — with both rows' state merged into it.
func TestAdoptionKeepsTheOlderID(t *testing.T) {
	t.Run("the vanished row is older", func(t *testing.T) {
		f := newIdentityFixture(t)
		older := "Show/Season 1/Show S01E13 HDTV.mkv"
		younger := "Show/Season 1/Show S01E13 WEB.mkv"
		f.scan(map[string][]byte{older: blob(50, 2*mib)})
		olderID := f.mustID(older)
		f.watch(olderID, 300, false)

		f.scan(map[string][]byte{older: blob(50, 2*mib), younger: blob(51, 2*mib)})
		youngerID := f.mustID(younger)
		f.watch(youngerID, 900, true)

		var vaultID string
		if err := f.pool.QueryRow(f.ctx,
			`INSERT INTO vaults (account_id, owner_user_id, name) VALUES ($1, $2, 'v') RETURNING id::text`,
			f.account, f.user).Scan(&vaultID); err != nil {
			t.Fatal(err)
		}
		f.exec(`INSERT INTO vault_items (vault_id, media_item_id) VALUES ($1, $2), ($1, $3)`, vaultID, olderID, youngerID)

		res := f.scan(map[string][]byte{younger: blob(51, 2*mib)})
		if got := f.idOf(younger); got != olderID {
			t.Fatalf("surviving file is item %q, want the older %q (result %+v)", got, olderID, res)
		}
		if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1`, youngerID); n != 0 {
			t.Error("the younger row survived the adoption")
		}
		if pos, watched, ok := f.playState(olderID); !ok || pos != 900 || !watched {
			t.Errorf("merged play_state = (%v, %v, %v), want (900, watched): watched if either was, position from the later update", pos, watched, ok)
		}
		if n := f.count(`SELECT count(*) FROM vault_items WHERE vault_id = $1`, vaultID); n != 1 {
			t.Errorf("vault holds %d entries, want 1 (no duplicate)", n)
		}
		if n := f.count(`SELECT count(*) FROM vault_items WHERE vault_id = $1 AND media_item_id = $2`, vaultID, olderID); n != 1 {
			t.Error("the vault entry does not point at the survivor")
		}
		if _, linked, ok := f.episode("Show", 1, 13); !ok || linked != olderID {
			t.Errorf("E13 links %q, want %q", linked, olderID)
		}
		if !strings.Contains(f.logs.String(), "adopted indexed replacement") {
			t.Errorf("adoption not logged:\n%s", f.logs.String())
		}
	})

	t.Run("the seen row is older", func(t *testing.T) {
		f := newIdentityFixture(t)
		older := "Show/Season 1/Show S01E14 HDTV.mkv"
		younger := "Show/Season 1/Show S01E14 WEB.mkv"
		f.scan(map[string][]byte{older: blob(52, 2*mib)})
		olderID := f.mustID(older)
		f.watch(olderID, 100, true)

		f.scan(map[string][]byte{older: blob(52, 2*mib), younger: blob(53, 2*mib)})
		youngerID := f.mustID(younger)
		f.watch(youngerID, 700, false)

		f.scan(map[string][]byte{older: blob(52, 2*mib)})
		if got := f.idOf(older); got != olderID {
			t.Fatalf("older file is item %q, want it unchanged %q", got, olderID)
		}
		if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1`, youngerID); n != 0 {
			t.Error("the vanished younger row survived")
		}
		if pos, watched, ok := f.playState(olderID); !ok || pos != 700 || !watched {
			t.Errorf("merged play_state = (%v, %v, %v), want (700, watched)", pos, watched, ok)
		}
	})
}

// TestFailedAdoptionIsCountedAndHeldBack: an adoption that fails writes
// nothing, holds the vanished row back like a failed carry, and shows in the
// sweep's error count rather than only in the log.
func TestFailedAdoptionIsCountedAndHeldBack(t *testing.T) {
	f := newIdentityFixture(t)
	older := "Show/Season 1/Show S01E15 HDTV.mkv"
	younger := "Show/Season 1/Show S01E15 WEB.mkv"
	f.scan(map[string][]byte{older: blob(54, 2*mib)})
	olderID := f.mustID(older)
	f.scan(map[string][]byte{older: blob(54, 2*mib), younger: blob(55, 2*mib)})
	youngerID := f.mustID(younger)

	f.sc.identityHook = func(string) error { return errors.New("injected adoption failure") }
	res := f.scan(map[string][]byte{younger: blob(55, 2*mib)})
	if res.Errors != 1 {
		t.Errorf("result = %+v, want the failed adoption counted in Errors", res)
	}
	if n := f.count(`SELECT count(*) FROM media_items WHERE id = $1 AND carry_held_since IS NOT NULL`, olderID); n != 1 {
		t.Error("the older row was not held back after its adoption failed")
	}
	if f.idOf(younger) != youngerID {
		t.Error("a failed adoption still changed the younger row")
	}
}
