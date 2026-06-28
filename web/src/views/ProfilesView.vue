<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api } from '@/api/client'
import { useSessionStore } from '@/stores/session'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type Profile = components['schemas']['ProfileSummary']
type Role = components['schemas']['Role']

const session = useSessionStore()
// Managing profiles is admin-only; the server enforces it too. Viewers reaching
// this screen just get an explanatory note instead of the management UI.
const isAdmin = computed(() => session.session?.role === 'admin')
const profiles = ref<Profile[]>([])
const loading = ref(true)

// One editor modal serves create (editing = null) and edit (editing = the row).
const editorOpen = ref(false)
const editing = ref<Profile | null>(null)
const formName = ref('')
const formRole = ref<Role>('viewer')
const deleteTarget = ref<Profile | null>(null)
const busy = ref(false)
const error = ref('')

function isSelf(p: Profile): boolean {
  return p.id === session.session?.userId
}

async function load(): Promise<void> {
  loading.value = true
  const { data } = await api.GET('/api/v1/auth/profiles')
  profiles.value = data ?? []
  loading.value = false
}

function openCreate(): void {
  editing.value = null
  formName.value = ''
  formRole.value = 'viewer'
  error.value = ''
  editorOpen.value = true
}

function openEdit(p: Profile): void {
  editing.value = p
  formName.value = p.name
  formRole.value = p.role
  error.value = ''
  editorOpen.value = true
}

function openDelete(p: Profile): void {
  deleteTarget.value = p
  error.value = ''
}

async function save(): Promise<void> {
  const name = formName.value.trim()
  if (!name) {
    error.value = 'Name is required.'
    return
  }
  busy.value = true
  error.value = ''
  const { error: e } = editing.value
    ? await api.PATCH('/api/v1/auth/profiles/{userId}', {
        params: { path: { userId: editing.value.id } },
        body: { name, role: formRole.value },
      })
    : await api.POST('/api/v1/auth/profiles', { body: { name, role: formRole.value } })
  busy.value = false
  if (e) {
    error.value = e.error
    return
  }
  editorOpen.value = false
  await load()
}

async function confirmDelete(): Promise<void> {
  const p = deleteTarget.value
  if (!p) return
  busy.value = true
  error.value = ''
  const { error: e } = await api.DELETE('/api/v1/auth/profiles/{userId}', {
    params: { path: { userId: p.id } },
  })
  busy.value = false
  if (e) {
    error.value = e.error
    return
  }
  deleteTarget.value = null
  await load()
}

onMounted(() => {
  setPage('Profiles')
  void load()
})
</script>

