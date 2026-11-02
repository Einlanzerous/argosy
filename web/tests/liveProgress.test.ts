import { describe, expect, test } from 'bun:test'

import {
  createLiveProgress,
  patchSeriesProgress,
  seriesHasItem,
  DEBOUNCE_MS,
  THROTTLE_MS,
} from '@/lib/liveProgress'
import type { BeaconEvent } from '@/lib/beacon'

// A hand-driven clock: timers fire only when advance() passes them.
function harness(opts: { deviceId?: string; relevant?: (ev: BeaconEvent) => boolean } = {}) {
  let now = 1_000_000
  let seq = 0
  const timers = new Map<number, { at: number; fn: () => void }>()
  const docListeners = new Map<string, () => void>()
  const winListeners = new Map<string, () => void>()
  const doc = {
    visibilityState: 'visible' as DocumentVisibilityState,
    addEventListener: (t: string, fn: () => void) => void docListeners.set(t, fn),
    removeEventListener: (t: string) => void docListeners.delete(t),
  }
  const win = {
    addEventListener: (t: string, fn: () => void) => void winListeners.set(t, fn),
    removeEventListener: (t: string) => void winListeners.delete(t),
  }
  const stream: {
    handlers: { onPosition?: (e: BeaconEvent) => void; onOpen?: () => void }
    closed: number
  } = { handlers: {}, closed: 0 }
  const calls = { refetch: 0, change: [] as BeaconEvent[] }
  const live = createLiveProgress(
    {
      relevant: opts.relevant,
      onChange: (ev) => calls.change.push(ev),
      refetch: () => {
        calls.refetch++
      },
      deviceId: () => opts.deviceId,
    },
    {
      subscribe: (h) => {
        stream.handlers = h
        return () => void stream.closed++
      },
      setTimeout: (fn, ms) => {
        const id = ++seq
        timers.set(id, { at: now + ms, fn })
        return id
      },
      clearTimeout: (h) => void timers.delete(h as number),
      now: () => now,
      doc,
      win,
    },
  )
  return {
    live,
    stream,
    calls,
    doc,
    docListeners,
    winListeners,
    timers,
    advance(ms: number) {
      now += ms
      for (const [id, t] of [...timers]) {
        if (t.at <= now) {
          timers.delete(id)
          t.fn()
        }
      }
    },
  }
}

const ev = (over: Partial<BeaconEvent> = {}): BeaconEvent => ({
  userId: 'u',
  itemId: 'item-1',
  positionSeconds: 30,
  watched: false,
  originDeviceId: 'other',
  updatedAt: '2026-11-01T00:00:00Z',
  ...over,
})

