<script setup lang="ts">
import { computed } from 'vue'
import BackButton from '@/components/BackButton.vue'
import { posterStyle } from '@/lib/poster'

// The shared anatomy of a detail page (ARGY-111): a backdrop hero carrying the
// back button, an optional poster tile, the title / meta / synopsis / cast
// column, and the action row — with the type-specific bits (a film's playback
// controls, a series' seasons and episodes) supplied through slots. Movie and
// Series detail had each hand-rolled this scaffold and the copies had drifted
// apart in a dozen small ways, which is what this component exists to stop.
const props = withDefaults(
  defineProps<{
    title: string
    /** Hero art. Prefers the landscape backdrop, falling back to the poster. */
    backdropUrl?: string | null
    /** Art for the poster tile, and the hero's fallback backdrop. Supplying it
        does not by itself draw the tile — see `layout`. */
    posterUrl?: string | null
    /** 'poster' sets the portrait tile beside the text column; 'stacked' (the
        default) runs the text column alone across the hero. A film with no
        cached artwork still wants the tile, holding its gradient placeholder,
        so the layout is an explicit choice rather than inferred from posterUrl. */
    layout?: 'poster' | 'stacked'
    overview?: string | null
    cast?: string[] | null
    genres?: string[] | null
    /** Where the back button lands on a cold/deep load with no history. */
    backFallback?: string
    /** Hero height. Films deliberately run ~20% taller than the series hero. */
    minHeight?: number
    /** Hero height under the 720px breakpoint, where the full one dominates. */
    minHeightNarrow?: number
  }>(),
  {
    backdropUrl: null,
    posterUrl: null,
    layout: 'stacked',
    overview: null,
    cast: null,
    genres: null,
    backFallback: 'library',
    minHeight: 605,
    minHeightNarrow: 380,
  },
)

// The heights ride in as custom properties rather than plain inline styles so
// the narrow-viewport media query can still override them (inline always wins).
const heroStyle = computed(() => ({
  ...posterStyle(props.backdropUrl ?? props.posterUrl, props.title),
  '--hero-min': `${props.minHeight}px`,
  '--hero-min-narrow': `${props.minHeightNarrow}px`,
}))
const posterTile = computed(() => posterStyle(props.posterUrl, props.title))
</script>

<template>
  <div>
    <section class="hero" :style="heroStyle">
      <div class="arg-hatch hatch" />
      <div class="shade" />
      <BackButton class="hero-back" :fallback="backFallback" />
      <div class="body">
        <div v-if="layout === 'poster'" class="poster" :style="posterTile">
          <div class="poster-title">{{ title }}</div>
        </div>
        <div class="info">
          <h1>{{ title }}</h1>
          <div class="meta"><slot name="meta" /></div>
          <p v-if="overview" class="synopsis">{{ overview }}</p>
          <p v-if="cast?.length" class="cast">
            <span class="cast-label">Cast</span>{{ cast.join(', ') }}
          </p>
          <div v-if="genres?.length" class="tags">
            <span v-for="g in genres" :key="`g-${g}`" class="tag">{{ g }}</span>
          </div>
          <div class="actions"><slot name="actions" /></div>
          <!-- Anything that hangs below the buttons: a resume bar, a review flag. -->
          <slot name="extra" />
        </div>
      </div>
    </section>

    <!-- Everything under the hero: a related rail, season tabs and episodes. -->
    <slot />
  </div>
</template>

<style scoped>
.hero {
  position: relative;
  border-radius: var(--arg-r-xl);
  overflow: hidden;
  border: 1px solid var(--arg-line);
  min-height: var(--hero-min);
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
/* Quadrant 1: top-left of the hero, aligned with the body's 40px inset so it
   sits above the art, left of the title. */
.hero-back {
  position: absolute;
  top: 50px;
  left: 40px;
  z-index: 3;
}
.body {
  position: relative;
  /* The top padding reserves room for the back button (top:50 + 40h) so the
     title always clears it when tall content outgrows the hero's min-height. */
  padding: 104px 40px 36px;
  min-height: var(--hero-min);
  display: flex;
  gap: 30px;
  align-items: flex-end;
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
/* The meta row's vocabulary. It is only ever written by a caller filling the
   #meta slot, so the rules have to reach into slot content explicitly. */
.meta :slotted(.sep) {
  opacity: 0.4;
}
.meta :slotted(.badge) {
  padding: 2px 7px;
  border: 1px solid var(--arg-line-3);
  border-radius: 5px;
  font-size: 11px;
}
.meta :slotted(.kind) {
  color: var(--arg-accent);
}
/* These two are <p>, so they carry a UA margin-bottom. Zeroing it makes every
   gap in this column come from one explicit margin-top: the old markup had the
   film's paragraphs collapsing against their neighbour and the series' not
   (they were flex items, which never collapse), so the same rules spaced the
   two pages differently. */
.synopsis {
  margin: 18px 0 0;
  max-width: 620px;
  font: 400 15px/1.65 var(--arg-body);
  color: #c4c4bc;
}
.cast {
  margin: 14px 0 0;
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
.actions {
  margin-top: 22px;
  display: flex;
  gap: 12px;
  align-items: center;
  flex-wrap: wrap;
}
/* Keep the hero from dominating narrow viewports. */
@media (max-width: 720px) {
  .hero,
  .body {
    min-height: var(--hero-min-narrow);
  }
}
</style>
