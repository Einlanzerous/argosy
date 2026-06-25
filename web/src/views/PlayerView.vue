<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Hls from 'hls.js'
import { api, getToken } from '@/api/client'
import { posterStyle } from '@/lib/poster'
import { formatClock, formatTitle } from '@/lib/format'
import {
  getNextEpisode,
  getPlaybackInfo,
  getPreferences,
  getProgress,
  listSubtitles,
  putPreferences,
  reportProgress,
  setWatched,
  startTranscode,
  stopTranscode,
  streamUrl,
  subtitleUrl,
  type DevicePreferences,
  type OnDeckItem,
  type SubtitleTrack,
} from '@/lib/playback'
import { parseVttCues, shiftVtt } from '@/lib/vtt'
import { useSessionStore } from '@/stores/session'
import type { components } from '@/api/schema'

type MovieDetail = components['schemas']['MediaItemDetail']

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const itemId = String(route.params.id)

const video = ref<HTMLVideoElement | null>(null)
const item = ref<MovieDetail | null>(null)
const playing = ref(false)
const position = ref(0)
const duration = ref(0)
const quality = ref('')
const error = ref('')
const starting = ref(false)
const resumeOpen = ref(false)
const resumeFrom = ref(0)
const subtitleTracks = ref<SubtitleTrack[]>([])
const activeSubtitle = ref<string | null>(null)
const subMenuOpen = ref(false)
// This device's saved playback preferences (subtitle language/on-off), applied
// when tracks load and updated when the viewer changes the subtitle (ARGY-37).
const prefs = ref<DevicePreferences | null>(null)

// Series auto-advance (ARGY-89) + credits-triggered roll-over (ARGY-90): when this
// item is a series episode and the device pref is on, an "Up Next / Play Next"
// card surfaces once the credits window begins and we roll into the next episode a
// few seconds before the file ends — rather than waiting for the hard end-of-file —
// so we don't sit on a black frame. nextEpisode is null for films or the last
// episode. The countdown tracks real remaining time, so it stays accurate and the
// card retracts if the viewer seeks back out of the window.
//
// We don't have real per-file credits markers yet (that needs embedded chapters —
// ARGY-100), so the credits window is heuristic: the last CREDITS_LEAD_SECONDS of
// runtime. creditsStart is the single seam where the chapter-marker follow-up can
// swap this heuristic for a real marker. Manual "Play Next" jumps immediately.
const CREDITS_LEAD_SECONDS = 40
// Auto roll-over fires this many seconds before the literal end, so the card shows
// a CREDITS_LEAD_SECONDS − AUTO_ADVANCE_TAIL_SECONDS = 15s countdown and then rolls
// into the next episode with ~25s of file left, instead of sitting through the
// tail. Viewers who want to cut even that hit Play Next.
const AUTO_ADVANCE_TAIL_SECONDS = 25
const autoAdvance = ref(true)
const nextEpisode = ref<OnDeckItem | null>(null)
const upNextOpen = ref(false)
const upNextCountdown = ref(0)
// Set when the viewer dismisses the card (or auto-advance is off): suppresses the
// card and the end-of-file roll-over for the rest of this episode.
const upNextCancelled = ref(false)
// Guards against firing the navigation twice (countdown end + ended event).
let advancing = false

const nextEpisodeLabel = computed(() => {
  const n = nextEpisode.value
  if (!n) return ''
  const code = `S${n.seasonNumber} E${n.episodeNumber}`
  return n.title ? `${code} · ${formatTitle(n.title)}` : code
})

// Caption styling (ARGY-43), persisted per-device, applied via ::cue.
type CaptionBg = 'translucent' | 'solid' | 'none'
const CAPTION_DEFAULTS = { scale: 1, color: '#ffffff', background: 'translucent' as CaptionBg }
const CAPTION_SCALES = [
  { v: 0.8, label: 'S' },
  { v: 1, label: 'M' },
  { v: 1.3, label: 'L' },
  { v: 1.6, label: 'XL' },
]
const CAPTION_COLORS = ['#ffffff', '#ffe082', '#80d8ff', '#a5d6a7']
const captionScale = ref(CAPTION_DEFAULTS.scale)
const captionColor = ref<string>(CAPTION_DEFAULTS.color)
const captionBackground = ref<CaptionBg>(CAPTION_DEFAULTS.background)

// A global ::cue rule styled from the prefs above. font-size as a percentage of
// the browser's default cue size keeps it scaling with the video.
const cueCss = computed(() => {
  const bg =
    captionBackground.value === 'none'
      ? 'transparent'
      : captionBackground.value === 'solid'
        ? '#000'
        : 'rgba(0, 0, 0, 0.6)'
  return `::cue{font-size:${Math.round(captionScale.value * 100)}%;color:${captionColor.value};background-color:${bg};}`
})
// The active subtitle is rendered by feeding cues straight into a single
// TextTrack (reused across switches); we track the cues we added so we can
// clear them when changing or turning off subtitles.
let subTrack: TextTrack | null = null
let subCues: VTTCue[] = []
// Chrome auto-hide: controls fade out after a few idle seconds while playing,
// and reappear on any pointer movement.
const controlsVisible = ref(true)
const isFullscreen = ref(false)
let hideTimer: ReturnType<typeof setTimeout> | null = null

// Playback mode + the media offset at which the current source begins. Direct
// play seeks natively (offset stays 0); a transcode seek restarts ffmpeg at the
// new offset, so the HLS timeline's 0 maps to baseOffset in the media.
let mode: 'direct' | 'transcode' = 'direct'
const baseOffset = ref(0)
let directAttached = false
let hls: Hls | null = null
let heartbeat: ReturnType<typeof setInterval> | null = null
let transcodeSessionId = ''

