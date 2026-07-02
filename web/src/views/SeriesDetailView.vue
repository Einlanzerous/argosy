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
import { setWatched, setSeasonWatched, setSeriesWatched } from '@/lib/playback'
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

// Watched-state affordances (ARGY-109). Toggling flips the flag server-side (the
// backend keeps any resume position) and mirrors it onto the local episode
// objects so the row updates without a refetch. A combined rip backs several
// episode rows through one file, so we flip every episode in the row together.
const busyItems = ref<Set<string>>(new Set())
const seasonBusy = ref(false)

function isRowBusy(row: EpisodeRow): boolean {
  return !!row.mediaItemId && busyItems.value.has(row.mediaItemId)
}

async function toggleEpisodeWatched(row: EpisodeRow): Promise<void> {
  const id = row.mediaItemId
  if (!id || busyItems.value.has(id)) return
  const next = !row.rep.watched
  busyItems.value = new Set(busyItems.value).add(id)
  try {
    await setWatched(id, next)
    for (const e of row.episodes) e.watched = next
  } finally {
    const s = new Set(busyItems.value)
    s.delete(id)
    busyItems.value = s
  }
}

const seasonPlayable = computed(() => (season.value?.episodes ?? []).filter((e) => e.mediaItemId))
const seasonWatchedCount = computed(() => seasonPlayable.value.filter((e) => e.watched).length)
const allSeasonWatched = computed(
  () => seasonPlayable.value.length > 0 && seasonWatchedCount.value === seasonPlayable.value.length,
)

async function markSeason(watched: boolean): Promise<void> {
  const s = season.value
  if (!s || seasonBusy.value || !seasonPlayable.value.length) return
  seasonBusy.value = true
  try {
    await setSeasonWatched(s.id, watched)
    for (const e of s.episodes) if (e.mediaItemId) e.watched = watched
  } finally {
    seasonBusy.value = false
  }
}

// Series-level bulk (ARGY-109) — the "mark the whole show" shortcut, offered
// alongside the per-season control on multi-season series.
const seriesBusy = ref(false)
const seriesPlayable = computed(() =>
  (series.value?.seasons ?? []).flatMap((s) => s.episodes).filter((e) => e.mediaItemId),
)
const allSeriesWatched = computed(
  () => seriesPlayable.value.length > 0 && seriesPlayable.value.every((e) => e.watched),
)

async function markSeries(watched: boolean): Promise<void> {
  const s = series.value
  if (!s || seriesBusy.value || !seriesPlayable.value.length) return
  seriesBusy.value = true
  try {
    await setSeriesWatched(s.id, watched)
    for (const se of s.seasons) for (const e of se.episodes) if (e.mediaItemId) e.watched = watched
  } finally {
    seriesBusy.value = false
  }
}

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

