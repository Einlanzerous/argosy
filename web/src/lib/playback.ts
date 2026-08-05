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
//
// The string must stay the same *shape* as the one the server advertises in a
// master playlist (`hvc1.<profile>.4.L<level>.B0`), because that is the string
// hls.js re-checks with isTypeSupported before it will touch the variant —
// answering "yes, HEVC" here about a form the browser then rejects is what made
// ARGY-174 silent.
//
// Profile and level are not guaranteed to match: a remux copies the source's
// own, and nothing stops a source from exceeding Main 10 @ 5.1 (a level 6.x
// encode, say). This probe is a representative ceiling, not an enforced bound —
// past it the manifest is rejected the same way. The server-side "session
// encoded segments but never served one" warning is what makes that case
// audible; closing it properly means negotiating per item (ARGY-175).
export function supportsHevc(): boolean {
  if (typeof MediaSource === 'undefined' || !MediaSource.isTypeSupported) return false
  return MediaSource.isTypeSupported('video/mp4; codecs="hvc1.2.4.L153.B0"')
}

// supportsHevcInHardware reports whether 10-bit HEVC decodes in *hardware* here.
// supportsHevc() cannot answer this — isTypeSupported says "supported" for a
// stream the client will software-decode and stutter on, and that ambiguity is
// the whole reason 10-bit sources were re-encoded to 8-bit unconditionally
// (ARGY-150), costing every 4K HDR title its resolution and its HDR (ARGY-178).
//
// MediaCapabilities answers it directly: `powerEfficient` means a hardware
// decoder, `smooth` means it keeps up at this resolution and bitrate. We require
// both, at the hardest realistic case (Main 10, level 5.1, 4K, ~20 Mbps), so a
// yes covers anything lighter. Anything unexpected — no MediaCapabilities, a
// rejected configuration, a rejected promise — resolves false and leaves the
// 8-bit re-encode in place.
export async function supportsHevcInHardware(): Promise<boolean> {
  const mc = navigator.mediaCapabilities
  if (!mc?.decodingInfo) return false
  try {
    const info = await mc.decodingInfo({
      type: 'media-source',
      video: {
        contentType: 'video/mp4; codecs="hvc1.2.4.L153.B0"',
        width: 3840,
        height: 2160,
        bitrate: 20_000_000,
        framerate: 30,
      },
    })
    return info.supported && info.smooth && info.powerEfficient
  } catch {
    return false
  }
}

// startTranscode begins (or joins) a server-side HLS transcode for an item that
// can't be direct-played, returning the session + its playlist URL. It advertises
// the client's HEVC capability so 4K HEVC can be passed through (copied) rather
// than re-encoded, and whether that decode is in hardware so a 10-bit source can
// keep its bit depth and HDR.
export async function startTranscode(
  itemId: string,
  startAt = 0,
): Promise<TranscodeSession | null> {
  const { data } = await api.POST('/api/v1/items/{itemId}/transcode', {
    params: { path: { itemId } },
    body: { startAt, hevc: supportsHevc(), hevcHardware: await supportsHevcInHardware() },
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

// --- ABR throughput memory (ARGY-177) -----------------------------------------
// Module scope on purpose. Every seek and every auto-advance tears the hls.js
// instance down, and App.vue keys the player by route.fullPath — so auto-advance
// remounts PlayerView entirely and any component-scoped value would reset. Held
// here, a link measured once is not re-learned from scratch on each restart.
let measured = 0

// rememberBandwidth records a throughput figure hls.js actually measured.
// Callers must only pass an estimate taken after a fragment completed: with no
// samples, hls.bandwidthEstimate returns the configured default, and feeding
// that back as abrEwmaDefaultEstimate would suppress the manifest-derived seed
// for the rest of the session — pinning playback to the lowest rung on a link
// that was never measured.
export function rememberBandwidth(bps: number): void {
  if (Number.isFinite(bps) && bps > 0) measured = bps
}

// measuredBandwidth is the last measured throughput, or 0 if nothing has been
// measured yet in this page session.
export function measuredBandwidth(): number {
  return measured
}
