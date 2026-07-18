<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import type { LocationQueryRaw, RouteLocationRaw } from 'vue-router'
import PosterCard from '@/components/PosterCard.vue'
import { posterStyle } from '@/lib/poster'
import { openSearch } from '@/lib/ui'
import {
  getLibraries,
  getMovies,
  getSeries,
  GENRES,
  type BrowseFilter,
  type MovieSort,
  type SeriesSort,
  type WatchedState,
} from '@/lib/manifest'
import { setPage } from '@/lib/page'

type Card = {
  id: string
  title: string
  subtitle?: string
  kind: string
  genre?: string
  rating?: number
  posterUrl?: string | null
  backdropUrl?: string | null
  to: RouteLocationRaw
}

const SORTS: { key: MovieSort; label: string }[] = [
  { key: 'added', label: 'Recently Added' },
  { key: 'title', label: 'Title' },
  { key: 'year', label: 'Year' },
  { key: 'rating', label: 'Rating' },
]
const WATCHED: { key: WatchedState; label: string }[] = [
  { key: 'unwatched', label: 'Unwatched' },
  { key: 'in_progress', label: 'In progress' },
  { key: 'watched', label: 'Watched' },
]

type Scope = 'all' | 'movies' | 'series'
const KINDS: { key: Scope; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'movies', label: 'Movies' },
  { key: 'series', label: 'Shows' },
]

const ALLOWED_SORT = ['title', 'added', 'year', 'rating']
const ALLOWED_WATCHED = ['watched', 'unwatched', 'in_progress']

const route = useRoute()
const router = useRouter()
const cards = ref<Card[]>([])
const loading = ref(true)

function asArray(v: unknown): string[] {
  if (Array.isArray(v)) return v.filter((x): x is string => typeof x === 'string')
  if (typeof v === 'string' && v) return [v]
  return []
}
function num(v: unknown): number | undefined {
  const n = Number(v)
  return typeof v === 'string' && v !== '' && !Number.isNaN(n) ? n : undefined
}

// All filter/sort state lives in the URL query so views are bookmarkable and
// shareable; these computeds decode it and the chips/inputs write it back.
const scope = computed<Scope>(() => {
  const k = route.query.kind
  if (k === 'movies') return 'movies'
  if (k === 'series' || k === 'shows') return 'series'
  return 'all'
})
const sort = computed<MovieSort>(() => {
  const s = route.query.sort
  return typeof s === 'string' && ALLOWED_SORT.includes(s) ? (s as MovieSort) : 'added'
})
const genres = computed(() => asArray(route.query.genre))
const watched = computed<WatchedState | undefined>(() => {
  const w = route.query.watched
  return typeof w === 'string' && ALLOWED_WATCHED.includes(w) ? (w as WatchedState) : undefined
})
const ratingMin = computed(() => num(route.query.rating_min))
const yearFrom = computed(() => num(route.query.year_from))
const yearTo = computed(() => num(route.query.year_to))

const hasFilters = computed(
  () =>
    genres.value.length > 0 ||
    !!watched.value ||
    !!ratingMin.value ||
    !!yearFrom.value ||
    !!yearTo.value,
)

// The advanced filter panel is collapsed by default (it's tall); the toggle shows
// how many facets are active so a collapsed panel still signals an active filter.
const panelOpen = ref(false)
const activeCount = computed(
  () =>
    genres.value.length +
    (watched.value ? 1 : 0) +
    (ratingMin.value ? 1 : 0) +
    (yearFrom.value || yearTo.value ? 1 : 0),
)
// Live label for the rating slider while dragging (committed on change).
const ratingLabel = ref(0)
watch(ratingMin, (v) => (ratingLabel.value = v ?? 0), { immediate: true })

// patch merges a change into the query and drops emptied keys.
function patch(next: Record<string, unknown>): void {
  const q: Record<string, unknown> = { ...route.query, ...next }
  for (const k of Object.keys(q)) {
    const v = q[k]
    if (v === undefined || v === '' || v === null || (Array.isArray(v) && v.length === 0))
      delete q[k]
  }
  void router.replace({ name: 'library', query: q as LocationQueryRaw })
}

