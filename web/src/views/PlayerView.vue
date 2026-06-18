<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/api/client'
import { posterStyle } from '@/lib/poster'
import { formatClock } from '@/lib/format'
import { useSessionStore } from '@/stores/session'
import type { components } from '@/api/schema'

type MovieDetail = components['schemas']['MediaItemDetail']

const route = useRoute()
const router = useRouter()
const session = useSessionStore()

const item = ref<MovieDetail | null>(null)
const playing = ref(false)
const position = ref(0)
const resumeOpen = ref(false)
const resumeFrom = ref<number | null>(null)
const resumeFromDevice = ref('another device')

const duration = computed(() => item.value?.durationSeconds ?? 0)
const pct = computed(() => (duration.value ? (position.value / duration.value) * 100 : 0))
const remaining = computed(() => Math.max(0, duration.value - position.value))

const backdrop = computed(() => posterStyle(item.value?.posterUrl, item.value?.title ?? ''))

onMounted(async () => {
  const { data } = await api.GET('/api/v1/items/{itemId}', {
    params: { path: { itemId: String(route.params.id) } },
  })
  item.value = data ?? null

  // Cross-device resume: in production this resolves from the shared play_state
  // (lands with Phase 3). A ?resume=<seconds> query lets the prompt be previewed
  // and is honoured here so a future "Resume" deep-link works unchanged.
  const q = route.query.resume
  if (typeof q === 'string' && Number.isFinite(Number(q))) {
    resumeFrom.value = Number(q)
    if (typeof route.query.from === 'string') resumeFromDevice.value = route.query.from
    resumeOpen.value = true
  }
})

function resume(): void {
  if (resumeFrom.value != null) position.value = resumeFrom.value
  resumeOpen.value = false
  playing.value = true
}

function startOver(): void {
  position.value = 0
  resumeOpen.value = false
  playing.value = true
}

function goBack(): void {
  if (window.history.length > 1) router.back()
  else void router.push({ name: 'home' })
}
</script>

<template>
  <div class="player">
    <div class="backdrop" :style="backdrop" />
    <div class="arg-hatch backdrop-hatch" />
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

    <!-- center -->
    <div class="center">
      <button class="big-play" type="button" @click="playing = !playing">
        {{ playing ? '❚❚' : '▶' }}
      </button>
    </div>

    <!-- bottom controls -->
    <div class="bottom">
      <div class="scrub">
        <span class="t">{{ formatClock(position) }}</span>
        <div class="bar">
          <div class="fill" :style="{ width: `${pct}%` }" />
          <div class="knob" :style="{ left: `${pct}%` }" />
        </div>
        <span class="t">{{ formatClock(duration) }}</span>
      </div>
      <div class="buttons">
        <button type="button">⟲ 10</button>
        <button type="button">10 ⟳</button>
        <button type="button">CC</button>
        <button type="button">⤢ Fullscreen</button>
      </div>
      <p class="note">Streaming is wired up in a later phase — this is the playback surface.</p>
    </div>

    <!-- ★ signature: cross-device resume prompt -->
    <div v-if="resumeOpen" class="resume-scrim">
      <div class="resume-card">
        <div class="resume-eyebrow"><span>⇄</span> Cross-device resume</div>
        <div class="resume-title">Pick up where you left off?</div>
        <div class="resume-body">
          You were watching <strong>{{ item?.title }}</strong> on your
          <strong>{{ resumeFromDevice }}</strong
          >.
        </div>
        <div class="resume-stat">
          <div>
            <div class="stat-label">Left off at</div>
            <div class="stat-time">{{ formatClock(resumeFrom ?? 0) }}</div>
          </div>
          <div class="stat-right">
            moments ago<br /><span>{{ formatClock(remaining) }} remaining</span>
          </div>
        </div>
        <button class="resume-primary" type="button" @click="resume">
          Resume from {{ formatClock(resumeFrom ?? 0) }}
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
  opacity: 0.5;
}
.backdrop-hatch {
  position: absolute;
  inset: 0;
  opacity: 0.5;
}
.vignette {
  position: absolute;
  inset: 0;
  background: radial-gradient(
    80% 60% at 50% 42%,
    rgba(0, 0, 0, 0) 0%,
    rgba(8, 8, 7, 0.55) 70%,
    var(--arg-ink) 100%
  );
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
}
.big-play {
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
.note {
  margin: 16px 0 0;
  text-align: center;
  font: 500 11px var(--arg-body);
  color: var(--arg-faint-2);
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
