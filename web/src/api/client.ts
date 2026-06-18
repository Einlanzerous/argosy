import createClient, { type Middleware } from 'openapi-fetch'
import type { paths } from './schema'

// Typed API client generated from proto/openapi/argosy.yaml. The SPA is served
// by the Go server, so requests are same-origin. A per-device bearer token
// (issued by /auth/devices) is attached to every request and persisted so the
// session survives reloads.

const TOKEN_KEY = 'argosy.deviceToken'

export function getToken(): string | null {
  return localStorage.getItem(TOKEN_KEY)
}

export function setToken(token: string | null): void {
  if (token) localStorage.setItem(TOKEN_KEY, token)
  else localStorage.removeItem(TOKEN_KEY)
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
