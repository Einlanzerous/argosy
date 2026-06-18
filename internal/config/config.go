// Package config loads runtime configuration from the environment.
package config

import (
	"net"
	"net/url"
	"os"
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
	// AdminUsername/AdminPassword, when both set, bootstrap an admin account on
	// first startup if one with that username does not already exist.
	AdminUsername string
	AdminPassword string
	// TMDB credentials for metadata matching (either is sufficient).
	TMDBReadToken string
	TMDBAPIKey    string
	// ArtworkDir is where downloaded poster/artwork files are cached.
	ArtworkDir string
	// ScanInterval is how often Stevedore re-sweeps every library to keep the
	// Manifest current (fsnotify is unreliable over the SMB mount, ARGY-53).
	// Zero disables the periodic sweep; on-demand scans still work.
	ScanInterval time.Duration
}

// Load reads configuration from the environment, applying sensible defaults.
func Load() Config {
	return Config{
		Addr:          getenv("ARGOSY_ADDR", ":8096"),
		DatabaseURL:   resolveDatabaseURL(),
		MediaDir:      getenv("ARGOSY_MEDIA_DIR", "/media"),
		AdminUsername: os.Getenv("ARGOSY_ADMIN_USERNAME"),
		AdminPassword: os.Getenv("ARGOSY_ADMIN_PASSWORD"),
		TMDBReadToken: os.Getenv("TMDB_API_READ_ACCESS_KEY"),
		TMDBAPIKey:    os.Getenv("TMDB_API_KEY"),
		ArtworkDir:    getenv("ARGOSY_ARTWORK_DIR", "artwork"),
		ScanInterval:  parseDuration(os.Getenv("ARGOSY_SCAN_INTERVAL")),
	}
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
