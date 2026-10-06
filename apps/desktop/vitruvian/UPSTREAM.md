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
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`):
  - `Services/Switcher/WindowPreviewProvider.swift`: `captureIsPaused`
    gains a `package` overload that takes the preferences and the frontmost
    app's bundle identifier; the private one passes the system's.
  - `Services/Switcher/WindowEnumerator.swift`: `dockPreviewMayActivate`
    gains a `package` overload that takes the window, the preference and the
    desktop query; the one the app calls passes the system's.
  - `Tests/SwitcherModelFeatureTests.swift` and
    `Tests/DockPreviewScopeTests.swift` check those overloads directly and
    drop their stand-ins.
  - `Tests/generate_sources.py` no longer copies `captureIsPaused` or
    `dockPreviewMayActivate`.
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
- **2026-10-04**: Refactor step 6zs (`REFACTOR.md`):
  - `@unchecked Sendable` lock-guarded cancellations in
    `Services/AgentUsage/AgentUsageService.swift`,
    `Core/Cleaner/CleanerSupport.swift`,
    `Services/Uninstall/UninstallerSupport.swift` and
    `Services/Media/MediaService.swift`, which also keeps the conversion
    log in a new locked type.
  - `Services/Metrics/SpeedTest.swift`: the time box's action is `@Sendable`.
  - `Services/SuperKey/SuperKeyService.swift`: the mapping work is
    `@Sendable`; CoreFoundation is a `@preconcurrency` import.
  - `Services/Notch/NotchNotificationService.swift`: the reader reaches its
    queue through a `nonisolated(unsafe)` local.
  - `Services/Clipboard/ClipboardHistoryService.swift`: the resize observer
    reads the panel from the notification.
  - `Services/QuickTools/RecentCaptureService.swift`: the file manager is
    `nonisolated(unsafe)`.
  - `@preconcurrency` imports in
    `Services/QuickTools/CameraPreviewService.swift` (AVFoundation),
    `Services/Notch/NotchAccessoryService.swift` (IOBluetooth),
    `Services/WindowLayout/WindowLayoutService.swift` and
    `Services/WindowMaximizer.swift` (ApplicationServices), and
    `Services/Notch/NotchMusicService.swift` (Dispatch).
- **2026-10-04**: Refactor step 6zt (`REFACTOR.md`):
  - `Services/TransientPaste.swift` is `@MainActor`; `shared`, init and
    `paste` are `nonisolated`, `paste` keeps its main-thread check and runs
    the new private `pasteOnMain`, the snapshot crosses to the lane through
    `nonisolated(unsafe)` locals, the restore enters the main actor, and the
    snapshot reader is `nonisolated`.
  - `Services/Clipboard/ClipboardAutoClearService.swift` is `@MainActor`;
    its observers and timer run through `MainActor.assumeIsolated`, and the
    lock-guarded configuration generation is `nonisolated(unsafe)`.
- **2026-10-04**: Refactor step 6zu (`REFACTOR.md`):
  - Static state says what guards it, as `nonisolated(unsafe)` with a
    comment:
    - a lock: `Services/CommandBar/CommandBarSystemSettings.swift`,
      `Services/Notch/NotchAudioLevelService.swift`,
      `Services/Notch/NotchNotificationReader.swift`,
      `Services/QuickTools/ScreenshotService.swift`, the caches in
      `Services/Recorder/RecorderCursorSprite.swift`,
      `RecorderImageRenderer.swift` and `RecorderTextRenderer.swift`,
      `Services/SpotlightNames.swift`,
      `Services/SystemShortcutTakeover.swift`, the activation generations in
      `Services/Switcher/WindowActivator.swift`, the wallpaper thumbnail
      generation in `Services/Wallpaper/WallpaperService.swift` and the
      prompt flag in `Services/ShellSupport.swift`, whose sleep-state count
      only its queue touches;
    - the main thread: `Services/ActivationHandoff.swift`,
      `Services/Display/BrightnessOSD.swift`,
      `Services/HorizontalWheelScrolling.swift`,
      `Services/MouseNavigation/MouseNavigationKeys.swift`,
      `Services/QuickTools/QuickToolHotkey.swift`,
      `Services/Switcher/SpaceHop.swift`, the pending close and restore in
      `Services/Switcher/WindowActivator.swift`, the command bar caches in
      `Services/CommandBar/CommandBarCatalog.swift` and
      `CommandBarExtras.swift`, the file icon list in
      `Services/Clipboard/ClipboardHistoryService.swift` and the app icons
      in `Services/RadialMenu/RadialNowPlayingService.swift`;
    - `NSCache`, which is thread-safe, in
      `Services/Clipboard/ClipboardHistoryService.swift`,
      `Services/MenuBar/MenuBarRenderer.swift`,
      `Services/ResponsibleProcess.swift` and
      `Services/Wallpaper/WallpaperService.swift`;
    - `dlopen` handles that only `dlsym` reads, in
      `Services/DockPreview/DockAutohideHold.swift`,
      `Services/Display/BrightnessService.swift` and
      `Services/MiddleClick/MiddleClickService.swift`, and the constant
      audio settings in `Services/Recorder/RecorderWriter.swift`.
  - `@MainActor`: `Services/QuickTools/WindowActivationPolicy.swift`,
    `Services/ServiceViews.swift` and `MediaPanelModal.panelModalActive`
    in `Services/Media/MediaPanelModal.swift`. `main.swift` installs the
    view factory inside `MainActor.assumeIsolated`.
- **2026-10-04**: Refactor step 6zv (`REFACTOR.md`):
  - `@MainActor`: `Services/DockPreview/DockPreviewDragGhost.swift`,
    `Services/Shelf/ShelfTooltipPopover.swift`,
    `Services/QuickTools/QRResultController.swift`,
    `Services/QuickTools/ScreenshotPinController.swift`,
    `Services/Bluetooth/BluetoothSleepService.swift`,
    `Services/RadialMenu/RadialNowPlayingService.swift` (the service, not
    its bridge), and:
    - `Services/ScrollWheelTarget.swift`, whose `shared`, init and
      `contains` are `nonisolated` and whose self-locking cache is
      `nonisolated(unsafe)`;
    - `Services/MouseAcceleration/MouseAccelerationService.swift`, whose
      HID device callback is `nonisolated` and enters the main actor;
    - `Services/FocusFollowsMouse/FocusFollowsMouseService.swift`, whose
      window query helpers are `nonisolated` and whose timer enters the
      main actor;
    - `Services/DockClick/DockClickService.swift`, whose tap enters the
      main actor and whose Accessibility helpers are `nonisolated`;
    - `Services/DiskImageInstaller/DiskImageInstallerService.swift`, whose
      mount check, install and their static helpers are `nonisolated`.

    Their main-queue observers enter the main actor through
    `MainActor.assumeIsolated`.
  - `@unchecked Sendable`, with a comment saying why:
    `Services/SessionActivity.swift` and
    `Services/GeneralPasteboardAccess.swift`.
  - `main.swift` recovers mouse acceleration inside
    `MainActor.assumeIsolated`.
- **2026-10-04**: Refactor step 6zw (`REFACTOR.md`):
  - `@MainActor`: `Services/Recorder/RecorderIndicator.swift`,
    `Services/QuitProtection/QuitProtectionHUD.swift`,
    `Services/HorizontalWheelScrolling.swift` (its state no longer
    `nonisolated(unsafe)`), `NotchFrameProbe` in
    `Services/Notch/NotchWindowHost.swift`, `WheelMotion` and
    `PanelDismissal` in `Services/RadialMenu/RadialMenuService.swift`, and
    `DiskImageInstallDestinationPrompt` in
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`.
  - `Services/Display/BrightnessOSD.swift` is `@MainActor` with plain
    statics; `show`, `teardown` and `dismiss` are `nonisolated`, hop to the
    main thread and run the new private `showOnMain`, `teardownOnMain` and
    `dismissOnMain`.
  - `@MainActor` functions: `appShell()` in `Services/AppShell.swift`,
    `runImportPanel` in `Services/SettingsBackup.swift`,
    `trashOwnBundleAndQuit` in `Services/SelfUninstall.swift`, `snapshot`,
    `listWindows(for:maximumCount:currentSpaceOnly:marksHiddenSpaces:)` and
    `listWindowsForDockPreview` in `Services/Switcher/WindowEnumerator.swift`
    and `add` in `Services/Notch/NotchOverlaySpace.swift`.
  - `MainActor.assumeIsolated` with a comment in
    `Services/Switcher/WindowActivator.swift` (this app's own windows),
    `Services/ActivationHandoff.swift`, `Services/ShellSupport.swift`,
    `Services/Notch/NotchMenuSpaceReader.swift`,
    `Services/Notch/NotchGestureSupport.swift` (`nativeInteraction`, which the
    tests call from plain code),
    `Services/CommandBar/CommandBarCatalog.swift`, the display-link tick in
    `Services/Notch/NotchWindowHost.swift`, and the animation completions in
    `BrightnessOSD.swift`, `RecorderIndicator.swift`,
    `RadialMenuService.swift` and `Services/Notch/NotchLockScreenService.swift`,
    whose completion types are `@MainActor () -> Void` where they cross.
  - `Services/MouseNavigation/MouseNavigationKeys.swift`: `Shortcut` is
    `Sendable`, `shortcut(for:)` reads the main menu inside
    `MainActor.assumeIsolated`, and `refresh` runs the new main-actor
    `refreshOnMain`.
  - `Services/DockClick/DockClickService.swift`: `activate(pid:)` and
    `restore(_:)` are `nonisolated`, and the restore and minimize walks take
    `[weak self]` in the main-queue block that uses it.
  - `nonisolated(unsafe)` with a comment: the formatters in
    `Services/AgentUsage/AgentLogParser.swift`, the attributes in
    `Services/EnhancedUserInterfaceSuspension.swift` and
    `Services/SpotlightNames.swift`, the UUIDs in
    `Services/Metrics/PeripheralBatterySampler.swift`, `Environment.system`
    in `Services/Notch/NotchPointerFollower.swift` and the run loop in
    `Services/PointerTapRunLoop.swift`.
- **2026-10-04**: Refactor step 6zx (`REFACTOR.md`):
  - `@unchecked Sendable`, with a comment naming what guards each:
    `Services/Finder/FinderRenameService.swift`,
    `Services/MouseClickDebounce/MouseClickDebounceService.swift`,
    `Services/Snippets/TextSnippetService.swift`,
    `Services/Switcher/WindowUseTracker.swift`,
    `Services/SystemMonitor/ProcessUsageService.swift`,
    `Services/Metrics/MaxCapacityProbe.swift` and
    `Services/Switcher/WindowPreviewProvider.swift`, whose `onUpdate` is
    `@MainActor @Sendable`.
  - `AlertSound` in `TextSnippetService.swift` is `Sendable`.
  - `@MainActor @Sendable` callback types: `WheelMotion.dismiss` and
    `PanelDismissal.begin` in `Services/RadialMenu/RadialMenuService.swift`,
    and `fadeOut` (with its caller's counter) in
    `Services/Notch/NotchLockScreenService.swift`.
- **2026-10-04**: Refactor step 6zy (`REFACTOR.md`):
  - `Services/DockClick/DockClickService.swift`: the restore and minimize
    walks' outer queue blocks take `[weak self]` again, beside the inner
    main-queue blocks that use it.
- **2026-10-04**: Refactor step 6zz (`REFACTOR.md`):
  - `@preconcurrency import CoreGraphics` in
    `Services/DockClick/DockClickService.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/MouseButtons/MouseButtonShortcutService.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/QuitProtection/QuitProtectionService.swift`,
    `Services/ShortcutRecordingTap.swift`, `Services/SmoothScrollService.swift`,
    `Services/Switcher/AppSwitcher.swift`,
    `Services/WindowLayout/WindowLayoutService.swift` and
    `Services/WindowMaximizer.swift`, and added to
    `Services/Audio/PreciseVolumeRollerService.swift`,
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Display/BrightnessService.swift` and
    `Services/RadialMenu/RadialMenuService.swift`.
- **2026-10-04**: Refactor step 6zza (`REFACTOR.md`):
  - `Services/TransientPaste.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift` and
    `Services/Notch/NotchService.swift`: callbacks and a planned pasteboard
    write handed across threads as `nonisolated(unsafe)` lets.
  - `Services/Clipboard/ClipboardAutoClearService.swift`,
    `Services/KillProcess/KillProcessService.swift`,
    `Services/Homebrew/HomebrewManager.swift` and
    `Services/Switcher/WindowEnumerator.swift`: callback parameters typed
    `@Sendable` or `@MainActor @Sendable`.
  - `Services/Homebrew/HomebrewManager.swift`: a lock-guarded output box
    replaces captured `var`s; completion blocks take `[weak self]` inside.
  - `Services/Switcher/WindowEnumerator.swift`: a lock-guarded batch type
    replaces captured `var`s.
  - `Services/AgentUsage/AgentCodexServer.swift`: the pipe buffer moves into
    its own lock-guarded inbox.
  - `@unchecked Sendable` with what guards them:
    `Services/URLCleanerService.swift` (poll token),
    `Services/Notch/NotchMusicService.swift` (pipe reader),
    `Services/Recorder/ScreenRecorderService.swift` (session),
    `Services/Recorder/RecorderPointerSampler.swift` and
    `Services/Recorder/RecorderTypingTrack.swift`.
  - `Services/Recorder/ScreenRecorderService.swift`: the tap audio choice
    is settled before the stream runs and withdrawn through an atomic flag.
  - `Services/KillProcess/KillProcessService.swift` and
    `Services/QuickTools/CameraPreviewService.swift`: notification fields
    read before `MainActor.assumeIsolated`.
  - `Services/Permissions.swift`: the Accessibility prompt option spelled as
    its value.
  - `Sources/VMStatisticsCompat/include/VMStatisticsCompat.h`,
    `Services/Metrics/VMStatisticsDecoder.swift` and
    `Services/SystemInfo.swift`: the kernel page size read in C.
- **2026-10-04**: Refactor step 6zzb (`REFACTOR.md`):
  - Notification fields read before `MainActor.assumeIsolated` in
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift`,
    `Services/Clipboard/ClipboardIgnoredApps.swift`,
    `Services/CommandBar/CommandBarService.swift`,
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`,
    `Services/MouseNavigation/MouseNavigationService.swift`,
    `Services/QuickTools/QuickLauncherService.swift`,
    `Services/QuickTools/RecentCaptureService.swift`,
    `Services/QuitProtection/QuitProtectionService.swift`,
    `Services/RadialMenu/RadialMenuService.swift`,
    `Services/Snippets/SnippetLibraryService.swift` and
    `Services/Switcher/AppSwitcher.swift`.
  - The notification or timer handed over as a `nonisolated(unsafe)` let in
    `Services/Audio/MusicLaunchBlocker.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Shelf/ShelfService.swift` and `Services/WindowMaximizer.swift`.
- **2026-10-04**: Refactor step 6zzc (`REFACTOR.md`):
  - Properties a main-actor `deinit` reads are `nonisolated(unsafe)` in
    `Services/Audio/AirPlayRouteManager.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/FanControl/FanControlService.swift`,
    `Services/Notch/NotchWindowHost.swift`, `Services/Permissions.swift` and
    `Services/Recorder/RecorderEditorController.swift`.
- **2026-10-04**: Refactor step 6zzd (`REFACTOR.md`):
  - Event-tap verdicts returned from `DispatchQueue.main.sync` in
    `Services/Switcher/AppSwitcher.swift` and
    `Services/Finder/FinderCutPaste.swift`.
  - Main-queue hops take their own `[weak self]` in
    `Services/Clipboard/ClipboardHistoryService.swift`.
  - `@unchecked Sendable` with what guards them:
    `Services/CommandBar/CommandBarFileSearch.swift`,
    `Services/CommandBar/CommandBarScriptRunner.swift`,
    `Services/Notch/NotchTimerAlert.swift`,
    `Services/Recorder/RecorderCaptureEngine.swift`,
    `Services/Recorder/RecorderCursorCatalog.swift` and two classes in
    `Services/Switcher/WindowActivator.swift`.
- **2026-10-04**: Refactor step 6zze (`REFACTOR.md`):
  - Callbacks typed `@MainActor @Sendable` or `@Sendable` in
    `Services/Notch/NotchNotificationService.swift`,
    `Services/Permissions.swift`, `Services/SelfUninstall.swift`,
    `Services/WindowMaximizer.swift`,
    `Services/Homebrew/HomebrewManager.swift`,
    `Services/SuperKey/SuperKeyService.swift` and
    `Services/ShellSupport.swift`.
  - `Services/GeneralPasteboardAccess.swift`: `Sendable` results and
    main-actor completions; the deadline canceller and `didFinish` move into
    the delivery object.
  - `Services/CommandBar/CommandBarCatalog.swift`: the clipboard helper is
    `@MainActor` and takes a main-actor body.
  - Callbacks passed through as `nonisolated(unsafe)` lets in
    `Services/KeepAwakeManager.swift`, `Services/TransientPaste.swift` and
    `Services/Notch/NotchMenuSpaceReader.swift`.
  - `Services/Switcher/WindowServerCaptureQueue.swift`: the captured value is
    a `nonisolated(unsafe)` let, handed to the caller as `sending`.
- **2026-10-04**: Refactor step 6zzf (`REFACTOR.md`):
  - Values read before the hop in
    `Services/AppUpdates/AppUpdatesService.swift`,
    `Services/Display/BrightnessService.swift` and
    `Services/MouseAcceleration/MouseAccelerationService.swift`.
  - `Services/DockPreview/DockPreviewFrameRestoration.swift`: a main-actor
    `isCurrent`. `Services/Media/MediaService.swift`: a `sending` operation,
    and the asset it reads handed over as a `nonisolated(unsafe)` let.
  - `@unchecked Sendable` with what keeps them safe:
    `Core/Switcher/SwitcherSupport.swift`,
    `Services/Switcher/WindowActivator.swift` and
    `Services/Shelf/ShelfFilePromiseTransfer.swift`.
  - `nonisolated(unsafe)` hand-offs in
    `Services/DockClick/DockClickService.swift`,
    `Services/CommandBar/CommandBarCatalog.swift`,
    `Services/AutoQuit/AutoQuitService.swift`,
    `Services/Audio/AppVolumeMixer.swift` and
    `Services/Snippets/TextSnippetService.swift`.
- **2026-10-04**: Refactor step 6zzg (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotCaptureEngine.swift`: only window IDs
    cross to the main actor when finding the windows to exclude.
  - `Services/Recorder/RecorderExporter.swift`: `Sendable`, with a
    `@Sendable` progress callback, and `nonisolated(unsafe)` hand-offs into
    the task group.
  - `Services/Recorder/RecorderEditorController.swift`: the waveform tracks
    and asset are handed over as `nonisolated(unsafe)` lets, and the
    progress closures take their own `[weak self]`.
- **2026-10-04**: Refactor step 6zzh (`REFACTOR.md`):
  - Tap callbacks as `nonisolated` static lets in
    `Services/ScrollInverter.swift` and
    `Services/MiddleClick/MiddleClickService.swift`.
  - `Services/PointerTapRunLoop.swift`: `TapThreadRunLoop.stop(_:)`, used by
    `Services/Switcher/AppSwitcher.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/SuperKey/SuperKeyService.swift`,
    `Services/KeyboardDebounce/KeyboardDebounceService.swift` and
    `Services/Display/BrightnessService.swift`.
  - `nonisolated` static helpers for the sound completion in
    `Services/Notch/NotchLockScreenService.swift` and the XPC error handler
    in `Services/FanControl/FanControlService.swift`.
- **2026-10-04**: Refactor step 6zzi (`REFACTOR.md`): `Services/` builds in
  Swift 6 mode (`BUILD`).
- **2026-10-04**: Refactor step 6zzj (`REFACTOR.md`): the app target builds
  in Swift 6 mode (`BUILD`).
  - `App/AppDelegate.swift` reads what it needs from two notifications before
    entering the main actor.
  - `App/StatusItemController.swift` marks the four properties its `deinit`
    reads `nonisolated(unsafe)`.
- **2026-10-04**: `Tests/SwitcherScrollTests.swift` gives each scroll check up
  to 3 s, not 0.5 s, to settle. On a loaded runner an animated reveal has
  landed later than that.
- **2026-10-04**: Refactor step 6zzk (`REFACTOR.md`): `FanControlKit/` and
  the fan control helper build in Swift 6 mode (`BUILD`).
- **2026-10-04**: Refactor step 6zzl (`REFACTOR.md`): the Now Playing helper
  builds in Swift 6 mode (`BUILD`). `NowPlayingAdapter/NowPlayingAdapter.swift`,
  `NowPlayingQueue.swift` and `NowPlayingSelection.swift` mark their shared
  state `nonisolated(unsafe)`, each with the lock, queue or rule that guards
  it, and the watch's `refresh()` is `@Sendable`.
- **2026-10-04**: Refactor step 6zzm (`REFACTOR.md`): the tests build in
  Swift 6 mode, with the main actor as their default isolation (`BUILD`).
  - `Services/GeneralPasteboardAccess.swift`,
    `Services/MouseExceptions/MouseAppExceptions.swift` and
    `Services/Metrics/SpeedTest.swift` take `@Sendable` clocks, and
    `SpeedTest` a `@Sendable` time-box scheduler: each calls them on its own
    queue.
  - `Tests/`: what runs off the main thread says `nonisolated`, stand-in base
    classes declare `init() {}`, and `TestSuite` is `Sendable`.
  - `Tests/generate_sources.py` can keep a `nonisolated` written above a
    copied declaration, and the app-updates copies do.
- **2026-10-04**: Refactor step 6zzn (`REFACTOR.md`): `make_icon` builds in
  Swift 6 mode, with the main actor as its default isolation (`BUILD`).
  `Tools/MakeIcon.swift` is unchanged.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), three more tests through
  the module:
  - `Services/ResponsibleProcess.swift`: `displayName` has an overload that
    takes the app name, kernel name and executable path lookups.
  - `Core/AppKitExtensions.swift`: `NSScreen.withMouse` makes its choice
    through `screen(containing:among:frame:fallback:)`.
  - `UI/Switcher/ScrollingTitle.swift`: `shouldScroll(scrolls:reduceMotion:overflows:)`.
  - `Tests/ProcessNameTests.swift`, `PointerScreenTests.swift` and
    `ScrollingTitleMotionTests.swift` call these, and
    `Tests/generate_sources.py` no longer copies them.
  - `Tests/PointerDisplayLookupTests.swift`: the stand-in screen, which still
    takes a copy of `withMouse`, chooses through the module's helper.
- **2026-10-04**: `Tests/SpeedTestTests.swift` fires the download time box
  only once the speed test has counted a chunk's bytes. The fixture finishes
  the first chunk and leaves the second unanswered: the delegate asks for the
  second only after counting the first. Before, the time box could fire
  between the fixture handing over the bytes and the delegate receiving them,
  and measure no download.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), three more tests through
  the module:
  - `Services/SystemMonitor/SystemMonitor.swift`: `readCPUUsage` hands the
    host's tick counters to `cpuUsage(ticks:now:previous:held:heldReadAt:)`.
  - `Services/CommandBar/CommandBarCatalog.swift`: `copyAnswer` has an
    overload that takes the pasteboard write and the HUD.
  - `Services/Clipboard/ClipboardHistoryService.swift`: `pasteIntoPreviousApp`
    has an overload that takes the target app's state, the Accessibility
    grant, the beep, the prompt and the paste.
  - `Tests/SystemMonitorCPUTests.swift`, `CommandBarFeatureTests.swift` and
    `ClipboardFeatureTests.swift` call these, and `Tests/generate_sources.py`
    no longer copies them.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), three more generated
  copies dropped:
  - `Services/Audio/AppVolumeMixer.swift`: `switchToNextSoundOutput(in:)`
    switches through `switchToNextSoundOutput(in:outputs:currentUID:switchTo:)`.
  - `UI/Settings/ShortcutsSettings.swift`: `expansionBinding(for:in:)` hands
    its state to `expansionBinding(for:in:expanded:)`.
  - `Tests/SoundOutputSwitchTests.swift` and `FeatureCatalogTests.swift` call
    these, and the tests use the shipped `NotchNotice`.
    `Tests/generate_sources.py` no longer copies any of the three.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), two more generated
  copies dropped:
  - `Services/Switcher/WindowPreviewProvider.swift`: `captureViaWindowServer`
    captures through an overload that takes the connection, capture
    function, options and queue; its two typealiases are `package`.
  - `Tests/WindowServerCaptureTests.swift` calls it with its fake, and
    `Tests/NotchPanelTests.swift` builds the shipped `NotchPanel`.
    `Tests/generate_sources.py` no longer copies either.
