#!/usr/bin/env bash
# Keep docs/architecture.archify.json honest (SERV-159).
#
#   scripts/architecture-map-check.sh
#
# That file is this repo's system map: a typed JSON IR that the estate wiki
# renders onto this repo's page (construct-server, SERV-159) and the public
# portfolio renders with evidence stripped (FOLIO-3). Every component in it
# carries `sources[]` — paths into this repo — and `meta.repository.revision`
# pins the commit those paths are read at, so each `SRC` chip on the rendered
# map deep-links to code that provably said what the map claims, at a commit
# that cannot change under it.
#
# The pin is the whole point AND the whole problem. It is what keeps the links
# honest; it is also what lets the map go quietly stale, because nothing about
# editing a cited file reminds anyone that a diagram somewhere describes it.
# This is that reminder. It began as a shell port of switchyard's
# scripts/architecture-map-check.ts and is the estate's shared copy: identical
# in every repo apart from SLUG, so a fix lands in all of them at once. It has
# moved ahead of the TS on two points — a path missing at the pin is an error
# only and never also drift, and drift is reported per cited file rather than
# per reference. Port both back to the TS when it is next touched.
#
# TWO CLASSES OF FINDING, and the split is deliberate:
#
#   ERROR — the map is BROKEN, and archify would refuse to render it at all. A
#   path that does not exist at the pinned revision, a line range past the end
#   of the file there, a source that breaks archify's schema (no path, a line
#   that is not a positive integer, a range ending before it starts, an unknown
#   key), a component with no id, unparsable JSON, a component citing more
#   than three sources. These fail the build, in the PR that introduced them, because the
#   alternative is finding out from a warning block on a wiki page nobody was
#   looking at. Nothing outside this repo can make them fire: both the pin and
#   the paths live in the tracked file.
#
#   DRIFT — the map is STALE, not broken. Files it cites have moved on since the
#   pin. This is the ordinary condition of a pinned map and warns only. Failing
#   here would mean every PR that touches a cited file must also re-pin the map,
#   which trains people to delete the map rather than maintain it.
#
# And one SKIP: if the pinned commit cannot be fetched, or jq is not on PATH,
# this says so and exits 0. A check that cannot run has found nothing, and a CI
# failure caused by a fetch is a false block — the same fail-open discipline as
# the estate's pre-push lint gate (SERV-58).
set -u

IR="docs/architecture.archify.json"
SLUG="einlanzerous/argosy"   # lower-case owner/name
# archify's architecture schema caps `sources` at three per component
# (`maxItems: 3`, vendored archify 2.16.0). The schema runs before anything
# else, so a fourth source is not a warning: the wiki refuses to render the
# whole map (SWY-470). The schema is vendored in construct-server, so a
# checkout that carries it reads the cap from the file and cannot drift from a
# vendor bump; every other repo restates it here. If archify moves the cap,
# move the constant with it.
MAX_SOURCES_PER_COMPONENT=3
schema="wiki/vendor/archify/schemas/architecture.schema.json"
if [ -f "$schema" ] && command -v jq >/dev/null 2>&1; then
  cap=$(jq -r '.properties.components.items.properties.sources.maxItems // empty' "$schema" 2>/dev/null)
  case "$cap" in '' | *[!0-9]*) ;; *) MAX_SOURCES_PER_COMPONENT=$cap ;; esac
fi

errors=()
# Drift is reported per FILE, not per reference: a map cites one file from
# several components (four of signet's 18 references point into main.go), and
# counting references would call one edited file four changed files.
drift_paths=()          # drifted paths, first-cited order
declare -A drift_how=() # path -> what happened to it
declare -A drift_by=()  # path -> the components that cite it, comma-joined
declare -A cited=()     # every cited path, so the summary counts files

# GitHub Actions annotations when running there, plain lines otherwise.
annotate() {
  local level=$1; shift
  local msg=$*
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::%s file=%s::%s\n' "$level" "$IR" "${msg//$'\n'/%0A}"
  else
    printf '%s: %s\n' "$level" "$msg"
  fi
}

# No map is a normal state, not a finding. Most repos have none.
if [ ! -f "$IR" ]; then
  echo "architecture-map: no $IR — nothing to check"
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  annotate notice "jq is not on PATH, so the map could not be checked."
  exit 0
fi

if ! jq -e . "$IR" >/dev/null 2>&1; then
  annotate error "$IR is not valid JSON."
  exit 1
fi

