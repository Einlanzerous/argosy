<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { api } from '@/api/client'
import PosterCard from '@/components/PosterCard.vue'
import PosterRail from '@/components/PosterRail.vue'
import { posterStyle } from '@/lib/poster'
import { formatRuntime, formatTitle } from '@/lib/format'
import {
  getRecent,
  getFacets,
  getMovies,
  getSeries,
  getLibraries,
  type RecentItem,
} from '@/lib/manifest'
import { getContinue, getOnDeck, type ContinueItem, type OnDeckItem } from '@/lib/playback'
import { listVaults, getVault } from '@/lib/vaults'
import { subscribeBeacon } from '@/lib/beacon'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type MovieDetail = components['schemas']['MediaItemDetail']

type GenreCard = {
  id: string
  title: string
  year?: number
  kind: string
  anime: boolean
  posterUrl?: string | null
  to: RouteLocationRaw
}

const recentItems = ref<RecentItem[]>([])
const continueItems = ref<ContinueItem[]>([])
const onDeckItems = ref<OnDeckItem[]>([])
const genreRows = ref<{ genre: string; cards: GenreCard[] }[]>([])
const vaultRows = ref<{ id: string; name: string; cards: GenreCard[] }[]>([])

// Surface up to three non-empty vaults as home rows.
async function buildVaultRows(): Promise<void> {
  const vs = (await listVaults()).filter((v) => v.itemCount > 0).slice(0, 3)
  const details = await Promise.all(vs.map((v) => getVault(v.id).catch(() => null)))
  vaultRows.value = details
    .filter((d): d is NonNullable<typeof d> => !!d)
    .map((d) => ({
      id: d.id,
      name: d.name,
      cards: d.items.slice(0, 12).map((e) => ({
        id: e.id,
        title: e.title,
        year: e.year ?? undefined,
        kind: e.kind === 'series' ? 'Series' : 'Film',
        anime: false,
        posterUrl: e.posterUrl,
        to: (e.kind === 'series'
          ? { name: 'series', params: { id: e.id } }
          : { name: 'movie', params: { id: e.id } }) as RouteLocationRaw,
      })),
    }))
}
const heroDetail = ref<MovieDetail | null>(null)
const loading = ref(true)

// Build a couple of auto "Because it's in the hold" genre rows from the most
// common genres, newest-rated first. Films + series for each, capped per row.
async function buildGenreRows(): Promise<void> {
  const libs = await getLibraries()
  const top = (await getFacets(8)).filter((f) => f.type === 'genre').slice(0, 2)
  genreRows.value = await Promise.all(
    top.map(async (f) => {
      const [movies, series] = await Promise.all([
        getMovies({ genres: [f.value], sort: 'rating' }, libs),
        getSeries({ genres: [f.value], sort: 'rating' }, libs),
      ])
      const cards: GenreCard[] = [
        ...movies.map((m) => ({
          id: m.id,
          title: m.title,
          year: m.year ?? undefined,
          kind: m.kind,
          anime: !!m.tags?.includes('anime'),
          posterUrl: m.posterUrl,
          to: { name: 'movie', params: { id: m.id } } as RouteLocationRaw,
        })),
        ...series.map((s) => ({
          id: s.id,
          title: s.title,
          year: s.year ?? undefined,
          kind: 'Series',
          anime: !!s.tags?.includes('anime'),
          posterUrl: s.posterUrl,
          to: { name: 'series', params: { id: s.id } } as RouteLocationRaw,
        })),
      ].slice(0, 12)
      return { genre: f.value, cards }
    }),
  )
}

const recent = computed(() => recentItems.value.slice(0, 12))
// The hero's film fallback is the newest *film* (a series id isn't directly
// playable). Films keep kind "movie"; series carry kind "series".
const newestFilm = computed(() => recentItems.value.find((i) => i.kind !== 'series'))

