package library

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/Einlanzerous/argosy/internal/auth"
	"github.com/jackc/pgx/v5"
)

// videoTypes maps container extensions to MIME types, since the system mime
// table often lacks the less-common ones (mkv, m2ts, …).
var videoTypes = map[string]string{
	".mkv":  "video/x-matroska",
	".mp4":  "video/mp4",
	".m4v":  "video/x-m4v",
	".webm": "video/webm",
	".mov":  "video/quicktime",
	".avi":  "video/x-msvideo",
	".ts":   "video/mp2t",
	".m2ts": "video/mp2t",
	".wmv":  "video/x-ms-wmv",
	".mpg":  "video/mpeg",
	".mpeg": "video/mpeg",
}

// itemPath resolves the library root + relative file path for an item the
// account owns. ok is false when the item isn't found in the account.
func (s *Store) itemPath(ctx context.Context, accountID, itemID string) (root, rel string, ok bool, err error) {
	err = s.pool.QueryRow(ctx,
		`SELECT l.root_path, mi.file_path
		 FROM media_items mi JOIN libraries l ON l.id = mi.library_id
		 WHERE l.account_id = $1 AND mi.id = $2`,
		accountID, itemID).Scan(&root, &rel)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", false, nil
	}
	if err != nil {
		return "", "", false, err
	}
	return root, rel, true, nil
}

// streamHandler serves a media file with byte-range support for direct play.
// An HTML5 <video> element can't send an Authorization header, so the per-device
// token may arrive either as a bearer header or a ?token= query param.
func streamHandler(store *Store, authStore *auth.Store, logger *slog.Logger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := streamToken(r)
		if token == "" {
			writeJSON(w, http.StatusUnauthorized, errorBody("missing token"))
			return
		}
		sess, err := authStore.AuthenticateDevice(r.Context(), token)
		if err != nil {
			writeJSON(w, http.StatusUnauthorized, errorBody("invalid or revoked token"))
			return
		}
		root, rel, ok, err := store.itemPath(r.Context(), sess.AccountId.String(), r.PathValue("itemId"))
		if err != nil {
			logger.Error("stream: resolve path failed", "err", err)
			writeJSON(w, http.StatusInternalServerError, errorBody("internal error"))
			return
		}
		if !ok {
			writeJSON(w, http.StatusNotFound, errorBody("not found"))
			return
		}

		// Resolve within the library root; reject any path traversal.
		rootAbs, err := filepath.Abs(root)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, errorBody("internal error"))
			return
		}
		fileAbs := filepath.Join(rootAbs, filepath.FromSlash(rel))
		if fileAbs != rootAbs && !strings.HasPrefix(fileAbs, rootAbs+string(os.PathSeparator)) {
			writeJSON(w, http.StatusForbidden, errorBody("forbidden"))
			return
		}

		f, err := os.Open(fileAbs)
		if err != nil {
			writeJSON(w, http.StatusNotFound, errorBody("file unavailable"))
			return
		}
		defer func() { _ = f.Close() }()
		fi, err := f.Stat()
		if err != nil || fi.IsDir() {
			writeJSON(w, http.StatusNotFound, errorBody("file unavailable"))
			return
		}

		ext := strings.ToLower(filepath.Ext(fileAbs))
		if ct := videoTypes[ext]; ct != "" {
			w.Header().Set("Content-Type", ct)
		} else if ct := mime.TypeByExtension(ext); ct != "" {
			w.Header().Set("Content-Type", ct)
		}
		w.Header().Set("Accept-Ranges", "bytes")
		w.Header().Set("ETag", fmt.Sprintf("%q", fmt.Sprintf("%x-%x", fi.ModTime().UnixNano(), fi.Size())))
		// ServeContent streams without buffering and handles Range → 206 +
		// Content-Range, If-Range, and Last-Modified.
		http.ServeContent(w, r, fi.Name(), fi.ModTime(), f)
	}
}

func streamToken(r *http.Request) string {
	if after, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer "); ok && after != "" {
		return after
	}
	return r.URL.Query().Get("token")
}
