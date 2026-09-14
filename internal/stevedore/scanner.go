package stevedore

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"path"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/Einlanzerous/argosy/internal/mediasource"
	"github.com/Einlanzerous/argosy/internal/mediatool"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// mediaExts is the allowlist of file extensions treated as media.
var mediaExts = map[string]bool{
	".mkv": true, ".mp4": true, ".m4v": true, ".avi": true, ".mov": true,
	".webm": true, ".ts": true, ".m2ts": true, ".wmv": true, ".mpg": true, ".mpeg": true,
}

// episodeRe detects a season/episode marker (SxxEyy) anywhere in a filename.
var episodeRe = regexp.MustCompile(`(?i)s\d{1,2}e\d{1,3}`)

// contentMatchMinSize is the smallest file matched to its replacement by content.
// partialHash covers the first MiB, so below this it hashes the whole file — and
// every empty or truncated placeholder shares one hash, however unrelated. Equal
// size doesn't separate them either: two empty files are the same size.
const contentMatchMinSize = 1 << 20

// carryHoldBack is how long a row whose carry failed is kept from prune. Long
// enough for a transient failure to be retried by the next few sweeps, short
// enough that a carry that fails every time doesn't keep a fileless row forever.
const carryHoldBack = time.Hour

// Prober extracts technical metadata from a local file path.
type Prober func(ctx context.Context, path string) (mediatool.Probe, error)

// Scanner walks a library source and upserts media_items, enriching each with
// ffprobe technical metadata.
type Scanner struct {
	pool       *pgxpool.Pool
	logger     *slog.Logger
	probe      Prober
	workers    int
	artworkDir string // where local-poster overrides are cached ("" disables copying)

	// identityHook, when set, runs inside a carry's or an adoption's transaction
	// before it commits; an error rolls it back. Tests use it to make one fail.
	identityHook func(itemID string) error
}

// NewScanner returns a Scanner using the real ffprobe-backed prober.
func NewScanner(pool *pgxpool.Pool, logger *slog.Logger, artworkDir string) *Scanner {
	return &Scanner{pool: pool, logger: logger, probe: mediatool.ProbeFile, workers: 4, artworkDir: artworkDir}
}

// Result summarizes a scan.
type Result struct {
	Scanned int
	Errors  int
	// Removed counts media_items pruned because their file vanished from disk
	// (e.g. renamed or deleted) since the previous sweep.
	Removed int
	// Carried counts vanished rows that kept their id by taking over the file
	// that replaced them (ARGY-238), rather than being pruned.
	Carried int
}

