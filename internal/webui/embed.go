// Package webui embeds the built Vue single-page app so the Go binary can serve
// the web UI from the same process and origin as the API and media endpoints.
//
// The contents of dist/ are produced by `vite build` (see web/). Before the
// first build only a placeholder is present, and the server serves a friendly
// "not built yet" page instead.
package webui

import (
	"embed"
	"io/fs"
)

//go:embed all:dist
var dist embed.FS

// FS returns the built SPA file tree rooted at the dist directory.
func FS() (fs.FS, error) {
	return fs.Sub(dist, "dist")
}
