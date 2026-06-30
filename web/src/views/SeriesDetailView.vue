<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '@/api/client'
import BackButton from '@/components/BackButton.vue'
import AddToVault from '@/components/AddToVault.vue'
import LabelEditor from '@/components/LabelEditor.vue'
import { posterStyle } from '@/lib/poster'
import { formatRuntime } from '@/lib/format'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type SeriesDetail = components['schemas']['SeriesDetail']
type Episode = SeriesDetail['seasons'][number]['episodes'][number]

const route = useRoute()
const router = useRouter()
const series = ref<SeriesDetail | null>(null)
const notFound = ref(false)
const activeSeason = ref(0)

const heroStyle = computed(() =>
  posterStyle(series.value?.backdropUrl ?? series.value?.posterUrl, series.value?.title ?? ''),
)
const season = computed(() => series.value?.seasons[activeSeason.value] ?? null)

const firstPlayable = computed(() => {
  for (const s of series.value?.seasons ?? []) {
    for (const e of s.episodes) if (e.mediaItemId) return e.mediaItemId
  }
  return null
})

const episodeCodeRe = /S\d{1,2}E\d{1,2}/i

// episodeName returns a real episode name only. The filename fallback is
// "<Show> S01E01" (carries the code) — until TMDB episode names land (ARGY-58)
// we show just E# + runtime rather than a cryptic code.
function episodeName(ep: Episode): string | null {
  if (!ep.title || episodeCodeRe.test(ep.title)) return null
  return ep.title
}

function epTimeLeft(ep: Episode): number {
  return Math.max(0, (ep.durationSeconds || 0) - (ep.positionSeconds || 0))
}

function epPercent(ep: Episode): number {
  if (!ep.durationSeconds || !ep.positionSeconds) return 0
  return Math.min(100, (ep.positionSeconds / ep.durationSeconds) * 100)
}

function epInProgress(ep: Episode): boolean {
  if (!ep.mediaItemId || ep.watched || (ep.positionSeconds ?? 0) <= 5) return false
  return !ep.durationSeconds || (ep.positionSeconds ?? 0) < ep.durationSeconds * 0.95
}

// A combined rip backs several episode numbers in one file (e.g. The Good Place
// "E1" is really EP1+EP2). Such episodes share a mediaItemId; we fold consecutive
// ones into a single row so the season reads "E1–2" instead of a false gap.
interface EpisodeRow {
  key: string
  episodes: Episode[]
  rep: Episode // representative — runtime/progress/play target (they share a file)
  mediaItemId: string | null | undefined
}

const seasonRows = computed<EpisodeRow[]>(() => {
  const rows: EpisodeRow[] = []
  for (const ep of season.value?.episodes ?? []) {
    const prev = rows[rows.length - 1]
    if (ep.mediaItemId && prev && prev.mediaItemId === ep.mediaItemId) {
      prev.episodes.push(ep)
    } else {
      rows.push({ key: ep.id, episodes: [ep], rep: ep, mediaItemId: ep.mediaItemId })
    }
  }
  return rows
})

function rowLabel(row: EpisodeRow): string {
  const nums = row.episodes.map((e) => e.episodeNumber)
  return nums.length > 1 ? `E${nums[0]}–${nums[nums.length - 1]}` : `E${nums[0]}`
}

function rowName(row: EpisodeRow): string | null {
  const names = row.episodes.map(episodeName).filter((n): n is string => !!n)
  return names.length ? names.join(' / ') : null
}

function rowStill(row: EpisodeRow): string | null {
  return row.episodes.find((e) => e.stillUrl)?.stillUrl ?? null
}