// The hero is the top continue-watching item when there is one (a real resume),
// otherwise the most recent film as a featured spotlight.
const hero = computed(() => {
  const r = continueItems.value[0]
  if (r) {
    return {
      id: r.id,
      eyebrow: 'Continue watching',
      title: r.seriesTitle || r.title,
      sub: r.seriesTitle ? formatTitle(r.title) : r.year ? String(r.year) : '',
      posterUrl: r.posterUrl,
      backdropUrl: r.backdropUrl,
      percent: r.percent,
      detailTo: (r.seriesId
        ? { name: 'series', params: { id: r.seriesId } }
        : { name: 'movie', params: { id: r.id } }) as RouteLocationRaw,
    }
  }
  const f = newestFilm.value
  if (f) {
    return {
      id: f.id,
      eyebrow: 'Featured in the hold',
      title: f.title,
      sub: f.year ? String(f.year) : '',
      posterUrl: f.posterUrl,
      backdropUrl: f.backdropUrl,
      percent: null as number | null,
      detailTo: { name: 'movie', params: { id: f.id } } as RouteLocationRaw,
    }
  }
  return null
})

// Heroes are full-screen + landscape, so prefer the backdrop; fall back to the
// poster when an item has no backdrop yet.
const heroStyle = computed(() =>
  posterStyle(hero.value?.backdropUrl ?? hero.value?.posterUrl, hero.value?.title ?? ''),
)

// Beacon keeps "Continue Watching" live: when another of the user's devices
// moves or finishes an item, refresh the rail (debounced, so a burst of
// heartbeats collapses to one fetch). The fetch also reconciles anything missed
// while disconnected — Beacon's onOpen fires on every (re)connect. A plain page
// load is the polling fallback when SSE is unavailable.
let closeBeacon: (() => void) | null = null
let refreshTimer: ReturnType<typeof setTimeout> | null = null
function refreshContinueSoon(): void {
  if (refreshTimer) return
  refreshTimer = setTimeout(async () => {
    refreshTimer = null
    continueItems.value = await getContinue().catch(() => continueItems.value)
  }, 1500)
}

onMounted(async () => {
  setPage('Home')
  ;[recentItems.value, continueItems.value, onDeckItems.value] = await Promise.all([
    getRecent().catch(() => []),
    getContinue().catch(() => []),
    getOnDeck().catch(() => []),
  ])
  loading.value = false
  void buildVaultRows().catch(() => {})
  void buildGenreRows().catch(() => {})
  if (hero.value) {
    const { data } = await api.GET('/api/v1/items/{itemId}', {
      params: { path: { itemId: hero.value.id } },
    })
    heroDetail.value = data ?? null
  }
  closeBeacon = subscribeBeacon({
    onPosition: refreshContinueSoon,
    onOpen: refreshContinueSoon,
  })
})

onUnmounted(() => {
  closeBeacon?.()
  if (refreshTimer) clearTimeout(refreshTimer)
})
</script>

