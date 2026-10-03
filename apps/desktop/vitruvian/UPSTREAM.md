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
- **2026-10-03**: Refactor step 5j (`REFACTOR.md`):
  - New `Core/Notch/NotchNoticeLayout.swift`.
  - `Core/Notch/NotchSupport.swift` gains `NotchGeometry.headerBottom`,
    `pageTop` and `headerSideWidth(contentWidth:)`.
  - These now use them:
    - `NotchService` (the notice's wing and the section scroll's header test);
    - `UI/Notch/NotchNoticeView.swift` and `UI/Notch/NotchView.swift`;
    - `UI/Settings/NotchContentEditor.swift`;
    - `Services/Notch/NotchFileToolsSupport.swift`;
    - `NotchCaptureControlsLayout`.
  - `UI/Notch/NotchCapsuleViews.swift` keeps one padding between the cover
    and the bars of an untitled music strip.
  - `Tests/NotchTests.swift` checks the new geometry.
  - `Tests/mutation_checks.py` gains one mutation, and its "device alerts
    return to the fixed level width" fixture reads the new wing expression.
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
  - `App/AppDelegate.swift`'s `setUpPopover()` is `@MainActor`.
  - `Tests/generate_sources.py` copies the port snapshot under its new
    `nonisolated` prefix.
- **2026-10-03**: Refactor step 6g (`REFACTOR.md`):
  - `Services/FeatureRuntime.swift` is `@MainActor`.
  - `Services/SettingsBackup.swift`'s `applyAndRelaunch` is `@MainActor`.
  - `Services/CommandBar/CommandBarCatalog.swift` (the feature toggles and
    the relaunch row), `Services/ShortcutCapture.swift` and
    `App/AppDelegate.swift`'s `relaunchApp()` reach it through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6h (`REFACTOR.md`):
  - These are `@MainActor`:
    - `Services/Audio/AudioPriorityService.swift`
    - `Services/Audio/MusicLaunchBlocker.swift`
    - `Services/Cleaner/CleanerScheduler.swift`
    - `Services/ManagedDownloads/WhatsAppDownloadScheduler.swift`
    - `Services/Wallpaper/WallpaperService.swift`
  - The schedulers' main-run-loop timers reach them through
    `MainActor.assumeIsolated`.
  - The wallpaper's apply generation and `needsCloudDownload` are
    `nonisolated`.
- **2026-10-03**: Refactor step 6i (`REFACTOR.md`):
  - Now `@MainActor`:
    - `DockPreviewPinnedPanel`
    - `ExtraBrightnessService`
    - `ClipboardIgnoredApps`
    - `HotkeyManager`
    - `CleaningModeManager`
    - `AudioInputDeviceManager`
    - `NotchAudioLevelService`
  - Methods that only main-actor code calls are `@MainActor`:
    - `Services/Update/UpdateService.swift`: `launchInstaller` and
      `launchAdminInstaller`;
    - `Services/Clipboard/ClipboardHistoryService.swift`:
      `syncWithPreferences`, `start`, `stop` and `captureIfChanged`;
    - `Services/DockPreview/DockPreviewService.swift`: `createPinnedPanel`,
      which `togglePinned()` reaches through `MainActor.assumeIsolated`;
    - `Services/SelfUninstall.swift`: `suspendInputInterceptors`;
    - `App/AppDelegate.swift`: `menuCleaningMode`.
  - These reach the newly isolated services through
    `MainActor.assumeIsolated`:
    - `ShortcutCapture.begin()`;
    - the command bar's Cleaning Mode row;
    - `NotchService`'s preference sync and teardown;
    - two main-run-loop timers.
  - The audio input manager's static HAL helpers are `nonisolated`.
- **2026-10-03**: Refactor step 6j (`REFACTOR.md`):
  - `App/AppDelegate.swift`'s `AppDelegate` and
    `Services/MenuPanel/MenuPanelFocus.swift` are `@MainActor`.
  - The per-method isolation added in 6f, 6g and 6i to `AppDelegate` is
    removed.
  - `main.swift` creates the delegate through `MainActor.assumeIsolated`.
  - `NotchService` reaches `MenuPanelFocus` through
    `MainActor.assumeIsolated`.
  - `Services/Wallpaper/WallpaperSupport.swift`'s
    `WallpaperGalleryLifecycle` is `@unchecked Sendable` (lock-guarded), and
    `WallpaperService.galleryLifecycle` is `nonisolated`.
