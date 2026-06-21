package metadata

import "testing"

func TestGenreNames(t *testing.T) {
	got := GenreNames([]int{28, 878, 99999, 18})
	want := []string{"Action", "Science Fiction", "Drama"} // unknown 99999 dropped, order kept
	if len(got) != len(want) {
		t.Fatalf("GenreNames = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("GenreNames = %v, want %v", got, want)
		}
	}
	if GenreNames(nil) != nil {
		t.Errorf("GenreNames(nil) = %v, want nil", GenreNames(nil))
	}
}
