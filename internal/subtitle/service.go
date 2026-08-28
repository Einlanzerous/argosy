package subtitle

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// maxExternalTracks caps how many OpenSubtitles candidates are surfaced per item
// — a couple of alternates in case the top match is mis-synced, without flooding
// the picker.
const maxExternalTracks = 3

// trackIDRe is the servable-track allowlist; it doubles as the cache-filename
// guard (the ":" becomes "-").
var trackIDRe = regexp.MustCompile(`^(embedded|os):\d+$`)

// textSubCodecs are the embedded subtitle codecs we can convert to WebVTT.
var textSubCodecs = map[string]bool{
	"subrip": true, "srt": true, "ass": true, "ssa": true,
	"mov_text": true, "webvtt": true, "text": true,
}

// imageSubCodecs are the embedded subtitle codecs that carry rendered bitmaps
// rather than characters. There is nothing to convert to WebVTT without OCR, so
// they are offered as burn-in tracks instead: the transcoder paints them into
// the frames (ARGY-59). Blu-ray rips are PGS, DVD rips are dvd_subtitle, and
// broadcast captures are dvb_subtitle; xsub is the DivX-era form.
var imageSubCodecs = map[string]bool{
	"hdmv_pgs_subtitle": true, "dvd_subtitle": true,
	"dvb_subtitle": true, "xsub": true,
}

// Target is everything needed to resolve subtitles for one media item.
type Target struct {
	ItemID       string
	Path         string          // absolute media path
	Technical    json.RawMessage // stored ffprobe JSON
	TMDBID       int64           // movie TMDB id (0 if none / is episode)
	ParentTMDBID int64           // series TMDB id (episodes)
	Season       int
	Episode      int
}

// Track is one selectable subtitle, embedded or external.
type Track struct {
	ID       string `json:"id"`       // "embedded:<idx>" | "os:<fileID>" | "burn:<idx>"
	Source   string `json:"source"`   // "embedded" | "opensubtitles"
	Language string `json:"language"` // BCP-47 code (e.g. "en")
	Label    string `json:"label"`    // human label for the picker
	Forced   bool   `json:"forced"`
	Default  bool   `json:"default"`
	// BurnIn marks an image-based track, which has no WebVTT form and is shown
	// by re-encoding it into the video (ARGY-59). Omitted for text tracks, so
	// their JSON is unchanged.
	BurnIn bool `json:"burnIn,omitempty"`
}

// ErrImageTrack is returned by VTT for a burn-in track. It is a refusal by
// design, not a failure to produce something that should exist, so callers can
// answer 400 rather than reporting an upstream problem they cannot fix.
var ErrImageTrack = errors.New("subtitle: image track has no WebVTT form")

// searchTTL bounds how often the same item re-queries OpenSubtitles — List runs
// on every player open, and results barely change between openings.
const searchTTL = time.Hour

type searchCacheEntry struct {
	tracks  []Track
	expires time.Time
}

// Service resolves and produces WebVTT subtitle tracks. os may be nil when
// OpenSubtitles isn't configured; embedded extraction still works.
type Service struct {
	os       *OpenSubtitles
	cacheDir string
	langs    []string
	logger   *slog.Logger

	mu       sync.Mutex
	searches map[string]searchCacheEntry
}

// NewService builds a subtitle service. os may be nil; langs defaults to ["en"].
func NewService(os *OpenSubtitles, cacheDir string, langs []string, logger *slog.Logger) *Service {
	if len(langs) == 0 {
		langs = []string{"en"}
	}
	return &Service{os: os, cacheDir: cacheDir, langs: langs, logger: logger,
		searches: map[string]searchCacheEntry{}}
}

// List returns the available subtitle tracks for an item: embedded text tracks
// (from ffprobe), plus OpenSubtitles candidates only for wanted languages that
// no embedded track covers (ARGY-153), plus any image-based tracks as burn-in
// candidates (ARGY-59). A failed external search degrades to embedded-only
// rather than erroring the whole list.
//
// Image tracks come last and never count as coverage. A burn-in costs a full
// re-encode and can't be switched off mid-session, so a text subtitle in the
// same language — including one fetched from OpenSubtitles — is strictly the
// better answer, and treating the image track as "this language is handled"
// would suppress the search that finds it.
func (s *Service) List(ctx context.Context, t Target) []Track {
	tracks := embeddedTracks(t.Technical)
	images := imageTracks(t.Technical)
	if s.os == nil || !s.os.Configured() {
		return append(tracks, images...)
	}
	missing := missingLangs(tracks, s.langs)
	if len(missing) == 0 {
		return append(tracks, images...)
	}
	tracks = append(tracks, s.externalTracks(ctx, t, missing)...)
	return append(tracks, images...)
}

// missingLangs returns the wanted languages no embedded track covers. Forced
// tracks don't count as coverage — they carry only foreign-dialogue lines, not
// full subtitles.
func missingLangs(embedded []Track, wanted []string) []string {
	covered := map[string]bool{}
	for _, tr := range embedded {
		if !tr.Forced {
			covered[tr.Language] = true
		}
	}
	missing := []string{}
	for _, l := range wanted {
		if c := langCode(l); !covered[c] {
			missing = append(missing, c)
		}
	}
	return missing
}

