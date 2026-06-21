/// <reference types="vite/client" />

// Fallback type shim for single-file components. vue-tsc resolves .vue natively,
// but a clean `tsc`/`bun run build` in the Docker image needs this declared or it
// fails with "Cannot find module '*.vue'".
declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<Record<string, never>, Record<string, never>, unknown>
  export default component
}