// Scan enumerates src, ingesting every media file into the library, then prunes
// any rows whose file no longer exists. It is idempotent: re-scanning updates
// existing rows (keyed on library_id+file_path) and reconciles deletions.
//
// A file that replaced one which vanished — a Sonarr upgrade, a rename — takes
// over the vanished row instead of minting a new one, so the item keeps its id
// and with it every profile's play_state and every stowed copy (ARGY-238).
func (s *Scanner) Scan(ctx context.Context, libraryID string, src mediasource.Source) (Result, error) {
	var entries []mediasource.Entry
	if err := src.Walk(ctx, func(e mediasource.Entry) error {
		if mediaExts[strings.ToLower(path.Ext(e.Path))] {
			entries = append(entries, e)
		}
		return nil
	}); err != nil {
		return Result{}, err
	}
	seen := make([]string, len(entries))
	for i, e := range entries {
		seen[i] = e.Path
	}

	// Decide which vanished rows carry onto which files before anything is
	// written, so no row is ever inserted for a replacement.
	plan, err := s.planIdentity(ctx, libraryID, src, entries)
	if err != nil {
		return Result{}, err
	}
	// Replacements already indexed in an earlier sweep. These run before ingest
	// so that, when the older row survives at the newer file's path, that path's
	// ingest refreshes the survivor.
	for _, a := range plan.adoptions {
		_ = s.adopt(ctx, a)
	}

	var (
		wg   sync.WaitGroup
		mu   sync.Mutex
		res  Result
		jobs = make(chan mediasource.Entry)
	)
	worker := func() {
		defer wg.Done()
		for e := range jobs {
			// A matched path's ingest *is* its carry: probed and written in one
			// statement, so no committed row ever pairs the new path with the old
			// file's technical metadata.
			c, carried := plan.carries[e.Path]
			var err error
			if carried {
				err = s.carry(ctx, libraryID, src, e, c)
			} else {
				err = s.ingest(ctx, libraryID, src, e)
			}
			mu.Lock()
			switch {
			case err != nil && carried:
				// Logged and held back by carry. The path itself is skipped this
				// sweep — not inserted — so the next sweep still sees a
				// replacement and retries the carry.
				res.Errors++
			case err != nil:
				s.logger.Warn("ingest failed", "path", e.Path, "err", err)
				res.Errors++
			case carried:
				res.Scanned++
				res.Carried++
			default:
				res.Scanned++
			}
			mu.Unlock()
		}
	}
	for range s.workers {
		wg.Add(1)
		go worker()
	}
	for _, e := range entries {
		select {
		case <-ctx.Done():
			close(jobs)
			wg.Wait()
			return res, ctx.Err()
		case jobs <- e:
		}
	}
	close(jobs)
	wg.Wait()

	// Group episodes into series/seasons and parse movie years (single-threaded).
	// Only rows whose file was seen: a vanished row must never claim a slot.
	if err := s.classify(ctx, libraryID, seen); err != nil {
		return res, err
	}
	// Apply local NFO/sidecar + artwork overrides.
	if err := s.ApplyOverrides(ctx, libraryID, src); err != nil {
		return res, err
	}
	// Reconcile deletions: drop rows for files that vanished since last sweep.
	removed, err := s.prune(ctx, libraryID, seen)
	if err != nil {
		return res, err
	}
	res.Removed = removed
	if removed > 0 || res.Carried > 0 {
		s.logger.Info("pruned missing media", "library", libraryID, "removed", removed, "carried", res.Carried)
	}
	return res, nil
}

// indexedFile is what matching needs to know about an indexed file.
type indexedFile struct {
	id, filePath, kind string
	contentHash        *string
	fileSize           *int64
	createdAt          time.Time
}

// olderThan reports whether r was indexed before o. Classify's order uses the
// same (created_at, id) comparison, so "older" means one thing everywhere.
func (r indexedFile) olderThan(o indexedFile) bool {
	if !r.createdAt.Equal(o.createdAt) {
		return r.createdAt.Before(o.createdAt)
	}
	return r.id < o.id
}

// carryPlan says which vanished row a newly walked file takes over.
type carryPlan struct {
	from   indexedFile
	method string
	// hash is the new file's partial hash when the content pass already read it.
	hash *string
}

// adoption pairs a vanished row with a row already indexed for its replacement.
type adoption struct {
	vanished, seen indexedFile
	method         string
}

type identityPlan struct {
	carries   map[string]carryPlan // by the new file's path
	adoptions []adoption
}

// Matching methods, as logged.
const (
	methodContent     = "content_hash"
	methodEpisodeSlot = "episode_slot"
	methodMovieFolder = "movie_folder"
)

