<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/api/client'
import { posterStyle } from '@/lib/poster'
import { formatRuntime, formatTitle } from '@/lib/format'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type SeriesDetail = components['schemas']['SeriesDetail']
type Episode = SeriesDetail['seasons'][number]['episodes'][number]

const route = useRoute()
const router = useRouter()
const series = ref<SeriesDetail | null>(null)
const notFound = ref(false)
const activeSeason = ref(0)

const heroStyle = computed(() => posterStyle(series.value?.posterUrl, series.value?.title ?? ''))
const season = computed(() => series.value?.seasons[activeSeason.value] ?? null)

const firstPlayable = computed(() => {
  for (const s of series.value?.seasons ?? []) {
    for (const e of s.episodes) if (e.mediaItemId) return e.mediaItemId
  }
  return null
})

function epPercent(ep: Episode): number {
  if (!ep.durationSeconds || !ep.positionSeconds) return 0
  return Math.min(100, (ep.positionSeconds / ep.durationSeconds) * 100)
}

function epInProgress(ep: Episode): boolean {
  if (!ep.mediaItemId || ep.watched || (ep.positionSeconds ?? 0) <= 5) return false
  return !ep.durationSeconds || (ep.positionSeconds ?? 0) < ep.durationSeconds * 0.95
}

// Playable episodes flattened in season/episode order, with their season number.
const playableEpisodes = computed(() =>
  (series.value?.seasons ?? []).flatMap((s) =>
    s.episodes.filter((e) => e.mediaItemId).map((ep) => ({ ep, seasonNumber: s.seasonNumber })),
  ),
)

// Resume target: the episode you're mid-way through, otherwise the next one
// after the last episode you touched (watched or partially watched).
const resumeTarget = computed(() => {
  const eps = playableEpisodes.value
  let lastTouched = -1
  eps.forEach((x, i) => {
    if (x.ep.watched || (x.ep.positionSeconds ?? 0) > 5) lastTouched = i
  })
  if (lastTouched < 0) return null
  const touched = eps[lastTouched]
  if (epInProgress(touched.ep)) return touched
  return eps[lastTouched + 1] ?? null
})

const resumeLabel = computed(() => {
  const t = resumeTarget.value
  return t ? `Resume Season ${t.seasonNumber} Ep ${t.ep.episodeNumber}` : ''
})

function resumeSeries(): void {
  const id = resumeTarget.value?.ep.mediaItemId
  if (id) void router.push({ name: 'player', params: { id } })
}

async function load(id: string): Promise<void> {
  notFound.value = false
  series.value = null
  activeSeason.value = 0
  const { data } = await api.GET('/api/v1/series/{seriesId}', {
    params: { path: { seriesId: id } },
  })
  if (!data) {
    notFound.value = true
    setPage('Not found', 'That series is no longer in the Manifest.')
    return
  }
  series.value = data
  setPage(data.title, `Series · ${data.seasons.length} season${data.seasons.length === 1 ? '' : 's'}`)
}

function playFirst(): void {
  if (firstPlayable.value) void router.push({ name: 'player', params: { id: firstPlayable.value } })
}

function playEpisode(mediaItemId: string | null | undefined): void {
  if (mediaItemId) void router.push({ name: 'player', params: { id: mediaItemId } })
}

onMounted(() => load(String(route.params.id)))
watch(
  () => route.params.id,
  (id) => id && load(String(id)),
)
</script>

<template>
  <div v-if="series">
    <section class="hero" :style="heroStyle">
      <div class="arg-hatch hatch" />
      <div class="shade" />
      <div class="body">
        <h1>{{ series.title }}</h1>
        <div class="meta">
          <span>{{ series.year ?? '—' }}</span>
          <span class="sep">•</span>
          <span>{{ series.seasons.length }} seasons</span>
          <span v-if="series.tags?.includes('anime')" class="sep">•</span>
          <span v-if="series.tags?.includes('anime')" class="kind">Anime</span>
        </div>
        <p v-if="series.overview" class="synopsis">{{ series.overview }}</p>
        <div class="actions">
          <template v-if="resumeTarget">
            <button class="play" type="button" @click="resumeSeries">
              <span>▶</span> {{ resumeLabel }}
            </button>
            <button class="ghost" type="button" :disabled="!firstPlayable" @click="playFirst">
              Start Over
            </button>
          </template>
          <button v-else class="play" type="button" :disabled="!firstPlayable" @click="playFirst">
            <span>▶</span> Play
          </button>
        </div>
      </div>
    </section>

    <div v-if="series.seasons.length" class="tabs">
      <button
        v-for="(s, i) in series.seasons"
        :key="s.id"
        class="tab"
        :class="{ on: i === activeSeason }"
        type="button"
        @click="activeSeason = i"
      >
        {{ s.title || `Season ${s.seasonNumber}` }}
      </button>
    </div>

    <div v-if="season" class="episodes">
      <button
        v-for="ep in season.episodes"
        :key="ep.id"
        class="episode"
        type="button"
        :disabled="!ep.mediaItemId"
        @click="playEpisode(ep.mediaItemId)"
      >
        <div class="thumb" :style="posterStyle(null, `${series.title}-${ep.id}`)">
          <div class="arg-hatch thumb-hatch" />
          <span class="glyph">▶</span>
        </div>
        <div class="ep-info">
          <div class="ep-head">
            <span class="ep-tag">E{{ ep.episodeNumber }}</span>
            <span class="ep-title">{{ ep.title ? formatTitle(ep.title) : `Episode ${ep.episodeNumber}` }}</span>
          </div>
          <div class="ep-meta">
            <span v-if="!ep.mediaItemId" class="ep-status">No file linked</span>
            <template v-else>
              <span class="ep-len">{{ formatRuntime(ep.durationSeconds) }}</span>
              <span v-if="ep.watched" class="ep-watched">✓ Watched</span>
              <span v-else-if="epInProgress(ep)" class="ep-left">
                {{ Math.round(epPercent(ep)) }}% · {{ formatRuntime((ep.durationSeconds || 0) - (ep.positionSeconds || 0)) }} left
              </span>
            </template>
          </div>
          <div v-if="epInProgress(ep)" class="ep-bar">
            <div class="ep-fill" :style="{ width: `${epPercent(ep)}%` }" />
          </div>
        </div>
      </button>
    </div>
  </div>

  <div v-else-if="notFound" class="missing">That series isn't in the Manifest.</div>