- **2026-10-04**: Refactor step 4b (`REFACTOR.md`), two more generated
  files dropped:
  - `UI/MenuPanel/MixerSection.swift`: the level field's Escape monitor
    decides through `MixerPercentEscape.cancelsLevel`.
  - `Tests/MixerPercentKeyTests.swift` calls it, and the notch tests use the
    shipped `NotchShape`. `Tests/generate_sources.py` no longer copies either,
    nor `NotchActivityPicker`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/MenuPanel/BrightnessSection.swift` decides which display rows offer the
  dimming choice through `SoftwareDimmingButton.offersChoice`, which
  `Tests/SoftwareDimmingRouteTests.swift` calls; `Tests/generate_sources.py`
  no longer copies the row's rule.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/MenuPanel/MenuPanelView.swift` lists its rows' hub features in
  `MenuPanelRowFeatures`, which `Tests/MenuPanelSectionGateTests.swift` checks
  against the shipped section gates; `Tests/generate_sources.py` no longer
  copies the sections, rows or quick toggles.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AgentUsage/AgentUsageService.swift` settles and saves progress
  through `settleArchive(on:keeping:save:remove:)` and
  `saveProgress(mark:savedMark:providers:store:cursors:save:)`, and filters
  agent events through `delivers(_:queuedIn:running:session:providers:in:)`,
  which `Tests/AgentUsageArchiveTests.swift` and
  `Tests/AgentUsageEventDeliveryTests.swift` call; `Tests/generate_sources.py`
  no longer copies the settle, save or report methods.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AgentUsage/AgentUsageService.swift` reads agent logs through
  `read(_:provider:cursors:store:isCancelled:report:lines:)`, which
  `Tests/AgentUsageReadTests.swift` calls; `Tests/generate_sources.py` no
  longer copies the read method. The test's cancelled read now has a new line
  to skip.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Cleaner/CleanerScheduler.swift` saves a finished pass through
  `recordRun(freed:failed:at:in:)`, and `UI/Cleaner/CleanerView.swift` builds
  its last-run line in `lastRunLine(ranAt:freed:failed:strings:)`, both called
  by `Tests/CleanerLastRunContract.swift`; `Tests/generate_sources.py` no
  longer copies `finishRun` or the card's line.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMusicService.swift` plays a queue row through
  `playQueued(_:visible:request:upcoming:playback:pending:failed:in:send:)`,
  which `Tests/NotchMusicHardeningTests.swift` calls; `Tests/generate_sources.py`
  no longer copies the row action.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/KeepAwakeManager.swift` decides a timer's handoff to automation in
  `timerHandoff(trigger:suppressed:in:batteryAllows:matching:enabled:requireAll:)`,
  which `Tests/KeepAwakeTimerHandoffTests.swift` calls; `Tests/generate_sources.py`
  no longer copies `continueAutomaticallyAfterTimerIfNeeded`, and
  `Tests/mutation_checks.py` targets the static's guard.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): `Tests/generate_sources.py`
  no longer copies nine data types the production modules export
  (`DisplayControlFailure`, `CommandBarService.Mode`, `JunkCleaner.Phase`,
  `UpdateService.State`, the quick preview's `Action`, `NotchMediaSession` and
  `SpaceWindowBridge.Topology` three times). The generated tests alias the
  module's types instead.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the Dock preview's
  desktop-change observation moves from `Services/DockPreview/DockPreviewService.swift`
  into the new `Services/DockPreview/DockPreviewSpaceObservation.swift`, which
  `Tests/DockPreviewScopeTests.swift` drives directly; `Tests/generate_sources.py`
  no longer copies the observation methods.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Cleaner/JunkCleaner.swift` reads its home folder, screenshot
  folders and Launch Services lookup from an injected `Places`, and runs its
  category scans and queues through an injected `Scanning`; `scan(attended:)`
  loops over the categories in the same order. `Tests/CleanerEligibilityTests.swift`
  and `Tests/CleanerScanFlowTests.swift` call the module, and
  `Tests/generate_sources.py` no longer copies the cleaner.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/CommandBar/CommandBarCatalog.swift` routes the bar's brightness
  command through an injected `BrightnessRoute`, which
  `Tests/CommandBarFeatureTests.swift` passes; `Tests/generate_sources.py` no
  longer copies `applyBrightness`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/DockPreview/DockPreviewFrameRestoration.swift` checks and
  restores a window through an injected `RestoreHost`, which
  `Tests/DockPreviewFrameRestorationTests.swift` passes; `Tests/generate_sources.py`
  no longer copies `restore`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/KeyboardDebounce/KeyboardDebounceService.swift` decides a key
  event in `suppresses(_:event:state:config:)`, which
  `Tests/KeyboardDebounceTapTests.swift` calls; `Tests/generate_sources.py` no
  longer copies the tap handler.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/PortManager/PortManagerService.swift` reads processes, the lsof
  listing and its queues through an injected `Scanning`, and `snapshot(_:)` is
  `package`; `Tests/PortManagerRefreshTests.swift` passes inert ones, and
  `Tests/generate_sources.py` no longer copies the refresh.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/FanControl/FanControlLifecycle.swift` (new) holds fan control's
  resume, preference and idle-work decisions, which
  `Services/FanControl/FanControlService.swift` forwards to;
  `Tests/FanControlResumeTests.swift` drives it with a recording host, and
  `Tests/generate_sources.py` no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchAudioLevelService.swift` reads its preferences, playback
  and readers through an injected `Environment`, with readers behind
  `NotchAudioLevelReading`; `Tests/NotchAudioLevelTests.swift` passes its own,
  and `Tests/generate_sources.py` no longer copies the service.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Audio/MusicLaunchBlocker.swift` reads its defaults, permission,
  clock, running players, notifications, key tap and replacement launcher
  through an injected `System`; the tap callback hands keys to
  `observeMediaKey(type:key:)`. `Tests/FeatureCatalogTests.swift` drives it
  with doubles, and `Tests/generate_sources.py` no longer copies its methods.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/RadialMenu/RadialNowPlayingService.swift` opens the player through an
  injected `Opening` (`open(_:using:)`); `Tests/NowPlayingOpenContract.swift`
  passes recording doubles, and `Tests/generate_sources.py` no longer copies
  `open`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Update/UpdateService.swift` runs its administrator install through
  an injected `AdminInstall`; `Tests/UpdateAdminInstallTests.swift` passes
  doubles to its own service, and `Tests/generate_sources.py` no longer copies
  `launchAdminInstaller`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Media/MediaPanelModal.swift` runs dialogs through
  `run(_:host:completion:)` with an injected `Dialog` and `Host`, and the island
  window behind `IslandWindowing`; `Tests/MediaDialogHostTests.swift` drives it
  with doubles, and `Tests/generate_sources.py` no longer copies
  `runPanelModal`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchLyricsService.swift` reads its preferences, lookups, island,
  file chooser, activation and queues through an injected `Environment`;
  `Services/Media/MediaPanelModal.swift`'s `IslandWindowing` is `Sendable`.
  `Tests/NotchMusicHardeningTests.swift` drives the real service with doubles,
  and `Tests/generate_sources.py` no longer copies its lifecycle.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchDownloadFolderChoice.swift` (new) holds the download
  folder chooser that `Services/Notch/NotchDownloadService.swift` forwards to,
  and `Services/Notch/NotchIslandSurface.swift` (new) the island state it and
  `Services/Notch/NotchLyricsService.swift` return to.
  `Tests/NotchDownloadFolderChoiceTests.swift` drives the choice with doubles,
  and `Tests/generate_sources.py` no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Recorder/RecorderExportProgressChip.swift` (new) is the export chip that
  `UI/Recorder/RecorderEditorView.swift` shows; `Tests/RecorderExportChipTests.swift`
  lays it out, and `Tests/generate_sources.py` no longer copies its body.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/SelfUninstall.swift` runs its clear and uninstall flows through
  injected `Steps`; `Tests/SelfUninstallTests.swift` passes logging doubles,
  and `Tests/generate_sources.py` no longer copies the flows.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Clipboard/ClipboardHistoryService.swift` hands a history image to the
  screenshot editor through a static `editImage(_:editing:)` with an injected
  `ImageEditing`; `Tests/ClipboardHistoryImageEditorTests.swift` runs it, and
  `Tests/generate_sources.py` no longer copies it or `imageCapture(from:)`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMissionControlPolling.swift` (new) holds the Mission Control
  polling that `Services/Notch/NotchWindowHost.swift` forwards to;
  `Tests/NotchMissionControlPollingTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the host's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/ScrollInverter.swift` decides each wheel event in
  `adjustWheel(_:state:defaults:ownProcessID:targets:)`, which
  `Tests/LinearScrollTapTests.swift` calls with real events;
  `Tests/generate_sources.py` no longer copies the tap handler.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Shelf/ShelfInternalDrag.swift` (new) holds the drag out of a shelf
  that `Services/Shelf/ShelfService.swift` forwards to;
  `Tests/ShelfDragCompletionTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/ScreenshotQuickPreviewController.swift` takes an injected
  `Scheduler` and opens its hover, action and auto-dismiss members to the
  package; `Tests/ScreenshotPreviewHoverTests.swift` drives a real preview, and
  `Tests/generate_sources.py` no longer copies the controller.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/CommandBar/CommandBarInputSourceBorrowing.swift` (new) holds the ASCII
  layout borrowing that `Services/CommandBar/CommandBarService.swift` forwards to;
  `Tests/CommandBarFeatureTests.swift` drives it, and `Tests/generate_sources.py`
  no longer copies the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Switcher/WindowActivator.swift` activates apps through injected
  `ActivationCalls` over `SwitcherActivatableApp`, and
  `Services/Switcher/SpaceWindowBridge.swift` fronts windows through injected
  `FrontingCalls`; `Tests/SwitcherActivationTests.swift` drives both, and
  `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/ScreenshotScrollingCapture.swift` runs its capture loop
  over an injected `FrameSource`; `Tests/ScreenshotScrollingCaptureTests.swift`
  supplies the frames, and `Tests/generate_sources.py` no longer copies the enum.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/UpdateHighlightsView.swift` takes the tour animation's URL and opens
  `UpdateHighlightsGIF` to the package; `Tests/UpdateHighlightsTests.swift`
  renders the real view, and `Tests/generate_sources.py` no longer copies it.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Settings/NotchSettingsRows.swift` (new) holds the destination and AI agents
  rows that `UI/Settings/NotchSettings.swift` and
  `UI/Settings/NotchAgentsSettings.swift` draw; `Tests/NotchSettingsChoiceTests.swift`
  measures them, and `Tests/generate_sources.py` no longer copies the rows or the
  card primitives.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Media/MediaWorkspaceView.swift` draws its layout and drop target through
  `MediaWorkspaceStack` and `MediaInputDropTarget` and picks tools through a
  static `pick`, and `UI/Notch/NotchFilesView.swift` sizes the island through a
  static `mediaHeightChanged` over `NotchMediaHeightTracking`
  (`Services/Notch/NotchFileToolsService.swift`);
  `Tests/MediaWorkspaceLayoutTests.swift` uses them, and
  `Tests/generate_sources.py` no longer copies the view members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuitProtection/QuitProtectionHUD.swift` opens the HUD and its content
  view to the package; the progress checks move from
  `Tests/Fixtures/QuitProtectionHUDChecks.swift` to `Tests/QuitProtectionHUDTests.swift`,
  and `Tests/generate_sources.py` no longer copies the HUD.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchPointerFollower.swift` gains `NotchIslandSummons`, which
  `Services/Notch/NotchService.swift` wires in place of `bringIsland(to:)`;
  `Tests/NotchMirrorTests.swift` drives it, and `Tests/generate_sources.py` no
  longer copies the service's method.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchScreenEdgeClicks.swift` works out the island's edge-click
  area and press in `area(for:)` and `pressed(hoverWork:hoverState:)`, which
  `Services/Notch/NotchService.swift` calls; `Tests/NotchScreenEdgeClickTests.swift`
  feeds them, and `Tests/generate_sources.py` no longer copies the members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AppUpdates/AppUpdatesService.swift` takes an injected `Environment`
  (preferences, availability, notifications, scan) and splits the scan from
  `check()`; `Tests/AppUpdateRulesTests.swift` drives the real service, and
  `Tests/generate_sources.py` no longer copies its rule members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/AppUpdates/AppUpdatesService.swift` takes an injected `Network` (clock,
  catalog session, feed URL loading) and opens its online sources to the package,
  and `Services/AppUpdates/AppUpdateFeedLoader.swift` accepts URL protocol classes;
  `Tests/AppUpdatesTests.swift` drives them, and `Tests/generate_sources.py` no
  longer copies the loader or the service's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the island's volume notice
  moves from `Services/Notch/NotchService.swift` to
  `Services/Notch/NotchVolumeFeedback.swift`, which takes an injected output
  and island; `NotchService` forwards to it. `Tests/NotchVolumeFeedbackTests.swift`
  drives it, `Tests/generate_sources.py` no longer copies the service's volume
  members, and `Tests/mutation_checks.py` mutates the new file.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/ScratchpadService.swift` takes an injected environment
  (store, HUD warning, autosave timer, save dialog, island window, activation,
  main queue) and exports from an `IslandWindowing` host;
  `Tests/ScratchpadStoreContractTests.swift` drives the real service, and
  `Tests/generate_sources.py` no longer copies its export and save members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the gallery's scroll
  routing moves from `Services/Notch/NotchService.swift` to
  `Services/Notch/NotchSectionScrollRoute.swift`;
  `Tests/NotchSectionPagingTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's scroll handlers.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the island's local key
  and click routing moves from `Services/Notch/NotchService.swift` to
  `Services/Notch/NotchLocalEventRoute.swift`; `Tests/NotchKeyMonitorTests.swift`
  drives it, and `Tests/generate_sources.py` no longer copies
  `installEventMonitors()`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `UI/Notch/NotchUpdateControl.swift` draws a new `NotchUpdateBadge` for a
  given state, `Services/Update/UpdateService.swift` adds `State.isOffer`,
  and `Services/Notch/NotchService.swift` names its update rule;
  `Tests/NotchUpdateTests.swift` uses them, and `Tests/generate_sources.py`
  no longer copies the control or `showUpdate()`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the menu bar panel's key
  routing moves from `App/AppDelegate.swift` to
  `Services/MenuPanelKeyRoute.swift`; `Tests/MenuPanelKeyTests.swift` drives
  it, and `Tests/generate_sources.py` no longer copies the delegate's key
  handler.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the post-update menu bar
  icon check moves from `App/AppDelegate.swift` to
  `Services/StatusItemUpdateCheck.swift`;
  `Tests/PostUpdateStatusItemRecoveryTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the delegate's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): quitting with a borrowed
  keyboard layout moves from `App/AppDelegate.swift` to
  `Services/CommandBar/CommandBarTermination.swift`;
  `Tests/CommandBarFeatureTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies `applicationShouldTerminate`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the island's queue rows
  and covers move from `Services/Notch/NotchMusicService.swift` to
  `NotchUpcomingQueue` in `Services/Notch/NotchQueueSupport.swift`;
  `Tests/NotchMusicHardeningTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's queue members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMusicAutomation.swift` takes an injected `System`, and
  the Apple Event fallback flow moves from `Services/Notch/NotchMusicService.swift`
  to `Services/Notch/NotchMusicAutomationFlow.swift`;
  `Tests/NotchMusicAutomationTests.swift` drives them, and
  `Tests/generate_sources.py` no longer copies the service's automation members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/QuickTools/QuickLauncherService.swift` takes an injected
  environment and reads keys through `QuickLauncherKey`, and
  `UI/QuickLauncher/QuickLauncherView.swift` exposes its tile icons for a
  given state; `Tests/QuickLauncherActionTests.swift` and
  `Tests/NotchDestinationTests.swift` drive them, and
  `Tests/generate_sources.py` no longer copies the launcher.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Clipboard/ClipboardHistoryService.swift` takes an injected
  environment (settings, history file, byte limit, stored images, pasteboard
  lane and search folding); `Tests/ClipboardFeatureTests.swift` drives it,
  and `Tests/generate_sources.py` no longer copies its history members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the Dock preview's
  auto-hide hold session moves from
  `Services/DockPreview/DockPreviewService.swift` to
  `Services/DockPreview/DockHoldSession.swift`;
  `Tests/DockAutohideHoldTests.swift` drives it, and
  `Tests/generate_sources.py` no longer copies the service's hold members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotQuickPreviewController.swift` takes its
    link actions from the new `Services/QuickTools/ScreenshotLinkActions.swift`
    and exposes its view model.
  - The latest-capture state moves from
    `Services/QuickTools/ScreenshotService.swift` to
    `Services/QuickTools/ScreenshotLatestCapture.swift`.
  - `Tests/ScreenshotShareCompletionTests.swift` drives both, and
    `Tests/generate_sources.py` no longer copies them.
  - `Tests/ScreenshotFeatureTests.swift` and `Tests/mutation_checks.py`
    follow the moved code.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/SuperKey/SuperKeyService.swift` takes an injected system (settings,
  event taps, tap thread, main queue, Accessibility trust, hidutil);
  `Tests/SuperKeyTapContract.swift` drives it, `Tests/PointerInputFeatureTests.swift`
  reads the new tap call, and `Tests/generate_sources.py` no longer copies it.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Notch/NotchMusicService.swift` takes an injected environment
  (adapter launch, main queue, delayed work, clock, command queue, settings,
  lyrics, Apple Events) and keeps a `NotchMusicAdapterLink` instead of the
  process and its pipes; `Tests/NotchMusicHardeningTests.swift` drives it,
  and `Tests/generate_sources.py` no longer copies it.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/KeepAwakeManager.swift` takes an injected system: settings,
    the sleep override, `pmset`, its queues and delayed work, timers, power
    assertions, the battery, the screen lock, the lid, the power manager
    and the built-in panel.
  - The `pmset disablesleep` lane, its probes and authorized restores move
    from `Sudoers` in `Services/ShellSupport.swift` to the new
    `Services/SleepOverride.swift`. `Sudoers` keeps the rule paths, the
    install command and two delegating calls.
  - `Tests/KeepAwakeLidSleepTests.swift`, `Tests/KeepAwakeClamshellTests.swift`
    and `Tests/KeepAwakeDimmingTests.swift` drive both, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the output volume and
  mute state of `Services/Audio/AppVolumeMixer.swift` moves to the new
  `Services/Audio/MixerOutputControl.swift`; `Tests/MixerOutputAdjustmentTests.swift`
  drives it, and `Tests/generate_sources.py` no longer copies the mixer's
  members (it also loses a comment left from an earlier removed block).
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `Services/Audio/AudioInputDeviceManager.swift` and
  `Services/QuickTools/MicMuteService.swift` take an injected environment
  (CoreAudio through the new `Services/Audio/AudioHAL.swift`, their queues,
  settings and feedback); `Tests/MixerInputVolumeTests.swift` drives both,
  and `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  `NowPlayingAdapter/NowPlayingSelection.swift` takes an injected platform
  (MediaRemote, the running applications, the uptime, the reply line, the
  refresh and the queue). The command switch moves there from
  `NowPlayingAdapter/NowPlayingAdapter.swift` as `perform`, and both files
  open what the test needs as `package`.
  - `Tests/NotchPlaybackRoutingTests.swift` drives the adapter's module
    (`BUILD` adds it to the test binary), and `Tests/NotchMusicHardeningTests.swift`
    reaches it through reply and request lines.
  - `Tests/generate_sources.py` no longer copies the selection.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): what running a row
  teaches `Services/CommandBar/CommandBarService.swift` moves to the new
  `Services/CommandBar/CommandBarRunRecorder.swift`, and
  `CommandBarCatalog.emojiEntries` in `Services/CommandBar/CommandBarCatalog.swift`
  takes its settings, permission and typing. `Tests/CommandBarEmojiTests.swift`
  drives both, `Tests/generate_sources.py` no longer copies them, and two
  emoji fixtures in `Tests/mutation_checks.py` follow the code to the
  recorder.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): whether the pointer
  is on a display moves into pure functions in `Core/Switcher/SpaceHopSupport.swift`,
  `Core/QuickTools/ScreenshotSupport.swift` and `Core/DockPreview/DockPreviewSupport.swift`,
  which `Services/Switcher/SpaceHop.swift`, `Services/QuickTools/ScreenshotSelectionController.swift`
  and `Services/DockPreview/DockPreviewService.swift` call.
  `Tests/PointerOnDisplayTests.swift` calls them, and `Tests/generate_sources.py`
  no longer copies the three owners.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the display under
  the pointer is read through the new `Core/ScreenGeometry.swift`.
  - Pure placement functions join `Core/WindowLayout/WindowLayoutSupport.swift`,
    `Core/QuitProtectionSupport.swift`, `Core/QuickTools/ScreenshotSupport.swift`,
    `Core/DockPreview/DockPreviewSupport.swift` and
    `Services/Switcher/SpaceWindowBridge.swift`.
  - `Services/QuickTools/ScreenshotService.swift`, `ScreenshotSelectionController.swift`,
    `Services/WindowLayout/WindowLayoutService.swift`, `Services/QuitProtection/QuitProtectionHUD.swift`
    and `Services/DockPreview/DockPreviewService.swift` call them.
  - `Tests/PointerDisplayLookupTests.swift` calls them, and
    `Tests/generate_sources.py` no longer copies the seven members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the update-intro
  sequence in `App/AppDelegate.swift` moves to the new
  `Services/Update/UpdateIntroSequence.swift`. `Core/AppInfo.swift` gains
  `isPrerelease`. `Tests/UpdateIntroFlowTests.swift` drives the sequence,
  and `Tests/generate_sources.py` no longer copies the delegate's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`): the key routing of
  `Services/QuickTools/ScreenshotQuickPreviewController.swift` and
  `Services/QuickTools/ScreenshotSelectionController.swift` moves to the new
  `Services/QuickTools/ScreenshotCaptureKeys.swift`.
  `Services/Notch/NotchService.swift` gains `CaptureFocus` behind
  `isCaptureVisible(id:)`. `Tests/NotchCaptureKeyboardTests.swift` calls
  them, and `Tests/generate_sources.py` no longer copies the monitors.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/Uninstall/AppUninstaller.swift` gains an injected
    `Environment` and a `PackageManager` protocol (`HomebrewManager`
    adopts it). Its scan and removal bodies move unchanged into
    `scan(_:)` and `remove(_:)`.
  - The command bar's uninstall review moves from
    `Services/CommandBar/CommandBarService.swift` to the new
    `Services/CommandBar/CommandBarUninstallReview.swift`.
  - `FinderBridge.selectionURLs` in
    `Services/Finder/FinderCutPaste.swift` takes an `Automation`.
  - `Tests/UninstallerFlowTests.swift` drives them, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/Display/BrightnessService.swift` takes an injected
    `Environment`. Its display-side platform calls go through it: queues,
    preferences, clock, displays, system brightness, DDC, gamma, the
    reconfiguration call and the lid.
  - The lid's IOKit subscription moves into a nested `LidObservation`.
  - `start()` and `step` become package-visible.
  - `Tests/DisplayRestorationTests.swift`, `Tests/BrightnessStepTests.swift`
    and `Tests/SoftwareDimmingRouteTests.swift` drive the service over the
    new `Tests/BrightnessRig.swift`, and `Tests/generate_sources.py` no
    longer copies its members.
  - `Tests/FeatureCatalogTests.swift`: the reconfiguration checks read
    `configureDisplay`, where the main-thread, built-in and lid guards now
    sit in front of the environment's transaction.
  - `Tests/RecorderExportRenderingTests.swift` names the export failure.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `RecorderEditorModel` in
    `Services/Recorder/RecorderEditorController.swift` takes an injected
    `Environment`: its preferences, how the recording's facts are read
    when it opens, and how the preview's composition is made.
  - `Tests/RecorderZoomAimingTests.swift` drives the model, and
    `Tests/generate_sources.py` no longer copies its members.
  - A source-text check in `Tests/RecorderFeatureTests.swift` (a redrawn
    blur keeps its strength) becomes a behavioral check there.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - `Services/QuickTools/ScreenshotSelectionController.swift` takes an
    injected `Environment`: the displays, the pointer, the preferences, the
    capture engine's calls and how the panels reach the screen. A panel is
    built from an `Environment.Display` instead of an `NSScreen`.
  - The panel and overlay view become package-visible, with the
    confirmations and the state their checks read.
  - `Services/QuickTools/ScreenCaptureService.swift`: the capture-controls
    forwarding is a static that takes whether the session is current.
  - `Tests/ScreenshotSelectionRefreshTests.swift` drives the controller, and
    `Tests/generate_sources.py` no longer copies it.
  - `Tests/MetricsTests.swift` line-buffers its output, so a crash still
    shows which suites finished.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The island stepping aside for a full-screen Space moves from
    `Services/Notch/NotchService.swift` to the new
    `Services/Notch/NotchFullscreenVisibility.swift`.
  - `Services/Audio/PreciseVolumeRollerService.swift` takes an injected
    `Environment`: its preference, whether the island takes the volume keys,
    Accessibility, the session and the event tap's creation.
  - `Tests/NotchFullscreenTests.swift` drives both, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The island's deferred preference and screen passes, its menu reader's
    schedule, its response to another app coming forward and its move to
    another display go from `Services/Notch/NotchService.swift` to the new
    `Services/Notch/NotchScreenRefresh.swift`.
  - `Tests/NotchScreenRefreshTests.swift` drives it, and
    `Tests/generate_sources.py` no longer copies those members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The drag handling of the private canvas view in
    `Services/Notch/NotchWindowHost.swift` goes to the new
    `Services/Notch/NotchCanvasDrop.swift`. The canvas forwards to it.
  - `Tests/ShelfDropRoutingTests.swift` drives it, and
    `Tests/generate_sources.py` no longer copies the canvas.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The rule for when the island takes files goes from
    `Services/Notch/NotchService.swift` to
    `Services/Notch/NotchFileDrop.swift`. `canAcceptFileDrop` forwards.
  - `Tests/ShelfDropRoutingTests.swift` drives it, and
    `Tests/generate_sources.py` no longer copies the island's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - Where a shelf drop goes moves from `Services/Shelf/ShelfService.swift`
    to the new `Services/Shelf/ShelfDropIntake.swift`. `acceptDrop`,
    `accept(draggingInfo:)` and `merge(draggingInfo:into:)` forward to it.
  - The shelf's `fileURLs(from:)` reader moves to `ShelfPasteboardSupport`
    in `Core/Shelf/ShelfSupport.swift`, and `ShelfService` forwards to it.
  - `Tests/ShelfDropRoutingTests.swift` drives the intake, and
    `Tests/generate_sources.py` no longer copies the shelf's members.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - What the island's media tools take as a drop goes from
    `Services/Notch/NotchFileToolsService.swift` to the new
    `Services/Notch/NotchMediaDrop.swift`. The service forwards to it.
  - The service takes an injected `Environment` for its switches.
  - `Tests/ShelfDropRoutingTests.swift` and
    `Tests/MediaWorkspaceLayoutTests.swift` drive the module's own types,
    and `Tests/generate_sources.py` no longer writes `ShelfDropRouting.swift`.
