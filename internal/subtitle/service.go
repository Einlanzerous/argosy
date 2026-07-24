package subtitle

import (
	"context"
	"encoding/json"
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
// Image-based codecs (hdmv_pgs_subtitle, dvd_subtitle, dvb_subtitle) need OCR or
// burn-in (ARGY-59) and are excluded.
var textSubCodecs = map[string]bool{
	"subrip": true, "srt": true, "ass": true, "ssa": true,
	"mov_text": true, "webvtt": true, "text": true,
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
	ID       string `json:"id"`       // "embedded:<idx>" | "os:<fileID>"
	Source   string `json:"source"`   // "embedded" | "opensubtitles"
	Language string `json:"language"` // BCP-47 code (e.g. "en")
	Label    string `json:"label"`    // human label for the picker
	Forced   bool   `json:"forced"`
	Default  bool   `json:"default"`
}

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
// no embedded track covers (ARGY-153). A failed external search degrades to
// embedded-only rather than erroring the whole list.
func (s *Service) List(ctx context.Context, t Target) []Track {
	tracks := embeddedTracks(t.Technical)
	if s.os == nil || !s.os.Configured() {
		return tracks
	}
	missing := missingLangs(tracks, s.langs)
	if len(missing) == 0 {
		return tracks
	}
	return append(tracks, s.externalTracks(ctx, t, missing)...)
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

// embeddedTracks enumerates text-based subtitle streams from the stored ffprobe
// JSON. Image-based streams are skipped (left to burn-in, ARGY-59).
func embeddedTracks(technical json.RawMessage) []Track {
	var doc struct {
		Streams []struct {
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
		} `json:"streams"`
	}
	tracks := []Track{}
	if len(technical) == 0 {
		return tracks
	}
	if err := json.Unmarshal(technical, &doc); err != nil {
		return tracks
	}
	for _, st := range doc.Streams {
		if st.CodecType != "subtitle" || !textSubCodecs[st.CodecName] {
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