<template>
  <div class="profiles">
    <div v-if="!isAdmin" class="banner">
      <span class="icon">☖</span>
      <span>Only an admin can manage household profiles.</span>
    </div>

    <template v-else>
      <div class="banner">
        <span class="icon">☻</span>
        <span>
          Profiles are who's watching — each keeps its own home, history, and resume. Admins manage
          libraries, the Fleet, and the household; viewers just watch.
        </span>
      </div>

      <div class="list">
        <div v-for="p in profiles" :key="p.id" class="profile">
          <div class="avatar">{{ p.name.charAt(0).toUpperCase() }}</div>
          <div class="info">
            <div class="head">
              <span class="name">{{ p.name }}</span>
              <span class="tag" :class="p.role">{{ p.role }}</span>
              <span v-if="isSelf(p)" class="tag current">YOU</span>
            </div>
            <div class="meta">
              {{ p.deviceCount }} {{ p.deviceCount === 1 ? 'device' : 'devices' }}
            </div>
          </div>
          <div class="actions">
            <button class="btn" type="button" @click="openEdit(p)">Edit</button>
            <button v-if="!isSelf(p)" class="btn danger" type="button" @click="openDelete(p)">
              Delete
            </button>
          </div>
        </div>

        <div v-if="!loading && !profiles.length" class="empty">No profiles yet.</div>
      </div>

      <button class="add" type="button" @click="openCreate">+ Add profile</button>
    </template>

    <!-- Create / edit modal -->
    <div v-if="editorOpen" class="scrim" @click.self="editorOpen = false">
      <div class="modal">
        <h3>{{ editing ? 'Edit profile' : 'New profile' }}</h3>
        <input
          v-model="formName"
          class="field"
          type="text"
          placeholder="Profile name"
          autofocus
          @keydown.enter="save"
          @keydown.esc="editorOpen = false"
        />
        <div class="seg">
          <button type="button" :class="{ on: formRole === 'viewer' }" @click="formRole = 'viewer'">
            Viewer
          </button>
          <button type="button" :class="{ on: formRole === 'admin' }" @click="formRole = 'admin'">
            Admin
          </button>
        </div>
        <p class="hint">
          {{
            formRole === 'admin'
              ? 'Can manage libraries, devices, and profiles.'
              : 'Can browse and watch; no household settings.'
          }}
        </p>
        <p v-if="error" class="error">{{ error }}</p>
        <div class="modal-actions">
          <button class="btn" type="button" @click="editorOpen = false">Cancel</button>
          <button class="btn primary" type="button" :disabled="busy" @click="save">
            {{ editing ? 'Save' : 'Create' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Delete confirmation modal -->
    <div v-if="deleteTarget" class="scrim" @click.self="deleteTarget = null">
      <div class="modal">
        <h3>Delete “{{ deleteTarget.name }}”?</h3>
        <p class="modal-body">
          Its home, history, and resume points are removed.
          <template v-if="deleteTarget.deviceCount">
            <br /><strong
              >{{ deleteTarget.deviceCount }}
              {{ deleteTarget.deviceCount === 1 ? 'device' : 'devices' }}</strong
            >
            bound to it will keep working but drop to viewer access until reassigned.
          </template>
        </p>
        <p v-if="error" class="error">{{ error }}</p>
        <div class="modal-actions">
          <button class="btn" type="button" @click="deleteTarget = null">Cancel</button>
          <button class="btn danger" type="button" :disabled="busy" @click="confirmDelete">
            Delete
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.profiles {
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
.profile {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 18px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line);
  background: var(--arg-panel);
}
.avatar {
  width: 46px;
  height: 46px;
  flex: none;
  border-radius: 50%;
  background: rgba(201, 154, 78, 0.16);
  display: flex;
  align-items: center;
  justify-content: center;
  font: 700 19px var(--arg-display);
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
.tag.admin {
  background: rgba(201, 154, 78, 0.16);
  color: var(--arg-accent);
}
.tag.current {
  background: rgba(125, 191, 130, 0.16);
  color: var(--arg-green);
}
.meta {
  margin-top: 4px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-mute);
}
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
.add {
  margin-top: 18px;
  padding: 11px 18px;
  border-radius: var(--arg-r-sm);
  border: 1px dashed var(--arg-line-2);
  background: transparent;
  color: var(--arg-dim);
  font: 600 13px var(--arg-body);
  cursor: pointer;
}
.add:hover {
  border-color: var(--arg-accent);
  color: var(--arg-accent);
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
.seg {
  margin-top: 12px;
  display: flex;
  gap: 8px;
}
.seg button {
  flex: 1;
  padding: 9px 0;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: transparent;
  color: var(--arg-dim);
  font: 600 13px var(--arg-body);
  cursor: pointer;
}
.seg button.on {
  border-color: var(--arg-accent);
  background: rgba(201, 154, 78, 0.14);
  color: var(--arg-accent);
}
.hint {
  margin: 10px 0 0;
  font: 500 12px/1.4 var(--arg-body);
  color: var(--arg-mute);
}
.error {
  margin: 14px 0 0;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-danger);
}
.modal-actions {
  margin-top: 20px;
  display: flex;
  justify-content: flex-end;
  gap: 10px;
}
</style>
