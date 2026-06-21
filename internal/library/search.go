package library

import (
	"context"
	"strings"
	"unicode"

	"github.com/Einlanzerous/argosy/internal/api"
)

// searchTSQuery turns free user input into a safe prefix tsquery string, e.g.
// `your na` -> `your:* & na:*`. The input is split on any non-alphanumeric run
// (matching how the text-search parser tokenizes, so `sci-fi` -> `sci:* & fi:*`),
// each token becomes a prefix term (so typeahead matches as you type), and the
// terms are AND-ed so more words narrow the result. Splitting on non-alphanumerics
// also strips the tsquery operators (& | ! ( ) : *), so the input can't inject
// query syntax; Unicode letters are preserved so non-Latin titles still search.
// Returns "" for input with no usable tokens (caller then returns empty results).
func searchTSQuery(raw string) string {
	tokens := strings.FieldsFunc(raw, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
	terms := make([]string, 0, len(tokens))
	for _, tok := range tokens {
		terms = append(terms, strings.ToLower(tok)+":*")
	}
	return strings.Join(terms, " & ")
}

// Search runs account-scoped full-text search over films and series, grouped by
// kind and ranked by relevance (ts_rank_cd, which honors the A/B/C weights so a
// title hit outranks a body hit), with a title tiebreak. An empty or all-symbol
// query returns empty groups. limit caps each group independently.
func (s *Store) Search(ctx context.Context, accountID, query string, limit int) (api.SearchResults, error) {
	res := api.SearchResults{Movies: []api.MediaItemSummary{}, Series: []api.SeriesSummary{}}
	tsq := searchTSQuery(query)
	if tsq == "" {
		return res, nil
	}
	switch {
	case limit < 1:
		limit = 8
	case limit > 25:
		limit = 25
	}

	movieRows, err := s.pool.Query(ctx,
		`SELECT mi.id::text, mi.kind, mi.title, mi.year, mi.tags, mi.provider_metadata, mi.metadata
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.kind = 'movie'
		   AND mi.search_vector @@ to_tsquery('simple', $2)
		 ORDER BY ts_rank_cd(mi.search_vector, to_tsquery('simple', $2)) DESC,
		          mi.sort_title ASC NULLS LAST, mi.title ASC
		 LIMIT $3`,
		accountID, tsq, limit)
	if err != nil {
		return res, err
	}
	defer movieRows.Close()
	for movieRows.Next() {
		var id, kind, title string
		var year *int
		var tags []string
		var prov, over []byte
		if err := movieRows.Scan(&id, &kind, &title, &year, &tags, &prov, &over); err != nil {
			return res, err
		}
		res.Movies = append(res.Movies, s.summary(id, kind, title, year, tags, prov, over))
	}
	if err := movieRows.Err(); err != nil {
		return res, err
	}

	seriesRows, err := s.pool.Query(ctx,
		`SELECT r.id::text, r.title, r.year, r.tags, r.provider_metadata, r.metadata
		 FROM series r JOIN libraries l ON l.id = r.library_id
		 WHERE l.account_id = $1 AND r.search_vector @@ to_tsquery('simple', $2)
		 ORDER BY ts_rank_cd(r.search_vector, to_tsquery('simple', $2)) DESC,
		          r.sort_title ASC NULLS LAST, r.title ASC
		 LIMIT $3`,
		accountID, tsq, limit)
	if err != nil {
		return res, err
	}
	defer seriesRows.Close()
	for seriesRows.Next() {
		var id, title string
		var year *int
		var tags []string
		var prov, over []byte
		if err := seriesRows.Scan(&id, &title, &year, &tags, &prov, &over); err != nil {
			return res, err
		}
		res.Series = append(res.Series, s.seriesSummary(id, title, year, tags, prov, over))
	}
	return res, seriesRows.Err()
}
