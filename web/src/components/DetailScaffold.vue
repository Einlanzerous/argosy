<script setup lang="ts">
import { computed } from 'vue'
import BackButton from '@/components/BackButton.vue'
import { posterStyle } from '@/lib/poster'

// The shared anatomy of a detail page (ARGY-111), drawn as the app's full-bleed
// hero (ARGY-214): the backdrop runs edge to edge beneath the floating bar,
// scrims carry the text, and the art fades into the divider that separates the
// hero from whatever the caller puts below it. The type-specific parts — a
// film's playback controls, a series' seasons and episodes — arrive as slots.
const props = withDefaults(
  defineProps<{
    title: string
    /** Hero art. Prefers the landscape backdrop, falling back to the poster. */
    backdropUrl?: string | null
    /** Only the hero's fallback art now; the portrait tile it used to fill was
        dropped in ARGY-214 — it duplicated the backdrop behind it. */
    posterUrl?: string | null
    overview?: string | null
    cast?: string[] | null
    genres?: string[] | null
    /** Where the back button lands on a cold/deep load with no history. */
    backFallback?: string
  }>(),
  {
    backdropUrl: null,
    posterUrl: null,
    overview: null,
    cast: null,
    genres: null,
    backFallback: 'library',
  },
)

const heroStyle = computed(() => posterStyle(props.backdropUrl ?? props.posterUrl, props.title))
</script>

<template>
  <div>
    <section class="hero" :style="heroStyle">
      <div class="arg-hatch hatch" />
      <div class="arg-hero-shade-l" />
      <div class="arg-hero-shade-b" />
      <BackButton class="hero-back" :fallback="backFallback" />
      <div class="body">
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
    </section>

    <!-- Everything under the hero: a related rail, season tabs and episodes.
         The route is full-bleed, so the page's side padding lives here. -->
    <div class="below"><slot /></div>
  </div>
</template>

<style scoped>
.hero {
  position: relative;
  /* Viewport-relative so the showcase keeps its proportion on a phone and on
     the TV, rather than being a pixel height tuned to one desktop. 86vh lands
     near the intended ~35% over the old fixed 605px on a 1080p display (whose
     browser viewport is ~950px, not 1080), while staying under a full screen
     so the divider below stays in view and shows there is more to scroll to. */
  min-height: 86vh;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  overflow: hidden;
  /* The line the art fades down onto, splitting hero from content below. */
  border-bottom: 1px solid var(--arg-line);
}
.hatch {
  position: absolute;
  inset: 0;
}
/* Clear of the floating bar (fixed, ~84px tall) now that the hero starts at the
   top of the viewport instead of below the shell's padding. */
.hero-back {
  position: absolute;
  top: 96px;
  left: 40px;
  z-index: 3;
}
.body {
  position: relative;
  z-index: 2;
  /* Top padding keeps the title clear of the back button when long copy
     outgrows the hero; the column is bottom-aligned until then. */
  padding: 136px 40px 64px;
  /* Holds the copy inside the left scrim, where it stays legible. */
  max-width: 760px;
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
   gap in this column come from one explicit margin-top. */
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
.below {
  padding: 0 40px 90px;
}
</style>
