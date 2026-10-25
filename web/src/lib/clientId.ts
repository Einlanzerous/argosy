// The build identity this SPA sends on every request (ARGY-262), so the server
// log and the Fleet can say which version a browser is running. The version is
// injected at build time (see vite.config.ts); the browser UA is logged beside it.
export const CLIENT_ID = `argosy-web/${__ARGOSY_VERSION__}`

export const CLIENT_HEADER = 'X-Argosy-Client'

// Parse "argosy-android/0.32.0+78 (Pixel 9; Android 36)" into its app and
// version. Returns null for anything that doesn't look like a client string.
export function parseClient(s: string | null | undefined): { app: string; version: string } | null {
  const m = /^argosy-([a-z]+)\/(\d+\.\d+\.\d+)/.exec(s ?? '')
  return m ? { app: m[1]!, version: m[2]! } : null
}

function semver(v: string): [number, number, number] | null {
  const m = /^v?(\d+)\.(\d+)\.(\d+)/.exec(v)
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// True when `version` is strictly older than the server's. Unparseable versions
// (a dev build, an empty healthz) are never flagged.
export function isBehind(version: string, server: string): boolean {
  const a = semver(version)
  const b = semver(server)
  if (!a || !b) return false
  for (let i = 0; i < 3; i++) {
    if (a[i]! !== b[i]!) return a[i]! < b[i]!
  }
  return false
}
