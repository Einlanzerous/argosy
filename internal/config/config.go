// Package config loads runtime configuration from the environment.
package config

import (
	"net"
	"net/url"
	"os"
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
}

// Load reads configuration from the environment, applying sensible defaults.
func Load() Config {
	return Config{
		Addr:        getenv("ARGOSY_ADDR", ":8096"),
		DatabaseURL: resolveDatabaseURL(),
		MediaDir:    getenv("ARGOSY_MEDIA_DIR", "/media"),
	}
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
