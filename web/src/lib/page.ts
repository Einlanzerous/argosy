import { reactive } from 'vue'

// Shared page header. The v2 chrome has no persistent title bar, so this mainly
// drives the browser tab title; the reactive is kept for any in-app use.
export const page = reactive<{ title: string; subtitle: string }>({
  title: '',
  subtitle: '',
})

export function setPage(title: string, subtitle = ''): void {
  page.title = title
  page.subtitle = subtitle
  document.title = title ? `${title} · Argosy` : 'Argosy'
}
