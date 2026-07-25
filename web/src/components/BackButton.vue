<script setup lang="ts">
import { useRouter } from 'vue-router'

// The same back control the player uses (the little "‹"). Uses real history when
// there is some (preserves where the user came from), falling back to a sensible
// route on a cold/deep load where there's nothing to go back to.
const props = defineProps<{ fallback?: string }>()
const router = useRouter()

function back(): void {
  // history.length counts entries from before the app too (a fresh tab starts
  // above 1), so it can't tell "navigated here in-app" from a deep link. Vue
  // Router records the previous in-app location in history.state.back — null
  // means this page is the entry point and back should go to the fallback.
  if (window.history.state?.back != null) router.back()
  else void router.push({ name: props.fallback ?? 'home' })
}
</script>

<template>
  <button class="back" type="button" aria-label="Back" @click="back">‹</button>
</template>

<style scoped>
.back {
  width: 40px;
  height: 40px;
  border-radius: var(--arg-r);
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.6);
  backdrop-filter: blur(6px);
  color: var(--arg-cream);
  font: 700 18px var(--arg-display);
  cursor: pointer;
}
.back:hover {
  border-color: var(--arg-accent);
}
</style>