- **2026-10-05**: Refactor step 4b (`REFACTOR.md`):
  - The preview and title strips in `UI/Switcher/SwitcherView.swift` use
    the new `UI/Switcher/SwitcherWindowStrip.swift`, which holds their
    scroll view and selection reveal.
  - The search filter in `Services/Switcher/AppSwitcher.swift` moves to
    `SwitcherSupport.searchResult` in `Core/Switcher/SwitcherSupport.swift`.
  - `Tests/SwitcherScrollTests.swift` drives both, `Tests/mutation_checks.py`
    points its two switcher mutations at the new file, and
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 6zzo (`REFACTOR.md`):
  - `Core/Defaults.swift` registers 12 more preferences:
    - the Auto Quit, cut-and-paste and shelf switches;
    - the six menu bar metric switches;
    - the onboarding step;
    - the command bar's links and row shortcuts.

    Each is registered with the empty value its views already assumed.
  - Their `@AppStorage` properties take the `Preference`, in:
    - `UI/MenuBarMetricsPreview.swift`;
    - `UI/MenuPanel/MenuPanelView.swift`;
    - `UI/Onboarding/OnboardingView.swift`;
    - the Auto Quit, command bar, cut-and-paste, monitor and shelf
      settings views.
- **2026-10-05**: Refactor step 5m (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` takes a `NotchService.Environment`
    with the preferences it reads; `.shared` passes the standard ones. Its
    defaults reads, `NotchSupport` queries, feature checks and the lock
    screen's sound check go through them.
  - `Tests/generate_sources.py` reads the island's text with that argument
    taken out, so its copies are unchanged, and `Tests/mutation_checks.py`
    names the new text in one mutation.
- **2026-10-05**: Refactor step 5n (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` holds its window as the new
    `NotchIslandHost` (`Services/Notch/NotchIslandHost.swift`), built by
    `Environment.makeHost`; `.system` builds the `NotchWindowHost` as before.
  - Its one `present` call passes `hideWhenSettled: false`, the default it
    used, and `Tests/NotchPresentationRefreshTests.swift`'s stand-in window
    takes that argument.
- **2026-10-05**: Refactor step 5o (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` reads the pointer and Reduce Motion,
    and schedules its main-queue timers, through `NotchService.Environment`;
    `.system` passes the system calls it used.
  - `Tests/generate_sources.py` maps those back when it copies the island.
- **2026-10-05**: Refactor step 5p (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` calls the services it uses through
    the new `NotchIslandServices` (`Services/Notch/NotchIslandServices.swift`),
    whose `SystemNotchIslandServices` forwards to the shared instances.
  - `Tests/generate_sources.py` maps the members back when it copies the
    island.
- **2026-10-05**: Refactor step 5q (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` takes its last shared-service
    readings through `NotchIslandServices`: the calendar, the watch, the
    timer's clock, the artwork, the scratchpad and the tools page.
- **2026-10-05**: Refactor step 5r (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` reads displays as the new
    `NotchDisplayInfo` (`Services/Notch/NotchDisplayInfo.swift`) through its
    environment; `.system` builds them from `NSScreen`.
- **2026-10-05**: Refactor step 5s (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` builds its movement watches, event
    bindings, volume feedback, menu reader, pointer follower, screen
    refresh, full-screen visibility, screen-edge clicks, file drop and
    session tracker from `Environment.Parts`, and observes and posts through
    the notification centers there; `.system` passes the system's.
- **2026-10-05**: Refactor step 5t (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` reads its remaining preferences
    through the defaults it was built with, and asks `NotchIslandServices`
    for the modal window, the status item, the Accessibility Keyboard, the
    popover, settings and the update preview.
- **2026-10-05**: Refactor step 5u (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` asks its window for the keyboard
    through `NotchIslandHost` (`hasKeyboard`, `takeKeyboard()`,
    `releaseKeyboard()`) and installs the open island's click and key
    monitors through `Environment.Parts.openEvents`, the new
    `NotchOpenEvents` (`Services/Notch/NotchOpenEvents.swift`); `.system`
    passes the panel's own calls and `NSEvent`'s monitors.
  - `Tests/generate_sources.py` maps the keyboard calls back when it copies
    the island.
- **2026-10-05**: Refactor step 5v (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` builds its copies' windows through
    `Environment.makeMirror`, reads full-screen displays through
    `Environment.Parts.fullscreenDisplays` and the battery through
    `Environment.hasBattery`; `.system` passes what it used before.
  - `Tests/generate_sources.py` maps the battery back when it copies the
    island.
- **2026-10-05**: Refactor step 4b, the island's destinations (`REFACTOR.md`):
  - `Tests/NotchDestinationTests.swift` drives a real island built by the
    new `Tests/NotchIslandFixture.swift`, not compiled copies of its
    opening, step-back and session members.
  - `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the island's music reader (`REFACTOR.md`):
  - `Tests/NotchMusicVisibilityTests.swift` drives a real island from
    `Tests/NotchIslandFixture.swift`, not compiled copies of its
    presentation and consumer members.
  - `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 5w (`REFACTOR.md`):
  - `Services/Notch/NotchWindowHost.swift` keeps whether its panel takes the
    mouse, through Mission Control and a settling hide, in the new
    `NotchWindowInputPolicy` (`Services/Notch/NotchWindowInputPolicy.swift`).
- **2026-10-05**: Refactor step 4b, the island's presentation (`REFACTOR.md`):
  - `Tests/NotchPresentationRefreshTests.swift` and
    `Tests/NotchCaptureControlsTests.swift` drive a real island from
    `Tests/NotchIslandFixture.swift`, not compiled copies of its refresh,
    capture and departure members or the window host's restore.
  - `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the island's hover (`REFACTOR.md`):
  - `Tests/NotchHoverTests.swift` drives a real island from
    `Tests/NotchIslandFixture.swift`, not compiled copies of its hover,
    notice and hidden-hover members.
  - `Tests/generate_sources.py` no longer copies them, drops its map of the
    island's environment and services, which no copy uses any more, and
    deletes generated files it no longer writes.
- **2026-10-05**: Refactor step 4b, the compact calendar rows and rail (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Notch/NotchCalendarView.swift`: `NotchCalendarEventRow`
    is `package` and spells out its initializer.
  - `Sources/Vitruvian/UI/Notch/NotchComponents.swift`: `NotchRail` spells out
    its initializer.
  - `Tests/NotchCompactTests.swift` renders both real views;
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the compact camera page and page sizing (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Notch/NotchCameraView.swift`: the view takes its
    camera (the new `NotchEmbeddedCamera`, which `CameraPreviewService`
    adopts) and preview; `init(size:)` passes the app's.
  - `Sources/Vitruvian/UI/Notch/NotchView.swift`: `pageSize` calls the new
    `NotchLayout.pageSize` (`Core/Notch/NotchPageSize.swift`), which holds
    the rule it held.
  - `Tests/NotchCompactTests.swift` tests both on the real code;
    `Tests/generate_sources.py` no longer copies them.
- **2026-10-05**: Refactor step 4b, the compact scratchpad (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/QuickTools/ScratchpadService.swift`: its
    `Environment` carries the `defaults` it reads its preferences from.
    `focusText` goes through the new `ScratchpadFocus`
    (`Services/QuickTools/ScratchpadFocus.swift`).
  - `Sources/Vitruvian/UI/Notch/NotchScratchpadView.swift` and
    `Sources/Vitruvian/UI/Scratchpad/ScratchpadFormatBar.swift` take their pad,
    defaulting to the shared one. The island page places its caret through
    `ScratchpadFocus`.
  - `Tests/NotchCompactTests.swift` tests the real page and focus rules;
    `Tests/ScratchpadStoreContractTests.swift`'s harness passes its own
    defaults; `Tests/mutation_checks.py` mutates the focus guard where it
    now lives; `Tests/generate_sources.py` no longer copies any of it.
- **2026-10-05**: Refactor step 4b, the menu panel's presentation (`REFACTOR.md`):
  - `Sources/Vitruvian/App/AppDelegate.swift`: the panel's placement,
    drift correction, close, foreign-close recovery and Settings placement
    move, with their state, to the new `MenuPanelPresenter`
    (`Services/MenuPanel/MenuPanelPresenter.swift`). `AppDelegate` builds it
    over AppKit and its own hooks, and forwards the popover's close
    callbacks to it.
  - `Tests/MenuPanelRecoveryTests.swift` drives the real presenter instead of
    a compiled copy over shadowed AppKit types.
  - `Tests/generate_sources.py` copies nothing any more; it writes the
    localization registry.
- **2026-10-05**: Refactor step 5x (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` keeps its notice in the new
    `NotchNoticeQueue` (`Services/Notch/NotchNoticeQueue.swift`), which decides
    which notice may show and how it arrives and leaves.
  - `Tests/NotchTests.swift` runs the new `Tests/NotchNoticeQueueTests.swift`.
- **2026-10-05**: Refactor step 5l (`REFACTOR.md`):
  - `Services/Notch/NotchService.swift` keeps its capture controls in the new
    `NotchCaptureControlsState` (`Services/Notch/NotchCaptureControlsState.swift`),
    which decides the clicks they take and what the pointer does to them.
  - `Tests/NotchTests.swift` runs the new
    `Tests/NotchCaptureControlsStateTests.swift`.
- **2026-10-05**: Refactor step 7b, the Command Bar catalog (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift`: the
    clipboard clear, keep awake, restart and volume confirmation rows come
    from their own builders (`clipboardClearEntry`, `keepAwakeEntries`,
    `restartAppEntry`, `confirmVolume`) with their actions passed in.
    `toggleEntries` and the uninstall rows read the `defaults` they are
    given; the Finder selection row is told whether the app is in
    Applications and whether the uninstaller takes it; `windowEntries` is
    given the frontmost app, the beat and the activation. `afterBeat` is
    package. Every caller passes the live values, so the bar behaves as before.
  - `Tests/CommandBarFeatureTests.swift`, `Tests/PointerInputFeatureTests.swift`
    and `Tests/SwitcherModelFeatureTests.swift` no longer read the catalog's
    source; the new `Tests/CommandBarCatalogRowTests.swift` builds the rows and
    runs them. `Tests/KeepAwakeCatalogTests.swift` is gone with its
    registration in `Tests/MetricsTests.swift`; its checks are among the new
    ones.
- **2026-10-05**: Refactor step 5y (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/Notch/NotchService.swift`,
    `Sources/Vitruvian/UI/Notch/NotchView.swift` and
    `Sources/Vitruvian/UI/Notch/NotchMusicView.swift` read the music page's
    row of controls from the new `NotchMusicControls`
    (`Core/Notch/NotchMusicControls.swift`). Lyrics and the queue count from
    their switches and features in the size as in the drawing, so the
    Settings preview no longer squeezes the player.
  - `Sources/Vitruvian/Core/Notch/NotchNotificationSupport.swift` adds
    `NotchNotificationBannerLayout.iconSide(stripHeight:)`, which
    `Sources/Vitruvian/UI/Notch/NotchNoticeView.swift` draws the banner's
    icon with.
  - `Tests/NotchCompactTests.swift` and `Tests/NotchTests.swift` check both.
- **2026-10-05**: Refactor step 5z (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchGeometry.compactReadingInset(textSize:)`. `Services/Notch/NotchService.swift`,
  `Core/Notch/NotchKeepAwakeSupport.swift`, `Core/Notch/NotchDownloadSupport.swift`
  and the timer, agent, keep awake and watch strips in `UI/Notch/` use it
  instead of spelling the digits' inset out.
- **2026-10-05**: Refactor step 5za (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds `NotchControlGroups`.
  `Services/Notch/NotchService.swift`, `Core/Notch/NotchPageSize.swift`,
  `UI/Notch/NotchControlsView.swift` and `UI/Settings/NotchLayoutEditor.swift`
  split the home page's controls with it instead of their own filters.
- **2026-10-05**: Refactor step 5zb (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.musicControlsRow(_:)`, `musicMainHeight(hasPlayback:layout:height:)`
  and `musicPlayerMinimumHeight`, used by its own sizing,
  `Core/Notch/NotchPageSize.swift` and `UI/Notch/NotchMusicView.swift`.
- **2026-10-05**: Refactor step 5zc (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchNoticeLayout.swift` adds `minimumWing`.
  `Core/Notch/NotchNotificationSupport.swift` takes the banner's inset and the
  low end of its range from `NotchNoticeLayout`, and
  `Services/Notch/NotchService.swift` a text notice's narrowest wing.
  `Tests/mutation_checks.py` quotes the changed line.
- **2026-10-05**: Refactor step 5zd (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` names the peek's height
  and adds `NotchLayout.scrollBottomPadding`, `captureCollapsedSide`,
  `dropHintHeight`, `dropHintBottomGap` and `NotchGeometry.dropPlaceholder`
  and `collapsedCaptureControls`. `Core/Notch/NotchDownloadSupport.swift` adds
  `companionWing`. `Services/Notch/NotchService.swift`, `UI/Notch/NotchView.swift`
  and `UI/Notch/NotchTimerStrip.swift` use them instead of the numbers.
- **2026-10-05**: Refactor step 5ze (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.iconButtonSide` and `headerButtonSpacing` and measures the
  header with them. `UI/Notch/NotchComponents.swift` (`NotchIconButton`) and
  `UI/Notch/NotchView.swift`'s header draw with them.
- **2026-10-05**: Refactor step 5zf (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds the lyrics and queue
  cards' padding, spacing, title height and `musicExtraListHeight(_:)`, which
  `UI/Notch/NotchLyricsView.swift` and `UI/Notch/NotchQueueView.swift` draw with.
- **2026-10-05**: Refactor step 5zg (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.displaySideMargins`, `displayBottomMargin` and
  `NotchGeometry.maximumSurfaceWidth`/`maximumSurfaceHeight`, and its sizing
  uses them. `Services/Notch/NotchService.swift` (the activity picker) and
  `Services/Notch/NotchLockScreenSupport.swift` do too.
- **2026-10-05**: Refactor step 5zh (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchGeometry.compactMarkInset(side:)`, `NotchLayout.compactMarkWing` and
  `compactReadingWing`.
  - The mark's inset is measured with the new rule in
    `Services/Notch/NotchService.swift` and in `Core/Notch/NotchKeepAwakeSupport.swift`,
    `NotchDownloadSupport.swift` and `NotchAgentSupport.swift`.
  - It is drawn with it in the timer, keep awake, watch, agent and download
    views (`UI/Notch/`). Those strips and the calendar strip use the named
    wing widths.
- **2026-10-05**: Refactor step 5zi (`REFACTOR.md`):
  `Sources/Vitruvian/Core/Notch/NotchSupport.swift` adds
  `NotchLayout.systemGridHeight(count:width:)` in place of
  `NotchGeometry.systemRows(cards:)`; `UI/Notch/NotchSystemView.swift` uses it.
- **2026-10-05**: Refactor step 6zzp (`REFACTOR.md`): 30 `@AppStorage`
  properties take their `Preference` instead of `DefaultsKey` and a written
  default, in `UI/MenuBarMetricsPreview.swift`, `UI/MenuPanel/PanelClipboardView.swift`,
  `UI/MenuPanel/PanelWindowLayoutView.swift`, `UI/Notch/NotchAgentStrip.swift`,
  `UI/Notch/NotchAgentsView.swift`, `UI/Notch/NotchCapsuleViews.swift`,
  `UI/Notch/NotchClipboardView.swift`, `UI/Notch/NotchLockScreenView.swift`,
  `UI/QuickLauncher/QuickLauncherView.swift` and the Clipboard, Keyboard
  Debounce, Monitor, Notch Agents, Notch, Screenshot, Shelf and Switcher
  settings (`UI/Settings/`).
- **2026-10-05**: Refactor steps 7c and 6zzq (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Settings/MouseButtonSettings.swift` decides its
    captures, prompts and refusals, the drag's binding and its exception
    list through the new `MouseButtonCapture`
    (`Core/MouseButtons/MouseButtonCapture.swift`).
    `UI/Settings/MouseSettings.swift` and `UI/MenuPanel/MenuPanelView.swift`
    read whether either mouse-button switch is on from it.
  - Those three views take the mouse-button, smooth scrolling and clipboard
    switches from their `Preference`, as `UI/Switcher/SwitcherView.swift`
    takes the window shortcut and `UI/Settings/CommandBarSettings.swift` the
    disabled sources.
  - `Tests/PointerInputFeatureTests.swift` no longer reads the three views;
    `Tests/MouseButtonCaptureTests.swift` (run from `Tests/MetricsTests.swift`)
    checks the rules.
- **2026-10-05**: Refactor step 5zj (`REFACTOR.md`):
  - `Sources/Vitruvian/Core/Notch/NotchSupport.swift` names the running
    timer's sizes, the music card's and the activity picker's label and
    chrome.
  - `Core/Notch/NotchAgentSupport.swift` adds `pageProviders(seen:)` and
    `pageRows(providers:width:)`.
  - `Core/Shelf/ShelfSupport.swift` holds the shelf tile's size, spacing and
    inset, which `UI/Shelf/ShelfTilesView.swift` now reads.
  - `Core/Notch/NotchPageSize.swift`, `Services/Notch/NotchService.swift` and
    the timer, music, files, agents and island views (`UI/Notch/`) use them.
- **2026-10-05**: Refactor step 7d (`REFACTOR.md`):
  - `Sources/Vitruvian/Services/FeatureRuntime.swift` takes an `Environment`
    (defaults, binding performer, change follow-up, saved domain), with the
    live one for `.shared`. Each feature's binding is a list of
    `FeatureBindingAction`s from `actions(for:in:)`, which `perform` runs on
    the live services in the same order as before.
  - `Tests/FeatureCatalogTests.swift`, `Tests/PointerInputFeatureTests.swift`
    and `Tests/ScreenshotFeatureTests.swift` no longer read it. The new
    `Tests/FeatureRuntimeTests.swift`, run from `Tests/MetricsTests.swift`,
    checks the runtime on its own defaults.
- **2026-10-05**: Refactor step 7e (`REFACTOR.md`):
  - `Sources/Vitruvian/UI/Settings/FeatureHubSettings.swift` undoes the
    never-used offer through the new `FeatureRuntime.reinstallKept(_:)`
    (`Services/FeatureRuntime.swift`).
  - The new `Tests/source_pins.txt` counts the tests' reads of source files,
    which the new `Tests/SourcePinLedgerTests.swift` (run from
    `Tests/MetricsTests.swift`) recounts.
  - `Tests/FeatureCatalogTests.swift` drops the undo's source read, and
    `Tests/FeatureRuntimeTests.swift` checks it instead.
- **2026-10-05**: Refactor step 7f (`REFACTOR.md`):
  - `Tests/MetricsTests.swift` takes its suites from the new
    `Tests/TestGroups.swift` instead of listing them itself, so the new
    `Tests/SwiftTesting/UnitTests.swift` runs the same list through Swift
    Testing.
  - `Tests/TestSuite.swift` (the harness checks) checks that the names
    Swift Testing lists match the runner's suites, in order.
- **2026-10-05**: Refactor step 4c (`REFACTOR.md`): test stand-ins no
  longer take the names of the types they stand in for.
  - `Tests/NotchScreenRefreshTests.swift`: `DispatchQueue`, `NSWorkspace`,
    `Bundle`, `NSEvent`, `NSScreen` and `ClipboardHistoryService` become
    `Clock`, `Frontmost`, `OwnApp`, `Pointer`, `Display` and `Clipboard`.
  - `Tests/ShelfDropRoutingTests.swift`: `AppFeature`, `NotchSupport`,
    `UserDefaults` and `ShelfService` become `Features`, `IslandModules`,
    `Switches` and `Shelf`.
  - `Tests/NotchAudioLevelTests.swift` (`RecordingReader`),
    `Tests/NotchVolumeFeedbackTests.swift` (`Mixer`),
    `Tests/UpdateIntroFlowTests.swift` (`IntroShell`) and
    `Tests/WindowServerCaptureTests.swift` (`Connection`,
    `CaptureFunction`).
  - The new `Tests/TestDoubleNameTests.swift` keeps it so.
- **2026-10-05**: Refactor step 6zzr (`REFACTOR.md`): five more
  `@AppStorage` properties take their `Preference` instead of a
  `DefaultsKey` and a written-out default.
  - `Sources/Vitruvian/UI/Notch/NotchTimerView.swift` (the timer mode) and
    `Sources/Vitruvian/UI/Settings/MouseSettings.swift` (the horizontal
    scroll modifier) read theirs as enums, through a new `@AppStorage`
    initializer in `Design/PreferenceStorage.swift`.
  - `Sources/Vitruvian/UI/Settings/CommandBarSettings.swift` (ASCII
    layout) and `Sources/Vitruvian/UI/Settings/WindowLayoutSettings.swift`
    (side repeat, disabled snap zones).
  - `Tests/CommandBarFeatureTests.swift` and
    `Tests/WindowLayoutFeatureTests.swift` look for the `Preferences` name
    in those views.
- **2026-10-05**: Refactor step 7g (`REFACTOR.md`): Swift Testing runs the
  unit tests.
  - `Tests/MetricsTests.swift`, the `@main` runner, is deleted. Its suites
    run from `Tests/TestGroups.swift` through
    `Tests/SwiftTesting/UnitTests.swift`.
  - `Tests/TestSuite.swift` drops `finish()`, which only that runner
    called.
  - `build.sh --test` still names `Tests/*.swift`. It has not built since
    the tests import the app's modules, and is unchanged.
- **2026-10-06**: Refactor step 7h (`REFACTOR.md`): source pins turned
  behavioral, first part. Each change puts a rule a test read as text
  behind a seam the code calls, with no change in behavior.
  - `build.sh`: the Developer build's fan helper rename is the function
    `rename_fan_helper`. `Tools/uninstall.sh`: its removal, rule search and
    sleep read are the functions `remove_user_state`,
    `find_closed_lid_rules` and `read_sleep_disabled`.
  - `Services/SelfUninstall.swift` (`ownedPaths`, `restoreSleep`),
    `Services/ShellSupport.swift` (`Sudoers.ruleFiles`),
    `Services/Metrics/DiskSampler.swift` (`volumeKeys`, `importantFree`
    made `package`), `Services/Homebrew/HomebrewManager.swift`
    (`awaitExit`).
  - Recorder: `Services/Recorder/RecorderComposer.swift` and
    `RecorderExporter.swift` take the filtering composition as a
    `FilteredComposition`; `RecorderTypingTrack.swift` adds `record(at:)`.
  - Command bar and keyboard: `Services/CommandBar/CommandBarService.swift`
    (`CommandBarKeys`), `CommandBarCatalog.swift` (`storeBootVolumeSpace`,
    `storeSystemAnswers`), `Services/ShortcutCapture.swift`
    (`ShortcutListening`, also used by `UI/ShortcutRecorderButton.swift`),
    `UI/CommandBar/CommandBarView.swift` (`examples(_:hasBattery:)`),
    `Core/GlobalShortcut.swift` (`KeycapLayoutSource`),
    `Core/InputSourceSelection.swift` (`selectNextSource`, used by
    `Services/SuperKey/SuperKeyService.swift`).
  - `App/AppDelegate.swift`: Settings' Command Tab presence goes through
    `WindowActivationClaim` (`Services/QuickTools/WindowActivationPolicy.swift`),
    the permission sinks through `FeatureRuntime.permissionDidChange(_:)`,
    and the quit's input releases through `QuitInputRelease`
    (`Services/FeatureRuntime.swift`).
  - `UI/Onboarding/OnboardingView.swift` (`OnboardingFeatureNames`),
    `Services/CleaningMode/CleaningUnlockCounter.swift`
    (`shippedPressWindow`) and `CleaningModeManager.swift`, whose session
    and disabled-tap decisions move to the new
    `CleaningSessionSupport.swift`.
  - Pointer input: `Core/MouseButtons/MouseButtonShortcutSupport.swift` and
    `MouseSpacesGestureSupport.swift`,
    `Services/MouseButtons/MouseButtonShortcutService.swift`,
    `Services/Switcher/SpaceWindowBridge.swift`,
    `Core/SuperKey/SuperKeySupport.swift` (`SuperKeyMouseTapRefusals`),
    `Services/SuperKey/SuperKeyService.swift`,
    `UI/Settings/SuperKeySettings.swift` (`SuperKeyStatusLine`),
    `Core/FocusFollowsMouse/FocusFollowsMouseSupport.swift`,
    `Services/FocusFollowsMouse/FocusFollowsMouseService.swift`,
    `Core/MouseExceptions/MouseAppExceptionSupport.swift`,
    `Services/MouseExceptions/MouseAppExceptions.swift`,
    `Services/InstalledApps.swift`, `UI/Settings/AppBundleList.swift`,
    `UI/Uninstall/AppPickerView.swift`,
    `Services/SessionActivitySupport.swift` (`TapCreationRetry`, used by
    `Services/ScrollInverter.swift` and `SmoothScrollService.swift`),
    `Services/MouseAcceleration/MouseAccelerationService.swift`.
  - Floating panels: each surface builds its panel through a `package`
    factory that the tests build: `App/AppDelegate.swift` (through
    `AppKitMenuPanel.makePositioningPanel`), `UI/PermissionGuideOverlay.swift`,
    `Services/CleaningMode/CleaningModeManager.swift`,
    `Services/Recorder/RecorderIndicator.swift`,
    `Services/QuitProtection/QuitProtectionHUD.swift`,
    `Services/Clipboard/ClipboardHistoryService.swift`,
    `Services/CommandBar/CommandBarService.swift`,
    `Services/RadialMenu/RadialMenuService.swift` and
    `RadialNowPlayingService.swift`, `Services/Switcher/AppSwitcher.swift`,
    `Services/DockPreview/DockPreviewService.swift`,
    `Services/Finder/FinderCutPaste.swift`,
    `Services/Display/BrightnessOSD.swift`,
    `Services/Snippets/SnippetLibraryService.swift`,
    `Services/WindowLayout/WindowLayoutService.swift`,
    `Services/DiskImageInstaller/DiskImageInstallerService.swift`, and in
    `Services/QuickTools/`: `QuickToolHUD`, `QuickLauncherService`,
    `CameraPreviewService`, `RecentCaptureService`, `ScratchpadService`,
    `QRResultController`, `ScreenshotQuickPreviewController`;
    `ScreenshotPinController.swift`'s window is `package`.
  - Shelf: `Core/Shelf/ShelfSupport.swift` (`ShelfDragWatchdog`,
    `ShelfDismissal`, `ShelfStoreLoad.isWhole`),
    `Services/Shelf/ShelfService.swift` (`dismiss(_:)`, `makePanel()`),
    `ShelfTooltipPopover.swift`, `UI/Shelf/ShelfView.swift` (a `dismissal`
    instead of an `onDismiss` closure) and `ShelfDropZoneView.swift`.
  - Elsewhere: `Services/HorizontalWheelScrolling.swift`,
    `Services/Notch/NotchWindowHost.swift` (`NotchPanel.takesScroll`),
    `Core/Notch/NotchWatchSupport.swift` and
    `Services/Notch/NotchWatchService.swift` (`NotchWatchLastReading`,
    `areaPicture`), `Services/QuickTools/PastePlainService.swift`,
    `Services/SettingsBackup.swift` (`restore(_:into:)`),
    `Core/WindowLayout/WindowLayoutSupport.swift` and
    `Services/WindowLayout/WindowLayoutService.swift`
    (`WindowLayoutSettledFrames`), `Services/Audio/MixerRender.swift` and
    `AppVolumeMixer.swift` (`renderCycle`, `MixerEngineTeardown`),
    `UI/KeepAwakeAutomationView.swift` (`KeepAwakeMatchModePicker`).
  - The suites that read those files as text check the code instead:
    `ShelfFeatureTests`, `OverlayPanelTests`, `ScrollHorizontalModifierTests`,
    `NotchScreenRefreshTests`, `NotchWatchTests`, `ClipboardFeatureTests`,
    `SettingsFeatureTests`, `WindowLayoutFeatureTests`,
    `PreferencesFeatureTests`, `MixerFeatureTests`,
    `LocalizationFeatureContractTests`, `NotchTests`,
    `PreferenceNamespaceTests`, `RepositoryFeatureTests`,
    `RecorderFeatureTests`, `RecorderExportRenderingTests`,
    `CommandBarFeatureTests`, `KeyboardFeatureTests`,
    `FeatureCatalogTests` and `PointerInputFeatureTests`.
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
