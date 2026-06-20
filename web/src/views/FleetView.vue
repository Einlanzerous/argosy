<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '@/api/client'
import { formatRelative } from '@/lib/format'
import { useSessionStore } from '@/stores/session'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type Device = components['schemas']['Device']

const router = useRouter()
const session = useSessionStore()
const devices = ref<Device[]>([])
const loading = ref(true)

// One modal serves both flows: rename (editable name) and retire (confirm).
const renameTarget = ref<Device | null>(null)
const renameValue = ref('')
const retireTarget = ref<Device | null>(null)
const busy = ref(false)

async function load(): Promise<void> {
  loading.value = true
  const { data } = await api.GET('/api/v1/auth/devices')
  devices.value = (data ?? []).filter((d) => !d.revoked)
  loading.value = false
}

function isCurrent(d: Device): boolean {
  return d.id === session.session?.deviceId
}

// Prefer the platform captured at registration; fall back to guessing from the name.
function glyph(d: Device): string {
  const k = (d.platform || d.name).toLowerCase()
  if (k.includes('iphone') || k.includes('phone') || k.includes('android')) return '▭'
  if (k.includes('ipad') || k.includes('tablet')) return '▢'
  if (k.includes('tv')) return '⛶'
  if (k.includes('web') || k.includes('browser')) return '◰'
  return '◳'
}

function openRename(d: Device): void {
  renameTarget.value = d
  renameValue.value = d.name
}

async function confirmRename(): Promise<void> {
  const d = renameTarget.value
  const next = renameValue.value.trim()
  if (!d || !next || next === d.name) {
    renameTarget.value = null
    return
  }
  busy.value = true
  await api.PATCH('/api/v1/auth/devices/{deviceId}', {
    params: { path: { deviceId: d.id } },
    body: { name: next },
  })
  busy.value = false
  renameTarget.value = null
  await load()
}

async function confirmRetire(): Promise<void> {
  const d = retireTarget.value
  if (!d) return
  busy.value = true
  await api.DELETE('/api/v1/auth/devices/{deviceId}', {
    params: { path: { deviceId: d.id } },
  })
  busy.value = false
  const wasCurrent = isCurrent(d)
  retireTarget.value = null
  if (wasCurrent) {
    // Retired the device we're on — its token is dead now; sign out + re-pair.
    session.logout()
    void router.push({ name: 'login' })
    return
  }
  await load()
}

onMounted(() => {
  setPage('Devices', 'Your Fleet · every screen that shares one playhead.')
  void load()
})
</script>

