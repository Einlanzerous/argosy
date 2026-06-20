package subtitle

import "testing"

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
