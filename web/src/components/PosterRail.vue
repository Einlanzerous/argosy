<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'

defineProps<{
  label: string
  viewAllTo?: RouteLocationRaw
  hint?: string
}>()
</script>

<template>
  <section class="rail">
    <header>
      <h2>{{ label }}</h2>
      <RouterLink v-if="viewAllTo" class="all" :to="viewAllTo">View all →</RouterLink>
      <span v-else-if="hint" class="hint">{{ hint }}</span>
    </header>
    <div class="track">
      <slot />
    </div>
  </section>
</template>

<style scoped>
.rail {
  margin-top: 40px;
}
header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  margin-bottom: 16px;
}
h2 {
  margin: 0;
  font: 700 16px var(--arg-display);
}
.all {
  background: none;
  border: none;
  color: var(--arg-mute);
  font: 600 12px var(--arg-body);
  cursor: pointer;
}
.all:hover {
  color: var(--arg-accent);
}
.hint {
  font: 500 12px var(--arg-body);
  color: var(--arg-faint);
}
.track {
  display: flex;
  gap: 18px;
  overflow-x: auto;
  padding-bottom: 8px;
}
</style>
