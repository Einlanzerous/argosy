<script setup lang="ts">
import { computed } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { posterStyle } from '@/lib/poster'

const props = defineProps<{
  title: string
  subtitle?: string
  kind?: string
  anime?: boolean
  posterUrl?: string | null
  to: RouteLocationRaw
  width?: number
}>()

const style = computed(() => posterStyle(props.posterUrl, props.title))
</script>

<template>
  <RouterLink class="card" :to="to" :style="width ? { width: `${width}px` } : undefined">
    <div class="poster" :style="style">
      <div class="arg-hatch overlay" />
      <span v-if="kind" class="kind">{{ kind }}</span>
      <span v-if="anime" class="anime">ANIME</span>
      <div class="meta">
        <div class="title">{{ title }}</div>
        <div v-if="subtitle" class="sub">{{ subtitle }}</div>
      </div>
    </div>
  </RouterLink>
</template>

<style scoped>
.card {
  display: block;
  cursor: pointer;
  transition: transform 0.18s ease;
}
.card:hover {
  transform: translateY(-4px);
}
.card:focus-visible {
  outline: 2px solid var(--arg-accent);
  outline-offset: 4px;
  border-radius: 9px;
}
.poster {
  position: relative;
  aspect-ratio: 2 / 3;
  border-radius: var(--arg-r-sm);
  overflow: hidden;
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4);
  border: 1px solid rgba(234, 234, 229, 0.06);
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
.anime {
  position: absolute;
  top: 9px;
  right: 9px;
  font: 700 9px var(--arg-display);
  letter-spacing: 0.08em;
  padding: 3px 7px;
  border-radius: 5px;
  background: rgba(201, 154, 78, 0.2);
  color: var(--arg-accent-soft);
}
.meta {
  position: absolute;
  left: 12px;
  right: 12px;
  bottom: 14px;
}
.title {
  font: 800 16px/1.05 var(--arg-display);
}
.sub {
  margin-top: 3px;
  font: 500 11px var(--arg-body);
  color: rgba(234, 234, 229, 0.5);
}
</style>
