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
2. **3.2b, the app shell and settings navigation** (landed, below).
3. **3.2c, presentation**, in two parts:
   - **3.2c-1, building blocks and models down** (landed, below);
   - **3.2c-2, the view factory** (landed, below).
4. **3.2d, the Notch cluster** (landed, below).
5. **3.2e, the split**, one module per step, smallest first:
   - **3.2e-1, `VitruvianDesign`** (landed, below);
   - **3.2e-2, `VitruvianServices`** (landed, below);
   - **3.2e-3, `VitruvianUI`.** `App` stays the executable's library.

   `bazel/layering.py` retires once Bazel holds the whole direction.

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

Landed (3.2b, the app shell and settings navigation): 100 references became
75, and nothing outside `App/` names `AppDelegate` any more.

- **`AppShell`** (`Services/AppShell.swift`) is what services and views may
  ask of the running app: open Settings and the intro windows, close the
  popover, hit-test the status item, show the permission guide, relaunch.
  - `appShell()` replaces `appDelegate()` and every
    `NSApp.delegate as? AppDelegate`. It is still the delegate underneath, so
    behavior is unchanged.
  - The protocol is not `@MainActor`. Its callers are services that are not
    actor-isolated, and in the Swift 5 mode a call from them into an
    explicitly main-actor protocol is a compile error (tried on the Swift 6.4
    toolchain). The delegate's own isolation comes from AppKit's
    `@preconcurrency` protocols, so it never stopped those calls.
  - `AppDelegate` conforms in `App/AppDelegate+AppShell.swift`. The
    requirements use its own signatures, and a protocol extension supplies the
    short forms with its defaults. The overloads were tried on the Swift 6.4
    toolchain first: inside the delegate and through the protocol, every call
    resolves to the intended method.
  - `Permissions` shows its guide through the shell, so the service no longer
    names the overlay.
- **Settings navigation moved down.**
  - `FeatureVisibilitySupport`, `SettingsSearchSupport` and
    `SettingsSidebarSupport` moved into Core: destinations, the router (a pure
    state machine), search and sidebar. They became `package`, and seven
    initializers are spelled out.
  - `PermissionKind` moved into Core, and `SettingsDirectory`, which reads two
    services, moved to `Services/Settings/`.
- **`SettingsHistoryNavigating`** is a Core `@objc` protocol for the Settings
  window's Back and Forward actions. The mouse-navigation service finds those
  menu items by its selectors, and the window conforms, so the compiler still
  ties the selectors to the window.
- **The metric status grouping** moved from `StatusItemController` into
  `MenuBarRenderer`, which the Settings preview already reads.
- **Tests:** five contracts that stubbed the delegate for extracted code now
  stub `appShell()`.
- **Checks that ran before macOS, on Linux:**
  - Core type-checks with the moved files, and the only new error is `@objc`,
    which Linux cannot compile.
  - The hidden-dependency scan finds nothing, and no test declares a moved
    name.

Landed (3.2c-1, building blocks and models down): 75 references became 40.

- **`Design/`** is a new layer between Core and Services, for the AppKit and
  SwiftUI building blocks that services and views both draw with. It knows
  no feature.
  - **Moved in:** `OverlayPanel` (named from 23 service files),
    `NonModalAlert`, `PlainTextEditor` and `MixerPercentNativeTextField`;
    `HUDBackdrop` (out of `SharedUI.swift`); and `Theme`'s space gradient (out
    of `Theme.swift`, as `SpaceGradient.swift`).
  - **Why a layer, not Core or Services:** Core is pure logic and Services is
    behavior. A panel or a backdrop is neither, and both need it.
  - `layering.py` ranks it: `Core` <- `Design` <- `Services` <- `UI` <- `App`.
- **Models that services own moved to `Services/`:**
  - `BackdropEditing`, the protocol both editor models conform to, out of the
    picker's view file;
  - `PanelInteractionState`, which is state, not a view;
  - `BreakdownKind`, which the process sampler is keyed by.
