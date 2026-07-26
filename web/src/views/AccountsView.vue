<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { api } from '@/api/client'
import { useSessionStore } from '@/stores/session'
import { setPage } from '@/lib/page'
import type { components } from '@/api/schema'

type Account = components['schemas']['AccountSummary']

const session = useSessionStore()
// Account lifecycle is the instance owner's power (ARGY-86/167); the server
// enforces it too. Anyone else reaching this screen just gets a note.
const canManage = computed(() => session.canManageServer)
const accounts = ref<Account[]>([])
const loading = ref(true)

const deleteTarget = ref<Account | null>(null)
const resetTarget = ref<Account | null>(null)
// The generated password is shown exactly once, in this modal; it is never
// retrievable again (the server stores only the hash).
const resetResult = ref('')
const copied = ref(false)
const busy = ref(false)
const error = ref('')

function isSelf(a: Account): boolean {
  return a.id === session.session?.accountId
}

async function load(): Promise<void> {
  loading.value = true
  const { data } = await api.GET('/api/v1/auth/accounts')
  accounts.value = data ?? []
  loading.value = false
}

async function toggleDisabled(a: Account): Promise<void> {
  busy.value = true
  error.value = ''
  const { error: e } = await api.PATCH('/api/v1/auth/accounts/{accountId}', {
    params: { path: { accountId: a.id } },
    body: { disabled: !a.disabled },
  })
  busy.value = false
  if (e) {
    error.value = e.error
    return
  }
  await load()
}

function openReset(a: Account): void {
  resetTarget.value = a
  resetResult.value = ''
  copied.value = false
  error.value = ''
}

async function confirmReset(): Promise<void> {
  const a = resetTarget.value
  if (!a) return
  busy.value = true
  error.value = ''
  const { data, error: e } = await api.POST('/api/v1/auth/accounts/{accountId}/password-reset', {
    params: { path: { accountId: a.id } },
  })
  busy.value = false
  if (e || !data) {
    error.value = e?.error ?? 'Reset failed.'
    return
  }
  resetResult.value = data.generatedPassword
}

async function copyPassword(): Promise<void> {
  try {
    await navigator.clipboard.writeText(resetResult.value)
    copied.value = true
  } catch {
    // Clipboard is gated to secure origins; the password stays visible to
    // copy by hand.
  }
}

function openDelete(a: Account): void {
  deleteTarget.value = a
  error.value = ''
}

async function confirmDelete(): Promise<void> {
  const a = deleteTarget.value
  if (!a) return
  busy.value = true
  error.value = ''
  const { error: e } = await api.DELETE('/api/v1/auth/accounts/{accountId}', {
    params: { path: { accountId: a.id } },
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
  setPage('Accounts')
  void load()
})
</script>

<template>
  <div class="accounts">
    <div v-if="!canManage" class="banner">
      <span class="icon">⚿</span>
      <span>Only the account that owns this server can manage its accounts.</span>
    </div>

    <template v-else>
      <div class="banner">
        <span class="icon">⚿</span>
        <span>
          Accounts are the households on this server — each signs in with its own email and manages
          its own profiles. Disabling keeps everything but blocks sign-in; deleting removes the
          household for good.
        </span>
      </div>

      <p v-if="error && !deleteTarget && !resetTarget" class="error">{{ error }}</p>

      <div class="list">
        <div v-for="a in accounts" :key="a.id" class="account" :class="{ off: a.disabled }">
          <div class="avatar">{{ a.name.charAt(0).toUpperCase() }}</div>
          <div class="info">
            <div class="head">
              <span class="name">{{ a.name }}</span>
              <span v-if="a.isOwner" class="tag owner">OWNER</span>
              <span v-if="isSelf(a)" class="tag current">YOU</span>
              <span v-if="a.disabled" class="tag disabled">DISABLED</span>
            </div>
            <div class="meta">
              {{ a.email }} · {{ a.profileCount }}
              {{ a.profileCount === 1 ? 'profile' : 'profiles' }}
            </div>
          </div>
          <div v-if="!a.isOwner" class="actions">
            <button class="btn" type="button" :disabled="busy" @click="openReset(a)">
              Reset password
            </button>
            <button class="btn" type="button" :disabled="busy" @click="toggleDisabled(a)">
              {{ a.disabled ? 'Enable' : 'Disable' }}
            </button>
            <button class="btn danger" type="button" :disabled="busy" @click="openDelete(a)">
              Delete
            </button>
          </div>
        </div>

        <div v-if="!loading && !accounts.length" class="empty">No accounts yet.</div>
      </div>
    </template>

    <!-- Password-reset modal: confirm, then show the one-time password. -->
    <div v-if="resetTarget" class="scrim" @click.self="resetTarget = null">
      <div class="modal">
        <template v-if="!resetResult">
          <h3>Reset password for “{{ resetTarget.name }}”?</h3>
          <p class="modal-body">
            Their current password stops working and a fresh one is generated. You'll see it exactly
            once — hand it over and have them change it. All their devices are signed out and must
            pair again with the new password.
          </p>
          <p v-if="error" class="error">{{ error }}</p>
          <div class="modal-actions">
            <button class="btn" type="button" @click="resetTarget = null">Cancel</button>
            <button class="btn primary" type="button" :disabled="busy" @click="confirmReset">
              Reset
            </button>
          </div>
        </template>
        <template v-else>
          <h3>New password for “{{ resetTarget.name }}”</h3>
          <p class="modal-body">
            This is shown only once — Argosy keeps just the hash. Copy it now.
          </p>
          <div class="secret">
            <code>{{ resetResult }}</code>
            <button class="btn" type="button" @click="copyPassword">
              {{ copied ? 'Copied ✓' : 'Copy' }}
            </button>
          </div>
          <div class="modal-actions">
            <button class="btn primary" type="button" @click="resetTarget = null">Done</button>
          </div>
        </template>
      </div>
    </div>

    <!-- Delete confirmation modal -->
    <div v-if="deleteTarget" class="scrim" @click.self="deleteTarget = null">
      <div class="modal">
        <h3>Delete “{{ deleteTarget.name }}”?</h3>
        <p class="modal-body">
          The whole household goes with it — {{ deleteTarget.profileCount }}
          {{ deleteTarget.profileCount === 1 ? 'profile' : 'profiles' }}, its devices, watch
          history, and vaults. This can't be undone. If they might come back, disable instead.
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
.accounts {
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
.account {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 18px;
  border-radius: var(--arg-r-lg);
  border: 1px solid var(--arg-line);
  background: var(--arg-panel);
}
.account.off {
  opacity: 0.6;
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
.tag.owner {
  background: rgba(201, 154, 78, 0.16);
  color: var(--arg-accent);
}
.tag.current {
  background: rgba(125, 191, 130, 0.16);
  color: var(--arg-green);
}
.tag.disabled {
  background: rgba(201, 106, 78, 0.16);
  color: var(--arg-danger);
}
.meta {
  margin-top: 4px;
  font: 500 12.5px var(--arg-body);
  color: var(--arg-mute);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
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
  width: min(440px, calc(100vw - 48px));
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
.secret {
  margin-top: 16px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 14px;
  border-radius: var(--arg-r-sm);
  border: 1px solid var(--arg-line-2);
  background: var(--arg-bg-2);
}
.secret code {
  flex: 1;
  font: 600 13.5px var(--arg-mono, monospace);
  color: var(--arg-cream);
  word-break: break-all;
  user-select: all;
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
