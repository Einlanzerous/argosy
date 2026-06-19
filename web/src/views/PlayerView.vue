<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Hls from 'hls.js'
import { api, getToken } from '@/api/client'
import { posterStyle } from '@/lib/poster'
import { formatClock } from '@/lib/format'
import {
  getPlaybackInfo,
  getProgress,
  reportProgress,
  setWatched,
  startTranscode,
  stopTranscode,
  streamUrl,
} from '@/lib/playback'
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
const error = ref('')
const resumeOpen = ref(false)
const resumeFrom = ref(0)

let hls: Hls | null = null
let heartbeat: ReturnType<typeof setInterval> | null = null
let transcodeSessionId = ''
const starting = ref(false)

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

  const el = video.value
  if (!el) return

  // Direct play when the browser can decode the file; otherwise fall back to a
  // server-side HLS transcode (The Helm).
  if (playback && !playback.directPlay) {
    const ok = await attachTranscode(el)
    if (!ok) return
  } else {
    attachSource(el, streamUrl(itemId))
  }
  bindVideo(el)

  // Resume prompt when there's a meaningful saved position.
  if (progress && !progress.watched && progress.positionSeconds > 5) {
    resumeFrom.value = progress.positionSeconds
    resumeOpen.value = true
  } else {
    void el.play().catch(() => {})
  }
})

// attachTranscode starts a server-side transcode, waits for the master playlist
// to warm up, then feeds it to hls.js (with the per-device token on every
// request). Returns false and sets an error on failure.
async function attachTranscode(el: HTMLVideoElement): Promise<boolean> {
  starting.value = true
  try {
    const sess = await startTranscode(itemId).catch(() => null)
    if (!sess) {
      error.value = "Couldn't start transcoding this title. The server may be at capacity."
      return false
    }
    transcodeSessionId = sess.id
    if (!(await waitForPlaylist(sess.playlistUrl))) {
      error.value = 'The transcoder is taking too long to start. Please try again.'
      return false
    }
    if (Hls.isSupported()) {
      hls = new Hls({
        xhrSetup: (xhr) => {
          const t = getToken()
          if (t) xhr.setRequestHeader('Authorization', `Bearer ${t}`)
        },
      })
      hls.loadSource(sess.playlistUrl)
      hls.attachMedia(el)
      hls.on(Hls.Events.ERROR, (_e, data) => {
        if (data.fatal) error.value = 'This stream could not be played.'
      })
    } else {
      // Native-HLS browsers (iOS Safari) can't set an Authorization header on a
      // bare <video> src; token-in-URL support is a follow-up.
      el.src = sess.playlistUrl
    }
    return true
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
  if (hls) hls.destroy()
  if (transcodeSessionId) void stopTranscode(transcodeSessionId).catch(() => {})
  const el = video.value
  if (el) {
    el.pause()
    el.removeAttribute('src')
    el.load()
  }
})

// hls.js for HLS sources (Phase 3 transcode), native element for direct play.
function attachSource(el: HTMLVideoElement, url: string): void {
  if (url.includes('.m3u8') && Hls.isSupported()) {
    hls = new Hls()
    hls.loadSource(url)
    hls.attachMedia(el)
    hls.on(Hls.Events.ERROR, (_e, data) => {
      if (data.fatal) error.value = 'This stream could not be played.'
    })
  } else {
    el.src = url
  }
}

function bindVideo(el: HTMLVideoElement): void {
  el.addEventListener('loadedmetadata', () => {
    duration.value = el.duration || item.value?.durationSeconds || 0
  })
  el.addEventListener('timeupdate', () => {
    position.value = el.currentTime
  })
  el.addEventListener('play', () => {
    playing.value = true
  })
  el.addEventListener('pause', () => {
    playing.value = false
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
    if (!el.paused && el.currentTime > 0) flush()
  }, 10000)
}

function flush(): void {
  const el = video.value
  if (el && el.currentTime > 0) {
    void reportProgress(itemId, el.currentTime, el.duration || undefined).catch(() => {})
  }
}

function togglePlay(): void {
  const el = video.value
  if (!el) return
  if (el.paused) void el.play().catch(() => {})
  else el.pause()
}

function seek(e: MouseEvent): void {
  const el = video.value
  if (!el || !duration.value) return
  const bar = e.currentTarget as HTMLElement
  const rect = bar.getBoundingClientRect()
  el.currentTime = ((e.clientX - rect.left) / rect.width) * duration.value
}

function skip(delta: number): void {
  const el = video.value
  if (el) el.currentTime = Math.min(duration.value, Math.max(0, el.currentTime + delta))
}

function fullscreen(): void {
  const el = video.value?.closest('.player') as HTMLElement | null
  if (el?.requestFullscreen) void el.requestFullscreen().catch(() => {})
}

function resume(): void {
  const el = video.value
  if (el) {
    el.currentTime = resumeFrom.value
    void el.play().catch(() => {})
  }
  resumeOpen.value = false
}

function startOver(): void {
  const el = video.value
  if (el) {
    el.currentTime = 0
    void el.play().catch(() => {})
  }
  resumeOpen.value = false
}

function goBack(): void {
  if (window.history.length > 1) router.back()
  else void router.push({ name: 'home' })
}

function onKey(e: KeyboardEvent): void {
  if (resumeOpen.value) return
  if (e.key === ' ') {
    e.preventDefault()
    togglePlay()
  } else if (e.key === 'ArrowLeft') skip(-10)
  else if (e.key === 'ArrowRight') skip(10)
  else if (e.key === 'f') fullscreen()
  else if (e.key === 'Escape') goBack()
}
onMounted(() => window.addEventListener('keydown', onKey))
onBeforeUnmount(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <div class="player">
    <div class="backdrop" :style="backdrop" />
    <div class="arg-hatch backdrop-hatch" />
    <video ref="video" class="video" playsinline @click="togglePlay" />
    <div class="vignette" />

    <!-- top chrome -->
    <div class="top">
      <div class="top-left">
        <button class="back" type="button" @click="goBack">‹</button>
        <div>
          <div class="title">{{ item?.title ?? 'Loading…' }}</div>
          <div class="sub">{{ item?.year ?? '' }}</div>
        </div>
      </div>
      <div class="device-pill">
        <span class="dot" /> Playing on {{ session.deviceName || 'this device' }}
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
    <div v-if="!playing && !error && !starting" class="center">
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
    <div class="bottom">
      <div class="scrub">
        <span class="t">{{ formatClock(position) }}</span>
        <div class="bar" @click="seek">
          <div class="fill" :style="{ width: `${pct}%` }" />
          <div class="knob" :style="{ left: `${pct}%` }" />
        </div>
        <span class="t">{{ formatClock(duration) }}</span>
      </div>
      <div class="buttons">
        <button type="button" @click="skip(-10)">⟲ 10</button>
        <button type="button" @click="togglePlay">{{ playing ? '❚❚ Pause' : '▶ Play' }}</button>
        <button type="button" @click="skip(10)">10 ⟳</button>
        <button type="button" @click="fullscreen">⤢ Fullscreen</button>
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
  margin-top: 18px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 26px;
}
.buttons button {
  background: none;
  border: none;
  color: var(--arg-soft-2);
  cursor: pointer;
  font: 500 13px var(--arg-body);
}
.buttons button:hover {
  color: var(--arg-cream);
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