<template>
  <div>
    <section v-if="hero" class="hero">
      <div class="hero-art" :style="heroStyle" />
      <div class="shade-l" />
      <div class="shade-b" />
      <div class="hero-body">
        <div class="eyebrow"><span>⇄</span> {{ hero.eyebrow }}</div>
        <h1>{{ hero.title }}</h1>
        <div class="meta">
          {{ [hero.sub, heroDetail ? formatRuntime(heroDetail.durationSeconds) : null]
            .filter(Boolean)
            .join(' · ') }}
        </div>
        <p v-if="heroDetail?.overview" class="synopsis">{{ heroDetail.overview }}</p>
        <div v-if="hero.percent != null" class="progress">
          <div class="track"><div class="fill" :style="{ width: `${hero.percent}%` }" /></div>
          <span>{{ Math.round(hero.percent) }}% watched</span>
        </div>
        <div class="cue"><span class="dot" /> Syncs across your Fleet — resume on any device</div>
        <div class="actions">
          <RouterLink
            class="play"
            :to="{ name: 'player', params: { id: hero.id }, query: hero.percent != null ? { resume: '1' } : undefined }"
          >
            <span>▶</span> {{ hero.percent != null ? 'Resume' : 'Play' }}
          </RouterLink>
          <RouterLink class="ghost" :to="hero.detailTo">Details</RouterLink>
        </div>
      </div>
    </section>

    <div class="rails" :class="{ 'no-hero': !hero }">
      <PosterRail
        v-if="continueItems.length"
        label="Continue Watching"
        hint="pick up on any deck in your Fleet"
      >
        <RouterLink
          v-for="c in continueItems"
          :key="c.id"
          class="cw"
          :to="{ name: 'player', params: { id: c.id }, query: { resume: '1' } }"
        >
          <div class="cw-art" :style="posterStyle(c.posterUrl, c.title)">
            <div class="arg-hatch cw-hatch" />
            <div class="cw-grad" />
            <div class="cw-meta">
              <div class="cw-title">{{ c.seriesTitle || formatTitle(c.title) }}</div>
              <div class="cw-sub">{{ c.seriesTitle ? formatTitle(c.title) : c.year }}</div>
            </div>
            <div class="cw-bar"><div class="cw-fill" :style="{ width: `${c.percent}%` }" /></div>
          </div>
          <div class="cw-foot">{{ Math.round(c.percent) }}% · resume</div>
        </RouterLink>
      </PosterRail>

      <PosterRail v-if="onDeckItems.length" label="On Deck" hint="next up in shows you're watching">
        <PosterCard
          v-for="o in onDeckItems"
          :key="o.id"
          :width="158"
          :title="o.seriesTitle"
          :subtitle="`S${o.seasonNumber} · E${o.episodeNumber}`"
          kind="Up Next"
          :poster-url="o.posterUrl"
          :to="{ name: 'player', params: { id: o.id } }"
        />
      </PosterRail>

      <PosterRail v-if="recent.length" label="Newly Arrived" :view-all-to="{ name: 'library' }">
        <PosterCard
          v-for="m in recent"
          :key="m.id"
          :width="158"
          :title="m.title"
          :subtitle="m.year ? String(m.year) : undefined"
          :kind="m.kind"
          :anime="m.tags?.includes('anime')"
          :poster-url="m.posterUrl"
          :to="m.kind === 'series'
            ? { name: 'series', params: { id: m.id } }
            : { name: 'movie', params: { id: m.id } }"
        />
      </PosterRail>

      <PosterRail
        v-for="row in vaultRows"
        :key="row.id"
        :label="row.name"
        :view-all-to="{ name: 'vault', params: { id: row.id } }"
      >
        <PosterCard
          v-for="c in row.cards"
          :key="c.id"
          :width="158"
          :title="c.title"
          :subtitle="c.year ? String(c.year) : undefined"
          :kind="c.kind"
          :anime="c.anime"
          :poster-url="c.posterUrl"
          :to="c.to"
        />
      </PosterRail>

      <PosterRail
        v-for="row in genreRows"
        :key="row.genre"
        :label="row.genre"
        :view-all-to="{ name: 'library', query: { genre: row.genre } }"
      >
        <PosterCard
          v-for="c in row.cards"
          :key="c.id"
          :width="158"
          :title="c.title"
          :subtitle="c.year ? String(c.year) : undefined"
          :kind="c.kind"
          :anime="c.anime"
          :poster-url="c.posterUrl"
          :to="c.to"
        />
      </PosterRail>

      <div v-if="!loading && !recent.length && !continueItems.length" class="hold-empty">
        <img src="/argosy_logo_dark.png" alt="" />
        <h2>The hold is empty</h2>
        <p>
          Stevedore hasn't loaded any cargo yet. Point Argosy at your media folders and rebuild the
          Manifest from Settings.
        </p>
        <RouterLink class="play" :to="{ name: 'settings' }"><span>⟲</span> Go to Settings</RouterLink>
      </div>
    </div>
  </div>
</template>

