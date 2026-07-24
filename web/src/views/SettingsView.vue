<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { api } from '@/api/client'
import { formatRelative } from '@/lib/format'
import { setPage } from '@/lib/page'
import { useSessionStore } from '@/stores/session'
import { getLibraries, createLibrary, deleteLibraryById, type Library } from '@/lib/manifest'
import {
  getPreferences,
  getUserPreferences,
  putPreferences,
  putUserPreferences,
  type DevicePreferences,
} from '@/lib/playback'
import type { components } from '@/api/schema'

type ScanStatus = components['schemas']['ScanStatus']

const sessionStore = useSessionStore()
// Triggering a re-scan is admin-only (the server enforces it too); viewers see
// status but not the control.
const isAdmin = computed(() => sessionStore.session?.role === 'admin')
const status = ref<ScanStatus | null>(null)
const message = ref('')
const triggering = ref(false)
let poll: ReturnType<typeof setInterval> | null = null

const libraries = ref<Library[]>([])
const newName = ref('')
const newPath = ref('')
const newKind = ref<'movie' | 'show' | 'mixed'>('mixed')
const addBusy = ref(false)
const addError = ref('')

async function loadLibraries(): Promise<void> {
  libraries.value = await getLibraries().catch(() => [])
}

type HomeLayout = 'focused' | 'discovery'
const homeLayout = ref<HomeLayout>('discovery')
async function loadUserPrefs(): Promise<void> {
  const p = await getUserPreferences().catch(() => null)
  if (p?.homeLayout === 'focused' || p?.homeLayout === 'discovery') homeLayout.value = p.homeLayout
}
async function setHomeLayout(v: HomeLayout): Promise<void> {
  if (homeLayout.value === v) return
  homeLayout.value = v
  await putUserPreferences({ homeLayout: v }).catch(() => {})
}

// Series auto-advance is a per-device playback preference (ARGY-89), default ON.
// We keep the full DevicePreferences around so toggling it writes back the whole
// object and never clobbers this device's subtitle/caption settings.
const devicePrefs = ref<DevicePreferences | null>(null)
const autoAdvance = ref(true)
async function loadDevicePrefs(): Promise<void> {
  const p = await getPreferences().catch(() => null)
  devicePrefs.value = p
  autoAdvance.value = p?.seriesAutoAdvance ?? true
}
async function setAutoAdvance(v: boolean): Promise<void> {
  if (autoAdvance.value === v) return
  autoAdvance.value = v
  const base: DevicePreferences = devicePrefs.value ?? { subtitleEnabled: false }
  const next: DevicePreferences = { ...base, seriesAutoAdvance: v }
  devicePrefs.value = next
  await putPreferences(next).catch(() => {})
}

// Self-serve change-password (ARGY-156). Any profile may rotate the household
// password by proving the current one; device tokens are independent of the
// password, so no device is signed out.
const curPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const pwBusy = ref(false)
const pwError = ref('')
const pwSuccess = ref(false)
const PW_MIN = 8
const pwTooShort = computed(() => newPassword.value !== '' && newPassword.value.length < PW_MIN)
const pwMismatch = computed(
  () => confirmPassword.value !== '' && newPassword.value !== confirmPassword.value,
)
const pwReady = computed(
  () =>
    curPassword.value !== '' &&
    newPassword.value.length >= PW_MIN &&
    newPassword.value === confirmPassword.value,
)

async function changePassword(): Promise<void> {
  if (!pwReady.value || pwBusy.value) return
  pwBusy.value = true
  pwError.value = ''
  pwSuccess.value = false
  const { error, response } = await api.POST('/api/v1/auth/password', {
    body: { currentPassword: curPassword.value, newPassword: newPassword.value },
  })
  pwBusy.value = false
  if (response.ok) {
    pwSuccess.value = true
    curPassword.value = ''
    newPassword.value = ''
    confirmPassword.value = ''
    return
  }
  if (response.status === 403) pwError.value = 'The current password is incorrect.'
  else pwError.value = (error as { error?: string })?.error ?? 'Could not change the password.'
}

