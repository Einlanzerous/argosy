import { describe, expect, mock, test } from 'bun:test'

// startTranscode's request body is the browser's half of the ARGY-179 contract:
// the generated TS type now carries minHeight/maxHeight, and the web client must
// not send them — the browser has no display-mode height to assert and keeps the
// full ladder, with hls.js's ABR picking the rung. This pins the body to exactly
// startAt, hevc, hevcHardware and (only when given) burnInSubtitle.

type Captured = { url: string; init: { params?: unknown; body?: Record<string, unknown> } }
const captured: Captured[] = []

// The module under test imports `api`, `ApiError` and `getToken` from the
// client; the mock has to export all three or the import fails to resolve.
mock.module('@/api/client', () => ({
  api: {
    POST: async (url: string, init: Captured['init']) => {
      captured.push({ url, init })
      return { data: { id: 'sess-1', playlistUrl: '/api/v1/transcode/sess-1/index.m3u8' } }
    },
    GET: async () => ({ data: null }),
    PUT: async () => ({ data: null }),
    DELETE: async () => ({ data: null }),
  },
  ApiError: class ApiError extends Error {
    constructor(readonly status: number) {
      super(`HTTP ${status}`)
    }
  },
  getToken: () => 'token',
}))

// bun's test runtime has no MediaSource or MediaCapabilities; stub the two
// probes startTranscode consults so the body carries deterministic answers.
;(globalThis as unknown as { MediaSource: unknown }).MediaSource = {
  isTypeSupported: () => true,
}
Object.defineProperty(navigator, 'mediaCapabilities', {
  configurable: true,
  value: {
    decodingInfo: async () => ({ supported: true, smooth: true, powerEfficient: false }),
  },
})

describe('startTranscode request body (ARGY-179)', () => {
  test('sends startAt, hevc and hevcHardware only — no ladder hints', async () => {
    const { startTranscode } = await import('../src/lib/playback')
    captured.length = 0

    const sess = await startTranscode('item-1', 12.5)
    expect(sess?.id).toBe('sess-1')
    expect(captured).toHaveLength(1)
    expect(captured[0].url).toBe('/api/v1/items/{itemId}/transcode')
    expect(captured[0].init.params).toEqual({ path: { itemId: 'item-1' } })

    const body = captured[0].init.body!
    expect(Object.keys(body).sort()).toEqual(['hevc', 'hevcHardware', 'startAt'])
    expect(body.startAt).toBe(12.5)
    expect(body.hevc).toBe(true)
    // smooth but not powerEfficient → false, the asymmetric reading.
    expect(body.hevcHardware).toBe(false)
    expect('minHeight' in body).toBe(false)
    expect('maxHeight' in body).toBe(false)
  })

  test('adds burnInSubtitle when given and still no ladder hints', async () => {
    const { startTranscode } = await import('../src/lib/playback')
    captured.length = 0

    await startTranscode('item-2', 0, 'burn:6')
    const body = captured[0].init.body!
    expect(Object.keys(body).sort()).toEqual(['burnInSubtitle', 'hevc', 'hevcHardware', 'startAt'])
    expect(body.burnInSubtitle).toBe('burn:6')
    expect(body.startAt).toBe(0)
    expect('minHeight' in body).toBe(false)
    expect('maxHeight' in body).toBe(false)
  })

  test('an empty burnInSubtitle is omitted, not sent as ""', async () => {
    const { startTranscode } = await import('../src/lib/playback')
    captured.length = 0

    await startTranscode('item-3', 3, null)
    expect(Object.keys(captured[0].init.body!).sort()).toEqual(['hevc', 'hevcHardware', 'startAt'])
  })
})