// Per-episode provider rating (⭐), when TMDB has one — first rated episode in the
// row represents it. Returns null so unrated rows omit the badge (ARGY-118).
function rowRating(row: EpisodeRow): number | null {
  return row.episodes.find((e) => e.rating != null)?.rating ?? null
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
        <p v-if="series.cast?.length" class="cast">
          <span class="cast-label">Cast</span>{{ series.cast.join(', ') }}
        </p>
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
      <div v-for="row in seasonRows" :key="row.key" class="episode-row">
        <button
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
              <span v-if="rowRating(row) != null" class="ep-rating"
                >★ {{ rowRating(row)!.toFixed(1) }}</span
              >
              <span v-if="rowName(row)" class="ep-name">{{ rowName(row) }}</span>
              <span class="ep-dot">·</span>
              <span class="ep-len">{{
                row.mediaItemId ? formatRuntime(row.rep.durationSeconds) : 'No file linked'
              }}</span>
              <span v-if="row.episodes.length > 1" class="ep-combined">Combined</span>
            </div>
            <p v-if="rowOverview(row)" class="ep-synopsis">{{ rowOverview(row) }}</p>
            <!-- Always rendered so an in-progress row (with its bar) is the same
                 height as a not-started one — only the contents are conditional. -->
            <div class="ep-line2">
              <template v-if="epInProgress(row.rep)">
                <div class="ep-bar">
                  <div class="ep-fill" :style="{ width: `${epPercent(row.rep)}%` }" />
                </div>
                <span class="ep-prog"
                  >{{ Math.round(epPercent(row.rep)) }}% ·
                  {{ formatRuntime(epTimeLeft(row.rep)) }} left</span
                >
              </template>
            </div>
          </div>
        </button>
        <button
          v-if="row.mediaItemId"
          class="ep-watch"
          :class="{ on: row.rep.watched }"
          type="button"
          :disabled="isRowBusy(row)"
          :aria-pressed="!!row.rep.watched"
          :title="row.rep.watched ? 'Mark unwatched' : 'Mark watched'"
          @click="toggleEpisodeWatched(row)"
        >
          ✓
        </button>
      </div>
      <!-- Bulk controls live under the list so they don't wedge empty space
           between the season tabs and the episodes (ARGY-109). -->
      <div v-if="seasonPlayable.length" class="season-tools">
        <span class="season-progress"
          >{{ seasonWatchedCount }}/{{ seasonPlayable.length }} watched</span
        >
        <button
          v-if="series.seasons.length > 1"
          class="season-mark"
          type="button"
          :disabled="seriesBusy"
          @click="markSeries(!allSeriesWatched)"
        >
          {{ allSeriesWatched ? 'Mark series unwatched' : 'Mark series watched' }}
        </button>
        <button
          class="season-mark"
          type="button"
          :disabled="seasonBusy"
          @click="markSeason(!allSeasonWatched)"
        >
          {{ allSeasonWatched ? 'Mark season unwatched' : 'Mark season watched' }}
        </button>
      </div>
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
  min-height: 605px;
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
  min-height: 605px;
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
.cast {
  margin-top: 14px;
  max-width: 620px;
  font: 400 13.5px/1.6 var(--arg-body);
  color: var(--arg-soft-2);
}
.cast-label {
  margin-right: 10px;
  font: 700 11px var(--arg-display);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--arg-dim);
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
.season-tools {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 14px;
  /* Footer under the episode list — a hairline separates it from the last row. */
  margin-top: 4px;
  padding-top: 14px;
  border-top: 1px solid var(--arg-line);
}
.season-progress {
  font: 600 12.5px var(--arg-body);
  color: var(--arg-dim);
  font-variant-numeric: tabular-nums;
}
.season-mark {
  padding: 7px 14px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 700 12px var(--arg-display);
  cursor: pointer;
}
.season-mark:hover:not(:disabled) {
  border-color: var(--arg-accent);
  color: var(--arg-accent);
}
.season-mark:disabled {
  opacity: 0.5;
  cursor: default;
}
.episode-row {
  position: relative;
}
.episode {
  width: 100%;
  box-sizing: border-box;
  display: flex;
  gap: 18px;
  /* Extra right padding reserves room for the watched toggle in the corner. */
  padding: 14px 56px 14px 14px;
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
.ep-rating {
  font: 700 13px var(--arg-body);
  color: var(--arg-accent);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
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
  /* Reserve the progress row's height even when empty so in-progress and
     not-started rows are always the same size (ARGY-109). */
  min-height: 16px;
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
/* Watched toggle — a small rectangular check pill in the row's top-right corner,
   right-justified past the line-1 metadata. Sibling of the play button (not
   nested) so both stay valid, independently clickable buttons. */
.ep-watch {
  position: absolute;
  top: 12px;
  right: 12px;
  z-index: 2;
  height: 22px;
  padding: 0 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 5px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.55);
  color: var(--arg-faint);
  font: 700 13px var(--arg-display);
  line-height: 1;
  cursor: pointer;
}
.ep-watch:hover:not(:disabled) {
  border-color: var(--arg-accent);
  color: var(--arg-accent);
}
.ep-watch.on {
  border-color: var(--arg-accent);
  background: var(--arg-accent);
  color: var(--arg-bg);
}
.ep-watch:disabled {
  opacity: 0.5;
  cursor: default;
}
.missing {
  padding: 80px 0;
  text-align: center;
  color: var(--arg-dim);
  font: 500 15px var(--arg-body);
}
/* Keep the enlarged hero from dominating narrow viewports. */
@media (max-width: 720px) {
  .hero,
  .body {
    min-height: 380px;
  }
}
</style>
