package subtitle

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestEmbeddedTracksFiltersImageSubs(t *testing.T) {
	technical := []byte(`{"streams":[
		{"index":0,"codec_type":"video","codec_name":"h264"},
		{"index":1,"codec_type":"audio","codec_name":"aac"},
		{"index":2,"codec_type":"subtitle","codec_name":"subrip",
		 "tags":{"language":"eng","title":"English"},
		 "disposition":{"default":1,"forced":0}},
		{"index":3,"codec_type":"subtitle","codec_name":"ass",
		 "tags":{"language":"jpn"},
		 "disposition":{"default":0,"forced":1}},
		{"index":4,"codec_type":"subtitle","codec_name":"hdmv_pgs_subtitle",
		 "tags":{"language":"eng"}}
	]}`)

	tracks := embeddedTracks(technical)
	if len(tracks) != 2 {
		t.Fatalf("expected 2 text tracks (PGS excluded), got %d: %+v", len(tracks), tracks)
	}

	if tracks[0].ID != "embedded:2" || tracks[0].Language != "en" || !tracks[0].Default {
		t.Errorf("track0 unexpected: %+v", tracks[0])
	}
	if tracks[0].Label != "English" { // explicit title wins
		t.Errorf("track0 label = %q, want English", tracks[0].Label)
	}
	if tracks[1].ID != "embedded:3" || tracks[1].Language != "ja" || !tracks[1].Forced {
		t.Errorf("track1 unexpected: %+v", tracks[1])
	}
	if tracks[1].Label != "Japanese (Forced)" { // derived label + forced suffix
		t.Errorf("track1 label = %q, want \"Japanese (Forced)\"", tracks[1].Label)
	}
}

func TestEmbeddedTracksEmpty(t *testing.T) {
	if got := embeddedTracks(nil); len(got) != 0 {
		t.Errorf("expected no tracks for empty technical, got %+v", got)
	}
	if got := embeddedTracks([]byte("not json")); len(got) != 0 {
		t.Errorf("expected no tracks for bad json, got %+v", got)
	}
}

func TestMissingLangs(t *testing.T) {
	tracks := []Track{
		{Language: "en", Forced: false},
		{Language: "ja", Forced: true}, // forced-only doesn't cover ja
		{Language: "und", Forced: false},
	}
	got := missingLangs(tracks, []string{"en", "ja", "de"})
	want := []string{"ja", "de"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("missingLangs = %v, want %v", got, want)
	}
	if got := missingLangs(tracks, []string{"eng"}); len(got) != 0 { // 639-2 config normalizes
		t.Errorf("expected eng covered by embedded en, got %v", got)
	}
}

// osTestService wires a Service to a stub OpenSubtitles search endpoint. The
// handler receives the search request; hits counts calls.
func osTestService(t *testing.T, langs []string, handler func(w http.ResponseWriter, r *http.Request)) (*Service, *int) {
	t.Helper()
	hits := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		handler(w, r)
	}))
	t.Cleanup(srv.Close)
	os := NewOpenSubtitles("key", "user", "pass")
	os.searchBase = srv.URL
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return NewService(os, t.TempDir(), langs, logger), &hits
}

// osSearchBody builds a minimal search response with one result per language.
func osSearchBody(langs ...string) string {
	type file struct {
		FileID int64 `json:"file_id"`
	}
	data := []map[string]any{}
	for i, l := range langs {
		data = append(data, map[string]any{"attributes": map[string]any{
			"language": l, "download_count": 100 - i, "release": "Test.1080p",
			"files": []file{{FileID: int64(1000 + i)}},
		}})
	}
	b, _ := json.Marshal(map[string]any{"data": data})
	return string(b)
}

const engEmbeddedTechnical = `{"streams":[
	{"index":2,"codec_type":"subtitle","codec_name":"subrip",
	 "tags":{"language":"eng"},"disposition":{"default":0,"forced":0}}
]}`

func TestListSkipsSearchWhenEmbeddedCovers(t *testing.T) {
	s, hits := osTestService(t, []string{"en"}, func(_ http.ResponseWriter, _ *http.Request) {
		t.Error("OpenSubtitles search should not fire when embedded covers all wanted languages")
	})
	tracks := s.List(context.Background(), Target{ItemID: "item1", TMDBID: 42,
		Technical: []byte(engEmbeddedTechnical)})
	if len(tracks) != 1 || tracks[0].Source != "embedded" {
		t.Errorf("expected only the embedded track, got %+v", tracks)
	}
	if *hits != 0 {
		t.Errorf("expected 0 search calls, got %d", *hits)
	}
}

func TestListSearchesOnlyMissingLangsAndFiltersResults(t *testing.T) {
	s, _ := osTestService(t, []string{"en", "ja"}, func(w http.ResponseWriter, r *http.Request) {
		if got := r.URL.Query().Get("languages"); got != "ja" {
			t.Errorf("search languages = %q, want %q (en is embedded-covered)", got, "ja")
		}
		// The API answering with an en result anyway must not produce a duplicate.
		_, _ = fmt.Fprint(w, osSearchBody("ja", "en"))
	})
	tracks := s.List(context.Background(), Target{ItemID: "item2", TMDBID: 42,
		Technical: []byte(engEmbeddedTechnical)})
	if len(tracks) != 2 {
		t.Fatalf("expected embedded en + external ja, got %+v", tracks)
	}
	if tracks[1].Source != "opensubtitles" || tracks[1].Language != "ja" {
		t.Errorf("external track unexpected: %+v", tracks[1])
	}
}

func TestListCachesSearchPerItem(t *testing.T) {
	s, hits := osTestService(t, []string{"ja"}, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, osSearchBody("ja"))
	})
	target := Target{ItemID: "item3", TMDBID: 42, Technical: []byte(engEmbeddedTechnical)}
	for range 3 {
		if tracks := s.List(context.Background(), target); len(tracks) != 2 {
			t.Fatalf("expected 2 tracks, got %+v", tracks)
		}
	}
	if *hits != 1 {
		t.Errorf("expected 1 search call across repeat opens, got %d", *hits)
	}
}

func TestLangCodeAndName(t *testing.T) {
	cases := []struct{ in, code, name string }{
		{"eng", "en", "English"},
		{"ENG", "en", "English"},
		{"fra", "fr", "French"},
		{"jpn", "ja", "Japanese"},
		{"", "und", "Unknown"},
		{"xyz", "xyz", "XYZ"}, // unknown passes through, upper-cased name
	}
	for _, c := range cases {
		if got := langCode(c.in); got != c.code {
			t.Errorf("langCode(%q) = %q, want %q", c.in, got, c.code)
		}
		if got := langName(c.code); got != c.name {
			t.Errorf("langName(%q) = %q, want %q", c.code, got, c.name)
		}
	}
}
