<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import PosterCard from '@/components/PosterCard.vue'
import PosterRail from '@/components/PosterRail.vue'
import { posterStyle } from '@/lib/poster'
import { getLibraries, getMovies, getSeries, type MovieSummary, type SeriesSummary } from '@/lib/manifest'
import { setPage } from '@/lib/page'

const movies = ref<MovieSummary[]>([])
const series = ref<SeriesSummary[]>([])
const loading = ref(true)

const featured = computed(() => movies.value[0] ?? null)
const recent = computed(() => movies.value.slice(1, 13))
const shows = computed(() => series.value.slice(0, 12))

onMounted(async () => {
  setPage('Home', 'Pick up where you left off — on any deck in your Fleet.')
  const libs = await getLibraries()
  ;[movies.value, series.value] = await Promise.all([
    getMovies({ sort: 'added' }, libs),
    getSeries({ sort: 'title' }, libs),
  ])
  loading.value = false
})
</script>

<template>
  <div>
    <!-- featured spotlight -->
    <section v-if="featured" class="hero" :style="posterStyle(featured.posterUrl, featured.title)">
      <div class="hero-shade" />
      <div class="arg-hatch hero-hatch" />
      <div class="hero-body">
        <div class="eyebrow"><span>⇄</span> Featured in the hold</div>
        <h1>{{ featured.title }}</h1>
        <div class="hero-sub">{{ featured.year ?? '' }}</div>
        <div class="fleet-cue">
          <span class="dot" /> Syncs across your Fleet — resume on any device
        </div>
        <div class="hero-actions">
          <RouterLink class="play" :to="{ name: 'player', params: { id: featured.id } }">
            <span>▶</span> Play
          </RouterLink>
          <RouterLink class="ghost" :to="{ name: 'movie', params: { id: featured.id } }">
            Details
          </RouterLink>
        </div>
      </div>
    </section>

    <!-- continue watching (play-state lands in a later phase) -->
    <PosterRail label="Continue Watching" hint="pick up on any deck">
      <div class="empty-rail">
        Nothing in progress yet — start something and Argosy will hold your place on every device
        in the Fleet.
      </div>
    </PosterRail>

    <PosterRail v-if="recent.length" label="Recently Added" :view-all-to="{ name: 'movies' }">
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
</template>

<style scoped>
.hero {
  position: relative;
  border-radius: var(--arg-r-xl);
  overflow: hidden;
  border: 1px solid var(--arg-line);
  min-height: 320px;
  display: flex;
  align-items: flex-end;
}
.hero-shade {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    105deg,
    rgba(15, 15, 14, 0.92) 0%,
    rgba(15, 15, 14, 0.65) 42%,
    rgba(15, 15, 14, 0.1) 100%
  );
}
.hero-hatch {
  position: absolute;
  inset: 0;
}
.hero-body {
  position: relative;
  padding: 38px 40px;
  max-width: 560px;
}
.eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font: 700 11px var(--arg-display);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
h1 {
  margin: 14px 0 0;
  font: 800 38px/1.05 var(--arg-display);
  letter-spacing: -0.02em;
}
.hero-sub {
  margin-top: 8px;
  font: 500 14px var(--arg-body);
  color: #bdbdb4;
}
.fleet-cue {
  margin-top: 16px;
  display: inline-flex;
  align-items: center;
  gap: 9px;
  padding: 8px 13px;
  border-radius: 999px;
  background: var(--arg-accent-bg);
  border: 1px solid var(--arg-accent-line);
  font: 600 12.5px var(--arg-body);
  color: var(--arg-accent-soft);
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--arg-accent);
  box-shadow: 0 0 8px var(--arg-accent);
}
.hero-actions {
  margin-top: 24px;
  display: flex;
  gap: 12px;
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
.ghost {
  padding: 13px 22px;
  border: 1px solid var(--arg-line-3);
  border-radius: var(--arg-r);
  background: rgba(20, 20, 19, 0.4);
  color: var(--arg-cream);
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.ghost:hover {
  border-color: var(--arg-cream);
}
.empty-rail {
  flex: none;
  max-width: 520px;
  padding: 22px;
  border-radius: var(--arg-r-lg);
  border: 1px dashed var(--arg-line-2);
  font: 400 13.5px/1.6 var(--arg-body);
  color: var(--arg-dim);
}
.hold-empty {
  margin-top: 50px;
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding: 60px 30px;
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
