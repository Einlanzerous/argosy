import { api } from '@/api/client'

// The calling profile's custom labels on a film or series. Exactly one of
// movieId / seriesId identifies the title.
export type LabelRef = { movieId?: string; seriesId?: string }

export async function listMyLabels(): Promise<string[]> {
  const { data } = await api.GET('/api/v1/labels')
  return data ?? []
}

// addLabel returns the title's labels after the add.
export async function addLabel(ref: LabelRef, label: string): Promise<string[]> {
  if (ref.seriesId) {
    const { data } = await api.POST('/api/v1/series/{seriesId}/labels', {
      params: { path: { seriesId: ref.seriesId } },
      body: { label },
    })
    return data ?? []
  }
  const { data } = await api.POST('/api/v1/items/{itemId}/labels', {
    params: { path: { itemId: ref.movieId ?? '' } },
    body: { label },
  })
  return data ?? []
}

export async function removeLabel(ref: LabelRef, label: string): Promise<void> {
  if (ref.seriesId) {
    await api.DELETE('/api/v1/series/{seriesId}/labels/{label}', {
      params: { path: { seriesId: ref.seriesId, label } },
    })
  } else {
    await api.DELETE('/api/v1/items/{itemId}/labels/{label}', {
      params: { path: { itemId: ref.movieId ?? '', label } },
    })
  }
}
