import type { BeaconEvent, subscribeBeacon } from '@/lib/beacon'
import type { components } from '@/api/schema'

// Keeps an already-open page honest about progress made on ANOTHER device
// (ARGY-290). Beacon pushes a `position` event whenever any of the user's
// devices moves or finishes an item; a page that fetched once on mount never
// saw it. This subscribes, patches what it can immediately (onChange), and
// reconciles with a debounced silent refetch, which is the authority — the
// server derives resume points and next-up, the event only carries a position.
//
// Beacon has no Last-Event-ID replay, so events missed while the stream was down
// are lost: the refetch on reconnect, on tab visibility and on window focus is
// what covers the gap (and is the fallback when SSE is unavailable at all).

export const DEBOUNCE_MS = 1500
export const THROTTLE_MS = 5000

export interface LiveProgressOptions {
  // Whether an event concerns what this page shows. Defaults to everything.
  relevant?: (ev: BeaconEvent) => boolean
  // Called synchronously for each relevant foreign event, before the refetch.
  onChange?: (ev: BeaconEvent) => void
  // The silent reconcile. Must not flash a spinner or reset view state.
  refetch: () => void | Promise<void>
  // This device's id. Events whose originDeviceId matches are our own echo. The
  // server stamps originDeviceId from the bearer token's session, so every
  // write this browser makes already carries it — nothing is sent from here.
  deviceId: () => string | undefined
}

// Everything the machine touches outside itself, injected so tests drive a fake
// clock, stream and document (see useLiveProgress.ts for the real wiring).
export interface LiveProgressDeps {
  subscribe: typeof subscribeBeacon
  setTimeout: (fn: () => void, ms: number) => unknown
  clearTimeout: (h: unknown) => void
  now: () => number
  doc: Pick<Document, 'addEventListener' | 'removeEventListener' | 'visibilityState'> | null
  win: Pick<Window, 'addEventListener' | 'removeEventListener'> | null
}

export function createLiveProgress(
  opts: LiveProgressOptions,
  deps: LiveProgressDeps,
): { start: () => void; stop: () => void } {
  let closeStream: (() => void) | null = null
  let timer: unknown = null
  let lastRefetch = -Infinity
  let running = false
  let inFlight = false
  let rerun = false
  let opens = 0

  async function doRefetch(): Promise<void> {
    lastRefetch = deps.now()
    if (inFlight) {
      rerun = true
      return
    }
    inFlight = true
    try {
      await opts.refetch()
    } catch {
      /* a failed silent refresh keeps what is on screen */
    } finally {
      inFlight = false
    }
    if (rerun && running) {
      rerun = false
      void doRefetch()
    }
  }

  // Throttled trigger for open/visibility/focus: at most one per THROTTLE_MS.
  function refetchThrottled(): void {
    if (!running || deps.now() - lastRefetch < THROTTLE_MS) return
    void doRefetch()
  }

  function onPosition(ev: BeaconEvent): void {
    const mine = opts.deviceId()
    if (mine && ev.originDeviceId === mine) return
    if (opts.relevant && !opts.relevant(ev)) return
    opts.onChange?.(ev)
    // Trailing debounce: a burst of heartbeats collapses to one refetch.
    if (timer !== null) deps.clearTimeout(timer)
    timer = deps.setTimeout(() => {
      timer = null
      if (running) void doRefetch()
    }, DEBOUNCE_MS)
  }

  function onOpen(): void {
    // The first open is the initial connect, right after the page's own load —
    // refetching then is a duplicate. Every later open is a reconnect, and a
    // reconnect is exactly when events were missed.
    if (opens++ === 0) return
    refetchThrottled()
  }

  function onVisibility(): void {
    if (deps.doc?.visibilityState === 'visible') refetchThrottled()
  }

  return {
    start() {
      if (running) return
      running = true
      closeStream = deps.subscribe({ onPosition, onOpen })
      deps.doc?.addEventListener('visibilitychange', onVisibility)
      deps.win?.addEventListener('focus', refetchThrottled)
    },
    stop() {
      running = false
      rerun = false
      closeStream?.()
      closeStream = null
      if (timer !== null) deps.clearTimeout(timer)
      timer = null
      deps.doc?.removeEventListener('visibilitychange', onVisibility)
      deps.win?.removeEventListener('focus', refetchThrottled)
    },
  }
}

type SeriesDetail = components['schemas']['SeriesDetail']

// patchSeriesProgress applies a foreign position event to every episode that
// shares the event's mediaItemId (a combined rip backs several episode numbers
// with one file). Returns whether anything matched.
export function patchSeriesProgress(series: SeriesDetail, ev: BeaconEvent): boolean {
  let hit = false
  for (const s of series.seasons) {
    for (const e of s.episodes) {
      if (e.mediaItemId !== ev.itemId) continue
      e.positionSeconds = ev.positionSeconds
      e.watched = ev.watched
      hit = true
    }
  }
  return hit
}

export function seriesHasItem(series: SeriesDetail, itemId: string): boolean {
  return series.seasons.some((s) => s.episodes.some((e) => e.mediaItemId === itemId))
}
