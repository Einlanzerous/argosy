import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Single-service build: the Vue SPA is emitted into the Go server's embed
// directory (internal/webui/dist) so `go build` bakes it into one binary.
// In dev, API/stream routes are proxied to the Go server (default :8096).
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
    proxy: {
      '/api': 'http://localhost:8096',
      '/healthz': 'http://localhost:8096',
      '/stream': 'http://localhost:8096',
      '/hls': 'http://localhost:8096',
    },
  },
})
