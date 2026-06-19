<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api } from '@/api/client'
import PosterCard from '@/components/PosterCard.vue'
import PosterRail from '@/components/PosterRail.vue'
import { posterStyle } from '@/lib/poster'
import { formatRuntime } from '@/lib/format'
import { getLibraries, getMovies, getSeries, type MovieSummary, type SeriesSummary } from '@/lib/manifest'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type MovieDetail = components['schemas']['MediaItemDetail']

const movies = ref<MovieSummary[]>([])
const series = ref<SeriesSummary[]>([])
const featuredDetail = ref<MovieDetail | null>(null)
const loading = ref(true)

const featured = computed(() => movies.value[0] ?? null)
const recent = computed(() => movies.value.slice(0, 12))
const shows = computed(() => series.value.slice(0, 12))
const heroStyle = computed(() => posterStyle(featured.value?.posterUrl, featured.value?.title ?? ''))

onMounted(async () => {
  setPage('Home')
  const libs = await getLibraries()
  ;[movies.value, series.value] = await Promise.all([
    getMovies({ sort: 'added' }, libs),
    getSeries({ sort: 'title' }, libs),
  ])
  loading.value = false
  if (featured.value) {
    const { data } = await api.GET('/api/v1/items/{itemId}', {
      params: { path: { itemId: featured.value.id } },
    })
    featuredDetail.value = data ?? null
  }
})
</script>

<template>
  <div>
    <!-- full-bleed cinematic hero -->
    <section v-if="featured" class="hero">
      <div class="hero-art" :style="heroStyle" />
      <div class="shade-l" />
      <div class="shade-b" />
      <div class="hero-body">
        <div class="eyebrow"><span>⇄</span> Featured in the hold</div>
        <h1>{{ featured.title }}</h1>
        <div class="meta">
          {{ [featured.year, featuredDetail ? formatRuntime(featuredDetail.durationSeconds) : null]
            .filter(Boolean)
            .join(' · ') }}
        </div>
        <p v-if="featuredDetail?.overview" class="synopsis">{{ featuredDetail.overview }}</p>
        <div class="cue">
          <span class="dot" /> Syncs across your Fleet — resume on any device
        </div>
        <div class="actions">
          <RouterLink class="play" :to="{ name: 'player', params: { id: featured.id } }">
            <span>▶</span> Play
          </RouterLink>
          <RouterLink class="ghost" :to="{ name: 'movie', params: { id: featured.id } }">
            Details
          </RouterLink>
        </div>
      </div>
    </section>

    <div class="rails" :class="{ 'no-hero': !featured }">
      <!-- Continue Watching takes this slot once play-state lands (Phase 3);
           until then we surface Newly Arrived rather than an empty rail. -->
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
          :to="{ name: 'movie', params: { id: m.id } }"
        />
      </PosterRail>

      <PosterRail v-if="shows.length" label="Shows" :view-all-to="{ name: 'shows' }">
        <PosterCard
          v-for="s in shows"
          :key="s.id"
          :width="158"
          :title="s.title"
          :subtitle="s.year ? String(s.year) : undefined"
          kind="Series"
          :anime="s.tags?.includes('anime')"
          :poster-url="s.posterUrl"
          :to="{ name: 'series', params: { id: s.id } }"
        />
      </PosterRail>

      <div v-if="!loading && !movies.length && !series.length" class="hold-empty">
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
  background: linear-gradient(
    90deg,
    rgba(20, 20, 19, 0.95) 0%,
    rgba(20, 20, 19, 0.6) 44%,
    rgba(20, 20, 19, 0) 78%
  );
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