// externalTracks returns OpenSubtitles candidates for the given languages,
// serving repeat player opens from a short-lived per-item cache instead of
// re-querying (and re-hashing the file) every time.
func (s *Service) externalTracks(ctx context.Context, t Target, langs []string) []Track {
	key := t.ItemID + "|" + strings.Join(langs, ",")
	s.mu.Lock()
	if e, ok := s.searches[key]; ok && time.Now().Before(e.expires) {
		s.mu.Unlock()
		return e.tracks
	}
	s.mu.Unlock()

	q := Query{
		TMDBID:       t.TMDBID,
		ParentTMDBID: t.ParentTMDBID,
		Season:       t.Season,
		Episode:      t.Episode,
		Languages:    langs,
	}
	if h, err := MovieHash(t.Path); err != nil {
		s.logger.Warn("subtitle: moviehash failed", "item", t.ItemID, "err", err)
	} else {
		q.MovieHash = h
	}

	results, err := s.os.Search(ctx, q)
	if err != nil {
		// Not cached: a transient failure shouldn't suppress retries for an hour.
		s.logger.Warn("subtitle: opensubtitles search failed", "item", t.ItemID, "err", err)
		return nil
	}

	wanted := map[string]bool{}
	for _, l := range langs {
		wanted[l] = true
	}
	external := []Track{}
	seen := map[string]int{} // de-dupe identical labels with a counter suffix
	for _, r := range results {
		if len(external) >= maxExternalTracks {
			break
		}
		if !wanted[langCode(r.Language)] {
			continue
		}
		label := externalLabel(r)
		seen[label]++
		if n := seen[label]; n > 1 {
			label = fmt.Sprintf("%s (%d)", label, n)
		}
		external = append(external, Track{
			ID:       "os:" + strconv.FormatInt(r.FileID, 10),
			Source:   "opensubtitles",
			Language: r.Language,
			Label:    label,
		})
	}

	s.mu.Lock()
	now := time.Now()
	for k, e := range s.searches { // lazy prune, map stays household-sized
		if now.After(e.expires) {
			delete(s.searches, k)
		}
	}
	s.searches[key] = searchCacheEntry{tracks: external, expires: now.Add(searchTTL)}
	s.mu.Unlock()
	return external
}

// VTT produces (or returns the cached) WebVTT file for a track and returns its
// path on disk. Production is atomic (temp file + rename), so concurrent callers
// are safe.
func (s *Service) VTT(ctx context.Context, t Target, trackID string) (string, error) {
	if strings.HasPrefix(trackID, BurnInPrefix) {
		// Listed by List, but deliberately not servable here: it is a bitmap.
		// Say so, rather than letting it fall through to the generic "invalid
		// track id" a typo produces (ARGY-59).
		return "", fmt.Errorf("%w: track %q is burned in during transcode", ErrImageTrack, trackID)
	}
	if !trackIDRe.MatchString(trackID) {
		return "", fmt.Errorf("invalid track id %q", trackID)
	}
	dir := filepath.Join(s.cacheDir, t.ItemID)
	dest := filepath.Join(dir, strings.ReplaceAll(trackID, ":", "-")+".vtt")
	if _, err := os.Stat(dest); err == nil {
		return dest, nil
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}

	tmp, err := os.CreateTemp(dir, ".vtt-*")
	if err != nil {
		return "", err
	}
	tmpName := tmp.Name()
	_ = tmp.Close()
	defer func() { _ = os.Remove(tmpName) }() // no-op once renamed

	kind, arg, _ := strings.Cut(trackID, ":")
	switch kind {
	case "embedded":
		if err := s.extractEmbedded(ctx, t.Path, arg, tmpName); err != nil {
			return "", err
		}
	case "os":
		if err := s.fetchExternal(ctx, arg, tmpName); err != nil {
			return "", err
		}
	}
	if err := os.Rename(tmpName, dest); err != nil {
		return "", err
	}
	return dest, nil
}

