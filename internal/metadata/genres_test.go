package metadata

import "testing"

func TestGenreNames(t *testing.T) {
	eq := func(got, want []string) {
		t.Helper()
		if len(got) != len(want) {
			t.Fatalf("GenreNames = %v, want %v", got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("GenreNames = %v, want %v", got, want)
			}
		}
	}
	// Unknown ID dropped, order preserved.
	eq(GenreNames([]int{28, 878, 99999, 18}), []string{"Action", "Science Fiction", "Drama"})
	// TV combined genres expand to movie-vocab names.
	eq(GenreNames([]int{10759, 10765}), []string{"Action", "Adventure", "Science Fiction", "Fantasy"})
	// De-dupe: movie "Action" (28) + TV "Action & Adventure" (10759) collapse.
	eq(GenreNames([]int{28, 10759}), []string{"Action", "Adventure"})
	// "Sci-Fi & Fantasy" (10765) and "Science Fiction" (878) share the canonical.
	eq(GenreNames([]int{878, 10765}), []string{"Science Fiction", "Fantasy"})
	if GenreNames(nil) != nil {
		t.Errorf("GenreNames(nil) = %v, want nil", GenreNames(nil))
	}
}
