import { getToken } from '@/api/client'

// A live play-state change pushed by Beacon (one of the current user's devices
// moved/finished an item). Mirrors internal/beacon.Event.
export interface BeaconEvent {
  userId: string
  itemId: string
  positionSeconds: number
  durationSeconds?: number
  watched: boolean
  originDeviceId?: string
  updatedAt: string
}

// subscribeBeacon opens the SSE stream of the current user's play-state changes
// (cross-device resume). Returns a close() fn. The browser's EventSource
// auto-reconnects on drop; `onOpen` fires on each (re)connect so the caller can
// reconcile any updates missed while disconnected with a plain fetch. The token
// rides as a query param because EventSource can't set the Authorization header.
export function subscribeBeacon(handlers: {
  onPosition?: (ev: BeaconEvent) => void
  onOpen?: () => void
}): () => void {
  const token = getToken()
  if (!token || typeof EventSource === 'undefined') return () => {}

  const es = new EventSource(`/api/v1/beacon?token=${encodeURIComponent(token)}`)
  if (handlers.onOpen) es.addEventListener('open', () => handlers.onOpen?.())
  es.addEventListener('position', (e) => {
    try {
      handlers.onPosition?.(JSON.parse((e as MessageEvent).data) as BeaconEvent)
    } catch {
      /* ignore malformed frame */
    }
  })
  return () => es.close()
}