async function addLibrary(): Promise<void> {
  const name = newName.value.trim()
  const path = newPath.value.trim()
  if (!name || !path || addBusy.value) return
  addBusy.value = true
  addError.value = ''
  const res = await createLibrary({ name, path, kind: newKind.value })
  addBusy.value = false
  if (!res.ok) {
    addError.value = res.error ?? 'Could not add the library.'
    return
  }
  newName.value = ''
  newPath.value = ''
  newKind.value = 'mixed'
  await loadLibraries()
  void rebuild() // scan + match the freshly-added library
}

async function removeLibrary(l: Library): Promise<void> {
  if (!confirm(`Remove “${l.name}” and its items from the Manifest? Files on disk are untouched.`))
    return
  await deleteLibraryById(l.id).catch(() => {})
  await loadLibraries()
  await refresh()
}

async function refresh(): Promise<void> {
  const { data } = await api.GET('/api/v1/scan/status')
  if (data) status.value = data
  // Poll while a sweep is running so progress stays live.
  if (data?.running && !poll) {
    poll = setInterval(refresh, 2000)
  } else if (!data?.running && poll) {
    clearInterval(poll)
    poll = null
  }
}

async function rebuild(): Promise<void> {
  triggering.value = true
  message.value = ''
  const { response } = await api.POST('/api/v1/scan')
  if (response.status === 202)
    message.value = 'Stevedore is loading the hold — rebuilding the Manifest.'
  else if (response.status === 409) message.value = 'A sweep is already running.'
  else message.value = 'Could not start a scan.'
  triggering.value = false
  await refresh()
}

onMounted(() => {
  setPage('Settings')
  void refresh()
  void loadLibraries()
  void loadUserPrefs()
  void loadDevicePrefs()
})
onUnmounted(() => {
  if (poll) clearInterval(poll)
})
</script>

