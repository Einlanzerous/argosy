<script setup lang="ts">
import { ref } from 'vue'
import { api } from '@/api/client'

// Approve a TV's pairing code (ARGY-112). The web user is already signed in
// (this route is auth-gated), so approving links the TV to their account.
const code = ref('')
const deviceName = ref('Living Room TV')
const busy = ref(false)
const error = ref('')
const done = ref(false)

async function approve(): Promise<void> {
  error.value = ''
  const c = code.value.trim().toUpperCase()
  if (c.length < 6) {
    error.value = 'Enter the 6-character code shown on your TV.'
    return
  }
  busy.value = true
  try {
    const { response } = await api.POST('/api/v1/auth/link/{code}/approve', {
      params: { path: { code: c } },
      body: { deviceName: deviceName.value.trim() || undefined },
    })
    if (!response.ok) {
      error.value =
        response.status === 404
          ? "That code wasn't found — it may have expired. Start over on your TV."
          : response.status === 409
            ? 'That code was already used.'
            : 'Could not link the TV. Please try again.'
      return
    }
    done.value = true
  } catch {
    error.value = 'Could not reach the server.'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="link">
    <div class="card">
      <div class="eyebrow">Fleet · Add a screen</div>
      <h1>Link a TV</h1>

      <template v-if="!done">
        <p class="lede">Enter the code shown on your TV to add it to your Fleet.</p>
        <form @submit.prevent="approve">
          <label>Pairing code</label>
          <input
            v-model="code"
            class="code"
            type="text"
            maxlength="6"
            autocapitalize="characters"
            autocomplete="off"
            placeholder="ABC123"
          />
          <label>TV name</label>
          <input v-model="deviceName" type="text" placeholder="Living Room TV" />
          <p v-if="error" class="error">{{ error }}</p>
          <button class="primary" type="submit" :disabled="busy">
            {{ busy ? 'Linking…' : 'Link this TV' }}
          </button>
        </form>
      </template>

      <template v-else>
        <p class="lede">
          <span class="accent">Linked.</span> Your TV will connect in a moment — no need to type
          anything on it.
        </p>
        <button class="primary" type="button" @click="((done = false), (code = ''))">
          Link another
        </button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.link {
  min-height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px;
}
.card {
  width: 100%;
  max-width: 420px;
  padding: 36px 34px;
  border: 1px solid var(--arg-line);
  border-radius: 14px;
  background: #1b1b19;
  box-shadow: 0 30px 80px rgba(0, 0, 0, 0.45);
}
.eyebrow {
  font: 600 11px var(--arg-display);
  letter-spacing: 0.22em;
  color: var(--arg-accent);
  text-transform: uppercase;
}
h1 {
  margin: 10px 0 0;
  font: 800 26px var(--arg-display);
  letter-spacing: -0.01em;
}
.lede {
  margin: 8px 0 0;
  font: 400 14px/1.55 var(--arg-body);
  color: var(--arg-dim);
}
.accent {
  color: var(--arg-accent);
}
label {
  display: block;
  margin-top: 18px;
  font: 600 11px var(--arg-display);
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: #8a8a82;
}
input {
  margin-top: 7px;
  width: 100%;
  padding: 13px 14px;
  border-radius: 9px;
  border: 1px solid var(--arg-line-2);
  background: #141413;
  color: var(--arg-cream);
  font: 500 15px var(--arg-body);
  outline: none;
}
input:focus {
  border-color: var(--arg-accent);
}
.code {
  font: 700 22px var(--arg-display);
  letter-spacing: 0.3em;
  text-transform: uppercase;
}
.primary {
  margin-top: 24px;
  width: 100%;
  padding: 14px;
  border: none;
  border-radius: 9px;
  background: var(--arg-accent);
  color: var(--arg-bg);
  font: 700 15px var(--arg-display);
  cursor: pointer;
}
.primary:hover {
  background: var(--arg-accent-hi);
}
.primary:disabled {
  opacity: 0.6;
  cursor: default;
}
.error {
  margin: 16px 0 0;
  font: 500 13px var(--arg-body);
  color: var(--arg-danger);
}
</style>
