import { api } from '@/api/client'
import type { components } from '@/api/schema'

export type Library = components['schemas']['Library']
export type MovieSummary = components['schemas']['MediaItemSummary']
export type SeriesSummary = components['schemas']['SeriesSummary']
export type SearchResults = components['schemas']['SearchResults']

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

// A "newly arrived" feed item — a film or a series (kind is "movie" | "series").
export type RecentItem = MovieSummary

// getRecent returns the unified, account-wide newly-arrived feed (films + series
// merged, newest first) — already cross-library, so no per-library fan-out.
export async function getRecent(limit = 24): Promise<RecentItem[]> {
  const { data } = await api.GET('/api/v1/recent', { params: { query: { limit } } })
  return data ?? []
}

// searchManifest runs the account-wide full-text search (titles, tags, genres,
// overviews), already grouped into films + series by the API. A blank query
// short-circuits to empty results so the caller needn't special-case it.
export async function searchManifest(q: string, limit = 8): Promise<SearchResults> {
  const query = q.trim()
  if (!query) return { movies: [], series: [] }
  const { data } = await api.GET('/api/v1/search', { params: { query: { q: query, limit } } })
  return data ?? { movies: [], series: [] }
}

// Tags surfaced as filter chips. "All" is the no-filter sentinel; the rest match
// the path-derived/override tags Stevedore writes (anime, etc.).
export const TAG_FILTERS = ['All', 'Anime', 'Sci-Fi', 'Drama', 'Action', 'Documentary', '4K']