const pct = computed(() => (duration.value ? (position.value / duration.value) * 100 : 0))
const remaining = computed(() => Math.max(0, duration.value - position.value))
// Start of the credits window (ARGY-90). Heuristic for now — the last
// CREDITS_LEAD_SECONDS of runtime — but isolated here so ARGY-100 can replace it
// with a real chapter marker without touching the roll-over logic below.
const creditsStart = computed(() =>
  duration.value ? Math.max(0, duration.value - CREDITS_LEAD_SECONDS) : 0,
)
const inCredits = computed(() => duration.value > 0 && position.value >= creditsStart.value)
const backdrop = computed(() =>
  posterStyle(item.value?.backdropUrl ?? item.value?.posterUrl, item.value?.title ?? ''),
)

onMounted(async () => {
  const [{ data }, progress, playback, devicePrefs] = await Promise.all([
    api.GET('/api/v1/items/{itemId}', { params: { path: { itemId } } }),
    getProgress(itemId).catch(() => null),
    getPlaybackInfo(itemId).catch(() => null),
    getPreferences().catch(() => null),
  ])
  item.value = data ?? null
  prefs.value = devicePrefs
  if (devicePrefs) {
    captionScale.value = devicePrefs.captionScale ?? CAPTION_DEFAULTS.scale
    captionColor.value = devicePrefs.captionColor ?? CAPTION_DEFAULTS.color
    captionBackground.value = (devicePrefs.captionBackground as CaptionBg) ?? CAPTION_DEFAULTS.background
  }
  // Default ON: only an explicit false disables auto-advance. If it's off there's
  // no point asking the server for the next episode.
  autoAdvance.value = devicePrefs?.seriesAutoAdvance ?? true
  if (autoAdvance.value) {
    void getNextEpisode(itemId)
      .then((n) => (nextEpisode.value = n))
      .catch(() => {})
  }

  // Subtitle tracks load in the background; an OpenSubtitles search can take a
  // moment and shouldn't hold up playback. Once they arrive, auto-enable the
  // viewer's preferred subtitle language for this device (ARGY-37).
  void listSubtitles(itemId)
    .then((t) => {
      subtitleTracks.value = t
      applyPreferredSubtitle()
    })
    .catch(() => {})

  const el = video.value
  if (!el) return

  // The true total runtime comes from the catalog; an HLS event playlist only
  // knows the encoded-so-far length, so never trust el.duration for transcodes.
  duration.value = item.value?.durationSeconds ?? 0
  mode = playback && !playback.directPlay ? 'transcode' : 'direct'
  bindVideo(el)

  // Intent from the entry point: ?resume jumps straight to the saved position,
  // ?start forces the beginning, and a bare /player asks (only when there's
  // history). So "Resume"/Continue-Watching links resume silently, while a plain
  // "Play" still offers the choice.
  const wantResume = route.query.resume != null
  const wantStart = route.query.start != null
  const hasHistory = !!(progress && !progress.watched && progress.positionSeconds > 5)

  if (hasHistory && wantResume) {
    await playFrom(progress!.positionSeconds)
  } else if (hasHistory && !wantStart) {
    resumeFrom.value = progress!.positionSeconds
    resumeOpen.value = true
    // Ready the direct-play source so resume is instant; defer a transcode until
    // the user picks an offset so we encode from there (server-side seek).
    if (mode === 'direct') attachDirect(el)
  } else {
    await playFrom(0)
  }
})

// playFrom begins playback at an absolute media offset (seconds).
async function playFrom(offset: number): Promise<void> {
  const el = video.value
  if (!el) return
  if (mode === 'direct') {
    attachDirect(el)
    baseOffset.value = 0
    el.currentTime = offset
    void el.play().catch(() => {})
  } else {
    await startTranscodeAt(el, offset)
  }
}

function attachDirect(el: HTMLVideoElement): void {
  if (directAttached) return
  el.src = streamUrl(itemId)
  directAttached = true
}

// startTranscodeAt (re)starts a server-side transcode encoding from offset, then
// feeds the playlist to hls.js (per-device token on every request) and plays.
// The HLS timeline's 0 corresponds to baseOffset in the media.
async function startTranscodeAt(el: HTMLVideoElement, offset: number): Promise<void> {
  if (hls) {
    hls.destroy()
    hls = null
  }
  if (transcodeSessionId) {
    void stopTranscode(transcodeSessionId).catch(() => {})
    transcodeSessionId = ''
  }
  baseOffset.value = offset
  starting.value = true
  try {
    const sess = await startTranscode(itemId, offset).catch(() => null)
    if (!sess) {
      error.value = "Couldn't start transcoding this title. The server may be at capacity."
      return
    }
    transcodeSessionId = sess.id
    if (!(await waitForPlaylist(sess.playlistUrl))) {
      error.value = 'The transcoder is taking too long to start. Please try again.'
      return
    }
    if (Hls.isSupported()) {
      hls = new Hls({
        // Each transcode is encoded *from* the requested offset (HLS-timeline 0 ==
        // baseOffset in the media), so playback must always begin at position 0.
        // The transcoder emits an `event` playlist (no ENDLIST while encoding), which
        // hls.js otherwise treats as live and joins at the live edge — and a fast
        // remux-copy races so far ahead that the edge can be minutes in, dropping a
        // fresh play deep into the episode (ARGY-103). Pin the start explicitly.
        startPosition: 0,
        xhrSetup: (xhr) => {
          const t = getToken()
          if (t) xhr.setRequestHeader('Authorization', `Bearer ${t}`)
        },
      })
      hls.on(Hls.Events.MANIFEST_PARSED, () => void el.play().catch(() => {}))
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) error.value = 'This stream could not be played.'
      })
      hls.loadSource(sess.playlistUrl)
      hls.attachMedia(el)
      reapplySubtitle()
    } else {
      // Native-HLS browsers (iOS Safari) can't set an Authorization header on a
      // bare <video> src; token-in-URL support is a follow-up.
      el.src = sess.playlistUrl
      void el.play().catch(() => {})
      reapplySubtitle()
    }
  } finally {
    starting.value = false
  }
}