// planIdentity matches every vanished row to the file that replaced it, when
// that can be told without guessing (ARGY-238).
//
// A vanished row is first matched against files with no row yet (a carry), then
// against rows already indexed (an adoption: both files sat on disk for a while).
// Each runs three passes, and each pass consumes what it pairs:
//
//  1. identical content — equal size of at least contentMatchMinSize and equal
//     first-MiB hash, whatever the paths say. A pure rename or move, including a
//     renumbering, which the slot pass would get wrong;
//  2. episode slot — the same show, season and episode set;
//  3. movie folder — the same per-movie directory.
//
// A pair must be one to one. A key with several rows or files on either side is
// ambiguous, carries nothing, and is left to prune exactly as before.
func (s *Scanner) planIdentity(ctx context.Context, libraryID string, src mediasource.Source, entries []mediasource.Entry) (identityPlan, error) {
	plan := identityPlan{carries: map[string]carryPlan{}}
	// Same guard as prune: an empty walk is a transient unmount, not a library
	// whose every file was replaced.
	if len(entries) == 0 {
		return plan, nil
	}

	rows, err := s.indexedFiles(ctx, libraryID)
	if err != nil {
		return plan, err
	}
	walked := make(map[string]bool, len(entries))
	for _, e := range entries {
		walked[e.Path] = true
	}
	indexed := make(map[string]bool, len(rows))
	var vanished, seenRows []indexedFile
	for _, r := range rows {
		indexed[r.filePath] = true
		if walked[r.filePath] {
			seenRows = append(seenRows, r)
		} else {
			vanished = append(vanished, r)
		}
	}
	if len(vanished) == 0 {
		return plan, nil
	}
	var arrived []mediasource.Entry
	for _, e := range entries {
		if !indexed[e.Path] {
			arrived = append(arrived, e)
		}
	}
	// A folder still holding a film nobody replaced is shared, not one film's
	// own, so a replacement inside it can't be told from a different film.
	sharedDirs := map[string]bool{}
	for _, r := range seenRows {
		if r.kind == "movie" {
			sharedDirs[path.Dir(r.filePath)] = true
		}
	}
	ownFolder := func(k string, ok bool) (string, bool) { return k, ok && !sharedDirs[k] }

	// Only files the same size as some vanished row could match by content, so
	// only those are hashed here; everything else waits for its own ingest.
	sizes := map[int64]bool{}
	for _, v := range vanished {
		if v.contentHash != nil && *v.contentHash != "" && v.fileSize != nil && *v.fileSize >= contentMatchMinSize {
			sizes[*v.fileSize] = true
		}
	}
	hashes := map[string]*string{}
	for _, e := range arrived {
		if e.Size < contentMatchMinSize || !sizes[e.Size] {
			continue
		}
		if h, err := partialHash(ctx, src, e.Path); err == nil {
			hashes[e.Path] = &h
		}
	}

	matched := map[string]bool{} // vanished row ids already paired
	ambiguous := map[string]string{}
	remaining := func() []indexedFile {
		out := vanished[:0:0]
		for _, v := range vanished {
			if !matched[v.id] {
				out = append(out, v)
			}
		}
		return out
	}

	// Carries: vanished rows onto files with no row yet.
	claimedPath := map[string]bool{}
	arrivedPasses := []struct {
		method string
		vKey   func(indexedFile) (string, bool)
		eKey   func(mediasource.Entry) (string, bool)
	}{
		{methodContent, rowContentKey, func(e mediasource.Entry) (string, bool) {
			h, ok := hashes[e.Path]
			if !ok {
				return "", false
			}
			return contentKey(*h, e.Size), true
		}},
		{methodEpisodeSlot, rowEpisodeKey, func(e mediasource.Entry) (string, bool) {
			if kindOf(e.Path) != "episode" {
				return "", false
			}
			return episodeKey(e.Path)
		}},
		{methodMovieFolder, func(r indexedFile) (string, bool) {
			return ownFolder(rowMovieFolderKey(r))
		}, func(e mediasource.Entry) (string, bool) {
			if kindOf(e.Path) != "movie" {
				return "", false
			}
			return ownFolder(movieFolderKey(e.Path))
		}},
	}
	for _, pass := range arrivedPasses {
		var free []mediasource.Entry
		for _, e := range arrived {
			if !claimedPath[e.Path] {
				free = append(free, e)
			}
		}
		for _, p := range pairUp(remaining(), free, pass.vKey, pass.eKey, pass.method, ambiguous) {
			matched[p.row.id] = true
			claimedPath[p.cand.Path] = true
			plan.carries[p.cand.Path] = carryPlan{from: p.row, method: pass.method, hash: hashes[p.cand.Path]}
		}
	}

	// Adoptions: vanished rows onto rows already indexed for their replacement.
	//
	// No movie-folder pass here. With both files indexed, "a folder that held a
	// film and its replacement, one now gone" reads exactly like "a folder of
	// two different films, one now deleted", and the second must not hand the
	// deleted film's id and watched state to the other. A film whose bytes match
	// still adopts through the content pass.
	claimedRow := map[string]bool{}
	seenPasses := []struct {
		method string
		key    func(indexedFile) (string, bool)
	}{
		{methodContent, rowContentKey},
		{methodEpisodeSlot, rowEpisodeKey},
	}
	for _, pass := range seenPasses {
		var free []indexedFile
		for _, r := range seenRows {
			if !claimedRow[r.id] {
				free = append(free, r)
			}
		}
		for _, p := range pairUp(remaining(), free, pass.key, pass.key, pass.method, ambiguous) {
			matched[p.row.id] = true
			claimedRow[p.cand.id] = true
			plan.adoptions = append(plan.adoptions, adoption{vanished: p.row, seen: p.cand, method: pass.method})
		}
	}

	for _, v := range vanished {
		if why, ok := ambiguous[v.id]; ok && !matched[v.id] {
			s.logger.Warn("replacement ambiguous, not carried",
				"library", libraryID, "item", v.id, "path", v.filePath, "match", why)
		}
	}
	return plan, nil
}

