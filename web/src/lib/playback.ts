import { api, getToken } from '@/api/client'
import type { components } from '@/api/schema'

export type PlayState = components['schemas']['PlayState']
export type ContinueItem = components['schemas']['ContinueItem']
export type PlaybackInfo = components['schemas']['PlaybackInfo']
export type TranscodeSession = components['schemas']['TranscodeSession']

// startTranscode begins (or joins) a server-side HLS transcode for an item that
// can't be direct-played, returning the session + its playlist URL.
export async function startTranscode(
  itemId: string,
  startAt = 0,
): Promise<TranscodeSession | null> {
  const { data } = await api.POST('/api/v1/items/{itemId}/transcode', {
    params: { path: { itemId } },
    body: { startAt },
  })
  return data ?? null
}

// stopTranscode tears a session down so the server frees it immediately rather
// than waiting for the idle reaper.
export async function stopTranscode(sessionId: string): Promise<void> {
  await api.DELETE('/api/v1/transcode/{sessionId}', { params: { path: { sessionId } } })
}

export async function getPlaybackInfo(itemId: string): Promise<PlaybackInfo | null> {
  const { data } = await api.GET('/api/v1/items/{itemId}/playback', {
    params: { path: { itemId } },
  })
  return data ?? null
}

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
