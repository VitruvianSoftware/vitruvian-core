<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 VitruvianSoftware -->

# Vitruvian refactor plan

Status: **in progress**. Each step is one PR that builds and tests green on the
`vitruvian-desktop-macos` unit before the next starts. Steps are ordered so that
each one makes the next safer: the compiler takes over checks that are done by
hand today, and only then does the code get moved around.

The gaps come from the architecture review of the imported code:

- a singleton web with `.shared` cycles;
- 3K-line god-object services;
- feature wiring that fails silently when a list is forgotten;
- untyped preferences;
- convention-only threading;
- a test harness that text-extracts production code and pins source text.

## Step 1: make feature wiring compiler-checked (done)

Problem: adding a feature means editing 12 to 20 files. Several of those lists
fail silently when an entry is missing:

- `FeatureRuntime.bindings` is a dictionary called as `bindings[feature]?()`.
- `AppDelegate` has a hand-kept quit-cleanup list, which has already drifted.
- `AppDelegate` has a hand-kept Accessibility-resync list. It has also drifted:
  `.pastePlain`, `.keepAwake` and `.commandBar` are missing.

Change:

- Turn `bindings` into an exhaustive `switch` over `AppFeature`. A new case then
  fails to compile until it is wired. Features with nothing to start return an
  explicit no-op.
- Derive the Accessibility-resync list from `AppFeature.permissions` instead of
  keeping a second copy.
- Add a test asserting that every feature with a runtime binding is also covered
  by the quit path, or is explicitly marked as needing no cleanup.

Done when: forgetting any of these is a compile error or a failing test, and the
three features dropped from the resync list are back.

Landed:

- `runBinding(for:)` is an exhaustive switch.
- Converting it exposed `connectedDevices`, which had no binding, so
  uninstalling it left SystemMonitor's sampling plan stale. It now re-syncs the
  monitor.
- Both permission sinks re-sync `AppFeature.dependents(on:)`, which is derived
  from `permissions`. That brings back `keepAwake`, `pastePlain`, `commandBar`,
  `notchNotifications`, `screenRecorder` and `cleaningMode` for Accessibility,
  and the switcher, screenshot, OCR and Watch for Screen Recording.
  `FeatureCatalogTests` guards both lists.
- The quit-cleanup check moved to step 2. The audit there found that tying
  quit to the catalog would be unsafe, so it was dropped (see step 2).

## Step 2: make crash recovery explicit (done)

The plan was a shared `FeatureService` protocol, with quit stopping only the
services that had started. Auditing the 25 quit-path calls rejected both parts:

- **Skipping services that never started saves little.** Opening the menu panel
  creates most of them anyway (`QuickControlsSection`), and so does closing it
  (`ProcessUsageService`).
- **Skipping them is unsafe for three.** For each, touching `.shared` at quit
  is what undoes a change a crashed run left behind:
  - Super Key: clears a leftover `hidutil` remap marker;
  - mouse acceleration: reads its on-disk journal;
  - Dock previews: creating the service restores Dock auto-hide.
- **A protocol adds no check.** After step 1, the exhaustive switch already
  makes the compiler check each feature's wiring. A protocol over 67
  `syncWithPreferences()` methods would add no check of its own.

What changed instead:

- **Dock auto-hide is restored at launch.** `DockAutohideHold.recoverIfNeeded()`
  joins the other launch-time recoveries (`FanControlService`, `KeepAwakeManager`,
  `SystemShortcutTakeover`, mouse acceleration):
  - **Before:** restoring auto-hide after a crash waited until something created
    the Dock preview service. With the feature uninstalled, that could be quit,
    so the Dock stayed visible for the whole session.
  - **Test:** `DockAutohideHoldTests` covers it.
- **`applicationWillTerminate` says which calls must stay unconditional,** so a
  later "only stop what started" change cannot drop a recovery.

Left for later steps:

- the quit and self-uninstall teardown lists (`AppDelegate`, `SelfUninstall`)
  stay separate, because they do different jobs: quit undoes system changes,
  while uninstall must stop every event tap before permissions are reset;
- per-service `stop()` semantics become explicit when the services move behind
  module seams (step 3).

## Step 3: split the single target into modules (in progress)

Problem: `App` / `Core` / `Services` / `UI` / `Support` are folders, not
boundaries. The test binary recompiles a hand-picked list of 290 production files,
plus about 590 text-extracted method bodies.

