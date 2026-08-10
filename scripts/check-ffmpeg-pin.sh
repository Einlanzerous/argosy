#!/usr/bin/env bash
# Assert the ffmpeg on PATH is the one .ffmpeg-version pins (ARGY-183).
#
# The Dockerfiles and CI all install `ffmpeg=$(cat .ffmpeg-version)`, so they
# cannot drift from each other by construction. What they *can* drift from is
# reality — an image built before the pin moved, a developer's system ffmpeg, a
# CI runner that resolved the package from a different pocket. This closes that
# gap, and it is the check that gives the manifest tests their meaning: they
# assert ffmpeg's output shape (ARGY-127, ARGY-174), which is only a guard if
# the ffmpeg under test is the ffmpeg that ships.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pin="$(tr -d '[:space:]' <"$root/.ffmpeg-version")"

# Debian package version -> upstream version, which is what `ffmpeg -version`
# reports: strip the "7:" epoch and everything from the "-0+deb13u1" revision on.
want="${pin#*:}"
want="${want%%-*}"

if ! command -v ffmpeg >/dev/null 2>&1; then
	echo "check-ffmpeg-pin: ffmpeg not on PATH (want $want, pinned $pin)" >&2
	exit 1
fi

got="$(ffmpeg -version | head -1 | awk '{print $3}')"

# Debian appends its revision to the reported version (7.1.5-0+deb13u1); a
# static or self-built ffmpeg reports the bare upstream version. Accept either,
# so long as the upstream version matches.
if [ "$got" != "$want" ] && [ "${got%%-*}" != "$want" ]; then
	cat >&2 <<-EOF
		check-ffmpeg-pin: FAILED

		  pinned (.ffmpeg-version): $pin  -> expected ffmpeg $want
		  on PATH:                  $got

		CI, the dev image and the prod image must all run the pinned build, or the
		HLS manifest tests are asserting one ffmpeg's output shape while production
		emits another's. Rebuild the image, or move the pin in .ffmpeg-version.
	EOF
	exit 1
fi

echo "check-ffmpeg-pin: ok — ffmpeg $got matches $pin"
