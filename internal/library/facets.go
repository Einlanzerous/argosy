package library

import (
	"context"

	"github.com/Einlanzerous/argosy/internal/api"
)

// Facets returns the most common facets — genres and path/label tags merged into
// one ranking by item count — across the account's films and series. It powers
// the discovery chips. Episodes are excluded (they carry neither genres nor
// meaningful tags); counts are over standalone movies + series. Genres read the
// effective value (override blob over provider).
func (s *Store) Facets(ctx context.Context, accountID string, limit int) ([]api.Facet, error) {
	switch {
	case limit < 1:
		limit = 8
	case limit > 50:
		limit = 50
	}
	const q = `
WITH facets AS (
	SELECT 'tag' AS type, t AS value
	FROM media_items mi JOIN libraries l ON l.id = mi.library_id, unnest(mi.tags) AS t
	WHERE l.account_id = $1 AND mi.kind = 'movie'
	UNION ALL
	SELECT 'genre', g
	FROM media_items mi JOIN libraries l ON l.id = mi.library_id,
	     jsonb_array_elements_text(COALESCE(mi.metadata->'genres', mi.provider_metadata->'genres', '[]'::jsonb)) AS g
	WHERE l.account_id = $1 AND mi.kind = 'movie'
	UNION ALL
	SELECT 'tag', t
	FROM series r JOIN libraries l ON l.id = r.library_id, unnest(r.tags) AS t
	WHERE l.account_id = $1
	UNION ALL
	SELECT 'genre', g
	FROM series r JOIN libraries l ON l.id = r.library_id,
	     jsonb_array_elements_text(COALESCE(r.metadata->'genres', r.provider_metadata->'genres', '[]'::jsonb)) AS g
	WHERE l.account_id = $1
)
SELECT type, value, count(*) AS n
FROM facets
GROUP BY type, value
ORDER BY n DESC, value ASC
LIMIT $2`
	rows, err := s.pool.Query(ctx, q, accountID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.Facet{}
	for rows.Next() {
		var f api.Facet
		var typ string
		if err := rows.Scan(&typ, &f.Value, &f.Count); err != nil {
			return nil, err
		}
		f.Type = api.FacetType(typ)
		out = append(out, f)
	}
	return out, rows.Err()
}
