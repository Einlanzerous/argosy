package stevedore

import (
	"reflect"
	"testing"
)

func TestDeriveTags(t *testing.T) {
	cases := []struct {
		path string
		want []string
	}{
		{"anime/Cowboy Bebop/Season 1/Cowboy Bebop S01E01.mkv", []string{"anime"}},
		{"Anime/Akira (1988).mkv", []string{"anime"}}, // case-insensitive; a film stays a film
		{"movies/Big Buck Bunny (2008).mkv", nil},
		{"tv/The Show/Season 1/The Show S01E01.mkv", nil},
		{"anime/anime/Redundant.mkv", []string{"anime"}}, // de-duped
	}
	for _, c := range cases {
		got := deriveTags(c.path)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("deriveTags(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}
