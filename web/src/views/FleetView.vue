<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api } from '@/api/client'
import { formatRelative } from '@/lib/format'
import { useSessionStore } from '@/stores/session'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type Device = components['schemas']['Device']

const session = useSessionStore()
const devices = ref<Device[]>([])
const loading = ref(true)

async function load(): Promise<void> {
  loading.value = true
  const { data } = await api.GET('/api/v1/auth/devices')
  devices.value = (data ?? []).filter((d) => !d.revoked)
  loading.value = false
}

async function revoke(d: Device): Promise<void> {
  if (!confirm(`Retire "${d.name}" from the Fleet? It will need to pair again.`)) return
  await api.DELETE('/api/v1/auth/devices/{deviceId}', {
    params: { path: { deviceId: d.id } },
  })
  await load()
}

function isCurrent(d: Device): boolean {
  return d.id === session.session?.deviceId
}

function glyph(name: string): string {
  const n = name.toLowerCase()
  if (n.includes('iphone') || n.includes('phone') || n.includes('android')) return '▭'
  if (n.includes('ipad') || n.includes('tablet')) return '▢'
  if (n.includes('tv')) return '⛶'
  return '◳'
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
      <span
        >Every device in your Fleet shares one playhead. Retire any to drop it from sync.</span
      >
    </div>

    <div class="list">
      <div v-for="d in devices" :key="d.id" class="device">
        <div class="glyph">{{ glyph(d.name) }}</div>
        <div class="info">
          <div class="head">
            <span class="name">{{ d.name }}</span>
            <span v-if="isCurrent(d)" class="current">THIS DEVICE</span>
          </div>
          <div class="seen">last seen {{ formatRelative(d.lastSeenAt) }}</div>
        </div>
        <button v-if="!isCurrent(d)" class="revoke" type="button" @click="revoke(d)">Retire</button>
        <span v-else class="here">Active</span>
      </div>

      <div v-if="!loading && !devices.length" class="empty">No devices paired yet.</div>
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
.current {
  font: 700 9.5px var(--arg-display);
  letter-spacing: 0.08em;
  padding: 3px 8px;
  border-radius: 5px;
  background: var(--arg-accent-bg-2);
  color: var(--arg-accent-soft);
}
.seen {
  margin-top: 4px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-mute);
}
.revoke {
  padding: 9px 16px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-dim);
  font: 600 12.5px var(--arg-body);
  cursor: pointer;
}
.revoke:hover {
  border-color: #c96a4e;
  color: var(--arg-danger);
}
.here {
  font: 600 12.5px var(--arg-body);
  color: var(--arg-green);
}
.empty {
  padding: 30px;
  text-align: center;
  color: var(--arg-dim);
  font: 500 14px var(--arg-body);
}
</style>