function setKind(k: Scope): void {
  patch({ kind: k === 'all' ? undefined : k })
}
function setSort(s: MovieSort): void {
  patch({ sort: s })
}
function toggleGenre(g: string): void {
  const cur = genres.value
  patch({ genre: cur.includes(g) ? cur.filter((x) => x !== g) : [...cur, g] })
}
function setWatched(w: WatchedState): void {
  patch({ watched: watched.value === w ? undefined : w })
}
function setRating(r: number): void {
  patch({ rating_min: r > 0 ? r : undefined })
}
function setYear(which: 'year_from' | 'year_to', e: Event): void {
  patch({ [which]: (e.target as HTMLInputElement).value || undefined })
}
function clearFilters(): void {
  void router.replace({
    name: 'library',
    query: scope.value === 'all' ? {} : { kind: scope.value },
  })
}

const libTitle = computed(() =>
  scope.value === 'movies' ? 'Movies' : scope.value === 'series' ? 'Shows' : 'All Titles',
)
const backdropStyle = computed(() =>
  posterStyle(cards.value[0]?.backdropUrl ?? cards.value[0]?.posterUrl, libTitle.value),
)

async function load(): Promise<void> {
  loading.value = true
  const f: BrowseFilter = {
    genres: genres.value,
    ratingMin: ratingMin.value,
    watched: watched.value,
    yearFrom: yearFrom.value,
    yearTo: yearTo.value,
  }
  const libs = await getLibraries()
  const out: Card[] = []
  if (scope.value !== 'series') {
    const movies = await getMovies({ sort: sort.value, ...f }, libs)
    out.push(
      ...movies.map((m) => ({
        id: m.id,
        title: m.title,
        subtitle: m.year ? String(m.year) : undefined,
        kind: m.kind,
        genre: m.genres?.[0],
        rating: m.rating ?? undefined,
        posterUrl: m.posterUrl,
        backdropUrl: m.backdropUrl,
        to: { name: 'movie', params: { id: m.id } } as RouteLocationRaw,
      })),
    )
  }
  if (scope.value !== 'movies') {
    // Series have no "added" sort; fall back to title for it.
    const seriesSort: SeriesSort =
      sort.value === 'year' || sort.value === 'rating' ? sort.value : 'title'
    const series = await getSeries({ sort: seriesSort, ...f }, libs)
    out.push(
      ...series.map((s) => ({
        id: s.id,
        title: s.title,
        subtitle: s.year ? String(s.year) : undefined,
        kind: 'Series',
        genre: s.genres?.[0],
        rating: s.rating ?? undefined,
        posterUrl: s.posterUrl,
        backdropUrl: s.backdropUrl,
        to: { name: 'series', params: { id: s.id } } as RouteLocationRaw,
      })),
    )
  }
  cards.value = out
  loading.value = false
}

// Any change to the scope/sort/filter query reloads (and retitles) the view.
watch(
  () => route.fullPath,
  () => {
    setPage(libTitle.value)
    void load()
  },
  { immediate: true },
)
</script>

