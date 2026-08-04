#!/usr/bin/env bash
#
# Generate a full changelog from Conventional Commits.
#
# This script is NOT concerned with versioning or tagging: it logs the commits
# in a range, grouped by type, each referenced by its short commit SHA, under a
# dated section prepended to the changelog file.
#
# Inputs (env):
#   INPUT_FROM         Base ref/commit, exclusive (default: the push's `before`).
#   INPUT_TO           Head ref/commit (default: the push's `after`, else HEAD).
#   INPUT_TITLE        Heading used when creating the file (default: Changelog).
#   INPUT_OUTPUT_FILE  File to write (default: CHANGELOG.md).
#   GITHUB_REPOSITORY  owner/repo; when set, short SHAs render as commit links.
#   GITHUB_SERVER_URL  Server for those links (default: https://github.com).
#
# Outputs (to $GITHUB_OUTPUT): changed, file
#
set -euo pipefail

: "${GITHUB_OUTPUT:=/dev/stdout}"
emit() { printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT}"; }

TITLE="${INPUT_TITLE:-Changelog}"
OUT="${INPUT_OUTPUT_FILE:-CHANGELOG.md}"

# ---------------------------------------------------------------------------
# 1. Determine the commit range.
#
# Explicit from/to win, so the action is usable from a tag job or a manual
# dispatch. With neither, fall back to the push event's before..after.
# ---------------------------------------------------------------------------
from="${INPUT_FROM:-}"
to="${INPUT_TO:-}"

if [ -z "${from}${to}" ] && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -f "${GITHUB_EVENT_PATH}" ] \
   && command -v jq >/dev/null 2>&1; then
  from="$(jq -r '.before // empty' "${GITHUB_EVENT_PATH}")"
  to="$(jq -r '.after // empty' "${GITHUB_EVENT_PATH}")"
fi
to="${to:-HEAD}"

# A push that created the branch reports an all-zero `before`.
zero="0000000000000000000000000000000000000000"
if [ -n "${from}" ] && [ "${from}" != "${zero}" ]; then
  commits="$(git rev-list --no-merges "${from}..${to}")"
else
  # New branch, manual run, or no base: log the tip commit only.
  commits="$(git rev-list --no-merges -n 1 "${to}")"
fi

if [ -z "${commits}" ]; then
  echo "No commits in range; nothing to log."
  emit changed false
  emit file "${OUT}"
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Group the commits by type; each entry links to its commit by short SHA.
# ---------------------------------------------------------------------------
commit_base="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}"

# Render a short SHA, as a markdown commit link when the repo is known.
sha_ref() {
  local sha short
  sha="$1"
  short="$(git rev-parse --short "${sha}")"
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '[%s](%s/commit/%s)' "${short}" "${commit_base}" "${sha}"
  else
    printf '%s' "${short}"
  fi
}

breaks=(); feats=(); fixes=(); perfs=(); others=()
while IFS= read -r sha; do
  [ -n "${sha}" ] || continue
  subject="$(git log -1 --format=%s "${sha}")"
  body="$(git log -1 --format=%b "${sha}")"
  ref="$(sha_ref "${sha}")"
  # Description = subject with the "type(scope)!:" prefix stripped.
  desc="$(printf '%s' "${subject}" | sed -E 's/^[a-z]+(\([^)]+\))?!?:[[:space:]]*//')"
  line="- ${desc} (${ref})"
  type="${subject%%[(:!]*}"

  if printf '%s' "${subject}" | grep -Eq '^[a-z]+(\([^)]+\))?!:' \
     || printf '%s' "${body}" | grep -Eq '^(BREAKING[ ]CHANGE|BREAKING-CHANGE):'; then
    bc="$(printf '%s' "${body}" | sed -n -E 's/^(BREAKING[ ]CHANGE|BREAKING-CHANGE):[[:space:]]*(.*)/\2/p' | head -n1)"
    [ -n "${bc}" ] || bc="${desc}"
    breaks+=("- ${bc} (${ref})")
  fi

  case "${type}" in
    feat) feats+=("${line}") ;;
    fix)  fixes+=("${line}") ;;
    perf) perfs+=("${line}") ;;
    *)    others+=("${line}") ;;
  esac
done <<< "${commits}"

# ---------------------------------------------------------------------------
# 3. Build the new section, headed by the date and the tip short SHA.
# ---------------------------------------------------------------------------
tip_ref="$(sha_ref "${to}")"
section="$(mktemp)"
trap 'rm -f "${section}"' EXIT
{
  printf '## %s (%s)\n' "$(date -u +%Y-%m-%d)" "${tip_ref}"
  if [ "${#breaks[@]}" -gt 0 ]; then
    printf '\n### ⚠ BREAKING CHANGES\n\n'; printf '%s\n' "${breaks[@]}"
  fi
  if [ "${#feats[@]}" -gt 0 ]; then
    printf '\n### Features\n\n'; printf '%s\n' "${feats[@]}"
  fi
  if [ "${#fixes[@]}" -gt 0 ]; then
    printf '\n### Bug Fixes\n\n'; printf '%s\n' "${fixes[@]}"
  fi
  if [ "${#perfs[@]}" -gt 0 ]; then
    printf '\n### Performance\n\n'; printf '%s\n' "${perfs[@]}"
  fi
  if [ "${#others[@]}" -gt 0 ]; then
    printf '\n### Other Changes\n\n'; printf '%s\n' "${others[@]}"
  fi
  printf '\n'
} > "${section}"

# ---------------------------------------------------------------------------
# 4. Create or update the changelog (newest section first).
# ---------------------------------------------------------------------------
if [ ! -f "${OUT}" ]; then
  {
    printf '# %s\n\n' "${TITLE}"
    printf 'All notable changes to this project are documented in this file,\n'
    printf 'grouped by push and referenced by short commit SHA.\n\n'
    cat "${section}"
  } > "${OUT}"
  echo "Created ${OUT}."
else
  # Prepend the new section before the first existing dated section.
  tmp="$(mktemp)"
  awk 'NR==FNR { sect = sect $0 ORS; next }
       /^## / && !ins { printf "%s", sect; ins = 1 }
       { print }
       END { if (!ins) printf "%s%s", ORS, sect }' \
       "${section}" "${OUT}" > "${tmp}"
  mv "${tmp}" "${OUT}"
  echo "Updated ${OUT}."
fi

echo "Logged ${#feats[@]} feature(s), ${#fixes[@]} fix(es), ${#perfs[@]} perf, ${#others[@]} other, ${#breaks[@]} breaking."
emit changed true
emit file "${OUT}"
