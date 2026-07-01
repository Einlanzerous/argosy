<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/api/client'
import BackButton from '@/components/BackButton.vue'
import PosterCard from '@/components/PosterCard.vue'
import PosterRail from '@/components/PosterRail.vue'
import AddToVault from '@/components/AddToVault.vue'
import LabelEditor from '@/components/LabelEditor.vue'
import { posterStyle } from '@/lib/poster'
import { formatRuntime, formatClock } from '@/lib/format'
import { getMovies, type MovieSummary } from '@/lib/manifest'
import { getProgress, type PlayState } from '@/lib/playback'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type MovieDetail = components['schemas']['MediaItemDetail']

const route = useRoute()
const movie = ref<MovieDetail | null>(null)
const related = ref<MovieSummary[]>([])
const progress = ref<PlayState | null>(null)
const notFound = ref(false)

// The full-screen hero prefers the landscape backdrop; the small poster tile
// stays the portrait poster.
const heroStyle = computed(() =>
  posterStyle(movie.value?.backdropUrl ?? movie.value?.posterUrl, movie.value?.title ?? ''),
)
const posterTile = computed(() => posterStyle(movie.value?.posterUrl, movie.value?.title ?? ''))

// In-progress when there's a saved, unfinished position — drives Resume + Start
// over (and the progress bar) instead of a bare Play.
const resumable = computed(() => {
  const p = progress.value
  return !!(p && !p.watched && p.positionSeconds > 5)
})
const percent = computed(() => {
  const p = progress.value
  if (!p?.durationSeconds) return 0
  return Math.min(100, (p.positionSeconds / p.durationSeconds) * 100)
})

async function load(id: string): Promise<void> {
  notFound.value = false
  movie.value = null
  progress.value = null
  const { data } = await api.GET('/api/v1/items/{itemId}', { params: { path: { itemId: id } } })
  if (!data) {
    notFound.value = true
    setPage('Not found')
    return
  }
  movie.value = data
  setPage(data.title)
  progress.value = await getProgress(id).catch(() => null)
  const all = await getMovies({ sort: 'title' })
  related.value = all.filter((m) => m.id !== id).slice(0, 8)
}

onMounted(() => load(String(route.params.id)))
watch(
  () => route.params.id,
  (id) => id && load(String(id)),
)
</script>

<template>
  <div v-if="movie">
    <section class="hero" :style="heroStyle">
      <div class="arg-hatch hatch" />
      <div class="shade" />
      <BackButton class="hero-back" fallback="library" />
      <div class="body">
        <div class="poster" :style="posterTile">
          <div class="poster-title">{{ movie.title }}</div>
        </div>
        <div class="info">
          <h1>{{ movie.title }}</h1>
          <div class="meta">
            <span>{{ movie.year ?? '—' }}</span>
            <span class="sep">•</span>
            <span>{{ formatRuntime(movie.durationSeconds) }}</span>
            <span v-if="movie.container" class="sep">•</span>
            <span v-if="movie.container" class="badge">{{ movie.container.toUpperCase() }}</span>
            <span class="sep">•</span>
            <span class="kind">{{ movie.kind === 'movie' ? 'Film' : movie.kind }}</span>
          </div>
          <p v-if="movie.overview" class="synopsis">{{ movie.overview }}</p>
          <p v-if="movie.cast?.length" class="cast">
            <span class="cast-label">Cast</span>{{ movie.cast.join(', ') }}
          </p>
          <div v-if="movie.genres?.length || movie.tags?.length" class="tags">
            <span v-for="g in movie.genres ?? []" :key="`g-${g}`" class="tag">{{ g }}</span>
            <span v-for="t in movie.tags ?? []" :key="`t-${t}`" class="tag accent">{{ t }}</span>
          </div>
          <LabelEditor :movie-id="movie.id" :initial="movie.labels ?? []" />
          <div class="actions">
            <template v-if="resumable">
              <RouterLink
                class="play"
                :to="{ name: 'player', params: { id: movie.id }, query: { resume: '1' } }"
              >
                <span>▶</span> Resume
              </RouterLink>
              <RouterLink
                class="ghost"
                :to="{ name: 'player', params: { id: movie.id }, query: { start: '1' } }"
              >
                Start over
              </RouterLink>
            </template>
            <RouterLink v-else class="play" :to="{ name: 'player', params: { id: movie.id } }">
              <span>▶</span> Play
            </RouterLink>
            <AddToVault :movie-id="movie.id" />
          </div>
          <div v-if="resumable && progress" class="resume-bar">
            <div class="track"><div class="fill" :style="{ width: `${percent}%` }" /></div>
            <span
              >{{ Math.round(percent) }}% · resume at
              {{ formatClock(progress.positionSeconds) }}</span
            >
          </div>
          <p v-if="movie.reviewRequired" class="review">
            ⚑ Flagged for review — metadata may be incomplete.
          </p>
        </div>
      </div>
    </section>

    <PosterRail v-if="related.length" label="More like this">
      <PosterCard
        v-for="r in related"
        :key="r.id"
        :width="150"
        :title="r.title"
        :subtitle="r.year ? String(r.year) : undefined"
        :kind="r.kind"
        :anime="r.tags?.includes('anime')"
        :poster-url="r.posterUrl"
        :to="{ name: 'movie', params: { id: r.id } }"
      />
    </PosterRail>
  </div>

  <div v-else-if="notFound" class="missing">That title isn't in the Manifest.</div>
