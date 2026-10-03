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
- `Core/` and `Design/` build in Swift 6 mode. Shared state there says what
  protects it: a lock or the main thread (`nonisolated(unsafe)` with a
  comment naming the guard), `@MainActor`, or `Sendable`. Isolate a type
  that Swift 5 modules use with `@preconcurrency @MainActor`, so its callers
  are not broken before their module moves to Swift 6.
- In a view, pass one of its methods as an optional action through a
  closure, `granted ? nil : { grant() }`, not by name, `granted ? nil :
  grant`. The named form makes the compiler fail with "failed to produce
  diagnostic" once the module is checked for Swift 6.
- A new preference goes in `Core/Preferences.swift` as a `Preference` with
  its default. `Defaults.registeredDefaults` registers it from there, views
  use `@AppStorage(Preferences.x) var x: Bool` (with the type written out),
  and nothing else spells out the default.
- `Tests/mutation_checks.py` plants real regressions and requires each to fail
  its test. It runs weekly in CI. Moving or rewording code that a mutation
  quotes breaks that run, so update the mutation in the same change.
- After changing the test, fan-helper or Now Playing source lists in `build.sh`,
  or the extractions in `Tests/generate_sources.py`, run
  `bazel run //apps/desktop/vitruvian:sync_sources`.
- Swift has no Gazelle. `BUILD` is hand-written and carries `# gazelle:ignore`.
- `Core/` is its own module, `VitruvianCore`, which depends on no other app
  module:
  - What the app or tests use from it must be `package` (an implicit
    memberwise initializer is never visible outside, so write it out).
  - Every app and test file imports it.
  - The module is the whole folder. A file that needs a service, view or
    singleton does not belong there: put it under `Services/` or `UI/`.
- The folders have one direction: `Core` <- `Design` <- `Services` <- `UI` <-
  `App` (with `Support` and `main.swift`). Each of the first four is a module,
  so Bazel holds the direction: a file that names something from a later layer
  does not compile. Cut such an edge (move the type down, or put an interface in
  front of it) rather than working around it. `Design/` holds the AppKit and
  SwiftUI building blocks that services and views share (panels, backdrops,
  editors), and knows no feature.
- `NotchService` names no service that follows it. When the island needs
  something new from one, add a hook to `NotchCollaborators` and wire it in
  `main.swift`, the composition root.
- Below `App/`, reach the running app through `appShell()` (the `AppShell`
  protocol), never `AppDelegate`. Add a requirement there when a service or
  view needs something new from it.
- A service shows SwiftUI content through `ServiceViews.factory`
  (`ServiceViewFactory`), never by naming a view. A new hosted view gets a
  method there and in `UI/UIServiceViewFactory.swift`.
- `Design/` is the `VitruvianDesign` module, which depends on Core alone. The
  same rules apply as for Core: what others use is `package`, initializers are
  spelled out, and every app and test file imports it. The exception is the
  files the fan helper or the Now Playing adapter also compile. A class that
  another module subclasses must be `open`, with its overrides `public`
  (`OverlayPanel`).
- `Services/` is the `VitruvianServices` module, which depends on Core and
  Design. The same rules apply again: every struct spells out its
  initializer, and a type that outside code builds as `Foo()` despite private
  stored properties spells out `package init() {}`. An extension member that a
  later layer declares is invisible to a service: put it in the lowest layer
  that uses it.
- `UI/` is the `VitruvianUI` module, which depends on Core, Design and
  Services; `App/`, `Support/` and `main.swift` are the app around it. The same
  rules apply. A SwiftUI view that `App/`, `Support/` or a test builds spells
  out its initializer, taking what the synthesized one took: its non-private
  stored properties, a `Binding` for a `@Binding`, the object for an
  `@ObservedObject`, closures `@escaping`.
- `FanControlKit/` is a third module, shared by Core and the privileged fan
  helper. Core re-exports it, so app code needs no extra import. Files that the
  helper also compiles import it directly.

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
