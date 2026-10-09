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
  notices, not branding. Releases ship as DMGs from the `vitruvian` delivery
  unit (`publish.sh`); check anything that lands in the bundle (artwork, GIFs,
  strings) for upstream's brand first.

## Building

- Use Bazel with `--config=macos-app` (see `README.md`). The targets are
  `manual`, so name them explicitly. Do not wire `build.sh` into CI: it stays only
  because upstream tests read its text.
- `Core/`, `Design/` and `UI/` build in Swift 6 mode. Shared state there
  says what protects it: a lock or the main thread (`nonisolated(unsafe)`
  with a comment naming the guard), `@MainActor`, or `Sendable`. Isolate a
  type that Swift 5 modules use with `@preconcurrency @MainActor`, so its
  callers are not broken before their module moves to Swift 6.
- In `UI/`, AppKit glue (coordinators, delegates, NSView subclasses) is
  `@MainActor`; a main-queue observer reaches it through
  `MainActor.assumeIsolated`; a closure that runs on a background queue
  takes plain values, never the view or a service.
- A Services API that runs a caller's closure off the main thread takes it
  `@Sendable`. Otherwise a closure from `UI/` (Swift 6 mode) checks at run
  time that it is on the main thread, and stops the app when it is not.
- In a view, pass one of its methods as an optional action through a
  closure, `granted ? nil : { grant() }`, not by name, `granted ? nil :
  grant`. The named form makes the compiler fail with "failed to produce
  diagnostic" once the module is checked for Swift 6.
- A new preference goes in `Core/Preferences.swift` as a `Preference` with
  its default. `Defaults.registeredDefaults` registers it from there, views
  use `@AppStorage(Preferences.x) var x: Bool` (with the type written out),
  and nothing else spells out the default. Code reads and writes it as
  `defaults[Preferences.x]`, not by its `DefaultsKey`. `source_lints_test`
  counts what still reaches a declared key by name, and only lets that
  count fall.
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
  - the quit cleanup: `AppDelegate`'s list and `QuitInputRelease`
  - `FeatureVisibilitySupport.features(for:)`
  - `Core/Defaults.swift` keys and defaults
  See `REFACTOR.md` for the plan to close those gaps too.
- An action a surface can trigger is a command. Add it as a `BuiltinCommand`
  case (`Core/Platform/BuiltinCommand.swift`) and give it a handler in
  `Services/Platform/BuiltinTools.swift`; the compiler asks for the handler.
  The radial menu, the Quick panel and the command bar run commands through
  `ToolRegistry`, and the command bar also lists them from it. Do not add a
  service call to a surface's own switch.
- A surface that lists tools has two sources: its own fixed list, and
  `ToolRegistry.extraCommands(on:)`, the commands that ask for that surface
  and that the fixed list does not already offer. Never list
  `commands(on:)` straight onto the Quick panel or the wheel: every built-in
  command is in it, and each would appear twice. A built-in command asks for
  a surface in `BuiltinTools.install` only when something there already runs
  it.
- A saved order may hold an id the app does not recognise right now: a tool
  that has not registered yet, or one that is switched off. Keep it where it
  is (`QuickToolsSupport.savedTileOrder`); drop only what is not well formed.
- To see a tool that is in no fixed list, build with
  `--define=vitruvian_sample_tool=true` (`Services/Platform/SampleTool.swift`).
- A global shortcut lives in one of several lists: `GlobalShortcutRole` (and
  the radial wheels it reads), window-layout actions, Command Bar rows, and
  tool commands. Anything that records one asks all of them before it saves:
  `GlobalShortcutRole.conflict`, `WindowLayoutService.shortcutConflictTitle`,
  then `ShortcutConflicts.title`, which covers rows and tool commands. A new
  list of shortcuts is added to `ShortcutConflicts`, not checked by hand at
  each recorder. A Reset button and an accepted macOS take-over write a
  combination too, so they ask the same lists before they save (the role
  and window-layout rows through `ShortcutConflicts.write`).
- A hotkey registrar that is tied to no hub feature must be re-synced in
  `ShortcutCapture.end()`: recording releases every key the app holds, and
  only each feature's own sync gives them back. Leaving this out fails
  silently, after the first shortcut the person records.
- One of the app's own commands that already has a `GlobalShortcutRole` does
  not also ask for the `shortcut` surface: that would give one action two
  combinations.
- `ToolShortcutRegistrar.assign` refuses a combination another tool command
  has saved and returns why; it never moves one. Its hotkey ids run from
  `ToolShortcutRegistrar.firstHotkeyID`, and `bazel/source_lints.py` keeps
  that run clear of the others.
- Every user-facing string needs all 15 `AppLanguage` cases. Each strings file
  switches over them exhaustively, so a missing one is a compile error.
- User preferences must take part in settings backup. Machine-specific state and
  private content need an explicit exclusion.
- Tests check through `TestSuite` (`Tests/TestSuite.swift`) and run under Swift
  Testing, one case per suite listed in `Tests/TestGroups.swift`. A new
  contract runs from a suite there or from a contract that already runs;
  `TestRegistrationTests` fails on one that nothing runs. Write behavioral
  tests: no unit test reads a source file as text, and
  `bazel/source_lints.py` (`source_lints_test`) fails on one that does. A
  rule about how all of the code is written, not about what one piece of it
  does, is a lint: add it there, with a mutation that shows it fails.

## Features that are also standalone apps

Nexus Agent ships twice: as its own app (`apps/desktop/nexus-agent`) and as a
feature here. The code both share lives in the standalone's folder, under MIT,
and this app holds only what is specific to it.

- Change a shared rule in `apps/desktop/nexus-agent/macos/Sources/NexusAgentCore`,
  never by copying it back here.
- Shared code takes its settings, text, theme and host hooks as inputs. It
  never imports a `Vitruvian*` module.
- `build.sh` and `Package.swift` here cannot see the shared library. Bazel is
  the only build of this app; `build.sh` stays as the source list upstream's
  tests read.
- After changing shared code, run
  `bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared` and add a line to
  the log in `UPSTREAM.md`. `nexus_agent_shared_pin_test` fails until you do.
- Nothing upstream wrote may leave this folder. A file leaves only if
  VitruvianSoftware wrote all of it, and `UPSTREAM.md` records it.
- The next standalone app that becomes a feature here follows the same shape.

## Porting from upstream

- Follow `UPSTREAM.md`, "Tracking and porting upstream". Start a port with
  `bazel run //apps/desktop/vitruvian:track_upstream -- port <sha>...`. Never copy
  upstream files over this tree: that undoes the rename and the refactor.
- Update the ledger (`upstream/ledger.tsv`) in the same PR: `ported` with the PR
  number, or `skipped` with why. `bazel test //apps/desktop/vitruvian:upstream_test`
  checks it.
- A port is not done while the tool's report lists a brand-review line. Nothing
  may point at upstream's brand, servers, update feed or repository.

## Verifying

`bazel test --config=macos-app //apps/desktop/vitruvian:unit_tests
//apps/desktop/vitruvian:selftest` is the minimum before claiming a change works.
Tests and `--selftest` do not exercise windows, permissions or hardware. For those,
describe what you actually ran and on which Mac and macOS version, and state what
remains untested.
