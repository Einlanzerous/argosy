package metadata

// TMDB exposes genres as numeric IDs on search results; the names come from a
// fixed, well-known list (the union of TMDB's movie and TV genre lists). We map
// IDs to names at match time so genres are stored as human-readable strings —
// usable for display, search, and the genre filter — without an extra API call.
// Source: TMDB /genre/movie/list + /genre/tv/list (stable IDs).
//
// TMDB's TV vocabulary bundles genres the movie vocabulary keeps separate
// ("Action & Adventure", "Sci-Fi & Fantasy", "War & Politics"). We normalize
// those to the finer-grained movie names so a show and a film land under the same
// facet/filter — otherwise "Action" and "Action & Adventure" both surface as
// distinct genres. Hence each ID maps to one *or more* canonical names.
var tmdbGenres = map[int][]string{
	28:    {"Action"},
	12:    {"Adventure"},
	16:    {"Animation"},
	35:    {"Comedy"},
	80:    {"Crime"},
	99:    {"Documentary"},
	18:    {"Drama"},
	10751: {"Family"},
	14:    {"Fantasy"},
	36:    {"History"},
	27:    {"Horror"},
	10402: {"Music"},
	9648:  {"Mystery"},
	10749: {"Romance"},
	878:   {"Sci-Fi"},
	10770: {"TV Movie"},
	53:    {"Thriller"},
	10752: {"War"},
	37:    {"Western"},
	// TV-specific genres, normalized to the movie vocabulary where they overlap.
	10759: {"Action", "Adventure"},        // Action & Adventure
	10765: {"Sci-Fi", "Fantasy"}, // Sci-Fi & Fantasy
	10768: {"War"},                        // War & Politics
	10762: {"Kids"},
	10763: {"News"},
	10764: {"Reality"},
	10766: {"Soap"},
	10767: {"Talk"},
}

// GenreNames maps TMDB genre IDs to canonical names, preserving first-seen order,
// dropping unknown IDs, and de-duplicating (a combined TV genre can expand to a
// name another ID also yields). Returns nil for empty input so callers can omit
// the field.
func GenreNames(ids []int) []string {
	seen := map[string]bool{}
	var out []string
	for _, id := range ids {
		for _, name := range tmdbGenres[id] {
			if !seen[name] {
				seen[name] = true
				out = append(out, name)
			}
		}
	}
	return out
}