type pair[C any] struct {
	row  indexedFile
	cand C
}

// pairUp matches rows to candidates sharing a key, one to one. A key held by
// more than one row or more than one candidate pairs nothing; the rows under it
// are noted in ambiguous so they can be reported if no later pass pairs them.
func pairUp[C any](rows []indexedFile, cands []C, rowKey func(indexedFile) (string, bool), candKey func(C) (string, bool), method string, ambiguous map[string]string) []pair[C] {
	byRow := map[string][]indexedFile{}
	for _, r := range rows {
		if k, ok := rowKey(r); ok {
			byRow[k] = append(byRow[k], r)
		}
	}
	if len(byRow) == 0 {
		return nil
	}
	byCand := map[string][]C{}
	for _, c := range cands {
		if k, ok := candKey(c); ok {
			if _, relevant := byRow[k]; relevant {
				byCand[k] = append(byCand[k], c)
			}
		}
	}
	var out []pair[C]
	for k, rs := range byRow {
		cs := byCand[k]
		switch {
		case len(cs) == 0:
		case len(rs) == 1 && len(cs) == 1:
			out = append(out, pair[C]{row: rs[0], cand: cs[0]})
		default:
			for _, r := range rs {
				ambiguous[r.id] = fmt.Sprintf("%s %q: %d vanished, %d candidates", method, k, len(rs), len(cs))
			}
		}
	}
	return out
}

func contentKey(hash string, size int64) string {
	return hash + "|" + strconv.FormatInt(size, 10)
}

func rowContentKey(r indexedFile) (string, bool) {
	if r.contentHash == nil || *r.contentHash == "" || r.fileSize == nil || *r.fileSize < contentMatchMinSize {
		return "", false
	}
	return contentKey(*r.contentHash, *r.fileSize), true
}

func rowEpisodeKey(r indexedFile) (string, bool) {
	if r.kind != "episode" {
		return "", false
	}
	return episodeKey(r.filePath)
}

func rowMovieFolderKey(r indexedFile) (string, bool) {
	if r.kind != "movie" {
		return "", false
	}
	return movieFolderKey(r.filePath)
}

// episodeKey is the slot an episode file fills: the show as Classify groups it,
// the season, and the full episode set (so a combined rip's slot differs from
// either of its single-episode replacements).
func episodeKey(filePath string) (string, bool) {
	info, ok := parseEpisode(filePath)
	if !ok {
		return "", false
	}
	eps := slices.Clone(info.episodes)
	slices.Sort(eps)
	nums := make([]string, len(eps))
	for i, n := range eps {
		nums[i] = strconv.Itoa(n)
	}
	return sortTitle(info.show) + "|" + strconv.Itoa(info.season) + "|" + strings.Join(nums, ","), true
}

// movieFolderKey is a movie's own directory, the way Radarr lays one out. A file
// at the library root, or directly under a category folder (movies/, films/…),
// shares its directory with every other film and has no folder of its own.
func movieFolderKey(filePath string) (string, bool) {
	dir := path.Dir(filePath)
	if dir == "." || dir == "/" || dir == "" || categoryDirs[strings.ToLower(path.Base(dir))] {
		return "", false
	}
	return dir, true
}

// slotOf is what an item's episode link depends on. A carry between different
// slots has to clear the old link; nothing else ever would, since the link is
// only cleared by deleting the item.
func slotOf(filePath, kind string) string {
	if kind == "episode" {
		if k, ok := episodeKey(filePath); ok {
			return k
		}
	}
	return "movie"
}

