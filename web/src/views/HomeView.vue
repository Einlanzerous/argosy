<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useSessionStore } from '@/stores/session'

const session = useSessionStore()
const ping = ref('…')

interface PingResponse {
  service: string
  status: string
  version: string
}

onMounted(async () => {
  try {
    const res = await fetch('/api/v1/ping')
    const body = (await res.json()) as PingResponse
    ping.value = `${body.service} ${body.version} — ${body.status}`
  } catch {
    ping.value = 'unreachable'
  }
})
</script>

<template>
  <main class="home">
    <h1>⚓ Argosy</h1>
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
