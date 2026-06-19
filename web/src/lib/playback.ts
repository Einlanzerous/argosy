import { api, getToken } from '@/api/client'
import type { components } from '@/api/schema'

export type PlayState = components['schemas']['PlayState']
export type ContinueItem = components['schemas']['ContinueItem']

// The stream endpoint authorizes via ?token= because an HTML5 <video> can't set
// the Authorization header.
export function streamUrl(itemId: string): string {
  return `/api/v1/items/${itemId}/stream?token=${encodeURIComponent(getToken() ?? '')}`
}

export async function getProgress(itemId: string): Promise<PlayState | null> {
  const { data } = await api.GET('/api/v1/items/{itemId}/progress', {
    params: { path: { itemId } },
  })
  return data ?? null
}

export async function reportProgress(
  itemId: string,
  positionSeconds: number,
  durationSeconds?: number,
): Promise<void> {
  await api.PUT('/api/v1/items/{itemId}/progress', {
    params: { path: { itemId } },
    body: { positionSeconds, durationSeconds },
  })
}

export async function setWatched(itemId: string, watched: boolean): Promise<void> {
  await api.POST('/api/v1/items/{itemId}/watched', {
    params: { path: { itemId } },
    body: { watched },
  })
}

export async function getContinue(): Promise<ContinueItem[]> {
  const { data } = await api.GET('/api/v1/continue')
  return data ?? []
}