- **2026-10-03**: Refactor step 6k (`REFACTOR.md`):
  - `Services/SecureInputMonitor.swift`,
    `Services/Audio/SoundOutputSwitcher.swift` and
    `Services/QuickTools/PastePlainService.swift` are `@MainActor`.
  - `PastePlainService.plainText(from:)` is `nonisolated`.
  - The secure-input timer, `ShortcutCapture.begin()` and the command bar's
    Paste Plain row reach them through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6l (`REFACTOR.md`):
  - `Services/AppShell.swift`'s `AppShell` is `@MainActor`.
  - `Services/RadialMenu/RadialMenuService.swift`'s `openSettings(at:)` is
    `@MainActor`.
  - These files reach the app shell through `MainActor.assumeIsolated`:
    - `CommandBarService` and `CommandBarCatalog`;
    - `ClipboardHistoryService`;
    - `RecentCaptureService`;
    - `Permissions`;
    - `NotchService`.
- **2026-10-03**: Refactor step 6m (`REFACTOR.md`):
  - `Services/Update/UpdateService.swift`,
    `Services/QuickTools/ColorSamplerService.swift`,
    `Services/Snippets/SnippetLibraryService.swift` and
    `App/StatusItemController.swift` are `@MainActor`.
  - `UpdateService`'s download completion invalidates its session on the
    main thread. `BoundedUpdateDownloadDelegate` takes `@Sendable` callbacks.
  - `UpdateService`'s `volumeIsReadOnly`, `installResultURL` and `isNewer`,
    and `ColorSamplerService`'s `formattedValue` and `copyQuietly`, are
    `nonisolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`'s `afterBeat` takes
    `@MainActor` work.
  - `NotchService.showUpdate()`, `FeedbackDiagnostics.current()`,
    `ScreenCaptureService`, `TextSnippetService` and the command bar's
    snippet rows reach them through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6n (`REFACTOR.md`):
  - `Services/CommandBar/CommandBarService.swift`'s `CommandBarService` is
    `@MainActor`, and `spotlightApplicationPaths()` is `nonisolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`'s `CommandBarEntry.run`
    is a `@MainActor` closure; `open(_:)` and `runScript(_:)` are
    `@MainActor`. Its rows and the bar's Settings calls drop
    `MainActor.assumeIsolated`.
  - The bar's restart observer, `NotchService`'s Command Bar action and
    `TextSnippetService`'s visibility read use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6o (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift`'s `NotchService` is `@MainActor`.
    Its `perform(_:)` takes `@MainActor` work, and
    `fullscreenVisibilityDidChange` is `nonisolated`.
  - These reach the island through `MainActor.assumeIsolated`:
    - `ShelfService`, `BrightnessService`, `BrightnessOSD`,
      `PreciseVolumeRollerService` and `MicMuteService`;
    - `CameraPreviewService`, `QuickLauncherService`, `ScratchpadService`
      and `ClipboardHistoryService`;
    - `ScreenCaptureService`, `ScreenshotService`,
      `ScreenshotQuickPreviewController` and
      `ScreenshotSelectionController`;
    - `NotchTimerService`, `NotchWatchService`, `NotchAccessoryService` and
      `NotchLockScreenService`;
    - `main.swift`.
  - These are `@MainActor`: `ShelfService`'s internal-drag methods,
    `ScratchpadService.exportText`, `MediaPanelModal.runPanelModal`,
    `NotchDownloadService`'s folder chooser and
    `NotchLyricsService.importLyrics`.
