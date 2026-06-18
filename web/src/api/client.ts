import createClient from 'openapi-fetch'
import type { paths } from './schema'

// Typed API client generated from proto/openapi/argosy.yaml. The SPA is served
// by the Go server, so requests are same-origin.
export const api = createClient<paths>({ baseUrl: '/' })
