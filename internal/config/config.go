// Package config loads runtime configuration from the environment.
package config

import (
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Config holds runtime configuration for the Argosy server.
type Config struct {
	// Addr is the host:port the HTTP server listens on.
	Addr string
	// DatabaseURL is the resolved PostgreSQL DSN. Empty means no database is
	// configured and the server runs without one (handy for `make server-dev`).
	DatabaseURL string
	// MediaDir is the root the ingestion layer reads from. The storage
	// abstraction (local FS vs. Pydio Cells) lands in Phase 1.
	MediaDir string
	// AdminEmail/AdminPassword, when both set, bootstrap an admin account on
	// first startup if no account exists yet (ARGY-159: keyed on "any account",
	// not the specific email, so renaming a login never re-triggers it).
	AdminEmail    string
	AdminPassword string
	// ProvisionToken, when set, enables the /api/v1/admin/accounts surface for
	// machine-to-machine account lifecycle (Purser): create (ARGY-132), look up
	// (ARGY-163), revoke and purge (ARGY-187). Requests must present it in the
	// X-Provision-Token header. Empty leaves the routes unregistered, so an
	// unconfigured server answers 404 rather than 401.
	ProvisionToken string
	// TMDB credentials for metadata matching (either is sufficient).
	TMDBReadToken string
	TMDBAPIKey    string
	// TMDBBaseURL / TMDBImageBaseURL override the API and artwork endpoints so
	// a stub server can stand in for TMDB (ARGY-139); empty uses the real one.
	TMDBBaseURL      string
	TMDBImageBaseURL string
	// TMDBRate caps sustained TMDB request throughput in requests/second,
	// shared across all endpoints and artwork downloads (ARGY-141). Zero uses
	// the client's built-in default.
	TMDBRate float64
	// ArtworkDir is where downloaded poster/artwork files are cached.
	ArtworkDir string
	// ScanInterval is how often Stevedore re-sweeps every library to keep the
	// Manifest current (fsnotify is unreliable over the SMB mount, ARGY-53).
	// Zero disables the periodic sweep; on-demand scans still work.
	ScanInterval time.Duration
	// TranscodeDir is where The Helm writes per-session HLS artifacts (Ballast
	// manages their lifecycle). Defaults to <os.TempDir>/argosy-transcode.
	TranscodeDir string
	// TranscodeIdleTimeout is how long a session may go without a playlist or
	// segment request before it's killed and purged.
	TranscodeIdleTimeout time.Duration
	// MaxTranscodeSessions caps concurrent transcode sessions (back-pressure).
	MaxTranscodeSessions int
	// EncoderPreference is the encoder fallback order (e.g. nvenc,vaapi,qsv,
	// software). Empty uses transcode.DefaultPreference.
	EncoderPreference []string
	// ForceSoftware pins encoding to libx264/libx265 regardless of hardware
	// (debugging aid; see ARGY-30). It skips the hardware probe rather than
	// discarding its result, so it stays usable on a host with a wedged GPU
	// driver — the case you most want it for (ARGY-183).
	ForceSoftware bool
	// TranscodeCacheBudget is the high-water mark (bytes) for the transcode
	// cache dir; Ballast evicts idle sessions oldest-first when exceeded.
	TranscodeCacheBudget int64
	// StowDir is where offline-download packages are written, one directory per
	// job (ARGY-49). Defaults to <os.TempDir>/argosy-stow.
	StowDir string
	// MaxStowJobs caps concurrent offline packaging encodes. Zero means 1:
	// packaging competes with live playback for the same encoder and nobody is
	// waiting on it in realtime, so it yields by default.
	MaxStowJobs int
	// StowRetention is how long a finished package is kept before the server
	// reclaims it. Zero uses stow.DefaultRetention. The device normally releases
	// its job as soon as the download lands, so this only catches uncollected
	// packages.
	StowRetention time.Duration
	// StowPassthroughMax is the size ceiling (bytes) for handing a source file to
	// a device untouched instead of packaging a smaller copy. Zero uses
	// library.DefaultStowPassthroughMax.
	StowPassthroughMax int64
	// SubtitleDir is where converted WebVTT subtitle files are cached. Defaults
	// to <os.TempDir>/argosy-subtitles.
	SubtitleDir string
	// OpenSubtitles credentials. External subtitle fetch is enabled only when
	// all three are set: search alone needs just the key, but download is quota'd
	// per logged-in user, so username+password are required to be useful.
	OpenSubtitlesAPIKey   string
	OpenSubtitlesUsername string
	OpenSubtitlesPassword string
	// SubtitleLanguages is the ISO-639 language set to fetch external subtitles
	// for (comma-separated, e.g. "en,es"). Empty defaults to English.
	SubtitleLanguages []string
	// PreferredLanguages is the household's preferred audio/subtitle language
	// set (comma-separated ISO-639). Clients show matching tracks by default
	// and fold the rest behind "More options" (ARGY-154). Distinct from
	// SubtitleLanguages, which controls what gets *fetched* externally.
	PreferredLanguages []string
	// ServerName is the human-friendly name advertised over mDNS and shown by
	// clients during PIN pairing (ARGY-123).
	ServerName string
	// DisableMDNS turns off LAN service advertising (e.g. when the deployment
	// network can't multicast anyway and the log noise isn't wanted).
	DisableMDNS bool
}

// Load reads configuration from the environment, applying sensible defaults.
func Load() Config {
	return Config{
		Addr:        getenv("ARGOSY_ADDR", ":8096"),
		DatabaseURL: resolveDatabaseURL(),
		MediaDir:    getenv("ARGOSY_MEDIA_DIR", "/media"),
		// ARGOSY_ADMIN_USERNAME is the pre-ARGY-159 name, kept as a fallback so
		// existing deployments don't need an env change to keep booting.
		AdminEmail:       getenv("ARGOSY_ADMIN_EMAIL", os.Getenv("ARGOSY_ADMIN_USERNAME")),
		AdminPassword:    os.Getenv("ARGOSY_ADMIN_PASSWORD"),
		ProvisionToken:   os.Getenv("ARGOSY_PROVISION_TOKEN"),
		TMDBReadToken:    os.Getenv("TMDB_API_READ_ACCESS_KEY"),
		TMDBAPIKey:       os.Getenv("TMDB_API_KEY"),
		TMDBBaseURL:      os.Getenv("TMDB_BASE_URL"),
		TMDBImageBaseURL: os.Getenv("TMDB_IMAGE_BASE_URL"),
		TMDBRate:         parseFloat(os.Getenv("ARGOSY_TMDB_RATE")),
		ArtworkDir:       getenv("ARGOSY_ARTWORK_DIR", "artwork"),
		ScanInterval:     parseDuration(os.Getenv("ARGOSY_SCAN_INTERVAL")),

		TranscodeDir:         getenv("ARGOSY_TRANSCODE_DIR", filepath.Join(os.TempDir(), "argosy-transcode")),
		TranscodeIdleTimeout: parseDuration(os.Getenv("ARGOSY_TRANSCODE_IDLE_TIMEOUT")),
		MaxTranscodeSessions: parseInt(os.Getenv("ARGOSY_MAX_TRANSCODE_SESSIONS")),
		EncoderPreference:    parseList(os.Getenv("ARGOSY_ENCODER_PREFERENCE")),
		ForceSoftware:        os.Getenv("ARGOSY_FORCE_SOFTWARE") == "1" || os.Getenv("ARGOSY_FORCE_SOFTWARE") == "true",
		TranscodeCacheBudget: parseSize(os.Getenv("ARGOSY_TRANSCODE_CACHE_BUDGET")),

		StowDir:            getenv("ARGOSY_STOW_DIR", filepath.Join(os.TempDir(), "argosy-stow")),
		MaxStowJobs:        parseInt(os.Getenv("ARGOSY_MAX_STOW_JOBS")),
		StowRetention:      parseDuration(os.Getenv("ARGOSY_STOW_RETENTION")),
		StowPassthroughMax: parseSize(os.Getenv("ARGOSY_STOW_PASSTHROUGH_MAX")),

		SubtitleDir:           getenv("ARGOSY_SUBTITLE_DIR", filepath.Join(os.TempDir(), "argosy-subtitles")),
		OpenSubtitlesAPIKey:   os.Getenv("OPEN_SUBTITLES_API_KEY"),
		OpenSubtitlesUsername: os.Getenv("OPEN_SUBTITLES_USERNAME"),
		OpenSubtitlesPassword: os.Getenv("OPEN_SUBTITLES_PASSWORD"),
		SubtitleLanguages:     parseList(os.Getenv("ARGOSY_SUBTITLE_LANGUAGES")),
		PreferredLanguages:    parseList(getenv("ARGOSY_PREFERRED_LANGUAGES", "en,ja")),

		ServerName:  getenv("ARGOSY_SERVER_NAME", "Argosy"),
		DisableMDNS: os.Getenv("ARGOSY_DISABLE_MDNS") == "1" || os.Getenv("ARGOSY_DISABLE_MDNS") == "true",
	}
}

// parseSize parses a byte size with an optional K/M/G suffix (powers of 1024),
// e.g. "10G", "500M", "1048576". Returns 0 for empty/invalid (callers default).
func parseSize(s string) int64 {
	s = strings.TrimSpace(strings.ToUpper(s))
	if s == "" {
		return 0
	}
	mult := int64(1)
	switch s[len(s)-1] {
	case 'K':
		mult, s = 1<<10, s[:len(s)-1]
	case 'M':
		mult, s = 1<<20, s[:len(s)-1]
	case 'G':
		mult, s = 1<<30, s[:len(s)-1]
	case 'B':
		s = s[:len(s)-1]
	}
	n, err := strconv.ParseInt(strings.TrimSpace(s), 10, 64)
	if err != nil || n < 0 {
		return 0
	}
	return n * mult
}

// parseFloat returns the float value of s, or 0 when empty/invalid (callers
// apply their own default).
func parseFloat(s string) float64 {
	f, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if err != nil {
		return 0
	}
	return f
}

// parseInt returns the int value of s, or 0 when empty/invalid (callers apply
// their own default).
func parseInt(s string) int {
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return n
}

// parseList splits a comma-separated list, trimming spaces and dropping empties.
func parseList(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if v := strings.TrimSpace(p); v != "" {
			out = append(out, v)
		}
	}
	return out
}

