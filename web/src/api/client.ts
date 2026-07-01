import createClient, { type Middleware } from 'openapi-fetch'
import type { paths } from './schema'

// Typed API client generated from proto/openapi/argosy.yaml. The SPA is served
// by the Go server, so requests are same-origin. A per-device bearer token
// (issued by /auth/devices) is attached to every request and persisted so the
// session survives reloads.

const TOKEN_KEY = 'argosy.deviceToken'
const INSTALL_KEY = 'argosy.installId'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null): void {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
}

// A stable per-browser install id, minted once and persisted across sign-outs so
// re-pairing this browser updates its existing Fleet row instead of spawning a
// duplicate (ARGY-99). Deliberately NOT cleared on logout.
//
// The value is opaque server-side (an upsert key, never parsed as a UUID), so we
// mint plain random hex from getRandomValues — available in every context,
// unlike crypto.randomUUID which is gated to secure origins (HTTPS/localhost) and
// throws when the SPA is reached over plain HTTP by hostname (ARGY-121).
export function getInstallId(): string {
  let id = localStorage.getItem(INSTALL_KEY)
  if (!id) {
    const bytes = crypto.getRandomValues(new Uint8Array(16))
    id = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
    localStorage.setItem(INSTALL_KEY, id)
  }
  return id
}

let onUnauthorized: (() => void) | null = null

// Lets the app react when an authenticated request is rejected (token revoked
// or expired) — typically by logging out and returning to the sign-in screen.
export function setUnauthorizedHandler(fn: () => void): void {
  onUnauthorized = fn
}

const authMiddleware: Middleware = {
  onRequest({ request }) {
    const token = getToken()
    if (token) request.headers.set('Authorization', `Bearer ${token}`)
    return request
  },
  onResponse({ response }) {
    // Only treat a 401 as a session drop when we actually sent a token; a 401
    // on the unauthenticated login/pair calls is just a bad-credentials answer.
    if (response.status === 401 && getToken()) onUnauthorized?.()
    return response
  },
}

export const api = createClient<paths>({ baseUrl: '/' })
api.use(authMiddleware)