// First episode's synopsis represents the row; combined names already convey the span.
function rowOverview(row: EpisodeRow): string | null {
  return row.episodes.find((e) => e.overview)?.overview ?? null
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

// The season tab to open on: the one holding the resume episode (mapping its
// 1-indexed seasonNumber → the matching season's array index), or 0 when nothing
// is in progress so a fresh series still opens on Season 1.
const resumeSeasonIndex = computed(() => {
  const t = resumeTarget.value
  if (!t) return 0
  const i = series.value?.seasons.findIndex((s) => s.seasonNumber === t.seasonNumber) ?? -1
  return i >= 0 ? i : 0
})

const resumeLabel = computed(() => {
  const t = resumeTarget.value
  return t ? `Resume Season ${t.seasonNumber} Ep ${t.ep.episodeNumber}` : ''
})

function resumeSeries(): void {
  const id = resumeTarget.value?.ep.mediaItemId
  if (id) void router.push({ name: 'player', params: { id }, query: { resume: '1' } })
}

// Start Over: play the first episode from the beginning (skip the resume prompt).
function startOverSeries(): void {
  if (firstPlayable.value) {
    void router.push({ name: 'player', params: { id: firstPlayable.value }, query: { start: '1' } })
  }
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
    setPage('Not found')
    return
  }
  series.value = data
  // Open on the season of the in-progress/next-up episode, not always Season 1.
  activeSeason.value = resumeSeasonIndex.value
  setPage(data.title)
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
      <BackButton class="hero-back" fallback="library" />
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
            <button class="ghost" type="button" :disabled="!firstPlayable" @click="startOverSeries">
              Start Over
            </button>
          </template>
          <button v-else class="play" type="button" :disabled="!firstPlayable" @click="playFirst">
            <span>▶</span> Play
          </button>
          <AddToVault v-if="series" :series-id="series.id" />
        </div>
        <LabelEditor v-if="series" :series-id="series.id" :initial="series.labels ?? []" />
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
        v-for="row in seasonRows"
        :key="row.key"
        class="episode"
        type="button"
        :disabled="!row.mediaItemId"
        @click="playEpisode(row.mediaItemId)"
      >
        <div class="thumb" :style="posterStyle(rowStill(row), `${series.title}-${row.key}`)">
          <div v-if="!rowStill(row)" class="arg-hatch thumb-hatch" />
          <span class="glyph">▶</span>
        </div>
        <div class="ep-info">
          <div class="ep-line1">
            <span class="ep-tag">{{ rowLabel(row) }}</span>
            <span v-if="rowName(row)" class="ep-name">{{ rowName(row) }}</span>
            <span class="ep-dot">·</span>
            <span class="ep-len">{{
              row.mediaItemId ? formatRuntime(row.rep.durationSeconds) : 'No file linked'
            }}</span>
            <span v-if="row.episodes.length > 1" class="ep-combined">Combined</span>
            <span v-if="row.rep.watched" class="ep-flag">✓ Watched</span>
          </div>
          <p v-if="rowOverview(row)" class="ep-synopsis">{{ rowOverview(row) }}</p>
          <div v-if="epInProgress(row.rep)" class="ep-line2">
            <div class="ep-bar">
              <div class="ep-fill" :style="{ width: `${epPercent(row.rep)}%` }" />
            </div>
            <span class="ep-prog"
              >{{ Math.round(epPercent(row.rep)) }}% ·
              {{ formatRuntime(epTimeLeft(row.rep)) }} left</span
            >
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
  min-height: 360px;
}
.hatch {
  position: absolute;
  inset: 0;
}
.shade {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    0deg,
    #171717 4%,
    rgba(23, 23, 23, 0.5) 55%,
    rgba(23, 23, 23, 0.15) 100%
  );
}
/* Quadrant 1: top-left of the hero, aligned with the body's 40px inset. */
.hero-back {
  position: absolute;
  top: 50px;
  left: 40px;
  z-index: 3;
}
.body {
  position: relative;
  /* Extra top padding reserves room for the back button (top:50 + 40h) so the
     title always clears it even when the overview makes the content tall. */
  padding: 104px 40px 34px;
  min-height: 360px;
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
.ep-line1 {
  display: flex;
  align-items: baseline;
  gap: 10px;
  flex-wrap: wrap;
}
.ep-tag {
  font: 800 13px var(--arg-display);
  color: var(--arg-accent);
  letter-spacing: 0.04em;
}
.ep-name {
  font: 700 17px var(--arg-display);
  color: var(--arg-cream);
}
.ep-dot {
  color: var(--arg-faint);
}
.ep-len {
  font: 600 13.5px var(--arg-body);
  color: var(--arg-dim);
  font-variant-numeric: tabular-nums;
}
.ep-flag {
  font: 700 12px var(--arg-display);
  color: var(--arg-accent);
}
.ep-combined {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.04em;
  color: var(--arg-soft-2);
  border: 1px solid var(--arg-line-2);
  border-radius: 4px;
  padding: 1px 6px;
}
.ep-synopsis {
  margin: 7px 0 0;
  font: 400 13px/1.5 var(--arg-body);
  color: var(--arg-dim);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.ep-line2 {
  margin-top: 11px;
  display: flex;
  align-items: center;
  gap: 14px;
}
.ep-bar {
  flex: 1;
  height: 5px;
  border-radius: 3px;
  background: rgba(234, 234, 229, 0.16);
  overflow: hidden;
}
.ep-fill {
  height: 100%;
  border-radius: 3px;
  background: var(--arg-accent);
}
.ep-prog {
  flex: none;
  font: 600 12.5px var(--arg-body);
  color: var(--arg-soft-2);
  font-variant-numeric: tabular-nums;
}
.missing {
  padding: 80px 0;
  text-align: center;
  color: var(--arg-dim);
  font: 500 15px var(--arg-body);
}
</style>