url=$(jq -r '.meta.repository.url // empty' "$IR")
rev=$(jq -r '.meta.repository.revision // empty' "$IR")
if [ -z "$url" ] || [ -z "$rev" ]; then
  annotate error "meta.repository must carry a url and a revision — without them the SRC chips cannot be verified."
  exit 1
fi
if ! [[ $rev =~ ^[a-fA-F0-9]{40}$ ]]; then
  annotate error "meta.repository.revision must be a full 40-character commit SHA, not \"$rev\"."
  exit 1
fi
normalised=$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]' | sed -E 's#(\.git/?|/)$##')
if [[ $normalised != *"$SLUG" ]]; then
  annotate error "meta.repository.url is $url, which is not this repository — the map would describe someone else's code."
  exit 1
fi

# A property of the tracked file alone, so it is checked before the pin is
# fetched: a map archify will refuse fails here even when the fetch skips.
overfull=0
while IFS=$'\t' read -r id n; do
  [ -n "$id" ] || continue
  annotate error "component \"$id\" carries $n sources; archify's schema allows at most $MAX_SOURCES_PER_COMPONENT, and a schema failure means the wiki renders no map at all."
  overfull=1
done < <(jq -r --argjson max "$MAX_SOURCES_PER_COMPONENT" \
  '.components[]? | select(((.sources // []) | length) > $max) | [.id, ((.sources // []) | length)] | @tsv' "$IR")
[ "$overfull" -eq 0 ] || exit 1

pin=${rev,,}
short=${pin:0:7}

# Make the pinned commit readable. CI checks out at depth 1, so it is normally
# absent and has to be fetched — by SHA, which GitHub allows.
#
# `--depth 1` ONLY on a repository that is already shallow: against a complete
# clone it writes `.git/shallow` and leaves the repository shallow after this
# check has exited, a lasting change to someone's working copy made by a
# read-only check. The remote is looked up rather than assumed: clones are not
# consistent about it, and a wrong guess here would read as "the pin is gone".
ensure_pinned() {
  git cat-file -e "$pin^{commit}" 2>/dev/null && return 0
  local depth=()
  [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ] && depth=(--depth 1)
  local remotes remote tried=" "
  remotes=$(git remote)
  for remote in origin upstream $remotes; do
    grep -qx "$remote" <<<"$remotes" || continue
    case "$tried" in *" $remote "*) continue ;; esac
    tried="$tried$remote "
    git fetch "${depth[@]}" --quiet "$remote" "$pin" 2>/dev/null && return 0
  done
  return 1
}

if ! ensure_pinned; then
  # Not an error. See the SKIP note in the header.
  annotate notice "the pinned commit $short could not be fetched, so the map could not be checked. A rewritten history removes a commit that was pinned honestly; re-pin the map if that is what happened."
  exit 0
fi

# Lines as an editor counts them: a trailing newline terminates the last line
# rather than starting a new one, and blank lines anywhere are lines. awk's NR
# is exactly that count.
count_lines() { awk 'END { print NR }'; }

