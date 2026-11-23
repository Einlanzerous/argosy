<script setup lang="ts">
import { nextTick, ref } from 'vue'
import { listVaults, createVault, addToVault, type Vault } from '@/lib/vaults'

// Exactly one of these identifies the title being filed.
const props = defineProps<{ movieId?: string; seriesId?: string }>()

const triggerEl = ref<HTMLElement | null>(null)
const menuEl = ref<HTMLElement | null>(null)
const newInput = ref<HTMLInputElement | null>(null)
// The menu is a popover="auto": the browser gives it top-layer stacking, Escape,
// click-outside dismissal and focus return to the trigger. `open` mirrors its
// state for aria-expanded. The trigger toggles it declaratively via popovertarget
// (a click on the trigger while open is then a close, not a dismiss-then-reopen).
const menuId = `atv-menu-${Math.random().toString(36).slice(2, 8)}`
const open = ref(false)
const vaults = ref<Vault[]>([])
const loaded = ref(false)
const flash = ref('')
const creating = ref(false)
const newName = ref('')
// The menu is teleported to <body> and positioned with fixed coords so it
// escapes the detail hero's `overflow: hidden` (which otherwise clips it).
// Anchor positioning is not in Firefox, so the coordinates stay JS-computed.

const MENU_WIDTH = 248

// Only vaults the profile may curate (its own, or any shared household one).
function editable(v: Vault): boolean {
  return v.isOwner || v.shared
}

// Runs just before the popover is shown, so it never paints at 0,0.
function onBeforeToggle(e: Event): void {
  if ((e as ToggleEvent).newState !== 'open') return
  const r = triggerEl.value?.getBoundingClientRect()
  if (r && menuEl.value) {
    const left = Math.min(r.left, window.innerWidth - MENU_WIDTH - 12)
    menuEl.value.style.top = `${r.bottom + 6}px`
    menuEl.value.style.left = `${Math.max(12, left)}px`
  }
}

async function onToggle(e: Event): Promise<void> {
  open.value = (e as ToggleEvent).newState === 'open'
  if (!open.value) {
    creating.value = false
    return
  }
  if (!loaded.value) {
    vaults.value = (await listVaults().catch(() => [])).filter(editable)
    loaded.value = true
  }
}

function closeMenu(): void {
  menuEl.value?.hidePopover()
}

function startCreating(): void {
  creating.value = true
  void nextTick(() => newInput.value?.focus())
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
  closeMenu()
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
  closeMenu()
}
</script>

<template>
  <button
    ref="triggerEl"
    class="arg-ghost"
    type="button"
    :popovertarget="menuId"
    :aria-expanded="open"
  >
    <span aria-hidden="true">＋</span> {{ flash || 'Add to Vault' }}
  </button>
  <Teleport to="body">
    <div
      :id="menuId"
      ref="menuEl"
      class="atv-menu"
      popover="auto"
      @beforetoggle="onBeforeToggle"
      @toggle="onToggle"
    >
      <div class="menu-head">Add to…</div>
      <button v-for="v in vaults" :key="v.id" class="row" type="button" @click="add(v)">
        <span class="nm">{{ v.name }}</span>
        <span v-if="v.shared" class="sh">shared</span>
      </button>
      <div v-if="loaded && !vaults.length" class="none">No vaults yet</div>
      <form v-if="creating" class="new" @submit.prevent="createAndAdd">
        <input ref="newInput" v-model="newName" type="text" placeholder="New vault name…" />
        <button type="submit">Create</button>
      </form>
      <button v-else class="row create" type="button" @click="startCreating">
        <span aria-hidden="true">＋</span> New vault…
      </button>
    </div>
  </Teleport>
</template>

<style scoped>
.atv-menu {
  /* Override the UA popover box (centred, inset: 0); top/left are set inline. */
  position: fixed;
  inset: auto;
  margin: 0;
  width: 248px;
  color: var(--arg-cream);
  overflow: visible;
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
