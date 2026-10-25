import { existsSync, readFileSync } from 'node:fs'
import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Single-service build: the Vue SPA is emitted into the Go server's embed
// directory (internal/webui/dist) so `go build` bakes it into one binary.
// In dev, API/stream routes are proxied to the Go server — default :8097 on the
// host (8096 is the production container's port; the dev stack publishes 8097 to
// avoid clashing), overridable via VITE_DEV_PROXY (the docker stack points it at
// the `server` container).
const proxyTarget = process.env.VITE_DEV_PROXY ?? 'http://localhost:8097'

// The version this build reports as X-Argosy-Client (ARGY-262). `make web-build`
// and the Docker web stage pass VITE_APP_VERSION (the same value the Go binary is
// stamped with); a bare `bun run build` falls back to the release-please manifest
// — the repo's version of record, since web/package.json stays 0.0.0 — and then `dev`.
function appVersion(): string {
  const fromEnv = process.env.VITE_APP_VERSION?.replace(/^v/, '')
  if (fromEnv) return fromEnv
  const manifest = fileURLToPath(new URL('../.release-please-manifest.json', import.meta.url))
  if (existsSync(manifest)) {
    try {
      const v = (JSON.parse(readFileSync(manifest, 'utf8')) as Record<string, string>)['.']
      if (v) return v
    } catch {
      // fall through
    }
  }
  return 'dev'
}

export default defineConfig({
  plugins: [vue()],
  define: {
    __ARGOSY_VERSION__: JSON.stringify(appVersion()),
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    outDir: fileURLToPath(new URL('../internal/webui/dist', import.meta.url)),
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    host: true,
    // Reachable by hostname (not just localhost/IP) — Vite otherwise rejects
    // requests whose Host header isn't in this allowlist.
    allowedHosts: ['imperial-construct'],
    proxy: {
      '/api': proxyTarget,
      '/artwork': proxyTarget, // cached posters/backdrops served by the Go static handler
      '/healthz': proxyTarget,
      '/stream': proxyTarget,
      '/hls': proxyTarget,
    },
  },
})
