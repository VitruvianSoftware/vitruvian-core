# Weekly upstream sync

The steps an agent follows to port everything upstream published since the last
sync and land it on `main`. A scheduled Claude Code routine runs it every Monday
morning, Pacific time, in a fresh cloud session that reads this file from
`main`. Anyone can run it by hand the same way.

The routine itself lives in James's Claude account, not in this repository: it
holds only the schedule and a pointer to this file. To change how the sync works,
change this file in a pull request; the next run follows the version on `main`.

The process it carries out is the one in [`UPSTREAM.md`](../UPSTREAM.md),
"Tracking and porting upstream", which stays the authority: the ledger, the
`track_upstream` tool, triage, porting and the commit format. Read it first, with
the repository's [`AGENTS.md`](../../../../AGENTS.md) and this app's
[`AGENTS.md`](../AGENTS.md). This file adds the order of work and what earlier
syncs learned.

## Goal

Every upstream commit is in the ledger, none is `pending`, and every port is on
`main` with its checks green.

## Steps

1. Start from the latest `origin/main`. If an open pull request already ports an
   upstream batch (its title contains "port upstream batch"), drive that one to
   merged before starting another.
2. Run `bazel run //apps/desktop/vitruvian:track_upstream -- status`. If nothing
   is untriaged or pending, stop and report "caught up at" the upstream commit.
3. Run `triage`, and commit the ledger on its own as
   `chore(vitruvian): triage N upstream commits from <date>`.
4. Port the pending commits oldest first, one commit in this fork per upstream
   commit. Keep a pull request to about 15 ports, and land them one at a time.
   For each upstream commit:
   - run `port <sha>` and read its `report.md`;
   - resolve the conflicts against the refactored code;
   - commit in the format `UPSTREAM.md` gives, with an "Adapted to this fork:"
     paragraph naming every way the port differs from upstream, and every
     upstream check left out and why.
5. Before every push, run
   `bazel test //apps/desktop/vitruvian:source_lints_test //apps/desktop/vitruvian:sources_in_sync_test //apps/desktop/vitruvian:upstream_test`
   and check its exit status. Piping it through `tail` hides a failure. Linux has
   no Swift compiler, so read the diff again against the rules below.
6. Open the pull request, titled
   `feat(vitruvian): port upstream batch <n>, <summary>` and numbered after the
   last merged batch. Its body is a table of each upstream commit, what changes
   for Vitruvian and how it was ported, then a test plan. Then push a commit that
   sets the ported ledger rows to `ported` with the pull request's number
   (`check-ledger` must pass), turn on auto-merge, and follow the pull request's
   activity.
7. Drive it to merged. `vitruvian-desktop-macos` is the first job that compiles
   the port. Read its log, find the lines matching
   `\.swift:[0-9]+:[0-9]+: error`, `FAILED` or `failed to build`, fix them, run
   the Linux checks again and push. A failure on a commit your own push replaced,
   whose jobs it cancelled, is not a failure. Never skip or disable a test. If a
   port cannot be made green after a few honest attempts, leave the pull request
   open with one comment naming what blocks it, and report that.
8. After it merges, run `bazel run //tools/pipeline-status -- <sha>` for the
   squashed commit, then `status` again. If upstream moved meanwhile, port the
   next batch.
9. Report the pull requests merged, the upstream commit the fork is now caught up
   with, anything skipped or left pending and why, and anything a maintainer must
   decide.

## What earlier syncs learned

- Core, Services, UI, the app and the tests are separate Swift 6 modules.
  Anything another module or a test uses must be `package`: new types, their
  members, static helpers and initializers. Write out a `package init`, because
  a memberwise initializer never leaves its module.
- A stored static or global of a type that is not `Sendable` does not compile in
  Swift 6; make it computed. A closure handed to `MainActor.assumeIsolated` must
  not capture a value that is not `Sendable`: copy what it needs into a local
  first. Work off the main thread must not read main-actor state.
- The self-test runs the app's launch path, so a crash there usually means new
  code that runs at launch.
- A new preference goes in `Core/DefaultsKey.swift`, `Core/Preferences.swift`
  and `Core/Defaults.swift`, registered with `Preferences.x.defaultValue`. Views
  read it with `@AppStorage(Preferences.x)` and services with
  `defaults[Preferences.x]`.
- Tests are behavioural: none reads source text, and none runs a generated copy
  (`Tests/generate_sources.py` is retired). When the code under test is private,
  move the rule into a `package` function or value the test can call, as
  `URLCleaning.StoredRules`, `URLCleaning.markupAddsOnlyFormatting` and
  `ClipboardSourceWindow` were. Otherwise leave the check out and say why in the
  commit.
- A new format string or SF Symbol goes in `Tests/SourceNames.swift`;
  `source_lints_test` names the ones missing.
- Upstream's brand, domains and services never come in
  ([`TRADEMARKS.md`](../TRADEMARKS.md)). Upstream's files keep upstream's
  copyright notice. Reverse-DNS names use `com.vitruviansoftware.vitruvian`.
