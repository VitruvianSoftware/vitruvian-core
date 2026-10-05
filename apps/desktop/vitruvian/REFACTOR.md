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

## Step 3: split the single target into modules (done)

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
   - **3.2e-3, `VitruvianUI`** (landed, below). `App` stays the executable's library.

   `bazel/layering.py` retires once Bazel holds the whole direction (it did, in 3.2e-3).

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
  - The `NotchActivationButton` copy is gone too: a gesture test built the
    copy and handed it to the module's `NotchGestureSupport`, whose type check
    then failed to recognize it. macOS CI caught this.
  - Six source-text checks split a file at `    func name`, which now reads
    `    package func name`; they split there instead. A scan of every test
    string literal, counted in the changed sources before and after, finds
    no other.
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

Landed (3.2e-3, `VitruvianUI`): `UI/` is its own module, which depends on
Core, Design and Services. With it, Bazel holds the whole direction, and the
layering ratchet is gone.

- **No hidden edges:** `App/`, `Support/` and `main.swift` declare no
  extension member on a type `UI/` can see, and the ratchet already counted
  zero wrong-way references.
- **Access:** its declarations are `package`.
  - `SettingsWindow` is `open`, with its two AppKit overrides `public`: a test
    subclasses it from the test module (to fake `isKeyWindow`).
  - Views that `App/`, `Support/`, a test, or a generated copy builds spell
    out their initializer, taking what the synthesized one took: the
    non-private stored properties, a `Binding` for a `@Binding`, the object
    for an `@ObservedObject` (through `ObservedObject(wrappedValue:)`),
    closures `@escaping`, defaults kept. 18 were written by hand and four
    generated, and `UIServiceViewFactory` spells out `init()`.
  - A view's explicit initializer takes the main-actor isolation the `View`
    conformance infers. Built from a test's non-isolated function, it draws
    no diagnostic in the Swift 5 language mode (tried with a stand-in
    `@preconcurrency @MainActor protocol View` across modules), as before.
- **Imports:** every `App/`, `Support/`, `main.swift` and test file imports it,
  as do the generated test sources.
- **Tests:** the test binary compiles no production file of its own any more;
  every listed source now comes from a module. Its source glob may now be
  empty (`allow_empty`), and fills again if upstream lists one outside them.
- **The ratchet retired:** `bazel/layering.py`, its baseline and both targets
  are deleted, and the pipeline unit no longer lists `:layering_test`
  (`presubmit.yaml` regenerated).
