<script setup lang="ts">
import { ref } from 'vue'
import { addLabel, removeLabel, type LabelRef } from '@/lib/labels'

const props = defineProps<{ movieId?: string; seriesId?: string; initial?: string[] }>()

const labels = ref<string[]>([...(props.initial ?? [])])
const adding = ref(false)
const draft = ref('')
const busy = ref(false)

function ref_(): LabelRef {
  return props.seriesId ? { seriesId: props.seriesId } : { movieId: props.movieId }
}

async function add(): Promise<void> {
  const v = draft.value.trim()
  if (!v || busy.value) return
  busy.value = true
  labels.value = await addLabel(ref_(), v).catch(() => labels.value)
  busy.value = false
  draft.value = ''
  adding.value = false
}

async function remove(label: string): Promise<void> {
  labels.value = labels.value.filter((l) => l !== label)
  await removeLabel(ref_(), label).catch(() => {})
}
</script>

<template>
  <div class="labels">
    <span class="lbl-head">Your labels</span>
    <div class="lbl-row">
      <span v-for="l in labels" :key="l" class="lbl">
        {{ l }}
        <button class="x" type="button" title="Remove" @click="remove(l)">✕</button>
      </span>
      <form v-if="adding" class="add" @submit.prevent="add">
        <input
          v-model="draft"
          type="text"
          placeholder="label…"
          autofocus
          @keyup.escape="adding = false"
          @blur="adding = false"
        />
      </form>
      <button v-else class="add-btn" type="button" @click="adding = true">＋ Label</button>
    </div>
  </div>
</template>

<style scoped>
.labels {
  display: flex;
  align-items: baseline;
  gap: 12px;
  flex-wrap: wrap;
  margin-top: 14px;
}
.lbl-head {
  font: 700 10px var(--arg-display);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--arg-faint);
}
.lbl-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.lbl {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 5px 6px 5px 12px;
  border-radius: 999px;
  border: 1px solid rgba(201, 154, 78, 0.5);
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent);
  font: 600 12.5px var(--arg-body);
}
.lbl .x {
  display: inline-flex;
  border: none;
  background: none;
  color: var(--arg-accent);
  font-size: 11px;
  cursor: pointer;
  opacity: 0.7;
}
.lbl .x:hover {
  opacity: 1;
}
.add-btn {
  padding: 6px 14px;
  border-radius: 999px;
  border: 1px dashed var(--arg-line-3);
  background: transparent;
  color: var(--arg-soft);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.add-btn:hover {
  border-color: var(--arg-accent);
  color: var(--arg-cream);
}
.add input {
  padding: 6px 12px;
  border-radius: 999px;
  border: 1px solid var(--arg-accent);
  background: var(--arg-panel-2);
  color: var(--arg-cream);
  font: 500 12.5px var(--arg-body);
  outline: none;
  width: 130px;
}
</style>
