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

export default defineConfig({
  plugins: [vue()],
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
    proxy: {
      '/api': proxyTarget,
      '/artwork': proxyTarget, // cached posters/backdrops served by the Go static handler
      '/healthz': proxyTarget,
      '/stream': proxyTarget,
      '/hls': proxyTarget,
    },
  },
})