- **Checks that ran before macOS, on Linux with SDK stand-ins:**
  - Core through UI type-checked as one module before and after: the only
    new errors are SwiftUI names the stand-ins lack (`ObservedObject`,
    `Binding`, view modifiers).
  - Core through UI emitted as one module, and `App/`, `Support/` and
    `main.swift` type-checked against it: no access error.
  - The test binary in its 3.2e-2 and 3.2e-3 layouts, errors compared at
    every path (the generated copies report at the production file's):
    no new error.
  - Every test string literal, counted in the changed sources before and
    after: none that a test slices or searches by changes.
  - The one top-level test copy of a `UI` type left (`NotchActivityPicker`)
    is never handed to the module or type-checked by it.
## Step 4: dependency injection at the seams that tests need (in progress)

Problem: services take no collaborators. Tests fake them by shadowing type names
inside the test module.

Change:

- Constructor injection for the collaborators tests replace today: UserDefaults,
  the clock, NSWorkspace, the pasteboard, the HAL and the queues.
- `.shared` stays as the production composition root.
- Break the `.shared` cycles (Notch ↔ Shelf, Notch ↔ Brightness,
  Notch ↔ PreciseVolumeRoller) with events or closures owned by the composition
  root.

Landed (4a, the island's cycles): `NotchService` names none of the three.

- **`NotchCollaborators`** (`Services/Notch/NotchCollaborators.swift`) holds
  what the island asks of them: resync key routing when it starts or stops
  showing volume and brightness feedback, resync the Shelf when its file
  routing changes, and hand a file drop to the Shelf.
- **`NotchService.collaborators`** is a static that `main.swift`, the
  composition root, fills in before anything runs. A static, so wiring it
  does not build the island any earlier than before. Its default does
  nothing, which is all a test without the services needs.
- The calls keep their order and their feature gates; they moved from the
  island into the wiring.
- **Tests:** three contracts copy island methods that now call the hook
  (file drop, fullscreen, session). Each contract wires its own stand-ins the
  way `main.swift` wires the services, so the tests count the same resyncs.
- Still named by the island: `BrightnessService.lidClosed()`, a static query
  with no state, not a cycle.

Landed (4b, two preview checks): the first tests that copied production
text so they could swap `UserDefaults`, `NSWorkspace` or a desktop query now
call the module's own code.

- **Injected:** `WindowPreviewProvider.captureIsPaused` takes the
  preferences and the app in front, and
  `WindowEnumerator.dockPreviewMayActivate` takes the window, the
  current-desktop preference and the desktop query. The overloads the app
  calls pass the system's, so nothing else changed.
- **Tested directly:** the switcher contract keeps its two checks, now
  against a preferences suite of its own; the Dock Preview scope test keeps
  its four, counting the desktop queries through its closure, and adds one
  for an item with no window. Their stand-in `UserDefaults`, `NSWorkspace`,
  `SpaceWindowBridge` and `SwitcherItem`, and the generated copies, are gone.
- **The pattern for the rest:** about 180 type aliases and stand-ins in the
  tests exist so a copied body reads a fake instead of the system. Each one
  goes the same way: the production code takes what the test swaps, and the
  test calls the module.

Landed (4b, process names, the pointer's screen and title motion): three
more tests call the module instead of a generated copy, which leaves 97.

- **Injected:**
  - `ResponsibleProcess.displayName` takes the app name, kernel name and
    executable path lookups;
  - `NSScreen.screen(containing:among:frame:fallback:)` is the choice
    `withMouse` makes, for any screens and pointer;
  - `ScrollingTitle.shouldScroll` takes hover, Reduce Motion and overflow.
    Overflow stays lazy, so a title that cannot scroll is still never
    measured, and the test now checks that too.
- **Tested directly:** the three tests keep their checks, now with plain
  values in place of stand-in `NSRunningApplication`, `proc_name`,
  `proc_pidpath`, `NSScreen` and `NSEvent` types. The libproc buffer handling
  stays in the system lookups the app passes, which the test no longer
  imitates.

Landed (4b, CPU ticks, copied answers and quick paste): three more tests call
the module instead of a generated copy, which leaves 94.

- **Injected:**
  - `SystemMonitor.cpuUsage(ticks:now:previous:held:heldReadAt:)` is the tick
    math `readCPUUsage` runs on the host's counters, with the monitor's state
    passed in and out;
  - `CommandBarCatalog.copyAnswer(_:copy:show:)` takes the pasteboard write
    and the HUD;
  - `ClipboardHistoryService.pasteIntoPreviousApp` has an overload that takes
    the target app, the Accessibility grant, the beep, the prompt and the
    paste shortcut.
- **Tested directly:** the three tests keep their checks, now with plain
  values and recorders in place of stand-in `host_statistics`, pasteboard,
  pasteboard lane, HUD, `NSRunningApplication`, `NSSound`, `Permissions` and
  main-queue types. The CPU test also checks that ticks which have not
  advanced report nothing and that niced ticks count as busy. The system
  calls stay in the app's wrappers, which the tests no longer imitate.

Landed (4b, sound output, shortcut rows and notch notices): three more
generated copies go, which leaves 91.

- **Injected:**
  - `AppVolumeMixer.switchToNextSoundOutput(in:outputs:currentUID:switchTo:)`
    is the switch the output shortcut makes, for any outputs;
  - `ShortcutsSettings.expansionBinding(for:in:expanded:)` takes the page's
    open rows as a binding.
- **Tested directly:** the two tests keep their checks, with plain outputs
  and a plain binding in place of a stand-in mixer and page.
- **Copy dropped:** `NotchNotice` already had a `package` initializer, so the
  tests use the shipped type instead of a copy of it.

Landed (4b, window-server capture and the island's panel): two more
generated copies go, which leaves 89.

- **Injected:** `WindowPreviewProvider.captureViaWindowServer` has an overload
  that takes the connection, the capture function, its options and the
  queue. The test passes its fake capture function and its own queue, so
  every queueing and cancellation check runs the shipped body.
- **Copy dropped:** `NotchPanel` is already `package`, with AppKit's
  initializers, so its tests build the shipped class.

Landed (4b, the island's outline and the mixer level's Escape): two more
generated files go, which leaves 87.

- **Copies dropped:** `NotchShape` already had a `package` initializer, so
  its tests draw the shipped shape. The copied `NotchActivityPicker` beside
  it was used by no test.
- **Injected:** `MixerPercentEscape.cancelsLevel(keyCode:isActive:inFieldWindow:composing:)`
  is the choice the mixer level field's Escape monitor makes. The field's
  coordinator is private to its view, so the test asks this directly, and
  now also checks that only Escape cancels, that an idle field ignores it,
  and that a press outside the field's window never asks the input method.

Landed (4b, the dimming choice): one more generated file goes, which leaves
86.

- **Injected:** `SoftwareDimmingButton.offersChoice(isActive:isBuiltIn:canChooseDimming:isDDC:readable:chosen:compact:)`
  is the rule every display row uses to offer the dimming choice. The test
  keeps all eleven of its checks with a plain row.
- **What is left:** most of the 86 remaining copies stand in for several
  collaborators at once. They cover the app delegate, which the tests cannot
  import, the notch and command bar services, and window and panel hosts. Each
  needs a step 5 style extraction or a seam per collaborator, not a one-line
  overload, so later slices will be fewer copies each.

Landed (4b, the panel's tab gates): one more generated file goes, which
leaves 85.

- **Injected:** `MenuPanelRowFeatures.utilities` and `.controls` list the hub
  features behind the panel's utility and control rows. The row enums stay
  private to the panel; the test compares these lists, and the shipped
  `QuickToggleAction`, against the shipped `PanelSectionID.featureGate`
  instead of copies of all four types.

Landed (4b, the agent usage service's save, settle and alerts): three more
generated files go, which leaves 82.

- **Injected:** `AgentUsageService.settleArchive(on:keeping:save:remove:)`
  settles saved progress on the reading queue, and
  `AgentUsageService.saveProgress(mark:savedMark:providers:store:cursors:save:)`
  writes it when reading moved on. The service passes its own queue, state and
  archive; the tests pass recorders.
- **Injected:** `AgentUsageService.delivers(_:queuedIn:running:session:providers:in:)`
  is the rule an agent event meets on the main thread: dropped after a stop or
  restart, or past the person's choices. The test reads those choices from a
  test defaults domain instead of a stand-in `NotchAgentSupport`.

Landed (4b, the agent usage service's log read): one more generated file
goes, which leaves 81.

- **Injected:** `AgentUsageService.read(_:provider:cursors:store:isCancelled:report:lines:)`
  applies a log's new lines to the store as they arrive. `lines` defaults to
  `AgentLogReader.readAppended`; the test wraps it to see each line arrive
  instead of shadowing the reader.
- **Check tightened:** the test now appends a line before its cancelled read,
  so "a cancelled reading consumes no more entries" fails when cancellation
  is ignored. Before, the file was unchanged and the check passed either way.

Landed (4b, the Cleaner's last run): one more generated file goes, which
leaves 80.

- **Injected:** `CleanerScheduler.recordRun(freed:failed:at:in:)` saves a
  finished automatic pass, and `CleanerView.lastRunLine(ranAt:freed:failed:strings:)`
  is the schedule card's line for it. The test saves to a test defaults
  domain, reads back through the card's `Preferences` keys and checks the
  shipped English strings, in place of a stand-in defaults store and strings.

Landed (4b, the music queue's row action): one more generated file goes,
which leaves 79.

- **Injected:** `NotchMusicService.playQueued(_:visible:request:upcoming:playback:pending:failed:in:send:)`
  holds the row action's rule and its pending and failed flags. The service
  passes its own state and `send`. The test reads its preferences from a test
  domain instead of a stand-in `NotchQueueSupport`.
- **Checks added:** a row action still waiting for its reply blocks another,
  and a queue turned off in Settings plays nothing. The stand-in always
  reported the queue on, so the second could not be checked before.

Landed (4b, Keep Awake's timer handoff): one more generated file goes,
which leaves 78.

- **Injected:** `KeepAwakeManager.timerHandoff(trigger:suppressed:in:batteryAllows:matching:enabled:requireAll:)`
  returns the conditions a timed session that ran out carries on with, or nil
  when it ends. The battery and condition readers are closures, so they are
  read in the same order as before, only after the cheaper guards pass.
- **Check added:** a session already running automatically never reads the
  conditions.
- **Mutation fixture:** `mutation_checks.py` "a timed session hands over on
  one condition" now targets the static's guard.

Landed (4b, type copies): nine copies of data types that production already
declares `package` become the module's own types. No generated file goes
away, so 78 remain.

- **Aliased:** `BrightnessService.DisplayControlFailure`,
  `CommandBarService.Mode`, `JunkCleaner.Phase`, `UpdateService.State`,
  `ScreenshotQuickPreviewController.Action`, and `SpaceWindowBridge.Topology`
  in three scopes. Each is a module-qualified typealias where the copied
  methods name the type unqualified.
- **Dropped:** the copy of `NotchMediaSession`, a top-level type the module
  already exports.
- **Kept:** the copy of `AppUninstaller.Phase`, whose `.done` case holds the
  test's stand-in `Leftover`.

Landed (4b, the Dock preview's desktop-change observer): one more generated
file goes, which leaves 77.

- **Extracted:** `Services/DockPreview/DockPreviewSpaceObservation.swift`
  keeps at most one desktop-change observer. While previews list only the
  current desktop, a change ends the open session, unless a window is being
  dragged.
- **Wiring:** `DockPreviewService` hands it its state and `endSession`. The
  notification center and name are injected.
- **Test:** the test drives the type on its own `NotificationCenter` instead
  of copies of `syncSpaceObservation` and `stopSpaceObservation`.

Landed (4b, the Cleaner's scans, grouped by owning file): both copies of
`JunkCleaner` go, which leaves 75.

- **Injected places:** `JunkCleaner.Places` names the home folder, the
  folders screenshots are saved in, and how an app registered with Launch
  Services is found. Every scanner and the removal guard read it instead of
  `NSHomeDirectory()` and `NSWorkspace`.
- **Injected scanning:** `JunkCleaner.Scanning` names what a scan runs for
  each category and the two queues it uses.
  - `shared` keeps the system's of both.
  - A package initializer lets a test build a cleaner with its own.
- **Tests:**
  - `CleanerEligibilityTests` lays its fixtures out under the real Library
    folders of a fixture home and calls `mayRemove`, `appendLeftovers`,
    `scanCaches`, `scanLogs`, `scanScreenshots` and `leftoverOwner`.
  - `CleanerScanFlowTests` drives a real cleaner through a manual queue.
- **Source text:** the anchors in `AppManagementFeatureTests` follow the
  new signatures.

Landed (4b, the command bar's brightness command): one more generated
file goes, which leaves 74.

- **Injected:** `CommandBarCatalog.applyBrightness(percent:display:route:)`
  takes a `BrightnessRoute`: the display under the pointer, the displays
  the brightness service drives, the set, refresh and refusal, and how the
  retry is scheduled. `system` keeps the AppKit lookups, the service and
  the 0.7 s retry.
- **Test:** the test passes a route of its own instead of shadowing
  `NSScreen`, `NSEvent`, `NSSound`, the service and the queue.

Landed (4b, the Dock preview's frame restore): one more generated file
goes, which leaves 73.

- **Injected:** `DockPreviewFrameRestoration.restore(...)` takes a
  `RestoreHost`:
  - a display's frames now;
  - the frontmost process and the focused window;
  - the restore itself, and the wait between checks.

  `system` keeps AppKit, the window activator and the main queue.
  `Screen` is `package`.
- **Test:** the test steps the checks one at a time instead of waiting on
  the run loop.
- **Checks added:** the waits are 0.15 s and then 0.05 s, and another app
  in front cancels the restore. The stand-in it replaced always reported
  the item's app in front.

Landed (4b, the keyboard debounce tap): one more generated file goes, which
leaves 72.

- **Injected:** `KeyboardDebounceService.suppresses(_:event:state:config:)` is
  the tap's rule for a key event, with the state and settings passed in.
- **What stayed:** the tap keeps its re-arm branch and its lock.
- **Test:** the test calls the rule with a state of its own.

Landed (4b, Port Manager's refresh): one more generated file goes, which
leaves 71.

- **Injected:** `PortManagerService` takes a `Scanning`:
  - the process list and each process's start time;
  - the lsof listing;
  - where the work runs and where its result is published.

  `system` keeps `proc_listallpids`, the kill service's start time, lsof
  and the dispatch queues. `snapshot(_:)` is `package`.
- **Test:** the test passes inert process data and a manual queue instead
  of shadowing `DispatchQueue`, `Shell`, the kill service and
  `proc_listallpids`.

Landed (4b, Fan Control's resume): one more generated file goes, which
leaves 70.

- **Extracted:** `FanControlLifecycle` (new, `Services/FanControl`) holds
  what fan control does on its own:
  - resuming after a launch or wake;
  - keeping or forgetting the resumed control as the preferences change;
  - winding down idle work.

  It reads the defaults it is given. `FanControlService` owns it and passes
  in its access state, snapshot, panel state and the helper requests.
- **Test:** the test drives the lifecycle with a recording host and a
  defaults domain of its own instead of a copy of ten service members.
- **Checks added:** an open panel keeps its updates running, waking with the
  panel closed does nothing, and a control that stopped cooling is not kept.
  Mutants of each of these passed the old test.

Landed (4b, the island's live equalizer): one more generated file goes,
which leaves 69.

- **Injected:** `NotchAudioLevelService` takes an `Environment`:
  - whether the equalizer is chosen, and whether Reduce Motion is on;
  - the playback it follows;
  - how a reader is built.

  `system` keeps the preferences, the music service and the Core Audio
  reader. Readers conform to `NotchAudioLevelReading`.
- **Test:** the test runs its own service on a playback subject, with
  readers that only record what they are told, instead of a copy of the
  whole class.
- **Mutation suite:** its two fixtures on this file now act on the code the
  test runs.

Landed (4b, the music-app launch blocker): one more generated file goes,
which leaves 68.

- **Injected:** `MusicLaunchBlocker` takes a `System`:
  - defaults, Accessibility and the clock;
  - the time since the last deliberate gesture, and which players run;
  - the launch notifications, the media-key tap and the replacement app.

  `system` keeps AppKit, Core Graphics and the workspace. The tap sits
  behind `MusicLaunchKeyTap`. A launch reaches the blocker as a
  `LaunchedApp`, and a key as a `MediaKey`.
- **What moved:** the tap callback only reads the key and hands it to
  `observeMediaKey(type:key:)`, and it always passes the event on. The tap
  is listen-only, so it could not swallow a key anyway. That is why the old
  per-key "passes the event through" check goes.
- **Test:** the test drives the real blocker with a session of doubles
  instead of a copy of five methods.
- **Check added:** a did-launch never re-judges a launch its will-launch
  let through, even after another key. A mutant without that guard passed
  the old test.
- **Known gap:** a second observer pair added on a repeated sync is still not
  seen by any check.

Landed (4b, opening the player from the island or the radial card): one
more generated file goes, which leaves 67.

- **Injected:** `RadialNowPlayingApplication.open(_:using:)` takes an
  `Opening`:
  - the running player, as an `OpenablePlayer`: its policy, its hidden
    state, unhiding, the activation handoff and both activation requests;
  - whether it has a window on screen;
  - where it is installed, and how an app is opened.

  `system` keeps `NSRunningApplication`, the window list and the
  workspace.
- **Test:** the test passes recording doubles instead of shadowing the
  AppKit types.
- **No longer checked:** that the cooperative request names Vitruvian as its
  source. That now sits in `system`'s one-line closure.

Landed (4b, the updater's administrator install): one more generated file
goes, which leaves 66.

- **Injected:** `UpdateService` takes an `AdminInstall`:
  - the authorization;
  - hiding and restoring the Extra Brightness overlay;
  - the main-queue hop;
  - quitting.

  `system` keeps `AdminShell`, the overlay service, the main queue and
  `NSApp`. `launchAdminInstaller` is `package`.
- **Test:** the test runs its own service.
- **Checks added:** the answer waits for the main queue, and a declined
  prompt leaves the service offering the update. Before, a double logged the
  offer.

Landed (4b, the media workspace's file dialogs): one more generated file
goes, which leaves 65.

- **Injected:** `MediaPanelModal.run(_:host:completion:)` takes:
  - a `Dialog`: begin above a level, focus, run modal;
  - a `Host`: the island, the event and key windows, whether the island
    is expanded, activation, the main queue and the launcher's refocus.

  `runPanelModal` keeps its signature and passes the panel and `system`.
  The island is an `IslandWindowing`, which `NSWindow` adopts.
- **Test:** the test drives `run` with doubles instead of a copy.
- **No longer checked:** that the panel stays up while another app is
  active. That now sits in the panel wrapper. A dialog can no longer
  be attached as a sheet: `Dialog` has no way to do it.

Landed (4b, the island's lyrics): one more generated file goes, which
leaves 64.

- **Injected:** `NotchLyricsService` takes an `Environment`:
  - the preferences;
  - lookups, which return their cancellation;
  - the island's state;
  - a `Chooser` (begin above a level, focus, cancel);
  - activation, reopening the music section, and both queues.

  `system` keeps the lyrics download, NotchService, an `NSOpenPanel`, `NSApp`
  and the dispatch queues.
- **What changed:**
  - A token, not panel identity, names the open chooser.
  - `visible` and `track` are readable.
  - `IslandWindowing` is now `Sendable`, so the reopen hop can capture the
    window weakly.
- **Test:** the lifecycle and picker tests drive the real service on a
  session of doubles. Lyrics now come from answered lookups or chosen files,
  where before the test wrote them straight into the cache.
- **Checks added:** six mutants passed the old test, and each now fails one
  of these:
  - a late answer from an earlier chooser;
  - a retried lookup's predecessor answering;
  - work that supersedes a chosen file's late read;
  - an island that moved on before the reopen;
  - focus taken before activation.

Landed (4b, the island's download folder choice): one more generated file
goes, which leaves 63.

- **Extracted:** `NotchDownloadFolderChoice` (new, `Services/Notch`) holds:
  - choosing the watched folder, from the Downloads page or from Settings;
  - returning to the page it came from;
  - the chooser's cancellation.

  `NotchDownloadService` owns it and adopts what is chosen: it stops, saves
  the bookmark, enables watching and syncs.
- **Injected:** the chooser (above the island or as an ordinary window),
  the feature and page settings, the island, the event and key windows,
  activation, the reopen, the main queue and the bookmark.
- **Shared:** `NotchIslandSurface` (new) is the island state that a chooser
  returns to, with `shows(_:in:)`. The lyrics importer uses it too.
- **Test:** the test drives the real choice on a session of doubles instead
  of copies of five service members.
- **Checks added:** two mutants passed the old test, and each now fails one
  of these:
  - a Settings chooser answered after the feature was removed saves
    nothing;
  - a click on the island opens the picker over it, even while another
    window is key.

Landed (4b, the recorder's export chip): one more generated file goes,
which leaves 62.

- **Extracted:** `RecorderExportProgressChip` (new, `UI/Recorder`) is the
  chip. `RecorderEditorView` passes it the phase, progress, label, cancel
  title and action.
- **Test:** the layout test renders the real view instead of a copy of its
  body.

Landed (4b, clearing permissions and uninstalling): one more generated
file goes, which leaves 61.

- **Injected:** `SelfUninstall.clearPermissions` and `uninstallCompletely`
  take `Steps`:
  - every teardown step: input interceptors, sleep, fan helper, login item,
    sudoers rule, TCC, preferences and the bundle;
  - the fan helper's registration;
  - the aftermath on success or failure;
  - the main and background queues.

  `system` is the real teardown. The local `stop` functions are marked
  `@Sendable`.
- **Test:** the test logs a run of doubles instead of a copy of five
  functions. Its messages now come from the real strings.
- **Generated registry kept:** `LocalizationCatalog.swift` stays. It lists
  every `FeatureStrings` factory and copies no production code, so it is a
  generated registry, not a copy.

Landed (4b, editing a history image): one more generated file goes, which
leaves 60.

- **Injected:** `ClipboardHistoryService.editImage(_:editing:)` is static and
  takes an `ImageEditing`:
  - the feature, the image store and both queues;
  - the beep;
  - putting the history away, and opening the editor.

  The instance method passes `system`, with the service's own dismissal.
- **Test:** the test runs the real handoff on the real queues. It also uses
  the real `ScreenshotService.imageCapture(from:)` instead of a copy.
- **Still to do:** `ClipboardPreview` is the service's other copy. It reaches
  into the history's editing, pinning and search caches, so it waits for
  those to move into their own type.

Landed (4b, the island's Mission Control polling): one more generated file
goes, which leaves 59.

- **Extracted:** `NotchMissionControlPolling` (new, `Services/Notch`) owns:
  - the polling timer and its cadence;
  - when a check is worth a frame probe.

  `NotchWindowHost` owns it and passes the panel's visibility, the conceal
  state, the window-list reading, the clock and its frame probe.
- **Test:** the test drives the real polling instead of a copy of four host
  members.
- **Check added:** an overview that opens again is probed at once, sooner
  than a lasting one. A mutant without that passed the old test.

Landed (4b, the raw wheel tap): one more generated file goes, which leaves
58.

- **Injected:** `ScrollInverter.adjustWheel(_:state:defaults:ownProcessID:targets:)`
  is the tap's decision for one wheel event:
  - linear lines;
  - direction;
  - the sideways shortcut;
  - holding back a fraction of a notch.

  It is a `nonisolated` static. What it remembers between events is a
  `WheelTapState`. What it asks about the pointer's target is a
  `WheelTapTargets`, and `system` asks the exception lists and the app's
  own windows.
- **What stayed:** the tap keeps its re-arm branch.
- **Test:** the test feeds real wheel events through the decision instead
  of through a copy of `handle`.
- **Verification:** this slice uses Core Graphics events, which the Linux
  model cannot build. It relies on macOS CI.

Landed (4b, dragging items out of the shelf): one more generated file goes,
which leaves 57.

- **Extracted:** `ShelfInternalDrag` (new, `Services/Shelf`) holds a drag out
  of a shelf:
  - the dragged items, and whether a drop inside merged them;
  - holding the island open while the drag lasts;
  - what the shelf it came from does once the items land.

  `ShelfService` owns it, reads its items and merge flag, and passes the
  island, its two shelf windows, the interaction end and item removal.
- **Test:** the test drives the real drag with stand-in windows instead of a
  copy of three service members.

Landed (4b, the screenshot preview's hover and dismissal): one more generated
file goes, which leaves 56.

- **Injected:** `ScreenshotQuickPreviewController` takes a `Scheduler` for
  its main-queue hops and the auto-dismiss timer; `main` keeps today's
  behavior.
- **Opened:** `hoverChanged`, `perform` and `scheduleAutoDismiss` are
  `package`. The image view's hover forwarding is the static
  `forwardImageHover(_:embedded:to:)`.
- **Test:** the hover test builds a real preview over a manual clock instead
  of a copy of the controller. The share-completion copy now copies the
  `package` `scheduleAutoDismiss` with a scheduler fixture.
- **Verification:** the controller draws through Core Graphics and SwiftUI,
  which the Linux model cannot build. It relies on macOS CI.

Landed (4b, the command bar's borrowed keyboard layout): one more generated
file goes, which leaves 55.

- **Extracted:** `CommandBarInputSourceBorrowing` (new, `Services/CommandBar`)
  borrows an ASCII layout when the bar opens and puts the person's own source
  back on close or quit. It takes a `System`: the preference, the Text Input
  Sources calls and the next main-loop turn. `live` keeps today's behavior.
  `CommandBarService` owns it, says which presentation is current, and keeps
  `hasBorrowedInputSource` and `restoreBorrowedInputSource()` for the app
  delegate.
- **Test:** the input-source test drives the real borrowing instead of a copy
  of four service members. The termination test, which still copies the
  delegate's callback, runs it against the real borrowing.
- **Check added:** a close with nothing borrowed queues no work. Without it, a
  close that queued a no-op restore passed.
- **Not covered:** the restore's second guard, that the record is still the
  one it captured. It is unreachable through the service: each open starts a
  new presentation first.

Landed (4b, switcher app activation and window fronting): one more generated
file goes, which leaves 54.

- **Injected:** `WindowActivator.activateApp(_:plan:windowID:windowOwnerPID:calls:)`
  and `activateSource(pid:windowID:windowOwnerPID:calls:)` are generic over
  `SwitcherActivatableApp`, which `NSRunningApplication` adopts. They take
  `ActivationCalls`: finding a running app, handing activation over, fronting,
  focusing and preparing a window. The private callers pass the live calls.
- **Injected:** `SpaceWindowBridge.frontWindow(_:ownerPID:calls:)` takes
  `FrontingCalls`, the window server's three private calls. `live` resolves
  the symbols as before.
- **Test:** the activation test drives the real activation and fronting with
  apps that log and calls that post nothing, instead of copies of four
  members.
- **Checks added:**
  - cooperative recovery still raises the selected window afterwards;
  - a source that is quitting is not restored.
- **Not covered:** `activateSource` passing the pid as the window owner when
  none is given. `activateApp` falls back to the same pid, so the mutant is
  equivalent.

Landed (4b, the scrolling screenshot's capture loop): one more generated file
goes, which leaves 53.

- **Injected:** `ScreenshotScrollingCapture.capture(region:finishSignal:onProgress:prepare:)`
  is the capture loop over a `FrameSource` that `prepare` resolves once. The
  existing `capture(region:includePointer:...)` resolves it through the
  capture engine as before. `stitch(_:)` is `package`.
- **Test:** the test runs the real loop and stitching over frames it supplies,
  instead of a copy of the whole enum with stand-ins for the region and the
  engine.
- **Check added:** a region that cannot be captured reports a failure.
- **Verification:** the loop draws through Core Graphics, which the Linux
  model cannot build. The model type-checks the new signatures and the test's
  calls in Swift 6; the loop itself relies on macOS CI.

Landed (4b, the update highlights tour): one more generated file goes, which
leaves 52.

- **Injected:** `UpdateHighlightsView` takes the animation's URL. The default,
  `bundledAnimationURL`, is the GIF in the app bundle as before.
  `UpdateHighlightsGIF` is `package`.
- **Test:** the layout test renders the real tour in every language, through
  the real `L10n`, which it restores afterwards. It no longer renders a copy of
  the view with stand-ins for the language, the screen, the bundle and the app
  shell.
- **Verification:** SwiftUI, so macOS CI only.

Landed (4b, the Dynamic Island settings rows): one more generated file goes,
which leaves 51.

- **Extracted:** `NotchSettingsRows.swift` (new, `UI/Settings`) holds the rows
  the layout test measures, as `package` views:
  - `NotchDestinationRow`, island or window for one kind of content;
  - `NotchAgentRows`: `Limits`, `LimitFocus`, `Readout`, `FinishAfter`,
    `LimitAt` and `Budget`.

  `NotchSettings` and `NotchAgentsSettingsControls` draw them where the
  inline rows were, with the same indents.
- **Test:** the test measures the real rows in the real `SettingsCard`,
  instead of copies of the card primitives and of the page fragments.
- **Verification:** SwiftUI, so macOS CI only.

Landed (4b, the media workspace's layout): one more generated file goes, which
leaves 50.

- **Extracted, in `MediaWorkspaceView.swift`:**
  - `MediaWorkspaceStack` stacks the header, tool picker and content, and
    reports the content's natural height in the island;
  - `MediaInputDropTarget` takes file drops only outside the island;
  - the static `pick(_:current:onToolChange:select:)` is the tool picker's
    change rule.
- **Extracted, in `NotchFilesView.swift`:** the static
  `mediaHeightChanged(_:id:in:refresh:)` resizes the island over
  `NotchMediaHeightTracking`, which `NotchFileToolsService` adopts.
- **Test:** the test lays out the real stack and drop target, and drives the
  real height and tool rules, instead of copies of four private members. Its
  file tools are still the shelf routing contract's, which adopts the new
  protocol in the test.
- **Generator:** the shelf routing copy now scopes `updateMediaHeight` to the
  service class, since the protocol declares it too.
- **Verification:** a Linux Swift 6 model runs the height and tool rules with
  these fixtures. The views rely on macOS CI.

Landed (4b, the quit-protection HUD): one more generated file goes, which
leaves 49.

- **Opened:** `QuitProtectionHUD` is `package`, with its `ContentView`,
  `minimumSize` and `fittingSize(_:)`.
- **Test:** the progress checks move from `Tests/Fixtures` into
  `Tests/QuitProtectionHUDTests.swift`, as an extension of the real HUD. They
  are no longer appended to a copy of the whole HUD file.
- **Removed:** `Tests/Fixtures` held only those checks. It leaves `BUILD`'s
  globs and `sync_sources.py`'s staging with them.
- **Verification:** AppKit and Core Animation, so macOS CI only.

Landed (4b, a click on a copy of the island): one more generated file goes,
which leaves 48.

- **Extracted:** `NotchIslandSummons` (new, beside `NotchPointerFollower`)
  holds what a click on a copy does:
  - an open island closes;
  - once its window settles, it moves to that display and opens;
  - it stays put if it stopped, can no longer move, or the display went away.

  `NotchService` wires it the way it wires the pointer follower, and
  `NotchMirrors` calls it on a click.
- **Test:** the mirror test drives the real summons instead of a copy of
  `bringIsland(to:)`.
- **Checks added:** the wait for the window to settle, an unplugged display,
  an island on one display only, an island suspended while it settles, and a
  closed island that must not be collapsed again. The last one catches a
  mutant the others let through.
- **Verification:** a Linux Swift 6 model of the summons and the test kills
  all eight mutants.

Landed (4b, the island's screen-edge click area): one more generated file goes,
which leaves 47.

- **Extracted:** `NotchScreenEdgeClicks.area(for:)` works out where a click at
  the top of the screen counts as a click on the closed island, from a
  `Resting` value of the island's state. `pressed(hoverWork:hoverState:)` is
  what a press there does to hover. `NotchService` passes its own state.
- **Test:** the edge-click test feeds the real rules the same state, and
  toggles each condition as before. It no longer runs a copy of the two
  service members.
- **Verification:** the rule moved verbatim. Its geometry lives in Core, so
  this slice relies on macOS CI.

Landed (4b, app update rules and scan completion): one more generated file
goes, which leaves 46.

- **Injected:** `AppUpdatesService` takes an `Environment`:
  - the preferences;
  - the feature switch;
  - notifications;
  - an optional scan.

  `live` is the app's, so `shared` behaves as before.
- **Split:** `check()` builds a `ScanRequest` and hands the scan's `ScanResult`
  to `finishCheck`. Without an injected scan, the service's own `runScan` runs
  the same sources on its work queue.
- **Opened:** `reloadRules()` is `package`, and `sourceRefreshPending` is
  readable.
- **Test:** the rules test runs the real service. Its scans finish when the
  test says, so it drives check, scan and completion as the app does,
  instead of a copy of ten members.
- **Verification:** AppKit and Combine, so macOS CI only.

## Step 5: decompose NotchService (in progress)

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

Landed (5a, session and lock tracking): `NotchSessionTracker`
(`Services/Notch/NotchSessionTracker.swift`) follows system sleep, display
sleep, the console, the lock screen and screen savers, and reports each change.

- **What moved:** the ten observers on the workspace and distributed
  notification centers, and the read of the current session at start.
- **What stayed:** `NotchService.updateSession(_:)` applies each change and
  owns its effects (suspending the island, the lock sounds, the timer), so the
  contract that exercises those effects is unchanged.
- **Injected:** both notification centers and the delivery queue. The app
  passes the system's centers and the main queue.
- **Tested directly:** `NotchSessionTrackerTests` drives the module's own
  tracker through centers of its own, with no queue, and checks every
  transition, that each center is read only for its own notifications, that
  starting again replaces the observers, and that a stopped tracker reports
  nothing. Run on Linux against the real file with AppKit stand-ins, it fails
  when an unlock forgets the screen saver, or when `stop()` leaves an
  observer behind.

Landed (5b, menu-bar space measurement): `NotchMenuSpaceReader`
(`Services/Notch/NotchMenuSpaceReader.swift`) reads how much of the menu bar
beside the camera the menus leave free.

- **What moved:** the once-a-second timer, the queue the accessibility read
  runs on, the flag that keeps reads one at a time, and the generation that
  drops an answer the island moved away from or a new menu bar owner made
  stale. So did the choice of whose menus to measure, the menu bar's owner.
- **What stayed:** `NotchService.syncMenuSpaceMonitoring()` still decides
  whether to read at all, and `applyMenuSpace(_:)` what an answer does to the
  island. The screen-refresh contract still runs those against a stand-in
  that counts starts, stops and reads; its timer double is gone.
- **Injected:** the menu bar's owner, the measurement, the background and
  main queues, and the ticks. The app passes `.system`.
- **Tested directly:** `NotchMenuSpaceReaderTests` runs each tick, read and
  answer by hand. It checks that one read runs at a time, that an answer
  reaches the island only while current, that a move or a new owner reads
  again, that a stop drops the answer in flight, also across a quick
  restart, and that a released reader cancels its ticks. Run on Linux against
  the real file, it catches each of six mutations of the reader.

Landed (5c, the copies on other displays): `NotchMirrors`
(`Services/Notch/NotchMirrors.swift`) keeps the copies of the closed island
that the other displays show when the island is on every display.

- **What moved:** creating, updating, hiding and closing the copies, the
  surface each one draws (a capsule's strip, a camera's strip or the island
  at rest), the room a copy may take beside another display's menus, and
  which displays show a full-screen Space.
- **What stayed:** `NotchService` decides when the copies sync, and a click
  on a copy still runs its `bringIsland(to:)`, which closes, moves and
  opens the island. Its other contracts still find `syncMirrors()`,
  `closeMirrors()` and `showsCopies`, now one line each. Choosing the
  island's own display (`updateScreen()`, following the pointer) is the
  other half of "display and mirror selection" and has not moved yet.
- **Injected:** the displays (each with whether it shows a menu bar), the
  island's geometry on a display, which displays are in full screen, the
  five preferences the copies follow, the island while it shows copies,
  its strip sizing, and the window each copy gets. A copy's window is a
  `NotchMirrorHost`; `NotchWindowHost` is one.
- **Tested directly:** `NotchMirrorContract` drives the module's own
  `NotchMirrors` through a stand-in world and windows, with every check it
  made of the copied methods, plus closing the copies and a click on a
  copy. Only `bringIsland(to:)` is still copied from `NotchService`. Two
  new mutations in `Tests/mutation_checks.py` guard the copies.

Landed (5d, clicks on the menu bar above the island): `NotchScreenEdgeClicks`
(`Services/Notch/NotchScreenEdgeClicks.swift`) watches clicks on the menu
bar's first row above the closed island and opens it, one of the island's
event bindings.

- **What moved:** installing and removing the global and local mouse
  monitors, turning each event into a point on screen, and the press,
  drag and release rules that make a click.
- **What stayed:** `NotchService.screenEdgeClickArea` (where the island
  takes these clicks, from its geometry and state) and the new
  `screenEdgePressed()`, which stops hover until the release. Other
  contracts still find `syncScreenEdgeClicks()` and
  `removeScreenEdgeClickMonitors()`, now one line each.
- **Injected:** the monitors (`.system` uses `NSEvent`), and the island's
  area, capsule gap, working surface, window shape and its press and click.
- **Tested directly:** `NotchScreenEdgeClickTests` drives the module's own
  type through stand-in monitors, with every check it made before plus an
  event that has no point on screen. The click area and the press come
  from `NotchService`, copied as before. Two new mutations guard the type.

Landed (5e, following the pointer): `NotchPointerFollower`
(`Services/Notch/NotchPointerFollower.swift`) brings the closed island to
the display the pointer rests on, when the display choice is the pointer
or every display. It is the moving half of "display and mirror selection".

- **What moved:** watching pointer movement while the island can follow,
  the check that the pointer left the island's display, the short wait
  before it moves, and the conditions for the move (still allowed, not in
  Mission Control, a different display).
- **What stayed:** `canFollowPointer` (only a closed island at rest moves)
  and `move(to:)`, which takes the display and refreshes the island.
  `updateScreen()`, which picks the display and builds the island's window,
  is the island's core and stays. Other contracts still find
  `syncPointerFollowing()`, `removePointerMonitors()` and
  `schedulePointerFollow()`, now one line each.
- **Injected:** the monitors, the pointer's location, the displays and the
  clock (`.system`), and the island's side, including how it waits for its
  window to settle and how it moves.
- **Tested directly:** `NotchScreenRefreshContract` drives the module's
  own follower with the island's copied `canFollowPointer` and `move(to:)`,
  through the same stand-in monitors, displays and clock, with every check
  it made before. Two new mutations guard the follower.

Landed (5f, the hover watches): `NotchMovementWatch`
(`Services/Notch/NotchMovementWatch.swift`) keeps a pair of pointer-movement
monitors, in this app and in others, while the island needs them.

- **Two uses:**
  - the watch while the island hides until the pointer reaches it;
  - the watch from an unreported hover exit until AppKit reports the
    pointer again.
- **What stayed:** `NotchService` still decides when each watch runs
  (`syncHiddenHoverMonitoring()`, `syncHoverExitMonitoring(entered:point:)`)
  and what a move does (`hover(_:)`), so `NotchHoverTests` keeps copying those.
- **Tested:** the copies now start and stop the module's own watches,
  through the test's stand-in monitors, with every check they made before.
  A new mutation guards against stacking monitors.

Landed (5g, the agent strip's marks): the first slice of the single source
for layout.

- **Helpers:** `NotchAgentSupport` now owns how big a working agent's mark is
  on a strip, the frame each mark takes and the width of a row of marks.
  The island's wing (`NotchService`) and the strips that draw the marks (agent,
  timer and watch, plus the capsule) all call these helpers.
- **The divergence it fixes:** the service reserved full-size marks while the
  strip shrank them to fit a short island. So on a 24-pt island the wing
  kept room for a 14-pt mark the strip drew at 10 pt.
- **Also:** the agents page lists agents through
  `NotchAgentSupport.providers()`, so it no longer keeps its own list of the
  three providers.
- **Tested:** `NotchAgentTests` checks the sizes on tall, short and tiny
  strips, and the width of a row of marks. A new mutation guards the
  shrinking.
- **Still duplicated:** the other copies the survey found move in later
  slices (5j below took the notice, the header and the capsule).

Landed (5h, file-drop routing): `NotchFileDrop`
(`Services/Notch/NotchFileDrop.swift`) takes files dragged onto the island.
A drop that the media tools can take offers two destinations, the shelf and
the tools, and the pointer chooses between them; any other drop goes to the
shelf.

- **What moved:** the two destinations and which one the pointer is over,
  opening the island on its files when a drag enters, and delivering the drop.
- **What stayed:** whether the island takes files at all
  (`canAcceptFileDrop`) and what a delivered drop does to the island. Views
  still read `choosingFileDropDestination` and `targetsMediaDrop`, which are
  now computed and announce each change through `objectWillChange`.
- **Injected:** the shelf and the media tools (`.system(shelfAccept:)`), and
  the island's side: its acceptance, the media tools' area and how it opens.
- **Tested directly:** `ShelfDropRoutingContract` drives the module's own
  type, wired to its stand-in shelf and tools, with every check it made
  before. A new check counts the change announcements, and a new mutation
  guards them.

Landed (5i, the capture controls' movement watch): the monitor that lets
clicks pass through the capture controls' window, except over the controls
themselves, is a `NotchMovementWatch` that watches this app only
(`.system(matching:inOtherApps: false)`). `NotchService` has no monitor
array of its own left except the open island's clicks and keys
(`eventMonitors`).

- **Tested:** the capture-controls checks start and stop the module's own
  watch through a stand-in monitor, and the teardown check now also asks the
  watch. A new mutation guards the teardown.

Landed (5j, the notice, the header and the capsule's music strip): more of
the layout has one source.

- **The text notice:** `NotchNoticeLayout` (new, in Core) holds its symbol
  column, spacing, inset and font. `NotchNotice.preferredWingWidth` sizes the
  wings with them and `NotchNoticeView` draws with them.
- **The open header:** `NotchGeometry` gains `headerBottom`, `pageTop` and
  `headerSideWidth(contentWidth:)`. The page clip, the media drop area, the
  section scroll's header test, the header halves in `NotchView` and the
  content editor, and the capture controls' header no longer spell out the
  sums.
- **The capsule's music strip without a title:** the view kept two paddings
  between the cover and the bars, while `CapsuleLayout.musicSurface` reserves
  one. The view now keeps one. Before, the capsule's resting width hid the
  difference.
- **Tested:** the spacing contract checks `pageTop` and the header halves on
  every layout and camera height. A new mutation guards the halves.
- **Left as they are:** the companion mark beside a timer is drawn at most
  13 points but reserved at the strip's icon size (up to 20). Over-reserving
  is safe, and the timer and download strips size it differently on
  purpose, so it stays until a design decision. Also left: the calendar,
  download and capture-control fonts and insets, which agree today.

Landed (5k, event bindings): `NotchEventBindings`
(`Services/Notch/NotchEventBindings.swift`) holds the island's subscriptions
to the services whose state it shows.

- **What moved:** `bindEvents`' subscriptions to eleven services: the timer,
  Watch, music, the tools page, the system monitor's fan card, downloads,
  agent usage (its strip and its events), the calendar, Keep Awake,
  notifications and the clipboard history. Each source keeps its operators
  (duplicates dropped, first values skipped, the hop to the main queue)
  in `Sources.system()`, and each is asked for only when its module or
  notice is on, so a service the island does not show is still never
  started for it.
- **What stayed:** every reaction. `NotchService` passes them in as
  `Island`: resizing, remembering and naming songs, the tools and fan
  card refreshes, and the notices, whose text it still builds. Volume and
  battery stay in `bindEvents`, since a contract copies the volume binding.
  `NotchService` loses 105 lines and 15 of its `.shared` reads.
- **Tested directly:** `NotchEventBindingsTests` binds the module's own
  type to subjects of its own and checks that only the sources of modules
  that are on are asked for, that each change reaches the island once,
  that binding again replaces the subscriptions, that a song is kept only
  while it plays, that the system's banner hides only for a notification
  the island stands in for, and that unbinding stops everything.

## Step 6: typed preferences and explicit concurrency (in progress)

- Preferences: a typed key (`Preference<Value>` carrying its default) replaces the
  795 string constants plus the defaults dictionary, so `@AppStorage` and service
  reads share one default.
- Concurrency: mark UI-state holders `@MainActor`. Turn on Swift 6 strict
  concurrency module by module, Core first.

Landed (6a, Swift 6 for Core and Design): `VitruvianCore` and
`VitruvianDesign` build in the Swift 6 language mode
(`features = ["swift.enable_v6"]`), so the compiler rejects shared state that
does not say what protects it. Services and UI stay in Swift 5 mode.

- **How:** a first pass built all four modules with complete concurrency
  checking, which only warns, so the real SDK said what Swift 6 would reject.
  For Core and Design it reported 20 places beyond those a Linux type-check
  had found. Each now says how it is safe:
  - **Lock or one thread:** state a lock guards, or that only the main
    thread or a test touches, is `nonisolated(unsafe)` with a comment naming
    its guard. So are the 13 shared `NSFont`s, which never change.
  - **Main actor:** these are main-actor isolated:
    - `SettingsRouter`, `NonModalAlert`, `ShelfSharePresenter`, the share
      anchor and the plain text editor's coordinator;
    - the two notch-display queries and the switcher's app icon.

    Each is `@preconcurrency`, so Swift 5 callers see no change.
    `ShelfSharePresenter`'s picker delegate is a `@preconcurrency`
    conformance, which Swift 6 checks at run time: AppKit calls it on the
    main thread.
  - **Sendable values:** `RadialMenuItem` is `Sendable`. The favicon
    download is `@unchecked Sendable`: only its session's serial delegate
    queue touches it. Its completion runs on the main actor.
  - **One overload:** `isTrustworthyStatusFrame` lists the attached screens
    in a main-actor overload, so the check itself takes any frames.
- **What is left for Services and UI** (measured in step 6c, below).
- **What stopped UI's build** (found in step 6c): with complete concurrency
  checking, the compiler gave up on `MenuPanelView.itemView` and
  `NotchMixerView.body` with "failed to produce diagnostic". The cause is
  not their size. It is a choice between `nil` and one of the view's own
  methods, passed where an optional action is expected:
  `permissionAction: granted ? nil : grantPermission`. Swift 6.4 reproduces
  it in a dozen lines, under complete checking and in Swift 6 mode alike;
  plain Swift 5 accepts it. The six such places pass a closure instead,
  `granted ? nil : { grantPermission() }`, which every mode accepts.

Measured (6c, what stands between Services and UI and Swift 6): both
modules were built with complete concurrency checking, which only warns.

- **Services:** each of its two compile actions wrote about 6.3 MB of
  diagnostics, more than Bazel shows (1 MB), so the warnings themselves were
  not printed. At several hundred bytes per warning with its source excerpt,
  that is thousands of places. Swift 6 for Services is a project of its
  own: type by type, starting with the services that views observe.
- **UI:** with those six closures the build completes, with 136 warnings
  in 34 files. 79 are main-actor crossings, mostly AppKit coordinators and
  delegates that are not isolated themselves; 23 send a value across
  isolation; the rest are shared statics, non-`Sendable` captures and
  `deinit` reads. That is one or two slices of work.
- **Order:** UI first: isolate its AppKit coordinators and delegates, fix
  the rest of the 136 (done in 6d, below), then build it in Swift 6 mode.
  Services follows type by type, starting with the 97 `ObservableObject`s
  that views observe, which become `@MainActor`.
- **Repeating a count:** UI keeps complete checking on since 6d. For
  Services, put `copts = ["-strict-concurrency=complete"]` on the module and
  build with `--experimental_ui_max_stdouterr_bytes=-1`.

Landed (6d, UI clean under complete checking): `VitruvianUI` builds with
no concurrency warning under complete checking. It is still in Swift 5
mode, and the build keeps complete checking on, so a new one shows. Each
of the 136 places now says what isolates it:

- **Main-actor protocols:** `ServiceViewFactory` and
  `SettingsHistoryNavigating`, `@preconcurrency` so that Swift 5 services
  still call them.
- **Main-actor types:** the AppKit coordinators of six representable views,
  the island's menu anchor, the permission guide, the screenshot keyboard
  context, and the agent-mark and radial-menu icon caches, which only views
  read.
- **Main-queue observers:** an observer the main queue delivers reaches its
  view through `MainActor.assumeIsolated`. Observers and work items that
  `deinit` removes are `nonisolated(unsafe)`: only the main thread touches
  them, and `deinit` runs after the last reference.
- **Statics:** two `NSCache`s (thread-safe) and the never-changed menu
  separator are `nonisolated(unsafe)`; two preference keys' defaults are
  `let`.
- **Values across queues:** notification settings are read before the hop
  to the main queue, the app picker's loader is `@Sendable`, and the drop
  handler's URL list says that its lock guards it.
- **Closures:** `Binding` setters and delayed refreshes take closures
  instead of function values.
- **Why Swift 6 mode came separately (6e, below):** in Swift 6 mode the compiler also
  checks, at run time, that main-actor code runs on the main thread where
  a system API calls back into it. A callback that arrives on another
  queue would then stop the app instead of racing. Before switching, each
  closure UI hands to a system or Objective-C API is checked for the queue
  it runs on.

Landed (6e, UI in Swift 6 mode): `VitruvianUI` builds in the Swift 6
language mode (`features = ["swift.enable_v6"]`), so a concurrency mistake
there is an error, not a warning.

- **The run-time check:** in Swift 6 mode, a closure written in main-actor
  code and passed to a parameter that is neither `@Sendable` nor
  `@MainActor`, in a module still in Swift 5 mode or in Objective-C, starts
  by checking that it runs on the main thread. The compiler inserts the
  check (`swift_task_isCurrentExecutor`, confirmed in SIL with Swift 6.4).
  A callback on another queue would stop the app where it used to race.
- **The audit:** every Services API that takes such a closure (80 of them)
  was listed, and each one UI calls was traced to the queue that runs the
  closure. All run on the main thread (the shortcut-recording tap, the
  clipboard copy, the island's `perform`, the panel modals, the editors'
  sharing, self-uninstall) except one: `GeneralPasteboardAccess.async`
  runs `work` on its own lane. Its `work` is now `@Sendable`, so UI's
  closure runs as plain code there.
- **Notifications:** UI's `onReceive` publishers already deliver on the
  main thread, except EventKit's store change, which now hops to the main
  run loop. UI has no KVO overrides, selector-based observers or
  background `perform`.
- **Left for Services:** the other APIs keep plain closures until Services
  moves to Swift 6; a new UI call to one of them needs the same trace.

Landed (6b, typed preferences, first slice): `Preference<Value>`
(`Core/Preference.swift`) is a key with its default. `Preferences`
(`Core/Preferences.swift`) declares them, `Defaults.registeredDefaults`
registers each from there, a view writes
`@AppStorage(Preferences.x) var x: Bool` (`Design/PreferenceStorage.swift`)
and a service can read `UserDefaults.standard[Preferences.x]`.

- **Properties keep their type.** Every `@AppStorage(Preferences.x)`
  property says its type, as it did when its default was written beside it,
  so a reader sees it without looking the preference up.

- **Why these five first:** comparing every `@AppStorage` default with the
  registered one found these disagreeing. The app registers its defaults at
  launch and the registered value wins there, so users saw the registered
  default. Views read the other one wherever registration had not run, as
  in a preview or a test:
  - `windowLayoutShortcutsEnabled`: registered off, two views on;
  - `micMuteMenuBarIndicator`: registered on, two views off;
  - `menuBarMetricSpacing`: registered `compact`, two views `standard`;
  - `menuBarMetricOrder`: registered the default order, two views empty;
  - `screenshotPreviewPosition`: registered `automatic`, the view empty.

  They now share the registered default, so the app's behavior does not
  change.
- **Tested directly:** `PreferenceTests` checks that each of the five is
  registered with its declared default, and that it reads the same through
  `UserDefaults` and through `@AppStorage`, before registration and after.
  It also checks the typed read: a missing or mistyped value reads as the
  default.
- **Second slice, the switches:** every on/off preference with a literal
  default moved too, 358 of them, with a script. Each is registered from its
  declaration, and its 453 `@AppStorage` properties take the `Preference`.
  - None of these disagreed.
  - The script left alone the ten switches whose key a test pins by name in
    source text, and `includeBetaUpdates`, whose view starts from
    `AppInfo.isBeta` on purpose.
  - A Linux type-check with an `AppStorage` stand-in carrying SwiftUI's
    initializers shows no new error. It does catch a property whose
    declared type disagrees with its preference.
- **Third slice, numbers and text:** 141 preferences with a literal whole
  number, fraction or text default moved the same way, and 130 `@AppStorage`
  properties take them. Each was moved only where every view repeated the
  same default with the same kind of literal, so no stored type changes.
  The script skipped seven whose views name their default through a
  constant, such as the usage bar colors.
- **Fourth slice, computed defaults:** 63 preferences whose default is an
  expression (a shortcut's storage value, a raw value, a named constant)
  that every view repeated word for word, so the views already showed it
  has a type `@AppStorage` stores. 88 `@AppStorage` properties take them.
  `Data` joined the value types for the quick-access layout.
- **Fifth slice, the rest:** the last 139 registered keys moved, so every
  default `Defaults.registeredDefaults` registers is declared in
  `Preferences`.
  - A `Preference` also holds a list of text or a table of text, for the 26
    lists and 3 tables. `@AppStorage` holds neither, so services read them
    through `UserDefaults[preference]`. `PreferenceTests` checks both, and
    that a list is registered with its declared default.
  - 19 `@AppStorage` properties for 11 of them take the `Preference`. Their
    views named the default through a constant, such as the usage bar
    colors, and each constant equals the registered value, so the
    declaration uses the constant.
  - Views still write out a default for the 27 keys that tests pin by name
    in source text, for two that views read as enums, and for
    `includeBetaUpdates`.
- **Left for later slices:**
  - services still read most preferences by `DefaultsKey`; each read can
    move to `UserDefaults[preference]` as its code is touched;
  - 26 `@AppStorage` keys that are not registered at all, such as the menu
    bar metric switches and the panel orders. Registering them would change
    what code that checks `object(forKey:) == nil` sees, so each needs a
    look first.

Landed (6f, the first services on the main actor): six of Services' 97
`ObservableObject`s are `@MainActor`. They are `AgentCodexResetService`,
`AppAppearanceController`, `DiskProtectionService`,
`NetworkAddressService`, `PortManagerService` and
`UpdateShowcaseMediaLoader`.

- **Why these six:** views observe them, and no Services code calls them
  outside the main thread. In Swift 5 mode, a call from plain synchronous
  code into a `@MainActor` method is already an error, not a warning, so
  each service that joins needs its callers on the main actor first.
- **What ran off the main thread stays off it, now said so:** the work
  these services do on their own queues is `nonisolated`:
  - the Codex lookup;
  - the `lsof` snapshot;
  - the Disk Arbitration eject and its completion;
  - the interface list.
- **A race fixed:** the showcase download's completion released the
  loader's session on the URL session's queue while the main thread could
  set it. It now does that on the main thread.
- **The app delegate:** only its `NSApplicationDelegate` callbacks are on
  the main actor. Its other methods are plain code, because the class
  itself is not isolated. So `setUpPopover()`, which
  `applicationDidFinishLaunching` calls and which hands the popover to
  `AppAppearanceController`, is now `@MainActor`.
- **Left as they are:**
  - `SpeedTest` keeps its own serial queue by design, so it does not join.
  - The next services all go through `FeatureRuntime`, which calls their
    `syncWithPreferences()` from plain code, and the screenshot and
    recorder editors through their controllers. Those hubs come next,
    from the top down: once they are on the main actor, the services they
    call can follow.
- **Checked:** a Linux type-check of Core through UI against stand-ins.
  Before the change, the probe listed every off-main call, each fixed
  above. After it, the six files are clean under complete checking.

Landed (6g, the features hub on the main actor): `FeatureRuntime`, which
starts, stops and syncs every feature's service, is `@MainActor`. That
opens the way for the services it calls.

- **Its callers:**
  - The app delegate, the settings and the onboarding already run on the
    main actor.
  - `SettingsBackup.applyAndRelaunch` is now `@MainActor`; only the
    Settings import calls it.
  - The app delegate's `relaunchApp()` implements the plain `AppShell`
    protocol, so it is not on the main actor. It reaches the hub through
    `MainActor.assumeIsolated`; its callers are UI buttons.
  - The command bar's toggle and relaunch rows, and `ShortcutCapture.end()`,
    stay in plain code, because their own callers are plain Services code.
    They reach the hub through `MainActor.assumeIsolated`. Every path to
    them was traced to the main thread: the bar's keys and clicks, the
    recorder button, and the recording tap's main-queue hops and
    `SessionActivity`'s main-queue delivery.
- **Checked:** the same Linux probe adds no error, and the source-text
  tests that read these lines still find what they look for.

Landed (6h, five services the hub starts): `AudioPriorityService`,
`MusicLaunchBlocker`, `CleanerScheduler`, `WhatsAppDownloadScheduler` and
`WallpaperService` are `@MainActor`. With the hub on the main actor, they
needed only their own off-main paths said:

- **The schedulers:** each schedules a one-shot `Timer` on the main run
  loop. Its block reaches the scheduler through `MainActor.assumeIsolated`.
- **The wallpaper:** the apply generation that the off-main apply reads is
  `nonisolated` and still answers under its lock. Checking whether a file
  waits on iCloud is `nonisolated` too.
- **Still waiting:** the following move later, together with their callers:
  - `JunkCleaner` (`PanelInteractionState` reads its phase);
  - `ClipboardIgnoredApps` (the clipboard history calls it);
  - `WindowLayoutIgnoredApps` (the window layout service);
  - `MenuPanelFocus` (the island);
  - the Dock preview's pinned panel;
  - the editors.
- **What is left, measured:** with 11 of the 97 on the main actor, the
  same probe was run with all 82 others annotated at once. It gives 580
  errors in 65 files. Three files hold 237 of them:
  - `AgentUsageService` (90), which keeps its own queue by design and may
    stay off the main actor, like `SpeedTest`;
  - `CommandBarCatalog` (75), whose rows' closures run on the main thread;
  - `SystemMonitor` (72).
  The rest are a few each. Rerunning that probe after each slice tracks
  the count.

Landed (6i, seven more services): `DockPreviewPinnedPanel`,
`ExtraBrightnessService`, `ClipboardIgnoredApps`, `HotkeyManager`,
`CleaningModeManager`, `AudioInputDeviceManager` and
`NotchAudioLevelService` are `@MainActor`. A per-service probe (each one
annotated alone) ranked these as one or two errors each.

- **Timers on the main run loop** (the pinned panel's refresh, Extra
  Brightness's heartbeat) reach their owner through `MainActor.assumeIsolated`.
- **Methods that only main-actor code calls** take `@MainActor` themselves,
  with the attribute on its own line so the test generator's prefixes still
  match:
  - the updater's `launchInstaller` and `launchAdminInstaller`;
  - the clipboard history's `syncWithPreferences`, `start` and `stop`;
  - the uninstaller's `suspendInputInterceptors`;
  - the app delegate's Cleaning Mode menu action;
  - the clipboard history's `captureIfChanged`, whose pasteboard read
    completes on the main queue;
  - the Dock preview's `createPinnedPanel`.
- **Plain callers that run on the main thread** use
  `MainActor.assumeIsolated`:
  - the Dock preview's `togglePinned()`, which UI passes as a method
    reference, so it stays plain itself;
  - the shortcut recorder's `begin()`;
  - the command bar's Cleaning Mode row;
  - the island's preference sync and teardown.
- **The audio input's HAL reads** run on their own queue, so its static
  helpers are `nonisolated`.
- **Not yet:** `MenuPanelFocus` (1 error in Services) is called about 30
  times from app delegate methods that are not on the main actor. It
  waits for the app delegate itself to be isolated.

Landed (6j, the app delegate on the main actor): `AppDelegate` is
`@MainActor`, so all of it runs as main-actor code, not only its
`NSApplicationDelegate` callbacks. `MenuPanelFocus` follows it.

- **Redundant annotations removed:** the per-method `@MainActor` on
  `setUpPopover()` (6f) and on the Cleaning Mode menu action (6i) are
  gone. So is the `MainActor.assumeIsolated` in `relaunchApp()` (6g).
- **`main.swift`** builds the delegate through `MainActor.assumeIsolated`;
  top-level code runs on the main thread.
- **Still plain code:** `AppShell`, the protocol Services and UI use to
  reach the app, is not isolated. In Swift 5 mode the delegate's
  conformance to it is a warning. It becomes an error in Swift 6, which
  means `AppShell` (and its callers) will need to move to the main actor
  before the App module does.
- **A warning fixed from 6h:** the wallpaper's folder scan read the
  gallery's lifecycle from its worker queue. The lifecycle keeps its
  state under a lock, so it is `@unchecked Sendable` and the property is
  `nonisolated`.
- **Checked:** the Linux probe now includes `App/`, `Support/` and
  `main.swift`. Against 6i it adds only the `AppShell` conformance warning.

Landed (6k, three more services): `SecureInputMonitor`,
`SoundOutputSwitcher` and `PastePlainService` are `@MainActor`.

- **Off-main paths:**
  - The secure-input poll is a main-run-loop timer and reaches the
    monitor through `MainActor.assumeIsolated`.
  - The paste-plain read runs on the pasteboard's lane, so
    `plainText(from:)` is `nonisolated`.
  - The output switcher's Carbon hotkey handler already hops to the main
    queue.
- **Plain callers that run on the main thread** use
  `MainActor.assumeIsolated`: the shortcut recorder's `begin()` and the
  command bar's Paste Plain row.
- **The ranking:** the per-service probe finished for all 84 remaining
  services. Its cheapest entries are services that own CGEvent taps:
  - `ScrollInverter`, the mouse services and `SmoothScrollService` run
    their taps on the pointer thread (`PointerTapRunLoop`), so they stay
    off the main actor;
  - `WindowMaximizer` and `PreciseVolumeRollerService` run theirs on the
    main run loop, but their C callbacks call the service directly. They
    need the callback reworked before they can follow.
  - The Linux probe cannot see into those callbacks, so taps are checked
    by hand.

Landed (6l, the app shell on the main actor): `AppShell`, the protocol
Services and UI use to reach the app, is `@MainActor`. So the app
delegate's conformance (6j) no longer crosses isolation, and the App
module has no concurrency warning of its own left.

- **Where Services reach the app:** the 17 calls run from the command
  bar's actions and monitors, the radial menu, the clipboard editor, the
  recent captures, the permission prompts and the island.
  - The radial menu's `openSettings` runs from main-queue blocks, so it is
    `@MainActor`.
  - The other calls go through `MainActor.assumeIsolated`; each one was
    traced to the main thread.
- **Listed by hand:** the Linux probe saw 12 of the 17. The rest sit in
  NSEvent monitor closures, which the stand-ins cannot type-check.

Landed (6m, the updater, two quick tools and the menu bar item):
`UpdateService`, `ColorSamplerService`, `SnippetLibraryService` and the
app's `StatusItemController` are `@MainActor`.

- **A race fixed:** the update download's completion invalidated the
  service's session on the URL session's queue while the main thread could
  clear it. It now does both on the main thread, as the showcase loader
  does since 6f. The download delegate's `progress` and `completion` are
  `@Sendable`, so the compiler checks that neither touches main-actor state.
- **Timers and observers on the main run loop** reach their owner through
  `MainActor.assumeIsolated`: the hourly update check, and the menu bar
  item's title timer and defaults observer.
- **The command bar's `afterBeat`** takes main-actor work. Its block runs
  on the main queue, so the rows that pass it a closure no longer need
  `MainActor.assumeIsolated`; four lose it, including two of 6l's.
- **Nonisolated:** the update's pure statics (the read-only volume check,
  the install-result path, the version compare) and the color sampler's
  formatting and quiet copy, which the capture loupe calls while it draws.
- **Plain callers that run on the main thread** use
  `MainActor.assumeIsolated`:
  - the island's update action, which UI passes as a method reference;
  - the feedback diagnostics' beta opt-in;
  - the capture chooser's native color sampler and color delivery;
  - the command bar's snippet rows;
  - the snippet expander's sync, which reads whether the library is up.
- **Waiting for their owners:** the island's lyrics and quick access
  motion wait for `NotchService`, and the pointer shortcut and the ignored
  apps list for `WindowLayoutService`. Most of their callers are inside
  those two.

Landed (6n, the command bar on the main actor): `CommandBarService` is
`@MainActor`, and so is every row's action: `CommandBarEntry.run` is a
`@MainActor` closure, since the bar runs its rows from its own keys and
clicks.

- **Wrappers gone:** the rows that reached main-actor code through
  `MainActor.assumeIsolated` call it directly: the feature switches, the
  relaunch and the snippet rows. So do the bar's three ways into Settings
  from 6l.
- **Off the main thread, said so:** the Spotlight app lookup runs on a
  global queue, so it is `nonisolated`. The bar's other background reads
  already hand their results to the main queue.
- **Main-queue callbacks:** the restart observer reaches the bar through
  `MainActor.assumeIsolated`.
- **Plain callers:** the island's Command Bar action and the snippet
  expander's visibility read use `MainActor.assumeIsolated`. The saved-link
  and script helpers, which only rows call, are `@MainActor`.
- **Checked by hand:** the bar's twelve background reads, its observer,
  its event monitors, and the result callbacks of the file search and the
  script runner. The Linux probe cannot type-check about a hundred of the
  file's expressions, because its stand-ins lack most of AppKit.

Landed (6o, the island on the main actor): `NotchService` is `@MainActor`.
Most notch services and quick tools report to it, so this slice is mostly
about its callers.

- **Calls into the island from plain code** go through
  `MainActor.assumeIsolated`. Each was traced to the main thread:
  - the Shelf's drag monitor, its watchdog and its toggles;
  - the brightness keys, slider and on-screen display, the precise volume
    keys and the microphone mute;
  - the camera, the launcher, the Scratchpad and the clipboard history;
  - the capture chooser, the quick preview, the selection's key monitor and
    the windows a capture leaves out;
  - the timer, Watch, accessory notices and the lock screen;
  - `main.swift`, which wires the island's collaborators. Top-level code
    runs on the main thread.
- **Methods that only main-actor code calls** take `@MainActor`, with the
  attribute on its own line so the tests' copies stay plain:
  - the Shelf's internal drag;
  - the Scratchpad's export;
  - the media dialogs' panel modal;
  - the downloads folder chooser;
  - the lyrics import.
- **`perform`** takes main-actor work. The action runs once the island
  settles, on the main queue, so the island's own Command Bar action no
  longer needs a wrapper (6n).
- **Read by hand:** about half of these calls sit in code the Linux
  stand-ins cannot type-check: event monitors, panels and SwiftUI hosts.
  Every reference to the island outside it was listed and read.
- **Tests:** where a test copies one of these methods, its stand-in island
  runs on the test's main thread, so the copies keep working.

Landed (6p, the island's own windows and notices): with the island on the
main actor, what it owns and drives follows. These are `@MainActor`:

- `NotchWindowHost`, its quick-access motion and its backdrop;
- the lock screen service and its model;
- the timer, Watch and accessory notices.

Details:

- **Wrappers gone:** the 6o `MainActor.assumeIsolated` calls inside the
  timer, Watch, accessory and lock screen services are no longer needed.
- **Off the main thread, said so:**
  - IOBluetooth may report a connection on any thread. Those two `@objc`
    callbacks are `nonisolated`, and each hops to the main queue as before.
  - Watch's down-scaling for text recognition runs in a detached task, so
    it is `nonisolated`.
- **The window host:**
  - Its Mission Control timer reaches it through `MainActor.assumeIsolated`.
  - `whenSettled` takes main-actor work.
  - Its conformance to the mirrors' host protocol is `@preconcurrency`;
    the mirrors drive it on the main thread.
- **Waiting for the music service:** the lyrics service is called from
  the music service's plain code, so it moves with that service.

Landed (6q, the island's music, lyrics, calendar and file tools): these are
`@MainActor`:

- `NotchMusicService` and `NotchLyricsService`;
- `NotchCalendarService`;
- `NotchFileToolsService`.

Details:

- **Their background work already hands results to the main queue**, so
  only what runs off the main thread had to say so:
  - The music adapter's pipe reader computes the artwork tint on its own
    queue, so `artworkTint(of:)` is `nonisolated`.
  - The lyrics download reports on its session's queue, so its completion
    is `@Sendable`.
  - The calendar's store observers are on the main queue and reach the
    service through `MainActor.assumeIsolated`.
  - Calendar reads stay in their own actor, as before.
- **The file drop's media environment** (`NotchFileDrop.Environment.system`)
  is `@MainActor`; the island builds it.
- **Left for Swift 6:** the music adapter's pipe reader takes a plain
  closure, which keeps its artwork cache in captured variables. Swift 6
  will ask for that closure to be `@Sendable`, and the cache will have to
  move into the reader.

Landed (6r, the island's downloads and notifications):
`NotchDownloadService` and `NotchNotificationService` are `@MainActor`.

- **Callbacks on the main queue or run loop** reach them through
  `MainActor.assumeIsolated`:
  - the downloads folder's file-system sources;
  - the workspace observers;
  - the Accessibility observer's C callback, whose source is on the main
    run loop.
- **Their reads stay on their own queues** and hand results to the main
  queue, as before.
- **Wrappers gone:** the 6o method-level `@MainActor` on the downloads
  folder chooser, and the downloads' `MainActor.assumeIsolated` around its
  main-actor progress callbacks.

Landed (6s, four quick tools): `QuickLauncherService`,
`CameraPreviewService`, `ScratchpadService` and `ScreenTextService` are
`@MainActor`.

- **Wrappers gone:** their 6o `MainActor.assumeIsolated` calls into the
  island, and the Scratchpad export's method-level `@MainActor`.
- **Off the main thread, said so:** text recognition runs on a background
  queue and in Watch's detached task, so `ScreenTextService.outcome` and
  the recognition it runs are `nonisolated`. So is the launcher's column
  count, a constant.
- **Plain callers:**
  - The capture chooser hands recognized text over through
    `MainActor.assumeIsolated`.
  - The settings export, which only Settings calls, is `@MainActor`.
- **Observers:** blocks registered on the main queue already run as
  main-actor code in this SDK, as the app delegate's do since 6j, so the
  camera's and the launcher's observers need nothing.
- **Not yet:** `RecentCaptureService` and `QuickTogglesService` do most of
  their work on background queues that read shared state directly. Each
  needs its own slice.

Landed (6t, the link cleaner, the WhatsApp downloads and Homebrew):
`URLCleanerService`, `WhatsAppDownloadManager`, `WhatsAppDownloadOrganizer`
and `HomebrewManager` are `@MainActor`.

- **Their workers are `nonisolated`:** the static functions that run on
  each service's queue or on the pasteboard lane:
  - the link cleaner's poll, rules and write;
  - the downloads review's candidate scan;
  - the organizer's whole file-moving and record-keeping engine;
  - Homebrew's process launch, stop and timeouts.
  These only touch files, the pasteboard and the defaults.
- **Timers and sources on the main run loop** use
  `MainActor.assumeIsolated`: the link cleaner's poll timer, and the
  organizer's timer and folder source.
- **Plain callers on the main thread:**
  - The app updates' Homebrew upgrade goes through
    `MainActor.assumeIsolated`, and so do the uninstaller's and the panel's
    reads of Homebrew's progress.
  - The uninstaller's Homebrew removal and the command bar's selection rows
    and clipboard link cleaner, which only main-actor code calls, are
    `@MainActor`.
- **Not yet:** `JunkCleaner`, `AppUninstaller` and `KillProcessService`
  run dozens of static scanners off the main thread. The test generator
  copies many of them by their declaration line, so they need their own
  slice.

Landed (6u, the capture tools): these are `@MainActor`:

- the capture chooser (`ScreenCaptureService`) and its options;
- the on-screen selection (`ScreenshotSelectionController`);
- the quick preview and its model;
- `ScreenshotService`;
- the media workspace's selection model.

Details:

- **Wrappers gone:** the `MainActor.assumeIsolated` calls these files made
  into the island (6o), the color sampler (6m) and screen text (6s).
- **Off the main thread, said so:** `ScreenshotService`'s static helpers
  flatten, encode and name captures in detached tasks and on other
  services' queues, so they are `nonisolated`. The test generator copies
  `imageCapture(from:)` by its declaration line, so its `nonisolated`
  stands on the line above.
- **One thread, said so:** the selection's "a session is on screen" flag
  and its active session are `nonisolated(unsafe)`. Only the main thread
  touches them, but a session's deinit clears them.
- **Smooth scrolling's question:** its tap, still plain here, asks whether
  the loupe takes raw wheel steps. That check is `nonisolated` and reads the
  session through `MainActor.assumeIsolated`; the tap's source is on the
  main run loop.
- **Plain callers on the main thread** use `MainActor.assumeIsolated`: the
  screenshot editor's close and the recorder's toggle.
- **Not yet:** the HUD (`QuickToolHUD`) is a static enum that almost every
  service calls, so its scrolling-capture model stays plain with it. The
  media service runs its workers on its own queue under a lock and needs
  its own slice.

Landed (6v, Keep Awake): `KeepAwakeManager` is `@MainActor`.

- **Its three timers** (session end, battery watch, pointer jiggle) are on
  the main run loop and reach it through `MainActor.assumeIsolated`.
- **Its other callbacks already hop to the main queue:**
  - the power-source and lid C callbacks;
  - the screen-lock and app observers;
  - the `sudo` and `pmset` checks.
- **The command bar's catalog is built on the main actor:**
  `CommandBarCatalog.build` and its action rows are `@MainActor`, so rows
  read Keep Awake's live state directly. The bar is their only caller.
- **Left for Swift 6:** Keep Awake's defaults subscription runs where the
  defaults change, which can be off the main thread. It flips a scheduling
  flag there before hopping to the main queue.
- **Not yet, each for its own reason:**
  - `MouseAppExceptions` is read from the pointer thread's taps.
  - `QuitProtectionService` is called from the app switcher's tap path.
  - `FanControlService` keeps its probe hardware on a serial queue of its
    own.

Landed (6w, the two editors): the screenshot and recording editors, their
models and their windows' controllers, are `@MainActor`. So is
`BackdropEditing`, the background picker's view of either model.

- **The text and code scans** run off the main thread. They used to stop
  early by comparing the capture they read with the model's current one,
  which is main-actor state. They now stop on a token:
  - each new scan cancels the one before, and every change of the capture
    starts a new scan;
  - a lock guards the token;
  - the main-queue check that drops a stale result is unchanged.
- **Off the main thread, said so:** the screenshot editor's clipboard and
  file helpers are `nonisolated`. The auto-copy builds its payload in a
  detached task, and the pin window calls them from plain code.
- **The player's time observer** is delivered on the main queue and reaches
  the model through `MainActor.assumeIsolated`.
- **Wrappers gone:** the screenshot editor's close no longer needs the 6u
  wrapper around `ScreenshotService`.
- **The recorder service** stays plain for now (its session calls back from
  capture queues). The methods that open, close and sweep editors are
  `@MainActor`; all their callers are the feature runtime, the media
  workspace and the recorder's own main-actor tasks.

Landed (6x, the mouse taps on the main run loop): five services whose event
tap is a source on the main run loop are `@MainActor`:

- the window maximizer;
- mouse navigation;
- mouse button shortcuts;
- the radial menu;
- smooth scrolling.

Details:

- **The tap callbacks** are C functions, so they reach their service through
  `MainActor.assumeIsolated`. The main run loop serves them.
- **Timers** on the main run loop (the maximizer's frame animation and
  settle, the smooth-scroll frame timer) do the same.
- **Off the main thread, said so:** mouse navigation lists the web URL
  handlers on a global queue, so that static is `nonisolated`.
- **Main-actor work:** the radial menu's delayed post takes `@MainActor`
  work, run from the main queue.
- **Not yet:** middle click and the scroll inverter serve their taps from
  the pointer thread (`PointerTapRunLoop`), so they stay plain.

Landed (6y, the volume keys, Auto Quit and Dock Preview): three more
services that serve their taps from the main run loop are `@MainActor`:

- the precise volume keys;
- Auto Quit;
- Dock Preview.

Details:

- **Tap and Accessibility callbacks** are C functions on the main run loop
  and reach their service through `MainActor.assumeIsolated`, as in 6x.
  Auto Quit's window observers are such a callback.
- **Timers** on the main run loop (Dock Preview's Dock-visibility and
  settings polls) do the same.
- **Wrappers gone:** the volume keys read the island directly again, as
  before 6o.
- **Plain callers:** the Dock click tap asks whether a preview panel covers
  the click, and the switcher's window close tells Auto Quit about it. Both
  run on the main thread and use `MainActor.assumeIsolated`.

Landed (6z, Window Layout and shortcut recording): these are `@MainActor`:

- `WindowLayoutService`, its ignored apps and the pointer's next-display
  key;
- `ShortcutCapture` and `ShortcutRecordingTap`, which say "main thread
  only" in their documentation.

Details:

- **Window Layout's three taps** (directional, edge snap, gesture) and its
  settle and gesture timers are on the main run loop and reach it through
  `MainActor.assumeIsolated`, as in 6x. Its Carbon hotkey handler already
  hops to the main queue.
- **Tests' statics:** the ignored-apps matching that tests call directly is
  `nonisolated`.
- **Wrappers gone:** `ShortcutCapture`'s three `MainActor.assumeIsolated`
  calls (6g to 6k).
- **UI:** the shortcut field's `deinit` gives the keys back through
  `MainActor.assumeIsolated` when it runs on the main thread; otherwise it
  still hops to the main queue.

Landed (6za, quick toggles and the recorder's audio choices): these are
`@MainActor`:

- `QuickTogglesService`;
- `RecorderSelectionAudioOptions`, the two audio choices shown while an
  area is picked.

Details:

- **The toggles' work queue** hands each result to the main queue, where
  the run state is published, instead of publishing from the queue through
  a main-thread check. What runs on the queue says so: the Finder restart
  and its exit poll, the volume listing and the Automation target are
  `nonisolated`.
- **The recorder's `record(_:audioOptions:)`** is `@MainActor`; the capture
  chooser is its only caller.
- **UI:** the radial menu's quick-toggle title reads the toggles' state, so
  it is `@MainActor`, like the item names next to it.
- **Not yet, each for its own reason:**
  - the microphone mute is read from the input manager's audio queue;
  - recent captures keep their store on a serial queue of their own.

Landed (6zb, clipboard history and quit protection): `ClipboardHistoryService`
and `QuitProtectionService` are `@MainActor`.

- **Off the main thread, said so:** the history's pasteboard read (on the
  shared pasteboard lane) and its persistence (on its own queue) run
  statics that are now `nonisolated`: the reader and its helpers, the
  limits, the store's location and the queue itself.
- **Wrappers gone:** the history's 6o `MainActor.assumeIsolated` calls into
  the island and its 6l call to the app shell.
- **Callers:**
  - The command bar's clipboard rows read the history, so the two catalog
    functions that build them are `@MainActor`; the bar is their only
    caller.
  - The switcher asks quit protection for a second press from its key
    handling, which runs inside `main.sync`, through
    `MainActor.assumeIsolated`.
- **Quit protection's tap and hold timer** are on the main run loop and use
  `MainActor.assumeIsolated`, as in 6x.
- **Not yet:** `Permissions` is read from the pointer thread (the scroll
  inverter), the switcher's tap path and some twenty plain call sites, so
  it moves when they do.

Landed (6zc, the cleaner, the uninstaller and the process killer):
`JunkCleaner`, `AppUninstaller` and `KillProcessService` are `@MainActor`,
and so is `PanelInteractionState`, the panel's close policy, which reads
all three.

- **Their scanners are `nonisolated`:** each service scans on a global
  queue with static functions that only touch files, processes and the
  defaults. The test generator copies many of them by their declaration
  line, so `nonisolated` stands on the line above each one.
- **The process killer's workers:** the batch kill and its follow-up run on
  a global queue and only hop to the main queue, so they are `nonisolated`.
  Its `refresh` is called from any thread (an app relaunch reports from the
  workspace's queue); it stays `nonisolated`, hops to the main queue when it
  has to, and runs its body through `MainActor.assumeIsolated`.
- **Wrappers gone:** the 6t `MainActor.assumeIsolated` calls in the
  uninstaller and the panel's close policy, and the uninstaller's
  method-level `@MainActor`.

Landed (6zd, the Shelf, app updates and fan control): `ShelfService`,
`AppUpdatesService` and `FanControlService` are `@MainActor`.

- **The Shelf:** its file sweeps run on a global queue and only read the
  temporary and store directories, so they, the directories and the
  persist queue are `nonisolated`. Its drag watchdog and auto-hide timers
  are on the main run loop and use `MainActor.assumeIsolated`. The 6o
  wrappers into the island and the method-level `@MainActor` on its
  internal drag are gone.
- **App updates:** the scan runs on its work queue. The six methods it
  calls there are `nonisolated` (on their own line, since the test
  generator copies three of them by their declaration line), and so are
  the statics they use. The two URL sessions are plain constants instead
  of lazy properties, which no isolation can describe; they are now made
  with the service. The online catalog cache is `nonisolated(unsafe)`:
  only the work queue touches it. The 6t wrapper is gone.
- **Fan control:** the probe hardware is `nonisolated(unsafe)`, since only
  the probe queue touches it, and the helper's removal statics, which
  uninstalling calls from a background queue, are `nonisolated`. Its
  replies already hop to the main queue.
- **Callers:** the command bar's row that keeps a selection on the Shelf
  calls it from `keepOnShelf`, which is `@MainActor`; the row's action is
  its only caller and already runs on the main actor.

Landed (6ze, Finder cut and paste, the speed test and agent usage):
`FinderCutPaste`, `SpeedTest` and `AgentUsageService` are `@MainActor`. Each
keeps work on its own thread or queue; what runs there now says so.

- **Finder cut and paste:** its keyboard tap runs on a thread of its own, so
  the tap's start, stop and callback are `nonisolated`, and the tap state
  its lock guards is `nonisolated(unsafe)`. The callback already handed a
  shortcut to the main thread with `DispatchQueue.main.sync`; that call now
  enters the main actor through `MainActor.assumeIsolated`. The moves and
  the progress poller run on global queues and are `nonisolated`.
- **The speed test:** its state lives on the URL session's delegate queue,
  so the methods that run there, the delegate methods and that state are
  `nonisolated`. Its published values already hop to the main queue. Its
  test calls it from the runner's main thread and now says so with
  `MainActor.assumeIsolated`.
- **Agent usage:** the log reading runs on its own queue. The methods and
  statics that run there are `nonisolated` (three on their own line, since
  the test generator copies them by their declaration line), and the state
  already marked "Confined to `queue`" is `nonisolated(unsafe)`. The tick
  timer is on the main run loop and uses `MainActor.assumeIsolated`.
- **Not yet:** `MouseAppExceptions` answers the pointer thread's taps
  (middle click, the scroll inverter), which read `.shared` there; its lists
  are lock-guarded for that, and it stays plain.

Landed (6zf, keyboard debounce, the system monitor and the media tools):
`KeyboardDebounceService`, `SystemMonitor`, `MonitorAlertService` and
`MediaService` are `@MainActor`.

- **Keyboard debounce:** its tap runs on a thread of its own and restarts
  itself from there, so starting, the tap loop, the callback and the
  running-flag publish are `nonisolated`. The state its two locks guard is
  `nonisolated(unsafe)`. The publish sets the flag through
  `MainActor.assumeIsolated` from a closure that is now `@Sendable`; it
  runs only on the main thread, directly or queued there.
- **The system monitor:** sampling runs on its own queue. The sensors, the
  samplers, the last readings and the histories belong to that queue and
  are `nonisolated(unsafe)`; what decides when to sample stays on the main
  thread. The sampling helpers are `nonisolated` (`readCPUUsage` on its own
  line, since the test generator copies it), and so are the fan-count
  statics the menu bar renderer reads. The timer is on the main run loop
  and uses `MainActor.assumeIsolated`. The alerts service, which only
  follows the monitor's snapshots on the main queue, is `@MainActor` with
  it.
- **The media tools:** every tool runs on the service's work queue, so the
  33 work methods are `nonisolated`, and the work a tool hands to `run` is
  `@Sendable`. The operation state its lock guards is
  `nonisolated(unsafe)`. Its init is `nonisolated`: the island's file tools
  and the media presentation probe make their own.

Landed (6zg, recent captures and the HUD): `RecentCaptureService`,
`QuickToolHUD` and the HUD's scrolling-capture model are `@MainActor`.

- **Recent captures:** the store lives on the service's queue. It was a
  lazy property, which no isolation can describe, so it is now a constant
  made with the service, and the folder it lives in is found once, in
  init. The queue's methods, the thumbnail statics and the recording
  thumbnail (which awaits off the main actor, as before) are
  `nonisolated`; the store, the clear generation its lock guards and the
  thread-safe thumbnail cache are `nonisolated(unsafe)`. The 6l wrappers
  around closing the panel are gone.
- **The HUD:** with almost every service on the main actor, its state is
  too. `show` and `showCountdown` stay callable from any thread, since the
  recorder, the microphone mute, the QR and pin windows and a command bar
  row still call them from plain code: each is a `nonisolated` entry that
  hops to the main queue when it has to and runs its body through
  `MainActor.assumeIsolated`.
- **Still plain:** the microphone mute (read from the input manager's
  audio queue, and copied whole by the test generator) and the screen
  recorder (its microphone callback runs off the main thread).

Landed (6zh, the switcher and the screen recorder): `AppSwitcher` and
`ScreenRecorderService` are `@MainActor`.

- **The switcher:** its keyboard tap runs on a thread of its own and routes
  each key by state its locks guard, so the tap's lifecycle and routing are
  `nonisolated` and that state is `nonisolated(unsafe)`. A key the switcher
  may consume already went to the main thread through `main.sync`; it now
  enters the main actor there through `MainActor.assumeIsolated`. The
  window enumeration's focused-window lookup runs on its queue and is
  `nonisolated`, and so are the two ownership queries other taps ask, which
  only read under the lock. The 6zb wrappers into quit protection are gone.
- **The recorder:** the session reports an unexpected stop, and a
  microphone that would not start, from its capture side. Both callbacks
  are now `@Sendable`. `stop` stays callable from any thread as a
  `nonisolated` entry that hops to the main queue when it has to. The
  microphone notice's text is read before the session starts, so its
  callback needs nothing from the main thread. The elapsed-time timer is
  on the main run loop and uses `MainActor.assumeIsolated`. The
  method-level `@MainActor` from 6u, 6w and 6za, and the 6u wrapper in
  `toggle`, are gone.

Landed (6zi, the Super key): `SuperKeyService` is `@MainActor`.

- **Its own threads:** the keyboard and mouse taps run on a thread of their
  own, and the key mapping is written on a serial queue. What runs there is
  `nonisolated`: the tap's lifecycle and callback, the solo actions, the
  mapping's request and the `hidutil` work, and the Caps Lock and key
  posting helpers. `runEventTap` takes `nonisolated` on its own line, since
  the test generator copies it by its declaration line. The state the two
  locks guard and the queue's mapping guard are `nonisolated(unsafe)`.
- **Back on the main thread:** the mapping's completion is `@MainActor`,
  since it publishes the run state and the failure. Letting go of a held
  key notifies through a `@Sendable` closure that runs only on the main
  thread, through `MainActor.assumeIsolated`.
- **The settings directory:** its builders defaulted an argument to the
  key's published source. A Swift 5 module evaluates a default argument
  outside any actor, so the argument now defaults to nil, and the
  builders, now `@MainActor`, read the source themselves. Their callers,
  the command bar's settings rows and the Settings window's directory
  cache, are `@MainActor` too.

Landed (6zj, the volume mixer): `AppVolumeMixer` is `@MainActor`.

- **Already split:** the mixer keeps its state on the main thread and does
  its audio-system work on two queues through statics that take values:
  every read of a refresh, the output volume and mute, the default device.
  Those 26 statics are `nonisolated`, and so are the support check and the
  maximum volume that views and the command bar read.
- **Across the queue:** an output adjustment checks on the HAL queue that
  its output is still current, under the output-control lock. That check
  is `nonisolated` (on its own line, since the test generator copies it),
  and the lifetime it reads is `nonisolated(unsafe)`.
- **Not yet:** the AirPlay route manager. The mixer's engine builds ask it
  for a renderer from the build queue, so it moves when it no longer has
  to be reached through `.shared` from there.

Landed (6zk, AirPlay routing): `AirPlayRouteManager` is `@MainActor`.

- **Handed over, not looked up:** an AirPlay build now takes the manager
  on the main thread and hands it to the build queue and its engine, which
  used to reach it through `.shared` there.
- **What the engines reach:** adding, preparing and ending a stream, and
  binding a renderer to the routing context, run on the engines' threads
  under the stream lock. They are `nonisolated`; the renderer is
  `nonisolated(unsafe)` behind that lock, and the routing context and the
  message-send symbol, set once in init, are too. The stream registry was
  a lazy property, which no isolation can describe, so it is made in init.
- **The mixer's snapshot:** the listed, connected and speaker statics the
  HAL queue reads stay behind their lock and are `nonisolated`, and so is
  the AirPlay sentinel.
- **Back on the main thread:** the renderer reports a failure through a
  `@MainActor` callback it already called from the main queue. The picker's
  delegate, the context's observer and the backup timer reach the manager
  through `MainActor.assumeIsolated`.
- **The self-test** reads whether AirPlay is available from top-level code,
  through `MainActor.assumeIsolated`, as `main.swift` does.

Landed (6zl, middle click and the scroll inverter): `MiddleClickService`
and `ScrollInverter` are `@MainActor`.

- **The pointer thread:** both serve their taps from `PointerTapRunLoop`.
  The callbacks and what they call are `nonisolated`, and the state their
  locks guard, or that only the tap touches, is `nonisolated(unsafe)`. The
  scroll inverter's callback takes `nonisolated` on its own line, since the
  test generator copies it by its declaration line.
- **Multitouch:** middle click's contact frames arrive on the multitouch
  framework's thread through a C callback that only has `.shared`. That
  instance and its init are `nonisolated`; the init's session handler,
  called on the main queue, enters the main actor through
  `MainActor.assumeIsolated`, as do the wake observer and the hot-plug
  port, which delivers on the main queue.
- **Not yet, each for its own reason:**
  - `MouseAppExceptions` answers both taps from the pointer thread.
  - `Permissions` is read from plain code in about twenty places, the
    window activator and the preview provider among them.
  - `MicMuteService` is read from the input manager's audio queue.
  - `BrightnessService` keeps a key thread, a work queue and two locks of
    its own, and needs a slice to itself.

Landed (6zm, brightness): `BrightnessService` is `@MainActor`.

- **Four kinds of state:** what the views publish stays on the main actor.
  The function-key thread's tap and its flags sit behind `keyThreadLock`;
  the routes, pending levels and topology behind `stateLock`; the DDC
  pacing, gamma baselines and dimmed set are touched only on the work
  queue. Those three groups are `nonisolated(unsafe)`, each with a comment
  naming its guard, and the methods that run there are `nonisolated`.
- **Static helpers:** the display queries, the system-brightness write and
  the IOKit lookups are `nonisolated`; the work queue and the key thread
  call them.
- **The main run loop:** the media-key tap's source is on the main run
  loop, so its callback enters the main actor through
  `MainActor.assumeIsolated`, as do the screen-parameters and wake
  observers, which deliver on the main queue.
- **Toggling a display:** `finishDisplayToggle` is reached from the main
  thread and from queued lid recovery. It stays `nonisolated` and publishes
  through a `@Sendable` closure that runs on the main thread, directly or
  queued, and enters the main actor there.
- **Generated tests:** four methods the test generator copies by their
  declaration line take `nonisolated` on its own line.
- **Callers:** the command bar's brightness row is `@MainActor`.

Landed (6zn, main-queue callbacks): the macOS build of #2686 listed 62
isolation warnings in 24 files the earlier slices had made `@MainActor`.
Swift 5 mode lets these through as warnings; Swift 6 mode would not.

- **Main-queue observers:** almost all of them are notification observers
  registered with `queue: .main`, whose closures the SDK types as
  `@Sendable`. Their bodies now run through `MainActor.assumeIsolated`,
  with a comment saying the main queue delivers them. That covers 22
  files, from app updates and Auto Quit to the camera preview and the
  window layout, plus four the later slices of this stack made
  `@MainActor` (Finder cut and paste, recent captures, the switcher and
  the volume mixer), found by scanning for the same shape.
- **Animation completion:** the edge-snap preview's fade-out completion,
  which AppKit calls on the main thread, does the same.
- **Off the main thread:** Music launch blocking's replacement callback
  comes back on a background queue and read the setting there. It now hops
  to the main queue before it reads it.
- **Under a lock:** the input-volume write lifetime the input device
  manager's audio queue reads under its lock is `nonisolated(unsafe)`.
- **Already fixed:** the command bar's Shelf row (`keepOnShelf`) was made
  `@MainActor` on #2686 itself.

Landed (6zo, microphone mute): `MicMuteService` is `@MainActor`.

- **The audio queue:** the sweep and the CoreAudio statics it calls are
  `nonisolated`, and so are the two entries the input manager uses from
  its own audio queue: the adjustment lifetime and `withUnmutedInput`.
  The blocked flag and the lifetime behind their lock are
  `nonisolated(unsafe)`.
- **The input manager** takes the service on the main thread before it
  queues a volume write, instead of reading `.shared` from its audio
  queue.
- **Generated tests:** the test generator copies the whole class, and
  strips `package` only at the start of a line, so the two `nonisolated`
  entries carry the modifier on its own line.
- **Reverted:** the two 6o wrappers around the island calls in `finish`.

Landed (6zp, mouse exceptions): `MouseAppExceptions` is `@MainActor`.

- **The pointer thread** asks it from the taps of middle click, the scroll
  inverter, the button shortcuts, navigation and focus-follows-mouse.
  What they call is `nonisolated`: the two questions, the pointer lookup,
  the source-process rebuild and their helpers. The state they read was
  already behind its lock and is now `nonisolated(unsafe)`.
- **`shared` and init are `nonisolated`,** since a tap can be the first to
  ask. Loading splits in two: the sets the taps read are filled before init
  returns, on whatever thread that is, and the published lists follow on
  the main thread, directly or queued. `reload()` still does both at once.
- **Running-app changes** may arrive off the main thread. The rebuild
  publishes its scopes through its existing hop to the main thread, which
  now enters the main actor.
- **Tests:** the pointer contract calls `reload()` from the suite's main
  thread through `MainActor.assumeIsolated`.

Landed (6zq, the rest of the macOS isolation warnings): the macOS build
of #2687 listed the isolation warnings 6zn had not reached, in the app
delegate and four services.

- **The app delegate:** its three main-queue observers and the
  quit-time input-source restore, which the main run loop performs, enter
  the main actor through `MainActor.assumeIsolated`. Its notification
  delegate method is `nonisolated`: it touches nothing of the delegate's,
  and already hops to the main queue for its one piece of work.
- **AppKit completions:** the HUD's fade-out and the island's Mission
  Control fade run their completions through `MainActor.assumeIsolated`,
  and the island's completion parameter is `@MainActor @Sendable`.
- **The switcher's wake observer,** a one-line closure the earlier scan
  missed, enters the main actor the same way.
- **The island window's animation delegate** is a `@preconcurrency`
  conformance: Core Animation calls it on the main thread.
- **Keep Awake's** shared running-apps handler is `@Sendable` and enters
  the main actor itself.
- **Recent captures'** file manager is `nonisolated`, since its queue
  removes files with it.
- **What is left** in that log are `Sendable` captures: values such as
  capture sessions, Bluetooth devices, accessibility elements and
  cancellation tokens captured by queue closures. They are not isolation
  crossings, and they belong to building Services in Swift 6 mode.

Landed (6zr, permissions): `Permissions` is `@MainActor`.

- **Read from other threads:** the window activator, the preview provider
  and the window capture asked `Permissions.shared` for Accessibility or
  Screen Recording from plain code, on whatever thread called them, and
  the capture from an `async` function, and the window enumerator's
  snapshot reads Accessibility from a plain function on the main queue.
  Both grants are now mirrored into two statics behind a lock as they are
  published, and those 14 reads use `Permissions.accessibilityGranted` and
  `screenRecordingGranted`, which any thread may call. Everything else
  still reads the published values.
- **Off the main thread inside it:** the Full Disk Access probe, its list
  of protected folders and the Automation status check run on background
  queues and are `nonisolated`. The activation and defaults observers and
  the polling timer enter the main actor through
  `MainActor.assumeIsolated`.
- **Callers:** five command bar builders that read a grant (toggles,
  snippets, emoji, typing at the cursor, clipboard rows) are `@MainActor`.

Landed (6zs, `Sendable` captures): what the macOS log of #2688 still
listed after the isolation fixes were values captured by closures that
run on another queue. Swift 6 mode rejects most of them.

- **Lock-guarded flags:** the agent reader's cancellation, the cleaner's
  and the uninstaller's scan cancellations and the media tools' token
  keep their flag behind a lock, so each is `@unchecked Sendable`, with a
  comment saying so.
- **The media tools' log:** the conversion's output was a captured `var`
  that the pipe's queue appended to under a lock the compiler could not
  see. It is now a small locked type.
- **Declared `@Sendable`:** the speed test's time box hands its action to
  another queue, and the Super key's mapping work runs on the mapping
  queue; both closure types now say so.
- **Confined:** the notification reader lives on the notification
  service's queue. The two closures that take it there capture it through
  a `nonisolated(unsafe)` local that says so.
- **Not captured:** the clipboard history panel's resize observer finds
  the panel in the notification instead of capturing it.
- **Not `Sendable` after all:** 6zq made recent captures' file manager
  `nonisolated`, but the SDK does not mark `FileManager` `Sendable`, so the
  macOS build warned. It is `nonisolated(unsafe)`, since the default
  manager is safe from any thread.
- **SDK types not yet marked:** capture sessions and devices, Bluetooth
  devices, accessibility elements, Mach ports and dispatch work items are
  imported with `@preconcurrency` (AVFoundation, IOBluetooth,
  ApplicationServices, CoreFoundation, Dispatch), in the five files that
  capture them, as the compiler suggests.

Landed (6zt, transient paste and the clipboard auto-clear): both keep
their state on the main thread and do their pasteboard work on the shared
pasteboard lane, and their lane closures captured `self`, a plain class.
They are `@MainActor`.

- **Transient paste:** snippet expansion asks for it from plain code, and
  it already refused any call off the main thread. `shared`, its init and
  `paste` are `nonisolated`; `paste` keeps that refusal and runs the rest
  on the main actor. The pasteboard snapshot it hands to the lane and back
  goes through `nonisolated(unsafe)` locals that say so, the restore's
  work item, run by the main queue, enters the main actor, and the
  snapshot reader is `nonisolated`.
- **The auto-clear:** its observers and its timer enter the main actor,
  and the configuration generation the lane reads under its lock is
  `nonisolated(unsafe)`.

Landed (6zu, static state, and complete checking for Services): in Swift 6
mode a static that any thread can reach must say what protects it. A
Swift 6 type-check of Services on Linux listed 80 statics that did not.

- **Complete checking on:** `VitruvianServices` builds with
  `-strict-concurrency=complete`, as UI did from 6d. Each build now lists,
  as warnings, what Swift 6 mode would reject (in CI in full since 6zv). The Linux check cannot see
  AppKit's own main-actor annotations, so this macOS list is the real one.
- **Behind a lock:** 22 statics are `nonisolated(unsafe)`, with a comment
  naming the lock that guards them (or, for the sleep-state count, the one
  queue that touches it).
- **Main thread only:** 20 more are `nonisolated(unsafe)` with a comment
  saying so: the activation handoff, the brightness overlay, wheel
  scrolling, the mouse navigation keys, the quick tools' hotkeys, the Space
  hop, the switcher's pending close and restore, the command bar's caches,
  the clipboard's file icon list and the now-playing app icons.
- **Thread-safe already:** five `NSCache`s, five `dlopen` handles that only
  `dlsym` reads, and the recorder's constant audio settings.
- **Main actor:** the activation policy, the view factory registry and the
  media panel's modal flag are `@MainActor`, since everything that uses them
  already is. `main.swift` installs the view factory inside
  `MainActor.assumeIsolated`.
- **Left as they are:** two `ISO8601DateFormatter`s and a list of
  `CGEventType`s, which the Linux stand-ins do not mark `Sendable`. The macOS
  SDK does mark the event types, but not the formatters; 6zw says the
  formatters are read behind their lock.
- **Next:** 20 singletons are `static let shared` of a class that is not
  `Sendable`. Each one is a choice between the main actor and a lock, so
  they are a slice of their own.

Landed (6zv, the main-thread singletons): of the 20 singletons 6zu left,
the ones whose state lives on the main thread are `@MainActor`, and two
that only hold constants or a locked flag say why any thread may use them.

- **Main actor:** the Dock preview's drag ghost, the Shelf tooltip, the QR
  result panel, screenshot pins, Bluetooth sleep, the scroll wheel target,
  mouse acceleration, focus follows mouse, Dock clicks, the radial menu's
  Now Playing card and the disk image installer.
- **Callbacks on the main thread:** their main-queue observers, the focus
  timer, the Dock click tap (a source on the main run loop) and the HID
  device callback (scheduled on the main run loop) enter the main actor
  through `MainActor.assumeIsolated`.
- **Off the main thread, said so:** the disk image installer's mount check
  and install run on its work queue, focus follows mouse asks for the
  window under the pointer on its query queue, and the Dock click sweeps
  read the Accessibility tree on a global queue, so those methods and the
  static helpers they call are `nonisolated`. The scroll wheel target's
  `shared`, init and `contains` are `nonisolated` too: the pointer taps
  ask it, and its cache keeps its own lock.
- **`@unchecked Sendable`:** `SessionActivity` keeps its flag behind a lock
  and adds and runs its handlers on the main thread, and
  `GeneralPasteboardAccess` holds only constants. Tests build both off the
  main actor.
- **`main.swift`** recovers mouse acceleration inside
  `MainActor.assumeIsolated`.
- **The full list in CI:** 6zu's first macOS build wrote about 1.7 MB of
  warnings per Services compile action, down from 6.3 MB in 6c, but Bazel
  prints at most 1 MB of an action's output and skipped them. The
  `vitruvian-desktop-macos` unit now builds with
  `--experimental_ui_max_stdouterr_bytes=-1`, so its log shows them all.
- **Not yet:** the window preview provider's captures run in tasks that a
  main-actor class would move onto the main thread, and six services serve
  event taps or caches from their own threads (Finder rename, click
  debounce, snippets, the window use tracker, process usage, the battery
  capacity probe). They are the next slice.

Landed (6zw, main-actor code reached from plain code): with 6zv printing
Services' full warning list, the macOS build reported 752 concurrency
warnings. 249 of them say the same thing: main-actor AppKit is reached
from code Swift does not know is on the main thread. Almost all of that code
is on the main thread already, so it now says so.

- **Main actor:** the recorder's indicator, the quit protection HUD, the
  brightness overlay, sideways wheel scrolling, the island's frame probe,
  the radial menu's arrival and departure, and the disk image installer's
  destination prompt. So are the functions that read `NSApp` for the main
  thread: `appShell()`, the settings import panel, the uninstaller's final
  quit, the switcher's snapshot of this app's windows and the two window
  lists that take one, and the island's overlay Space join.
- **Hopping in:** the brightness overlay's `show`, `teardown` and `dismiss`
  stay callable from any thread and hop to the main thread first, as they
  did; its state is now plain main-actor statics instead of
  `nonisolated(unsafe)`. Wheel scrolling's state is the same.
- **Main thread, said at the call:** `MainActor.assumeIsolated` with a
  comment where code that is already on the main thread touches AppKit:
  - the window activator's paths for this app's own windows;
  - the activation handoff's `NSApp` calls;
  - the shell helper's direct branch of bringing the app forward;
  - the island's menu-space reader asking whether this app is active;
  - the island's gesture check walking up the view tree, which the tests
    call from plain code;
  - the mouse navigation keys reading the main menu, with the hidden-menu
    probe moved to a main-actor `refreshOnMain`;
  - the command bar opening Settings;
  - the island's display-link tick (the link is on the main run loop);
  - animation completions, which AppKit calls on the main thread, in the
    brightness overlay, the recorder's indicator, the radial menu and the
    lock screen fade. The radial menu and lock screen completions are
    typed `@MainActor @Sendable () -> Void`, so they can cross into those
    handlers (6zx added `@Sendable`: `@MainActor` alone does not make a
    function type `Sendable`).
- **Off the main thread, said so:** the Dock click service's `activate(pid:)`
  and `restore(_:)` run on whatever queue the restore walk is on, as their
  comments already said, so they are `nonisolated`. The walk's `[weak self]`
  moves to the main-queue block that uses it.
- **Statics:** the agent log's two formatters are read behind its lock;
  two constant strings, two constant Bluetooth UUIDs, the pointer
  follower's system environment and the pointer tap's run loop never change.
  All are `nonisolated(unsafe)` with that comment.
- **Not yet:**
  - the seven singletons 6zv left (6zx);
  - two SDK globals the code reads, `kAXTrustedCheckOptionPrompt` and
    `vm_kernel_page_size`;
  - about 490 warnings about values that are not `Sendable` crossing to
    another thread, among them a capture engine handing back
    ScreenCaptureKit windows and the recorder editor's waveform task;
  - about 60 deprecations, which are not concurrency.

Landed (6zx, the last singletons): the seven `static let shared` 6zv left
are reached from more than one thread, so each says what keeps it safe
there. None of them changes behavior.

- **`@unchecked Sendable`, the locks named:** Finder rename, click debounce,
  text snippets, the window use tracker, process usage and the battery
  capacity probe already keep everything their taps, threads and queues
  touch behind a lock. What is left lives on one thread, and each says
  which: the debounce's sleep observers, the snippets' activation observer
  and the tracker's `started` on the main thread, the tracker's observer
  state on its watcher thread.
- **The window preview provider** is `@unchecked Sendable` rather than
  main-actor: its capture and warm tasks do their image work off the main
  thread and reach the cache only through `MainActor.run`, which a
  main-actor class would undo by running those tasks on the main thread.
  Its `onUpdate` is `@MainActor @Sendable`, since it is only called inside
  those `MainActor.run` blocks.
- **Main-actor callbacks that cross threads** are `@MainActor @Sendable`:
  6zw typed the radial menu's and the lock screen's animation completions
  `@MainActor` alone, which does not make a function type `Sendable`, so the
  capture into AppKit's completion handler still warned. The lock screen's
  fade counter is declared with that type, which lets it keep its counter.
- **The snippets' alert sound** is `Sendable`: it holds one sound ID.
- **Not yet:** the remaining warnings are values that are not `Sendable`
  crossing to another thread, two SDK globals, and deprecations (see 6zw).

Measured (6zy, what stands between Services and Swift 6 mode): the
complete-checking warning list overstates it. One build of
`VitruvianServices` in Swift 6 mode (`swift.enable_v6`, continuing after
errors) failed with **46 errors**, where the same code under complete
checking printed 429 concurrency warnings.

- **Why fewer:** most of the 429 are not errors in Swift 6 mode. The
  weak-`self` relay (an outer `@Sendable` block taking `[weak self]` and a
  nested main-queue block using it) warns under complete checking and
  compiles in Swift 6 mode, as a Swift 6.4 type-check confirms; it was 68
  of the warnings. Swift 6 also only warns about the `Sendable` captures of
  SDK types it imports without full annotations.
- **19 errors, one shape:** an event tap's callback returns its `CGEvent`
  out of `MainActor.assumeIsolated`, and `CGEvent` is not `Sendable`. The
  15 files with a main-run-loop tap need the same fix, as 6zs did for
  CoreFoundation with an `@preconcurrency` import.
- **27 errors in 13 files:**
  - callbacks captured by queue blocks without being `Sendable`: transient
    paste, clipboard auto-clear and history, kill process, the URL cleaner,
    the Codex agent server, the Notch music reader and island actions;
  - values sent to another thread: the screen recorder's session and
    service, the camera preview's notification;
  - captured `var`s mutated across threads: Homebrew's output buffers and
    the switcher's pending window queries;
  - the two SDK globals, `kAXTrustedCheckOptionPrompt` and
    `vm_kernel_page_size`.
- **A floor, not a ceiling:** the `sending` checks run only on files that
  type-check, so fixing the errors above can show more of them.
- **Still warnings in Swift 6 mode (212):** 79 deprecations, `Sendable`
  captures of SDK types, and 20 suggested `@preconcurrency` imports.
  None blocks the switch.
- **Order:** the event taps (6zz), then the 27, then Services in Swift 6
  mode, measuring again on the way.
- **Also in this step:** the Dock click service's restore and minimize
  walks take `[weak self]` on both the outer queue block and the inner
  main-queue block. 6zw had moved it to the inner block only, which drew a
  new warning (a weak capture differing from the outer block's implicit
  strong one); weak on both is clean under complete checking and in Swift 6
  mode.

Landed (6zz, the event taps): the 19 errors of one shape from 6zy. An event
tap's callback hands its `CGEvent` back out of `MainActor.assumeIsolated`,
which needs a `Sendable` result, and `CGEvent` is not. The event never
leaves the thread: the tap's source is on the main run loop, so the callback
and the main actor are the same thread.

- **The fix:** the 15 files with a main-run-loop tap import CoreGraphics as
  `@preconcurrency`, the compiler's own suggestion and what 6zs did for
  CoreFoundation. Eleven already imported it; the other four
  (precise volume, auto-quit, brightness and the radial menu) reached it
  through AppKit and now import it directly.
- **Checked by the build:** in Swift 5 mode a `@preconcurrency` import
  silences these warnings, so the macOS log of this step's build lists no
  `CGEvent` `Sendable` warning in Services.
- **Next:** the 27 errors in 13 files, then Services in Swift 6 mode.

Landed (6zza, the 27 errors in 13 files): the rest of 6zy's list.

- **Passed through, never called off the main thread:** transient paste's
  three callbacks, clipboard history's planned write and the island's
  settle action go through as `nonisolated(unsafe)` lets, the idiom those
  files already use for a value handed to the pasteboard lane and back.
- **Callbacks typed for where they run:**
  - `@MainActor @Sendable`: clipboard auto-clear's change-count reader,
    kill process's refresh and kill completions, Homebrew's streamed output;
  - `@Sendable`: Homebrew's command completions, which run on its work
    queue and hop to the main queue themselves (each caller's inner block
    now takes `[weak self]` too, as 6zy found clean in both modes), and the
    switcher's cancellation check.
- **Shared state given a type:** Homebrew's output buffer, the switcher's
  Accessibility batch and the Codex server's inbox each move into a small
  lock-guarded class. The URL cleaner's poll token, the Notch music reader,
  the screen recorder's session and its two samplers say what guards them
  and are `@unchecked Sendable`.
- **One race fixed:** the recorder's capture queue read `writesTapAudio`, a
  plain `Bool` that `start()` could still lower after the stream began. It
  is now settled before the stream runs and withdrawn through an atomic flag.
- **Notifications stay put:** kill process and the camera preview read what
  they need from the notification before `MainActor.assumeIsolated`, so the
  notification never crosses to the main actor.
- **The two SDK globals:** the Accessibility prompt option is spelled as
  its value, `"AXTrustedCheckOptionPrompt"`, and the kernel page size is
  read by the VM statistics C shim, which already reads those statistics.
- **Measured again:** a build of `VitruvianServices` in Swift 6 mode with
  one compiler process per file (batch mode off) shows none of the 27, and
  **99 errors in 50 files**.
- **Why 6zy's 46 was a floor:** batch mode hands each compiler process a
  share of the module's files, and one file that fails to type-check stops
  the `sending` checks for its whole batch. With errors spread over 25
  files, almost no batch got that far.
- **The 99, by shape:**
  - 18 notifications and 3 timers handed into `MainActor.assumeIsolated`,
    the shape fixed here in kill process and the camera preview;
  - 9 reads of non-`Sendable` properties in a main-actor class's `deinit`;
  - 10 `self`s of non-`Sendable` helper classes sent off the main actor,
    and 4 event-tap verdicts;
  - 55 others, mostly completion blocks and values handed to a queue, plus
    ScreenCaptureKit window lists and the recorder's export closures.
- **Next:** the 99, a shape at a time, measuring with batch mode off, then
  Services in Swift 6 mode.

Landed (6zzb, notifications and timers): 20 of the 99. Each observer and
timer block runs on the main thread, but it is typed nonisolated, so handing
its non-`Sendable` `Notification` or `Timer` into `MainActor.assumeIsolated`
reads as a send.

- **Sixteen observers** read what they need before the hop: the app (a
  `Sendable` `NSRunningApplication`), its process ID, the mounted volume's
  URL, the resized panel or the notification's name. The checks on them stay
  inside, unchanged. Auto-quit has three such observers.
- **The music launch blocker** passes the notification itself, which its
  unit test drives directly, so it crosses as a `nonisolated(unsafe)` let.
- **The three timers** (Dock preview visibility, the shelf's auto-hide fade
  and the maximize animation) cross the same way: a timer on the main run
  loop fires on the main thread and nothing else touches it.
- **Left for the Accessibility errors:** the eighteenth `notification` in
  6zza's count is the name auto-quit's Accessibility observer callback
  passes, which goes with the other values that callback sends.
- **Measured** (Swift 6 mode, batch mode off): the 20 are gone and nothing
  new appeared; **79 errors in 39 files** remain.

Landed (6zzc, main-actor `deinit`s): 9 of the 99. A main-actor class's
`deinit` is nonisolated, so it cannot read a non-`Sendable` property: the
timers, observers, XPC connection and display link these six classes tear
down on the way out.

- **The fix:** each such property is `nonisolated(unsafe)`, with a comment
  that `deinit` reads it once nothing else holds the object.
- **Not `isolated deinit`:** Swift 6.2's isolated `deinit` needs the macOS
  15.4 runtime, and the app supports macOS 14.
- **Measured** (Swift 6 mode, batch mode off): the 9 are gone and nothing
  new appeared; **70 errors in 35 files** remain.

Landed (6zzd, event-tap verdicts and `self` sent to the main thread): 14 of
the 99.

- **Four event-tap verdicts** (three in the switcher, one in Finder cut and
  paste): the tap callback set a captured `var` inside
  `DispatchQueue.main.sync`. It now returns the verdict from the `sync` call
  instead, so nothing captured is mutated.
- **Clipboard history's save:** the persist block's nested `finishPersist()`
  captured the block's weak `self` by reference, so each main-queue hop sent
  that shared reference. Both hops now take their own `[weak self]`, which
  6zy found clean in both modes.
- **Seven helper classes say how they are shared** and are
  `@unchecked Sendable`:
  - Command Bar file search: main-thread state, plus the Spotlight query
    under its lock;
  - Command Bar script runner and the Notch timer alarm: main thread only;
  - the recorder's capture engine and cursor catalog: lock-guarded, with
    the rest fixed before use;
  - the switcher's pending window close and minimize restore: main thread
    only, their Accessibility observer included.
- **Not `@MainActor`:** the alarm's unit test drives it from plain code,
  which a main-actor class would refuse.
- **Measured** (Swift 6 mode, batch mode off): the 14 are gone and nothing
  new appeared; **56 errors in 27 files** remain.

Landed (6zze, callbacks handed to a queue): 25 of the 99.

- **Typed for where they run:** `@MainActor @Sendable` for the callbacks
  that only ever run on the main thread:
  - opening a notification, the microphone request, self-uninstall's two
    results;
  - the window maximizer's frame changes, Homebrew's tap retry, the Super
    Key's physical-key read;
  - the sleep restore's `shouldProceed`. Its completion is `@Sendable`,
    since it runs on the restore's own queue.
- **The pasteboard lane:** results are `Sendable` and completions
  `@MainActor`. The deadline's canceller and `didFinish` now live in the
  main-thread delivery object, so only that object, the value and the clock
  check cross the lane.
- **Passed through as `nonisolated(unsafe)` lets:**
  - keep-awake recovery's completion and transient paste's callbacks, both
    made and run on the main thread;
  - the menu-space reader's answer, made by a background read and run only
    on the main thread.
- **The window-capture queue** hands the captured value to the waiting
  caller as `sending`. The value is a `nonisolated(unsafe)` let: Xcode 27
  counts the result as part of the capture operation that made it, so the
  probe still reported it as shared.
- **Kept plain:** keep-awake recovery's completion parameter, because a
  unit-test fixture copies that method into a class off the main actor.
- **Measured** (Swift 6 mode, batch mode off): the 25 are gone and nothing
  new appeared; **31 errors in 15 files** remain.

Landed (6zzf, values sent across threads): 18 of the 99.

- **Read before the hop, so only `Sendable` values cross:**
  - app updates' results, copied out of the variables the sources filled;
  - the brightness route's path key and dimming flag, without its IOKit
    service;
  - the mouse-acceleration callback's service, unwrapped from its context
    pointer.
- **Typed or marked:**
  - the Dock preview's frame repair takes a main-actor `isCurrent`;
  - the media loader's async operation is `sending`, handed to the task
    that runs it. The video asset that operation reads crosses as a
    `nonisolated(unsafe)` let, since the caller waits while the task
    reads it;
  - the switcher's two focus-retry states (one in Core), and the shelf's
    file-promise transfer, say what keeps them safe and are
    `@unchecked Sendable`.
- **Accessibility references handed across** as `nonisolated(unsafe)` lets,
  each with a comment saying where it goes:
  - the Dock click walks' window lists;
  - the Command Bar's menu item;
  - auto-quit's observer callback arguments.
- **Other hand-offs:**
  - the mixer's pending output write, which its unit-test fixture copies
    into a class off the main actor;
  - the snippet tap's started port, which the main thread only compares.
- **Kept per site, not a conformance:** an `AXUIElement` is an immutable
  reference, but a module-wide `@retroactive @unchecked Sendable` would
  vouch for every use at once; each crossing says what it does instead.
- **Measured** (Swift 6 mode, batch mode off): the 18 are gone and nothing
  new appeared; **13 errors in 3 files** remain.

Landed (6zzg, screen capture and recorder export): the last 13 of the 99.

- **Screenshot exclusions:** finding the app's own windows to leave out ran
  on the main actor, so the shareable-content snapshot was sent there and
  its windows sent back. Now only window IDs cross. The main-actor part
  returns the IDs to exclude, and the snapshot is filtered where the
  capture runs.
- **Recorder export:**
  - the exporter is `Sendable`, since its only state is the lock-guarded
    cancel flag the editor flips;
  - its progress callback is `@Sendable`, and each of the editor's two
    progress closures takes its own `[weak self]`;
  - the writer inputs and reader outputs cross into the task group as
    `nonisolated(unsafe)` lets. Each is drained by one child task alone,
    and the reader and writer are used again only after the group ends.
- **Audio waveforms:** the loaded tracks and the source asset cross into
  the detached task that reads them as `nonisolated(unsafe)` lets. The
  editor keeps only the tracks' keys.
- **Not `sending`:** Xcode 27 treats an `AVAsset` as non-`Sendable`; 6zzf's
  probe rejected a `sending` closure that captured one.
- **Measured** (Swift 6 mode, batch mode off): **no errors remain**. With
  Services in Swift 6 mode the app builds, and its unit tests and self test
  pass.
- **Run-time checks:** the same build gave 1,745 functions Swift 6's
  main-thread check: 716 closures typed `@MainActor`, and 1,029 that take
  the main actor from where they are written. Among the second kind are 17
  event-tap callbacks, and some of those taps run off the main thread.
  Step 6zzh traces them before Services switches.

Landed (6zzh, what would stop the app in Swift 6 mode): 6zzg's probe listed
1,745 functions with Swift 6's main-thread check. A SwiftSyntax tool matched
each one to the call it is passed to, and each was traced to the thread
that runs it.

- **Nine run off the main thread**, so in Swift 6 mode each would stop the
  app:
  - the scroll inverter's and middle click's tap callbacks, which run on
    the pointer thread;
  - the block that ends each of five tap threads (the switcher, Finder cut
    and paste, the Super Key, keyboard debounce and the brightness keys),
    which runs on that thread;
  - the lock-screen sound's completion, on a thread of the system's choosing;
  - the fan control helper's XPC error handler, on XPC's own queue.
- **The fix:** each is now written outside the main actor. The tap callbacks
  are `nonisolated` static lets, the five stops share
  `TapThreadRunLoop.stop(_:)`, and the sound and the error handler are made
  in `nonisolated` static functions.
- **Safe as they are:** everything else either runs synchronously
  (collection algorithms, `withLock`, SwiftUI builders) or runs on the main
  thread. That covers main-queue blocks and work items, `assumeIsolated`,
  AppKit's event monitors, animations and sheets, and dispatch sources and
  IOKit ports set to the main queue. The CoreAudio and HID callbacks were
  listed only for the main-queue blocks inside them.
- **Measured** (Swift 6 mode): no errors, and 1,736 checked functions,
  exactly the nine fewer. The other differences are only renumbering: the
  closures after a removed tap callback in the same `start()` count from one
  lower. The unit tests and self test pass.

Landed (6zzi, Services in Swift 6 mode): `VitruvianServices` builds in the
Swift 6 language mode (`features = ["swift.enable_v6"]`), as Core, Design and
UI already do. A concurrency mistake in Services is now an error, not a
warning.

- **No more `-strict-concurrency=complete`:** Swift 6 mode implies it.
- **The run-time check:** main-actor closures in Services now check for the
  main thread when they start. 6zzh traced all 1,745 of them, and moved the
  nine that run elsewhere out of the main actor. A new callback that runs off
  the main thread needs the same: write it outside the main actor.
- **Still in Swift 5 mode:** the app target (`VitruvianLib`),
  `FanControlKit`, the fan control helper, the Now Playing helper and the
  tests.

Landed (6zzj, the app target in Swift 6 mode): `VitruvianLib` builds in the
Swift 6 language mode too, so every module of the app but `FanControlKit`
does (6zzk moves it).

- **Measured:** a probe built it in Swift 6 mode and found 6 errors in 2
  files. Each is fixed the way Services fixed the same error:
  - two notification handlers in `AppDelegate` read the notification on the
    main actor, so each now reads what it needs first;
  - `StatusItemController`'s `deinit` reads four properties, which are now
    `nonisolated(unsafe)`.
- **The run-time check:** with the fixes, 70 closures check for the main
  thread when they start. All 70 run there, so none moved:
  - 28 blocks on the main queue;
  - 12 Combine sinks received on the main queue;
  - 11 `MainActor.assumeIsolated` bodies;
  - 3 event monitors;
  - 16 closures that a call runs before it returns, such as `filter` or
    `first(where:)`.
- **Still in Swift 5 mode:** `FanControlKit`, the fan control helper, the
  Now Playing helper and the tests.

Landed (6zzk, `FanControlKit` and the fan helper in Swift 6 mode): both build
in the Swift 6 language mode. `FanControlKit` holds the fan-control policy
the app reaches through `VitruvianCore` and the fan helper links. The lists
in 6zzi and 6zzj had left it out.

- **Measured:** a probe built both in Swift 6 mode and found no errors.
  - The fan helper has 18 warnings, each a closure it sends to its own serial
    queue that captures the controller or an XPC reply. The controller's state
    lives on that queue.
  - `FanControlKit` has one deprecation warning.
- **The run-time check:** two closures check for the main thread when they
  start: the helper's `SIGTERM` and `SIGINT` handlers. Their dispatch sources
  run on the main queue.
- **Still in Swift 5 mode:** the Now Playing helper and the tests.
  - A first probe also built the Now Playing helper and found 20 errors, all
    in its three adapter files. Each is global or static state that does not say
    what guards it: a lock, a serial queue, or the watch process alone.

Landed (6zzl, the Now Playing helper in Swift 6 mode): it builds in the Swift
6 language mode, so the app, its modules and both helpers all do now.

- **The 20 errors:** each property is `nonisolated(unsafe)`, grouped with
  the guard it already had:
  - `lock` for the six that track the chosen player;
  - the serial `work` queue for the four that track a queue request;
  - `lifetimeLock` for the four that more than one queue reads;
  - the watch process for three: it sets `watching` and `readAt` before its
    first read, and its reads, which keep `previousArtwork`, run one at a
    time;
  - set once, then only read, for the two MediaRemote handles and
    `includeOtherPlayers`.
- **Two more errors** showed once those were gone: `pending` and
  `commandFramer`, locals of the watch that only the main queue touches. They
  are `nonisolated(unsafe)` too, and `refresh()`, which uses `pending`, is
  `@Sendable`.
- **The run-time check:** two closures check for the main thread when they
  start. Both are blocks the watch queues on the main queue.
- **Still in Swift 5 mode:** the tests, and `make_icon`, the build tool that
  draws the app icon. The lists in earlier steps left `make_icon` out.

Landed (6zzm, the tests in Swift 6 mode): `unit_tests_bin` builds in the Swift
6 language mode, with the main actor as the module's default isolation.

- **Measured:** a first probe found 457 errors. 420 were statics in stand-ins
  and test types that did not say what guards them; the rest were callbacks
  the runner runs on the main thread.
- **Why the main actor by default:** the runner runs every suite on the main
  thread, and the production services the stand-ins copy are main-actor.
  `-default-isolation MainActor` states both, in place of 420
  `nonisolated(unsafe)` annotations.
- **What runs elsewhere says `nonisolated`:**
  - `TestSuite`, whose lock guards the counts;
  - the URL protocols, a file manager and a file-promise receiver, which the
    system calls on its own threads;
  - the stand-ins for Dispatch, the HAL and defaults, which production reaches
    from nonisolated helpers, as it reaches the real APIs;
  - lock-guarded clocks, collectors and schedulers that production calls on
    its own queues;
  - the writer, export and window-capture tests, whose work runs in detached
    tasks while the main thread waits.
- **Compiler rules it hit,** each checked with the Linux toolchain:
  - a base class's implicit `init()` is nonisolated while its subclass's is
    main-actor, so 28 stand-in base classes declare `init() {}`;
  - members of an `extension` do not take `nonisolated` from the type;
  - a type named `DispatchQueue` gets Dispatch's `@Sendable` inference for
    `async`.
- **The run-time check:** four suites failed the main-thread check on another
  thread. Each fix makes the compiler catch the case instead:
  - `GeneralPasteboardAccess` and `MouseAppExceptions` held an injected clock
    as a plain or `nonisolated(unsafe)` closure but call it on their own
    queues. It is `@Sendable` now, and so are `SpeedTest`'s clock and time-box
    scheduler, the same case before it ran;
  - the repository source reader is nonisolated, and so, before they ran, are
    the download-progress results and the archive outcome;
  - `generate_sources.py` dropped a `nonisolated` written on the line above a
    copied declaration, so the app-updates batch loop became main-actor and
    its queue closures failed. A copy keeps it with `keep_nonisolated=True`.
    The copies the tests run on the main thread leave it off, as their
    stand-ins keep main-actor state.
- **Still in Swift 5 mode:** only `make_icon`.

Landed (6zzn, `make_icon` in Swift 6 mode): the build tool that draws the app
icon builds in the Swift 6 language mode, so every Swift target in the app does
now.

- **Why the main actor by default:** `Tools/MakeIcon.swift` is a script of
  top-level code, which runs on the main thread. In Swift 6 its top-level
  variables are main-actor and its top-level functions are not, so
  `drawMark` and the renderers could not read the images they draw.
  `-default-isolation MainActor` puts the functions with the variables, as in
  the tests, and the script compiles unchanged. A model of the script, built
  with the Linux toolchain, shows the error without the default and none with
  it.

## Step 7: test-suite hygiene

- Run `Tests/mutation_checks.py` in CI (nightly or `manual`), so weak tests are
  caught.
- Replace the roughly 440 source-substring assertions with behavioral ones as the
  code they guard moves (steps 3 to 5).
- Move to Swift Testing once tests link modules instead of extracted text.

Landed (7a, the mutation checks run again): `Tests/mutation_checks.py` had
stopped working when `build.sh` stopped building the app.

- **Through Bazel:** it plants each regression in the checkout, runs that
  suite with `bazel test`, and requires a failure carrying the expected
  diagnostic. A build error, a timeout or a different failure still does not
  count. Each file goes back afterwards, also when the run is stopped, and the
  run refuses to start while a file it mutates has uncommitted changes, so
  `git checkout` can always restore it.
- **Where it runs:** `bazel run --config=macos-app
  //apps/desktop/vitruvian:mutation_checks`, and weekly in
  `.github/workflows/vitruvian-mutation-checks.yaml` on the macOS runner.
  Each of the 56 mutations rebuilds a module and reruns a suite, so no PR
  waits on it. A red run files or refreshes one tracking issue.
- **Fixtures:** all 56 still apply. One needed `package func toggle()`.

## Not in scope

Product decisions remain open:

- own temporary-link and feedback backends;
- community channels;
- versioning;
- the release pipeline.

`UPSTREAM.md` lists them as release blockers.
