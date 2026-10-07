# Tracking upstream God's Eye View

`apps/web/gods-eye-view` is a copy of
[bilawalsidhu/gods-eye-view](https://github.com/bilawalsidhu/gods-eye-view), which
ships fixes and features most days. This directory keeps the copy in step with it.
It is the counterpart of `apps/desktop/vitruvian`'s upstream tracking, adapted for
a copy that was not refactored. Everything in it is this repository's own: upstream
has no `upstream/` directory.

## What this copy is

Upstream at one commit (the base), plus three things:

- the MIT header `bazel run //tools/license:add` puts on every source file.
  Upstream's own notice stays in `LICENSE`;
- the local changes [`local-changes.tsv`](local-changes.tsv) lists, each with why:
  files only here (`added`), files changed here (`modified`) and upstream files
  left out (`deleted`);
- nothing else.

`check` proves it: it sets each file's header aside, compares the rest with the
base, and fails on any difference the list does not name, or on a row that no
longer matches a difference.

## Why the whole tree, not commit by commit

The Vitruvian desktop app was restructured after its import, so each upstream
commit has to be placed by hand and the fork keeps a ledger of every commit. This
copy keeps upstream's layout, so a sync is one three-way merge of the whole tree
from the old base to upstream's latest. Files this copy never changed take
upstream's version as they are; only the listed files need a merge. No commit is
skipped, so no per-commit ledger is needed: the base line records where the copy
stands, and each sync's pull request lists what landed upstream.

## The pieces

- **The list**, [`local-changes.tsv`](local-changes.tsv): its `# base` line is the
  upstream commit this copy matches, with its tree, so the base is found again if
  upstream rewrites its history. Each row is `path<TAB>change<TAB>why`. A path
  ending in `/` covers a directory of files only here.
- **The tool**, run as `bazel run //apps/web/gods-eye-view:track_upstream -- <command>`:
  - `status` shows how far upstream has moved past the base, its merged pull
    requests, and anything `check` would fail on;
  - `check` exits non-zero unless the copy is the base plus the listed changes;
  - `sync` merges upstream's latest into the copy and moves the base line. It
    writes conflicts into the files with markers, as git does, and prints a
    report: what merged into a local change, what to resolve, and the follow-ups
    below;
  - `check-changes` validates the list's format, offline.

  `bazel test //apps/web/gods-eye-view:upstream_test` tests the tool against
  throwaway repositories and checks the committed list. It runs in this app's
  presubmit.
- **The watch**, `.github/workflows/gods-eye-view-upstream-watch.yaml`, runs
  daily. It keeps one issue, "Upstream gods-eye-view: changes to sync", that
  lists the upstream pull requests not yet in the copy and any unlisted local
  change. It comments when new ones land, and closes the issue when the copy is
  caught up.
- **The weekly sync**, [`SYNC.md`](SYNC.md), is what an agent follows to merge
  upstream and land it. A Claude Code routine runs it every Monday morning
  (Pacific). The routine holds only the schedule and a pointer to that file, so
  the steps change through pull requests like any other file here.

## Local changes

Keep the list short. Each row is a merge to resolve in every sync from then on.

- Put what only this repository needs in a file of its own (`BUILD.bazel`,
  `Dockerfile`, `server.mjs`, `scripts/bazel-unit-tests.mjs`) rather than in an
  upstream file.
- Change an upstream file only when there is no other way, and say why in its row.
- When upstream makes a local change unnecessary, drop the change and its row.
  `check` names a row that no longer matches anything.
- A fix that would help upstream too belongs upstream as a pull request. Once it
  lands there, the next sync drops the local copy of it.

## The production server

Upstream serves its `/api` routes from its Vite dev server (`server/` and
`build/`). The production image runs `server.mjs`, which serves the built `dist/`
and re-implements those routes. So a new or changed upstream route reaches
production only once `server.mjs` has it. `sync` lists the server files upstream
changed, so each sync can decide what production needs.
