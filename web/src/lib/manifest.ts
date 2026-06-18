import { api } from '@/api/client'
import type { components } from '@/api/schema'

export type Library = components['schemas']['Library']
export type MovieSummary = components['schemas']['MediaItemSummary']
export type SeriesSummary = components['schemas']['SeriesSummary']

export type MovieSort = 'title' | 'added' | 'year'
export type SeriesSort = 'title' | 'year'

// The browse API is per-library; the UI presents one unified Manifest, so these
// helpers fan out across every library the account owns and merge the results.

export async function getLibraries(): Promise<Library[]> {
  const { data } = await api.GET('/api/v1/libraries')
  return data ?? []
}

export async function getMovies(
  opts: { tag?: string; sort?: MovieSort } = {},
  libraries?: Library[],
): Promise<MovieSummary[]> {
  const libs = libraries ?? (await getLibraries())
  const pages = await Promise.all(
    libs.map((l) =>
      api.GET('/api/v1/libraries/{libraryId}/movies', {
        params: {
          path: { libraryId: l.id },
          query: { limit: 200, sort: opts.sort, tag: opts.tag || undefined },
        },
      }),
    ),
  )
  return pages.flatMap((p) => p.data?.items ?? [])
}

export async function getSeries(
  opts: { tag?: string; sort?: SeriesSort } = {},
  libraries?: Library[],
): Promise<SeriesSummary[]> {
  const libs = libraries ?? (await getLibraries())
  const pages = await Promise.all(
    libs.map((l) =>
      api.GET('/api/v1/libraries/{libraryId}/series', {
        params: {
          path: { libraryId: l.id },
          query: { limit: 200, sort: opts.sort, tag: opts.tag || undefined },
        },
      }),
    ),
  )
  return pages.flatMap((p) => p.data?.items ?? [])
}

// Tags surfaced as filter chips. "All" is the no-filter sentinel; the rest match
// the path-derived/override tags Stevedore writes (anime, etc.).
export const TAG_FILTERS = ['All', 'Anime', 'Sci-Fi', 'Drama', 'Action', 'Documentary', '4K']
