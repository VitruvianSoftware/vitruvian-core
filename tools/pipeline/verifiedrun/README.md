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
   commit: context `verified-run`, description `tree=<tree> base=<base> plan=<digest>`,
   linking to the build results.

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

The status must come from a GitHub App that **only** the recorder uses, with
`Commit statuses: write`. Agent apps can't be used, because they open the PRs and
a record must not come from the PR's author. No such App exists yet, so
[`recorder.tsv`](recorder.tsv) is empty and the tool ends with:

> The tests passed, but: not recorded: there is no recorder identity yet.

(exit code 3). To set it up: create the App, install it on this repo, put its
ids in `recorder.tsv`, and put its key at
`tools/sync-env-secrets/agent-keys/verified-run-recorder.pem` in the main
checkout. The token is minted with `//tools/agent-app`'s `token` command;
`GH_TOKEN` and the `gh` login are never used.

Exit codes: 0 passed (and recorded, or `--no-record`, or nothing to test),
1 a test failed or the run can't count as remote, 2 couldn't start,
3 passed but not recorded.

## How the later PR check must verify a record

Count a record only if **all** of these hold. Otherwise run the full tests.

- The context is exactly `verified-run` and the state is `success`.
- Its creator is the recorder App's bot account, compared by numeric id
  (`bot_user_id` in `recorder.tsv`), not by name.
- The PR's head branch is in this repo (not a fork), and an agent app opened it.
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

**Known limit.** The recorder key would sit on the same Mac as the agent keys,
so an agent that went wrong could write a record without running anything. The
merge queue still runs every test on the merged code, so the worst case is a
wasted queue slot, not bad code on main.
