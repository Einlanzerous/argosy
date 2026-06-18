import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Single-service build: the Vue SPA is emitted into the Go server's embed
// directory (internal/webui/dist) so `go build` bakes it into one binary.
// In dev, API/stream routes are proxied to the Go server — default :8096 on the
// host, overridable via VITE_DEV_PROXY (the docker stack points it at the
// `server` container).
const proxyTarget = process.env.VITE_DEV_PROXY ?? 'http://localhost:8096'

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
      '/healthz': proxyTarget,
      '/stream': proxyTarget,
      '/hls': proxyTarget,
    },
  },
})