describe('createLiveProgress', () => {
  test('an event from this device is ignored', () => {
    const h = harness({ deviceId: 'me' })
    h.live.start()
    h.stream.handlers.onPosition!(ev({ originDeviceId: 'me' }))
    h.advance(DEBOUNCE_MS)
    expect(h.calls.change).toHaveLength(0)
    expect(h.calls.refetch).toBe(0)
  })

  test('with no known device id nothing is filtered', () => {
    const h = harness({})
    h.live.start()
    h.stream.handlers.onPosition!(ev({ originDeviceId: undefined }))
    expect(h.calls.change).toHaveLength(1)
  })

  test('an irrelevant item is ignored', () => {
    const h = harness({ deviceId: 'me', relevant: (e) => e.itemId === 'item-1' })
    h.live.start()
    h.stream.handlers.onPosition!(ev({ itemId: 'other-item' }))
    h.advance(DEBOUNCE_MS)
    expect(h.calls.change).toHaveLength(0)
    expect(h.calls.refetch).toBe(0)
  })

  test('a burst of 5 events patches each and refetches once, after the debounce', () => {
    const h = harness({ deviceId: 'me' })
    h.live.start()
    for (let i = 0; i < 5; i++) {
      h.stream.handlers.onPosition!(ev({ positionSeconds: i }))
      h.advance(200)
    }
    expect(h.calls.change).toHaveLength(5)
    expect(h.calls.refetch).toBe(0)
    h.advance(DEBOUNCE_MS)
    expect(h.calls.refetch).toBe(1)
    h.advance(10 * DEBOUNCE_MS)
    expect(h.calls.refetch).toBe(1)
  })

  test('the first open is the initial connect; a reconnect refetches', () => {
    const h = harness({ deviceId: 'me' })
    h.live.start()
    h.stream.handlers.onOpen!()
    expect(h.calls.refetch).toBe(0)
    h.advance(THROTTLE_MS)
    h.stream.handlers.onOpen!()
    expect(h.calls.refetch).toBe(1)
  })

  test('visibilitychange to visible refetches, throttled to once per 5s', async () => {
    const h = harness({ deviceId: 'me' })
    h.live.start()
    h.docListeners.get('visibilitychange')!()
    expect(h.calls.refetch).toBe(1)
    await Promise.resolve()
    await Promise.resolve()
    h.advance(THROTTLE_MS - 1)
    h.docListeners.get('visibilitychange')!()
    h.winListeners.get('focus')!()
    expect(h.calls.refetch).toBe(1)
    h.advance(1)
    h.winListeners.get('focus')!()
    expect(h.calls.refetch).toBe(2)
  })

  test('becoming hidden does not refetch', () => {
    const h = harness({ deviceId: 'me' })
    h.live.start()
    h.doc.visibilityState = 'hidden'
    h.docListeners.get('visibilitychange')!()
    expect(h.calls.refetch).toBe(0)
  })

  test('stop closes the stream, clears the timer and removes listeners', () => {
    const h = harness({ deviceId: 'me' })
    h.live.start()
    h.stream.handlers.onPosition!(ev())
    expect(h.timers.size).toBe(1)
    h.live.stop()
    expect(h.stream.closed).toBe(1)
    expect(h.timers.size).toBe(0)
    expect(h.docListeners.size).toBe(0)
    expect(h.winListeners.size).toBe(0)
    h.advance(DEBOUNCE_MS * 2)
    expect(h.calls.refetch).toBe(0)
  })

  test('a failing refetch is swallowed and a later one still runs', async () => {
    let n = 0
    const h = harness({ deviceId: 'me' })
    const live = createLiveProgress(
      {
        refetch: async () => {
          n++
          throw new Error('boom')
        },
        deviceId: () => 'me',
      },
      {
        subscribe: () => () => {},
        setTimeout: () => 0,
        clearTimeout: () => {},
        now: (() => {
          let t = 0
          return () => (t += 10_000)
        })(),
        doc: h.doc,
        win: h.win,
      },
    )
    live.start()
    h.docListeners.get('visibilitychange')!()
    await Promise.resolve()
    h.docListeners.get('visibilitychange')!()
    expect(n).toBe(2)
  })
})

// The no-spinner property of the series view lives in how a refresh is applied:
// the payload is patched in place, so `series` is never nulled between events.
describe('patchSeriesProgress', () => {
  const mk = () =>
    ({
      id: 's',
      seasons: [
        {
          id: 'a',
          episodes: [
            { id: 'e1', mediaItemId: 'file-1', positionSeconds: 0, watched: false },
            { id: 'e2', mediaItemId: 'file-1', positionSeconds: 0, watched: false },
            { id: 'e3', mediaItemId: 'file-2', positionSeconds: 5, watched: false },
            { id: 'e4', mediaItemId: null, positionSeconds: 0, watched: false },
          ],
        },
      ],
    }) as unknown as Parameters<typeof patchSeriesProgress>[0]

  test('updates every episode sharing the mediaItemId and nothing else', () => {
    const s = mk()
    const before = s.seasons
    expect(
      patchSeriesProgress(s, ev({ itemId: 'file-1', positionSeconds: 99, watched: true })),
    ).toBe(true)
    const eps = s.seasons[0]!.episodes
    expect(eps.map((e) => [e.positionSeconds, e.watched])).toEqual([
      [99, true],
      [99, true],
      [5, false],
      [0, false],
    ])
    expect(s.seasons).toBe(before)
  })

  test('reports no match for an unknown item', () => {
    const s = mk()
    expect(patchSeriesProgress(s, ev({ itemId: 'nope' }))).toBe(false)
    expect(seriesHasItem(s, 'file-2')).toBe(true)
    expect(seriesHasItem(s, 'nope')).toBe(false)
  })
})
