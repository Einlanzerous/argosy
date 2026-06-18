import { reactive } from 'vue'

// Shared page header (title + subtitle) the AppShell topbar renders. Each view
// sets it on mount so the chrome stays in sync without prop-drilling.
export const page = reactive<{ title: string; subtitle: string }>({
  title: '',
  subtitle: '',
})

export function setPage(title: string, subtitle = ''): void {
  page.title = title
  page.subtitle = subtitle
}