<template>
  <div class="fleet">
    <div class="banner">
      <span class="icon">⇄</span>
      <span>Every device in your Fleet shares one playhead. Retire any to drop it from sync.</span>
    </div>

    <div class="list">
      <div v-for="d in devices" :key="d.id" class="device">
        <div class="glyph">{{ glyph(d) }}</div>
        <div class="info">
          <div class="head">
            <span class="name">{{ d.name }}</span>
            <span v-if="d.platform" class="tag">{{ d.platform }}</span>
            <span v-if="isCurrent(d)" class="tag current">THIS DEVICE</span>
          </div>
          <div class="seen">
            <span v-if="d.userName">{{ d.userName }} · </span>last seen {{ formatRelative(d.lastSeenAt) }}
          </div>
        </div>
        <div class="actions">
          <button class="btn" type="button" @click="openRename(d)">Rename</button>
          <button class="btn danger" type="button" @click="retireTarget = d">Retire</button>
        </div>
      </div>

      <div v-if="!loading && !devices.length" class="empty">No devices paired yet.</div>
    </div>

    <!-- Rename modal -->
    <div v-if="renameTarget" class="scrim" @click.self="renameTarget = null">
      <div class="modal">
        <h3>Rename device</h3>
        <input
          v-model="renameValue"
          class="field"
          type="text"
          autofocus
          @keydown.enter="confirmRename"
          @keydown.esc="renameTarget = null"
        />
        <div class="modal-actions">
          <button class="btn" type="button" @click="renameTarget = null">Cancel</button>
          <button class="btn primary" type="button" :disabled="busy" @click="confirmRename">Save</button>
        </div>
      </div>
    </div>

    <!-- Retire confirmation modal -->
    <div v-if="retireTarget" class="scrim" @click.self="retireTarget = null">
      <div class="modal">
        <h3>Retire “{{ retireTarget.name }}”?</h3>
        <p class="modal-body">
          It will be dropped from the Fleet and must pair again to stream.
          <template v-if="isCurrent(retireTarget)">
            <br /><strong>This is the device you're using — you'll be signed out here.</strong>
          </template>
        </p>
        <div class="modal-actions">
          <button class="btn" type="button" @click="retireTarget = null">Cancel</button>
          <button class="btn danger" type="button" :disabled="busy" @click="confirmRetire">Retire</button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.fleet {
  max-width: 760px;
}
.banner {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 14px 18px;
  border-radius: var(--arg-r-lg);
  background: var(--arg-accent-bg);
  border: 1px solid rgba(201, 154, 78, 0.2);
  margin-bottom: 24px;
}
.banner .icon {
  font-size: 16px;
  color: var(--arg-accent);
}
.banner span:last-child {
  font: 500 13.5px var(--arg-body);
  color: var(--arg-accent-soft);
}
.list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.device {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 18px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line);
  background: var(--arg-panel);
}
.glyph {
  width: 46px;
  height: 46px;
  flex: none;
  border-radius: 11px;
  background: rgba(234, 234, 229, 0.06);
  display: flex;
  align-items: center;
  justify-content: center;
  font: 400 20px var(--arg-display);
  color: var(--arg-accent);
}
.info {
  flex: 1;
  min-width: 0;
}
.head {
  display: flex;
  align-items: center;
  gap: 9px;
}
.name {
  font: 700 15px var(--arg-display);
}
.tag {
  font: 700 9.5px var(--arg-display);
  letter-spacing: 0.08em;
  padding: 3px 8px;
  border-radius: 5px;
  background: rgba(234, 234, 229, 0.07);
  color: var(--arg-mute);
  text-transform: uppercase;
}
.tag.current {
  background: rgba(125, 191, 130, 0.16);
  color: var(--arg-green);
}
.seen {
  margin-top: 4px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-mute);
}
/* Both actions share one size/spacing so rows never shift. */
.actions {
  flex: none;
  display: flex;
  gap: 8px;
}
.btn {
  padding: 9px 16px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-dim);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.btn:hover {
  border-color: var(--arg-line);
  color: var(--arg-cream);
}
.btn.danger:hover {
  border-color: #c96a4e;
  color: var(--arg-danger);
}
.btn.primary {
  border-color: transparent;
  background: var(--arg-accent);
  color: var(--arg-bg);
}
.btn.primary:hover {
  background: var(--arg-accent-hi);
  color: var(--arg-bg);
}
.btn:disabled {
  opacity: 0.6;
  cursor: default;
}
.empty {
  padding: 30px;
  text-align: center;
  color: var(--arg-dim);
  font: 500 14px var(--arg-body);
}
.scrim {
  position: fixed;
  inset: 0;
  z-index: 50;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(12, 12, 11, 0.6);
  backdrop-filter: blur(3px);
}
.modal {
  width: min(420px, calc(100vw - 48px));
  padding: 22px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line);
  background: var(--arg-panel);
  box-shadow: 0 24px 60px rgba(0, 0, 0, 0.5);
}
.modal h3 {
  margin: 0;
  font: 700 17px var(--arg-display);
}
.modal-body {
  margin: 12px 0 0;
  font: 400 13.5px/1.5 var(--arg-body);
  color: var(--arg-dim);
}
.field {
  margin-top: 16px;
  width: 100%;
  padding: 11px 13px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: var(--arg-bg-2);
  color: var(--arg-cream);
  font: 500 14px var(--arg-body);
}
.field:focus {
  outline: none;
  border-color: var(--arg-accent);
}
.modal-actions {
  margin-top: 20px;
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
</style>