// waitForPlaylist polls the master playlist until ffmpeg has written it (the
// endpoint returns 503 until then), giving the encoder time to warm up.
async function waitForPlaylist(url: string): Promise<boolean> {
  const token = getToken()
  const headers: HeadersInit = token ? { Authorization: `Bearer ${token}` } : {}
  for (let i = 0; i < 40; i++) {
    try {
      const r = await fetch(url, { headers })
      if (r.ok) return true
      if (r.status !== 503) return false
    } catch {
      return false
    }
    await new Promise((res) => setTimeout(res, 500))
  }
  return false
}

onBeforeUnmount(() => {
  flush()
  if (heartbeat) clearInterval(heartbeat)
  if (hideTimer) clearTimeout(hideTimer)
  removeSubtitleEl()
  if (hls) hls.destroy()
  if (transcodeSessionId) void stopTranscode(transcodeSessionId).catch(() => {})
  const el = video.value
  if (el) {
    el.pause()
    el.removeAttribute('src')
    el.load()
  }
})

function bindVideo(el: HTMLVideoElement): void {
  el.addEventListener('loadedmetadata', () => {
    if (!duration.value) duration.value = el.duration || 0
    updateQuality(el)
  })
  // Fires when the decoded resolution changes (e.g. hls.js switches level).
  el.addEventListener('resize', () => updateQuality(el))
  el.addEventListener('timeupdate', () => {
    position.value = baseOffset.value + el.currentTime
    maybeUpNext()
  })
  el.addEventListener('play', () => {
    playing.value = true
    poke()
  })
  el.addEventListener('pause', () => {
    playing.value = false
    // Paused → keep the controls up so they're there when you come back.
    controlsVisible.value = true
    if (hideTimer) clearTimeout(hideTimer)
    flush()
  })
  el.addEventListener('seeked', flush)
  el.addEventListener('ended', () => {
    void setWatched(itemId, true).catch(() => {})
    // Roll into the next episode unless the viewer opted out (pref off or card
    // dismissed). Otherwise we leave the player on the finished episode.
    if (autoAdvance.value && nextEpisode.value && !upNextCancelled.value) advance()
  })
  el.addEventListener('error', () => {
    // hls.js surfaces its own errors; only flag native-element failures.
    if (!hls) error.value = 'This stream could not be played.'
  })
  // Throttled heartbeat while open.
  heartbeat = setInterval(() => {
    if (!el.paused) flush()
  }, 10000)
}

// updateQuality derives a friendly label from the currently decoded resolution
// (reflects the live hls.js variant, or the file for direct play).
function updateQuality(el: HTMLVideoElement): void {
  const h = el.videoHeight
  if (!h) return
  quality.value = h >= 2160 ? '4K' : `${h}p`
}

function flush(): void {
  const pos = baseOffset.value + (video.value?.currentTime ?? 0)
  if (pos > 0) {
    void reportProgress(itemId, pos, duration.value || undefined).catch(() => {})
  }
}

// maybeUpNext drives the "Up Next / Play Next" card from the live remaining
// time: it appears once playback enters the credits window and retracts if the
// viewer seeks back out of it. The countdown tracks the time left until the
// automatic roll-over, which fires AUTO_ADVANCE_TAIL_SECONDS before the file ends
// — credits-triggered rather than waiting for the 'ended' event (ARGY-90). The
// viewer can jump immediately with Play Next or opt out with Cancel.
function maybeUpNext(): void {
  if (!autoAdvance.value || !nextEpisode.value || upNextCancelled.value || advancing) return
  if (!duration.value) return
  const rem = duration.value - position.value
  if (inCredits.value && rem > 0) {
    upNextOpen.value = true
    upNextCountdown.value = Math.max(1, Math.ceil(rem - AUTO_ADVANCE_TAIL_SECONDS))
    if (rem <= AUTO_ADVANCE_TAIL_SECONDS) advance()
  } else if (!inCredits.value && upNextOpen.value) {
    upNextOpen.value = false
  }
}

// advance rolls into the next episode, resuming from its own saved position (or
// the top). Guarded so the countdown and the ended event can't double-fire it.
function advance(): void {
  const next = nextEpisode.value
  if (advancing || !next) return
  advancing = true
  flush()
  void router.push({ name: 'player', params: { id: next.id }, query: { resume: '1' } })
}

// playNext skips the rest of the credits/countdown and jumps straight to the
// next episode (ARGY-90).
function playNext(): void {
  advance()
}

// cancelUpNext dismisses the card and suppresses auto-advance for the remainder
// of this episode, leaving the player on the finished episode at the end.
function cancelUpNext(): void {
  upNextOpen.value = false
  upNextCancelled.value = true
}

// poke reveals the controls and schedules them to hide again after an idle
// stretch — but only while actually playing and with no menu/prompt open.
function poke(): void {
  controlsVisible.value = true
  if (hideTimer) clearTimeout(hideTimer)
  hideTimer = setTimeout(() => {
    if (playing.value && !subMenuOpen.value && !resumeOpen.value) controlsVisible.value = false
  }, 4000)
}

function togglePlay(): void {
  poke()
  const el = video.value
  if (!el) return
  if (el.paused) void el.play().catch(() => {})
  else el.pause()
}

function seek(e: MouseEvent): void {
  if (!duration.value) return
  const bar = e.currentTarget as HTMLElement
  const rect = bar.getBoundingClientRect()
  void seekTo(((e.clientX - rect.left) / rect.width) * duration.value)
}

function skip(delta: number): void {
  void seekTo(position.value + delta)
}