// extractEmbedded pulls one embedded subtitle stream out of the source and lets
// ffmpeg convert it to WebVTT.
func (s *Service) extractEmbedded(ctx context.Context, src, streamIdx, dest string) error {
	cmd := exec.CommandContext(ctx, "ffmpeg", "-y", "-loglevel", "error",
		"-i", src, "-map", "0:"+streamIdx, "-c:s", "webvtt", "-f", "webvtt", dest)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("extract subtitle stream %s: %w: %s", streamIdx, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// fetchExternal downloads an OpenSubtitles file and converts it to WebVTT.
func (s *Service) fetchExternal(ctx context.Context, fileIDStr, dest string) error {
	if s.os == nil || !s.os.Configured() {
		return fmt.Errorf("opensubtitles not configured")
	}
	fileID, err := strconv.ParseInt(fileIDStr, 10, 64)
	if err != nil {
		return err
	}
	srt, err := s.os.Download(ctx, fileID)
	if err != nil {
		return err
	}
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer func() { _ = f.Close() }()
	if err := SRTToVTT(strings.NewReader(string(srt)), f); err != nil {
		return err
	}
	return f.Close()
}

// subtitleStream is one subtitle stream as ffprobe describes it.
type subtitleStream struct {
	Index     int    `json:"index"`
	CodecType string `json:"codec_type"`
	CodecName string `json:"codec_name"`
	Tags      struct {
		Language string `json:"language"`
		Title    string `json:"title"`
	} `json:"tags"`
	Disposition struct {
		Default int `json:"default"`
		Forced  int `json:"forced"`
	} `json:"disposition"`
}

// subtitleStreams pulls every subtitle stream out of the stored ffprobe JSON,
// in file order. Index is ffprobe's absolute stream index, which is what both
// the extraction map (`0:<idx>`) and the burn-in filtergraph link (`[0:<idx>]`)
// address.
func subtitleStreams(technical json.RawMessage) []subtitleStream {
	var doc struct {
		Streams []subtitleStream `json:"streams"`
	}
	if len(technical) == 0 {
		return nil
	}
	if err := json.Unmarshal(technical, &doc); err != nil {
		return nil
	}
	var out []subtitleStream
	for _, st := range doc.Streams {
		if st.CodecType == "subtitle" {
			out = append(out, st)
		}
	}
	return out
}

// embeddedTracks enumerates text-based subtitle streams from the stored ffprobe
// JSON. Image-based streams are enumerated separately, by imageTracks.
func embeddedTracks(technical json.RawMessage) []Track {
	tracks := []Track{}
	for _, st := range subtitleStreams(technical) {
		if !textSubCodecs[st.CodecName] {
			continue
		}
		lang := langCode(st.Tags.Language)
		tracks = append(tracks, Track{
			ID:       "embedded:" + strconv.Itoa(st.Index),
			Source:   "embedded",
			Language: lang,
			Label:    embeddedLabel(st.Tags.Title, lang, st.Disposition.Forced == 1),
			Forced:   st.Disposition.Forced == 1,
			Default:  st.Disposition.Default == 1,
		})
	}
	return tracks
}

// imageTracks enumerates image-based subtitle streams as burn-in candidates
// (ARGY-59). Their ids carry the `burn:` prefix rather than `embedded:` so that
// nothing can route one into the WebVTT path by accident: trackIDRe rejects
// them, so the subtitles endpoint refuses the id instead of shelling out to
// ffmpeg to convert a bitmap into text and failing there.
func imageTracks(technical json.RawMessage) []Track {
	var tracks []Track
	for _, st := range subtitleStreams(technical) {
		if !imageSubCodecs[st.CodecName] {
			continue
		}
		lang := langCode(st.Tags.Language)
		tracks = append(tracks, Track{
			ID:       BurnInPrefix + strconv.Itoa(st.Index),
			Source:   "embedded",
			Language: lang,
			Label:    embeddedLabel(st.Tags.Title, lang, st.Disposition.Forced == 1),
			Forced:   st.Disposition.Forced == 1,
			Default:  st.Disposition.Default == 1,
			BurnIn:   true,
		})
	}
	return tracks
}

// BurnInPrefix marks a track id as an image subtitle to be drawn into the video
// rather than served as WebVTT.
const BurnInPrefix = "burn:"

// BurnInStream resolves a burn-in track id against an item's stored ffprobe JSON
// and returns the absolute source stream index to overlay. ok is false for
// anything that is not a `burn:<n>` id naming an image subtitle stream of *this*
// item.
//
// It validates against the item rather than just parsing the id because the
// index goes straight into an ffmpeg filtergraph. A caller that passed
// "burn:0" — the video — would otherwise build a graph that consumes the video
// stream twice and fails at session start, and one that passed a text stream's
// index would silently produce a video with nothing drawn on it.
func BurnInStream(technical json.RawMessage, trackID string) (int, bool) {
	arg, ok := strings.CutPrefix(trackID, BurnInPrefix)
	if !ok {
		return 0, false
	}
	idx, err := strconv.Atoi(arg)
	if err != nil {
		return 0, false
	}
	for _, st := range subtitleStreams(technical) {
		if st.Index == idx && imageSubCodecs[st.CodecName] {
			return idx, true
		}
	}
	return 0, false
}

func embeddedLabel(title, lang string, forced bool) string {
	if title != "" {
		return title
	}
	label := langName(lang)
	if forced {
		label += " (Forced)"
	}
	return label
}

// resRe pulls a resolution token out of a release name for a compact label.
var resRe = regexp.MustCompile(`(?i)\b(2160p|1440p|1080p|720p|480p)\b`)

// externalLabel builds a short, scannable label: the language plus one
// distinguishing hint — "best match" for the moviehash hit, else a resolution
// token from the release (raw release names are too noisy for a picker).
func externalLabel(r Subtitle) string {
	label := langName(r.Language)
	switch {
	case r.MovieHashMatch:
		label += " · best match"
	case resRe.FindString(r.Release) != "":
		label += " · " + strings.ToLower(resRe.FindString(r.Release))
	}
	if r.HearingImpaired {
		label += " · SDH"
	}
	return label
}