<template>
  <div class="settings">
    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>Home layout</h2>
          <p>Choose how much the home page shows.</p>
        </div>
      </div>
      <div class="layout-opts">
        <button
          class="layout-opt"
          :class="{ on: homeLayout === 'focused' }"
          type="button"
          @click="setHomeLayout('focused')"
        >
          <span class="layout-name">Focused</span>
          <span class="layout-desc"
            >Just the essentials — Continue Watching, On Deck, Newly Arrived.</span
          >
        </button>
        <button
          class="layout-opt"
          :class="{ on: homeLayout === 'discovery' }"
          type="button"
          @click="setHomeLayout('discovery')"
        >
          <span class="layout-name">Discovery</span>
          <span class="layout-desc">Everything, plus your Vaults and genre rows for browsing.</span>
        </button>
      </div>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>Playback</h2>
          <p>How episodes behave on this device.</p>
        </div>
      </div>
      <div class="toggle-row">
        <div class="toggle-text">
          <span class="toggle-name">Auto-play next episode</span>
          <span class="toggle-desc">
            When a series episode ends, roll into the next one with an Up Next countdown you can
            cancel.
          </span>
        </div>
        <button
          class="switch"
          :class="{ on: autoAdvance }"
          type="button"
          role="switch"
          :aria-checked="autoAdvance"
          @click="setAutoAdvance(!autoAdvance)"
        >
          <span class="knob" />
        </button>
      </div>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>Account password</h2>
          <p>
            Change the password used to sign in and pair new devices. Devices already in the Fleet
            stay signed in.
          </p>
        </div>
      </div>
      <form class="pwform" @submit.prevent="changePassword">
        <input
          v-model="curPassword"
          type="password"
          autocomplete="current-password"
          placeholder="Current password"
        />
        <input
          v-model="newPassword"
          type="password"
          autocomplete="new-password"
          placeholder="New password"
        />
        <input
          v-model="confirmPassword"
          type="password"
          autocomplete="new-password"
          placeholder="Confirm new password"
        />
        <button type="submit" :disabled="pwBusy || !pwReady">
          {{ pwBusy ? 'Changing…' : 'Change password' }}
        </button>
      </form>
      <p v-if="pwTooShort" class="message err-msg">
        The new password must be at least {{ PW_MIN }} characters.
      </p>
      <p v-else-if="pwMismatch" class="message err-msg">The new passwords don't match.</p>
      <p v-if="pwError" class="message err-msg">{{ pwError }}</p>
      <p v-if="pwSuccess" class="message">Password changed.</p>
    </section>

    <section class="panel">
      <div class="panel-head">
        <div>
          <h2>Library scan</h2>
          <p>Stevedore re-sweeps your media so the Manifest stays current.</p>
        </div>
        <button
          v-if="isAdmin"
          class="rebuild"
          type="button"
          :disabled="triggering || status?.running"
          @click="rebuild"
        >
          <span>⟲</span> {{ status?.running ? 'Rebuilding…' : 'Rebuild the Manifest' }}
        </button>
        <span v-else class="viewer-note">Only an admin can rebuild the Manifest.</span>
      </div>

      <div class="state">
        <span class="badge" :class="{ live: status?.running }">
          <span class="dot" /> {{ status?.running ? 'Sweeping' : 'Idle' }}
        </span>
        <span v-if="status?.finishedAt" class="when"
          >last swept {{ formatRelative(status.finishedAt) }}</span
        >
      </div>

      <p v-if="message" class="message">{{ message }}</p>

      <div v-if="status?.libraries?.length" class="libs">
        <div v-for="l in status.libraries" :key="l.libraryId" class="lib">
          <span class="lib-name">{{ l.name }}</span>
          <span class="lib-counts">
            <span>{{ l.scanned }} scanned</span>
            <span v-if="l.errors" class="err">{{ l.errors }} errors</span>
            <span v-if="l.error" class="err" :title="l.error">unreadable root</span>
          </span>
        </div>
      </div>
      <p v-else class="hint">No libraries registered yet.</p>
    </section>

    <section v-if="isAdmin" class="panel">
      <div class="panel-head">
        <div>
          <h2>Libraries</h2>
          <p>Point Argosy at media folders on the server. Adding one kicks off a scan.</p>
        </div>
      </div>

      <div v-if="libraries.length" class="libs">
        <div v-for="l in libraries" :key="l.id" class="lib lib-manage">
          <div class="lib-info">
            <span class="lib-name">{{ l.name }}</span>
            <span class="lib-path">{{ l.rootPath }}</span>
          </div>
          <div class="lib-right">
            <span class="kind-badge">{{ l.kind }}</span>
            <button class="remove" type="button" @click="removeLibrary(l)">Remove</button>
          </div>
        </div>
      </div>

      <form class="addlib" @submit.prevent="addLibrary">
        <input v-model="newName" type="text" placeholder="Library name" />
        <input v-model="newPath" type="text" placeholder="/path/on/server" />
        <select v-model="newKind">
          <option value="mixed">Mixed</option>
          <option value="movie">Movies</option>
          <option value="show">Shows</option>
        </select>
        <button type="submit" :disabled="addBusy || !newName.trim() || !newPath.trim()">
          {{ addBusy ? 'Adding…' : 'Add & scan' }}
        </button>
      </form>
      <p v-if="addError" class="message err-msg">{{ addError }}</p>
    </section>
  </div>
</template>