<style scoped>
.hero {
  position: relative;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  overflow: hidden;
}
.hero-art {
  position: absolute;
  inset: 0;
}
.shade-l {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(90deg, rgba(20, 20, 19, 0.95) 0%, rgba(20, 20, 19, 0.6) 44%, rgba(20, 20, 19, 0) 78%);
}
.shade-b {
  position: absolute;
  inset: 0;
  pointer-events: none;
  background: linear-gradient(0deg, #171717 2%, rgba(23, 23, 23, 0.5) 26%, rgba(23, 23, 23, 0) 60%);
}
.hero-body {
  position: relative;
  z-index: 2;
  padding: 0 56px 96px;
  max-width: 680px;
}
.eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 9px;
  font: 700 11px var(--arg-display);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
h1 {
  margin: 16px 0 0;
  font: 800 clamp(46px, 6vw, 70px) / 0.97 var(--arg-display);
  letter-spacing: -0.025em;
}
.meta {
  margin-top: 13px;
  font: 600 15px var(--arg-body);
  color: var(--arg-soft-2);
}
.synopsis {
  margin: 13px 0 0;
  max-width: 520px;
  font: 400 15px/1.6 var(--arg-body);
  color: #a8a89f;
}
.progress {
  margin-top: 22px;
  display: flex;
  align-items: center;
  gap: 14px;
  max-width: 460px;
}
.progress .track {
  flex: 1;
  height: 5px;
  border-radius: 3px;
  background: rgba(234, 234, 229, 0.2);
}
.progress .fill {
  height: 100%;
  border-radius: 3px;
  background: var(--arg-accent);
}
.progress span {
  font: 600 12.5px var(--arg-body);
  color: #bdbdb4;
  font-variant-numeric: tabular-nums;
}
.cue {
  margin-top: 16px;
  display: inline-flex;
  align-items: center;
  gap: 9px;
  padding: 9px 14px;
  border-radius: 999px;
  background: var(--arg-accent-bg);
  border: 1px solid rgba(201, 154, 78, 0.26);
  font: 600 12.5px var(--arg-body);
  color: var(--arg-accent-soft);
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--arg-accent);
  box-shadow: 0 0 9px var(--arg-accent);
}
.actions {
  margin-top: 26px;
  display: flex;
  gap: 12px;
}
.play {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 15px 30px;
  border: none;
  border-radius: 11px;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 16px var(--arg-display);
  cursor: pointer;
}
.play:hover {
  background: var(--arg-accent-hi);
}
.ghost {
  padding: 15px 24px;
  border: 1px solid rgba(234, 234, 229, 0.2);
  border-radius: 11px;
  background: rgba(20, 20, 19, 0.45);
  backdrop-filter: blur(6px);
  color: var(--arg-cream);
  font: 600 15px var(--arg-body);
  cursor: pointer;
}
.ghost:hover {
  border-color: var(--arg-cream);
}
.rails {
  padding: 6px 56px 96px;
}
.rails.no-hero {
  padding-top: 96px;
}
.cw {
  display: block;
  flex: none;
  width: 300px;
  cursor: pointer;
  transition: transform 0.18s ease;
}
.cw:hover {
  transform: translateY(-3px);
}
.cw-art {
  position: relative;
  aspect-ratio: 16 / 9;
  border-radius: 11px;
  overflow: hidden;
  border: 1px solid var(--arg-line);
}
.cw-hatch {
  position: absolute;
  inset: 0;
}
.cw-grad {
  position: absolute;
  inset: 0;
  background: linear-gradient(transparent 45%, rgba(12, 12, 11, 0.85));
}
.cw-meta {
  position: absolute;
  left: 14px;
  right: 14px;
  bottom: 16px;
}
.cw-title {
  font: 700 16px var(--arg-display);
}
.cw-sub {
  margin-top: 2px;
  font: 500 11.5px var(--arg-body);
  color: #bdbdb4;
}
.cw-bar {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 4px;
  background: rgba(234, 234, 229, 0.18);
}
.cw-fill {
  height: 100%;
  background: var(--arg-accent);
}
.cw-foot {
  margin-top: 9px;
  font: 500 11.5px var(--arg-body);
  color: var(--arg-mute);
}
.hold-empty {
  margin-top: 40px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 40px 30px;
}
.hold-empty img {
  width: 180px;
  height: auto;
  opacity: 0.18;
  filter: grayscale(1);
}
.hold-empty h2 {
  margin: 26px 0 0;
  font: 800 24px var(--arg-display);
}
.hold-empty p {
  margin: 10px 0 26px;
  max-width: 420px;
  font: 400 15px/1.6 var(--arg-body);
  color: var(--arg-dim);
}
</style>
