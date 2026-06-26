<script setup lang="ts">
import { ref } from 'vue'
import { listVaults, createVault, addToVault, type Vault } from '@/lib/vaults'

// Exactly one of these identifies the title being filed.
const props = defineProps<{ movieId?: string; seriesId?: string }>()

const triggerEl = ref<HTMLElement | null>(null)
const open = ref(false)
const vaults = ref<Vault[]>([])
const loaded = ref(false)
const flash = ref('')
const creating = ref(false)
const newName = ref('')
// The menu is teleported to <body> and positioned with fixed coords so it
// escapes the detail hero's `overflow: hidden` (which otherwise clips it).
const menuStyle = ref<{ top: string; left: string }>({ top: '0px', left: '0px' })

const MENU_WIDTH = 248

// Only vaults the profile may curate (its own, or any shared household one).
function editable(v: Vault): boolean {
  return v.isOwner || v.shared
}

async function toggle(): Promise<void> {
  open.value = !open.value
  if (!open.value) return
  const r = triggerEl.value?.getBoundingClientRect()
  if (r) {
    const left = Math.min(r.left, window.innerWidth - MENU_WIDTH - 12)
    menuStyle.value = { top: `${r.bottom + 6}px`, left: `${Math.max(12, left)}px` }
  }
  if (!loaded.value) {
    vaults.value = (await listVaults().catch(() => [])).filter(editable)
    loaded.value = true
  }
}

function ref_(): { movieId?: string; seriesId?: string } {
  return props.seriesId ? { seriesId: props.seriesId } : { movieId: props.movieId }
}

function flashAdded(name: string): void {
  flash.value = `Added to ${name}`
  setTimeout(() => {
    if (flash.value === `Added to ${name}`) flash.value = ''
  }, 1800)
}

async function add(v: Vault): Promise<void> {
  await addToVault(v.id, ref_()).catch(() => {})
  flashAdded(v.name)
  open.value = false
}

async function createAndAdd(): Promise<void> {
  const name = newName.value.trim()
  if (!name) return
  const v = await createVault({ name }).catch(() => null)
  if (v) {
    await addToVault(v.id, ref_()).catch(() => {})
    flashAdded(v.name)
  }
  newName.value = ''
  creating.value = false
  loaded.value = false
  open.value = false
}
</script>

<template>
  <button ref="triggerEl" class="trigger" type="button" @click="toggle">
    <span>＋</span> {{ flash || 'Add to Vault' }}
  </button>
  <Teleport to="body">
    <template v-if="open">
      <div class="atv-scrim" @click="open = false" />
      <div class="atv-menu" :style="menuStyle">
        <div class="menu-head">Add to…</div>
        <button v-for="v in vaults" :key="v.id" class="row" type="button" @click="add(v)">
          <span class="nm">{{ v.name }}</span>
          <span v-if="v.shared" class="sh">shared</span>
        </button>
        <div v-if="loaded && !vaults.length" class="none">No vaults yet</div>
        <form v-if="creating" class="new" @submit.prevent="createAndAdd">
          <input v-model="newName" type="text" placeholder="New vault name…" autofocus />
          <button type="submit">Create</button>
        </form>
        <button v-else class="row create" type="button" @click="creating = true">
          ＋ New vault…
        </button>
      </div>
    </template>
  </Teleport>
</template>

<style scoped>
/* Matches the secondary "Start Over"/ghost buttons on the detail pages. */
.trigger {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 13px 22px;
  border-radius: var(--arg-r);
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.4);
  color: var(--arg-cream);
  font: 600 14px var(--arg-body);
  cursor: pointer;
}
.trigger:hover {
  border-color: var(--arg-accent);
}
.atv-scrim {
  position: fixed;
  inset: 0;
  z-index: 200;
}
.atv-menu {
  position: fixed;
  z-index: 201;
  width: 248px;
  padding: 8px;
  border-radius: var(--arg-r);
  border: 1px solid var(--arg-line-2);
  background: var(--arg-panel-2);
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.5);
}
.menu-head {
  padding: 6px 10px;
  font: 700 10px var(--arg-display);
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--arg-faint);
}
.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  width: 100%;
  padding: 9px 10px;
  border: none;
  border-radius: var(--arg-r-sm);
  background: none;
  color: var(--arg-cream);
  font: 500 14px var(--arg-body);
  text-align: left;
  cursor: pointer;
}
.row:hover {
  background: var(--arg-panel);
}
.sh {
  font: 600 10px var(--arg-body);
  color: var(--arg-accent);
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
.create {
  color: var(--arg-accent);
  font-weight: 600;
}
.none {
  padding: 9px 10px;
  font: 500 13px var(--arg-body);
  color: var(--arg-faint);
}
.new {
  display: flex;
  gap: 6px;
  padding: 6px;
}
.new input {
  flex: 1;
  min-width: 0;
  padding: 8px 10px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-cream);
  font: 500 13px var(--arg-body);
  outline: none;
}
.new button {
  padding: 8px 12px;
  border-radius: var(--arg-r-sm);
  border: none;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 12px var(--arg-display);
  cursor: pointer;
}
</style>
