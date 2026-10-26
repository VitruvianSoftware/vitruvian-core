# `//tools/pipeline/verifiedrun`

Runs the tests a pull request would run in CI, on the same remote build machines
CI uses, and records a pass against the exact code. Part of
[#3418](https://github.com/VitruvianSoftware/vitruvian-core/issues/3418), Step 2.
An agent runs it before opening or updating a PR:

```sh
bazel run //tools/pipeline/verifiedrun
bazel run //tools/pipeline/verifiedrun -- --no-record   # check only
```

Nothing uses the record yet. A later change will let the PR workflow skip its
heavy test jobs when a valid record exists. The merge queue stays the real gate
either way.

## What it does

1. Refuses if the working tree has uncommitted or untracked files. The record
   names HEAD's files, so the tests must run on exactly those.
2. Takes git's **tree hash** of HEAD. It changes when any file changes and
   doesn't change when only the commit message or a rebase does.
3. Asks CI's own tools what to test, compared with the merge base with
   `origin/main`:
   - **presubmit units**: the planner (`//tools/pipeline/plan`), with the same
     flags and dependency map as the presubmit `plan` job;
   - **build-test**: `tools/ci/affected-targets.sh`, unchanged, as on a PR.
4. Runs them through a `bazel` wrapper that forces every build and test onto the
   remote machines (see "Remote only" below) and logs each run's BuildBuddy link
   and Bazel's count of where each process ran.
5. If everything passed **and** ran remotely, writes a commit status on the head
   commit as the recorder (scout): context `verified-run`, description
   `tree=<tree> base=<base> plan=<digest>`, linking to the build results.

It prints what it ran, why, and what it left to CI.

## What it leaves to CI

- Units on macOS runners (the remote machines are Linux), units that need an
  Android emulator, and units that build files CI uploads.
- The fast checks (secret scan, licence, vulnerability scan, conformance, tidy)
  and every other CI job (macOS build, race tests, lint, ...).

A record covers only the lanes it names (`build-test`, `unit:<name>`).

## Remote only

The wrapper adds these flags last, so nothing a script passes can override them:
`--config=remote`, Linux `--platforms`/`--host_platform`/`--extra_execution_platforms`
(without them a Mac picks Mac toolchains), `--spawn_strategy=remote`,
`--noremote_local_fallback`, `--noremote_upload_local_results`, `--disk_cache=`,
`--nocache_test_results`, plus `COMMIT_SHA`/`TREE_SHA` build metadata.

A run counts only if Bazel reports every process as `remote`, `remote cache hit`,
`internal` or `action cache hit` (a build step already in this output base;
tests never count that way, because test results aren't cached). Anything else,
such as `darwin-sandbox`, `local`, `worker` or `disk cache hit`, means work ran
on the laptop, and the run is refused.

The BuildBuddy key comes from `user.bazelrc`: the workspace's own, or else the
main checkout's (loaded with `--bazelrc`, never both). With no key it refuses.
There is no local-only mode: CI could not trust it.

## Recording

The status is set by the one identity named in [`recorder.tsv`](recorder.tsv):
the **scout** agent's App (bot user id `314429511`). It is the only agent App with
`Commit statuses: write`, granted by James on 2026-10-16 and listed in
`tools/agent-app/permissions.tsv`. The tool checks that `recorder.tsv` agrees
with `tools/agent-app/agents.tsv`, mints scout's one-hour token with
`//tools/agent-app`'s `token` command from `scout.pem` in the agent key folder
(the main checkout's `tools/sync-env-secrets/agent-keys`, or `$AGENT_KEY_DIR`),
and never uses `GH_TOKEN` or the `gh` login. After writing, it reads GitHub's
reply and refuses to call it recorded unless GitHub says scout set it.

The commit must be pushed first; GitHub can't put a status on a commit it doesn't
have.

Exit codes: 0 passed (and recorded, or `--no-record`, or nothing to test),
1 a test failed or the run can't count as remote, 2 couldn't start,
3 passed but not recorded (the message says why).

## How the later PR check must verify a record

Count a record only if **all** of these hold. Otherwise run the full tests.

- The context is exactly `verified-run` and the state is `success`.
- Its creator is scout's bot user, compared by numeric id `314429511`
  (`recorder.tsv`), not by name.
- The PR's head branch is in this repo (not a fork), and an agent app opened it,
  but **never scout itself**: a record must not come from the PR's author.
- `tree=` equals the tree hash of the PR head.
- `base=` equals the PR's merge base with main.
- It is recent (for example, under 24 hours old).
- `plan=` equals the digest the check computes itself with the same planner
  and script (a dry-run wrapper that lists targets instead of running them),
  taken from the **base branch**, not the PR, so a PR can't change what's
  required of it.
- The linked BuildBuddy runs, read back with CI's own key, succeeded and ran
  remotely.
- It skips only the lanes the record names.

Nothing a PR author controls can switch the heavy jobs off: not a label, not a
file in the PR, not a status set with their own token.

**Known limit.** The recorder key sits on the same Mac as the other agent keys,
so an agent that went wrong could write a record without running anything. The
merge queue still runs every test on the merged code, so the worst case is a
wasted queue slot, not bad code on main.

## Rust and Go

`:verifiedrun` is the Rust port (`src/`); the Go original stays as
`:verifiedrun-go`. It runs `//tools/pipeline/plan`, which is the Rust planner
too (the Go one is `//tools/pipeline/plan:plan-go`). Both pairs are held to
the same behaviour by `verifiedrun_rs_parity_test` and `plan_rs_parity_test`,
which run Go and Rust side by side and require the same output, exit codes and
bazel command lines.
