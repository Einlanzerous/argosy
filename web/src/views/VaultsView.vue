<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { listVaults, createVault, type Vault } from '@/lib/vaults'
import { setPage } from '@/lib/page'

const router = useRouter()
const vaults = ref<Vault[]>([])
const loading = ref(true)
const creating = ref(false)
const newName = ref('')
const newShared = ref(false)
const busy = ref(false)

async function load(): Promise<void> {
  vaults.value = await listVaults().catch(() => [])
  loading.value = false
}

async function create(): Promise<void> {
  const name = newName.value.trim()
  if (!name || busy.value) return
  busy.value = true
  const v = await createVault({ name, shared: newShared.value }).catch(() => null)
  busy.value = false
  if (v) {
    newName.value = ''
    newShared.value = false
    creating.value = false
    void router.push({ name: 'vault', params: { id: v.id } })
  }
}

onMounted(() => {
  setPage('Vaults')
  void load()
})
</script>

<template>
  <div class="vaults">
    <header class="head">
      <div>
        <div class="eyebrow">The Hold</div>
        <h1>Vaults</h1>
        <div class="count">Your curated cargo — collections of films &amp; series</div>
      </div>
      <button class="new" type="button" @click="creating = !creating">＋ New Vault</button>
    </header>

    <form v-if="creating" class="creator" @submit.prevent="create">
      <input v-model="newName" type="text" placeholder="Vault name…" autofocus />
      <label class="shared"><input v-model="newShared" type="checkbox" /> Share with household</label>
      <button class="go" type="submit" :disabled="busy || !newName.trim()">Create</button>
    </form>

    <div v-if="vaults.length" class="grid">
      <RouterLink
        v-for="v in vaults"
        :key="v.id"
        class="card"
        :to="{ name: 'vault', params: { id: v.id } }"
      >
        <div class="card-top">
          <span class="vault-name">{{ v.name }}</span>
          <span v-if="v.shared" class="badge">Shared</span>
        </div>
        <div class="card-sub">{{ v.itemCount }} {{ v.itemCount === 1 ? 'item' : 'items' }}</div>
        <div class="card-foot">{{ v.isOwner ? 'Yours' : `by ${v.ownerName}` }}</div>
      </RouterLink>
    </div>

    <div v-else-if="!loading" class="empty">
      <h2>No vaults yet</h2>
      <p>Create a vault to start curating collections — favorites, a rewatch list, anything.</p>
    </div>
  </div>
</template>

<style scoped>
.vaults {
  padding: 104px 40px 90px;
}
.head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
  flex-wrap: wrap;
}
.eyebrow {
  font: 700 11px var(--arg-display);
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--arg-accent);
}
h1 {
  margin: 10px 0 0;
  font: 800 clamp(30px, 3.4vw, 40px) var(--arg-display);
  letter-spacing: -0.02em;
}
.count {
  margin-top: 4px;
  font: 500 13px var(--arg-body);
  color: var(--arg-dim);
}
.new {
  padding: 11px 20px;
  border-radius: 999px;
  border: 1px solid var(--arg-accent);
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 13px var(--arg-display);
  cursor: pointer;
}
.creator {
  margin-top: 22px;
  display: flex;
  align-items: center;
  gap: 14px;
  flex-wrap: wrap;
  padding: 16px 18px;
  border: 1px solid var(--arg-line-2);
  border-radius: var(--arg-r-lg);
  background: rgba(20, 20, 19, 0.5);
}
.creator input[type='text'] {
  flex: 1;
  min-width: 220px;
  padding: 10px 14px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-cream);
  font: 500 14px var(--arg-body);
  outline: none;
}
.creator input[type='text']:focus {
  border-color: var(--arg-accent);
}
.shared {
  display: flex;
  align-items: center;
  gap: 7px;
  font: 500 13px var(--arg-body);
  color: var(--arg-soft);
}
.go {
  padding: 10px 18px;
  border-radius: var(--arg-r-sm);
  border: none;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 13px var(--arg-display);
  cursor: pointer;
}
.go:disabled {
  opacity: 0.5;
  cursor: default;
}
.grid {
  margin-top: 28px;
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 16px;
}
.card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 20px;
  min-height: 120px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line-2);
  background: linear-gradient(158deg, #221f1b, #15130f);
  cursor: pointer;
}
.card:hover {
  border-color: var(--arg-accent);
}
.card-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}
.vault-name {
  font: 800 18px var(--arg-display);
  color: var(--arg-cream);
}
.badge {
  flex: none;
  padding: 3px 9px;
  border-radius: 999px;
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent);
  font: 700 10px var(--arg-display);
  letter-spacing: 0.08em;
  text-transform: uppercase;
}
.card-sub {
  font: 600 13px var(--arg-body);
  color: var(--arg-soft);
}
.card-foot {
  margin-top: auto;
  font: 500 12px var(--arg-body);
  color: var(--arg-faint);
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
