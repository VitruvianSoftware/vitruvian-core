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

Landed (3.1, first cut):

- **`VitruvianCore` is `Core/`, minus 16 files that still reach a service.**
  They were listed in `CORE_FILES_STILL_IN_APP` in `BUILD` (gone since 3.1c).
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

Landed (3.1b, the catalog and its helpers):

- **One edge cut, 65 files joined.** Nearly every remaining `Core/` file
  reached a service through a single chain: `Defaults` → `MixerRoutingSupport` →
  `AirPlayRouteManager`, for one constant. The constant
  (`airPlaySentinelUID`) now lives in `MixerRoutingSupport`, and the route
  manager keeps an alias.
  - **Joined:** `Defaults`, `FeatureCatalog`, `FeaturePresets`,
    `GlobalShortcut`, `SymbolicHotKeys`, `SettingsBackupSupport` and the
    remaining strings.
  - **Moved into `Core/`, keeping their folder names:** the 50 pure `*Support`
    and model files they need, from `Services/`.
- **`FanControlKit`** is a third module, holding `FanControlSupport.swift` and
  `TemperatureSensorSelector.swift`.
  - **Dependents:** `Defaults` needs their default values, and the privileged
    fan helper compiles them too. Both depend on the module, and the helper
    links nothing else of the app.
  - **Imports:** Core re-exports the module (`@_exported import`), so app code
    sees it through `import VitruvianCore`. The helper's `main.swift` and the
    three files it shares with the app import it directly.
- **Still in the app:**
  - `AppKitExtensions` needs a screenshot service's `NSScreen.displayID`.
  - `Permissions` opens the permission-guide UI.
  - `SecureInputMonitor` is a singleton service.
- **Initializers:** 197 initializers are spelled out, because a synthesized
  initializer never leaves its module and outside code builds these types, by
  name or as a contextual `.init(...)`.
  - **What gets one:** every struct and class in the module without an
    initializer of its own, except the `*Strings` family, which only Core
    builds.
  - **How:** a generator writes the memberwise initializer, following Swift's
    synthesis rules: a `let` with a default is excluded, a `var` keeps its
    default, and an optional `var` defaults to `nil`.
  - **Private stored properties:** the synthesized initializer is fileprivate,
    so those types get `package init() {}` when they are built outside as
    `Foo()`. Otherwise they are left alone.
- **Checks that ran before macOS, all on Linux:**
  - The module type-checks with SDK stand-ins, and no error is new beyond SDK
    gaps.
  - A hidden-dependency scan matches every missing-member error against
    extensions declared outside the module. It finds the `displayID` case
    above, and nothing in this set.
  - No top-level test declaration shadows a name the module uses.
  - Generated test sources are byte-identical.
  - Source-text pins naming a full moved path were updated. One test builds
    the path from a relative fragment (`"Sources/Vitruvian/\(file)"`), which
    that search missed; macOS CI caught it, and a rescan of every app file
    for relative fragments of all 52 moved paths found no other.

Landed (3.1c, the folder is the module):

- **`AppKitExtensions` joined.** `NSScreen.displayID` moved into it from
  `ScreenshotCaptureEngine.swift`, which was the only edge to a service.
- **`Permissions` and `SecureInputMonitor` moved to `Services/`.** Each is a
  singleton that owns live system state, which is what a service is, so by
  this step's own rule neither belongs in Core. The earlier plan was to split
  the permission-guide call out of `Permissions`, but that would still have
  left a service singleton in Core. No Core file uses either.
- **`CORE_FILES_STILL_IN_APP` is gone.** `VitruvianCore` is now exactly the
  `Core/` folder: a file there that reaches a service fails to compile.
- **Checks that ran before macOS, on Linux:** the whole folder type-checks as
  one module with the SDK stand-ins, adding only SDK-gap errors (`NSScreen`
  members the stand-in lacks), and the hidden-dependency scan finds nothing.

### 3.2: interfaces first, then the split

The split waits until nothing points the wrong way, so each module lands
without exceptions. Measured at the start (type names and top-level
functions, comments and strings blanked): 145 wrong-way references.

- **`Services` -> `UI`, from 35 files.** Four kinds:
  - pure types filed under `UI/` (settings destinations, `PermissionKind`,
    panel layout models);
  - window primitives (`OverlayPanel` in 23 files, `HUDBackdrop`,
    `NonModalAlert`, `PlainTextEditor`);
  - services that build their own SwiftUI view (about 25 views);
  - the Notch cluster, mostly `NotchService`.
- **`UI` -> `App`, from 32 files:** `FeatureRuntime` in 23, then menu-bar
  types and `AppDelegate`.
- **`Services` -> `App`, from 6 files:** `FeatureRuntime` and `AppDelegate`.

The order:

1. **3.2a, move what is filed in the wrong layer** (landed, below).
2. **3.2b, the app shell:** an `AppShell` interface in front of
   `AppDelegate` (open Settings, close the popover, status-item hit test),
   and the status-item grouping out of `StatusItemController`. The settings
   destinations and `PermissionKind` move down.
3. **3.2c, presentation:** window primitives move below Services, and
   services stop building feature views. They ask a view factory that `UI`
   implements and `App` wires at launch.
4. **3.2d, the Notch cluster.**
5. **3.2e, the split:** `VitruvianServices` and `VitruvianUI` targets in
   `BUILD`, and `bazel/layering.py` retires once Bazel holds the direction.

Landed (3.2a, the ratchet and the misfiled files):

- **`layering_test`** (Linux, in the pipeline unit) fails on any wrong-way
  reference missing from `bazel/layering_baseline.txt`, and on any baseline
  line that no longer occurs, so the baseline only shrinks.
  - Proved both ways: a planted `StatusItemController` reference from a
    service fails it, and so does a stale line.
  - It matches type names, top-level function calls and globals. Its first
    version saw types only and missed `appDelegate()`, a top-level function in
    `UI/` that five services call. It misses extension members declared in a
    later layer, which Bazel catches once the modules exist.
- **Moves:** 145 references became 100.
  - `FeatureRuntime` moved to `Services/`. It references 77 services and
    nothing in `UI/` or `App/`: it is the service orchestrator, not the app
    shell. That alone cut 27 files' references.
  - `AppAppearanceController` moved to `Services/`, and `MenuBarRenderer.swift`
    (the menu-bar metric models and the segment builder, which read service
    snapshots) to `Services/MenuBar/`.
  - The pure `MenuBarSpacingSupport`, `MenuBarAllowanceSupport`,
    `StatusItemAnchorSupport` and `ReopenRequestSupport` moved into Core,
    which made them `package` and spelled out two initializers.
  - `BlackHoleGlyph`, the menu-bar mark's drawing, moved out of
    `StatusItemController.swift` into `UI/`.

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
