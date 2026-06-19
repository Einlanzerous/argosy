import { reactive } from 'vue'

// Global UI state for the chrome — currently the animated "Search the Manifest"
// overlay, which can be opened from the top bar, the Browse button, or the
// Library header.
export const ui = reactive<{ searchOpen: boolean }>({ searchOpen: false })

export function openSearch(): void {
  ui.searchOpen = true
}

export function closeSearch(): void {
  ui.searchOpen = false
}
