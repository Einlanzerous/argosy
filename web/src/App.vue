<script setup lang="ts">
import { ref, watch } from 'vue'
import { RouterView, useRoute } from 'vue-router'
import { FULLSCREEN_ROOT_ATTR, shouldExitFullscreen } from '@/lib/fullscreen'

const root = ref<HTMLElement | null>(null)
const route = useRoute()

// The wrapper outlives the keyed player remount, so it must be released by hand
// when the user leaves the player (back, a link) — see lib/fullscreen.ts.
watch(
  () => route.name,
  (name) => {
    if (shouldExitFullscreen(name, document.fullscreenElement, root.value)) {
      void document.exitFullscreen().catch(() => {})
    }
  },
)

const rootAttr = { [FULLSCREEN_ROOT_ATTR]: '' }
</script>

<template>
  <!-- ARGY-287: the stable fullscreen root. The player is fullscreened through
       this wrapper rather than its own .player div, because the keyed RouterView
       below destroys .player on every episode change and that would end
       fullscreen. -->
  <div ref="root" class="fullscreen-root" v-bind="rootAttr">
    <!-- Key the player by its full path so navigating episode→episode (auto-advance)
         remounts PlayerView, giving it a clean teardown/setup of the video element,
         HLS, and transcode session. Other routes key by their top-level record path
         so the AppShell stays mounted across child navigations. -->
    <RouterView v-slot="{ Component, route: r }">
      <component :is="Component" :key="r.name === 'player' ? r.fullPath : r.matched[0]?.path" />
    </RouterView>
  </div>
</template>

<style>
/* No box of its own, so layout is exactly what it was without the wrapper. */
.fullscreen-root {
  display: contents;
}
/* display: contents has no box to fullscreen; give it one only while fullscreen. */
.fullscreen-root:fullscreen {
  display: block;
  width: 100%;
  height: 100%;
  overflow: auto;
  background: var(--arg-ink);
}
</style>
