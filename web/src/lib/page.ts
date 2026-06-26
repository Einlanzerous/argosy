// Sets the browser tab title. The v2 chrome has no in-app title bar, so there's
// nothing else to drive — just the document title.
export function setPage(title: string): void {
  document.title = title ? `${title} · Argosy` : 'Argosy'
}
