import { describe, expect, mock, test } from 'bun:test'

// reportProgress is the browser's half of the ARGY-289 contract: an ordinary
// report is a plain position write, and only a paused player's liveness ping
// carries keepalive:true (which the server answers without storing a position).

type Captured = { url: string; body: Record<string, unknown> }
const captured: Captured[] = []

mock.module('@/api/client', () => ({
  api: {
    PUT: async (url: string, init: { body: Record<string, unknown> }) => {
      captured.push({ url, body: init.body })
      return { data: null }
    },
    GET: async () => ({ data: null }),
    POST: async () => ({ data: null }),
    DELETE: async () => ({ data: null }),
  },
  ApiError: class ApiError extends Error {},
  getToken: () => 'token',
}))

const { reportProgress } = await import('@/lib/playback')

describe('reportProgress', () => {
  test('an ordinary report carries no keepalive flag', async () => {
    captured.length = 0
    await reportProgress('item-1', 42, 100)
    expect(captured[0].url).toBe('/api/v1/items/{itemId}/progress')
    expect(captured[0].body).toEqual({ positionSeconds: 42, durationSeconds: 100 })
    expect('keepalive' in captured[0].body).toBe(false)
  })

  test('a paused keepalive is flagged so the server will not store its position', async () => {
    captured.length = 0
    await reportProgress('item-1', 42, 100, true)
    expect(captured[0].body.keepalive).toBe(true)
  })
})
