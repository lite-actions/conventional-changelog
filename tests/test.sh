#!/usr/bin/env bash
#
# Exercises generate.sh and asserts the output. Run: bash tests/test.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="${ROOT}/scripts/generate.sh"

pass=0
fail=0
check() { # description  condition-exit-code
  if [ "$2" -eq 0 ]; then echo "  ok   - $1"; pass=$((pass + 1))
  else echo "  FAIL - $1"; fail=$((fail + 1)); fi
}

# Same, but runs the assertion itself — `[ … ]; check … $?` trips SC2319.
assert() { # description  command...
  local desc="$1"; shift
  if "$@"; then echo "  ok   - ${desc}"; pass=$((pass + 1))
  else echo "  FAIL - ${desc}"; fail=$((fail + 1)); fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
cd "${tmp}" || exit 1
git init -q
git config user.email test@example.com
git config user.name test

# ---------------------------------------------------------------------------
# One of each change type, plus a breaking change with a footer.
# ---------------------------------------------------------------------------
git commit -q --allow-empty -m "chore: init"
base="$(git rev-parse HEAD)"
git commit -q --allow-empty -m "feat: add sso login"
git commit -q --allow-empty -m "fix(api): handle empty payload"
git commit -q --allow-empty -m "docs: tweak readme"
git commit -q --allow-empty -m "perf: cache lookups"
git commit -q --allow-empty -F - <<'EOF'
refactor!: drop node 16

BREAKING CHANGE: node 18 is now required
EOF
first_head="$(git rev-parse HEAD)"

echo "== creating a new changelog (no GITHUB_REPOSITORY: plain SHAs)"
export GITHUB_OUTPUT="${tmp}/out1"
INPUT_FROM="${base}" INPUT_TO=HEAD bash "${GEN}" >/dev/null 2>&1
echo "----- generated CHANGELOG.md -----"; cat CHANGELOG.md; echo "----------------------------------"

grep -q '^# Changelog$' CHANGELOG.md; check "default title heading created" $?
grep -q '^### ⚠ BREAKING CHANGES$' CHANGELOG.md; check "BREAKING section present" $?
grep -q 'node 18 is now required' CHANGELOG.md; check "breaking footer description used" $?
grep -q '^### Features$' CHANGELOG.md; check "Features section present" $?
grep -q 'add sso login' CHANGELOG.md; check "feature listed" $?
grep -q '^### Bug Fixes$' CHANGELOG.md; check "Bug Fixes section present" $?
grep -q 'handle empty payload' CHANGELOG.md; check "fix listed" $?
grep -q '^### Performance$' CHANGELOG.md; check "Performance section present" $?
grep -q '^### Other Changes$' CHANGELOG.md; check "Other Changes section present" $?
grep -q 'tweak readme' CHANGELOG.md; check "docs commit kept (changelog logs everything)" $?

# The "type(scope):" prefix is stripped from descriptions.
grep -q 'feat: add sso login' CHANGELOG.md && check "conventional prefix stripped" 1 \
  || check "conventional prefix stripped" 0

# Section order.
awk '/⚠ BREAKING CHANGES/{b=NR} /### Features/{f=NR} /### Bug Fixes/{x=NR} END{exit !(b<f && f<x)}' CHANGELOG.md
check "order is BREAKING -> Features -> Bug Fixes" $?

# Without GITHUB_REPOSITORY the SHAs are plain text, not links.
grep -qE '\([0-9a-f]{7,}\)' CHANGELOG.md; check "plain short SHA outside CI" $?
grep -q '](http' CHANGELOG.md && check "no markdown links outside CI" 1 \
  || check "no markdown links outside CI" 0

grep -q '^changed=true$' "${GITHUB_OUTPUT}"; check "emits changed=true" $?
grep -q '^file=CHANGELOG.md$' "${GITHUB_OUTPUT}"; check "emits file=CHANGELOG.md" $?

# ---------------------------------------------------------------------------
# A second run prepends, and links SHAs when the repo is known.
# ---------------------------------------------------------------------------
echo
echo "== prepending a second section (with GITHUB_REPOSITORY: linked SHAs)"
git commit -q --allow-empty -m "feat: add audit log"
export GITHUB_OUTPUT="${tmp}/out2"
GITHUB_REPOSITORY="acme/widget" INPUT_FROM="${first_head}" INPUT_TO=HEAD bash "${GEN}" >/dev/null 2>&1

grep -q 'add audit log' CHANGELOG.md; check "new commit logged" $?
grep -q 'add sso login' CHANGELOG.md; check "earlier section preserved" $?
grep -q '^# Changelog$' CHANGELOG.md; check "header not duplicated into the body" $?
assert "exactly one top-level heading" test "$(grep -c '^# Changelog$' CHANGELOG.md)" -eq 1
assert "two dated sections" test "$(grep -c '^## ' CHANGELOG.md)" -eq 2

# Newest first: the new entry must appear above the older one.
new_line="$(grep -n 'add audit log' CHANGELOG.md | head -n1 | cut -d: -f1)"
old_line="$(grep -n 'add sso login' CHANGELOG.md | head -n1 | cut -d: -f1)"
assert "newest section prepended first" test "${new_line}" -lt "${old_line}"

grep -qE '\[[0-9a-f]{7,}\]\(https://github\.com/acme/widget/commit/[0-9a-f]{40}\)' CHANGELOG.md
check "short SHAs render as commit links in CI" $?

# ---------------------------------------------------------------------------
# An empty range changes nothing.
# ---------------------------------------------------------------------------
echo
echo "== empty range"
before="$(cat CHANGELOG.md)"
export GITHUB_OUTPUT="${tmp}/out3"
INPUT_FROM=HEAD INPUT_TO=HEAD bash "${GEN}" >/dev/null 2>&1
assert "changelog untouched for an empty range" test "${before}" = "$(cat CHANGELOG.md)"
grep -q '^changed=false$' "${GITHUB_OUTPUT}"; check "emits changed=false" $?

# ---------------------------------------------------------------------------
# Custom title and output file.
# ---------------------------------------------------------------------------
echo
echo "== custom title and output-file"
export GITHUB_OUTPUT="${tmp}/out4"
INPUT_TITLE="Widget History" INPUT_OUTPUT_FILE="HISTORY.md" \
  INPUT_FROM="${base}" INPUT_TO=HEAD bash "${GEN}" >/dev/null 2>&1
grep -q '^# Widget History$' HISTORY.md; check "custom title honoured" $?
grep -q '^file=HISTORY.md$' "${GITHUB_OUTPUT}"; check "emits the custom file path" $?

# ---------------------------------------------------------------------------
# No base: log the tip commit only (new branch / manual run).
# ---------------------------------------------------------------------------
echo
echo "== no base ref"
rm -f CHANGELOG.md
export GITHUB_OUTPUT="${tmp}/out5"
INPUT_TO=HEAD bash "${GEN}" >/dev/null 2>&1
grep -q 'add audit log' CHANGELOG.md; check "tip commit logged with no base" $?
assert "only the tip commit logged" test "$(grep -c '^- ' CHANGELOG.md)" -eq 1

# An all-zero `before` (branch creation) is treated the same way.
rm -f CHANGELOG.md
export GITHUB_OUTPUT="${tmp}/out6"
INPUT_FROM="0000000000000000000000000000000000000000" INPUT_TO=HEAD bash "${GEN}" >/dev/null 2>&1
assert "all-zero base treated as a new branch" test "$(grep -c '^- ' CHANGELOG.md)" -eq 1

echo
echo "passed: ${pass}, failed: ${fail}"
[ "${fail}" -eq 0 ]