<template>
  <div class="library">
    <div class="backdrop" :style="backdropStyle" />
    <div class="backdrop-fade" />

    <div class="content">
      <header class="head">
        <div class="title-block">
          <div class="eyebrow">The Manifest</div>
          <h1>{{ libTitle }}</h1>
          <div class="count">{{ cards.length }} titles in the hold</div>
        </div>
        <button class="search" type="button" @click="openSearch">
          <span>⌕</span> Search the Manifest…
        </button>
      </header>

      <div class="controls">
        <div class="kinds">
          <button
            v-for="k in KINDS"
            :key="k.key"
            class="kind"
            :class="{ on: scope === k.key }"
            type="button"
            @click="setKind(k.key)"
          >
            {{ k.label }}
          </button>
        </div>
        <div class="sorts">
          <span class="sort-label">Sort</span>
          <button
            v-for="s in SORTS"
            :key="s.key"
            class="sort"
            :class="{ on: sort === s.key }"
            type="button"
            @click="setSort(s.key)"
          >
            {{ s.label }}
          </button>
        </div>
      </div>

      <div class="filterbar">
        <button
          class="filters-toggle"
          :class="{ on: panelOpen || activeCount > 0 }"
          type="button"
          @click="panelOpen = !panelOpen"
        >
          <span class="i">⚑</span> Filters
          <span v-if="activeCount" class="fbadge">{{ activeCount }}</span>
          <span class="caret">{{ panelOpen ? '▴' : '▾' }}</span>
        </button>
        <button v-if="hasFilters" class="clear" type="button" @click="clearFilters">Clear</button>
      </div>

      <div v-show="panelOpen" class="panel">
        <div class="facet">
          <span class="facet-label">Genre</span>
          <div class="chips">
            <button
              v-for="g in GENRES"
              :key="g"
              class="chip"
              :class="{ on: genres.includes(g) }"
              type="button"
              @click="toggleGenre(g)"
            >
              {{ g }}
            </button>
          </div>
        </div>

        <div class="facet-row">
          <div class="facet">
            <span class="facet-label">Watched</span>
            <div class="chips">
              <button
                v-for="w in WATCHED"
                :key="w.key"
                class="chip"
                :class="{ on: watched === w.key }"
                type="button"
                @click="setWatched(w.key)"
              >
                {{ w.label }}
              </button>
            </div>
          </div>

          <div class="facet">
            <span class="facet-label">Rating</span>
            <div class="rating">
              <input
                type="range"
                min="0"
                max="10"
                step="0.5"
                :value="ratingLabel"
                @input="ratingLabel = +($event.target as HTMLInputElement).value"
                @change="setRating(+($event.target as HTMLInputElement).value)"
              />
              <span class="rating-val">{{
                ratingLabel ? `★ ${ratingLabel.toFixed(1)}+` : 'Any'
              }}</span>
            </div>
          </div>

          <div class="facet">
            <span class="facet-label">Year</span>
            <div class="years">
              <input
                type="number"
                class="year"
                placeholder="From"
                :value="yearFrom ?? ''"
                @change="setYear('year_from', $event)"
              />
              <span class="dash">–</span>
              <input
                type="number"
                class="year"
                placeholder="To"
                :value="yearTo ?? ''"
                @change="setYear('year_to', $event)"
              />
            </div>
          </div>
        </div>
      </div>

      <div class="showing">Showing {{ cards.length }} titles</div>

      <div v-if="cards.length" class="grid">
        <PosterCard
          v-for="c in cards"
          :key="c.id"
          :title="c.title"
          :subtitle="c.subtitle"
          :kind="c.kind"
          :genre="c.genre"
          :rating="c.rating"
          :poster-url="c.posterUrl"
          :to="c.to"
        />
      </div>

      <div v-else-if="!loading" class="empty">
        <img src="/argosy_logo_dark.png" alt="" />
        <h2>The hold is empty</h2>
        <p>
          Stevedore hasn't loaded any cargo for this filter. Point Argosy at your media folders and
          we'll rebuild the Manifest.
        </p>
        <RouterLink class="scan" :to="{ name: 'settings' }">Scan library</RouterLink>
      </div>
    </div>
  </div>
</template>

