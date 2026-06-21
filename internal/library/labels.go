package library

import (
	"context"
	"net/http"
	"strings"

	"github.com/Einlanzerous/argosy/internal/api"
)

// User-applied labels (ARGY-73): a profile's own custom tags on a film or series,
// stored in user_labels and kept separate from the path-derived media_items.tags.

// ---- store ----

// ItemLabels returns the profile's labels on a film, sorted.
func (s *Store) ItemLabels(ctx context.Context, userID, itemID string) ([]string, error) {
	return s.labels(ctx, `SELECT label FROM user_labels WHERE user_id = $1 AND media_item_id = $2 ORDER BY label`, userID, itemID)
}

// SeriesLabels returns the profile's labels on a series, sorted.
func (s *Store) SeriesLabels(ctx context.Context, userID, seriesID string) ([]string, error) {
	return s.labels(ctx, `SELECT label FROM user_labels WHERE user_id = $1 AND series_id = $2 ORDER BY label`, userID, seriesID)
}

// ListLabels returns the profile's distinct labels across everything, sorted.
func (s *Store) ListLabels(ctx context.Context, userID string) ([]string, error) {
	return s.labels(ctx, `SELECT DISTINCT label FROM user_labels WHERE user_id = $1 ORDER BY label`, userID)
}

func (s *Store) labels(ctx context.Context, q string, args ...any) ([]string, error) {
	rows, err := s.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var l string
		if err := rows.Scan(&l); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// AddItemLabel adds a label to a film the account owns. found is false when the
// film isn't in the account. Re-adding is a no-op. Returns the item's labels.
func (s *Store) AddItemLabel(ctx context.Context, accountID, userID, itemID, label string) (labels []string, found bool, err error) {
	var ok bool
	if err = s.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		                WHERE mi.id = $1 AND l.account_id = $2)`,
		itemID, accountID).Scan(&ok); err != nil {
		return nil, false, err
	}
	if !ok {
		return nil, false, nil
	}
	if _, err = s.pool.Exec(ctx,
		`INSERT INTO user_labels (user_id, media_item_id, label) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
		userID, itemID, label); err != nil {
		return nil, false, err
	}
	labels, err = s.ItemLabels(ctx, userID, itemID)
	return labels, true, err
}

// AddSeriesLabel adds a label to a series the account owns.
func (s *Store) AddSeriesLabel(ctx context.Context, accountID, userID, seriesID, label string) (labels []string, found bool, err error) {
	var ok bool
	if err = s.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM series r JOIN libraries l ON l.id = r.library_id
		                WHERE r.id = $1 AND l.account_id = $2)`,
		seriesID, accountID).Scan(&ok); err != nil {
		return nil, false, err
	}
	if !ok {
		return nil, false, nil
	}
	if _, err = s.pool.Exec(ctx,
		`INSERT INTO user_labels (user_id, series_id, label) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
		userID, seriesID, label); err != nil {
		return nil, false, err
	}
	labels, err = s.SeriesLabels(ctx, userID, seriesID)
	return labels, true, err
}

// RemoveItemLabel deletes one of the profile's labels from a film (user-scoped,
// so it can only ever remove the caller's own).
func (s *Store) RemoveItemLabel(ctx context.Context, userID, itemID, label string) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM user_labels WHERE user_id = $1 AND media_item_id = $2 AND label = $3`, userID, itemID, label)
	return err
}

// RemoveSeriesLabel deletes one of the profile's labels from a series.
func (s *Store) RemoveSeriesLabel(ctx context.Context, userID, seriesID, label string) error {
	_, err := s.pool.Exec(ctx,
		`DELETE FROM user_labels WHERE user_id = $1 AND series_id = $2 AND label = $3`, userID, seriesID, label)
	return err
}

// ---- handlers ----

func (h *handlers) listLabels(w http.ResponseWriter, r *http.Request) {
	labels, err := h.store.ListLabels(r.Context(), userOf(r))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, labels)
}

// labelOf pulls and validates the label from the request body.
func labelOf(w http.ResponseWriter, r *http.Request) (string, bool) {
	var req api.AddLabelRequest
	if !decodeJSON(w, r, &req) {
		return "", false
	}
	label := strings.TrimSpace(req.Label)
	if label == "" {
		writeJSON(w, http.StatusBadRequest, errorBody("label required"))
		return "", false
	}
	return label, true
}

func (h *handlers) addItemLabel(w http.ResponseWriter, r *http.Request) {
	label, ok := labelOf(w, r)
	if !ok {
		return
	}
	labels, found, err := h.store.AddItemLabel(r.Context(), accountOf(r), userOf(r), r.PathValue("itemId"), label)
	if err != nil {
		h.fail(w, err)
		return
	}
	if !found {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	writeJSON(w, http.StatusOK, labels)
}

func (h *handlers) addSeriesLabel(w http.ResponseWriter, r *http.Request) {
	label, ok := labelOf(w, r)
	if !ok {
		return
	}
	labels, found, err := h.store.AddSeriesLabel(r.Context(), accountOf(r), userOf(r), r.PathValue("seriesId"), label)
	if err != nil {
		h.fail(w, err)
		return
	}
	if !found {
		writeJSON(w, http.StatusNotFound, errorBody("not found"))
		return
	}
	writeJSON(w, http.StatusOK, labels)
}

func (h *handlers) removeItemLabel(w http.ResponseWriter, r *http.Request) {
	if err := h.store.RemoveItemLabel(r.Context(), userOf(r), r.PathValue("itemId"), r.PathValue("label")); err != nil {
		h.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handlers) removeSeriesLabel(w http.ResponseWriter, r *http.Request) {
	if err := h.store.RemoveSeriesLabel(r.Context(), userOf(r), r.PathValue("seriesId"), r.PathValue("label")); err != nil {
		h.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
