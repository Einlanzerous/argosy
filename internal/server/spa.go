package server

import (
	"net/http"
	"path"
	"strings"

	"github.com/Einlanzerous/argosy/internal/httpx"
	"github.com/Einlanzerous/argosy/internal/webui"
)

// apiNotFound returns a JSON 404 for unmatched /api/ paths so API clients never
// receive the SPA shell (which would break openapi-fetch error handling).
func apiNotFound(w http.ResponseWriter) {
	httpx.Error(w, http.StatusNotFound, "not found")
}

// assetPrefix is Vite's content-hashed build output. Every filename under it
// embeds a hash of its contents, which drives both caching rules below.
const assetPrefix = "/assets/"

// newSPAHandler serves the embedded Vue app with single-page-app fallback: real
// asset paths are served directly, unknown paths fall back to index.html
// (client-side routing), and before the first `vite build` a placeholder page
// is shown instead.
//
// Caching is deliberate (ARGY-168). A deploy swaps every content-hashed asset at
// once, so a tab opened before it holds references to chunks that no longer
// exist. Two rules keep that recoverable:
//
//   - the SPA shell is `no-store`. It is the only document that names the current
//     chunk hashes, so it must never be served from cache — otherwise the
//     recovery reload in router/index.ts re-reads a stale shell, asks for the
//     same dead chunks, and the route stays broken until a manual hard refresh.
//   - assets are `immutable` for a year. The hash *is* the version, so a given
//     URL's bytes never change and the browser need not revalidate.
func newSPAHandler() (http.Handler, error) {
	sub, err := webui.FS()
	if err != nil {
		return nil, err
	}
	fileServer := http.FileServer(http.FS(sub))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Unmatched API routes fall through to this catch-all; never serve them
		// the SPA shell — return a JSON 404 so API clients see a real error.
		if strings.HasPrefix(r.URL.Path, "/api/") {
			apiNotFound(w)
			return
		}

		name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if name == "" {
			name = "index.html"
		}

		if f, err := sub.Open(name); err == nil {
			info, statErr := f.Stat()
			_ = f.Close()
			if statErr == nil && !info.IsDir() {
				if strings.HasPrefix(r.URL.Path, assetPrefix) {
					w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
				} else {
					setNoStore(w)
				}
				fileServer.ServeHTTP(w, r)
				return
			}
		}

		// A miss under /assets/ is a genuinely absent build artifact — almost
		// always a stale chunk requested by a tab that predates a deploy. Answer
		// 404 rather than falling through to the shell: returning 200 text/html
		// for a .js URL makes the browser reject it as a MIME violation
		// ("Loading module ... was blocked because of a disallowed MIME type"),
		// which is a confusing way to say "not found" and risks caching an HTML
		// body under a script URL.
		if strings.HasPrefix(r.URL.Path, assetPrefix) {
			setNoStore(w)
			http.NotFound(w, r)
			return
		}

		if idx, err := sub.Open("index.html"); err == nil {
			_ = idx.Close()
			req := r.Clone(r.Context())
			req.URL.Path = "/"
			setNoStore(w)
			fileServer.ServeHTTP(w, req)
			return
		}

		// SPA not built yet.
		setNoStore(w)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(notBuiltHTML))
	}), nil
}

// setNoStore marks a response as never cacheable. http.FileServer would
// otherwise add only Last-Modified, leaving freshness to browser heuristics.
func setNoStore(w http.ResponseWriter) {
	w.Header().Set("Cache-Control", "no-store, must-revalidate")
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
