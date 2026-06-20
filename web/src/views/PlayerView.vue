<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Hls from 'hls.js'
import { api, getToken } from '@/api/client'
import { posterStyle } from '@/lib/poster'
import { formatClock, formatTitle } from '@/lib/format'
import {
  getPlaybackInfo,
  getProgress,
  listSubtitles,
  reportProgress,
  setWatched,
  startTranscode,
  stopTranscode,
  streamUrl,
  subtitleUrl,
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
const backdrop = computed(() => posterStyle(item.value?.posterUrl, item.value?.title ?? ''))

onMounted(async () => {
  const [{ data }, progress, playback] = await Promise.all([
    api.GET('/api/v1/items/{itemId}', { params: { path: { itemId } } }),
    getProgress(itemId).catch(() => null),
    getPlaybackInfo(itemId).catch(() => null),
  ])
  item.value = data ?? null

  // Subtitle tracks load in the background; an OpenSubtitles search can take a
  // moment and shouldn't hold up playback.
  void listSubtitles(itemId)
    .then((t) => {
      subtitleTracks.value = t
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
// across transcode restarts via reapplySubtitle.
async function selectSubtitle(trackId: string | null): Promise<void> {
  subMenuOpen.value = false
  activeSubtitle.value = trackId
  removeSubtitleEl()
  if (trackId) await applySubtitle(trackId)
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
        <button
          class="icon-btn"
          type="button"
          :title="isFullscreen ? 'Exit fullscreen' : 'Fullscreen'"
          @click="fullscreen"
        >
          {{ isFullscreen ? '▢' : '⛶' }}
        </button>
        <span v-if="quality" class="quality">{{ quality }}</span>
        <div class="device-pill">
          <span class="dot" /> Playing on {{ session.deviceName || 'this device' }}
        </div>
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
          </div>
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
  padding: 6px 11px;
  border-radius: 7px;
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
.device-pill {
  display: flex;
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
  justify-content: center;
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
.ctrl.icon-only {
  padding: 11px 14px;
  gap: 0;
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
.ctrl.on {
  border-color: var(--arg-accent);
}
.ctrl.on .ic.cc {
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
  position: absolute;
  right: 0;
  top: 50%;
  transform: translateY(-50%);
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
