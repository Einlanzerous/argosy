package server

import (
	"net/http"
	"path"
	"strings"

	"github.com/Einlanzerous/argosy/internal/webui"
)

// newSPAHandler serves the embedded Vue app with single-page-app fallback: real
// asset paths are served directly, unknown paths fall back to index.html
// (client-side routing), and before the first `vite build` a placeholder page
// is shown instead.
func newSPAHandler() (http.Handler, error) {
	sub, err := webui.FS()
	if err != nil {
		return nil, err
	}
	fileServer := http.FileServer(http.FS(sub))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if name == "" {
			name = "index.html"
		}

		if f, err := sub.Open(name); err == nil {
			info, statErr := f.Stat()
			_ = f.Close()
			if statErr == nil && !info.IsDir() {
				fileServer.ServeHTTP(w, r)
				return
			}
		}

		if idx, err := sub.Open("index.html"); err == nil {
			_ = idx.Close()
			req := r.Clone(r.Context())
			req.URL.Path = "/"
			fileServer.ServeHTTP(w, req)
			return
		}

		// SPA not built yet.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(notBuiltHTML))
	}), nil
}

const notBuiltHTML = `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Argosy</title>
<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:4rem auto;padding:0 1rem;color:#1f2937;line-height:1.6}code{background:#f3f4f6;padding:.15rem .35rem;border-radius:.25rem}</style>
</head>
<body>
<h1>&#9875; Argosy</h1>
<p>The server is running, but the web UI has not been built yet.</p>
<p>Build it with <code>make web-build</code> (or <code>npm --prefix web run build</code>), then reload.</p>
<p>API health: <code>GET /healthz</code> &middot; <code>GET /api/v1/ping</code></p>
</body>
</html>
`
