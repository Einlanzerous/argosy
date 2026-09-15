package library

import (
	"context"
	"log/slog"
	"time"

	"github.com/Einlanzerous/argosy/internal/fileid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// LiveItems adapts the media_items table to ballast.Live for the subtitle VTT
// cache (ARGY-155). Cache directories are named after an item *and* its current
// file — fileid.ItemKey — so a key still present in the catalog is live and its
// extracted VTTs are kept, while a key retired by a delete, a rescan, or a file
// replacement that kept the item's id (ARGY-238) turns its directory into an
// orphan the sweeper reclaims.
//
// The key is formatted by the same fileid helper the subtitle service writes
// with, never in SQL. If the two ever disagreed, every live directory would read
// as an orphan and the hourly sweep would empty the cache each run.
//
// LiveIDs returns nil when the query fails — the sweeper treats that as
// "unknown" and skips the pass, so a transient DB error can never mass-purge
// the cache.
type LiveItems struct {
	Pool   *pgxpool.Pool
	Logger *slog.Logger
}

// LiveIDs returns the cache key of every media item currently in the catalog,
// or nil when the query fails (see the type comment for why nil, not empty).
func (l LiveItems) LiveIDs() map[string]bool {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	rows, err := l.Pool.Query(ctx, `SELECT id, content_hash, file_size FROM media_items`)
	if err != nil {
		l.Logger.Warn("subtitle sweep: listing media item ids failed", "err", err)
		return nil
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var id string
		var hash *string
		var size *int64
		if err := rows.Scan(&id, &hash, &size); err != nil {
			l.Logger.Warn("subtitle sweep: scanning media item id failed", "err", err)
			return nil
		}
		out[fileid.ItemKey(id, fileid.Identity(hash, size))] = true
	}
	if err := rows.Err(); err != nil {
		l.Logger.Warn("subtitle sweep: listing media item ids failed", "err", err)
		return nil
	}
	return out
}
