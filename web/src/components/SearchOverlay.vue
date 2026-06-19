<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import type { RouteLocationRaw } from 'vue-router'
import { closeSearch } from '@/lib/ui'

const router = useRouter()
const input = ref<HTMLInputElement | null>(null)
const query = ref('')

const browse: { label: string; icon: string; to: RouteLocationRaw }[] = [
  { label: 'Movies', icon: '▦', to: { name: 'library', query: { kind: 'movies' } } },
  { label: 'Shows', icon: '▥', to: { name: 'library', query: { kind: 'series' } } },
  { label: 'Anime', icon: '◆', to: { name: 'library', query: { tag: 'Anime' } } },
  { label: 'Documentary', icon: '❖', to: { name: 'library', query: { tag: 'Documentary' } } },
  { label: '4K', icon: '◇', to: { name: 'library', query: { tag: '4K' } } },
]

function go(to: RouteLocationRaw): void {
  closeSearch()
  void router.push(to)
}

function submit(): void {
  // Free-text search isn't backed yet; Enter opens the full Manifest.
  go({ name: 'library' })
}

function onKey(e: KeyboardEvent): void {
  if (e.key === 'Escape') closeSearch()
}

onMounted(() => {
  window.addEventListener('keydown', onKey)
  input.value?.focus()
})
onUnmounted(() => window.removeEventListener('keydown', onKey))
</script>

<template>
  <div class="scrim" @click.self="closeSearch">
    <div class="panel">
      <div class="eyebrow">The Manifest</div>
      <div class="prompt">What are we watching?</div>
      <div class="field">
        <span class="icon">⌕</span>
        <input
          ref="input"
          v-model="query"
          type="text"
          placeholder="Search titles, genres, tags…"
          @keyup.enter="submit"
        />
      </div>
      <div class="chips">
        <button v-for="b in browse" :key="b.label" class="chip" type="button" @click="go(b.to)">
          <span class="chip-icon">{{ b.icon }}</span> {{ b.label }}
        </button>
      </div>
      <div class="hint">Press a tag to open the Manifest · full-text search arrives soon</div>
    </div>
  </div>
</template>

<style scoped>
.scrim {
  position: fixed;
  inset: 0;
  z-index: 60;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px;
  background: rgba(10, 10, 9, 0.82);
  backdrop-filter: blur(10px);
  animation: argFade 0.28s ease;
}
.panel {
  width: 100%;
  max-width: 640px;
  text-align: center;
  animation: argRise 0.32s cubic-bezier(0.16, 1, 0.3, 1) both;
}
.eyebrow {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.22em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
.prompt {
  margin-top: 14px;
  font: 800 clamp(32px, 4.4vw, 46px) var(--arg-display);
  letter-spacing: -0.02em;
}
.field {
  margin-top: 28px;
  position: relative;
}
.field .icon {
  position: absolute;
  left: 20px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--arg-accent);
  font-size: 21px;
}
.field input {
  width: 100%;
  padding: 20px 22px 20px 56px;
  border-radius: 14px;
  border: 1px solid rgba(201, 154, 78, 0.4);
  background: var(--arg-panel-2);
  color: var(--arg-cream);
  font: 500 18px var(--arg-body);
  outline: none;
}
.field input:focus {
  border-color: var(--arg-accent);
}
.chips {
  margin-top: 24px;
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  justify-content: center;
}
.chip {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 11px 20px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: var(--arg-panel);
  color: #e4e4dc;
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.chip:hover {
  border-color: var(--arg-accent);
  background: #221f1b;
}
.chip-icon {
  color: var(--arg-accent);
  font-size: 13px;
}
.hint {
  margin-top: 26px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-faint);
}
</style>
