<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import type { RouteLocationRaw } from 'vue-router'
import PosterCard from '@/components/PosterCard.vue'
import { getLibraries, getMovies, getSeries, TAG_FILTERS, type MovieSort } from '@/lib/manifest'
import { setPage } from '@/lib/page'

type Card = {
  id: string
  title: string
  year?: number
  kind: string
  anime: boolean
  posterUrl?: string | null
  to: RouteLocationRaw
}

const SORTS: { key: MovieSort; label: string }[] = [
  { key: 'added', label: 'Recently Added' },
  { key: 'title', label: 'Title' },
  { key: 'year', label: 'Year' },
]

const route = useRoute()
const tag = ref('All')
const sort = ref<MovieSort>('added')
const cards = ref<Card[]>([])
const loading = ref(true)

const scope = computed<'all' | 'movies' | 'series'>(() => {
  if (route.name === 'movies') return 'movies'
  if (route.name === 'shows') return 'series'
  return 'all'
})

function headerFor(s: 'all' | 'movies' | 'series'): [string, string] {
  if (s === 'movies') return ['Movies', 'The Manifest · standalone films.']
  if (s === 'series') return ['Shows', 'The Manifest · series in the hold.']
  return ['Library', 'The Manifest · everything in the hold.']
}

async function load(): Promise<void> {
  loading.value = true
  const t = tag.value === 'All' ? undefined : tag.value.toLowerCase()
  const libs = await getLibraries()
  const out: Card[] = []
  if (scope.value !== 'series') {
    const movies = await getMovies({ tag: t, sort: sort.value }, libs)
    out.push(
      ...movies.map((m) => ({
        id: m.id,
        title: m.title,
        year: m.year ?? undefined,
        kind: m.kind,
        anime: !!m.tags?.includes('anime'),
        posterUrl: m.posterUrl,
        to: { name: 'movie', params: { id: m.id } } as RouteLocationRaw,
      })),
    )
  }
  if (scope.value !== 'movies') {
    const seriesSort = sort.value === 'year' ? 'year' : 'title'
    const series = await getSeries({ tag: t, sort: seriesSort }, libs)
    out.push(
      ...series.map((s) => ({
        id: s.id,
        title: s.title,
        year: s.year ?? undefined,
        kind: 'Series',
        anime: !!s.tags?.includes('anime'),
        posterUrl: s.posterUrl,
        to: { name: 'series', params: { id: s.id } } as RouteLocationRaw,
      })),
    )
  }
  cards.value = out
  loading.value = false
}

onMounted(load)

watch(
  () => [scope.value, tag.value, sort.value],
  () => {
    const [t, s] = headerFor(scope.value)
    setPage(t, s)
    void load()
  },
  { immediate: true },
)
</script>

<template>
  <div>
    <div class="controls">
      <div class="chips">
        <button
          v-for="t in TAG_FILTERS"
          :key="t"
          class="chip"
          :class="{ on: tag === t }"
          type="button"
          @click="tag = t"
        >
          {{ t }}
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
          @click="sort = s.key"
        >
          {{ s.label }}
        </button>
      </div>
    </div>

    <div v-if="cards.length" class="grid">
      <PosterCard
        v-for="c in cards"
        :key="c.id"
        :title="c.title"
        :subtitle="c.year ? String(c.year) : undefined"
        :kind="c.kind"
        :anime="c.anime"
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
</template>

<style scoped>
.controls {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
  flex-wrap: wrap;
  margin-bottom: 24px;
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
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(156px, 1fr));
  gap: 24px 18px;
}
.empty {
  margin-top: 50px;
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
