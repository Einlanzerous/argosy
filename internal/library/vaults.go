package library

import (
	"context"
	"errors"
	"net/http"

	"github.com/Einlanzerous/argosy/internal/api"
	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/jackc/pgx/v5"
)

// Vaults (ARGY-42): user-curated collections of films + series. Visibility — a
// profile sees its own vaults plus any shared with the household. Editing items
// — owner always, plus any household member when the vault is shared. Managing
// (rename / re-share / delete) — owner or an admin.

// ---- store ----

// ListVaults returns the vaults visible to the profile: its own plus shared ones.
func (s *Store) ListVaults(ctx context.Context, accountID, userID string) ([]api.Vault, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT v.id::text, v.name, v.description, v.shared, v.owner_user_id::text, u.name,
		        (SELECT count(*) FROM vault_items vi WHERE vi.vault_id = v.id)
		 FROM vaults v JOIN users u ON u.id = v.owner_user_id
		 WHERE v.account_id = $1 AND (v.owner_user_id = $2 OR v.shared = true)
		 ORDER BY v.name`,
		accountID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []api.Vault{}
	for rows.Next() {
		v, err := scanVaultSummary(rows, userID)
		if err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanVaultSummary(row rowScanner, userID string) (api.Vault, error) {
	var id, name, ownerID, ownerName string
	var desc *string
	var shared bool
	var count int
	if err := row.Scan(&id, &name, &desc, &shared, &ownerID, &ownerName, &count); err != nil {
		return api.Vault{}, err
	}
	return api.Vault{
		Id: parseUUID(id), Name: name, Description: desc, Shared: shared,
		OwnerId: parseUUID(ownerID), OwnerName: ownerName, ItemCount: count,
		IsOwner: ownerID == userID,
	}, nil
}

// vaultSummary re-reads one vault as an api.Vault (after a create/update).
func (s *Store) vaultSummary(ctx context.Context, vaultID, userID string) (*api.Vault, error) {
	row := s.pool.QueryRow(ctx,
		`SELECT v.id::text, v.name, v.description, v.shared, v.owner_user_id::text, u.name,
		        (SELECT count(*) FROM vault_items vi WHERE vi.vault_id = v.id)
		 FROM vaults v JOIN users u ON u.id = v.owner_user_id WHERE v.id = $1`,
		vaultID)
	v, err := scanVaultSummary(row, userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// CreateVault inserts a vault owned by the profile.
func (s *Store) CreateVault(ctx context.Context, accountID, userID, name string, desc *string, shared bool) (*api.Vault, error) {
	var id string
	if err := s.pool.QueryRow(ctx,
		`INSERT INTO vaults (account_id, owner_user_id, name, description, shared)
		 VALUES ($1,$2,$3,$4,$5) RETURNING id::text`,
		accountID, userID, name, desc, shared).Scan(&id); err != nil {
		return nil, err
	}
	return s.vaultSummary(ctx, id, userID)
}

// vaultMetaRow carries just the fields needed to authorize an operation.
type vaultMetaRow struct {
	accountID, ownerID string
	shared             bool
}

func (s *Store) vaultMeta(ctx context.Context, vaultID string) (*vaultMetaRow, error) {
	var m vaultMetaRow
	err := s.pool.QueryRow(ctx,
		`SELECT account_id::text, owner_user_id::text, shared FROM vaults WHERE id = $1`,
		vaultID).Scan(&m.accountID, &m.ownerID, &m.shared)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &m, nil
}

// GetVault returns a visible vault with its resolved items, or nil when missing
// or not visible to the profile. canEdit is set by the caller (it depends on the
// session role) — the store leaves it false.
func (s *Store) GetVault(ctx context.Context, accountID, userID, vaultID string) (*api.VaultDetail, error) {
	var id, name, ownerID, ownerName string
	var desc *string
	var shared bool
	err := s.pool.QueryRow(ctx,
		`SELECT v.id::text, v.name, v.description, v.shared, v.owner_user_id::text, u.name
		 FROM vaults v JOIN users u ON u.id = v.owner_user_id
		 WHERE v.id = $1 AND v.account_id = $2 AND (v.owner_user_id = $3 OR v.shared = true)`,
		vaultID, accountID, userID).Scan(&id, &name, &desc, &shared, &ownerID, &ownerName)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	detail := api.VaultDetail{
		Id: parseUUID(id), Name: name, Description: desc, Shared: shared,
		OwnerId: parseUUID(ownerID), OwnerName: ownerName, IsOwner: ownerID == userID,
		Items: []api.VaultEntry{},
	}
	rows, err := s.pool.Query(ctx,
		`SELECT vi.id::text,
		        vi.media_item_id::text, mi.kind, mi.title, mi.year, mi.provider_metadata, mi.metadata,
		        vi.series_id::text, sr.title, sr.year, sr.provider_metadata, sr.metadata
		 FROM vault_items vi
		 LEFT JOIN media_items mi ON mi.id = vi.media_item_id
		 LEFT JOIN series sr ON sr.id = vi.series_id
		 WHERE vi.vault_id = $1
		 ORDER BY vi.position, vi.added_at`, vaultID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		entry, err := s.scanVaultEntry(rows)
		if err != nil {
			return nil, err
		}
		detail.Items = append(detail.Items, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	detail.ItemCount = len(detail.Items)
	return &detail, nil
}

func (s *Store) scanVaultEntry(rows pgx.Rows) (api.VaultEntry, error) {
	var entryID string
	var miID, miKind, miTitle, srID, srTitle *string
	var miYear, srYear *int
	var miProv, miOver, srProv, srOver []byte
	if err := rows.Scan(&entryID, &miID, &miKind, &miTitle, &miYear, &miProv, &miOver,
		&srID, &srTitle, &srYear, &srProv, &srOver); err != nil {
		return api.VaultEntry{}, err
	}
	e := api.VaultEntry{EntryId: parseUUID(entryID)}
	if miID != nil {
		p, o := decodeMap(miProv), decodeMap(miOver)
		e.Kind = api.VaultEntryKind("movie")
		e.Id = parseUUID(*miID)
		e.Title = effectiveTitle(o, p, deref(miTitle))
		e.Year = effectiveYear(o, p, miYear)
		e.PosterUrl = posterURL(s.artworkBase, o, p)
		e.BackdropUrl = backdropURL(s.artworkBase, o, p)
		e.Rating = f32(effectiveRating(o, p))
	} else {
		p, o := decodeMap(srProv), decodeMap(srOver)
		e.Kind = api.VaultEntryKind("series")
		e.Id = parseUUID(deref(srID))
		e.Title = effectiveTitle(o, p, deref(srTitle))
		e.Year = effectiveYear(o, p, srYear)
		e.PosterUrl = posterURL(s.artworkBase, o, p)
		e.BackdropUrl = backdropURL(s.artworkBase, o, p)
		e.Rating = f32(effectiveRating(o, p))
	}
	return e, nil
}

// UpdateVault applies the supplied fields (each optional) and returns the vault.
func (s *Store) UpdateVault(ctx context.Context, vaultID, userID string, req api.UpdateVaultRequest) (*api.Vault, error) {
	if _, err := s.pool.Exec(ctx,
		`UPDATE vaults SET
		    name        = COALESCE($2, name),
		    description = CASE WHEN $3 THEN $4 ELSE description END,
		    shared      = COALESCE($5, shared),
		    updated_at  = now()
		 WHERE id = $1`,
		vaultID, req.Name, req.Description != nil, req.Description, req.Shared); err != nil {
		return nil, err
	}
	return s.vaultSummary(ctx, vaultID, userID)
}

// DeleteVault removes a vault (its items cascade).
func (s *Store) DeleteVault(ctx context.Context, vaultID string) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM vaults WHERE id = $1`, vaultID)
	return err
}