<style scoped>
.settings {
  max-width: 760px;
}
.panel {
  padding: 24px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line);
  background: var(--arg-panel);
}
.panel-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 18px;
}
h2 {
  margin: 0;
  font: 700 18px var(--arg-display);
}
.panel-head p {
  margin: 6px 0 0;
  font: 400 13.5px var(--arg-body);
  color: var(--arg-dim);
}
.rebuild {
  flex: none;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 18px;
  border: none;
  border-radius: var(--arg-r);
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 13px var(--arg-display);
  cursor: pointer;
}
.rebuild:hover {
  background: var(--arg-accent-hi);
}
.rebuild:disabled {
  opacity: 0.6;
  cursor: default;
}
.viewer-note {
  flex: none;
  align-self: center;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-faint);
}
.state {
  margin-top: 20px;
  display: flex;
  align-items: center;
  gap: 12px;
}
.badge {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 6px 12px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  font: 600 12px var(--arg-body);
  color: var(--arg-dim);
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--arg-faint);
}
.badge.live {
  color: var(--arg-accent-soft);
  border-color: var(--arg-accent-line);
}
.badge.live .dot {
  background: var(--arg-accent);
  box-shadow: 0 0 8px var(--arg-accent);
}
.when {
  font: 500 12px var(--arg-body);
  color: var(--arg-faint);
}
.message {
  margin-top: 14px;
  font: 500 13px var(--arg-body);
  color: var(--arg-accent-soft);
}
.libs {
  margin-top: 20px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.lib {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 14px;
  border-radius: var(--arg-r-sm);
  background: var(--arg-bg-2);
  border: 1px solid var(--arg-line);
}
.lib-name {
  font: 600 13.5px var(--arg-body);
}
.lib-counts {
  display: flex;
  gap: 12px;
  font: 500 12px var(--arg-body);
  color: var(--arg-dim);
}
.err {
  color: var(--arg-danger);
}
.hint {
  margin-top: 18px;
  font: 500 13px var(--arg-body);
  color: var(--arg-faint);
}
.lib-manage {
  align-items: center;
}
.lib-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.lib-path {
  font: 500 12px var(--arg-mono, var(--arg-body));
  color: var(--arg-faint);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.lib-right {
  display: flex;
  align-items: center;
  gap: 12px;
}
.kind-badge {
  padding: 3px 9px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  color: var(--arg-soft);
  font: 600 10px var(--arg-display);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.remove {
  padding: 6px 12px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-soft);
  font: 600 12px var(--arg-body);
  cursor: pointer;
}
.remove:hover {
  border-color: #b4513a;
  color: #e9836c;
}
.addlib {
  margin-top: 18px;
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}
.addlib input,
.addlib select {
  padding: 10px 12px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-cream);
  font: 500 13px var(--arg-body);
  outline: none;
}
.addlib input {
  flex: 1;
  min-width: 160px;
}
.addlib input:focus {
  border-color: var(--arg-accent);
}
.addlib button {
  padding: 10px 18px;
  border-radius: var(--arg-r-sm);
  border: none;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 13px var(--arg-display);
  cursor: pointer;
}
.addlib button:disabled {
  opacity: 0.5;
  cursor: default;
}
.err-msg {
  color: #e9836c;
}
.pwform {
  margin-top: 18px;
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}
.pwform input {
  flex: 1;
  min-width: 180px;
  padding: 10px 12px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-cream);
  font: 500 13px var(--arg-body);
  outline: none;
}
.pwform input:focus {
  border-color: var(--arg-accent);
}
.pwform button {
  padding: 10px 18px;
  border-radius: var(--arg-r-sm);
  border: none;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 13px var(--arg-display);
  cursor: pointer;
}
.pwform button:disabled {
  opacity: 0.5;
  cursor: default;
}
.layout-opts {
  margin-top: 16px;
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}
.layout-opt {
  flex: 1;
  min-width: 220px;
  display: flex;
  flex-direction: column;
  gap: 5px;
  padding: 16px 18px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  text-align: left;
  cursor: pointer;
}
.layout-opt:hover {
  border-color: var(--arg-soft);
}
.layout-opt.on {
  border-color: var(--arg-accent);
  background: var(--arg-accent-bg-2);
}
.layout-name {
  font: 700 15px var(--arg-display);
  color: var(--arg-cream);
}
.layout-desc {
  font: 400 13px/1.5 var(--arg-body);
  color: var(--arg-dim);
}
.toggle-row {
  margin-top: 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 18px;
}
.toggle-text {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.toggle-name {
  font: 700 15px var(--arg-display);
  color: var(--arg-cream);
}
.toggle-desc {
  max-width: 520px;
  font: 400 13px/1.5 var(--arg-body);
  color: var(--arg-dim);
}
.switch {
  flex: none;
  position: relative;
  width: 48px;
  height: 28px;
  border-radius: 999px;
  border: 1px solid var(--arg-line-2);
  background: var(--arg-bg-2);
  cursor: pointer;
  transition:
    background 0.18s ease,
    border-color 0.18s ease;
}
.switch.on {
  background: var(--arg-accent);
  border-color: var(--arg-accent);
}
.switch .knob {
  position: absolute;
  top: 50%;
  left: 3px;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: var(--arg-cream);
  transform: translateY(-50%);
  transition: left 0.18s ease;
}
.switch.on .knob {
  left: 23px;
  background: var(--arg-bg);
}
</style>
