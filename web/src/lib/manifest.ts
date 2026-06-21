import { api } from '@/api/client'
import type { components } from '@/api/schema'

export type Library = components['schemas']['Library']
export type MovieSummary = components['schemas']['MediaItemSummary']
export type SeriesSummary = components['schemas']['SeriesSummary']
export type SearchResults = components['schemas']['SearchResults']

export type MovieSort = 'title' | 'added' | 'year' | 'rating'
export type SeriesSort = 'title' | 'year' | 'rating'
export type WatchedState = 'watched' | 'unwatched' | 'in_progress'

// Facet filters shared by the movie + series browse helpers. All optional;
// omitted/empty fields impose no constraint.
export type BrowseFilter = {
  tag?: string
  genres?: string[]
  ratingMin?: number
  watched?: WatchedState
  yearFrom?: number
  yearTo?: number
}

// Genres offered by the filter panel — the TMDB names Stevedore now stores.
export const GENRES = [
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'Horror',
  'Mystery',
  'Romance',
  'Science Fiction',
  'Thriller',
  'War',
  'Western',
]

// Real labels/tags Stevedore derives from the path layout — distinct from genres.
export const LABELS = ['Anime']

function filterQuery(f: BrowseFilter) {
  return {
    tag: f.tag || undefined,
    genre: f.genres && f.genres.length ? f.genres : undefined,
    rating_min: f.ratingMin || undefined,
    watched: f.watched || undefined,
    year_from: f.yearFrom || undefined,
    year_to: f.yearTo || undefined,
  }
}

// The browse API is per-library; the UI presents one unified Manifest, so these
// helpers fan out across every library the account owns and merge the results.

export async function getLibraries(): Promise<Library[]> {
  const { data } = await api.GET('/api/v1/libraries')
  return data ?? []
}

export async function getMovies(
  opts: { sort?: MovieSort } & BrowseFilter = {},
  libraries?: Library[],
): Promise<MovieSummary[]> {
  const libs = libraries ?? (await getLibraries())
  const pages = await Promise.all(
    libs.map((l) =>
      api.GET('/api/v1/libraries/{libraryId}/movies', {
        params: {
          path: { libraryId: l.id },
          query: { limit: 200, sort: opts.sort, ...filterQuery(opts) },
        },
      }),
    ),
  )
  return pages.flatMap((p) => p.data?.items ?? [])
}

export async function getSeries(
  opts: { sort?: SeriesSort } & BrowseFilter = {},
  libraries?: Library[],
): Promise<SeriesSummary[]> {
  const libs = libraries ?? (await getLibraries())
  const pages = await Promise.all(
    libs.map((l) =>
      api.GET('/api/v1/libraries/{libraryId}/series', {
        params: {
          path: { libraryId: l.id },
          query: { limit: 200, sort: opts.sort, ...filterQuery(opts) },
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

