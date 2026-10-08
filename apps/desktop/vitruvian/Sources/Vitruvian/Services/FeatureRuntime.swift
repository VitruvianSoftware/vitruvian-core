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
@MainActor
package final class FeatureRuntime: ObservableObject {
    package static let shared = FeatureRuntime(environment: .live)

    /// What the runtime reads and drives. The app passes the standard
    /// defaults and the live services; a test passes its own defaults and
    /// records the binding actions instead of running them.
    package struct Environment {
        package var defaults: UserDefaults
        /// Runs one of a feature's binding actions (`FeatureBindingAction`).
        package var perform: @MainActor (FeatureBindingAction) -> Void
        /// Once after each availability change.
        package var availabilityDidChange: @MainActor () -> Void
        /// The values saved in the app's own domain, as opposed to registered.
        package var savedPreferences: @MainActor () -> [String: Any]
        /// Why this Mac cannot run a feature, or nil when it can. The app asks
        /// the hardware (`AppFeature.hardwareUnsupportedReason`); a test names
        /// a Mac without some of it.
        package var hardwareUnsupportedReason: @MainActor (AppFeature) -> String?

        package init(defaults: UserDefaults,
                     perform: @escaping @MainActor (FeatureBindingAction) -> Void,
                     availabilityDidChange: @escaping @MainActor () -> Void,
                     savedPreferences: @escaping @MainActor () -> [String: Any],
                     hardwareUnsupportedReason: @escaping @MainActor (AppFeature) -> String? = {
                         $0.hardwareUnsupportedReason
                     }) {
            self.defaults = defaults
            self.perform = perform
            self.availabilityDidChange = availabilityDidChange
            self.savedPreferences = savedPreferences
            self.hardwareUnsupportedReason = hardwareUnsupportedReason
        }

        package static var live: Environment {
            Environment(
                defaults: .standard,
                perform: { FeatureRuntime.perform($0) },
                // The Command Bar drops rows of features that just left the
                // hub, so a pin cannot linger as a bare id.
                availabilityDidChange: {
                    CommandBarService.shared.noteHubChange()
                    if AppFeature.notch.isAvailable { NotchService.shared.syncWithPreferences() }
                },
                savedPreferences: {
                    guard let domain = Bundle.main.bundleIdentifier else { return [:] }
                    return UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
                })
        }
    }

    private let environment: Environment
    private var defaults: UserDefaults { environment.defaults }

    /// Bumped on every availability change; views observing the runtime
    /// re-read the catalog when it moves.
    @Published package private(set) var revision = 0

    /// Every feature that came to life in THIS process: available at launch
    /// or installed later in the session. A feature uninstalled mid-session
    /// stops working immediately, but its (inert) singleton only leaves
    /// memory on the next launch — this set is what the hub's restart banner
    /// keys off, including the install-then-uninstall-again case.
    private var loadedThisSession: Set<AppFeature>

    /// What was installed when the app came up and has not been installed
    /// again since. A feature installed later in the session, a reinstall
    /// included, has not had its chance yet, so it is never offered for
    /// uninstalling as unused until the next launch.
    private var offerableThisSession: Set<AppFeature>

    package init(environment: Environment) {
        self.environment = environment
        let available = Set(AppFeature.allCases.filter { $0.isAvailable(in: environment.defaults) })
        loadedThisSession = available
        offerableThisSession = available
    }

    private func installed(_ feature: AppFeature) -> Bool { feature.isAvailable(in: defaults) }

    /// True while something that loaded this session is now uninstalled, so
    /// a restart would actually unload it. Features already uninstalled when
    /// the app came up never loaded, so they need no restart.
    package var needsRestartToUnload: Bool {
        loadedThisSession.contains { !installed($0) }
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

    package func isAvailable(_ feature: AppFeature) -> Bool { installed(feature) }

    package var availableCount: Int { AppFeature.allCases.filter(installed).count }

    /// How many features this Mac can end up with. Counting against the whole
    /// catalog instead would leave the hub's install-all button forever one
    /// short of its own disabled condition on a Mac missing some hardware.
    /// An install that predates the check still counts, so the tally can
    /// never read more installed than installable.
    package var installableCount: Int {
        AppFeature.allCases.filter { isHardwareSupported($0) || installed($0) }.count
    }

    /// Why a feature list must refuse to install `feature`, ready to show as
    /// a tooltip. `nil` once it is installed: the check reads hardware and
    /// can be wrong, so it is never allowed to strand an existing install
    /// behind a greyed row. Both the hub and the first-run picker ask here,
    /// beside the gate below, so neither list can drift from it.
    package func installBlockedReason(_ feature: AppFeature) -> String? {
        installed(feature) ? nil : environment.hardwareUnsupportedReason(feature)
    }

    private func isHardwareSupported(_ feature: AppFeature) -> Bool {
        environment.hardwareUnsupportedReason(feature) == nil
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
        guard installed(feature) != available else { return false }
        return !available || isHardwareSupported(feature)
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
            && !defaults.bool(forKey: DefaultsKey.notchInitialExtensionsInstalled)
        let requested = firstIslandInstall
            ? features + AppFeature.dynamicIslandInitialExtensions.filter { !features.contains($0) }
            : features
        let savedValues = savedPreferences()
        for feature in requested where mayFlip(feature, to: available) {
            if available && enablingFirstInstalls {
                feature.enableOnFirstInstall(in: defaults, savedValues: savedValues)
            }
            defaults.set(available, forKey: feature.availabilityKey)
            if available {
                loadedThisSession.insert(feature)
                offerableThisSession.remove(feature)
            }
            runBinding(for: feature)
            changed = true
        }
        if firstIslandInstall && installed(.notch) {
            defaults.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
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
            defaults.set(true, forKey: key)
        }
        let savedValues = savedPreferences()
        for feature in AppFeature.allCases
        where mayFlip(feature, to: selected.contains(feature)) {
            let joins = selected.contains(feature)
            if joins {
                feature.enableOnFirstInstall(in: defaults, savedValues: savedValues)
            }
            defaults.set(joins, forKey: feature.availabilityKey)
            if joins {
                loadedThisSession.insert(feature)
                offerableThisSession.remove(feature)
            }
            runBinding(for: feature)
        }
        // Features that stayed installed still need a sync: their enable
        // keys may have just flipped on. Syncs are idempotent, so a repeat
        // for the ones handled above costs nothing. A selected feature the
        // gate refused is not installed, so it is skipped like any other
        // unavailable one and its service never comes to life.
        for feature in selected where installed(feature) {
            runBinding(for: feature)
        }
        if selected.contains(.notch) && installed(.notch) {
            defaults.set(true, forKey: DefaultsKey.notchInitialExtensionsInstalled)
        }
        finishAvailabilityChange()
    }

    /// Installed switches that were never once turned on, for the Features
    /// page to offer as one batch, minus the ones the person chose to keep.
    package func neverSwitchedOnFeatures() -> [AppFeature] {
        let saved = savedPreferences()
        let kept = keptFeatures()
        return AppFeature.neverSwitchedOn(isAvailable: installed,
                                          boolFor: defaults.bool(forKey:),
                                          isSaved: { saved[$0] != nil })
            .filter { offerableThisSession.contains($0) && !kept.contains($0) }
    }

    /// Brings back features just uninstalled as never used, when the person
    /// changes their mind. That is also an answer to the offer, so they are
    /// kept and never offered again; none of them was ever on, and the
    /// reinstall leaves their switches off too.
    package func reinstallKept(_ features: [AppFeature]) {
        keep(features)
        setAvailable(features, true, enablingFirstInstalls: false)
    }

    /// Stops offering these features as unused. A later one that turns out
    /// never used is still offered, on its own merits.
    package func keep(_ features: [AppFeature]) {
        let kept = keptFeatures().union(features)
        defaults.set(kept.map(\.rawValue).sorted().joined(separator: ","),
                     forKey: DefaultsKey.featureHubKeptFeatures)
    }

    private func keptFeatures() -> Set<AppFeature> {
        Set((defaults.string(forKey: DefaultsKey.featureHubKeptFeatures) ?? "")
            .split(separator: ",")
            .compactMap { AppFeature(rawValue: String($0)) })
    }

    /// Bulk install or uninstall for the hub's "all" buttons.
    package func setAllAvailable(_ available: Bool) {
        setAvailable(AppFeature.allCases, available, enablingFirstInstalls: false)
    }

    private func savedPreferences() -> [String: Any] { environment.savedPreferences() }

    /// Launch path: replaces the old unconditional sync block. Only available
    /// features get their binding run, so nothing else even instantiates.
    package func syncAtLaunch() {
        for feature in AppFeature.allCases where installed(feature) {
            runBinding(for: feature)
        }
    }

    /// Re-syncs a set of features (used by the permission sinks); skips
    /// unavailable ones so their singletons never come to life.
    package func sync(_ features: [AppFeature]) {
        for feature in features where installed(feature) {
            runBinding(for: feature)
        }
    }

    /// A grant changed while the app runs, say Accessibility granted during
    /// onboarding: every installed feature that declares it is synced again,
    /// so it comes up, or goes down, without a relaunch.
    package func permissionDidChange(_ permission: AppPermission) {
        sync(AppFeature.dependents(on: permission))
    }

    /// One bump for Settings, then the environment's own follow-up.
    private func finishAvailabilityChange() {
        revision += 1
        environment.availabilityDidChange()
    }

    private func runBinding(for feature: AppFeature) {
        for action in Self.actions(for: feature, in: defaults) { environment.perform(action) }
    }

    /// What `feature` must re-evaluate when its availability (or a permission
    /// it depends on) changes, read from `defaults`. Exhaustive on purpose: a
    /// new `AppFeature` case does not compile until it says what it binds, or
    /// that it binds nothing. (This was a dictionary looked up with `?()`,
    /// where a forgotten entry silently did nothing.) Media binds only so
    /// uninstalling it can cancel work already in flight.
    package static func actions(for feature: AppFeature, in defaults: UserDefaults) -> [FeatureBindingAction] {
        let islandShows = AppFeature.notch.isAvailable(in: defaults)
        /// An island extension resyncs the island while it shows, and stops
        /// its own service once the island is gone.
        func islandExtension(stopping stop: FeatureBindingAction?) -> [FeatureBindingAction] {
            islandShows ? [.notch] : stop.map { [$0] } ?? []
        }
        switch feature {
        case .switcher: return [.windowUseTracker, .appSwitcher]
        case .dockPreview: return [.dockPreview]
        case .dockClick: return [.dockClick]
        case .windowMaximizer: return [.windowMaximizer]
        case .windowLayout: return [.windowUseTracker, .windowLayout, .pointerDisplay]
        case .autoQuit: return [.autoQuit]
        case .spacesOrder: return [.spacesOrder]
        case .scrollInverter, .scrollHorizontal, .linearScroll: return [.scrollInverter]
        case .focusFollowsMouse: return [.focusFollowsMouse]
        case .smoothScroll: return [.smoothScroll]
        case .mouseAcceleration: return [.mouseAcceleration]
        case .mouseNavigation: return [.mouseNavigation]
        case .mouseButtonShortcuts: return [.mouseButtonShortcuts]
        case .middleClick: return [.middleClick]
        case .mouseClickDebounce: return [.mouseClickDebounce]
        case .keyboardDebounce: return [.keyboardDebounce]
        case .quitWindowProtection: return [.quitProtection]
        case .superKey: return [.superKey]
        case .textSnippets: return [.textSnippets, .snippetLibrary]
        // Auto clear rides the clipboard feature's availability but not its
        // capture toggle: uninstalling the feature stops it, turning history
        // off does not.
        case .clipboardHistory: return [.clipboardHistory, .clipboardAutoClear]
        case .mediaTools:
            return AppFeature.mediaTools.isAvailable(in: defaults) ? [.fileTools]
                : [.fileTools, .cancelMedia, .closeMediaEditors]
        case .pastePlain: return [.pastePlain]
        case .finderCutPaste: return [.finderCutPaste]
        case .finderRename: return [.finderRename]
        case .shelf: return [.shelf, .fileTools]
        case .urlCleaner: return [.urlCleaner]
        case .diskImageInstaller: return [.diskImageInstaller]
        case .mixer: return [.preciseVolumeRoller, .appVolumeMixer, .audioInputDevices]
        case .soundOutputSwitcher: return [.appVolumeMixer, .soundOutputSwitcher]
        // Priority owns no sibling CoreAudio listener stack. Keep the shared
        // system-device observers alive even when Volume mixer is not
        // installed, then start/stop the policy that consumes them.
        case .audioPriority: return [.appVolumeMixer, .audioInputDevices, .audioPriority]
        case .micMute: return [.micMute]
        case .musicBlock: return [.musicLaunchBlocker]
        case .keepAwake: return [.keepAwake, .hotkeys]
        case .brightness: return [.brightness]
        case .extraBrightness: return [.extraBrightness]
        case .bluetoothSleep: return [.bluetoothSleep]
        case .quickLauncher: return [.quickLauncher]
        case .colorPicker: return [.screenCapture]
        case .screenOCR: return [.screenCapture, .screenText]
        case .screenshot: return [.screenCapture, .screenshot, .recentCaptures]
        case .screenRecorder: return [.screenCapture, .screenRecorder, .recentCaptures]
        case .cameraPreview: return [.cameraPreview]
        case .wallpaper: return [.wallpaper]
        case .radialMenu: return [.radialMenu]
        case .notch: return [.notch]
        case .notchGestures: return islandExtension(stopping: nil)
        case .notchTimer: return islandExtension(stopping: .stopNotchTimer)
        case .notchAccessories: return islandExtension(stopping: .stopNotchAccessories)
        case .notchLyrics: return NotchLyricsSupport.isEnabled(in: defaults) ? [] : [.stopNotchLyrics]
        case .notchQueue: return [.notchQueue]
        case .notchLiveEqualizer: return [.notchAudioLevel]
        case .notchNotifications: return islandExtension(stopping: .stopNotchNotifications)
        case .notchDownloads: return islandExtension(stopping: .stopNotchDownloads)
        case .notchCalendar: return islandExtension(stopping: .stopNotchCalendar)
        case .notchAgents: return islandExtension(stopping: .stopAgentUsage)
        case .notchWatch: return islandExtension(stopping: .stopNotchWatch)
        // Only the sign-in exists so far, and it lives outside the island:
        // installing checks a saved token, uninstalling stops a sign-in in
        // progress. The strip and page (package C) add `.notch` here through
        // `islandExtension`, and package B wires GitHubService here.
        case .notchGitHub: return [.gitHubAuth]
        // Leaving folds the wings it rests in, and coming back greets.
        case .notchMascot: return islandExtension(stopping: nil)
        case .scratchpad: return [.scratchpad]
        case .commandBar: return [.commandBar]
        // Its hotkey, the auto-start and, on uninstall, stopping the bot.
        case .nexusAgent: return [.nexusAgent]
        case .cleaner:
            let schedules: [FeatureBindingAction] = [.cleanerScheduler, .whatsAppScheduler, .whatsAppOrganizer]
            let keepsDownloads = AppFeature.cleaner.isAvailable(in: defaults)
                && defaults[Preferences.whatsAppDownloadsEnabled]
            return keepsDownloads ? schedules : schedules + [.resetWhatsAppDownloads, .stopWhatsAppOrganizer]
        case .appUpdates: return [.appUpdates]
        // Connected devices feeds SystemMonitor's sampling plan like the
        // metric families. As a dictionary entry it was simply missing, so
        // uninstalling it mid-session left the plan stale until something
        // else recomputed it.
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .connectedDevices:
            return [.monitorPlan, .monitorAlerts]
        case .fanControl:
            let needsRecovery = defaults[Preferences.fanControlRecoveryNeeded]
            let hasRegisteredHelper = !(defaults[Preferences.fanControlHelperVersion]).isEmpty
            let syncsHelper = needsRecovery || (!AppFeature.fanControl.isAvailable(in: defaults) && hasRegisteredHelper)
            return syncsHelper ? [.monitorPlan, .fanControl] : [.monitorPlan]
        // On-demand tools: they check what they need each time they run, so
        // there is nothing to start, stop or re-evaluate.
        case .quickToggles, .cleaningMode, .uninstaller, .homebrew, .killProcess, .portManager:
            return []
        }
    }

    /// Runs one binding action on the live service.
    fileprivate static func perform(_ action: FeatureBindingAction) {
        switch action {
        case .windowUseTracker: WindowUseTracker.shared.syncWithFeatures()
        case .appSwitcher: AppSwitcher.shared.syncWithPreferences()
        case .dockPreview: DockPreviewService.shared.syncWithPreferences()
        case .dockClick: DockClickService.shared.syncWithPreferences()
        case .windowMaximizer: WindowMaximizer.shared.syncWithPreferences()
        case .windowLayout: WindowLayoutService.shared.syncWithPreferences()
        case .pointerDisplay: PointerDisplayService.shared.syncWithPreferences()
        case .autoQuit: AutoQuitService.shared.syncWithPreferences()
        case .spacesOrder: SpacesOrderHold.shared.syncWithPreferences()
        case .scrollInverter: ScrollInverter.shared.syncWithPreferences()
        case .focusFollowsMouse: FocusFollowsMouseService.shared.syncWithPreferences()
        case .smoothScroll: SmoothScrollService.shared.syncWithPreferences()
        case .mouseAcceleration: MouseAccelerationService.shared.syncWithPreferences()
        case .mouseNavigation: MouseNavigationService.shared.syncWithPreferences()
        case .mouseButtonShortcuts: MouseButtonShortcutService.shared.syncWithPreferences()
        case .middleClick: MiddleClickService.shared.syncWithPreferences()
        case .mouseClickDebounce: MouseClickDebounceService.shared.syncWithPreferences()
        case .keyboardDebounce: KeyboardDebounceService.shared.syncWithPreferences()
        case .quitProtection: QuitProtectionService.shared.syncWithPreferences()
        case .superKey: SuperKeyService.shared.syncWithPreferences()
        case .textSnippets: TextSnippetService.shared.syncWithPreferences()
        case .snippetLibrary: SnippetLibraryService.shared.syncWithPreferences()
        case .clipboardHistory: ClipboardHistoryService.shared.syncWithPreferences()
        case .clipboardAutoClear: ClipboardAutoClearService.shared.syncWithPreferences()
        case .fileTools: NotchFileToolsService.shared.syncWithPreferences()
        case .cancelMedia: MediaService.shared.cancel()
        case .closeMediaEditors: ScreenRecorderService.shared.closeEditors(ownedBy: .mediaTools)
        case .pastePlain: PastePlainService.shared.syncWithPreferences()
        case .finderCutPaste: FinderCutPaste.shared.syncWithPreferences()
        case .finderRename: FinderRenameService.shared.syncWithPreferences()
        case .shelf: ShelfService.shared.syncWithPreferences()
        case .urlCleaner: URLCleanerService.shared.syncWithPreferences()
        case .diskImageInstaller: DiskImageInstallerService.shared.syncWithPreferences()
        case .preciseVolumeRoller: PreciseVolumeRollerService.shared.syncWithPreferences()
        case .appVolumeMixer: AppVolumeMixer.shared.syncWithPreferences()
        case .audioInputDevices: AudioInputDeviceManager.shared.syncWithPreferences()
        case .soundOutputSwitcher: SoundOutputSwitcher.shared.syncWithPreferences()
        case .audioPriority: AudioPriorityService.shared.syncWithPreferences()
        case .micMute: MicMuteService.shared.syncWithPreferences()
        case .musicLaunchBlocker: MusicLaunchBlocker.shared.syncWithPreferences()
        case .keepAwake: KeepAwakeManager.shared.syncWithFeatures()
        case .hotkeys: HotkeyManager.shared.syncWithPreferences()
        case .brightness: BrightnessService.shared.syncWithPreferences()
        case .extraBrightness: ExtraBrightnessService.shared.syncWithPreferences()
        case .bluetoothSleep: BluetoothSleepService.shared.syncWithPreferences()
        case .quickLauncher: QuickLauncherService.shared.syncWithPreferences()
        case .screenCapture: ScreenCaptureService.shared.syncWithPreferences()
        case .screenText: ScreenTextService.shared.syncWithPreferences()
        case .screenshot: ScreenshotService.shared.syncWithPreferences()
        case .screenRecorder: ScreenRecorderService.shared.syncWithPreferences()
        case .recentCaptures: RecentCaptureService.shared.syncWithPreferences()
        case .cameraPreview: CameraPreviewService.shared.syncWithPreferences()
        case .wallpaper: WallpaperService.shared.syncWithPreferences()
        case .radialMenu: RadialMenuService.shared.syncWithPreferences()
        case .notch: NotchService.shared.syncWithPreferences()
        case .stopNotchTimer: NotchTimerService.shared.stop()
        case .stopNotchAccessories: NotchAccessoryService.shared.stop()
        case .stopNotchLyrics: NotchLyricsService.shared.stop()
        case .notchQueue: NotchMusicService.shared.syncQueuePreference()
        case .notchAudioLevel: NotchAudioLevelService.shared.syncWithPreferences()
        case .stopNotchNotifications: NotchNotificationService.shared.stop()
        case .stopNotchDownloads: NotchDownloadService.shared.stop()
        case .stopNotchCalendar: NotchCalendarService.shared.stop()
        case .stopAgentUsage: AgentUsageService.shared.stop()
        case .stopNotchWatch: NotchWatchService.shared.stop()
        case .gitHubAuth: GitHubAuthService.shared.syncWithPreferences()
        case .scratchpad: ScratchpadService.shared.syncWithPreferences()
        case .commandBar: CommandBarService.shared.syncWithPreferences()
        case .nexusAgent: NexusAgentService.shared.syncWithPreferences()
        case .cleanerScheduler: CleanerScheduler.shared.syncWithPreferences()
        case .whatsAppScheduler: WhatsAppDownloadScheduler.shared.syncWithPreferences()
        case .whatsAppOrganizer: WhatsAppDownloadOrganizer.shared.syncWithPreferences()
        case .resetWhatsAppDownloads: WhatsAppDownloadManager.shared.reset()
        case .stopWhatsAppOrganizer: WhatsAppDownloadOrganizer.shared.stop()
        case .appUpdates: AppUpdatesService.shared.syncWithPreferences()
        case .monitorPlan: SystemMonitor.shared.planDidChange()
        case .monitorAlerts: MonitorAlertService.shared.syncWithPreferences()
        case .fanControl: FanControlService.shared.syncWithPreferences()
        }
    }
}

/// One thing a feature's binding does to a live service, named so a test can
/// read a feature's bindings without bringing any service to life. Most sync
/// a service with its preferences; the `stop…`, `cancel…`, `close…` and
/// `reset…` ones tear down what an uninstalled feature left running.
package enum FeatureBindingAction: Hashable, CaseIterable {
    case windowUseTracker, appSwitcher, dockPreview, dockClick, windowMaximizer, windowLayout, pointerDisplay
    case autoQuit, spacesOrder, scrollInverter, focusFollowsMouse, smoothScroll, mouseAcceleration, mouseNavigation
    case mouseButtonShortcuts, middleClick, mouseClickDebounce, keyboardDebounce, quitProtection, superKey
    case textSnippets, snippetLibrary, clipboardHistory, clipboardAutoClear
    case fileTools, cancelMedia, closeMediaEditors
    case pastePlain, finderCutPaste, finderRename, shelf, urlCleaner, diskImageInstaller
    case preciseVolumeRoller, appVolumeMixer, audioInputDevices, soundOutputSwitcher, audioPriority
    case micMute, musicLaunchBlocker, keepAwake, hotkeys, brightness, extraBrightness, bluetoothSleep
    case quickLauncher, screenCapture, screenText, screenshot, screenRecorder, recentCaptures
    case cameraPreview, wallpaper, radialMenu
    case notch, stopNotchTimer, stopNotchAccessories, stopNotchLyrics, notchQueue, notchAudioLevel
    case stopNotchNotifications, stopNotchDownloads, stopNotchCalendar, stopAgentUsage, stopNotchWatch
    case gitHubAuth
    case scratchpad, commandBar, nexusAgent
    case cleanerScheduler, whatsAppScheduler, whatsAppOrganizer, resetWhatsAppDownloads, stopWhatsAppOrganizer
    case appUpdates, monitorPlan, monitorAlerts, fanControl
}

/// The pointer and keyboard features a normal quit takes down at once, in
/// this order. Each one is forced off on the spot, whatever its preference
/// says: switching a feature off may wait for the Up of a button still held,
/// and a quitting process has no future Up to wait for. Named so a test can
/// read the list without bringing any service to life.
package enum QuitInputRelease: CaseIterable {
    case focusFollowsMouse, windowMaximizer, windowLayout, keyboardDebounce, mouseClickDebounce
    case textSnippets, superKey, appSwitcher, mouseButtonShortcuts, middleClick, scrollInverter, smoothScroll

    /// Takes every one down, in order. Each touches its `.shared` whether or
    /// not the service ran this session.
    @MainActor package static func releaseAll() {
        for feature in allCases { feature.release() }
    }

    @MainActor private func release() {
        switch self {
        case .focusFollowsMouse: FocusFollowsMouseService.shared.stop()
        case .windowMaximizer: WindowMaximizer.shared.stop()
        case .windowLayout: WindowLayoutService.shared.suspend()
        case .keyboardDebounce: KeyboardDebounceService.shared.suspend()
        case .mouseClickDebounce: MouseClickDebounceService.shared.suspend()
        case .textSnippets: TextSnippetService.shared.suspend()
        // Takes the Super key mapping back out before the process goes away.
        case .superKey: SuperKeyService.shared.suspend()
        // Dock's app and window switcher hotkeys persist after quit.
        case .appSwitcher: AppSwitcher.shared.suspend()
        case .mouseButtonShortcuts: MouseButtonShortcutService.shared.suspend()
        case .middleClick: MiddleClickService.shared.suspend()
        case .scrollInverter: ScrollInverter.shared.suspend()
        case .smoothScroll: SmoothScrollService.shared.suspend()
        }
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
}
