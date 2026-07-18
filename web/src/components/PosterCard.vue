<script setup lang="ts">
import { computed } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { posterStyle } from '@/lib/poster'

const props = defineProps<{
  title: string
  subtitle?: string
  kind?: string
  genre?: string | null
  rating?: number | null
  posterUrl?: string | null
  to: RouteLocationRaw
  width?: number
}>()

const style = computed(() => posterStyle(props.posterUrl, props.title))

// Caption line under the title: subtitle (year / SxxExx) joined with the primary
// genre, matching the design's "2021 · Sci-Fi" treatment.
const metaLine = computed(() => [props.subtitle, props.genre].filter(Boolean).join(' · '))
const ratingText = computed(() =>
  typeof props.rating === 'number' ? props.rating.toFixed(1) : null,
)
</script>

<template>
  <RouterLink class="card" :to="to" :style="width ? { width: `${width}px` } : undefined">
    <div class="poster" :style="style">
      <div class="arg-hatch overlay" />
      <span v-if="kind" class="kind">{{ kind }}</span>
      <div class="plate">
        <div class="title">{{ title }}</div>
        <div v-if="metaLine || ratingText" class="line">
          <span class="sub">{{ metaLine }}</span>
          <span v-if="ratingText" class="score">★ {{ ratingText }}</span>
        </div>
      </div>
    </div>
  </RouterLink>
</template>

<style scoped>
.card {
  display: block;
  cursor: pointer;
  transition: transform 0.18s ease;
  /* In a PosterRail's horizontal scroller, hold the intended width instead of
     shrinking to cram the whole row in (which squeezed the caption line). */
  flex: none;
}
.card:hover,
.card:focus-visible {
  transform: translateY(-4px);
}
.card:focus-visible {
  outline: none;
}
.poster {
  position: relative;
  aspect-ratio: 2 / 3;
  border-radius: var(--arg-r-sm);
  overflow: hidden;
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4);
  border: 1px solid rgba(234, 234, 229, 0.06);
  transition:
    box-shadow 0.24s ease,
    outline-color 0.24s ease;
  outline: 3px solid transparent;
  outline-offset: 3px;
}
.card:hover .poster {
  box-shadow: 0 14px 34px rgba(0, 0, 0, 0.5);
}
.card:focus-visible .poster {
  box-shadow: 0 14px 34px rgba(0, 0, 0, 0.5);
  outline-color: var(--arg-accent);
}
.overlay {
  position: absolute;
  inset: 0;
}
.kind {
  position: absolute;
  top: 9px;
  left: 10px;
  font: 700 8.5px var(--arg-display);
  letter-spacing: 0.13em;
  color: rgba(234, 234, 229, 0.4);
  text-transform: uppercase;
}
/* 1f — reveal on focus: the poster stays clean and gallery-like; the title
   plate slides up only on hover/keyboard-focus so our label never fights the
   title baked into the key-art. */
.plate {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 11px 10px;
  background: linear-gradient(180deg, rgba(30, 26, 18, 0.65), rgba(24, 20, 14, 1));
  border-top: 2px solid var(--arg-accent);
  opacity: 0;
  transform: translateY(14px);
  transition:
    opacity 0.26s cubic-bezier(0.16, 1, 0.3, 1),
    transform 0.26s cubic-bezier(0.16, 1, 0.3, 1);
}
.card:hover .plate,
.card:focus-visible .plate {
  opacity: 1;
  transform: translateY(0);
}
.title {
  font: 700 14px/1.12 var(--arg-display);
  color: var(--arg-cream);
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.line {
  margin-top: 3px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.sub {
  flex: 1 1 auto;
  min-width: 0;
  font: 600 10px var(--arg-body);
  color: var(--arg-accent-soft);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.score {
  flex: none;
  margin-left: auto;
  font: 600 10px var(--arg-body);
  color: var(--arg-accent);
  white-space: nowrap;
}
/* Touch devices have no hover: keep the plate visible so titles never vanish. */
@media (hover: none) {
  .plate {
    opacity: 1;
    transform: none;
  }
}
@media (prefers-reduced-motion: reduce) {
  .card,
  .poster,
  .plate {
    transition: none;
  }
}
</style>