// seekTo seeks to an absolute media time. Direct play seeks natively; a
// transcode seek stays native when the target is already encoded/buffered,
// otherwise restarts ffmpeg from the new offset.
async function seekTo(t: number): Promise<void> {
  const el = video.value
  if (!el) return
  t = Math.max(0, duration.value ? Math.min(duration.value, t) : t)
  if (mode === 'direct') {
    el.currentTime = t
    return
  }
  const rel = t - baseOffset.value
  const buffered = el.seekable.length ? el.seekable.end(el.seekable.length - 1) : 0
  if (rel >= 0 && rel <= buffered) {
    el.currentTime = rel
  } else {
    await startTranscodeAt(el, t)
  }
}

// selectSubtitle switches the active track (null = off). Selection persists
// across transcode restarts via reapplySubtitle, and (when persist) is saved as
// this device's preference so it auto-applies on the next title.
async function selectSubtitle(trackId: string | null, persist = true): Promise<void> {
  subMenuOpen.value = false
  activeSubtitle.value = trackId
  removeSubtitleEl()
  if (trackId) await applySubtitle(trackId)
  if (persist) void savePreferredSubtitle(trackId)
}

// savePreferredSubtitle persists the subtitle choice for this device. Turning
// subtitles off keeps the last language, so re-enabling remembers it.
// buildPrefs assembles a full DevicePreferences from current state, so saving one
// facet (subtitle choice or caption style) never clobbers the others.
function buildPrefs(over: Partial<DevicePreferences>): DevicePreferences {
  return {
    subtitleEnabled: prefs.value?.subtitleEnabled ?? false,
    subtitleLanguage: prefs.value?.subtitleLanguage ?? null,
    audioLanguage: prefs.value?.audioLanguage ?? null,
    captionScale: captionScale.value,
    captionColor: captionColor.value,
    captionBackground: captionBackground.value,
    seriesAutoAdvance: prefs.value?.seriesAutoAdvance ?? true,
    ...over,
  }
}

function savePreferredSubtitle(trackId: string | null): Promise<void> {
  const track = trackId ? subtitleTracks.value.find((t) => t.id === trackId) : null
  const next = buildPrefs({
    subtitleEnabled: trackId != null,
    subtitleLanguage: track?.language ?? prefs.value?.subtitleLanguage ?? null,
  })
  prefs.value = next
  return putPreferences(next).catch(() => {})
}

function saveCaptionStyle(): void {
  const next = buildPrefs({})
  prefs.value = next
  void putPreferences(next).catch(() => {})
}
function setCaptionScale(v: number): void {
  captionScale.value = v
  saveCaptionStyle()
}
function setCaptionColor(v: string): void {
  captionColor.value = v
  saveCaptionStyle()
}
function setCaptionBackground(v: CaptionBg): void {
  captionBackground.value = v
  saveCaptionStyle()
}

// applyPreferredSubtitle auto-enables the saved subtitle language once tracks
// load — only if the viewer hasn't already picked one this session.
function applyPreferredSubtitle(): void {
  if (activeSubtitle.value) return
  const p = prefs.value
  if (!p?.subtitleEnabled || !p.subtitleLanguage) return
  const match = subtitleTracks.value.find((t) => t.language === p.subtitleLanguage)
  if (match) void selectSubtitle(match.id, false)
}

// applySubtitle fetches the WebVTT (authenticated), rewrites its cue timings for
// the current transcode offset, and loads the cues into the TextTrack. Rebuilding
// per offset keeps cues aligned whether we direct-play or seek a transcode.
async function applySubtitle(trackId: string): Promise<void> {
  const el = video.value
  const track = subtitleTracks.value.find((t) => t.id === trackId)
  if (!el || !track) return
  try {
    const token = getToken()
    const r = await fetch(subtitleUrl(itemId, trackId), {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    })
    if (!r.ok) return
    let text = await r.text()
    if (baseOffset.value > 0) text = shiftVtt(text, -baseOffset.value)
    // A stale selection may have changed while we awaited the fetch.
    if (activeSubtitle.value !== trackId) return
    const cues = parseVttCues(text)
    clearSubCues()
    if (!subTrack) subTrack = el.addTextTrack('subtitles', 'Argosy', track.language || 'und')
    for (const c of cues) {
      const cue = new VTTCue(c.start, c.end, c.text)
      // Position cues at 84% height (from the top) so they sit above the control
      // bar and stay visible when controls are up; the default pins them to the
      // very bottom, behind the controls.
      cue.snapToLines = false
      cue.line = 84
      subTrack.addCue(cue)
      subCues.push(cue)
    }
    subTrack.mode = 'showing'
  } catch {
    /* leave subtitles off on failure */
  }
}

// reapplySubtitle rebuilds the active track against a new transcode offset.
function reapplySubtitle(): void {
  if (activeSubtitle.value) void applySubtitle(activeSubtitle.value)
}

function clearSubCues(): void {
  if (subTrack) {
    for (const c of subCues) {
      try {
        subTrack.removeCue(c)
      } catch {
        /* cue already gone */
      }
    }
  }
  subCues = []
}

function removeSubtitleEl(): void {
  clearSubCues()
  if (subTrack) subTrack.mode = 'disabled'
}

// fullscreen toggles: exit when already fullscreen, otherwise expand the player.
function fullscreen(): void {
  if (document.fullscreenElement) {
    void document.exitFullscreen().catch(() => {})
    return
  }
  const el = video.value?.closest('.player') as HTMLElement | null
  if (el?.requestFullscreen) void el.requestFullscreen().catch(() => {})
}

function onFullscreenChange(): void {
  isFullscreen.value = !!document.fullscreenElement
}
onMounted(() => document.addEventListener('fullscreenchange', onFullscreenChange))
onBeforeUnmount(() => document.removeEventListener('fullscreenchange', onFullscreenChange))

function resume(): void {
  resumeOpen.value = false
  void playFrom(resumeFrom.value)
}

