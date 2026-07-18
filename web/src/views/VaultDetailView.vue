<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import type { RouteLocationRaw } from 'vue-router'
import PosterCard from '@/components/PosterCard.vue'
import BackButton from '@/components/BackButton.vue'
import {
  getVault,
  updateVault,
  deleteVault,
  removeFromVault,
  reorderVault,
  type VaultDetail,
  type VaultEntry,
} from '@/lib/vaults'
import { setPage } from '@/lib/page'

const route = useRoute()
const router = useRouter()
const vault = ref<VaultDetail | null>(null)
const items = ref<VaultEntry[]>([])
const loading = ref(true)
const editingName = ref(false)
const nameDraft = ref('')

const vaultId = computed(() => String(route.params.id))

async function load(): Promise<void> {
  loading.value = true
  vault.value = await getVault(vaultId.value).catch(() => null)
  items.value = vault.value?.items ?? []
  loading.value = false
  setPage(vault.value?.name ?? 'Vault')
}

function entryTo(e: VaultEntry): RouteLocationRaw {
  return e.kind === 'series'
    ? { name: 'series', params: { id: e.id } }
    : { name: 'movie', params: { id: e.id } }
}

async function remove(e: VaultEntry): Promise<void> {
  await removeFromVault(vaultId.value, e.entryId).catch(() => {})
  items.value = items.value.filter((x) => x.entryId !== e.entryId)
}

async function move(i: number, dir: -1 | 1): Promise<void> {
  const j = i + dir
  if (j < 0 || j >= items.value.length) return
  const next = items.value.slice()
  ;[next[i], next[j]] = [next[j], next[i]]
  items.value = next
  await reorderVault(
    vaultId.value,
    next.map((e) => e.entryId),
  ).catch(() => {})
}

function startRename(): void {
  nameDraft.value = vault.value?.name ?? ''
  editingName.value = true
}
async function saveName(): Promise<void> {
  const name = nameDraft.value.trim()
  editingName.value = false
  if (!name || !vault.value || name === vault.value.name) return
  const v = await updateVault(vaultId.value, { name }).catch(() => null)
  if (v && vault.value) vault.value.name = v.name
  setPage(name)
}

async function toggleShared(): Promise<void> {
  if (!vault.value) return
  const next = !vault.value.shared
  const v = await updateVault(vaultId.value, { shared: next }).catch(() => null)
  if (v && vault.value) vault.value.shared = v.shared
}

async function destroy(): Promise<void> {
  if (!vault.value || !confirm(`Delete the vault “${vault.value.name}”? This can't be undone.`))
    return
  await deleteVault(vaultId.value).catch(() => {})
  void router.push({ name: 'vaults' })
}

onMounted(load)
watch(vaultId, load)
</script>

<template>
  <div class="vault">
    <div class="topbar"><BackButton fallback="vaults" /></div>

    <template v-if="vault">
      <header class="head">
        <div class="title-row">
          <input
            v-if="editingName"
            v-model="nameDraft"
            class="name-edit"
            type="text"
            @keyup.enter="saveName"
            @blur="saveName"
          />
          <h1 v-else>{{ vault.name }}</h1>
          <span v-if="vault.shared" class="badge">Shared</span>
        </div>
        <div class="sub">
          {{ vault.isOwner ? 'Yours' : `by ${vault.ownerName}` }} · {{ items.length }}
          {{ items.length === 1 ? 'item' : 'items' }}
        </div>
        <div v-if="vault.isOwner" class="manage">
          <button type="button" @click="startRename">Rename</button>
          <button type="button" @click="toggleShared">
            {{ vault.shared ? 'Make private' : 'Share with household' }}
          </button>
          <button type="button" class="danger" @click="destroy">Delete</button>
        </div>
      </header>

      <div v-if="items.length" class="grid">
        <div v-for="(e, i) in items" :key="e.entryId" class="cell">
          <PosterCard
            :width="158"
            :title="e.title"
            :subtitle="e.year ? String(e.year) : undefined"
            :kind="e.kind === 'series' ? 'Series' : 'Film'"
            :genre="e.genres?.[0]"
            :rating="e.rating"
            :poster-url="e.posterUrl"
            :to="entryTo(e)"
          />
          <div v-if="vault.canEdit" class="controls">
            <button type="button" :disabled="i === 0" title="Move up" @click="move(i, -1)">
              ↑
            </button>
            <button
              type="button"
              :disabled="i === items.length - 1"
              title="Move down"
              @click="move(i, 1)"
            >
              ↓
            </button>
            <button type="button" class="rm" title="Remove" @click="remove(e)">✕</button>
          </div>
        </div>
      </div>

      <div v-else class="empty">
        <h2>This vault is empty</h2>
        <p>Open any film or series and use “Add to Vault” to start filling it.</p>
      </div>
    </template>

    <div v-else-if="!loading" class="empty"><h2>Vault not found</h2></div>
  </div>
</template>

<style scoped>
.vault {
  padding: 84px 40px 90px;
}
.topbar {
  margin-bottom: 14px;
}
.title-row {
  display: flex;
  align-items: center;
  gap: 14px;
}
h1 {
  margin: 0;
  font: 800 clamp(28px, 3.2vw, 38px) var(--arg-display);
  letter-spacing: -0.02em;
}
.name-edit {
  font: 800 32px var(--arg-display);
  background: transparent;
  border: none;
  border-bottom: 2px solid var(--arg-accent);
  color: var(--arg-cream);
  outline: none;
}
.badge {
  padding: 4px 10px;
  border-radius: 999px;
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent);
  font: 700 10px var(--arg-display);
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.sub {
  margin-top: 6px;
  font: 500 13px var(--arg-body);
  color: var(--arg-dim);
}
.manage {
  margin-top: 14px;
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}
.manage button {
  padding: 8px 14px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.manage button:hover {
  border-color: var(--arg-accent);
  color: var(--arg-cream);
}
.manage button.danger:hover {
  border-color: #b4513a;
  color: #e9836c;
}
.grid {
  margin-top: 26px;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(158px, 1fr));
  gap: 24px 18px;
}
.cell {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.controls {
  display: flex;
  gap: 6px;
}
.controls button {
  flex: 1;
  padding: 5px 0;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: rgba(20, 20, 19, 0.6);
  color: var(--arg-soft);
  font-size: 13px;
  cursor: pointer;
}
.controls button:disabled {
  opacity: 0.35;
  cursor: default;
}
.controls button.rm:hover {
  border-color: #b4513a;
  color: #e9836c;
}
.empty {
  margin-top: 60px;
  text-align: center;
  color: var(--arg-dim);
}
.empty h2 {
  font: 800 22px var(--arg-display);
}
.empty p {
  margin-top: 8px;
  font: 400 14px var(--arg-body);
}
</style>
