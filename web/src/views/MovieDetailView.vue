<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '@/api/client'
import DetailScaffold from '@/components/DetailScaffold.vue'
import PosterCard from '@/components/PosterCard.vue'
import PosterRail from '@/components/PosterRail.vue'
import AddToVault from '@/components/AddToVault.vue'
import { formatRuntime, formatClock } from '@/lib/format'
import { getMovies, type MovieSummary } from '@/lib/manifest'
import { getProgress, setWatched, type PlayState } from '@/lib/playback'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type MovieDetail = components['schemas']['MediaItemDetail']

const route = useRoute()
const movie = ref<MovieDetail | null>(null)
const related = ref<MovieSummary[]>([])
const progress = ref<PlayState | null>(null)
const notFound = ref(false)

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

// Explicit watched toggle (ARGY-109), independent of playback progress. Marking
// watched clears Resume (resumable checks !watched); unmarking restores it if a
// resume position is still on file. The backend keeps the position either way.
const marking = ref(false)
const isWatched = computed(() => !!progress.value?.watched)
async function toggleWatched(): Promise<void> {
  const m = movie.value
  if (!m || marking.value) return
  const next = !isWatched.value
  marking.value = true
  try {
    await setWatched(m.id, next)
    if (progress.value) progress.value.watched = next
    else progress.value = { positionSeconds: 0, watched: next }
  } finally {
    marking.value = false
  }
}

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
  <DetailScaffold
    v-if="movie"
    layout="poster"
    :title="movie.title"
    :backdrop-url="movie.backdropUrl"
    :poster-url="movie.posterUrl"
    :overview="movie.overview"
    :cast="movie.cast"
    :genres="movie.genres"
    :min-height="726"
    :min-height-narrow="456"
  >
    <template #meta>
      <span>{{ movie.year ?? '—' }}</span>
      <span class="sep">•</span>
      <span>{{ formatRuntime(movie.durationSeconds) }}</span>
      <span v-if="movie.container" class="sep">•</span>
      <span v-if="movie.container" class="badge">{{ movie.container.toUpperCase() }}</span>
      <span class="sep">•</span>
      <span class="kind">{{ movie.kind === 'movie' ? 'Film' : movie.kind }}</span>
    </template>

    <template #actions>
      <template v-if="resumable">
        <RouterLink
          class="arg-play"
          :to="{ name: 'player', params: { id: movie.id }, query: { resume: '1' } }"
        >
          <span>▶</span> Resume
        </RouterLink>
        <RouterLink
          class="arg-ghost"
          :to="{ name: 'player', params: { id: movie.id }, query: { start: '1' } }"
        >
          Start over
        </RouterLink>
      </template>
      <RouterLink v-else class="arg-play" :to="{ name: 'player', params: { id: movie.id } }">
        <span>▶</span> Play
      </RouterLink>
      <AddToVault :movie-id="movie.id" />
      <button
        class="arg-ghost mark"
        :class="{ on: isWatched }"
        type="button"
        :disabled="marking"
        @click="toggleWatched"
      >
        {{ isWatched ? '✓ Watched' : 'Mark watched' }}
      </button>
    </template>

    <template #extra>
      <div v-if="resumable && progress" class="resume-bar">
        <div class="track"><div class="fill" :style="{ width: `${percent}%` }" /></div>
        <span
          >{{ Math.round(percent) }}% · resume at {{ formatClock(progress.positionSeconds) }}</span
        >
      </div>
      <p v-if="movie.reviewRequired" class="review">
        ⚑ Flagged for review — metadata may be incomplete.
      </p>
    </template>

    <PosterRail v-if="related.length" label="More like this">
      <PosterCard
        v-for="r in related"
        :key="r.id"
        :width="150"
        :title="r.title"
        :subtitle="r.year ? String(r.year) : undefined"
        :kind="r.kind"
        :genre="r.genres?.[0]"
        :rating="r.rating"
        :poster-url="r.posterUrl"
        :to="{ name: 'movie', params: { id: r.id } }"
      />
    </PosterRail>
  </DetailScaffold>

  <div v-else-if="notFound" class="arg-missing">That title isn't in the Manifest.</div>
</template>

<style scoped>
.mark.on {
  border-color: rgba(201, 154, 78, 0.5);
  color: var(--arg-accent);
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
</style>
