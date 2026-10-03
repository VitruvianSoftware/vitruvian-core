# Agent guide: apps/desktop/vitruvian

This guide adds to the root `AGENTS.md` for this subtree. Read
[`UPSTREAM.md`](UPSTREAM.md) first.

## Hard rules

- **This directory is GPL-3.0-or-later.** Never edit or remove an upstream
  `SPDX-License-Identifier` / `Copyright (C) 2026 Vorssaint` header. New files
  get `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 VitruvianSoftware`, never the monorepo's Apache/MIT
  header. Never copy code from here into Apache-licensed parts of the repo.
- **Log every change to an upstream file** with a dated entry under
  "Modifications" in `UPSTREAM.md` (GPL-3.0 §5(a)).
- **Never use upstream's brand or services.** No Vorssaint name, icon, bundle ID,
  update feed, upload/feedback server or community link in what the app shows or
  calls (see `TRADEMARKS.md`). Keep upstream's copyright lines, which are legal
  notices, not branding. Publish nothing until the release blockers in
  `UPSTREAM.md` are cleared.

## Building

- Use Bazel with `--config=macos-app` (see `README.md`). The targets are
  `manual`, so name them explicitly. Do not wire `build.sh` into CI: it stays only
  because upstream tests read its text.
- After changing the test, fan-helper or Now Playing source lists in `build.sh`,
  or the extractions in `Tests/generate_sources.py`, run
  `bazel run //apps/desktop/vitruvian:sync_sources`.
- Swift has no Gazelle. `BUILD` is hand-written and carries `# gazelle:ignore`.
- `Core/` is its own module, `VitruvianCore`, which depends on no other app
  module:
  - What the app or tests use from it must be `package` (an implicit
    memberwise initializer is never visible outside, so write it out).
  - Every app and test file imports it.
  - A new `Core/` file that needs a service, view or singleton does not belong
    there. If it must stay for now, add it to `CORE_FILES_STILL_IN_APP` in
    `BUILD`.

## Conventions (from upstream)

- App lifecycle lives in `Sources/Vitruvian/App`, shared catalogs and preferences
  in `Core`, behavior in `Services`, views in `UI`, diagnostics in `Support`.
  Keep decisions outside views where tests can reach them. Pure logic goes in a
  `*Support.swift` file with injectable `UserDefaults`.
- A new feature needs an `AppFeature` case in `Core/FeatureCatalog.swift`. The
  compiler enforces its switch arms, including `FeatureRuntime.runBinding(for:)`.
  Permission re-syncs derive from `permissions`. The compiler does **not**
  enforce these, so check each one:
  - `AppDelegate`'s quit-cleanup list
  - `FeatureVisibilitySupport.features(for:)`
  - `Core/Defaults.swift` keys and defaults
  See `REFACTOR.md` for the plan to close those gaps too.
- Every user-facing string needs all 15 `AppLanguage` cases. Each strings file
  switches over them exhaustively, so a missing one is a compile error.
- User preferences must take part in settings backup. Machine-specific state and
  private content need an explicit exclusion.
- Tests use the custom runner in `Tests/TestSuite.swift`, registered by hand in
  `Tests/MetricsTests.swift`. A test file that is not registered compiles and
  never runs. Write behavioral tests, not assertions on source text.

## Verifying

`bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests
//apps/desktop/vitruvian:selftest` is the minimum before claiming a change works.
Tests and `--selftest` do not exercise windows, permissions or hardware. For those,
describe what you actually ran and on which Mac and macOS version, and state what
remains untested.
