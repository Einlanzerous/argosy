package library

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// LiveItems adapts the media_items table to ballast.Live for the subtitle VTT
// cache (ARGY-155): cache directories are named after media item ids, so an id
// still present in the catalog is live and its extracted VTTs are kept. An id
// retired by a delete or rescan turns its directory into an orphan the sweeper
// reclaims.
//
// LiveIDs returns nil when the query fails — the sweeper treats that as
// "unknown" and skips the pass, so a transient DB error can never mass-purge
// the cache.
type LiveItems struct {
	Pool   *pgxpool.Pool
	Logger *slog.Logger
}

// LiveIDs returns the set of media item ids currently in the catalog, or nil
// when the query fails (see the type comment for why nil, not empty).
func (l LiveItems) LiveIDs() map[string]bool {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	rows, err := l.Pool.Query(ctx, `SELECT id FROM media_items`)
	if err != nil {
		l.Logger.Warn("subtitle sweep: listing media item ids failed", "err", err)
		return nil
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			l.Logger.Warn("subtitle sweep: scanning media item id failed", "err", err)
			return nil
		}
		out[id] = true
	}
	if err := rows.Err(); err != nil {
		l.Logger.Warn("subtitle sweep: listing media item ids failed", "err", err)
		return nil
	}
	return out
}