function startOver(): void {
  resumeOpen.value = false
  void playFrom(0)
}

function goBack(): void {
  if (window.history.length > 1) router.back()
  else void router.push({ name: 'home' })
}

function onKey(e: KeyboardEvent): void {
  if (resumeOpen.value) return
  if (e.key === 'Escape' && subMenuOpen.value) {
    subMenuOpen.value = false
    return
  }
  if (e.key === 'Escape' && upNextOpen.value) {
    cancelUpNext()
    return
  }
  // 'n' jumps to the next episode while the card is up (ARGY-90).
  if (e.key === 'n' && upNextOpen.value && nextEpisode.value) {
    playNext()
    return
  }
  if (e.key === ' ') {
    e.preventDefault()
    togglePlay()
  } else if (e.key === 'ArrowLeft') skip(-10)
  else if (e.key === 'ArrowRight') skip(10)
  else if (e.key === 'f') fullscreen()
  else if (e.key === 'c' && subtitleTracks.value.length) subMenuOpen.value = !subMenuOpen.value
  else if (e.key === 'Escape') goBack()
}
onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <!-- Per-device caption styling, applied to the native ::cue pseudo-element. -->
  <component :is="'style'">{{ cueCss }}</component>
  <div class="player" :class="{ idle: !controlsVisible }" @mousemove="poke">
    <div class="backdrop" :style="backdrop" />
    <div class="arg-hatch backdrop-hatch" />
    <video ref="video" class="video" playsinline @click="togglePlay" />
    <div class="vignette" />

    <!-- top chrome -->
    <div class="top" :class="{ hidden: !controlsVisible }">
      <div class="top-left">
        <button class="back" type="button" @click="goBack">‹</button>
        <div>
          <div class="title">{{ item ? formatTitle(item.title) : 'Loading…' }}</div>
          <div class="sub">{{ item?.year ?? '' }}</div>
        </div>
      </div>
      <div class="top-right">
        <span v-if="quality" class="quality">{{ quality }}</span>
        <button
          class="icon-btn"
          type="button"
          :title="isFullscreen ? 'Exit fullscreen' : 'Fullscreen'"
          @click="fullscreen"
        >
          {{ isFullscreen ? '▢' : '⛶' }}
        </button>
      </div>
    </div>

    <!-- preparing transcode -->
    <div v-if="starting" class="center prep">
      <div class="prep-card">
        <div class="prep-spinner" />
        <div class="prep-text">Preparing your stream…</div>
        <div class="prep-sub">Transcoding for your device</div>
      </div>
    </div>

    <!-- center play -->
    <div v-if="!playing && !error && !starting && !resumeOpen" class="center">
      <button class="big-play" type="button" @click="togglePlay">▶</button>
    </div>

    <!-- error overlay -->
    <div v-if="error" class="error">
      <div class="error-card">
        <div class="error-eyebrow">Can't direct-play</div>
        <p>{{ error }}</p>
        <button type="button" @click="goBack">Back to details</button>
      </div>
    </div>

    <!-- bottom controls -->
    <div class="bottom" :class="{ hidden: !controlsVisible }">
      <div class="scrub">
        <span class="t">{{ formatClock(position) }}</span>
        <div class="bar" @click="seek">
          <div class="fill" :style="{ width: `${pct}%` }" />
          <div class="knob" :style="{ left: `${pct}%` }" />
        </div>
        <span class="t">{{ formatClock(duration) }}</span>
      </div>
      <div class="buttons">
        <div class="btn-left">
          <div class="device-pill">
            <span class="dot" /> Playing on {{ session.deviceName || 'this device' }}
          </div>
        </div>
        <div class="btn-mid">
        <button class="ctrl" type="button" title="Back 10s" @click="skip(-10)">
          <span class="ic">↺</span><span class="lbl">10s</span>
        </button>
        <button
          class="ctrl primary"
          :class="{ glow: !playing }"
          type="button"
          :title="playing ? 'Pause' : 'Play'"
          @click="togglePlay"
        >
          <span class="ic">{{ playing ? '❚❚' : '▶' }}</span>
          <span class="lbl">{{ playing ? 'Pause' : 'Play' }}</span>
        </button>
        <button class="ctrl" type="button" title="Forward 10s" @click="skip(10)">
          <span class="ic">↻</span><span class="lbl">10s</span>
        </button>
        </div>
        <div class="btn-right">
        <div v-if="subtitleTracks.length" class="cc-wrap">
          <button
            class="ctrl icon-only"
            :class="{ on: activeSubtitle }"
            type="button"
            title="Subtitles"
            @click="subMenuOpen = !subMenuOpen"
          >
            <span class="ic cc">CC</span>
          </button>
          <div v-if="subMenuOpen" class="cc-menu">
            <div class="cc-head">Subtitles</div>
            <button class="cc-item" :class="{ sel: !activeSubtitle }" type="button" @click="selectSubtitle(null)">
              <span class="cc-label">Off</span>
              <span v-if="!activeSubtitle" class="cc-check">✓</span>
            </button>
            <button
              v-for="t in subtitleTracks"
              :key="t.id"
              class="cc-item"
              :class="{ sel: activeSubtitle === t.id }"
              type="button"
              @click="selectSubtitle(t.id)"
            >
              <span class="cc-label">
                {{ t.label }}
                <span class="cc-src">{{ t.source === 'opensubtitles' ? 'OpenSubtitles' : 'Embedded' }}</span>
              </span>
              <span v-if="activeSubtitle === t.id" class="cc-check">✓</span>
            </button>

            <div class="cc-head cc-style-head">Caption style</div>
            <div class="cc-style-row">
              <span class="cc-style-label">Size</span>
              <div class="cc-seg">
                <button
                  v-for="s in CAPTION_SCALES"
                  :key="s.v"
                  type="button"
                  :class="{ on: captionScale === s.v }"
                  @click="setCaptionScale(s.v)"
                >
                  {{ s.label }}
                </button>
              </div>
            </div>
            <div class="cc-style-row">
              <span class="cc-style-label">Color</span>
              <div class="cc-swatches">
                <button
                  v-for="c in CAPTION_COLORS"
                  :key="c"
                  type="button"
                  class="cc-swatch"
                  :class="{ on: captionColor === c }"
                  :style="{ background: c }"
                  @click="setCaptionColor(c)"
                />
              </div>
            </div>
            <div class="cc-style-row">
              <span class="cc-style-label">Background</span>
              <div class="cc-seg">
                <button
                  type="button"
                  :class="{ on: captionBackground === 'translucent' }"
                  @click="setCaptionBackground('translucent')"
                >
                  Dim
                </button>
                <button
                  type="button"
                  :class="{ on: captionBackground === 'solid' }"
                  @click="setCaptionBackground('solid')"
                >
                  Solid
                </button>
                <button
                  type="button"
                  :class="{ on: captionBackground === 'none' }"
                  @click="setCaptionBackground('none')"
                >
                  None
                </button>
              </div>
            </div>
          </div>
        </div>
        </div>
      </div>
    </div>

    <!-- Up Next / Play Next: auto-advance to the next episode (ARGY-89/90).
         Surfaces once the credits window begins; the countdown mirrors the time
         left until the automatic roll-over (which fires shortly before the file
         ends), and "Play Next" jumps straight into the next episode. -->
    <div v-if="upNextOpen && nextEpisode" class="up-next">
      <div class="up-next-card">
        <div class="up-next-head">
          <span class="up-next-eyebrow">Up Next</span>
          <span class="up-next-count">in {{ upNextCountdown }}s</span>
        </div>
        <div class="up-next-title">{{ nextEpisodeLabel }}</div>
        <div v-if="nextEpisode.seriesTitle" class="up-next-series">{{ nextEpisode.seriesTitle }}</div>
        <div class="up-next-actions">
          <button class="up-next-play" type="button" @click="playNext">⏭ Play Next</button>
          <button class="up-next-cancel" type="button" @click="cancelUpNext">Cancel</button>
        </div>
      </div>
    </div>

    <!-- ★ cross-device resume prompt -->
    <div v-if="resumeOpen" class="resume-scrim">
      <div class="resume-card">
        <div class="resume-eyebrow"><span>⇄</span> Cross-device resume</div>
        <div class="resume-title">Pick up where you left off?</div>
        <div class="resume-body">
          You were watching <strong>{{ item?.title }}</strong> on another device in your Fleet.
        </div>
        <div class="resume-stat">
          <div>
            <div class="stat-label">Left off at</div>
            <div class="stat-time">{{ formatClock(resumeFrom) }}</div>
          </div>
          <div class="stat-right">
            <span>{{ formatClock(remaining || duration - resumeFrom) }} remaining</span>
          </div>
        </div>
        <button class="resume-primary" type="button" @click="resume">
          Resume from {{ formatClock(resumeFrom) }}
        </button>
        <button class="resume-ghost" type="button" @click="startOver">Start from the beginning</button>
        <div class="resume-foot">Synced across your Fleet</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.player {
  position: relative;
  min-height: 100vh;
  background: var(--arg-ink);
  overflow: hidden;
}
.backdrop {
  position: absolute;
  inset: 0;
  opacity: 0.25;
}
.backdrop-hatch {
  position: absolute;
  inset: 0;
  opacity: 0.4;
}
.video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: transparent;
}
.vignette {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: radial-gradient(80% 60% at 50% 42%, rgba(0, 0, 0, 0) 0%, rgba(8, 8, 7, 0.35) 75%, var(--arg-ink) 100%);
}
.top {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  padding: 24px 30px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: linear-gradient(#0c0c0bcc, transparent);
  transition: opacity 0.3s ease;
}
.top.hidden,
.bottom.hidden {
  opacity: 0;
  pointer-events: none;
}
.player.idle {
  cursor: none;
}
.top-left {
  display: flex;
  align-items: center;
  gap: 16px;
}
.back {
  width: 40px;
  height: 40px;
  border-radius: var(--arg-r);
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.6);
  color: var(--arg-cream);
  font: 700 18px var(--arg-display);
  cursor: pointer;
}
.back:hover {
  border-color: var(--arg-accent);
}
.title {
  font: 700 17px var(--arg-display);
}
.sub {
  font: 500 12px var(--arg-body);
  color: var(--arg-dim);
}
.top-right {
  display: flex;
  align-items: center;
  gap: 10px;
}
.quality {
  height: 32px;
  display: inline-flex;
  align-items: center;
  padding: 0 12px;
  border-radius: 8px;
  border: 1px solid rgba(201, 154, 78, 0.5);
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent);
  font: 800 12px var(--arg-display);
  letter-spacing: 0.04em;
}
.icon-btn {
  width: 38px;
  height: 32px;
  border-radius: 8px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.5);
  color: var(--arg-cream);
  font-size: 16px;
  line-height: 1;
  cursor: pointer;
}
.icon-btn:hover {
  border-color: var(--arg-accent);
  color: #fff;
}
/* Lives in the left zone of the controls row (far left, under the progress bar)
   — the mirror of the CC control in the right zone. */
