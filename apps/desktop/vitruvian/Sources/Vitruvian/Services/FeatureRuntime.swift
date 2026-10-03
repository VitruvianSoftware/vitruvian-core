// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign

/// Bridges the pure feature catalog to the live singletons. Every binding is
/// a closure, so merely mentioning a feature never instantiates its service:
/// a service only comes to life when its binding runs, and syncAtLaunch skips
/// unavailable features entirely — switched off in the hub means nothing
/// loads and nothing runs after the next launch. Main thread only, like the
/// services it drives.
package final class FeatureRuntime: ObservableObject {
    package static let shared = FeatureRuntime()

    /// Bumped on every availability change; views observing the runtime
    /// re-read the catalog when it moves.
    @Published package private(set) var revision = 0

    /// Every feature that came to life in THIS process: available at launch
    /// or installed later in the session. A feature uninstalled mid-session
    /// stops working immediately, but its (inert) singleton only leaves
    /// memory on the next launch — this set is what the hub's restart banner
    /// keys off, including the install-then-uninstall-again case.
    private var loadedThisSession = Set(AppFeature.allCases.filter(\.isAvailable))

    /// What was installed when the app came up and has not been installed
    /// again since. A feature installed later in the session, a reinstall
    /// included, has not had its chance yet, so it is never offered for
    /// uninstalling as unused until the next launch.
    private var offerableThisSession = Set(AppFeature.allCases.filter(\.isAvailable))

    private init() {}

    /// True while something that loaded this session is now uninstalled, so
    /// a restart would actually unload it. Features already uninstalled when
    /// the app came up never loaded, so they need no restart.
    package var needsRestartToUnload: Bool {
        loadedThisSession.contains { !$0.isAvailable }
    }

    /// Relaunches the app in place: a detached helper waits for this process
    /// to be gone and only then reopens it, so the fresh instance starts
    /// without the uninstalled features.
    ///
    /// It waits for the process rather than for a fixed moment because
    /// quitting flushes the clipboard history and every other pending write
    /// first: a reopen that arrives while the app is still here does nothing,
    /// and the restart ends as a plain quit.
    package func relaunchApp() {
        let path = Bundle.main.bundlePath
        // Its own session: the reopen fires after we terminate, so the child
        // has to outlive the session it was started from. It gives up if we
        // are somehow still here after twenty seconds, so a quit that never
        // happens cannot reopen the app long afterwards.
        let script = """
            waited=0
            while kill -0 "$1" 2>/dev/null && [ "$waited" -lt 100 ]; do
                sleep 0.2
                waited=$((waited + 1))
            done
            kill -0 "$1" 2>/dev/null || /usr/bin/open "$2"
            """
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        // Nothing is quit until the helper is running: without it, terminating
        // would close the app instead of restarting it.
        guard (try? DetachedProcess.spawn(
            "/bin/sh", ["-c", script, "vitruvian-relaunch", pid, path])) != nil
        else { return }
        NSApp.terminate(nil)
    }

    package func isAvailable(_ feature: AppFeature) -> Bool { feature.isAvailable }

    package var availableCount: Int { AppFeature.allCases.filter(\.isAvailable).count }

    /// How many features this Mac can end up with. Counting against the whole
    /// catalog instead would leave the hub's install-all button forever one
    /// short of its own disabled condition on a Mac missing some hardware.
    /// An install that predates the check still counts, so the tally can
    /// never read more installed than installable.
    package var installableCount: Int {
        AppFeature.allCases.filter { $0.isHardwareSupported || $0.isAvailable }.count
    }

    /// The one gate every install passes, whichever surface asks: the hub
    /// row, the hub's install-all button, a preset and the first-run picker
    /// all decide here. A feature the Mac cannot run never installs, so a
    /// disabled row cannot be walked around from the button above it.
    ///
    /// Uninstalls are never refused and an existing install is never revoked:
    /// the check reads hardware and can be wrong, and a wrong answer that
    /// strands someone's settings costs far more than one that leaves a
    /// feature reporting itself unsupported.
    private func mayFlip(_ feature: AppFeature, to available: Bool) -> Bool {
        guard feature.isAvailable != available else { return false }
        return !available || feature.isHardwareSupported
    }

    /// Flipping availability runs each feature's binding immediately, in the
    /// order given: off tears every resource down on the spot, while a first
    /// install turns on the feature's main control. Saved choices survive a
    /// reinstall. One row, the "all" buttons and the Dynamic Island leaving
    /// with its extensions all pass through here, with one revision bump.
    /// Install all leaves enable keys alone: it would otherwise switch on
    /// intrusive features nobody picked, such as focus follows mouse.
    package func setAvailable(_ features: [AppFeature], _ available: Bool,
                      enablingFirstInstalls: Bool = true) {
        var changed = false
        let firstIslandInstall = available && features.contains(.notch)
            && mayFlip(.notch, to: true)
            && !UserDefaults.standard.bool(forKey: DefaultsKey.notchInitialExtensionsInstalled)
        let requested = firstIslandInstall
            ? features + AppFeature.dynamicIslandExtensions.filter { !features.contains($0) }
            : features
        let savedValues = savedPreferences()
        for feature in requested where mayFlip(feature, to: available) {
            if available && enablingFirstInstalls {
                feature.enableOnFirstInstall(in: .standard, savedValues: savedValues)
            }
            UserDefaults.standard.set(available, forKey: feature.availabilityKey)
            if available {
                loadedThisSession.insert(feature)
                offerableThisSession.remove(feature)
            }
            Self.runBinding(for: feature)
            changed = true
        }
        if firstIslandInstall && AppFeature.notch.isAvailable {
            UserDefaults.standard.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
        }
        if changed { finishAvailabilityChange() }
    }

    /// Applies a hub preset: its features become the installed set, with
    /// their enable keys switched on so they work right away, and everything
    /// else uninstalls. Nothing is deleted, so any feature returns with one
    /// click, settings intact.
    package func apply(_ preset: FeaturePreset) {
        replaceAvailable(with: preset.features, enabling: preset.enableKeys)
    }

    /// Replaces the installed set after the first-run picker. It uses the same
    /// availability layer as the hub, so unselected features disappear without
    /// losing any of their settings.
    package func replaceAvailable(with selected: Set<AppFeature>, enabling keys: [String] = []) {
        for key in keys {
            UserDefaults.standard.set(true, forKey: key)
        }
        let savedValues = savedPreferences()
        for feature in AppFeature.allCases
        where mayFlip(feature, to: selected.contains(feature)) {
            let joins = selected.contains(feature)
            if joins {
                feature.enableOnFirstInstall(in: .standard, savedValues: savedValues)
            }
            UserDefaults.standard.set(joins, forKey: feature.availabilityKey)
            if joins {
                loadedThisSession.insert(feature)
                offerableThisSession.remove(feature)
            }
            Self.runBinding(for: feature)
        }
        // Features that stayed installed still need a sync: their enable
        // keys may have just flipped on. Syncs are idempotent, so a repeat
        // for the ones handled above costs nothing. A selected feature the
        // gate refused is not installed, so it is skipped like any other
        // unavailable one and its service never comes to life.
        for feature in selected where feature.isAvailable {
            Self.runBinding(for: feature)
        }
        if selected.contains(.notch) && AppFeature.notch.isAvailable {
            UserDefaults.standard.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
        }
        finishAvailabilityChange()
    }

    /// Installed switches that were never once turned on, for the Features
    /// page to offer as one batch, minus the ones the person chose to keep.
    package func neverSwitchedOnFeatures() -> [AppFeature] {
        let saved = savedPreferences()
        let kept = Self.keptFeatures()
        return AppFeature.neverSwitchedOn(isAvailable: \.isAvailable,
                                          boolFor: UserDefaults.standard.bool(forKey:),
                                          isSaved: { saved[$0] != nil })
            .filter { offerableThisSession.contains($0) && !kept.contains($0) }
    }

    /// Stops offering these features as unused. A later one that turns out
    /// never used is still offered, on its own merits.
    package func keep(_ features: [AppFeature]) {
        let kept = Self.keptFeatures().union(features)
        UserDefaults.standard.set(kept.map(\.rawValue).sorted().joined(separator: ","),
                                  forKey: DefaultsKey.featureHubKeptFeatures)
    }

    private static func keptFeatures() -> Set<AppFeature> {
        Set((UserDefaults.standard.string(forKey: DefaultsKey.featureHubKeptFeatures) ?? "")
            .split(separator: ",")
            .compactMap { AppFeature(rawValue: String($0)) })
    }

    /// Bulk install or uninstall for the hub's "all" buttons.
    package func setAllAvailable(_ available: Bool) {
        setAvailable(AppFeature.allCases, available, enablingFirstInstalls: false)
    }

    private func savedPreferences() -> [String: Any] {
        guard let domain = Bundle.main.bundleIdentifier else { return [:] }
        return UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
    }

    /// Launch path: replaces the old unconditional sync block. Only available
    /// features get their binding run, so nothing else even instantiates.
    package func syncAtLaunch() {
        for feature in AppFeature.allCases where feature.isAvailable {
            Self.runBinding(for: feature)
        }
    }

    /// Re-syncs a set of features (used by the permission sinks); skips
    /// unavailable ones so their singletons never come to life.
    package func sync(_ features: [AppFeature]) {
        for feature in features where feature.isAvailable {
            Self.runBinding(for: feature)
        }
    }

    /// One bump for Settings, and the Command Bar drops rows of features that
    /// just left the hub so a pin cannot linger as a bare id.
    private func finishAvailabilityChange() {
        revision += 1
        CommandBarService.shared.noteHubChange()
        if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
    }

    /// Runs what `feature` must re-evaluate when its availability (or a
    /// permission it depends on) changes. Exhaustive on purpose: a new
    /// `AppFeature` case does not compile until it says what it binds, or
    /// that it binds nothing. (This was a dictionary looked up with `?()`,
    /// where a forgotten entry silently did nothing.) Media binds only so
    /// uninstalling it can cancel work already in flight.
    private static func runBinding(for feature: AppFeature) {
        switch feature {
        case .switcher:
            WindowUseTracker.shared.syncWithFeatures()
            AppSwitcher.shared.syncWithPreferences()
        case .dockPreview: DockPreviewService.shared.syncWithPreferences()
        case .dockClick: DockClickService.shared.syncWithPreferences()
        case .windowMaximizer: WindowMaximizer.shared.syncWithPreferences()
        case .windowLayout:
            WindowUseTracker.shared.syncWithFeatures()
            WindowLayoutService.shared.syncWithPreferences()
            PointerDisplayService.shared.syncWithPreferences()
        case .autoQuit: AutoQuitService.shared.syncWithPreferences()
        case .scrollInverter: ScrollInverter.shared.syncWithPreferences()
        case .scrollHorizontal: ScrollInverter.shared.syncWithPreferences()
        case .focusFollowsMouse: FocusFollowsMouseService.shared.syncWithPreferences()
        case .smoothScroll: SmoothScrollService.shared.syncWithPreferences()
        case .linearScroll: ScrollInverter.shared.syncWithPreferences()
        case .mouseAcceleration: MouseAccelerationService.shared.syncWithPreferences()
        case .mouseNavigation: MouseNavigationService.shared.syncWithPreferences()
        case .mouseButtonShortcuts: MouseButtonShortcutService.shared.syncWithPreferences()
        case .middleClick: MiddleClickService.shared.syncWithPreferences()
        case .mouseClickDebounce: MouseClickDebounceService.shared.syncWithPreferences()
        case .keyboardDebounce: KeyboardDebounceService.shared.syncWithPreferences()
        case .quitWindowProtection: QuitProtectionService.shared.syncWithPreferences()
        case .superKey: SuperKeyService.shared.syncWithPreferences()
        case .textSnippets:
            TextSnippetService.shared.syncWithPreferences()
            SnippetLibraryService.shared.syncWithPreferences()
        case .clipboardHistory:
            ClipboardHistoryService.shared.syncWithPreferences()
            // Auto clear rides the clipboard feature's availability but not its
            // capture toggle: uninstalling the feature stops it, turning history
            // off does not.
            ClipboardAutoClearService.shared.syncWithPreferences()
        case .mediaTools:
            NotchFileToolsService.shared.syncWithPreferences()
            guard !AppFeature.mediaTools.isAvailable else { return }
            MediaService.shared.cancel()
            ScreenRecorderService.shared.closeEditors(ownedBy: .mediaTools)
        case .pastePlain: PastePlainService.shared.syncWithPreferences()
        case .finderCutPaste: FinderCutPaste.shared.syncWithPreferences()
        case .finderRename: FinderRenameService.shared.syncWithPreferences()
        case .shelf:
            ShelfService.shared.syncWithPreferences()
            NotchFileToolsService.shared.syncWithPreferences()
        case .urlCleaner: URLCleanerService.shared.syncWithPreferences()
        case .diskImageInstaller: DiskImageInstallerService.shared.syncWithPreferences()
        case .mixer:
            PreciseVolumeRollerService.shared.syncWithPreferences()
            AppVolumeMixer.shared.syncWithPreferences()
            AudioInputDeviceManager.shared.syncWithPreferences()
        case .soundOutputSwitcher:
            AppVolumeMixer.shared.syncWithPreferences()
            SoundOutputSwitcher.shared.syncWithPreferences()
        case .audioPriority:
            // Priority owns no sibling CoreAudio listener stack. Keep the
            // shared system-device observers alive even when Volume mixer is
            // not installed, then start/stop the policy that consumes them.
            AppVolumeMixer.shared.syncWithPreferences()
            AudioInputDeviceManager.shared.syncWithPreferences()
            AudioPriorityService.shared.syncWithPreferences()
        case .micMute: MicMuteService.shared.syncWithPreferences()
        case .musicBlock: MusicLaunchBlocker.shared.syncWithPreferences()
        case .keepAwake:
            KeepAwakeManager.shared.syncWithFeatures()
            HotkeyManager.shared.syncWithPreferences()
        case .brightness: BrightnessService.shared.syncWithPreferences()
        case .extraBrightness: ExtraBrightnessService.shared.syncWithPreferences()
        case .bluetoothSleep: BluetoothSleepService.shared.syncWithPreferences()
        case .quickLauncher: QuickLauncherService.shared.syncWithPreferences()
        case .colorPicker:
            ScreenCaptureService.shared.syncWithPreferences()
        case .screenOCR:
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenTextService.shared.syncWithPreferences()
        case .screenshot:
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenshotService.shared.syncWithPreferences()
            RecentCaptureService.shared.syncWithPreferences()
        case .screenRecorder:
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenRecorderService.shared.syncWithPreferences()
            RecentCaptureService.shared.syncWithPreferences()
        case .cameraPreview: CameraPreviewService.shared.syncWithPreferences()
        case .wallpaper: WallpaperService.shared.syncWithPreferences()
        case .radialMenu: RadialMenuService.shared.syncWithPreferences()
        case .notch: NotchService.shared.syncWithPreferences()
        case .notchGestures:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
        case .notchTimer:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchTimerService.shared.stop() }
        case .notchAccessories:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchAccessoryService.shared.stop() }
        case .notchLyrics:
            if !NotchLyricsSupport.isEnabled() { NotchLyricsService.shared.stop() }
        case .notchQueue: NotchMusicService.shared.syncQueuePreference()
        case .notchLiveEqualizer: NotchAudioLevelService.shared.syncWithPreferences()
        case .notchNotifications:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchNotificationService.shared.stop() }
        case .notchDownloads:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchDownloadService.shared.stop() }
        case .notchCalendar:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchCalendarService.shared.stop() }
        case .notchAgents:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { AgentUsageService.shared.stop() }
        case .notchWatch:
            if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
            else { NotchWatchService.shared.stop() }
        case .scratchpad: ScratchpadService.shared.syncWithPreferences()
        case .commandBar: CommandBarService.shared.syncWithPreferences()
        case .cleaner:
            CleanerScheduler.shared.syncWithPreferences()
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
            if !AppFeature.cleaner.isAvailable || !WhatsAppDownloadSupport.isEnabled {
                WhatsAppDownloadManager.shared.reset()
                WhatsAppDownloadOrganizer.shared.stop()
            }
        case .appUpdates: AppUpdatesService.shared.syncWithPreferences()
        case .monitorCPU: FeatureRuntime.syncMonitor()
        case .monitorGPU: FeatureRuntime.syncMonitor()
        case .monitorMemory: FeatureRuntime.syncMonitor()
        case .monitorNetwork: FeatureRuntime.syncMonitor()
        case .monitorDisk: FeatureRuntime.syncMonitor()
        case .monitorPower: FeatureRuntime.syncMonitor()
        case .fanControl:
            SystemMonitor.shared.planDidChange()
            let defaults = UserDefaults.standard
            let needsRecovery = defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
            let hasRegisteredHelper = !(defaults.string(forKey: DefaultsKey.fanControlHelperVersion) ?? "").isEmpty
            if needsRecovery || (!AppFeature.fanControl.isAvailable && hasRegisteredHelper) {
                FanControlService.shared.syncWithPreferences()
            }
        // Connected devices feeds SystemMonitor's sampling plan like the metric
        // families above. As a dictionary entry it was simply missing, so
        // uninstalling it mid-session left the plan stale until something else
        // recomputed it.
        case .connectedDevices: FeatureRuntime.syncMonitor()
        // On-demand tools: they check what they need each time they run, so
        // there is nothing to start, stop or re-evaluate.
        case .quickToggles, .cleaningMode, .uninstaller, .homebrew, .killProcess, .portManager:
            break
        }
    }

    private static func syncMonitor() {
        SystemMonitor.shared.planDidChange()
        MonitorAlertService.shared.syncWithPreferences()
    }
}

/// Hardware a feature needs and this Mac may not have. One switch answers
/// both questions, so a feature can never be unsupported without a reason to
/// show for it, and a feature added here can never grey a row silently.
/// It lives beside the runtime rather than in the catalog because the answer
/// comes from a service, and the catalog stays a pure description.
extension AppFeature {
    /// Why this Mac cannot run the feature, ready to show. `nil` when it can,
    /// or when the feature depends on no hardware at all.
    package var hardwareUnsupportedReason: String? {
        switch self {
        case .fanControl:
            return FanControlHardware.hasControllableFan
                ? nil : FeatureStrings.fanControl(L10n.shared.language).noFans
        default:
            return nil
        }
    }

    package var isHardwareSupported: Bool { hardwareUnsupportedReason == nil }

    /// Why a feature list must refuse to install this feature, ready to show
    /// as a tooltip. `nil` once it is installed: the check reads hardware and
    /// can be wrong, so it is never allowed to strand an existing install
    /// behind a greyed row. Both the hub and the first-run picker read this,
    /// so neither can drift from the gate in `FeatureRuntime`.
    package var installBlockedReason: String? {
        isAvailable ? nil : hardwareUnsupportedReason
    }
}
