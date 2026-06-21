package metadata

// TMDB exposes genres as numeric IDs on search results; the names come from a
// fixed, well-known list (the union of TMDB's movie and TV genre lists). We map
// IDs to names at match time so genres are stored as human-readable strings —
// usable for display, search, and the genre filter — without an extra API call.
// Source: TMDB /genre/movie/list + /genre/tv/list (stable IDs).
var tmdbGenres = map[int]string{
	28:    "Action",
	12:    "Adventure",
	16:    "Animation",
	35:    "Comedy",
	80:    "Crime",
	99:    "Documentary",
	18:    "Drama",
	10751: "Family",
	14:    "Fantasy",
	36:    "History",
	27:    "Horror",
	10402: "Music",
	9648:  "Mystery",
	10749: "Romance",
	878:   "Science Fiction",
	10770: "TV Movie",
	53:    "Thriller",
	10752: "War",
	37:    "Western",
	// TV-specific genres.
	10759: "Action & Adventure",
	10762: "Kids",
	10763: "News",
	10764: "Reality",
	10765: "Sci-Fi & Fantasy",
	10766: "Soap",
	10767: "Talk",
	10768: "War & Politics",
}

// GenreNames maps TMDB genre IDs to their names, preserving order and dropping
// any unknown IDs. Returns nil for empty input so callers can omit the field.
func GenreNames(ids []int) []string {
	var out []string
	for _, id := range ids {
		if name, ok := tmdbGenres[id]; ok {
			out = append(out, name)
		}
	}
	return out
}
