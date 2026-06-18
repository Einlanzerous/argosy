<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useSessionStore } from '@/stores/session'
import type { components } from '@/api/schema'

type UserProfile = components['schemas']['UserProfile']

const session = useSessionStore()
const router = useRouter()
const route = useRoute()

const step = ref<1 | 2>(1)
const username = ref('')
const password = ref('')
const deviceName = ref('')
const selectedProfile = ref('')
const profileList = ref<UserProfile[]>([])
const error = ref('')
const busy = ref(false)

async function signIn(): Promise<void> {
  error.value = ''
  busy.value = true
  try {
    const profiles = await session.login(username.value, password.value)
    if (profiles.length === 0) throw new Error('This account has no profiles yet.')
    profileList.value = profiles
    selectedProfile.value = profiles[0].id
    deviceName.value = defaultDeviceName()
    step.value = 2
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Sign in failed.'
  } finally {
    busy.value = false
  }
}

async function pair(): Promise<void> {
  error.value = ''
  busy.value = true
  try {
    await session.pairDevice(
      username.value,
      password.value,
      selectedProfile.value,
      deviceName.value.trim() || defaultDeviceName(),
    )
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
    await router.push(redirect)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Pairing failed.'
  } finally {
    busy.value = false
  }
}

function defaultDeviceName(): string {
  const ua = navigator.userAgent
  if (/iPhone/.test(ua)) return 'iPhone'
  if (/iPad/.test(ua)) return 'iPad'
  if (/Android/.test(ua)) return 'Android device'
  if (/Mac/.test(ua)) return 'Mac · this browser'
  if (/Win/.test(ua)) return 'Windows · this browser'
  return 'This browser'
}
</script>

<template>
  <div class="screen">
    <div class="card">
      <!-- brand panel -->
      <div class="brand">
        <img src="/argosy_logo_dark.png" alt="Argosy" />
        <div>
          <div class="eyebrow">Owned media · self-hosted</div>
          <div class="pitch">Your library. Your hardware.<br />Every screen in sync.</div>
          <div class="blurb">
            Start a film on the train, finish it on the big screen. Argosy keeps your whole fleet
            at the same frame.
          </div>
        </div>
        <div class="footnote">Stevedore is standing by to load the hold.</div>
      </div>

      <!-- form -->
      <div class="form">
        <div class="steps">
          <div class="step">
            <span class="num on">1</span>
            <span class="step-label on">Sign in</span>
          </div>
          <div class="rule" />
          <div class="step">
            <span class="num" :class="{ on: step === 2 }">2</span>
            <span class="step-label" :class="{ on: step === 2 }">Pair device</span>
          </div>
        </div>

        <form v-if="step === 1" @submit.prevent="signIn">
          <h1>Welcome aboard</h1>
          <p class="lede">Sign in to reach your library.</p>
          <label>Email</label>
          <input v-model="username" type="text" autocomplete="username" placeholder="you@argosy.local" />
          <label>Password</label>
          <input v-model="password" type="password" autocomplete="current-password" placeholder="••••••••" />
          <p v-if="error" class="error">{{ error }}</p>
          <button class="primary" type="submit" :disabled="busy">
            {{ busy ? 'Signing in…' : 'Sign in' }}
          </button>
          <p class="origin">Connected to <span>this server</span> · single origin</p>
        </form>

        <form v-else class="fade" @submit.prevent="pair">
          <h1>Name this device</h1>
          <p class="lede">
            It'll join your <span class="accent">Fleet</span> so you can resume across screens.
            Revoke it anytime.
          </p>
          <template v-if="profileList.length > 1">
            <label>Profile</label>
            <select v-model="selectedProfile">
              <option v-for="p in profileList" :key="p.id" :value="p.id">{{ p.name }}</option>
            </select>
          </template>
          <label>Device name</label>
          <input v-model="deviceName" type="text" placeholder="Studio Desktop" />
          <p v-if="error" class="error">{{ error }}</p>
          <button class="primary" type="submit" :disabled="busy">
            {{ busy ? 'Joining…' : 'Join the Fleet' }}
          </button>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.screen {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px;
  background: radial-gradient(120% 90% at 50% -10%, #20201d 0%, #171717 55%, #121211 100%);
}
.card {
  width: 100%;
  max-width: 880px;
  display: grid;
  grid-template-columns: 1.05fr 0.95fr;
  border: 1px solid var(--arg-line);
  border-radius: 14px;
  overflow: hidden;
  background: #1b1b19;
  box-shadow: 0 40px 120px rgba(0, 0, 0, 0.55);
}
.brand {
  padding: 48px 44px;
  background: linear-gradient(155deg, #1f1f1c, #161513);
  border-right: 1px solid var(--arg-line);
  display: flex;
  flex-direction: column;
  justify-content: space-between;
  min-height: 480px;
}
.brand img {
  width: 188px;
  height: auto;
}
.eyebrow {
  font: 600 11px var(--arg-display);
  letter-spacing: 0.22em;
  color: var(--arg-accent);
  text-transform: uppercase;
}
.pitch {
  margin-top: 14px;
  font: 700 27px/1.18 var(--arg-display);
  letter-spacing: -0.01em;
}
.blurb {
  margin-top: 14px;
  font: 400 14px/1.6 var(--arg-body);
  color: var(--arg-dim);
  max-width: 320px;
}
.footnote {
  font: 500 11px var(--arg-body);
  letter-spacing: 0.04em;
  color: var(--arg-faint-2);
}
.form {
  padding: 48px 44px;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.steps {
  display: flex;
  gap: 8px;
  align-items: center;
  margin-bottom: 26px;
}
.step {
  display: flex;
  align-items: center;
  gap: 9px;
}
.num {
  width: 22px;
  height: 22px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font: 700 11px var(--arg-display);
  background: transparent;
  color: var(--arg-mute);
  border: 1px solid var(--arg-line-3);
}
.num.on {
  background: var(--arg-accent);
  color: var(--arg-bg);
  border-color: transparent;
}
.step-label {
  font: 600 12px var(--arg-display);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--arg-mute);
}
.step-label.on {
  color: var(--arg-cream);
}
.rule {
  flex: 1;
  height: 1px;
  background: var(--arg-line-2);
}
.fade {
  animation: argFade 0.4s ease;
}
h1 {
  margin: 0;
  font: 800 24px var(--arg-display);
  letter-spacing: -0.01em;
}
.lede {
  margin: 6px 0 0;
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
input,
select {
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
input:focus,
select:focus {
  border-color: var(--arg-accent);
}
.primary {
  margin-top: 26px;
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
.origin {
  margin-top: 16px;
  text-align: center;
  font: 500 13px var(--arg-body);
  color: var(--arg-faint);
}
.origin span {
  color: var(--arg-dim);
}
@media (max-width: 720px) {
  .card {
    grid-template-columns: 1fr;
  }
  .brand {
    min-height: auto;
  }
}
</style>