</template>

<style scoped>
.hero {
  position: relative;
  border-radius: var(--arg-r-xl);
  overflow: hidden;
  border: 1px solid var(--arg-line);
  min-height: 726px; /* films run ~20% taller than the series hero (605px) */
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
    rgba(23, 23, 23, 0.5) 50%,
    rgba(23, 23, 23, 0.15) 100%
  );
}
/* Quadrant 1: top-left of the hero, aligned with the poster's left edge (the
   hero body's 40px inset) so it sits above the art, left of the title. */
.hero-back {
  position: absolute;
  top: 50px;
  left: 40px;
  z-index: 3;
}
.body {
  position: relative;
  padding: 48px 40px 36px;
  display: flex;
  gap: 30px;
  align-items: flex-end;
  min-height: 726px; /* films run ~20% taller than the series hero (605px) */
}
.poster {
  flex: none;
  width: 158px;
  aspect-ratio: 2 / 3;
  border-radius: 9px;
  border: 1px solid var(--arg-line-2);
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.5);
  position: relative;
  overflow: hidden;
}
.poster-title {
  position: absolute;
  left: 11px;
  right: 11px;
  bottom: 13px;
  font: 800 15px/1.05 var(--arg-display);
}
.info {
  flex: 1;
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
.badge {
  padding: 2px 7px;
  border: 1px solid var(--arg-line-3);
  border-radius: 5px;
  font-size: 11px;
}
.kind {
  color: var(--arg-accent);
}
.synopsis {
  margin-top: 18px;
  max-width: 620px;
  font: 400 15px/1.65 var(--arg-body);
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
.tags {
  margin-top: 16px;
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.tag {
  padding: 5px 12px;
  border-radius: 999px;
  background: rgba(234, 234, 229, 0.07);
  font: 600 11.5px var(--arg-body);
  color: #a8a89f;
}
.tag.accent {
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent-soft);
}
.actions {
  margin-top: 24px;
  display: flex;
  gap: 12px;
  align-items: center;
}
.play {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 14px 28px;
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
  display: flex;
  align-items: center;
  padding: 14px 22px;
  border: 1px solid var(--arg-line-2);
  border-radius: var(--arg-r);
  background: rgba(20, 20, 19, 0.4);
  color: var(--arg-cream);
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.ghost:hover {
  border-color: var(--arg-cream);
}
.vault {
  width: 48px;
  height: 48px;
  border: 1px solid var(--arg-line-3);
  border-radius: var(--arg-r);
  background: rgba(20, 20, 19, 0.4);
  color: var(--arg-cream);
  font: 400 18px var(--arg-display);
  cursor: pointer;
}
.vault:hover {
  border-color: var(--arg-accent);
}
.resume-bar {
  margin-top: 16px;
  display: flex;
  align-items: center;
  gap: 12px;
  max-width: 460px;
}
.resume-bar .track {
  flex: 1;
  height: 5px;
  border-radius: 3px;
  background: rgba(234, 234, 229, 0.2);
  overflow: hidden;
}
.resume-bar .fill {
  height: 100%;
  border-radius: 3px;
  background: var(--arg-accent);
}
.resume-bar span {
  font: 600 12px var(--arg-body);
  color: var(--arg-soft-2);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.review {
  margin-top: 16px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-accent-soft);
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
    min-height: 456px; /* keep the ~20%-over-series ratio on narrow viewports (series 380px) */
  }
}
</style>
