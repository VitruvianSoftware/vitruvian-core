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