// kindOf classifies a file by name, as ingest always has.
func kindOf(filePath string) string {
	if episodeRe.MatchString(path.Base(filePath)) {
		return "episode"
	}
	return "movie"
}

// indexedFiles loads what matching needs for every row in the library.
func (s *Scanner) indexedFiles(ctx context.Context, libraryID string) ([]indexedFile, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT id::text, file_path, kind, content_hash, file_size, created_at
		   FROM media_items WHERE library_id = $1`, libraryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []indexedFile
	for rows.Next() {
		var r indexedFile
		if err := rows.Scan(&r.id, &r.filePath, &r.kind, &r.contentHash, &r.fileSize, &r.createdAt); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// fileFacts is what ingest learns about a file.
type fileFacts struct {
	kind, title string
	technical   json.RawMessage
	container   any
	duration    any
	hash        *string
	hashErr     error
}

// inspect probes and hashes a file. A probe failure is not an error — the file
// is still recorded, with empty technical metadata — and neither is a hash
// failure; hashErr says which happened. knownHash skips a hash already read.
func (s *Scanner) inspect(ctx context.Context, src mediasource.Source, e mediasource.Entry, knownHash *string) fileFacts {
	f := fileFacts{kind: kindOf(e.Path), title: titleFromPath(e.Path), technical: json.RawMessage("{}")}
	if local, ok := src.LocalPath(e.Path); ok {
		if p, err := s.probe(ctx, local); err != nil {
			s.logger.Warn("probe failed", "path", e.Path, "err", err)
		} else {
			if len(p.Raw) > 0 {
				f.technical = p.Raw
			}
			if p.Container != "" {
				f.container = p.Container
			}
			if p.DurationSeconds > 0 {
				f.duration = p.DurationSeconds
			}
		}
	}
	if knownHash != nil {
		f.hash = knownHash
	} else if h, err := partialHash(ctx, src, e.Path); err == nil {
		f.hash = &h
	} else {
		f.hashErr = err
	}
	return f
}

func (s *Scanner) ingest(ctx context.Context, libraryID string, src mediasource.Source, e mediasource.Entry) error {
	f := s.inspect(ctx, src, e, nil)

	// A failed hash read keeps the row's previous hash when the size hasn't
	// changed. Without that, one transient read error (a file mid-move, a disk
	// hiccup) would flip an unchanged file's identity and back over two sweeps,
	// failing its stow packages and orphaning its caption cache each time. A
	// same-name, same-size replacement whose read also fails keeps the old
	// identity for one sweep; that is the cheaper mistake.
	//
	// Being seen also clears any carry hold-back, so a file that went missing
	// once and came back doesn't enter a later failure with its hour used up.
	var hashed bool
	err := s.pool.QueryRow(ctx, `
		INSERT INTO media_items
			(library_id, kind, title, sort_title, file_path, container, duration_seconds,
			 content_hash, file_size, technical)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT (library_id, file_path) DO UPDATE SET
			kind = EXCLUDED.kind,
			title = EXCLUDED.title,
			sort_title = EXCLUDED.sort_title,
			container = EXCLUDED.container,
			duration_seconds = EXCLUDED.duration_seconds,
			content_hash = COALESCE(EXCLUDED.content_hash,
				CASE WHEN media_items.file_size = EXCLUDED.file_size THEN media_items.content_hash END),
			file_size = EXCLUDED.file_size,
			technical = EXCLUDED.technical,
			carry_held_since = NULL,
			updated_at = now()
		RETURNING content_hash IS NOT NULL`,
		libraryID, f.kind, f.title, sortTitle(f.title), e.Path, f.container, f.duration,
		f.hash, e.Size, f.technical).Scan(&hashed)
	if err != nil {
		return err
	}
	if f.hashErr != nil {
		if hashed {
			s.logger.Warn("hash read failed, kept previous hash", "path", e.Path, "err", f.hashErr)
		} else {
			s.logger.Warn("hash read failed", "path", e.Path, "err", f.hashErr)
		}
	}
	return nil
}

// carry re-points a vanished row at the file that replaced it. It is that file's
// ingest: the row gets the new path and everything probed from the new file in
// one statement, and keeps its id, added_at, provider match, play_state and
// vault entries. If the move changes slot — a renumbering, a move into another
// show — the item's old episode link is cleared too; Classify links the new
// one, and prune sweeps what's left.
//
// A failed carry writes nothing and holds the vanished row back from prune (see
// holdBack), so the next sweep retries it instead of the cascade taking the
// row's state.
func (s *Scanner) carry(ctx context.Context, libraryID string, src mediasource.Source, e mediasource.Entry, c carryPlan) error {
	f := s.inspect(ctx, src, e, c.hash)
	slotChanged := slotOf(c.from.filePath, c.from.kind) != slotOf(e.Path, f.kind)
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE media_items SET
				file_path = $2, kind = $3, title = $4, sort_title = $5, container = $6,
				duration_seconds = $7, content_hash = $8, file_size = $9, technical = $10,
				carry_held_since = NULL, updated_at = now()
			WHERE id = $1 AND library_id = $11`,
			c.from.id, e.Path, f.kind, f.title, sortTitle(f.title), f.container, f.duration,
			f.hash, e.Size, f.technical, libraryID)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return fmt.Errorf("item %s no longer exists", c.from.id)
		}
		if slotChanged {
			if _, err := tx.Exec(ctx, `UPDATE episodes SET media_item_id = NULL WHERE media_item_id = $1`, c.from.id); err != nil {
				return err
			}
		}
		if s.identityHook != nil {
			return s.identityHook(c.from.id)
		}
		return nil
	})
	if err != nil {
		s.holdBack(ctx, c.from, err)
		return err
	}
	s.logger.Info("carried item identity", "library", libraryID, "item", c.from.id, "method", c.method,
		"old_path", c.from.filePath, "new_path", e.Path, "slot_changed", slotChanged)
	return nil
}

