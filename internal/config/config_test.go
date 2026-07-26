package config

import "testing"

// TestLoadTMDBKnobs pins the operator-facing TMDB tuning env vars (ARGY-141):
// these are what stand between a 100TB ingest and an unthrottled match run,
// so a renamed env var must fail a test, not a production run.
func TestLoadTMDBKnobs(t *testing.T) {
	t.Setenv("TMDB_BASE_URL", "http://stub:9090")
	t.Setenv("TMDB_IMAGE_BASE_URL", "http://stub:9090/img")
	t.Setenv("ARGOSY_TMDB_RATE", "12.5")

	cfg := Load()
	if cfg.TMDBBaseURL != "http://stub:9090" {
		t.Errorf("TMDBBaseURL = %q", cfg.TMDBBaseURL)
	}
	if cfg.TMDBImageBaseURL != "http://stub:9090/img" {
		t.Errorf("TMDBImageBaseURL = %q", cfg.TMDBImageBaseURL)
	}
	if cfg.TMDBRate != 12.5 {
		t.Errorf("TMDBRate = %v", cfg.TMDBRate)
	}
}

func TestParseFloat(t *testing.T) {
	cases := []struct {
		in   string
		want float64
	}{
		{"", 0},
		{"25", 25},
		{" 40.5 ", 40.5},
		{"garbage", 0},
		{"-3", -3}, // negative passes through; NewTMDB treats ≤0 as "use default"
	}
	for _, c := range cases {
		if got := parseFloat(c.in); got != c.want {
			t.Errorf("parseFloat(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}