.device-pill {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 8px 13px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.5);
  font: 600 12px var(--arg-body);
  color: var(--arg-dim);
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--arg-accent);
  box-shadow: 0 0 8px var(--arg-accent);
}
.center {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
}
.big-play {
  pointer-events: auto;
  width: 84px;
  height: 84px;
  border-radius: 50%;
  border: 1px solid var(--arg-line-3);
  background: rgba(20, 20, 19, 0.45);
  backdrop-filter: blur(4px);
  color: var(--arg-cream);
  font: 400 28px var(--arg-display);
  cursor: pointer;
}
.big-play:hover {
  background: rgba(201, 154, 78, 0.22);
  border-color: var(--arg-accent);
}
.prep {
  pointer-events: none;
}
.prep-card {
  text-align: center;
}
.prep-spinner {
  width: 46px;
  height: 46px;
  margin: 0 auto 18px;
  border-radius: 50%;
  border: 3px solid rgba(201, 154, 78, 0.25);
  border-top-color: var(--arg-accent);
  animation: argSpin 0.9s linear infinite;
}
.prep-text {
  font: 700 16px var(--arg-display);
}
.prep-sub {
  margin-top: 5px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-dim);
}
@keyframes argSpin {
  to {
    transform: rotate(360deg);
  }
}
.error {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 30px;
}
.error-card {
  max-width: 420px;
  text-align: center;
  padding: 32px;
  border-radius: var(--arg-r-xl);
  background: linear-gradient(160deg, #201d18, #161513);
  border: 1px solid var(--arg-line-2);
}
.error-eyebrow {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
.error-card p {
  margin: 14px 0 22px;
  font: 400 14px/1.6 var(--arg-body);
  color: var(--arg-soft);
}
.error-card button {
  padding: 12px 22px;
  border: 1px solid var(--arg-line-2);
  border-radius: var(--arg-r);
  background: transparent;
  color: var(--arg-cream);
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.error-card button:hover {
  border-color: var(--arg-accent);
}
.bottom {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 30px 40px;
  background: linear-gradient(transparent, var(--arg-ink) 70%);
  transition: opacity 0.3s ease;
}
.scrub {
  display: flex;
  align-items: center;
  gap: 14px;
  font: 600 12px var(--arg-body);
  color: var(--arg-soft-2);
}
.t {
  font-variant-numeric: tabular-nums;
}
.bar {
  position: relative;
  flex: 1;
  height: 5px;
  border-radius: 3px;
  background: rgba(234, 234, 229, 0.16);
  cursor: pointer;
}
.fill {
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  border-radius: 3px;
  background: var(--arg-accent);
}
.knob {
  position: absolute;
  top: 50%;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  background: var(--arg-cream);
  transform: translate(-50%, -50%);
  box-shadow: 0 0 0 4px rgba(201, 154, 78, 0.3);
}
.buttons {
  position: relative;
  margin-top: 20px;
  display: flex;
  align-items: center;
  gap: 18px;
}
/* Three zones: device pill (far left), transport controls (centered by the
   equal-flex sides), CC (far right). */
.btn-left,
.btn-right {
  flex: 1;
  display: flex;
  align-items: center;
}
.btn-right {
  justify-content: flex-end;
}
.btn-mid {
  display: flex;
  align-items: center;
  gap: 18px;
}
.ctrl {
  display: inline-flex;
  align-items: center;
  gap: 9px;
  padding: 11px 20px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.55);
  color: var(--arg-cream);
  cursor: pointer;
  font: 600 14px var(--arg-body);
}
.ctrl:hover {
  border-color: var(--arg-accent);
  color: #fff;
}
.ctrl .ic {
  font-size: 19px;
  line-height: 1;
  color: var(--arg-accent);
}
.ctrl .lbl {
  font: 600 14px var(--arg-body);
}
.ctrl.primary {
  /* Fixed width so swapping Play ⇄ Pause never resizes the button. */
  min-width: 138px;
  justify-content: center;
  padding: 13px 30px;
  background: var(--arg-accent);
  border-color: var(--arg-accent);
  color: var(--arg-bg);
}
/* CC drops the outer transport pill — just the "CC" badge, no surrounding
   border/background. */
.ctrl.icon-only {
  padding: 8px;
  gap: 0;
  border-color: transparent;
  background: transparent;
}
.ctrl.icon-only:hover {
  border-color: transparent;
  background: rgba(234, 234, 229, 0.06);
}
/* Paused → the play button breathes a brass glow, echoing the resume card. */
.ctrl.primary.glow {
  animation: playGlow 2.6s ease-in-out infinite;
}
@keyframes playGlow {
  0%,
  100% {
    box-shadow: 0 0 16px 1px rgba(201, 154, 78, 0.45);
  }
  50% {
    box-shadow: 0 0 30px 5px rgba(201, 154, 78, 0.72);
  }
}
.ctrl.primary .ic {
  color: var(--arg-bg);
  font-size: 17px;
}
.ctrl.primary:hover {
  background: var(--arg-accent-hi);
  color: var(--arg-bg);
}
/* Active CC keeps the same (borderless) outer as inactive — the inner badge
   fill is signal enough; no gold outline. */
.ctrl.on {
  border-color: transparent;
}
.ctrl.on .ic.cc {
  border-color: var(--arg-accent);
  background: var(--arg-accent);
  color: var(--arg-bg);
}
.ic.cc {
  font: 800 11px var(--arg-display);
  letter-spacing: 0.04em;
  padding: 2px 5px;
  border-radius: 4px;
  border: 1.5px solid var(--arg-accent);
  color: var(--arg-accent);
}
.cc-wrap {
  position: relative;
}
.cc-menu {
  position: absolute;
  bottom: calc(100% + 12px);
  right: 0;
  min-width: 248px;
  padding: 7px;
  border-radius: var(--arg-r-lg);
  /* Translucent so the media stays visible behind the picker. */
  background: rgba(18, 17, 15, 0.78);
  backdrop-filter: blur(16px) saturate(1.1);
  border: 1px solid var(--arg-line-2);
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.5);
  animation: argFade 0.16s ease;
}
.cc-head {
  padding: 6px 10px 8px;
  font: 700 10px var(--arg-display);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--arg-dim);
}
.cc-style-head {
  margin-top: 6px;
  border-top: 1px solid var(--arg-line-2);
  padding-top: 12px;
}
.cc-style-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 6px 10px;
}
.cc-style-label {
  font: 500 12.5px var(--arg-body);
  color: var(--arg-soft);
}
.cc-seg {
  display: flex;
  gap: 4px;
}
.cc-seg button {
  min-width: 34px;
  padding: 5px 9px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 600 11.5px var(--arg-body);
  cursor: pointer;
}
.cc-seg button.on {
  background: var(--arg-accent);
  border-color: var(--arg-accent);
  color: var(--arg-bg);
}
.cc-swatches {
  display: flex;
  gap: 7px;
}
.cc-swatch {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  border: 2px solid transparent;
  cursor: pointer;
}
.cc-swatch.on {
  border-color: var(--arg-accent);
  box-shadow: 0 0 0 2px rgba(0, 0, 0, 0.5) inset;
}
.cc-item {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 11px;
  border: none;
  border-radius: var(--arg-r);
  background: transparent;
  color: var(--arg-cream);
  font: 600 13.5px var(--arg-body);
  text-align: left;
  cursor: pointer;
}
.cc-item:hover {
  background: rgba(201, 154, 78, 0.12);
}
.cc-item.sel {
  background: var(--arg-accent-bg);
}
.cc-label {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.cc-src {
  font: 500 10.5px var(--arg-body);
  color: var(--arg-dim);
}
.cc-check {
  color: var(--arg-accent);
  font-size: 13px;
}
/* Up Next card: a compact, non-modal overlay in the bottom-right so the tail of
   the episode stays visible behind it. Sits above the controls' fade zone. */
.up-next {
  position: absolute;
  right: 30px;
  bottom: 130px;
  z-index: 4;
  animation: argFade 0.25s ease;
}
.up-next-card {
  width: 320px;
  padding: 18px 20px;
  border-radius: var(--arg-r-lg);
  background: rgba(18, 17, 15, 0.86);
  backdrop-filter: blur(16px) saturate(1.1);
  border: 1px solid rgba(201, 154, 78, 0.32);
  box-shadow: 0 18px 44px rgba(0, 0, 0, 0.5);
}
.up-next-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.up-next-eyebrow {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
.up-next-count {
  font: 600 12px var(--arg-body);
  color: var(--arg-dim);
  font-variant-numeric: tabular-nums;
}
.up-next-title {
  margin-top: 12px;
  font: 700 17px/1.3 var(--arg-display);
  color: var(--arg-cream);
}
.up-next-series {
  margin-top: 4px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-dim);
}
.up-next-actions {
  margin-top: 16px;
  display: flex;
  gap: 10px;
}
.up-next-play {
  flex: 1;
  padding: 11px;
  border: none;
  border-radius: var(--arg-r);
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 14px var(--arg-display);
  cursor: pointer;
}
.up-next-play:hover {
  background: var(--arg-accent-hi);
}
.up-next-cancel {
  padding: 11px 18px;
  border: 1px solid var(--arg-line-2);
  border-radius: var(--arg-r);
  background: transparent;
  color: var(--arg-soft-2);
  font: 600 13px var(--arg-body);
  cursor: pointer;
}
.up-next-cancel:hover {
  border-color: var(--arg-cream);
}
.resume-scrim {
  position: absolute;
  inset: 0;
  background: rgba(8, 8, 7, 0.72);
  backdrop-filter: blur(6px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 30px;
  animation: argFade 0.35s ease;
}
.resume-card {
  position: relative;
  width: 100%;
  max-width: 440px;
  padding: 38px 36px 32px;
  border-radius: var(--arg-r-xl);
  background: linear-gradient(160deg, #201d18, #161513);
  border: 1px solid rgba(201, 154, 78, 0.32);
  animation: argPulse 3.4s ease-in-out infinite;
}
.resume-eyebrow {
  display: flex;
  align-items: center;
  gap: 9px;
  font: 700 11px var(--arg-display);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
.resume-title {
  margin-top: 18px;
  font: 700 21px/1.25 var(--arg-display);
}
.resume-body {
  margin-top: 8px;
  font: 400 14px/1.55 var(--arg-body);
  color: #a8a89f;
}
.resume-stat {
  margin-top: 22px;
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  padding: 18px 20px;
  border-radius: var(--arg-r-lg);
  background: var(--arg-accent-bg);
  border: 1px solid rgba(201, 154, 78, 0.18);
}
.stat-label {
  font: 500 11px var(--arg-display);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: #8a8a82;
}
.stat-time {
  margin-top: 4px;
  font: 800 34px var(--arg-display);
  letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
}
.stat-right {
  text-align: right;
  font: 500 12px var(--arg-body);
  color: #8a8a82;
}
.stat-right span {
  color: var(--arg-accent);
}
.resume-primary {
  margin-top: 22px;
  width: 100%;
  padding: 15px;
  border: none;
  border-radius: var(--arg-r);
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 15px var(--arg-display);
  cursor: pointer;
}
.resume-primary:hover {
  background: var(--arg-accent-hi);
}
.resume-ghost {
  margin-top: 10px;
  width: 100%;
  padding: 13px;
  border: 1px solid var(--arg-line-2);
  border-radius: var(--arg-r);
  background: transparent;
  color: var(--arg-soft-2);
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.resume-ghost:hover {
  border-color: var(--arg-cream);
}
.resume-foot {
  margin-top: 18px;
  text-align: center;
  font: 500 11px var(--arg-body);
  color: var(--arg-faint-2);
}
</style>

<!-- ::cue lives on the native text-track overlay, which scoped styles can't
     reach — keep this block unscoped (manually namespaced to .player). -->
<style>
.player video::cue {
  font-size: 2.9vh; /* ~30% smaller than the browser default */
  line-height: 1.32;
  background: rgba(8, 8, 7, 0.62);
}
</style>