// adopt settles a vanished row against a row already indexed for its
// replacement: both files were on disk for at least a sweep. The older id
// survives either way, because it is the one clients have held longest — stows,
// queued progress, vault entries, Continue Watching.
//
//   - Vanished row older: the younger row's state merges into it, the younger
//     row is deleted, and the vanished row takes over its path and the metadata
//     already probed from that file. The slot-change rule applies as for a carry.
//   - Seen row older: the vanished row's state merges into it, and prune removes
//     the vanished row as usual. Nothing needs re-pointing.
func (s *Scanner) adopt(ctx context.Context, a adoption) error {
	vanishedOlder := a.vanished.olderThan(a.seen)
	slotChanged := false
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if !vanishedOlder {
			if err := mergeItemState(ctx, tx, a.vanished.id, a.seen.id); err != nil {
				return err
			}
			if s.identityHook != nil {
				return s.identityHook(a.vanished.id)
			}
			return nil
		}

		if err := mergeItemState(ctx, tx, a.seen.id, a.vanished.id); err != nil {
			return err
		}
		var (
			filePath, kind, title string
			sortTitle, container  *string
			duration              *float64
			hash                  *string
			size                  *int64
			technical             []byte
		)
		// Deleted first: the path is unique, and the survivor is about to take it.
		if err := tx.QueryRow(ctx, `
			DELETE FROM media_items WHERE id = $1
			RETURNING file_path, kind, title, sort_title, container, duration_seconds,
			          content_hash, file_size, technical`, a.seen.id).Scan(
			&filePath, &kind, &title, &sortTitle, &container, &duration, &hash, &size, &technical); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE media_items SET
				file_path = $2, kind = $3, title = $4, sort_title = $5, container = $6,
				duration_seconds = $7, content_hash = $8, file_size = $9, technical = $10,
				carry_held_since = NULL, updated_at = now()
			WHERE id = $1`,
			a.vanished.id, filePath, kind, title, sortTitle, container, duration, hash, size, technical); err != nil {
			return err
		}
		slotChanged = slotOf(a.vanished.filePath, a.vanished.kind) != slotOf(filePath, kind)
		if slotChanged {
			if _, err := tx.Exec(ctx, `UPDATE episodes SET media_item_id = NULL WHERE media_item_id = $1`, a.vanished.id); err != nil {
				return err
			}
		}
		if s.identityHook != nil {
			return s.identityHook(a.vanished.id)
		}
		return nil
	})
	if err != nil {
		s.holdBack(ctx, a.vanished, err)
		return err
	}
	survivor, retired := a.seen, a.vanished
	if vanishedOlder {
		survivor, retired = a.vanished, a.seen
	}
	s.logger.Info("adopted indexed replacement", "item", survivor.id, "retired", retired.id,
		"method", a.method, "old_path", a.vanished.filePath, "new_path", a.seen.filePath,
		"slot_changed", slotChanged)
	return nil
}

// mergeItemState moves one item's per-profile state onto another. Where a
// profile has play_state on both, it is watched if either was, and position,
// duration and device come from whichever row was updated last. A vault entry
// moves unless the vault already holds the target.
func mergeItemState(ctx context.Context, tx pgx.Tx, fromID, toID string) error {
	if _, err := tx.Exec(ctx, `
		INSERT INTO play_state (user_id, media_item_id, position_seconds, duration_seconds, watched, updated_at, device_id)
		SELECT user_id, $2, position_seconds, duration_seconds, watched, updated_at, device_id
		  FROM play_state WHERE media_item_id = $1
		ON CONFLICT (user_id, media_item_id) DO UPDATE SET
			watched          = play_state.watched OR EXCLUDED.watched,
			position_seconds = CASE WHEN EXCLUDED.updated_at > play_state.updated_at
			                        THEN EXCLUDED.position_seconds ELSE play_state.position_seconds END,
			duration_seconds = CASE WHEN EXCLUDED.updated_at > play_state.updated_at
			                        THEN EXCLUDED.duration_seconds ELSE play_state.duration_seconds END,
			device_id        = CASE WHEN EXCLUDED.updated_at > play_state.updated_at
			                        THEN EXCLUDED.device_id ELSE play_state.device_id END,
			updated_at       = GREATEST(play_state.updated_at, EXCLUDED.updated_at)`,
		fromID, toID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `DELETE FROM play_state WHERE media_item_id = $1`, fromID); err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE vault_items vi SET media_item_id = $2
		 WHERE vi.media_item_id = $1
		   AND NOT EXISTS (SELECT 1 FROM vault_items o WHERE o.vault_id = vi.vault_id AND o.media_item_id = $2)`,
		fromID, toID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `DELETE FROM vault_items WHERE media_item_id = $1`, fromID)
	return err
}