// AddVaultItem adds a film or series (exactly one) to the vault, after checking
// it belongs to the account. Re-adding an existing item is a no-op that returns
// the existing entry. Returns nil when the referenced item isn't in the account.
func (s *Store) AddVaultItem(ctx context.Context, accountID, vaultID string, movieID, seriesID *string) (*api.VaultEntry, error) {
	var ok bool
	if movieID != nil {
		if err := s.pool.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
			                WHERE mi.id = $1 AND l.account_id = $2 AND mi.kind = 'movie')`,
			*movieID, accountID).Scan(&ok); err != nil {
			return nil, err
		}
	} else {
		if err := s.pool.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM series r JOIN libraries l ON l.id = r.library_id
			                WHERE r.id = $1 AND l.account_id = $2)`,
			*seriesID, accountID).Scan(&ok); err != nil {
			return nil, err
		}
	}
	if !ok {
		return nil, nil
	}
	var entryID string
	err := s.pool.QueryRow(ctx,
		`INSERT INTO vault_items (vault_id, media_item_id, series_id, position)
		 VALUES ($1, $2, $3, COALESCE((SELECT max(position) + 1 FROM vault_items WHERE vault_id = $1), 0))
		 ON CONFLICT DO NOTHING
		 RETURNING id::text`,
		vaultID, movieID, seriesID).Scan(&entryID)
	if errors.Is(err, pgx.ErrNoRows) {
		// Already present — find the existing entry id.
		col, val := "media_item_id", movieID
		if seriesID != nil {
			col, val = "series_id", seriesID
		}
		if err := s.pool.QueryRow(ctx,
			`SELECT id::text FROM vault_items WHERE vault_id = $1 AND `+col+` = $2`,
			vaultID, val).Scan(&entryID); err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx,
		`SELECT vi.id::text,
		        vi.media_item_id::text, mi.kind, mi.title, mi.year, mi.provider_metadata, mi.metadata,
		        vi.series_id::text, sr.title, sr.year, sr.provider_metadata, sr.metadata
		 FROM vault_items vi
		 LEFT JOIN media_items mi ON mi.id = vi.media_item_id
		 LEFT JOIN series sr ON sr.id = vi.series_id
		 WHERE vi.id = $1`, entryID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	if !rows.Next() {
		return nil, rows.Err()
	}
	e, err := s.scanVaultEntry(rows)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// RemoveVaultItem deletes an entry from a vault. Reports whether a row was removed.
func (s *Store) RemoveVaultItem(ctx context.Context, vaultID, entryID string) (bool, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM vault_items WHERE id = $1 AND vault_id = $2`, entryID, vaultID)
	return tag.RowsAffected() > 0, err
}

// ReorderVault rewrites item positions to match the given entry-id order. Entry
// ids not in the vault are ignored; omitted entries keep their relative order
// after the listed ones (they aren't touched, so they sort by their old position).
func (s *Store) ReorderVault(ctx context.Context, vaultID string, entryIDs []string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	for i, id := range entryIDs {
		if _, err := tx.Exec(ctx,
			`UPDATE vault_items SET position = $1 WHERE id = $2 AND vault_id = $3`,
			i, id, vaultID); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// ---- handlers ----

// vaultPerm loads a vault and resolves the session's rights over it. found is
// false when the vault is missing or outside the session's account.
func (h *handlers) vaultPerm(r *http.Request, vaultID string) (canEdit, canManage, found bool) {
	m, err := h.store.vaultMeta(r.Context(), vaultID)
	if err != nil || m == nil {
		return false, false, false
	}
	sess, _ := auth.SessionFromContext(r.Context())
	if m.accountID != sess.AccountId.String() {
		return false, false, false
	}
	isOwner := m.ownerID == sess.UserId.String()
	canEdit = isOwner || m.shared
	canManage = isOwner || sess.Role == api.Admin
	return canEdit, canManage, true
}

func (h *handlers) listVaults(w http.ResponseWriter, r *http.Request) {
	vaults, err := h.store.ListVaults(r.Context(), accountOf(r), userOf(r))
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, vaults)
}

func (h *handlers) createVault(w http.ResponseWriter, r *http.Request) {
	var req api.CreateVaultRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Name == "" {
		httpx.Error(w, http.StatusBadRequest, "name required")
		return
	}
	shared := req.Shared != nil && *req.Shared
	v, err := h.store.CreateVault(r.Context(), accountOf(r), userOf(r), req.Name, req.Description, shared)
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, v)
}

func (h *handlers) getVault(w http.ResponseWriter, r *http.Request) {
	d, err := h.store.GetVault(r.Context(), accountOf(r), userOf(r), r.PathValue("vaultId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if d == nil {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	d.CanEdit = d.IsOwner || d.Shared
	httpx.JSON(w, http.StatusOK, d)
}

func (h *handlers) updateVault(w http.ResponseWriter, r *http.Request) {
	vaultID := r.PathValue("vaultId")
	_, canManage, found := h.vaultPerm(r, vaultID)
	if !found {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	if !canManage {
		httpx.Error(w, http.StatusForbidden, "only the owner or an admin can manage this vault")
		return
	}
	var req api.UpdateVaultRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	v, err := h.store.UpdateVault(r.Context(), vaultID, userOf(r), req)
	if err != nil {
		h.fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, v)
}

func (h *handlers) deleteVault(w http.ResponseWriter, r *http.Request) {
	vaultID := r.PathValue("vaultId")
	_, canManage, found := h.vaultPerm(r, vaultID)
	if !found {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	if !canManage {
		httpx.Error(w, http.StatusForbidden, "only the owner or an admin can delete this vault")
		return
	}
	if err := h.store.DeleteVault(r.Context(), vaultID); err != nil {
		h.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handlers) addVaultItem(w http.ResponseWriter, r *http.Request) {
	vaultID := r.PathValue("vaultId")
	canEdit, _, found := h.vaultPerm(r, vaultID)
	if !found {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	if !canEdit {
		httpx.Error(w, http.StatusForbidden, "you can't curate this vault")
		return
	}
	var req api.AddVaultItemRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	var movieID, seriesID *string
	if req.MovieId != nil {
		s := req.MovieId.String()
		movieID = &s
	}
	if req.SeriesId != nil {
		s := req.SeriesId.String()
		seriesID = &s
	}
	if (movieID == nil) == (seriesID == nil) {
		httpx.Error(w, http.StatusBadRequest, "exactly one of movieId or seriesId is required")
		return
	}
	entry, err := h.store.AddVaultItem(r.Context(), accountOf(r), vaultID, movieID, seriesID)
	if err != nil {
		h.fail(w, err)
		return
	}
	if entry == nil {
		httpx.Error(w, http.StatusNotFound, "item not found in this account")
		return
	}
	httpx.JSON(w, http.StatusCreated, entry)
}

func (h *handlers) removeVaultItem(w http.ResponseWriter, r *http.Request) {
	vaultID := r.PathValue("vaultId")
	canEdit, _, found := h.vaultPerm(r, vaultID)
	if !found {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	if !canEdit {
		httpx.Error(w, http.StatusForbidden, "you can't curate this vault")
		return
	}
	removed, err := h.store.RemoveVaultItem(r.Context(), vaultID, r.PathValue("entryId"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if !removed {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handlers) reorderVault(w http.ResponseWriter, r *http.Request) {
	vaultID := r.PathValue("vaultId")
	canEdit, _, found := h.vaultPerm(r, vaultID)
	if !found {
		httpx.Error(w, http.StatusNotFound, "not found")
		return
	}
	if !canEdit {
		httpx.Error(w, http.StatusForbidden, "you can't curate this vault")
		return
	}
	var req api.ReorderVaultRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	ids := make([]string, 0, len(req.EntryIds))
	for _, id := range req.EntryIds {
		ids = append(ids, id.String())
	}
	if err := h.store.ReorderVault(r.Context(), vaultID, ids); err != nil {
		h.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