</template>

<style scoped>
.hero {
  position: relative;
  border-radius: var(--arg-r-xl);
  overflow: hidden;
  border: 1px solid var(--arg-line);
  min-height: 330px;
}
.hatch {
  position: absolute;
  inset: 0;
}
.shade {
  position: absolute;
  inset: 0;
  background: linear-gradient(0deg, #171717 4%, rgba(23, 23, 23, 0.5) 55%, rgba(23, 23, 23, 0.15) 100%);
}
.body {
  position: relative;
  padding: 44px 40px 34px;
  min-height: 330px;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
}
h1 {
  margin: 0;
  font: 800 40px/1.04 var(--arg-display);
  letter-spacing: -0.02em;
}
.meta {
  margin-top: 10px;
  display: flex;
  gap: 14px;
  align-items: center;
  font: 600 13px var(--arg-body);
  color: var(--arg-dim);
}
.sep {
  opacity: 0.4;
}
.kind {
  color: var(--arg-accent);
}
.synopsis {
  margin-top: 16px;
  max-width: 620px;
  font: 400 14.5px/1.6 var(--arg-body);
  color: #c4c4bc;
}
.actions {
  margin-top: 22px;
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}
.play {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 13px 26px;
  border: none;
  border-radius: var(--arg-r);
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 15px var(--arg-display);
  cursor: pointer;
}
.play:hover {
  background: var(--arg-accent-hi);
}
.play:disabled {
  opacity: 0.5;
  cursor: default;
}
.ghost {
  padding: 13px 22px;
  border: 1px solid var(--arg-line-2);
  border-radius: var(--arg-r);
  background: rgba(20, 20, 19, 0.4);
  color: var(--arg-cream);
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.ghost:hover {
  border-color: var(--arg-accent);
}
.ghost:disabled {
  opacity: 0.5;
  cursor: default;
}
.tabs {
  margin-top: 22px;
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.tab {
  padding: 9px 18px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 700 13px var(--arg-display);
  cursor: pointer;
}
.tab.on {
  background: var(--arg-accent-bg-2);
  border-color: rgba(201, 154, 78, 0.5);
  color: var(--arg-accent);
}
.episodes {
  margin-top: 22px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.episode {
  display: flex;
  gap: 18px;
  padding: 14px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line);
  background: var(--arg-panel);
  cursor: pointer;
  align-items: center;
  text-align: left;
}
.episode:hover {
  border-color: rgba(201, 154, 78, 0.4);
  background: var(--arg-panel-hi);
}
.episode:disabled {
  opacity: 0.55;
  cursor: default;
}
.thumb {
  position: relative;
  flex: none;
  width: 150px;
  aspect-ratio: 16 / 9;
  border-radius: var(--arg-r-sm);
  overflow: hidden;
  border: 1px solid var(--arg-line);
}
.thumb-hatch {
  position: absolute;
  inset: 0;
}
.glyph {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgba(234, 234, 229, 0.6);
  font: 400 20px var(--arg-display);
}
.ep-info {
  flex: 1;
  min-width: 0;
}
.ep-head {
  display: flex;
  align-items: baseline;
  gap: 10px;
}
.ep-tag {
  font: 700 11px var(--arg-display);
  color: var(--arg-accent);
  letter-spacing: 0.06em;
}
.ep-title {
  font: 700 15px var(--arg-display);
}
.ep-meta {
  margin-top: 6px;
  display: flex;
  align-items: center;
  gap: 10px;
  font: 600 11.5px var(--arg-body);
}
.ep-status {
  color: var(--arg-faint);
}
.ep-len {
  color: var(--arg-dim);
  font-variant-numeric: tabular-nums;
}
.ep-watched {
  color: var(--arg-accent);
}
.ep-left {
  color: var(--arg-soft-2);
  font-variant-numeric: tabular-nums;
}
.ep-bar {
  margin-top: 9px;
  height: 4px;
  border-radius: 2px;
  background: rgba(234, 234, 229, 0.16);
  overflow: hidden;
}
.ep-fill {
  height: 100%;
  border-radius: 2px;
  background: var(--arg-accent);
}
.missing {
  padding: 80px 0;
  text-align: center;
  color: var(--arg-dim);
  font: 500 15px var(--arg-body);
}
</style>
