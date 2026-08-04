# Conventional Changelog

A composite GitHub Action (pure shell) that maintains a **full changelog** from
[Conventional Commits](https://www.conventionalcommits.org/) — every commit in
the range, grouped by type and referenced by its **short commit SHA**, under a
dated section prepended to `CHANGELOG.md`.

Sections, in order, with empty ones omitted:

1. ⚠ BREAKING CHANGES
2. Features
3. Bug Fixes
4. Performance
5. Other Changes

Nothing is excluded — `docs`, `chore`, `ci` and friends land in **Other
Changes**. This action does no versioning or tagging. No Node/Docker — just
`bash`, `git`, `sed`, `grep`.

> Looking for the abbreviated, user-facing view instead (BREAKING/feat/fix since
> the last release, no SHAs)? That is
> [`mrdoodles/release-notes`](https://github.com/mrdoodles/release-notes). The
> two are designed to be used together.

## Usage

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0 # needed so the commit range can be resolved
- uses: mrdoodles/conventional-changelog@v1
- run: cat CHANGELOG.md
```

On a `push` event the range defaults to the push's `before..after`, so the
changelog gains exactly the commits that just landed. Set `from`/`to` explicitly
to use it from a tag job or a manual dispatch.

## Inputs

| Input         | Default                | Description                                    |
| ------------- | ---------------------- | ---------------------------------------------- |
| `from`        | push event `before`    | Base ref/commit for the range, exclusive.      |
| `to`          | push event `after`     | Head ref/commit for the range, else `HEAD`.    |
| `title`       | `Changelog`            | Heading used when the file is first created.   |
| `output-file` | `CHANGELOG.md`         | File to write.                                 |

## Outputs

| Output    | Description                             |
| --------- | --------------------------------------- |
| `changed` | `true` if any commits were logged.      |
| `file`    | The path the changelog was written to.  |

## Behaviour notes

- **Newest first.** Each run prepends a new dated section above the existing
  ones; the file header is written only when the file is created.
- **Commit links.** When `GITHUB_REPOSITORY` is set (i.e. in Actions), short
  SHAs render as markdown links to the commit. Outside CI they stay plain text,
  so local runs are readable.
- **Breaking changes** are detected from a `!` in the subject or a
  `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer, and are listed *in addition*
  to the commit's own type section.
- **Empty range** → no file change, and `changed=false`.
- **No base** (new branch, all-zero `before`, or a manual run without `from`) →
  the tip commit only.

## Example output

```markdown
# Changelog

All notable changes to this project are documented in this file,
grouped by push and referenced by short commit SHA.

## 2026-08-04 ([9f2a1c4](https://github.com/acme/widget/commit/9f2a1c4…))

### ⚠ BREAKING CHANGES

- node 18 is now required ([f28cc28](https://github.com/acme/widget/commit/f28cc28…))

### Features

- add sso login ([3b7d901](https://github.com/acme/widget/commit/3b7d901…))

### Bug Fixes

- handle empty payload ([c1e40aa](https://github.com/acme/widget/commit/c1e40aa…))

### Other Changes

- tweak readme ([c66e3db](https://github.com/acme/widget/commit/c66e3db…))
```
