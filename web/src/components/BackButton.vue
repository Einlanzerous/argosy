<script setup lang="ts">
import { useRouter } from 'vue-router'

// The same back control the player uses (the little "‹"). Uses real history when
// there is some (preserves where the user came from), falling back to a sensible
// route on a cold/deep load where there's nothing to go back to.
const props = defineProps<{ fallback?: string }>()
const router = useRouter()

function back(): void {
  if (window.history.length > 1) router.back()
  else router.push({ name: props.fallback ?? 'home' })
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