- **Checks that ran before macOS, on Linux:**
  - No `Design` file names a later layer, and none uses an extension member
    declared in one. A scan matched every `.member` against later-layer
    extensions.
  - The same holds for the three files that moved into Services.
  - No file name is used twice in a module.
  - Every test-compiled file still finds the types it uses in the test set.
  - The source pins on the split files (`SharedUI`,
    `ScreenshotBackdropPopover`, `Theme`) read text that stayed.

Landed (3.2c-2, the view factory): 40 references became 17. The 17 left are
the Notch cluster (15, step 3.2d) and the screenshot quick preview's two
borrowed widgets.

- **`ServiceViewFactory`** (`Services/ServiceViews.swift`) builds the SwiftUI
  content services host in their own panels and windows: 17 views.
  - `UI/UIServiceViewFactory.swift` implements it, each view built exactly as
    the service built it.
  - `main.swift` installs it right after `Defaults.register()`, before any
    self-test, probe or service can present.
  - A service still owns its window and only asks for the content.
  - `ServiceViews.factory` stops with a precondition if nothing was
    installed. That cannot happen in the app, and none of these services is
    compiled into the tests.
  - Like `AppShell`, it is not `@MainActor`, for the same Swift 5 reason.
- **Window controllers that were filed under `UI/` moved to `Services/`**,
  next to `QuickToolHUD` and `BrightnessOSD`: `QuitProtectionHUD` and
  `ShelfTooltipPopover`. Neither needs anything above `Design`.
- **Lane and layout models moved to `Services/`:**
  - the recorder lane's kind and item (the view keeps typealiases);
  - the panel layout store (`PanelOrderItem`, `PanelSectionID`,
    `PanelLayout`), split from the views in `PanelLayout.swift`.
- **Checks that ran before macOS, on Linux:**
  - No extracted test code reaches the factory, and no test pins a replaced
    line.
  - The moved files use no extension member declared above them.
  - No file name repeats within a module.
  - The test generator's output for the panel layout is unchanged.

Landed (3.2d, the Notch cluster): 17 references became **0**. Nothing in
`Core`, `Design` or `Services` names a type, top-level function or global
of a later layer.

- **Models and state that services own moved to `Services/`:**
  - the lock screen's model;
  - the menu panel's focus requests (`MenuPanelFocus`) and `MetricDetailKind`;
  - the compact music snapshot;
  - the quick-access motion and the island's backdrop presentation, which
    the window host drives;
  - the media workspace's file-dialog runner (`MediaPanelModal`), whose flag
    the island reads.
- **Drawing pieces moved to `Design/`:** `NotchShape`, `NotchButtonStyle`,
  and the share picker's anchor and presenter.
- **Seven Notch views** come from `ServiceViewFactory`: the island, its
  mirror, quick access, its background, and the three lock-screen surfaces.
- **One access change the split forced.**
  `NotchBackdropPresentation.contourBottom` was `fileprivate`, and the view
  left behind in `NotchComponents.swift` reads it, so it is internal now. A
  scan of every split pair for private and fileprivate members, and for
  private extensions, used across the split found it. It found nothing else.
- **Checks that ran before macOS, on Linux:**
  - The generated test sources are unchanged apart from one re-indented
    line.
  - No test or mutation check reads text that left its file.
  - The test compile set is still closed.
  - The moved files use no extension member declared above them.
  - No file name repeats within a module.

The ratchet's baseline is empty, so any new wrong-way reference fails
`layering_test`. Step 3.2e can now make the layers modules.

Landed (3.2e-1, `VitruvianDesign`): `Design/` is its own module, which
depends on Core alone, so Bazel now enforces the bottom of the stack.

- **Access:** its declarations are `package`.
  - Four structs spell out their initializers: `HUDBackdrop`,
    `NotchButtonStyle`, `NotchShape` and `ShelfSharePickerAnchor`.
  - The share anchor's box class spells out `package init() {}`.
  - An `NSObject` subclass keeps a usable `init()` across modules, and a
    plain class does not. Both were tried with two real modules on the Swift
    6.4 toolchain.
  - `OverlayPanel` is `open`, because 13 services subclass it, and only an
    open class can be subclassed outside its module. Its override is
    `public`, as an override in an open class must be at least as visible as
    the AppKit method it overrides. Both rules were tried the same way.
