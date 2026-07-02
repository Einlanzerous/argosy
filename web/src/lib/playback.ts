import { api, getToken } from '@/api/client'
import type { components } from '@/api/schema'

export type PlayState = components['schemas']['PlayState']
export type ContinueItem = components['schemas']['ContinueItem']
export type OnDeckItem = components['schemas']['OnDeckItem']
export type PlaybackInfo = components['schemas']['PlaybackInfo']
export type TranscodeSession = components['schemas']['TranscodeSession']
export type SubtitleTrack = components['schemas']['SubtitleTrack']
export type DevicePreferences = components['schemas']['DevicePreferences']
export type UserPreferences = components['schemas']['UserPreferences']

// getUserPreferences returns the profile's account-wide preferences (e.g. the
// home layout), defaulting to discovery on the server when unset.
export async function getUserPreferences(): Promise<UserPreferences | null> {
  const { data } = await api.GET('/api/v1/user/preferences')
  return data ?? null
}

export async function putUserPreferences(prefs: UserPreferences): Promise<void> {
  await api.PUT('/api/v1/user/preferences', { body: prefs })
}

// getPreferences returns this device's saved playback preferences (subtitle
// language/on-off, audio language). Defaults (subtitles off) when none saved.
export async function getPreferences(): Promise<DevicePreferences | null> {
  const { data } = await api.GET('/api/v1/preferences')
  return data ?? null
}

// putPreferences persists this device's playback preferences.
export async function putPreferences(prefs: DevicePreferences): Promise<void> {
  await api.PUT('/api/v1/preferences', { body: prefs })
}

// supportsHevc reports whether this client can play 4K HEVC (including 10-bit
// Main 10 / HDR) in fMP4 via MSE. We probe the hardest case — Main 10 at level
// 5.1 (4K) — so a positive answer means it's safe for the server to copy *any*
// HEVC source untouched (native resolution, bit depth, HDR) instead of
// re-encoding it down to H.264 1080p. hvc1 matches the sample-entry tag we mux.
export function supportsHevc(): boolean {
  if (typeof MediaSource === 'undefined' || !MediaSource.isTypeSupported) return false
  return MediaSource.isTypeSupported('video/mp4; codecs="hvc1.2.4.L153.B0"')
}

// startTranscode begins (or joins) a server-side HLS transcode for an item that
// can't be direct-played, returning the session + its playlist URL. It advertises
// the client's HEVC capability so 4K HEVC can be passed through (copied) rather
// than re-encoded.
export async function startTranscode(
  itemId: string,
  startAt = 0,
): Promise<TranscodeSession | null> {
  const { data } = await api.POST('/api/v1/items/{itemId}/transcode', {
    params: { path: { itemId } },
    body: { startAt, hevc: supportsHevc() },
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

// listSubtitles returns the available subtitle tracks for an item (embedded text
// tracks + OpenSubtitles candidates when configured).
export async function listSubtitles(itemId: string): Promise<SubtitleTrack[]> {
  const { data } = await api.GET('/api/v1/items/{itemId}/subtitles', {
    params: { path: { itemId } },
  })
  return data ?? []
}

// subtitleUrl authorizes via ?token= for the same reason as the stream endpoint;
// we fetch it as text (with the bearer header) and serve a blob to the <track>.
export function subtitleUrl(itemId: string, trackId: string): string {
  return `/api/v1/items/${itemId}/subtitles/${encodeURIComponent(trackId)}?token=${encodeURIComponent(getToken() ?? '')}`
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

// setSeasonWatched marks every episode of a season watched/unwatched in one call
// (ARGY-109). Resume positions are left intact server-side; only the flag flips.
export async function setSeasonWatched(seasonId: string, watched: boolean): Promise<void> {
  await api.POST('/api/v1/seasons/{seasonId}/watched', {
    params: { path: { seasonId } },
    body: { watched },
  })
}

// setSeriesWatched marks every episode across all seasons of a series (ARGY-109).
export async function setSeriesWatched(seriesId: string, watched: boolean): Promise<void> {
  await api.POST('/api/v1/series/{seriesId}/watched', {
    params: { path: { seriesId } },
    body: { watched },
  })
}

export async function getContinue(): Promise<ContinueItem[]> {
  const { data } = await api.GET('/api/v1/continue')
  return data ?? []
}

// getOnDeck returns the next-up episode of each series the profile is current on
// (distinct from in-progress items, which are in getContinue).
export async function getOnDeck(): Promise<OnDeckItem[]> {
  const { data } = await api.GET('/api/v1/ondeck')
  return data ?? []
}

// getNextEpisode returns the episode that follows itemId in its series (across
// season boundaries), or null when there's nothing after it — the item is the
// last episode, or isn't a series episode at all. Powers player auto-advance.
export async function getNextEpisode(itemId: string): Promise<OnDeckItem | null> {
  const { data } = await api.GET('/api/v1/items/{itemId}/next-episode', {
    params: { path: { itemId } },
  })
  return data ?? null
}