// holdBack marks a vanished row whose carry or adoption failed, so prune keeps
// it for carryHoldBack from the first failure rather than letting the cascade
// take its state over what may be a transient error.
func (s *Scanner) holdBack(ctx context.Context, r indexedFile, cause error) {
	var since time.Time
	if err := s.pool.QueryRow(ctx,
		`UPDATE media_items SET carry_held_since = COALESCE(carry_held_since, now())
		  WHERE id = $1 RETURNING carry_held_since`, r.id).Scan(&since); err != nil {
		s.logger.Warn("carry failed, and holding it back failed too", "item", r.id, "path", r.filePath,
			"err", cause, "hold_err", err)
		return
	}
	s.logger.Warn("carry failed, held back from prune", "item", r.id, "path", r.filePath,
		"err", cause, "held_since", since)
}

// prune reconciles the library against what's currently on disk: it removes
// media_items whose file_path wasn't seen this sweep (renamed or deleted files),
// then the episodes/seasons/series those deletions leave empty. Deleting a
// media_item cascades its play_state / vault / label rows and NULLs the owning
// episode's media_item_id (FK ON DELETE SET NULL), so the orphan sweep that
// follows clears those now-fileless episodes.
//
// A row that was replaced rather than removed never reaches here: the scan has
// already carried it onto its replacement's path, or merged it into the older
// indexed row (ARGY-238). What prune still deletes is a file that went with no
// replacement that could be told apart from a guess — and so still takes its
// state with it. The exception is a row whose carry failed: it is held back for
// carryHoldBack, so a transient failure costs a retry rather than the row's
// state, and then pruned as before.
//
// It is a deliberate no-op when nothing was seen: the media root is an SMB mount,
// and a transient unmount makes Walk yield zero entries — pruning then would wipe
// the entire library. (Walk errors already abort the scan before we reach here;
// this guards the "mounted but empty" case.)
func (s *Scanner) prune(ctx context.Context, libraryID string, seen []string) (int, error) {
	if len(seen) == 0 {
		return 0, nil
	}
	holdSecs := carryHoldBack.Seconds()

	// Rows whose hold-back has run out are pruned below like any other; say so,
	// since their state goes with them.
	expired, err := s.pool.Query(ctx,
		`SELECT id::text, file_path FROM media_items
		  WHERE library_id = $1 AND file_path <> ALL($2)
		    AND carry_held_since IS NOT NULL
		    AND carry_held_since <= now() - make_interval(secs => $3)`,
		libraryID, seen, holdSecs)
	if err != nil {
		return 0, err
	}
	for expired.Next() {
		var id, filePath string
		if err := expired.Scan(&id, &filePath); err != nil {
			expired.Close()
			return 0, err
		}
		s.logger.Warn("carry failed repeatedly, pruning", "library", libraryID, "item", id, "path", filePath)
	}
	expired.Close()
	if err := expired.Err(); err != nil {
		return 0, err
	}

	tag, err := s.pool.Exec(ctx,
		`DELETE FROM media_items
		  WHERE library_id = $1 AND file_path <> ALL($2)
		    AND (carry_held_since IS NULL OR carry_held_since <= now() - make_interval(secs => $3))`,
		libraryID, seen, holdSecs)
	if err != nil {
		return 0, err
	}
	removed := int(tag.RowsAffected())

	// Episodes orphaned by the deletes above (media_item_id NULLed), scoped to
	// this library via their season → series chain. This also sweeps the old
	// slot of a carry that changed slot.
	if _, err := s.pool.Exec(ctx,
		`DELETE FROM episodes e
		  WHERE e.media_item_id IS NULL
		    AND e.season_id IN (
		      SELECT se.id FROM seasons se
		      JOIN series sr ON sr.id = se.series_id
		      WHERE sr.library_id = $1
		    )`, libraryID); err != nil {
		return removed, err
	}
	// Seasons, then series, left with no children.
	//
	// A season carrying an operator's provider mapping is kept even when empty.
	// The prune guard above is library-wide, so one show's files going missing
	// for a single sweep — a rename in flight, a season folder briefly absent —
	// is enough to delete the row, and Classify recreates it with the mapping
	// columns NULL. That silently discards a hand-set mapping the resolver
	// otherwise promises never to overwrite (ARGY-224). An empty season row
	// costs nothing and disappears the moment the operator clears the mapping.
	if _, err := s.pool.Exec(ctx,
		`DELETE FROM seasons se
		  WHERE se.series_id IN (SELECT id FROM series WHERE library_id = $1)
		    AND NOT EXISTS (SELECT 1 FROM episodes e WHERE e.season_id = se.id)
		    AND se.provider_season_source IS DISTINCT FROM 'manual'`,
		libraryID); err != nil {
		return removed, err
	}
	if _, err := s.pool.Exec(ctx,
		`DELETE FROM series sr
		  WHERE sr.library_id = $1
		    AND NOT EXISTS (SELECT 1 FROM seasons se WHERE se.series_id = sr.id)`,
		libraryID); err != nil {
		return removed, err
	}
	return removed, nil
}

// partialHash hashes the first 1 MiB of a file — a cheap, stable signature for
// dedup/identity across mirrors without reading entire media files.
func partialHash(ctx context.Context, src mediasource.Source, rel string) (string, error) {
	rc, err := src.Open(ctx, rel)
	if err != nil {
		return "", err
	}
	defer func() { _ = rc.Close() }()
	h := sha256.New()
	if _, err := io.CopyN(h, rc, 1<<20); err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func titleFromPath(p string) string {
	base := path.Base(p)
	base = strings.TrimSuffix(base, path.Ext(base))
	base = strings.NewReplacer(".", " ", "_", " ").Replace(base)
	return strings.Join(strings.Fields(base), " ")
}

func sortTitle(title string) string {
	t := strings.ToLower(title)
	for _, prefix := range []string{"the ", "a ", "an "} {
		if rest, ok := strings.CutPrefix(t, prefix); ok {
			return rest
		}
	}
	return t
}
