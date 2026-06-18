// Package config loads runtime configuration from the environment.
package config

import "os"

// Config holds runtime configuration for the Argosy server.
type Config struct {
	// Addr is the host:port the HTTP server listens on.
	Addr string
	// DatabaseURL is the PostgreSQL connection string (used from the Phase 0 schema work onward).
	DatabaseURL string
	// MediaDir is the root the ingestion layer reads from. The storage
	// abstraction (local FS vs. Pydio Cells) lands in Phase 1.
	MediaDir string
}

// Load reads configuration from the environment, applying sensible defaults.
func Load() Config {
	return Config{
		Addr:        getenv("ARGOSY_ADDR", ":8096"),
		DatabaseURL: os.Getenv("ARGOSY_DATABASE_URL"),
		MediaDir:    getenv("ARGOSY_MEDIA_DIR", "/media"),
	}
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