- **2026-10-03**: Refactor step 6p (`REFACTOR.md`):
  - In `Services/Notch/`, these are `@MainActor`:
    - `NotchWindowHost`, `NotchQuickAccessMotion` and
      `NotchBackdropPresentation`;
    - `NotchLockScreenService` and `NotchLockScreenModel`;
    - `NotchTimerService`, `NotchWatchService` and `NotchAccessoryService`.
  - `NotchAccessoryService`'s IOBluetooth callbacks and
    `NotchWatchService.scaledForRecognition` are `nonisolated`.
  - `NotchWindowHost.whenSettled` takes `@MainActor` work, and its Mission
    Control timer uses `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6q (`REFACTOR.md`):
  - In `Services/Notch/`, `NotchMusicService`, `NotchLyricsService`,
    `NotchCalendarService` and `NotchFileToolsService` are `@MainActor`.
  - `NotchMusicService.artworkTint(of:)` is `nonisolated`, and the lyrics
    download's completion is `@Sendable`.
  - `NotchCalendarService`'s store observers use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6r (`REFACTOR.md`):
  - `Services/Notch/NotchDownloadService.swift` and
    `Services/Notch/NotchNotificationService.swift` are `@MainActor`.
  - Their file-system source, workspace observers and Accessibility
    observer callback use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6s (`REFACTOR.md`):
  - In `Services/QuickTools/`, `QuickLauncherService`,
    `CameraPreviewService`, `ScratchpadService` and `ScreenTextService` are
    `@MainActor`.
  - `ScreenTextService.outcome`, the recognition it runs, and
    `QuickLauncherService.columns` are `nonisolated`.
  - `Services/SettingsBackup.swift`'s `runExportPanel()` is `@MainActor`.
  - `ScreenCaptureService` hands recognized text to `ScreenTextService`
    through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6t (`REFACTOR.md`):
  - `Services/URLCleanerService.swift`,
    `Services/ManagedDownloads/WhatsAppDownloadManager.swift`,
    `Services/ManagedDownloads/WhatsAppDownloadOrganizer.swift` and
    `Services/Homebrew/HomebrewManager.swift` are `@MainActor`; their
    queue-side statics are `nonisolated`.
  - Their timers and the organizer's folder source use
    `MainActor.assumeIsolated`.
  - `AppUpdatesService.startUpgrade`, `AppUninstaller.isRemovingWithHomebrew`
    and `PanelInteractionState.preventsPopoverDismissal` reach Homebrew
    through `MainActor.assumeIsolated`.
  - `AppUninstaller.removeSelectedWithHomebrew` and `CommandBarCatalog`'s
    `selectionEntries` and `cleanClipboardURL` are `@MainActor`.
- **2026-10-03**: Refactor step 6u (`REFACTOR.md`):
  - In `Services/QuickTools/`, `ScreenCaptureService`,
    `ScreenCaptureSelectionOptions`, `ScreenshotSelectionController`,
    `ScreenshotQuickPreviewController`, `ScreenshotQuickPreviewModel` and
    `ScreenshotService` are `@MainActor`, and so is
    `Services/Media/MediaService.swift`'s `MediaWorkspaceSelection`.
  - `ScreenshotService`'s static helpers are `nonisolated`, and the
    selection's session statics are `nonisolated(unsafe)`. Its
    `steppedLoupeNeedsRawWheel` is `nonisolated` and reads the session
    through `MainActor.assumeIsolated`.
  - The 6m, 6o and 6s `MainActor.assumeIsolated` calls in those files are
    gone.
  - `ScreenshotEditorController.windowWillClose` and
    `ScreenRecorderService.toggle` use `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6v (`REFACTOR.md`):
  - `Services/KeepAwakeManager.swift` is `@MainActor`; its three timers use
    `MainActor.assumeIsolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`'s `build` and
    `actionEntries` are `@MainActor`.