- **Imports:** every app and test file imports it next to `VitruvianCore`, as
  do the generated test sources.
  - The exceptions are the files the fan helper and the Now Playing adapter
    also compile, which link neither module.
  - A uniform import also covers extension members, which a type-name scan
    would miss.
- **Tests:** the generator no longer copies `OverlayPanel` into the test
  binary; the overlay test builds the module's own class.
- **Checks:**
  - No test declares a `Design` name at top level.
  - Nothing outside `Design` subclasses a `Design` class except
    `OverlayPanel`'s subclasses, which override AppKit members only.
  - No `Design` file uses an extension member that a later layer declares.
  - `Design` declares no extensions.
  - The generated test sources still build from the annotated declarations.

Landed (3.2e-2, `VitruvianServices`): `Services/` is its own module, which
depends on Core and Design, so Bazel now enforces Core <- Design <- Services.

- **Five hidden edges cut first.** The layering check sees type names, not
  extension members, and five services used members that `UI/` declared:
  - `AppFeature.hubTitle` and `hubDescription` moved to
    `Services/Settings/FeatureHubText.swift`;
  - `MenuBarMetric.detailKind` moved next to `MetricDetailKind`;
  - `Notification.Name.menuPanelWillShow` moved to `MenuPanelFocus`;
  - `NotchModule.title` moved to Core, beside `NotchModule` (its
    `PanelOrderItem` conformance stays in `UI/`);
  - `View.screenshotSafeHelp` moved to `Design/`.
- **How they were found:** Services, Core and Design were type-checked as
  one module on Linux with SDK stand-ins, and the errors were matched against
  extensions declared outside that set. A name scan of every such extension
  member found the ones whose receivers the stand-ins could not resolve.
- **Access:** its declarations are `package`.
  - As in Core, every struct without an initializer of its own spells out
    its memberwise one (149), so nothing depends on finding each place that
    builds one: tests build nested and generic ones by qualified name, and
    some only as a contextual `.init()`.
  - 32 types spell out `package init() {}`: structs whose private stored
    properties keep the memberwise initializer private, and plain classes,
    that outside code builds as `Foo()`. A class with only convenience
    initializers counts: its default `init()` is still synthesized, and
    still internal.
  - Two one-line structs declared a second property after a `;`; it is
    `package` too.
- **Imports:** every `UI/`, `App/`, `Support/` and test file imports it, as do
  the generated test sources.
- **Shared files:** the fan helper and the Now Playing adapter still compile
  their few `Services/` files themselves; the adapter's library now passes the
  package name, as the helper's already did.
- **Tests:** the test binary takes `Services/` from the module instead of
  compiling 131 of its files.
  - `generate_sources.py` reads production files with their `package`
    modifiers removed, so every extraction sees the text it was written
    against (a modifier can now follow an attribute).
  - The `NotchModule.title` copy is gone, since Core has it, and the
    `detailKind` copy reads its new file.
- **Checks that ran before macOS, on Linux:**
  - Core, Design and Services emitted as one module with the SDK stand-ins,
    and `UI/`, `App/` and `Support/` type-checked against it: the only new
    errors were initializers that were not yet spelled out, now all fixed.
  - The test binary, type-checked the same way in its old and new layouts:
    the new layout adds no error beyond the SDK stand-ins' gaps. This is the
    check that found the nested initializers, the `;` declarations and
    `AgentUsageStore()`. It also reported `ScanCancellation()`, which macOS CI
    then caught too: the copies the generator makes report errors at the
    production file's path, which the first comparison left out.
  - Annotating added no type-check errors in the module.
  - Nothing outside `Services/` subclasses a `Services` class, and no
    runtime lookup depends on the module name (no archived classes, no
    `NSClassFromString` of an app class).
  - Five test sources still declare a top-level copy of a `Services` type;
    the copy shadows the module's, and no test hands it to the module.
  - Generated test sources match the previous ones but for the spelled-out
    initializers in their copies.

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
