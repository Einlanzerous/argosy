import { defineStore } from 'pinia'
import { ref } from 'vue'

// Placeholder for the cross-device session / play-state store (Phases 2 & 4).
export const useSessionStore = defineStore('session', () => {
  const beats = ref(0)

  function touch() {
    beats.value++
  }

  return { beats, touch }
})
