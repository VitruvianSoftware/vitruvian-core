# Upstream provenance

This directory is a fork of **vorssaint-utils**, a macOS menu-bar utility app.

| | |
| --- | --- |
| Upstream | <https://github.com/vorssaint/vorssaint-utils> |
| Imported commit | `aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958` (2026-10-02, "chore(agents): update AI price list") |
| Upstream version at import | 3.4.1-beta.1 (build 96) |
| Imported on | 2026-10-02 |
| License | GPL-3.0-or-later (see [`LICENSE`](LICENSE)) |

## Licensing: this directory is GPL, not Apache

The monorepo is Apache-2.0, but **everything under `apps/desktop/vitruvian/` is
GPL-3.0-or-later**, including the files added here (BUILD, `bazel/`, docs). The
upstream project has many contributors, so it cannot be relicensed.

What that means in practice:

- Keep every upstream `SPDX-License-Identifier` / `Copyright (C) 2026 Vorssaint`
  header exactly as it is. New files in this directory carry
  `GPL-3.0-or-later` with a VitruvianSoftware copyright line.
- Code from this directory must not be copied into Apache-licensed parts of the
  monorepo, and Apache-licensed targets must not link against it. The `BUILD`
  file keeps every target private for that reason.
- Distributing a build, including to testers, obliges us to offer the complete
  corresponding source under the GPL. A Copybara export of this directory to a
  public mirror is the natural way to do that, and the mirror has to be in place
  before the first build goes out.

## Trademarks and release blockers

Upstream's [`TRADEMARKS.md`](TRADEMARKS.md) reserves the Vorssaint name, logo,
icon, bundle identity, signing identity and update feed for upstream. The rename
(2026-10-02) replaced them:

- **Name:** Vitruvian everywhere the app shows or reads it. Upstream's
  copyright lines stay, because they are legal notices, not branding (GPL-3.0 §5).
- **Bundle IDs:** `com.vitruviansoftware.vitruvian`, plus its fan helper and Now
  Playing adapter IDs.
- **Icon:** Vitruvian's own app icon and menu bar mark (VitruvianSoftware/vitruvian-core#2643),
  which replaced the placeholders the import used.
- **Update feed and price list:** the planned public mirror
  `VitruvianSoftware/vitruvian`. It does not exist yet, so update checks find
  nothing and prices fall back to the bundled list.
- **Temporary links and feedback:** these were upstream's own servers. They now
  target reserved `.invalid` hosts (RFC 6761) and fail closed, so no capture or
  report leaves the Mac.
- **Donation, Discord and X:** `AppInfo.hasCommunityChannels` is `false`. That
  hides the Support settings page and upstream's post-update support prompt, and
  the remaining links point at the repository.
- **Upstream migrations removed:** the fork must never act on an upstream
  install. `BundleMigration` (it renamed or removed old Vorssaint bundles) is
  deleted, and `build.sh` and `Tools/uninstall.sh` no longer touch legacy
  upstream app paths. The Cleaner also protects upstream's data namespaces.

**Still blocking a first release:**

- The public mirror `VitruvianSoftware/vitruvian`. The GPL requires offering the
  source with every build, and the update feed points there.
- Re-record `Resources/Gifs/*.gif` from the renamed app: they still show
  upstream's planet mark.
- A Developer ID signing identity and the release pipeline.
- A decision on whether to run our own temporary-link and feedback backends, or
  remove those features and their dead UI in the refactor.
- `CHANGELOG.md` is upstream's history, shown in-app under Release notes. Start
  Vitruvian's own changelog at its first version.

## What the import left out

The import is the upstream tree at the commit above. Every file kept is byte for
byte identical to upstream except `.gitignore` (listed below). Left out:

- `Resources/Brand/`: upstream's logo, app icon and Icon Composer project.
  Upstream reserves this artwork as brand material and does not license it
  under the GPL (its SVG says so in its metadata, and see `TRADEMARKS.md`), so we
  have no licence to copy it. In its place, `Resources/Brand/` holds original
  placeholder artwork with the same file names, drawn by
  `Resources/Brand/make_placeholder_brand.py`. Vitruvian's own artwork has since
  replaced `AppIcon-Default.png` and `logo.png`
  (VitruvianSoftware/vitruvian-core#2643). Do not rerun the script: it would
  overwrite them.
- `.github/`: upstream CI, release and issue workflows. The monorepo pipeline
  replaces them.
- `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `SUPPORT.md` and
  `docs/AI-CONTRIBUTIONS.md`: upstream's own contact points and processes.
  `README.md` and `AGENTS.md` here replace them.
- `docs/assets/`, `docs/demo.gif` and `ReleaseAssets/`: marketing screenshots
  and videos (about 45 MB) that are not used by the build or the tests.

## Modifications

GPL-3.0 §5(a) requires a notice that the work was modified, with a date. This log
is that notice. Add an entry for every change to upstream files.

- **2026-10-02**: Imported. Added `BUILD`, `bazel/`, `UPSTREAM.md`,
  `README.md` and `AGENTS.md`. In `.gitignore`, dropped the `AGENTS.md` entry so
  the nested agent guide can be committed. Replaced the reserved brand artwork
  in `Resources/Brand/` with generated placeholders.
- **2026-10-02**: Renamed to Vitruvian (see "Trademarks and release blockers"):
  - names, bundle IDs, module and source paths (`Sources/Vorssaint` became
    `Sources/Vitruvian`), keys and namespaces;
  - upstream servers, feeds and community links replaced or disabled;
  - `BundleMigration.swift` deleted, and the legacy-app cleanup in `build.sh` and
    `Tools/uninstall.sh` dropped;
  - tests that pinned upstream's links and support prompt updated.

  Copyright notices, `LICENSE`, `TRADEMARKS.md` and `CHANGELOG.md` are unchanged.
- **2026-10-02**: Refactor step 1 (`REFACTOR.md`):
  - `FeatureRuntime`'s bindings dictionary became an exhaustive switch, adding
    the missing `connectedDevices` binding;
  - `AppDelegate`'s permission re-sync lists now come from
    `AppFeature.dependents(on:)`;
  - tests updated.
- **2026-10-03**: Refactor step 2 (`REFACTOR.md`):
  - `DockAutohideHold.recoverIfNeeded()` runs at launch from `AppDelegate`;
  - `applicationWillTerminate` documents the calls that must stay
    unconditional;
  - `DockAutohideHoldTests` extended.
- **2026-10-03**: Refactor step 3, first module (`REFACTOR.md`):
  - `Core/` builds as the `VitruvianCore` module, and its declarations are
    `package`;
  - `DefaultsKey` moved out of `Core/Defaults.swift`;
  - `KeepAwakeAutomationSupport.swift` and `ScratchpadSupport.swift` moved to
    `Core/`;
  - app and test files import `VitruvianCore`;
  - `build.sh` lists the moved files;
  - `Tests/generate_sources.py` tolerates `package`;
  - `RepositoryFeatureTests` French check hardened.
- **2026-10-03**: Refactor step 3.1b (`REFACTOR.md`):
  - 50 `*Support` and model files moved from `Services/` to `Core/` (same
    subfolders), and `FanControlSupport.swift` and
    `TemperatureSensorSelector.swift` to `FanControlKit/`;
  - `AirPlayRouteManager.airPlaySentinelUID` now aliases
    `MixerRoutingSupport.airPlaySentinelUID`;
  - explicit `package` initializers added to the structs and classes the
    module exports;
  - `import FanControlKit` added to `Sources/FanControlHelper/main.swift`
    and the three files the helper shares with the app;
  - `build.sh`, `Tests/mutation_checks.py` and four test files point at the
    new paths.
- **2026-10-03**: Refactor step 3.1c (`REFACTOR.md`):
  - the `NSScreen.displayID` extension moved from
    `Services/QuickTools/ScreenshotCaptureEngine.swift` into
    `Core/AppKitExtensions.swift`, whose members are now `package`;
  - `Permissions.swift` and `SecureInputMonitor.swift` moved from `Core/` to
    `Services/`.
- **2026-10-03**: Refactor step 3.2a (`REFACTOR.md`):
  - `App/FeatureRuntime.swift` and `App/AppAppearanceController.swift` moved
    to `Services/`, and `App/MenuBarRenderer.swift` to `Services/MenuBar/`;
  - `App/MenuBarSpacingSupport.swift`, `App/MenuBarAllowanceSupport.swift` and
    `App/StatusItemAnchorSupport.swift` moved to `Core/MenuBar/`, and
    `App/ReopenRequestSupport.swift` to `Core/`: their declarations are now
    `package`, without the self-import, and `MenuBarUsageBarSupport.RGB` and
    `ReopenRequestSupport.Sender` spell out their memberwise initializers;
  - `BlackHoleGlyph` moved from `App/StatusItemController.swift` into the new
    `UI/BlackHoleGlyph.swift`. Its one-time read of the bundled PNGs moved from
    a closure into `loadBase()`, so the repository check against file reads in
    view code, which covers `UI/` only, sees that the read happens in a
    function;
  - `build.sh`, `Tests/generate_sources.py` and three test files point at the
    new paths, and a comment in `Tools/MakeIcon.swift` names the glyph's new
    file.
- **2026-10-03**: Refactor step 3.2b (`REFACTOR.md`):
  - `UI/Settings/FeatureVisibilitySupport.swift`, `SettingsSearchSupport.swift`
    and `SettingsSidebarSupport.swift` moved to `Core/Settings/`. Their
    declarations are now `package`, without the self-import, and seven structs
    spell out their memberwise initializers.
  - `UI/Settings/SettingsDirectory.swift` moved to `Services/Settings/`.
  - `PermissionKind` moved from `UI/Settings/SettingsView.swift` into the new
    `Core/PermissionKind.swift`, now `package`.
  - `appDelegate()` was removed from `UI/Theme.swift`. Its calls, and every
    `NSApp.delegate as? AppDelegate` under `Services/` and `UI/`, now call
    `appShell()` (20 files).
  - `Services/Permissions.swift` shows the permission guide through it.
  - `SettingsWindow` conforms to `SettingsHistoryNavigating`. Its
    `navigationItem(for:in:)` now calls `MouseNavigationKeys.settingsItem`,
    which holds the menu lookup and finds the items by the protocol's
    selectors.
  - `StatusItemController.MetricStatusGroup` and `metricStatusGroups(for:strings:)`
    moved into `Services/MenuBar/MenuBarRenderer.swift`, and
    `UI/MenuBarMetricsPreview.swift` reads them there.
  - Five test contracts stub `appShell()` instead of the app delegate.
  - `build.sh` and `Tests/RecorderFeatureTests.swift` point at the new paths.
- **2026-10-03**: Refactor step 3.2c-1 (`REFACTOR.md`):
  - `UI/OverlayPanel.swift`, `UI/NonModalAlert.swift`, `UI/PlainTextEditor.swift`
    and `UI/MenuPanel/MixerPercentNativeTextField.swift` moved to the new
    `Design/`.
  - `HUDBackdrop` moved from `UI/SharedUI.swift` into `Design/HUDBackdrop.swift`.
  - `Theme` moved from `UI/Theme.swift` into `Design/SpaceGradient.swift`.
    The doc line it carried, which describes the whole file, stays in
    `Theme.swift` as a plain comment.
  - `UI/MenuPanel/PanelInteractionState.swift` moved to `Services/`.
  - `BackdropEditing` moved from `UI/Screenshot/ScreenshotBackdropPopover.swift`
    into `Services/QuickTools/BackdropEditing.swift`.
  - `BreakdownKind` moved from `UI/MenuPanel/SystemSection.swift` into
    `Services/SystemMonitor/BreakdownKind.swift`.
  - `build.sh` and `Tests/generate_sources.py` point at the new paths.
- **2026-10-03**: Refactor step 3.2c-2 (`REFACTOR.md`):
  - 17 service sites that built a SwiftUI view now ask
    `ServiceViews.factory`:
    - `AppSwitcher`, `SnippetLibraryService`, `ShelfService` (two),
      `ScreenshotEditorController`, `ScratchpadService`,
      `RecorderEditorController`, `RecentCaptureService`, `RadialMenuService`,
      `QuickLauncherService`, `DockPreviewService` (two), `FinderCutPaste`,
      `CommandBarService`, `ClipboardHistoryService`, `CleaningModeManager`
      and `CameraPreviewService`;
    - `CleaningModeManager`'s hosting view is now `NSHostingView<AnyView>`.
  - `main.swift` installs the factory after `Defaults.register()`.
  - `UI/QuitProtection/QuitProtectionHUD.swift` and
    `UI/Shelf/ShelfTooltipPopover.swift` moved to `Services/`.
  - `RecorderZoomLane.Kind` and `.Item` moved into
    `Services/Recorder/RecorderLane.swift` as `RecorderLaneKind` and
    `RecorderLaneItem`, and the view keeps typealiases.
  - `PanelOrderItem`, `PanelSectionID` and `PanelLayout` moved from
    `UI/MenuPanel/PanelLayout.swift` into
    `Services/MenuPanel/PanelLayoutStore.swift`.
  - `Tests/generate_sources.py` and three test files point at the new paths.
- **2026-10-03**: Refactor step 3.2d (`REFACTOR.md`):
  - Moved to `Services/`, unchanged except where noted:
    - `NotchLockScreenModel`, from `UI/Notch/NotchLockScreenView.swift`;
    - `MenuPanelFocus`, `MenuPanelFocusRequest` and `MenuPanelFocusTarget`,
      from `UI/MenuPanel/MenuPanelView.swift`;
    - `MetricDetailKind`, from `UI/MenuPanel/MetricDetailView.swift`;
    - `NotchCompactMusicSnapshot`, from `UI/Notch/NotchMusicStrip.swift`;
    - `NotchQuickAccessMotion`, from `UI/Notch/NotchQuickAccessView.swift`;
    - `NotchBackdropPresentation`, from `UI/Notch/NotchComponents.swift`. Its
      `contourBottom` is now internal, because the view left in that file
      reads it.
  - Moved to `Design/`:
    - `NotchShape`, from `UI/Notch/NotchView.swift`;
    - `NotchButtonStyle`, from `UI/Notch/NotchComponents.swift`;
    - `ShelfSharePickerAnchor`, from `UI/Shelf/ShelfView.swift`;
    - `UI/Shelf/ShelfSharePresenter.swift`.
  - `MediaWorkspaceView.panelModalActive` and `runPanelModal` moved into
    `Services/Media/MediaPanelModal.swift`, now callable by the view, and the
    view and `NotchService` call them there.
  - `NotchService` and `NotchLockScreenService` build their seven views
    through `ServiceViews.factory`.
  - `Tests/generate_sources.py` reads the moved declarations from their new
    files.
- **2026-10-03**: Refactor step 3.2e-1 (`REFACTOR.md`):
  - The files under `Design/` became the `VitruvianDesign` module. Their
    declarations are now `package`.
  - `HUDBackdrop`, `NotchButtonStyle`, `NotchShape` and
    `ShelfSharePickerAnchor` (and its `Anchor`) spell out their initializers.
  - `OverlayPanel` is `open` and its override `public`, so services can
    subclass it from their module. `Tests/generate_sources.py` no longer
    copies it into the test binary, and `OverlayPanelTests` says so.
  - Every app and test file that imports `VitruvianCore` also imports
    `VitruvianDesign`.
- **2026-10-03**: Refactor step 3.2e-2 (`REFACTOR.md`):
  - The files under `Services/` became the `VitruvianServices` module. Their
    declarations are now `package`; 149 structs spell out their memberwise
    initializer, and 32 structs and classes `package init() {}`.
  - `NotchMusicAutomationCapabilities.Event` and `.Position` declare their
    second property `package` too, and `Event` moved onto several lines to
    spell out its initializer.
  - `AppFeature.hubTitle`/`hubDescription` moved from
    `UI/Settings/FeatureHubSettings.swift` to the new
    `Services/Settings/FeatureHubText.swift`; `MenuBarMetric.detailKind` from
    `UI/MenuPanel/MetricDetailView.swift` to `MetricDetailKind.swift`;
    `Notification.Name.menuPanelWillShow` from `UI/MenuPanel/MenuPanelView.swift`
    to `MenuPanelFocus.swift`; `NotchModule.title` from `UI/Notch/NotchView.swift`
    to `Core/Notch/NotchSupport.swift`; `View.screenshotSafeHelp` from
    `UI/Screenshot/ScreenshotEditorView.swift` to the new
    `Design/ScreenshotSafeHelp.swift`.
  - Every `UI/`, `App/`, `Support/` and test file imports `VitruvianServices`.
  - `Tests/generate_sources.py` reads production sources without their
    `package` modifiers, drops the `NotchModule.title` and
    `NotchActivationButton` copies, and reads `detailKind` from its new file.
  - Six source-text checks that split a file at `    func name` now split
    at `    package func name` (`RepositoryFeatureTests`,
    `ScreenshotFeatureTests`, `ShelfFeatureTests`, `UtilitiesFeatureTests`).
- **2026-10-03**: Refactor step 3.2e-3 (`REFACTOR.md`):
  - The files under `UI/` became the `VitruvianUI` module. Their declarations
    are now `package`; `SettingsWindow` is `open` with `public` overrides, and
    the views the app, the probes and the tests build spell out their
    initializers.
  - Every `App/`, `Support/`, `main.swift` and test file imports
    `VitruvianUI`.
- **2026-10-03**: Refactor step 4a (`REFACTOR.md`):
  - `NotchService` calls the Shelf, the brightness keys and the precise volume
    roller through `NotchService.collaborators` (the new
    `Services/Notch/NotchCollaborators.swift`), which `main.swift` wires.
  - `Tests/generate_sources.py` gives the file-drop, fullscreen and
    destination contracts their own `collaborators` stand-ins.
- **2026-10-03**: Refactor step 5a (`REFACTOR.md`):
  - The session observers moved from `NotchService.installObservers()` into
    the new `Services/Notch/NotchSessionTracker.swift`; `NotchService` starts
    and stops the tracker and applies its changes as before.
  - New test: `Tests/NotchSessionTrackerTests.swift`, run in the notch suite.
- **2026-10-03**: Refactor step 5b (`REFACTOR.md`):
  - The menu-space timer, read queue and staleness checks moved from
    `NotchService` into the new `Services/Notch/NotchMenuSpaceReader.swift`;
    `NotchService` starts, stops and invalidates the reader and applies its
    answers as before.
  - `Tests/generate_sources.py` no longer copies `stopMenuSpaceMonitoring()`,
    which is gone, and `Tests/NotchScreenRefreshTests.swift` stands in for
    the reader instead of a timer. Its check that the menu bar's owner is
    measured reads the reader's file.
  - New test: `Tests/NotchMenuSpaceReaderTests.swift`, run in the notch suite.
- **2026-10-03**: Refactor step 5c (`REFACTOR.md`):
  - The copies of the island on other displays moved from `NotchService`
    into the new `Services/Notch/NotchMirrors.swift`: `syncMirrors()`,
    `mirrorSurface`, `mirrorSideRoom`, `makeMirror`, `closeMirrors()` and
    `updateFullscreenDisplays()`. `NotchService` keeps one-line forwards
    under the old names and `bringIsland(to:)`.
  - `Tests/NotchMirrorTests.swift` drives `NotchMirrors` itself, and
    `Tests/generate_sources.py` copies only `bringIsland(to:)` for it.
  - `Tests/mutation_checks.py` gains two mutations of `NotchMirrors`.
- **2026-10-03**: Refactor step 5d (`REFACTOR.md`):
  - The menu-bar click monitors and their press, drag and release rules
    moved from `NotchService` into the new
    `Services/Notch/NotchScreenEdgeClicks.swift`. `NotchService` keeps
    `screenEdgeClickArea`, a new `screenEdgePressed()` with the hover reset
    the press made, and one-line forwards under the old names.
  - `Tests/NotchScreenEdgeClickTests.swift` drives the new type, and
    `Tests/generate_sources.py` copies `screenEdgeClickArea` and
    `screenEdgePressed()` for it.
  - `Tests/mutation_checks.py` gains two mutations of the new type.
- **2026-10-03**: Refactor step 5e (`REFACTOR.md`):
  - Following the pointer to another display moved from `NotchService`
    into the new `Services/Notch/NotchPointerFollower.swift`:
    `syncPointerFollowing()`, `removePointerMonitors()`,
    `schedulePointerFollow()`, `followPointer()` and their state.
    `NotchService` keeps `canFollowPointer`, `move(to:)` and one-line
    forwards under the old names.
  - `Tests/NotchScreenRefreshTests.swift` drives the follower, and
    `Tests/generate_sources.py` copies only `canFollowPointer` and
    `move(to:)` for it.
  - `Tests/mutation_checks.py` gains two mutations of the follower.
- **2026-10-03**: Refactor step 5f (`REFACTOR.md`): the hidden-hover and
  hover-exit monitors in `NotchService` are two `NotchMovementWatch`es (new
  `Services/Notch/NotchMovementWatch.swift`); `NotchService` still decides
  when they run. `Tests/NotchHoverTests.swift` gives its stand-in island the
  same watches, and `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5g (`REFACTOR.md`): the agent strip's marks
  are sized in one place.
  - `Core/Notch/NotchAgentSupport.swift` gains `stripMarkSize(height:working:)`
    (formerly `NotchTimerSupport.stripAgentMarkSize`), `markFrame(size:)`,
    `marksWidth(size:count:)` and `stripMarksWidth(working:in:)`.
  - `NotchService`'s agent-strip wing now shrinks the marks on a short
    island, as `UI/Notch/NotchAgentStrip.swift` draws them; before, it
    reserved full-size marks.
  - `UI/Notch/NotchAgentStrip.swift`, `NotchTimerStrip.swift`,
    `NotchWatchView.swift`, `NotchAgentComponents.swift` and
    `Core/Notch/NotchSupport.swift` call those helpers instead of their own copies.
  - `UI/Notch/NotchAgentsView.swift` lists agents through
    `NotchAgentSupport.providers()`.
  - `Tests/NotchAgentTests.swift` checks the sizes, and
    `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5h (`REFACTOR.md`):
  - File-drop routing moved from `NotchService` into the new
    `Services/Notch/NotchFileDrop.swift`. That covers `beginFileDrop`,
    `updateFileDrop`, `endFileDrop`, `accept(_:)` and the two destinations
    they set.
  - `NotchService` keeps `canAcceptFileDrop` and two new private members,
    `mediaDropArea` and `fileDropLanded()`. Its forwards keep the old names
    and span several lines, so the contract can copy them.
  - `Tests/ShelfDropRoutingTests.swift` and `Tests/generate_sources.py` wire
    the contract's stand-in island to the new type, and the test gains one
    check. `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 5i (`REFACTOR.md`): `NotchService`'s
  capture-controls click-through monitor is a `NotchMovementWatch` that
  watches this app only (`.system(matching:inOtherApps:)`, new). The stand-in
  island in `Tests/NotchPresentationRefreshTests.swift` and
  `Tests/NotchCaptureControlsTests.swift` uses the same watch, and
  `Tests/mutation_checks.py` gains one mutation.
- **2026-10-03**: Refactor step 6b (`REFACTOR.md`):
  - New `Core/Preference.swift`, `Core/Preferences.swift` and
    `Design/PreferenceStorage.swift`.
  - `Core/Defaults.swift` registers five keys from `Preferences`:
    `menuBarMetricSpacing`, `menuBarMetricOrder`, `micMuteMenuBarIndicator`,
    `screenshotPreviewPosition` and `windowLayoutShortcutsEnabled`.
  - Their `@AppStorage` properties in `UI/` take the `Preference`, which
    replaces a default that disagreed with the registered one:
    `MenuBarMetricsPreview`, `PanelWindowLayoutView`, `QuickLauncherView`,
    `MonitorSettings`, `QuickToolsSettings`, `ScreenshotSettings` and
    `WindowLayoutSettings`.
  - New test: `Tests/PreferenceTests.swift`, run in the preferences suite
    (`Tests/MetricsTests.swift`).
  - A second slice moved 358 on/off preferences with literal defaults:
    `Core/Defaults.swift` registers them from `Preferences`, and every
    `@AppStorage` in `UI/` that repeated one of their defaults takes the
    `Preference` instead.
  - A third slice did the same for 141 preferences with a literal number,
    fraction or text default, and a fourth for 63 with a computed default
    that every view repeated.
  - A fifth slice declared the last 139 registered defaults in
    `Core/Preferences.swift`, so `Core/Defaults.swift` registers every one
    from there. 19 `@AppStorage` properties that named their default through
    a constant take the `Preference`: in `MenuBarMetricsPreview`,
    `MenuPanelView`, `MixerSection`, `KeyboardDebounceSettings`,
    `MonitorSettings`, `MouseSettings`, `SwitcherSettings`,
    `TextSnippetsSettings` and `SwitcherView`.
- **2026-10-03**: Refactor step 6a (`REFACTOR.md`): `Core/` and `Design/`
  build in Swift 6 mode. To get there:
  - Shared statics that a lock, the main thread or a test guards, and the
    island's fonts, are `nonisolated(unsafe)`.
  - These are `@preconcurrency @MainActor`: `SettingsRouter`,
    `NonModalAlert`, `ShelfSharePresenter`, `ShelfSharePickerAnchor.Anchor`,
    `PlainTextEditor.Coordinator`, `NotchSupport.hasNotchedDisplay` and
    `hasDisplayWithoutNotch`, and `SwitcherAppIconCache.icon(for:)` with
    `SwitcherItem.appIcon`.
  - `RadialMenuItem` is `Sendable`, and the favicon download is
    `@unchecked Sendable`. `RadialMenuFaviconFetcher.fetchFavicon` calls back
    on the main actor.
  - `StatusItemAnchorSupport.isTrustworthyStatusFrame` takes its screen
    frames, and a main-actor overload supplies the attached ones.
- **2026-10-03**: Refactor step 6c (`REFACTOR.md`): six optional actions
  that chose between `nil` and one of the view's methods now pass a closure
  that calls the method, which the compiler accepts under Swift 6 checking:
  five in `UI/MenuPanel/MenuPanelView.swift` and one in
  `UI/Notch/NotchMixerView.swift`. Behavior is unchanged.
- **2026-10-03**: Refactor step 6d (`REFACTOR.md`): every place in `UI/`
  that complete concurrency checking reported says what isolates it, with
  no change in behavior. Upstream files touched:
  - **Main-actor types:** the coordinators in `MenuPanel/MixerSection.swift`,
    `MenuPanel/PanelHomebrewView.swift`, `Notch/NotchClipboardView.swift`,
    `Notch/NotchLevelSlider.swift`, `Notch/NotchTimerRuler.swift` and
    `Settings/SettingsView.swift`; `NotchMenuAnchor` in
    `Notch/NotchComponents.swift`; `PermissionGuideOverlay.swift`; the
    keyboard context in `Screenshot/ScreenshotToolOrderControls.swift`;
    `AgentMarks` in `Notch/NotchAgentComponents.swift`; and
    `RadialMenuIconStore` with `RadialMenuItem.displayName` in
    `RadialMenu/RadialMenuView.swift`.
  - **Observers:** `CommandBar/CommandBarView.swift`,
    `Notch/NotchAgentAnimationView.swift`, `Notch/NotchEqualizerBars.swift`,
    `ShortcutRecorderButton.swift`, `WindowVisibilityReader.swift`,
    `Notch/NotchComponents.swift` and `Notch/NotchScratchpadView.swift`
    reach the view through `MainActor.assumeIsolated` from main-queue
    observers, and mark what `deinit` removes `nonisolated(unsafe)`.
  - **Statics:** the caches in `CommandBar/CommandBarView.swift` and
    `Screenshot/ScreenshotBackdropPopover.swift`, the menu separator in
    `Notch/NotchComponents.swift`, and the preference keys in
    `MenuPanel/MenuPanelView.swift` and `Settings/SettingsSectionFocus.swift`.
  - **Across queues:** `Cleaner/CleanerView.swift` and
    `Settings/MonitorAlertsControls.swift` read the notification status
    before the hop to the main queue; `Uninstall/AppPickerView.swift` takes a
    `@Sendable` loader, and `Settings/AppBundleList.swift` and
    `Settings/QuitProtectionSettings.swift` hand it plain values, so Quit
    Protection no longer reads its service off the main thread;
    `Media/MediaWorkspaceView.swift` marks the list its lock guards.
  - **Closures:** `MenuPanel/MetricDetailView.swift`,
    `MenuPanel/NetworkSection.swift`, `Notch/NotchSectionsView.swift`,
    `Recorder/RecorderInspector.swift`, `Settings/TextSnippetsSettings.swift`
    and `KillProcess/KillProcessView.swift`; `MenuPanel/ClipboardQuickPanelView.swift`
    compares its row outside the main actor.
- **2026-10-03**: Refactor step 6e (`REFACTOR.md`): `UI/` builds in Swift 6
  mode. `Services/GeneralPasteboardAccess.swift` takes the work it runs on
  its lane as `@Sendable`, and `UI/Settings/NotchCalendarSelection.swift`
  handles EventKit's store-change notification on the main run loop.
- **2026-10-03**: Refactor step 6f (`REFACTOR.md`):
  - These six files are `@MainActor`:
    - `Services/AgentUsage/AgentCodexResetService.swift`
    - `Services/AppAppearanceController.swift`
    - `Services/Metrics/DiskProtectionService.swift`
    - `Services/Metrics/NetworkAddressService.swift`
    - `Services/PortManager/PortManagerService.swift`
    - `Services/Update/UpdateShowcaseMedia.swift` (the loader)
  - Their off-main helpers are `nonisolated`.
  - The showcase loader releases its session on the main thread.
  - `Tests/generate_sources.py` copies the port snapshot under its new
    `nonisolated` prefix.
- **2026-10-03**: Refactor step 7a (`REFACTOR.md`):
  - `Tests/mutation_checks.py` runs the unit tests through Bazel instead of
    `build.sh`, which no longer builds the app. It mutates the checkout in
    place, refuses to start while a file it mutates has uncommitted changes,
    and puts each file back however the run ends.
  - Its `func toggle()` fixture reads `package func toggle()`, as
    `NotchService` has since step 3.2e-2.

## Syncing from upstream

There is no automatic sync. To take a later upstream commit:

1. `git archive` that commit into a scratch directory and drop the paths listed
   above.
2. Diff it against this directory. Port the changes, keeping this repo's own
   modifications.
3. Run `bazel run //apps/desktop/vitruvian:sync_sources` (in case `build.sh`
   changed its source lists), then build and test (see `README.md`).
4. Update the commit and version in the table above, and add an entry under
   Modifications.

Once the refactor diverges from upstream, cherry-picking individual fixes will
be more practical than taking whole commits.