- **2026-10-03**: Refactor step 6w (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotEditorController.swift`: the model and
    controller are `@MainActor`; the text and code scans stop on a
    lock-guarded token instead of reading the model off the main thread; the
    clipboard and file helpers are `nonisolated`; the 6u close wrapper is
    gone.
  - `Services/Recorder/RecorderEditorController.swift`: the model and
    controller are `@MainActor`; the player's time observer uses
    `MainActor.assumeIsolated`.
  - `Services/QuickTools/BackdropEditing.swift` is `@MainActor`.
  - `Services/Recorder/ScreenRecorderService.swift`: the methods that open,
    close and sweep editors are `@MainActor`.
- **2026-10-03**: Refactor step 6x (`REFACTOR.md`):
  - `Services/WindowMaximizer.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/MouseButtons/MouseButtonShortcutService.swift`,
    `Services/RadialMenu/RadialMenuService.swift` and
    `Services/SmoothScrollService.swift` are `@MainActor`. Their tap
    callbacks and main-run-loop timers use `MainActor.assumeIsolated`.
  - Mouse navigation's `registeredWebURLHandlers` is `nonisolated`; the
    radial menu's `postWhenModifiersReleased` takes `@MainActor` work.
- **2026-10-03**: Refactor step 6y (`REFACTOR.md`):
  - `Services/Audio/PreciseVolumeRollerService.swift`,
    `Services/AutoQuit/AutoQuitService.swift` and
    `Services/DockPreview/DockPreviewService.swift` are `@MainActor`. Their
    tap and Accessibility callbacks and main-run-loop timers use
    `MainActor.assumeIsolated`; the volume keys' 6o wrappers are gone.
  - `Services/DockClick/DockClickService.swift` and
    `Services/Switcher/WindowActivator.swift` reach Dock Preview and Auto
    Quit through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6z (`REFACTOR.md`):
  - `Services/WindowLayout/WindowLayoutService.swift`,
    `Services/WindowLayout/WindowLayoutIgnoredApps.swift` and
    `Services/WindowLayout/PointerDisplayService.swift` are `@MainActor`.
    Window Layout's taps and timers use `MainActor.assumeIsolated`; the
    ignored apps' `contains(_:in:)` and `matches` are `nonisolated`.
  - `Services/ShortcutCapture.swift` and `Services/ShortcutRecordingTap.swift`
    are `@MainActor`; the recording tap's callback uses
    `MainActor.assumeIsolated`, and `ShortcutCapture`'s wrappers are gone.
  - `UI/ShortcutRecorderButton.swift`'s `deinit` uses
    `MainActor.assumeIsolated` on the main thread.
- **2026-10-03**: Refactor step 6za (`REFACTOR.md`):
  - `Services/QuickTools/QuickTogglesService.swift` is `@MainActor`; its work
    queue returns results through the main queue, and the helpers it runs
    there are `nonisolated`.
  - `Services/Recorder/ScreenRecorderService.swift`:
    `RecorderSelectionAudioOptions` and `record(_:audioOptions:)` are
    `@MainActor`.
  - `UI/RadialMenu/RadialMenuView.swift`: `RadialMenuQuickToggle.radialTitle`
    is `@MainActor`.
- **2026-10-03**: Refactor step 6zb (`REFACTOR.md`):
  - `Services/Clipboard/ClipboardHistoryService.swift` is `@MainActor`; the
    statics its pasteboard lane and persist queue run are `nonisolated`, and
    its 6l and 6o wrappers are gone.
  - `Services/QuitProtection/QuitProtectionService.swift` is `@MainActor`;
    its tap callback and hold timer use `MainActor.assumeIsolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`: `clipboardEntries` and
    `clipboardBrowseEntries` are `@MainActor`.
  - `Services/Switcher/AppSwitcher.swift` reaches quit protection through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zc (`REFACTOR.md`):
  - `Services/Cleaner/JunkCleaner.swift` and
    `Services/Uninstall/AppUninstaller.swift` are `@MainActor`; their static
    scanners are `nonisolated`, on their own line. The uninstaller's 6t
    changes are reverted.
  - `Services/KillProcess/KillProcessService.swift` is `@MainActor`; its
    statics, batch kill and follow-up are `nonisolated`, and `refresh` is a
    `nonisolated` entry that runs its body (now `refreshOnMain`) on the main
    actor.
  - `Services/PanelInteractionState.swift` is `@MainActor`; its 6t wrapper
    is gone.
- **2026-10-03**: Refactor step 6zd (`REFACTOR.md`):
  - `Services/Shelf/ShelfService.swift` is `@MainActor`; its file sweeps,
    directories and persist queue are `nonisolated`, its timers use
    `MainActor.assumeIsolated`, and the 6o changes are reverted.
  - `Services/AppUpdates/AppUpdatesService.swift` is `@MainActor`; its
    work-queue methods and statics are `nonisolated`, its URL sessions are
    constants instead of lazy properties, the catalog cache is
    `nonisolated(unsafe)`, and the 6t change is reverted.
  - `Services/FanControl/FanControlService.swift` is `@MainActor`; the probe
    hardware is `nonisolated(unsafe)` and the removal statics are
    `nonisolated`.
  - `Services/CommandBar/CommandBarCatalog.swift`: `keepOnShelf`, which hands
    a selection to the Shelf, is `@MainActor`.
- **2026-10-03**: Refactor step 6ze (`REFACTOR.md`):
  - `Services/Finder/FinderCutPaste.swift` is `@MainActor`; its tap thread's
    methods, the progress poller and the move statics are `nonisolated`,
    the tap state its lock guards is `nonisolated(unsafe)`, and the tap
    hands a shortcut to the main thread through `MainActor.assumeIsolated`.
  - `Services/Metrics/SpeedTest.swift` is `@MainActor`; its delegate-queue
    methods and the URL session delegate methods are `nonisolated`, and the
    state that queue owns is `nonisolated(unsafe)`.
  - `Services/AgentUsage/AgentUsageService.swift` is `@MainActor`; its
    reading-queue methods and statics are `nonisolated` (three on their own
    line), the state that queue owns is `nonisolated(unsafe)`, and its tick
    timer uses `MainActor.assumeIsolated`.
  - `Tests/SpeedTestTests.swift` runs its checks on the main actor.
- **2026-10-03**: Refactor step 6zf (`REFACTOR.md`):
  - `Services/KeyboardDebounce/KeyboardDebounceService.swift` is
    `@MainActor`; its tap thread's methods are `nonisolated`, the state its
    two locks guard is `nonisolated(unsafe)`, and its running flag is set
    through `MainActor.assumeIsolated` from a `@Sendable` closure.
  - `Services/SystemMonitor/SystemMonitor.swift` is `@MainActor`; its
    sampling-queue methods and the fan statics are `nonisolated`, the
    sensors, samplers, readings and histories that queue owns are
    `nonisolated(unsafe)`, and its timer uses `MainActor.assumeIsolated`.
  - `Services/SystemMonitor/MonitorAlertService.swift` is `@MainActor`.
  - `Services/Media/MediaService.swift` is `@MainActor`; its init and every
    work method but `run` are `nonisolated`, the operation state its lock
    guards is `nonisolated(unsafe)`, and `run` takes `@Sendable` work.
- **2026-10-03**: Refactor step 6zg (`REFACTOR.md`):
  - `Services/QuickTools/RecentCaptureService.swift` is `@MainActor`; its
    store is a constant made with the service instead of a lazy property,
    its location is found once in init, its queue methods and statics are
    `nonisolated`, the state its queue and lock own is
    `nonisolated(unsafe)`, and the 6l changes are reverted.
  - `Services/QuickTools/QuickToolHUD.swift`: the HUD and its scrolling
    capture model are `@MainActor`; `show` and `showCountdown` are
    `nonisolated` entries that hop to the main thread and run their bodies,
    now `showOnMain` and `showCountdownOnMain`, on the main actor.
- **2026-10-03**: Refactor step 6zh (`REFACTOR.md`):
  - `Services/Switcher/AppSwitcher.swift` is `@MainActor`; its tap thread's
    methods, the focused-window lookup the enumeration queue runs and the
    two lock-only ownership queries are `nonisolated`, the state its two
    locks guard is `nonisolated(unsafe)`, the tap enters the main actor
    inside its existing `main.sync` hops, and the 6zb changes are reverted.
  - `Services/Recorder/ScreenRecorderService.swift`: the service is
    `@MainActor`; its `stop` is a `nonisolated` entry that hops to the main
    thread and runs its body, now `stopOnMain`, on the main actor; the
    session's two callbacks are `@Sendable`; the microphone message is read
    before the session starts; its timer uses `MainActor.assumeIsolated`;
    and the 6u, 6w and 6za method-level changes are reverted.
- **2026-10-03**: Refactor step 6zi (`REFACTOR.md`):
  - `Services/SuperKey/SuperKeyService.swift` is `@MainActor`; its tap
    thread's methods (`runEventTap` on its own line), the mapping queue's
    work, the Caps Lock and key-posting helpers and the solo actions are
    `nonisolated`; the state its two locks and its mapping queue guard is
    `nonisolated(unsafe)`; the mapping's completion is `@MainActor`; and
    `forgetHeldKey` and `runOnMainIfNeeded` hand `@Sendable` work to the
    main thread.
  - `Services/Settings/SettingsDirectory.swift`: the four directory builders
    are `@MainActor` and take an optional source that defaults to nil,
    reading the Super key's own source when none is given.
  - `Services/CommandBar/CommandBarCatalog.swift`: `settingsEntries` is
    `@MainActor`.
  - `UI/Settings/SettingsView.swift`: the directory cache is `@MainActor`.
- **2026-10-03**: Refactor step 6zj (`REFACTOR.md`):
  - `Services/Audio/AppVolumeMixer.swift`: the mixer is `@MainActor`; its 26
    static HAL helpers, the two static constants others read and the
    output-volume selector table are `nonisolated`, the output-control
    lifetime its lock guards is `nonisolated(unsafe)`, and
    `isCurrentOutputAdjustment` is `nonisolated` on its own line.
- **2026-10-03**: Refactor step 6zk (`REFACTOR.md`):
  - `Services/Audio/AirPlayRouteManager.swift`: the manager is `@MainActor`;
    the stream registry is a constant made in init instead of a lazy
    property; the streaming methods, the context binding and the snapshot
    statics are `nonisolated`, with the renderer, the routing context, the
    message-send symbol and the snapshot behind their lock or set once;
    the picker delegate runs its bodies through `MainActor.assumeIsolated`
    (the second now `didEndPresentingRoutes`); its context observer and
    timer do too; and the renderer's failure callback is `@MainActor`.
  - `Services/Audio/AppVolumeMixer.swift`: an AirPlay build takes the
    manager from the main thread and hands it to its engine.
  - `Support/SelfTest.swift`: the AirPlay check reads the manager through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zl (`REFACTOR.md`):
  - `Services/MiddleClick/MiddleClickService.swift` is `@MainActor`; its
    shared instance and init are `nonisolated` (the multitouch callback
    reaches it from its own thread), its tap and contact-frame paths are
    `nonisolated`, the state its three locks guard is
    `nonisolated(unsafe)`, and its session, wake and hot-plug callbacks run
    their bodies through `MainActor.assumeIsolated`.
  - `Services/ScrollInverter.swift` is `@MainActor`; its tap callback is
    `nonisolated` on its own line, and the tap-thread state is
    `nonisolated(unsafe)`.
- **2026-10-03**: Refactor step 5k (`REFACTOR.md`):
  - `NotchService.bindEvents` keeps the volume and battery bindings; the
    other subscriptions moved to the new
    `Services/Notch/NotchEventBindings.swift`, and their reactions moved to
    the `eventBindings` wiring in `NotchService`, which also unbinds it on
    teardown.
  - `Tests/NotchTests.swift` runs the new `NotchEventBindingsTests`.
- **2026-10-03**: Refactor step 6zm (`REFACTOR.md`):
  - `Services/Display/BrightnessService.swift` is `@MainActor`; the state
    behind the key-thread lock, the state lock and the work queue is
    `nonisolated(unsafe)` with comments naming each guard; the methods
    that run on the key thread or the work queue, and the static display,
    system-brightness and IOKit helpers, are `nonisolated`; the media-key
    tap and the screen-parameters and wake observers run their bodies
    through `MainActor.assumeIsolated`; and the display-toggle finish
    publishes through a `@Sendable` closure that enters the main actor on
    the main thread.
  - `Services/CommandBar/CommandBarCatalog.swift`: the brightness row's
    apply is `@MainActor`.
- **2026-10-03**: Refactor step 6zn (`REFACTOR.md`):
  - Main-queue notification observers run their bodies through
    `MainActor.assumeIsolated` in `Services/AppUpdates/AppUpdatesService.swift`,
    `Services/Audio/AppVolumeMixer.swift`,
    `Services/Audio/MusicLaunchBlocker.swift`,
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Cleaner/CleanerScheduler.swift`,
    `Services/CleaningMode/CleaningModeManager.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift`,
    `Services/Clipboard/ClipboardIgnoredApps.swift`,
    `Services/CommandBar/CommandBarService.swift`,
    `Services/Display/ExtraBrightnessService.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/KeepAwakeManager.swift`,
    `Services/KillProcess/KillProcessService.swift`,
    `Services/ManagedDownloads/WhatsAppDownloadScheduler.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/Notch/NotchLockScreenService.swift`,
    `Services/QuickTools/CameraPreviewService.swift`,
    `Services/QuickTools/QuickLauncherService.swift`,
    `Services/QuickTools/RecentCaptureService.swift`,
    `Services/QuitProtection/QuitProtectionService.swift`,
    `Services/RadialMenu/RadialMenuService.swift`,
    `Services/SmoothScrollService.swift`,
    `Services/Snippets/SnippetLibraryService.swift`,
    `Services/Switcher/AppSwitcher.swift` and
    `Services/WindowLayout/WindowLayoutService.swift`.
  - `Services/WindowLayout/WindowLayoutService.swift`: the edge-snap
    preview's fade-out completion does the same.
  - `Services/Audio/MusicLaunchBlocker.swift`: the replacement app's launch
    callback hops to the main queue before it reads the setting.
  - `Services/Audio/AudioInputDeviceManager.swift`: the lock-guarded
    input-volume write lifetime is `nonisolated(unsafe)`.
- **2026-10-03**: Refactor step 6zo (`REFACTOR.md`):
  - `Services/QuickTools/MicMuteService.swift` is `@MainActor`; the
    CoreAudio statics, the adjustment lifetime and `withUnmutedInput` are
    `nonisolated` (the last two on their own line), the lock-guarded flag
    and lifetime are `nonisolated(unsafe)`, and the 6o change is reverted.
  - `Services/Audio/AudioInputDeviceManager.swift`: a volume write takes
    the mute service on the main thread before it is queued.
- **2026-10-03**: Refactor step 6zp (`REFACTOR.md`):
  - `Services/MouseExceptions/MouseAppExceptions.swift` is `@MainActor`;
    its shared instance and init are `nonisolated`, loading is split into
    the lock-guarded lookups (filled in init) and the published lists
    (published on the main thread), the tap-facing questions and their
    helpers are `nonisolated`, the lock-guarded state and the clock are
    `nonisolated(unsafe)`, and the source rebuild publishes through
    `MainActor.assumeIsolated` inside its main-thread hop.
  - `Tests/PointerInputFeatureTests.swift`: the pointer contract's
    `reload()` runs through `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zq (`REFACTOR.md`):
  - `App/AppDelegate.swift`: three main-queue observers and the quit-time
    input-source restore run through `MainActor.assumeIsolated`, and the
    notification delegate method is `nonisolated`.
  - `Services/QuickTools/QuickToolHUD.swift` and
    `Services/Notch/NotchWindowHost.swift`: their AppKit animation
    completions run through `MainActor.assumeIsolated`; the window host's
    completion parameter is `@MainActor @Sendable` and its
    `CAAnimationDelegate` conformance is `@preconcurrency`.
  - `Services/KeepAwakeManager.swift`: the running-apps handler is
    `@Sendable` and enters the main actor itself.
  - `Services/QuickTools/RecentCaptureService.swift`: the file manager is
    `nonisolated`.
  - `Services/Switcher/AppSwitcher.swift`: the wake observer runs through
    `MainActor.assumeIsolated`.
- **2026-10-03**: Refactor step 6zr (`REFACTOR.md`):
  - `Services/Permissions.swift` is `@MainActor`; Accessibility and Screen
    Recording are mirrored into lock-guarded statics as they are published,
    read through the new `nonisolated` `accessibilityGranted` and
    `screenRecordingGranted`; the Full Disk Access probe, its folder list
    and `automationStatus(for:)` are `nonisolated`; and the two observers
    and the polling timer run through `MainActor.assumeIsolated`.
  - `Services/Switcher/WindowActivator.swift`,
    `Services/Switcher/WindowPreviewProvider.swift`,
    `Services/Switcher/WindowEnumerator.swift` and
    `Services/QuickTools/ScreenshotCaptureEngine.swift` read the mirrored
    grants.
  - `Services/CommandBar/CommandBarCatalog.swift`: five builders that read
    a grant are `@MainActor`.
  - `Tests/ScreenshotFeatureTests.swift`: the window capture's permission
    gate is looked for as `Permissions.accessibilityGranted`.
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
