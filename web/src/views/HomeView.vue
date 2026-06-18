<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useSessionStore } from '@/stores/session'
import { api } from '@/api/client'

const session = useSessionStore()
const ping = ref('…')

onMounted(async () => {
  // Typed call generated from the OpenAPI spec.
  const { data } = await api.GET('/api/v1/ping')
  ping.value = data ? `${data.service} ${data.version} — ${data.status}` : 'unreachable'
})
</script>

<template>
  <main class="home">
    <img class="logo" src="/argosy_logo_light.png" alt="Argosy" width="360" height="100" />
    <p class="tagline">Your fleet, your manifest, your media.</p>
    <p class="ping">API: <code>{{ ping }}</code></p>
    <p class="hint">Scaffold ready — this home view is a placeholder for the Phase 2 web player.</p>
    <button type="button" @click="session.touch()">Heartbeat: {{ session.beats }}</button>
  </main>
</template>

<style scoped>
.home {
  max-width: 40rem;
  margin: 4rem auto;
  padding: 0 1rem;
}
.logo {
  display: block;
  width: min(360px, 80%);
  height: auto;
}
.tagline {
  color: #6b7280;
}
.ping code {
  background: #f3f4f6;
  padding: 0.15rem 0.35rem;
  border-radius: 0.25rem;
}
.hint {
  color: #9ca3af;
  font-size: 0.9rem;
}
button {
  margin-top: 1rem;
}
</style>