<style scoped>
.library {
  position: relative;
  min-height: 100vh;
}
.backdrop {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 460px;
  opacity: 0.45;
  filter: blur(1px);
}
.backdrop-fade {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  height: 460px;
  background: linear-gradient(
    180deg,
    rgba(23, 23, 23, 0.4) 0%,
    rgba(23, 23, 23, 0.78) 55%,
    #171717 100%
  );
}
.content {
  position: relative;
  padding: 104px 40px 90px;
}
.head {
  display: flex;
  align-items: flex-end;
  gap: 24px;
  flex-wrap: wrap;
}
.title-block {
  flex: none;
  width: 200px;
}
.eyebrow {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
h1 {
  margin: 10px 0 0;
  font: 800 clamp(30px, 3.4vw, 40px) var(--arg-display);
  letter-spacing: -0.02em;
}
.count {
  margin-top: 4px;
  font: 500 13px var(--arg-body);
  color: var(--arg-dim);
}
.search {
  flex: 1;
  min-width: 280px;
  max-width: 520px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 13px 18px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line-3);
  background: rgba(20, 20, 19, 0.7);
  backdrop-filter: blur(8px);
  color: #8a8a82;
  font: 500 14.5px var(--arg-body);
  cursor: text;
  text-align: left;
}
.search:hover {
  border-color: var(--arg-accent);
}
.controls {
  margin-top: 22px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 14px;
  flex-wrap: wrap;
}
.filters {
  display: flex;
  align-items: center;
  gap: 18px;
  flex-wrap: wrap;
}
.kinds {
  display: flex;
  gap: 2px;
  padding: 3px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.5);
}
.kind {
  padding: 7px 16px;
  border-radius: 999px;
  border: none;
  background: transparent;
  color: var(--arg-soft);
  font: 700 12.5px var(--arg-display);
  cursor: pointer;
}
.kind:hover {
  color: var(--arg-cream);
}
.kind.on {
  background: var(--arg-accent);
  color: var(--arg-bg);
}
.chips {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.chip {
  padding: 8px 15px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.chip:hover {
  border-color: var(--arg-accent);
}
.chip.on {
  background: var(--arg-accent-bg-2);
  border-color: rgba(201, 154, 78, 0.5);
  color: var(--arg-accent);
}
.sorts {
  display: flex;
  align-items: center;
  gap: 8px;
}
.sort-label {
  font: 500 12px var(--arg-body);
  color: var(--arg-faint);
}
.sort {
  padding: 8px 14px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.sort.on {
  background: var(--arg-accent-bg-2);
  border-color: rgba(201, 154, 78, 0.5);
  color: var(--arg-accent);
}
.filterbar {
  margin-top: 16px;
  display: flex;
  align-items: center;
  gap: 10px;
}
.filters-toggle {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 9px 16px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.5);
  color: var(--arg-soft);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.filters-toggle.on {
  border-color: var(--arg-accent);
  color: var(--arg-cream);
}
.filters-toggle .i {
  color: var(--arg-accent);
}
.fbadge {
  min-width: 18px;
  padding: 1px 6px;
  border-radius: 999px;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 11px var(--arg-display);
  text-align: center;
}
.caret {
  color: var(--arg-faint);
  font-size: 10px;
}
.panel {
  margin-top: 12px;
  padding: 18px 20px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.5);
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.facet {
  display: flex;
  align-items: baseline;
  gap: 14px;
}
.facet-label {
  flex: none;
  width: 64px;
  font: 700 11px var(--arg-display);
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--arg-faint);
  padding-top: 8px;
}
.facet-row {
  display: flex;
  gap: 30px;
  flex-wrap: wrap;
}
.facet-row .facet {
  align-items: center;
}
.facet-row .facet-label {
  width: auto;
  padding-top: 0;
}
.rating {
  display: flex;
  align-items: center;
  gap: 12px;
}
.rating input[type='range'] {
  width: 150px;
  accent-color: var(--arg-accent);
}
.rating-val {
  min-width: 58px;
  font: 600 12.5px var(--arg-body);
  color: var(--arg-soft);
}
.years {
  display: flex;
  align-items: center;
  gap: 10px;
}
.year {
  width: 90px;
  padding: 8px 12px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-cream);
  font: 500 13px var(--arg-body);
  outline: none;
}
.year:focus {
  border-color: var(--arg-accent);
}
.dash {
  color: var(--arg-faint);
}
.clear {
  padding: 9px 16px;
  border-radius: 999px;
  border: 1px solid transparent;
  background: transparent;
  color: var(--arg-accent);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.clear:hover {
  border-color: var(--arg-accent);
}
.showing {
  margin: 22px 0;
  font: 600 12.5px var(--arg-body);
  color: var(--arg-mute);
}
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(156px, 1fr));
  gap: 24px 18px;
}
.empty {
  margin-top: 30px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 60px 30px;
}
.empty img {
  width: 180px;
  height: auto;
  opacity: 0.18;
  filter: grayscale(1);
}
.empty h2 {
  margin: 26px 0 0;
  font: 800 24px var(--arg-display);
}
.empty p {
  margin: 10px 0 26px;
  max-width: 420px;
  font: 400 15px/1.6 var(--arg-body);
  color: var(--arg-dim);
}
.scan {
  padding: 13px 24px;
  border-radius: var(--arg-r);
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 14px var(--arg-display);
  cursor: pointer;
}
.scan:hover {
  background: var(--arg-accent-hi);
}
</style>
