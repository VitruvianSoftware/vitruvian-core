# Weekly upstream sync

The steps an agent follows to bring `apps/web/gods-eye-view` up to upstream's
latest and land it on `main`. A scheduled Claude Code routine runs it every Monday
morning, Pacific time, in a fresh cloud session that reads this file from `main`.
Anyone can run it by hand the same way.

The routine itself lives in James's Claude account, not in this repository: it
holds only the schedule and a pointer to this file. To change how the sync works,
change this file in a pull request; the next run follows the version on `main`.

[`README.md`](README.md) is the authority on what this copy is, the list of local
changes and the tool. Read it first, with the repository's
[`AGENTS.md`](../../../../AGENTS.md). This file adds the order of work and what
earlier syncs learned.

## Goal

The copy is upstream's latest `main` plus only the changes
[`local-changes.tsv`](local-changes.tsv) lists, on `main`, with its checks green.

## Steps

1. Start from the latest `origin/main`. If an open pull request already syncs
   this app (its title starts with "feat(gods-eye-view): sync upstream"), drive
   that one to merged before starting another.
2. Run `bazel run //apps/web/gods-eye-view:track_upstream -- status`. If it is 0
   commits behind and reports no problem, stop and report "caught up at" the base.
3. If `status` reports problems with the list, fix them first, in a commit of
   their own: list a deliberate change with why, or undo one nobody needs. Never
   list a change just to make the check pass without knowing why it exists; ask
   instead.
4. Run `bazel run //apps/web/gods-eye-view:track_upstream -- sync --report /tmp/gev-sync.md`
   and read the report. It moves the base and leaves the merge in the working tree.
   Then:
   - resolve every conflict, keeping both upstream's change and the reason for
     the local one (the row's why). Search for leftover `<<<<<<<` markers;
   - for each file merged into a local change, check the change still does its
     job;
   - run `bazel run //tools/license:add` for the new files;
   - when `package.json` changed, run `pnpm install` at the repository root and
     commit `pnpm-lock.yaml`. A dependency upstream adds or bumps must resolve
     to the one version the rest of the repository uses
     ([`docs/dependency-versioning/javascript.md`](../../../../docs/dependency-versioning/javascript.md)).
     Keep the versions the row for `package.json` explains;
   - when upstream added a top-level directory, decide whether `BUILD.bazel`'s
     globs need it: they name directories one by one;
   - for upstream's server changes, decide what `server.mjs` needs (README.md,
     "The production server"). Porting a whole new feature's routes can be its
     own pull request; say so in the report rather than leave it unmentioned.
     When `:server_test` fails because the image lacks a file the tile engine
     now imports, add it to the Dockerfile's runtime-stage `COPY` lines.
5. Before every push, run these and check each exit status. Piping one through
   `tail` hides a failure.
   - `bazel run //apps/web/gods-eye-view:track_upstream -- check`
   - `bazel test //apps/web/gods-eye-view:unit_tests //apps/web/gods-eye-view:server_test //apps/web/gods-eye-view:cesium_assets_test //apps/web/gods-eye-view:upstream_test`
   - `bazel build //apps/web/gods-eye-view:build`
   - `bazel run //tools/license:check`
6. Commit as `feat(gods-eye-view): sync upstream to <short sha>`, with the
   report's "What landed upstream" list and an "Adapted to this copy:" paragraph
   naming each conflict and how it was resolved, and every follow-up left for
   later. Open the pull request with the same title. Its body is a table of the
   upstream pull requests that landed and what each changes here, then the
   conflicts and follow-ups, then the test plan. Turn on auto-merge and follow
   the pull request's activity.
7. Drive it to merged. A failure on a commit your own push replaced, whose jobs
   it cancelled, is not a failure. Never skip or disable a test. If an upstream
   test fails only in this repository's sandbox, adapt the test or the harness
   and list it in `local-changes.tsv`; if it fails because upstream is broken,
   say so in the pull request rather than patch upstream's code here. If the sync
   cannot be made green after a few honest attempts, leave the pull request open
   with one comment naming what blocks it, and report that.
8. After it merges, run `bazel run //tools/pipeline-status -- <sha>` for the
   squashed commit, then `status` again. If upstream moved meanwhile, sync again.
9. Report the pull request merged, the upstream commit the copy now matches,
   the follow-ups left (above all, routes `server.mjs` still lacks), and anything
   a maintainer must decide.

## What earlier syncs learned

- `BUILD.bazel` is named so because a file named `BUILD` collides with upstream's
  `build/` directory on case-insensitive file systems. Never add a `BUILD` file.
- Bazel tests run in a sandbox with no `.git`, a `node` shim on `PATH`, and an
  event loop that exits when only abandoned promises are left. Upstream tests
  that shell out to git, spawn `node`, or wait on a promise nothing keeps alive
  need the adaptations the list already records. Look there first when one fails.
- `vite-plugin-cesium`'s asset copy fails under rules_js; `vite.config.js` replaces
  it. If upstream changes how Cesium's assets are copied, keep `dist/cesium`
  complete: `cesium_assets_test` checks it.
- pnpm does not hoist transitive dependencies the way npm does, so an upstream
  import of a package npm happened to hoist must be declared in `package.json`.
- The landing view is `HOME_VIEW` (Irvine, CA) in `src/camera.js`.
