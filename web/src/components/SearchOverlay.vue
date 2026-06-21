<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import type { RouteLocationRaw } from 'vue-router'
import { closeSearch } from '@/lib/ui'
import {
  getFacets,
  searchManifest,
  type MovieSummary,
  type SeriesSummary,
} from '@/lib/manifest'
import { posterStyle } from '@/lib/poster'

const router = useRouter()
const input = ref<HTMLInputElement | null>(null)
const query = ref('')

const movies = ref<MovieSummary[]>([])
const series = ref<SeriesSummary[]>([])
const loading = ref(false)
const searched = ref(false) // a query has resolved at least once for the current text

const hasQuery = computed(() => query.value.trim().length > 0)
const hasResults = computed(() => movies.value.length > 0 || series.value.length > 0)

type Chip = { label: string; icon: string; to: RouteLocationRaw }

// Movies + Series are always offered; the rest are the most-common facets
// (genres + tags) in the manifest, fetched on open — so the chips reflect what's
// actually in the library rather than a hardcoded guess.
const staticChips: Chip[] = [
  { label: 'Movies', icon: '▦', to: { name: 'library', query: { kind: 'movies' } } },
  { label: 'Shows', icon: '▥', to: { name: 'library', query: { kind: 'series' } } },
]
const facetChips = ref<Chip[]>([])
const browse = computed<Chip[]>(() => [...staticChips, ...facetChips.value])

// Debounced live search. A monotonically increasing token discards out-of-order
// responses so a slow earlier request can't overwrite a newer one's results.
let debounce: ReturnType<typeof setTimeout> | undefined
let token = 0

watch(query, (q) => {
  if (debounce) clearTimeout(debounce)
  if (!q.trim()) {
    movies.value = []
    series.value = []
    loading.value = false
    searched.value = false
    return
  }
  loading.value = true
  debounce = setTimeout(() => void run(q), 180)
})

async function run(q: string): Promise<void> {
  const mine = ++token
  const res = await searchManifest(q)
  if (mine !== token) return // a newer keystroke superseded this request
  movies.value = res.movies
  series.value = res.series
  loading.value = false
  searched.value = true
}

function go(to: RouteLocationRaw): void {
  closeSearch()
  void router.push(to)
}

function openMovie(m: MovieSummary): void {
  go({ name: 'movie', params: { id: m.id } })
}

function openSeries(s: SeriesSummary): void {
  go({ name: 'series', params: { id: s.id } })
}

// Enter jumps to the top result (films first, then series).
function submit(): void {
  if (movies.value.length) openMovie(movies.value[0])
  else if (series.value.length) openSeries(series.value[0])
}

function onKey(e: KeyboardEvent): void {
  if (e.key === 'Escape') closeSearch()
}

onMounted(async () => {
  window.addEventListener('keydown', onKey)
  input.value?.focus()
  // A genre chip filters by genre; a tag chip by tag — routed to the Library.
  const facets = await getFacets(6)
  facetChips.value = facets.map((f) => ({
    label: f.value,
    icon: f.type === 'tag' ? '◆' : '◇',
    to: { name: 'library', query: f.type === 'tag' ? { tag: f.value } : { genre: f.value } },
  }))
})
onUnmounted(() => {
  window.removeEventListener('keydown', onKey)
  if (debounce) clearTimeout(debounce)
})
</script>

<template>
  <div class="scrim" @click.self="closeSearch">
    <div class="panel">
      <div class="eyebrow">The Manifest</div>
      <div class="prompt">What are we watching?</div>
      <div class="field">
        <span class="icon">⌕</span>
        <input
          ref="input"
          v-model="query"
          type="text"
          placeholder="Search titles, genres, tags…"
          @keyup.enter="submit"
        />
      </div>
      <template v-if="!hasQuery">
        <div class="chips">
          <button v-for="b in browse" :key="b.label" class="chip" type="button" @click="go(b.to)">
            <span class="chip-icon">{{ b.icon }}</span> {{ b.label }}
          </button>
        </div>
        <div class="hint">Press a tag to browse, or start typing to search the Manifest</div>
      </template>

      <div v-else class="results">
        <div v-if="series.length" class="group">
          <div class="group-head">Series</div>
          <button
            v-for="s in series"
            :key="s.id"
            class="result"
            type="button"
            @click="openSeries(s)"
          >
            <span class="thumb" :style="posterStyle(s.posterUrl, s.title)" />
            <span class="meta">
              <span class="title">{{ s.title }}</span>
              <span class="sub">Series<template v-if="s.year"> · {{ s.year }}</template></span>
            </span>
          </button>
        </div>
        <div v-if="movies.length" class="group">
          <div class="group-head">Films</div>
          <button
            v-for="m in movies"
            :key="m.id"
            class="result"
            type="button"
            @click="openMovie(m)"
          >
            <span class="thumb" :style="posterStyle(m.posterUrl, m.title)" />
            <span class="meta">
              <span class="title">{{ m.title }}</span>
              <span class="sub">Film<template v-if="m.year"> · {{ m.year }}</template></span>
            </span>
          </button>
        </div>
        <div v-if="searched && !hasResults" class="hint">No matches for "{{ query.trim() }}"</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.scrim {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px;
  background: rgba(10, 10, 9, 0.82);
  backdrop-filter: blur(10px);
  animation: argFade 0.28s ease;
}
.panel {
  width: 100%;
  max-width: 640px;
  text-align: center;
  animation: argRise 0.32s cubic-bezier(0.16, 1, 0.3, 1) both;
}
.eyebrow {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
.prompt {
  margin-top: 14px;
  font: 800 clamp(32px, 4.4vw, 46px) var(--arg-display);
  letter-spacing: -0.02em;
}
.field {
  margin-top: 28px;
  position: relative;
}
.field .icon {
  position: absolute;
  left: 20px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--arg-accent);
  font-size: 21px;
}
.field input {
  width: 100%;
  padding: 20px 22px 20px 56px;
  border-radius: 14px;
  border: 1px solid rgba(201, 154, 78, 0.4);
  background: var(--arg-panel-2);
  color: var(--arg-cream);
  font: 500 18px var(--arg-body);
  outline: none;
}
.field input:focus {
  border-color: var(--arg-accent);
}
.chips {
  margin-top: 24px;
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  justify-content: center;
}
.chip {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 11px 20px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: var(--arg-panel);
  color: #e4e4dc;
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.chip:hover {
  border-color: var(--arg-accent);
  background: #221f1b;
}
.chip-icon {
  color: var(--arg-accent);
  font-size: 13px;
}
.hint {
  margin-top: 26px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-faint);
}
.results {
  margin-top: 22px;
  text-align: left;
  max-height: min(56vh, 460px);
  overflow-y: auto;
}
.group + .group {
  margin-top: 18px;
}
.group-head {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--arg-faint);
  padding: 0 4px 8px;
}
.result {
  display: flex;
  align-items: center;
  gap: 14px;
  width: 100%;
  padding: 8px 10px;
  border: 1px solid transparent;
  border-radius: 12px;
  background: none;
  color: var(--arg-cream);
  cursor: pointer;
  text-align: left;
}
.result:hover {
  background: var(--arg-panel);
  border-color: var(--arg-line-2);
}
.thumb {
  flex: none;
  width: 40px;
  height: 58px;
  border-radius: 6px;
  border: 1px solid var(--arg-line-2);
  background-color: var(--arg-panel-2);
}
.meta {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}
.title {
  font: 600 15px var(--arg-body);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.sub {
  font: 500 12px var(--arg-body);
  color: var(--arg-faint);
}
</style>
