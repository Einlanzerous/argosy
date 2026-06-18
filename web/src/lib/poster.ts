import type { CSSProperties } from 'vue'

// Charcoal/teal/brown gradient placeholders matching the design, used when an
// item has no cached artwork. The gradient is chosen deterministically from a
// seed (title) so a given title always renders the same placeholder.
const GRADIENTS = [
  'linear-gradient(158deg,#26323f,#12171c)',
  'linear-gradient(158deg,#3a2a28,#171110)',
  'linear-gradient(158deg,#1f342f,#0f1614)',
  'linear-gradient(158deg,#2b2f38,#13151a)',
  'linear-gradient(158deg,#332439,#161018)',
  'linear-gradient(158deg,#24333a,#101618)',
  'linear-gradient(158deg,#34301f,#171510)',
  'linear-gradient(158deg,#21332b,#0f1614)',
]

function hash(seed: string): number {
  let h = 0
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0
  return h
}

export function gradientFor(seed: string): string {
  return GRADIENTS[hash(seed) % GRADIENTS.length]
}

// Background style for a poster/backdrop surface: the real artwork when present,
// otherwise a seeded gradient placeholder.
export function posterStyle(
  posterUrl: string | null | undefined,
  seed: string,
): CSSProperties {
  if (posterUrl) {
    return {
      backgroundImage: `url("${posterUrl}")`,
      backgroundSize: 'cover',
      backgroundPosition: 'center',
    }
  }
  return { backgroundImage: gradientFor(seed) }
}
