import { api } from '@/api/client'
import type { components } from '@/api/schema'

export type Vault = components['schemas']['Vault']
export type VaultDetail = components['schemas']['VaultDetail']
export type VaultEntry = components['schemas']['VaultEntry']

export async function listVaults(): Promise<Vault[]> {
  const { data } = await api.GET('/api/v1/vaults')
  return data ?? []
}

export async function getVault(id: string): Promise<VaultDetail | null> {
  const { data } = await api.GET('/api/v1/vaults/{vaultId}', { params: { path: { vaultId: id } } })
  return data ?? null
}

export async function createVault(body: {
  name: string
  description?: string
  shared?: boolean
}): Promise<Vault | null> {
  const { data } = await api.POST('/api/v1/vaults', {
    body: { ...body, shared: body.shared ?? false },
  })
  return data ?? null
}

export async function updateVault(
  id: string,
  body: { name?: string; description?: string | null; shared?: boolean },
): Promise<Vault | null> {
  const { data } = await api.PATCH('/api/v1/vaults/{vaultId}', {
    params: { path: { vaultId: id } },
    body,
  })
  return data ?? null
}

export async function deleteVault(id: string): Promise<void> {
  await api.DELETE('/api/v1/vaults/{vaultId}', { params: { path: { vaultId: id } } })
}

// addToVault adds exactly one of a film (movieId) or series (seriesId).
export async function addToVault(
  id: string,
  ref: { movieId?: string; seriesId?: string },
): Promise<VaultEntry | null> {
  const { data } = await api.POST('/api/v1/vaults/{vaultId}/items', {
    params: { path: { vaultId: id } },
    body: ref,
  })
  return data ?? null
}

export async function removeFromVault(id: string, entryId: string): Promise<void> {
  await api.DELETE('/api/v1/vaults/{vaultId}/items/{entryId}', {
    params: { path: { vaultId: id, entryId } },
  })
}

export async function reorderVault(id: string, entryIds: string[]): Promise<void> {
  await api.PUT('/api/v1/vaults/{vaultId}/order', {
    params: { path: { vaultId: id } },
    body: { entryIds },
  })
}