Change, in order:

1. `VitruvianCore`: the `*Support.swift` pure logic, catalogs, preferences keys
   and strings. It must import no AppKit service singletons. Make what other
   modules use `public` (or `package`).
2. `VitruvianServices` (depends on Core) and `VitruvianUI` (depends on Core and
   Services). `App` becomes the thin executable.
3. Tests depend on the modules directly (`@testable import`). Each
   `generate_sources.py` extraction is replaced as the code it targets moves
   behind a module seam, until the script and `bazel/sources.bzl` can be
   deleted.

Done when: Bazel enforces the dependency direction (Core never imports Services
or UI), and no test reads production source as text.

Landed so far (3.1, first cut):

- **`VitruvianCore` is `Core/`, minus 16 files that still reach a service.**
  They are listed in `CORE_FILES_STILL_IN_APP` in `BUILD`.
  - **Contents:** 83 files, which are the preferences keys, localization and all
    15 languages, the strings and pure helpers.
  - **How the set was chosen:** a file-level reference graph found the files
    with no path to a service singleton. Compiling the set as its own module
    with the Linux Swift toolchain proved it closed.
  - **What the graph missed:** it tracks type names, not extension members.
    `AppKitExtensions.swift` uses `NSScreen.displayID`, which a screenshot
    service declares, and Linux cannot compile AppKit files, so only macOS
    CI caught it. It stays in the app.
- **Supporting moves:**
  - `DefaultsKey` moved out of `Defaults.swift`, whose defaults table still
    references about 30 `*Support` types.
  - `KeepAwakeAutomationSupport.swift` and `ScratchpadSupport.swift` moved into
    `Core/`.
- **Access:**
  - Declarations in the module are `package`, so the app and tests (same Swift
    package) see them and nothing else does.
  - Three structs the app or tests build with a memberwise initializer now spell
    it out.
- **Tests:** the test binary depends on the module instead of recompiling it.
  - `generate_sources.py` reads past a `package` modifier.
  - The French punctuation check would otherwise have passed while scanning
    nothing. It now fails if it reads no French block.

Next for 3.1:

- move the `*Support` types that `Defaults`, `FeatureCatalog` and the remaining
  strings need;
- split `Permissions.swift` from the permission guide UI it opens.

## Step 4: dependency injection at the seams that tests need

Problem: services take no collaborators. Tests fake them by shadowing type names
inside the test module.

Change:

- Constructor injection for the collaborators tests replace today: UserDefaults,
  the clock, NSWorkspace, the pasteboard, the HAL and the queues.
- `.shared` stays as the production composition root.
- Break the `.shared` cycles (Notch ↔ Shelf, Notch ↔ Brightness,
  Notch ↔ PreciseVolumeRoller) with events or closures owned by the composition
  root.

## Step 5: decompose NotchService

Problem: NotchService has 3,400 lines and about 14 responsibilities. It has 33
outbound singletons and 119 inbound call sites. View-layout math is duplicated
between it and the views, and the copies have already diverged.

Change: extract, one PR each:

- session/lock tracking
- display and mirror selection
- menu-bar space measurement
- the notice/HUD queue
- the capture-controls host
- file-drop routing
- event bindings

Move the shared geometry into `NotchGeometry` as the single source used by both
the service and the views. `AgentUsageService` is the template: documented thread
ownership, pure helpers in enums, no outbound `.shared`.

## Step 6: typed preferences and explicit concurrency

- Preferences: a typed key (`Preference<Value>` carrying its default) replaces the
  795 string constants plus the defaults dictionary, so `@AppStorage` and service
  reads share one default.
- Concurrency: mark UI-state holders `@MainActor`. Turn on Swift 6 strict
  concurrency module by module, Core first.

## Step 7: test-suite hygiene

- Run `Tests/mutation_checks.py` in CI (nightly or `manual`), so weak tests are
  caught.
- Replace the roughly 440 source-substring assertions with behavioral ones as the
  code they guard moves (steps 3 to 5).
- Move to Swift Testing once tests link modules instead of extracted text.

## Not in scope

Product decisions remain open:

- own temporary-link and feedback backends;
- community channels;
- versioning;
- the release pipeline.

`UPSTREAM.md` lists them as release blockers.