# One type gate for the source shape, mirroring archify's vendored schema
# (`sources.items`: `path` a non-empty string, `line`/`end_line` integers >= 1,
# `label` the only other key, `additionalProperties: false`; and every
# component an `id`). Checked here as data, in one place, rather than field by
# field downstream, where each new coercion was its own hole: a string line
# that `tostring` smoothed over, a `false` that `//` read as absent.
shape=$(jq -r '
  (.components // []) | to_entries[] | .key as $i | .value as $c
  | (if ($c.id|type)=="string" and ($c.id|length)>0 then $c.id else "#\($i)" end) as $name
  | ( if ($c.id|type)!="string" or ($c.id|length)==0 then "component \($name) has no string id" else empty end ),
    ( ($c.sources // []) | if type!="array" then "component \($name): sources is not an array"
      else to_entries[] | .key as $j | .value as $s
      | if ($s|type)!="object" then "component \($name) source \($j) is not an object"
        else ( ($s|keys[]) | select(. != "path" and . != "line" and . != "end_line" and . != "label") | "component \($name) source \($j) has an unknown key \"\(.)\"" ),
             ( if ($s.path|type)!="string" or ($s.path|length)==0 then "component \($name) source \($j) has no string path" else empty end ),
             ( $s | to_entries[] | select(.key=="line" or .key=="end_line")
               | select((.value|type)!="number" or (.value|floor)!=.value or .value<1 or .value>999999999)
               | "component \($name) source \($j) \(.key) is not a positive integer" ),
             ( if ($s.line|type)=="number" and ($s.end_line|type)=="number" and $s.end_line<$s.line then "component \($name) source \($j) range ends before it starts" else empty end ),
             ( if ($s.end_line|type)=="number" and ($s.line|type)!="number" then "component \($name) source \($j) has end_line but no line" else empty end )
        end end )' "$IR" 2>&1) || { annotate error "$IR could not be read for its source shapes: $shape"; exit 1; }
if [ -n "$shape" ]; then
  while IFS= read -r finding; do annotate error "$finding. The map will not render."; done <<<"$shape"
  exit 1
fi

# Captured first and checked, never read through a process substitution: bash
# does not see the exit status of `< <(jq …)`, so a jq error partway through
# the stream (a non-string path, say) would leave every later reference
# unchecked and the summary saying "in sync".
if ! refs=$(jq -r '.components[]? | .id as $c | (.sources // [])[] | [$c, (.path // ""), (.line // "" | tostring), (.end_line // "" | tostring)] | join("\u001f")' "$IR"); then
  annotate error "$IR has a source jq cannot read (a path or line that is not a string or number?); the map will not render."
  exit 1
fi

if [ -z "$refs" ]; then
  annotate error "no component carries sources[] — archify refuses a map that pins a revision and cites nothing."
  exit 1
fi

count=0
# Fields are separated by US (0x1f), not a tab: `read` treats a tab as
# whitespace and merges consecutive ones, so an absent field would shift the
# columns and a missing path would be read as whatever came next.
while IFS=$'\x1f' read -r component path line end_line; do
  count=$((count + 1))
  cited[$path]=1
  where="component \"$component\" cites $path"

  # Would archify render this at all? Everything here is an ERROR.
  if [ "$(git cat-file -t "$pin:$path" 2>/dev/null)" != "blob" ]; then
    errors+=("$where, which is not a file at the pinned commit $short. The map will not render.")
    # Already an error; saying it also "no longer exists" would be false for
    # a path that never did, so the drift check below is skipped for it.
    continue
  elif [ -n "$line" ]; then
    # Piped straight into awk, never captured first: `$(…)` strips every
    # trailing newline, so a file ending in blank lines would be undercounted
    # and a citation into those lines reported as out of range.
    if ! lines=$(set -o pipefail; git show "$pin:$path" 2>/dev/null | count_lines); then
      errors+=("$where, which could not be read at $short.")
    else
      wanted=${end_line:-$line}
      if [ "$wanted" -gt "$lines" ]; then
        errors+=("$where:$line${end_line:+-$end_line}, but that file has $lines lines at $short.")
      fi
    fi
  fi

  # Has the cited code moved on since the pin? Everything here is DRIFT.
  how=""
  if [ ! -e "$path" ]; then
    how="no longer exists — the map still links to it at the pin"
  elif ! git diff --quiet "$pin" HEAD -- "$path" 2>/dev/null; then
    stat=$(git diff --shortstat "$pin" HEAD -- "$path" 2>/dev/null)
    how="has changed since the pin${stat:+ —$stat}"
  fi
  if [ -n "$how" ]; then
    if [ -z "${drift_how[$path]:-}" ]; then
      drift_paths+=("$path"); drift_how[$path]=$how; drift_by[$path]=$component
    else
      case ", ${drift_by[$path]}, " in *", $component, "*) ;; *) drift_by[$path]+=", $component" ;; esac
    fi
  fi
done <<<"$refs"

echo "architecture-map: $count source reference(s) checked against $short"
for e in "${errors[@]}"; do annotate error "$e"; done

if [ "${#drift_paths[@]}" -gt 0 ]; then
  msg="the system map is stale: ${#drift_paths[@]} of ${#cited[@]} cited file(s) have changed since $short ($count references)."
  for p in "${drift_paths[@]}"; do msg+=$'\n'"  - $p ${drift_how[$p]} (cited by ${drift_by[$p]})."; done
  msg+=$'\n'"Re-read the map, update it where the shape actually changed, and re-pin meta.repository.revision to the merge commit."
  annotate warning "$msg"
fi

if [ "${#errors[@]}" -eq 0 ] && [ "${#drift_paths[@]}" -eq 0 ]; then
  echo "architecture-map: in sync with the pinned commit"
fi

[ "${#errors[@]}" -eq 0 ]