// parseDuration parses a Go duration string (e.g. "15m", "1h"). It returns 0
// for an empty or invalid value, leaving the periodic sweep disabled.
func parseDuration(s string) time.Duration {
	d, err := time.ParseDuration(s)
	if err != nil {
		return 0
	}
	return d
}

// resolveDatabaseURL prefers an explicit ARGOSY_DATABASE_URL, otherwise builds a
// DSN from ARGOSY_DB_* parts. Building it at runtime keeps any credential out of
// committed config (no connection-string literal). Returns "" when no database
// is configured.
func resolveDatabaseURL() string {
	if dsn := os.Getenv("ARGOSY_DATABASE_URL"); dsn != "" {
		return dsn
	}
	host := os.Getenv("ARGOSY_DB_HOST")
	if host == "" {
		return ""
	}
	u := url.URL{
		Scheme: "postgres",
		Host:   net.JoinHostPort(host, getenv("ARGOSY_DB_PORT", "5432")),
		Path:   "/" + getenv("ARGOSY_DB_NAME", "argosy"),
	}
	if pw := os.Getenv("ARGOSY_DB_PASSWORD"); pw != "" {
		u.User = url.UserPassword(getenv("ARGOSY_DB_USER", "argosy"), pw)
	} else {
		u.User = url.User(getenv("ARGOSY_DB_USER", "argosy"))
	}
	q := url.Values{}
	q.Set("sslmode", getenv("ARGOSY_DB_SSLMODE", "disable"))
	u.RawQuery = q.Encode()
	return u.String()
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
