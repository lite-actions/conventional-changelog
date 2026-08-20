# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

A composite **GitHub Action** (pure shell) that maintains a **full changelog**
from Conventional Commits. Every commit in the range is logged, grouped by type
and referenced by its **short commit SHA**, under a dated section prepended to
`CHANGELOG.md`. It does **no versioning or tagging**.

This is the full counterpart to the abbreviated view: **changelog entries here
keep commit SHAs**; `lite-actions/release-notes` deliberately omits them because
release notes are for end users. `mrdoodles/versioning-tests` consumes both from
its `changelog.yml`, so the output format is effectively a contract — the tests
lock it down.

Extracted from `versioning-tests/.github/scripts/generate-changelog.sh` so the
sibling action repos can share it instead of each carrying a copy.

## Layout

- `action.yml` — composite action; one shell step runs `scripts/generate.sh`
  with `INPUT_*` env and exposes outputs `changed`, `file`.
- `scripts/generate.sh` — all the logic.
- `tests/test.sh` — assert-based suite over the generated markdown.
- `.github/workflows/ci.yml` — shellcheck + tests.
- `README.md`, `LICENSE` (MIT).

## How `generate.sh` works

- Inputs (env): `INPUT_FROM`, `INPUT_TO`, `INPUT_TITLE` (default `Changelog`),
  `INPUT_OUTPUT_FILE` (default `CHANGELOG.md`).
- **Range**: explicit `FROM..TO` wins, so the action works from a tag job or a
  manual dispatch. With neither set it falls back to the push event's
  `before`/`after` from `$GITHUB_EVENT_PATH` (needs `jq`; guarded by
  `command -v`). An empty or all-zero `from` means a new branch → log the tip
  commit only.
- Classifies every commit: `feat` → Features, `fix` → Bug Fixes, `perf` →
  Performance, everything else → Other Changes. A `!` subject or a
  `BREAKING CHANGE:`/`BREAKING-CHANGE:` footer *additionally* lists it under
  BREAKING CHANGES.
- Short SHAs render as markdown commit links when `GITHUB_REPOSITORY` is set,
  and as plain text otherwise, so local runs stay readable.
- Prepends the new section above the first existing `## ` heading via `awk`; the
  `# <title>` header is written only when the file is created.

## Commands

```bash
bash tests/test.sh
shellcheck -x --severity=warning scripts/*.sh tests/*.sh
# Manual run over a range:
INPUT_FROM=HEAD~5 INPUT_TO=HEAD bash scripts/generate.sh && cat CHANGELOG.md
```

## Coding style

- Pure `bash` with `set -euo pipefail`; must pass
  `shellcheck -x --severity=warning` (CI enforces).
- **The output format is the spec.** Any change to headings/ordering/content
  must update `tests/test.sh`.
- In `tests/test.sh`, use the `assert` helper for bracket tests —
  `[ … ]; check … $?` trips **SC2319** ("`$?` refers to a condition").
- Quote `done` when used as a literal (shell keyword → SC1010); prefer
  `awk`/`printf` over `sed | head` (SIGPIPE under pipefail).
- Keep it dependency-free (`bash`, `git`, `sed`, `grep`; `jq` optional).

## Marketplace

The `name:` must be **globally unique** across the Marketplace and the
`description:` must be **≤125 characters**. "Conventional Changelog Generator"
was already taken by `quant-eagle`, hence the shorter `Conventional Changelog`.
Fallback if it is refused at publish time: "Conventional Commit Changelog".

## Versioning & releasing

Releases are cut by `release.yml` (`workflow_dispatch`) — never by hand, and
never through the GitHub web UI:

```bash
gh workflow run release.yml --repo lite-actions/conventional-changelog
```

It computes the version from the commits since the last `vX.Y.Z` tag, tags the
release, force-moves `@vN`, and publishes the GitHub Release with the generated
notes as its body. `@vN` is the moving major tag consumers use.

**Never create a release through the web UI.** The "publish to the Marketplace"
checkbox is required only for an action's *first* publish; once a listing
exists, releases cut by the workflow appear on it automatically — verified
2026-08-20 on `git-checkout`, where `v1.1.0` reached the listing with nothing
ticked. Using the UI afterwards is what produced the `v1.12` and `1.3.5` tags,
and left `@v1` pointing at an old commit three times. The workflow types
nothing, so it cannot mistype.

## Conventions

- Public, **unprotected** repo — push docs/fixes to `main` directly; workflow-
  file changes need a `workflow`-scoped token.
- Conventional Commits for messages, with the body as a **single unwrapped
  paragraph**; co-authored commits use the bot identity:
  `Co-Authored-By: Claude <309050497+MrDClaudeBot@users.noreply.github.com>`.
