// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import os.log
import Combine
import SwiftUI
import UserNotifications
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusController: StatusItemController!
    private let popover = NSPopover()
    /// Where the panel opens, how it holds its spot and how it closes and
    /// comes back (`MenuPanelPresenter`), over AppKit and this delegate's hooks.
    private lazy var presenter = MenuPanelPresenter<AppKitMenuPanel>(popover: popover, environment: .init(
        screens: { NSScreen.screens },
        screenWithMenuBar: { NSScreen.withMenuBar },
        pointerVisibleFrame: { NSScreen.pointerVisibleFrame },
        currentEvent: { NSApp.currentEvent },
        activate: { NSApp.activate(ignoringOtherApps: true) },
        main: { work in DispatchQueue.main.async { work() } },
        observeGeometry: { window, changed in
            [NSWindow.didMoveNotification, NSWindow.didResizeNotification].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { notification in
                    // Read here: the notification itself never crosses to the main actor.
                    let contentResized = notification.name == NSWindow.didResizeNotification
                    // Delivered on the main queue.
                    MainActor.assumeIsolated { changed(contentResized) }
                }
            }
        },
        stopObserving: { NotificationCenter.default.removeObserver($0) },
        statusButton: { [weak self] in self?.statusController?.button },
        holdStatusBadge: { [weak self] in self?.statusController?.setMicBadgeHeld($0) },
        setPopoverVisible: { MenuPanelFocus.shared.setPopoverVisible($0) },
        setSwitchingAnchor: { MenuPanelFocus.shared.setSwitchingMetricAnchor($0) },
        setAnchorScreen: { PanelInteractionState.shared.anchorScreen = $0 },
        preventsDismissal: { PanelInteractionState.shared.preventsPopoverDismissal },
        endDismissalProtection: {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
            PanelInteractionState.shared.isPresentingPopoverModal = false
        },
        releaseResources: {
            SystemMonitor.shared.setMenuPanelNeeds(.none)
            MenuPanelFocus.shared.clearMetricFocus()
            // Non-forced stop: the shortened lease lets nettop wind down on its
            // own within a few seconds while keeping the delta baseline, so a
            // quick reopen shows per-app rows immediately instead of re-priming.
            ProcessUsageService.shared.stopNetworkMonitoring()
            ProcessUsageService.shared.clearCachedRows()
            ResponsibleProcess.clearIconCache()
        },
        configureWindow: { [weak self] in self?.configurePopoverWindow($0) },
        usePositioningView: { [weak self] in self?.useStablePopoverPositioningViewIfNeeded($0) == true },
        installDismissMonitors: { [weak self] in self?.installPopoverDismissMonitor() },
        removeDismissMonitors: { [weak self] in self?.removePopoverDismissMonitor() },
        beginActivationTracking: { [weak self] in self?.beginPanelActivationTracking() },
        endActivationTracking: { [weak self] in self?.endPanelActivationTracking() },
        returnActivation: { [weak self] in self?.returnActivation(to: $0, after: $1) },
        closePanel: { [weak self] in self?.closePopover() },
        settingsWindow: { [weak self] in self?.settingsWindow },
        isTerminating: { [weak self] in self?.isTerminating == true }))
    private var popoverDismissMonitor: Any?
    private var popoverLocalDismissMonitor: Any?
    private var popoverKeyboardMonitor: Any?
    /// The app to hand activation back to when the panel is dismissed, so
    /// Vitruvian does not stay in front. Captured when a click opens the panel
    /// and kept current by the observers below while the panel is shown.
    private var panelActivationSource: NSRunningApplication?
    private var panelActivationObservers: [NSObjectProtocol] = []
    private var metricAnchorSwitchSerial = 0
    private var isTerminating = false
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    /// Settings keeps the app in Command Tab while its window is visible.
    private lazy var settingsActivation = WindowActivationClaim()
    private var feedbackWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var supportIntroWindow: NSWindow?
    private var updateHighlightsWindow: NSWindow?
    /// Which update intro comes next, and what closing one means.
    private lazy var introSequence = UpdateIntroSequence(host: .init(
        defaults: .standard,
        version: { AppInfo.version },
        isBeta: { AppInfo.isBeta },
        isTerminating: { [unowned self] in self.isTerminating },
        open: { [unowned self] intro in self.openIntroWindow(intro) },
        cleanupShowcaseCache: { UpdateShowcaseInfo.cleanupCache() },
        finish: { [unowned self] in self.showBrightnessUpdatePromptIfNeeded() },
        later: { work in DispatchQueue.main.async { work() } }))
    private var updateShowcaseWindow: NSWindow?
    private var updatePreviewWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Before any window exists, so nothing is ever built with the wrong
        // appearance and then repainted.
        AppAppearanceController.shared.apply()
        GlobalShortcut.startObservingKeyboardLayout()
        // UNUserNotificationCenter aborts in a process without a bundle;
        // guard keeps ad-hoc runs of the bare binary alive for probing.
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
        beginStartupWatch()
        Self.boundAccessibilityWaits()
        // Pay the first AppKit process lookup before an input callback needs
        // it. Each click still resolves the current process independently.
        _ = AssistiveKeyboard.isRunning

        // Finish the on-disk rename for installs carried over from a pre-2.5
        // build, or retire a leftover old-named bundle. Returns true when we are
        // quitting to relaunch under the new name, so skip the rest of startup.

        // Shape a clean install before any feature can create a listener,
        // timer or shortcut. The onboarding can replace this set after the
        // person chooses what they actually want.
        FeaturePreset.prepareFirstRunAvailability()

        // Redo a launch at login registration the system lost. The stored
        // choice is the last thing the user expressed in the app; startup
        // never turns the item off.
        LaunchAtLogin.repairAtStartup()

        // Switch back on any display a previous run left off. A run that ends
        // without putting one back leaves a screen dark with no app around to
        // offer it back, so the repair happens before anything else can care
        // about which displays are attached.
        BrightnessService.shared.restoreDisplaysLeftOff()

        // An accessory (LSUIElement) app gets no default main menu, so the standard
        // keyboard shortcuts (Cmd+H/M/W/Q and the Edit shortcuts Cmd+C/V/X/A) have
        // no menu items to fire and do nothing in the Settings window. Install one.
        installMainMenu()
        HorizontalWheelScrolling.install()
        PanelLayout.resetCollapsedSectionsOnce(for: "2.15.1")

        statusController = StatusItemController()
        statusController.onLeftClick = { [weak self] in
            self?.presenter.captureStatusClick()
            self?.toggleMainPopover()
        }
        statusController.onRightClick = { [weak self] button in
            if AppFeature.keepAwake.isAvailable
                && UserDefaults.standard[Preferences.keepAwakeRightClickToggle] {
                KeepAwakeManager.shared.toggle()
            } else {
                self?.showContextMenu(from: button)
            }
        }
        statusController.onMetricClick = { [weak self] metric, button in
            self?.presenter.captureStatusClick()
            self?.showMetricPanel(for: metric, anchoredTo: button)
        }
        statusController.onClipboardPreviewClick = {
            // No presenter.captureStatusClick() here, unlike the other click handlers:
            // it only ever helps anchor the main popover to a status item,
            // and this action opens the clipboard quick panel instead, which
            // centers itself on the pointer's screen rather than anchoring to
            // any status item.
            ClipboardHistoryService.shared.toggleHistoryWindow()
        }
        // The shelf drop zone chip anchors itself under the menu bar icon.
        ShelfService.shared.statusItemFrameProvider = { [weak self] in
            guard let item = self?.statusController.statusItem else { return nil }
            return StatusItemRecovery.anchorFrame(isVisible: item.isVisible,
                                                  windowFrame: self?.statusController.button?.window?.frame,
                                                  screenFrames: NSScreen.screens.map(\.frame))
        }

        setUpPopover()
        bindManagers()

        // A marker from an earlier build may name a hotkey id this build no
        // longer owns; give it back before any feature decides what to hold,
        // except the ids the switcher is about to take over again, which stay
        // off rather than flipping on and back. It has to run before the first
        // claim of the launch — keep-awake makes one on the next line — because
        // a claim resolves what every source wants together, and a marker no
        // source has spoken for yet resolves to nothing and is handed back whole.
        SystemShortcutTakeover.recoverIfNeeded(keeping: AppSwitcher.launchTakeoverIDs())
        HotkeyManager.shared.onActivate = { KeepAwakeManager.shared.toggle() }
        HotkeyManager.shared.syncWithPreferences()

        KeepAwakeManager.shared.recoverIfNeeded {
            KeepAwakeManager.shared.activateOnLaunchIfNeeded()
        }
        FanControlService.recoverIfNeeded()
        DockAutohideHold.recoverIfNeeded()
        SpacesOrderHold.recoverIfNeeded()
        // One binding per feature: only available features are touched, so a
        // feature switched off in the hub never even instantiates here.
        FeatureRuntime.shared.syncAtLaunch()
        if AppFeature.monitorPower.isAvailable, PowerSampler.hasInternalBattery {
            MaxCapacityProbe.shared.refreshIfStale()
        }
        UpdateService.shared.startAutomaticChecks()
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)

        // If Accessibility is granted while the app is running (e.g. during
        // onboarding), bring the input features up without a relaunch.
        Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.permissionDidChange(.accessibility)
            }
            .store(in: &cancellables)

        Permissions.shared.$screenRecording
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { _ in
                FeatureRuntime.shared.permissionDidChange(.screenRecording)
            }
            .store(in: &cancellables)

        // Keep the menu titles in step with the in-app language.
        L10n.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installMainMenu() }
            .store(in: &cancellables)

        let defaults = UserDefaults.standard
        // Whatever opens a window at startup waits for the next turn of the
        // run loop, so the menu bar icon is on screen first. A start that goes
        // wrong after this point then leaves the app reachable instead of
        // invisible. And if the previous start never finished, the extra
        // windows are skipped entirely this time: the app comes up bare rather
        // than walking into the same thing twice.
        let skipStartupWindows = startupOfPreviousRunDidNotFinish
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            #if VITRUVIAN_DEVELOPMENT
            if CommandLine.arguments.contains("--preview-notch-tour") {
                self.showUpdateHighlights(isReview: true)
                return
            }
            #endif
            if !defaults.bool(forKey: DefaultsKey.hasOnboarded) {
                guard !skipStartupWindows else { return }
                self.showOnboarding(mode: .full)
            } else {
                // Keep the last seen version marker current without opening
                // post-update release notes; the update flow already previews
                // them.
                let previousVersion = defaults.string(forKey: DefaultsKey.lastUpdateIntroVersion)
                self.queueBrightnessUpdatePromptIfNeeded(previousVersion: previousVersion)
                defaults.set(OnboardingInfo.currentFeatureSet, forKey: DefaultsKey.featuresOnboardingVersion)
                defaults.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
                guard !skipStartupWindows else { return }
                self.recoverStatusItemAfterUpdate(previousVersion: previousVersion)
                self.introSequence.present()
            }
        }
    }

    /// Asking another app about its windows waits for that app to answer, and
    /// the wait allowed by default is a second and a half per question. An app
    /// that is busy saving, or stuck on a slow disk, would hold this one still
    /// for that long each time, and this app asks in places where the whole
    /// session is waiting on it. The limit is set once here, low enough that a
    /// slow answer is dropped rather than felt. The value matches what the
    /// window features already settled on for themselves. It applies to every
    /// question asked from this process, whichever element it is asked of, so
    /// it also covers the places that never set one of their own.
    private static func boundAccessibilityWaits() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.35)
    }

    // MARK: - Startup that did not finish

    /// A start is marked as under way before anything else happens and cleared
    /// once the app has been running healthily for a while, or when it is
    /// quit properly. Finding the mark still set means the previous run died
    /// on the way up, and this one leaves the optional windows out of it.
    private var startupOfPreviousRunDidNotFinish = false

    /// How long a run has to last before its start counts as having worked.
    /// Comfortably past the point where the reported failures happened.
    private static let healthyStartupSeconds: TimeInterval = 20

    private func beginStartupWatch() {
        let defaults = UserDefaults.standard
        startupOfPreviousRunDidNotFinish = defaults.bool(forKey: DefaultsKey.startupDidNotFinish)
        defaults.set(true, forKey: DefaultsKey.startupDidNotFinish)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.healthyStartupSeconds) {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.startupDidNotFinish)
        }
    }

    private func endStartupWatch() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.startupDidNotFinish)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        commandBarTermination.shouldTerminate { sender.reply(toApplicationShouldTerminate: $0) }
    }

    /// Puts a borrowed keyboard layout back before the app quits.
    private let commandBarTermination = CommandBarTermination(
        hasBorrowed: { CommandBarService.shared.hasBorrowedInputSource },
        restore: { CommandBarService.shared.restoreBorrowedInputSource() })

    // Most calls below touch `.shared` whether or not the service ran this
    // session. Some of them rely on that, so do not gate them on "was it
    // started": SuperKeyService clears a remap marker a killed run left, and
    // SystemShortcutTakeover and the mouse-acceleration journal restore
    // system settings saved on disk. A new recovery belongs at launch, next
    // to FanControlService.recoverIfNeeded(), not only here. (REFACTOR.md,
    // step 2.)
    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        CommandBarService.shared.restoreBorrowedInputSource()
        if AppFeature.notch.isAvailable { NotchService.shared.stop(restoreCapture: false) }
        // Quitting properly means the start worked, whenever it happened.
        endStartupWatch()
        if AppFeature.brightness.isAvailable {
            BrightnessService.shared.restoreDisplaysBeforeTermination()
        }
        ExtraBrightnessService.shared.stop()
        ProcessUsageService.shared.stopNetworkMonitoring(force: true)
        URLCleanerService.shared.stop()
        // Forced off rather than synced: a held button's Up never comes now.
        QuitInputRelease.releaseAll()
        if AppFeature.mouseAcceleration.isAvailable
            || MouseAccelerationRecovery.hasPendingEntries() {
            MouseAccelerationService.shared.stop()
        }
        MouseNavigationService.shared.suspend()
        DockPreviewService.shared.stop()
        SoundOutputSwitcher.shared.stop()
        PreciseVolumeRollerService.shared.stop()
        AppVolumeMixer.shared.stopAll()
        FanControlService.restoreBeforeTerminationIfNeeded()
        // Restore a singular preferred-microphone override. An active
        // microphone priority selection remains the system input on quit.
        AudioInputDeviceManager.shared.stop()
        // Flushes any scratchpad edit still inside the save debounce.
        ScratchpadService.shared.suspend()
        // Ends a Quick Prompt reply in flight. The Telegram bot is left
        // running, as the standalone app leaves it; its PID file lets the
        // next launch adopt it.
        if AppFeature.nexusAgent.isAvailable { NexusAgentService.shared.prepareForQuit() }
        // Every macOS shortcut a feature took over goes back now, whichever
        // feature held it; not all of them suspend here.
        SystemShortcutTakeover.restoreAll()
        // The clipboard history persists through an async pipeline; the last
        // mutation (often a Clear) must land before the process dies.
        if AppFeature.clipboardHistory.isAvailable {
            ClipboardHistoryService.shared.flushBeforeTermination()
        }
        KeepAwakeManager.shared.deactivate(reason: .quit)
    }

    /// The lifeline when the menu bar icon goes missing. Opening the app again
    /// from Finder, Spotlight or Launchpad while it's already running lands here:
    /// force the icon back and pop the panel so there's immediate proof the app is
    /// alive. Without this, a hidden icon would strand the app running with no way
    /// in. (A cold launch can't happen while running, so this is the recovery path.)
    /// Reopens that Siri and Shortcuts send on their own are ignored.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let requester = ReopenRequestSupport.currentSender()
        let reopen = StatusItemRecovery.reopen(sender: requester,
                                               hasVisibleWindows: flag,
                                               hiddenByChoice: statusController?.mainItemHiddenByChoice == true,
                                               iconIsOnScreen: { iconIsOnScreen() })
        switch reopen {
        case .ignore:
            Self.menuBarLog.log("reopen ignored from \(ReopenRequestSupport.logName(requester), privacy: .public)")
            return false
        case .handled:
            return true
        case .recover(let rebuildIcon):
            // A deliberate reopen with no windows showing is the user's recovery action.
            // Rebuild the menu bar item only when it is actually missing: the
            // pre-rebuild item has a settled frame, so iconIsOnScreen() is trustworthy
            // here (the not-ready-frame caveat below only applies to a freshly created
            // item), and a dropped icon reads off-screen/zero, so recovery still gets
            // its rebuild with fresh placement. A healthy icon is left alone: on
            // macOS 27 a rebuilt item's window can keep reporting the slot it was
            // born in (the far right of the status area) while the icon draws at the
            // user's arranged spot, and that mismatch strands the panel against the
            // screen edge and survives relaunches. An item the app took out of the
            // bar itself, for Dynamic Island or for metrics, is not missing either:
            // a rebuild would only hide it again, and Settings opens below.
            if rebuildIcon {
                statusController?.recreateStatusItem()
            }
        }
        // Decide on the next run-loop turn: a freshly rebuilt status item has no
        // laid-out on-screen frame yet this turn, so iconIsOnScreen() would read a
        // not-ready frame and wrongly skip the panel. After layout: pop the panel
        // when the icon is genuinely on screen, else fall back to the Settings
        // window. Either way the user ALWAYS gets back in.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.iconIsOnScreen(), !self.popover.isShown {
                self.presenter.popoverClosedAt = .distantPast
                self.togglePopover()
            }
            if !self.popover.isShown {
                self.openSettingsWindow()
            }
        }
        return true
    }

    /// Whether the menu bar icon is actually visible on a screen, rather than
    /// present in the status bar but clipped or dropped by a crowded/notched menu
    /// bar (in which case the button still has a window, just not an on-screen one).
    private static let menuBarLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian",
                                           category: "menubar")

    private func iconIsOnScreen() -> Bool {
        StatusItemRecovery.iconIsOnScreen(isVisible: statusController?.statusItem.isVisible == true,
                                          windowFrame: statusController?.statusItem.button?.window?.frame,
                                          screenFrames: NSScreen.screens.map(\.frame))
    }

    private func iconIsSettling() -> Bool {
        StatusItemAnchorSupport.isSettlingStatusFrame(
            statusController?.statusItem.button?.window?.frame)
    }

    /// What the recovery saw, in the app's own log. Whether macOS gave the
    /// rebuilt item a place is invisible from the outside, so a report of an
    /// icon that never comes back has nothing to go on without this
    /// (issue #369). Read with:
    /// log show --last 1h --predicate 'category == "menubar"'
    private func logStatusItemPlacement(_ stage: String) {
        let window = statusController?.statusItem.button?.window
        let frame = window?.frame ?? .zero
        let placement = "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))"
        let screens = NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }
            .joined(separator: ",")
        let visible = statusController?.statusItem.isVisible ?? false
        let manager = Self.runningMenuBarManagerName() ?? "none"
        Self.menuBarLog.log("reshow \(stage, privacy: .public) window=\(window != nil) frame=\(placement, privacy: .public) visible=\(visible) screens=\(screens, privacy: .public) organizer=\(manager, privacy: .public)")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func bindManagers() {
        KeepAwakeManager.shared.onSessionEnded = { reason in
            let strings = L10n.shared.s
            switch reason {
            case .timer:
                Notifier.post(title: strings.notifySessionEndedTitle, body: strings.notifySessionEndedBody)
            case .battery:
                Notifier.post(title: strings.notifyBatteryTitle, body: strings.notifyBatteryBody)
            default:
                break
            }
        }
    }

    // MARK: - Main panel

    private func setUpPopover() {
        // Application-defined (not .transient) so the panel stays open while the
        // user works in our own Settings window and sees changes live. Click
        // monitors below dismiss it when it would block that same Settings window.
        popover.behavior = .applicationDefined
        popover.animates = true
        // The panel paints its own glass surface, or the arrow tip would show plain
        // system material where the surface stops, the seam users see. The visible
        // content stays inset either way, before through the content view's frame
        // and now through the safe area the popover publishes, so only the surface
        // reaches the arrow. Before macOS 26 AppKit does not lay full-size content
        // out, so the panel keeps the inset content there.
        PanelSurface.hostFullSizeContent(in: popover)
        popover.delegate = self
        let host = NSHostingController(rootView: MenuPanelView())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        AppAppearanceController.shared.follow(panel: popover)
    }

    private func togglePopover(anchor button: NSStatusBarButton? = nil) {
        if popover.isShown {
            closePopover(reason: .statusItem)
            return
        }
        presenter.showPopover(anchor: button)
    }

    private func toggleMainPopover() {
        if NotchSupport.routesAppPanel(), NotchService.shared.acceptsSystemFeedback {
            NotchService.shared.openAppPanel(toggle: true); return
        }
        if !popover.isShown {
            MenuPanelFocus.shared.showNormalPanel()
        }
        togglePopover()
    }

    func isOverStatusItem(_ point: NSPoint) -> Bool {
        statusController?.containsStatusItem(at: point) == true
    }

    private func showMetricPanel(for metric: MenuBarMetric, anchoredTo button: NSStatusBarButton) {
        let detailKind = metric.detailKind
        if NotchSupport.routesAppPanel(), NotchService.shared.acceptsSystemFeedback,
           NotchSupport.modules().contains(.system) {
            NotchService.shared.showMetric(detailKind, toggle: true); return
        }
        if popover.isShown {
            if MenuPanelFocus.shared.activeMetric == detailKind {
                metricAnchorSwitchSerial &+= 1
                MenuPanelFocus.shared.clearMetricFocus()
                closePopover(animated: false, reason: .statusItem)
                return
            }
            MenuPanelFocus.shared.focus(detailKind)
            scheduleMetricAnchorSwitch(to: detailKind, anchoredTo: button)
            return
        }
        MenuPanelFocus.shared.focus(detailKind)
        presenter.showPopover(anchor: button)
    }

    private func scheduleMetricAnchorSwitch(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        metricAnchorSwitchSerial &+= 1
        let serial = metricAnchorSwitchSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self, weak button] in
            guard let self,
                  let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial == serial,
                  MenuPanelFocus.shared.activeMetric == detailKind else { return }
            self.reanchorMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    private func reanchorMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        guard popover.isShown else {
            MenuPanelFocus.shared.focus(detailKind)
            presenter.showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            return
        }
        presenter.popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        let expectedMidX = presenter.statusButtonMidX(button)
        // The panel measures itself against this while the popover lays out,
        // so it has to be right before the content is asked for its size.
        PanelInteractionState.shared.anchorScreen = presenter.statusScreen(for: button)
        popover.animates = false
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        MenuPanelFocus.shared.setPopoverVisible(popover.isShown)
        popover.animates = true
        popover.contentViewController?.view.window?.makeKey()
        if let window = popover.contentViewController?.view.window {
            configurePopoverWindow(window)
            presenter.beginPopoverDriftCorrection(window: window,
                                        anchor: presenter.resolvePanelAnchor(for: button, window: window))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self, weak button] in
            guard let self else {
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            guard let button,
                  self.popover.isShown,
                  self.metricAnchorSwitchSerial > 0,
                  MenuPanelFocus.shared.activeMetric == detailKind else {
                self.presenter.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                // A close in this window, like a second click on the same
                // metric, ran while switching, so popoverDidClose kept these.
                if !self.popover.isShown {
                    self.statusController.setMicBadgeHeld(false)
                    self.presenter.releasePanelResources()
                    _ = self.endPanelActivationTracking()
                }
                return
            }
            // The pinned anchor is the yardstick; a reported frame the system
            // has since parked out of the way is not.
            if let expectedMidX = self.presenter.popoverAnchor?.midX ?? expectedMidX,
               let popoverMidX = self.popover.contentViewController?.view.window?.frame.midX,
               abs(popoverMidX - expectedMidX) <= 34 {
                self.presenter.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            self.switchMetricPopover(to: detailKind, anchoredTo: button)
        }
    }

    /// An untrustworthy status-item frame leaves AppKit pointing the arrow at a
    /// parked positioning view. Replace it with a transparent screen-space view
    /// at the opening arrow location, and keep that view current as the popover
    /// or display geometry changes.
    @discardableResult
    private func useStablePopoverPositioningViewIfNeeded(_ window: NSWindow) -> Bool {
        guard let anchor = presenter.popoverAnchor,
              presenter.popoverPositioningPanel != nil
                || presenter.statusFrameNeedsAnchorOverride(anchor),
              let visibleFrame = presenter.anchorVisibleFrame(anchor, window: window) else { return false }
        let targetFrame = StatusItemAnchorSupport.pinnedPanelFrame(size: window.frame.size,
                                                                  anchorMidX: anchor.midX,
                                                                  anchorTop: anchor.top,
                                                                  visibleFrame: visibleFrame)
        let tipX = min(max(anchor.tipX, visibleFrame.minX), visibleFrame.maxX)
        let anchorRect = CGRect(x: tipX - 0.5, y: targetFrame.maxY, width: 1, height: 1)
        if let panel = presenter.popoverPositioningPanel {
            if abs(panel.frame.minX - anchorRect.minX) > 0.5
                || abs(panel.frame.minY - anchorRect.minY) > 0.5 {
                panel.setFrame(anchorRect, display: false)
            }
            return true
        }
        let panel = AppKitMenuPanel.makePositioningPanel(at: anchorRect)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = window.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        let positioningView = NSView(frame: CGRect(origin: .zero, size: anchorRect.size))
        panel.contentView = positioningView
        presenter.popoverPositioningPanel = panel
        panel.orderFrontRegardless()
        let preservedAnchor = anchor
        presenter.popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        popover.animates = false
        popover.show(relativeTo: positioningView.bounds,
                     of: positioningView,
                     preferredEdge: .minY)
        MenuPanelFocus.shared.setPopoverVisible(popover.isShown)
        popover.animates = true
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window else {
            presenter.endPopoverDriftCorrection()
            panel.close()
            removePopoverDismissMonitor()
            presenter.popoverIsSwitchingAnchor = false
            MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
            // A close during the show ran while switching, so popoverDidClose
            // kept these for a panel that is not coming back.
            if !popover.isShown {
                statusController.setMicBadgeHeld(false)
                presenter.releasePanelResources()
                _ = endPanelActivationTracking()
            }
            return false
        }
        configurePopoverWindow(popoverWindow)
        popoverWindow.makeKey()
        presenter.beginPopoverDriftCorrection(window: popoverWindow,
                                    anchor: preservedAnchor,
                                    preserving: panel)
        installPopoverDismissMonitor()
        DispatchQueue.main.async { [weak self] in
            self?.presenter.popoverIsSwitchingAnchor = false
            MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
        }
        return true
    }

    private func configurePopoverWindow(_ window: NSWindow) {
        // Keep the panel alive next to fullscreen apps and on any Space —
        // without this it blinks shut when another display is fullscreen.
        window.collectionBehavior.insert([.fullScreenAuxiliary, .canJoinAllSpaces])
        if let panel = window as? NSPanel {
            panel.hidesOnDeactivate = false
        }
    }

    private func switchMetricPopover(to detailKind: MetricDetailKind, anchoredTo button: NSStatusBarButton) {
        presenter.popoverIsSwitchingAnchor = true
        MenuPanelFocus.shared.setSwitchingMetricAnchor(true)
        removePopoverDismissMonitor()
        presenter.popoverCloseIsAppRequested = true
        presenter.popoverIsClosing = true
        popover.animates = false
        popover.close()
        popover.animates = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak button] in
            guard let self else {
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                return
            }
            guard let button else {
                self.presenter.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
                if !self.popover.isShown {
                    self.statusController.setMicBadgeHeld(false)
                    self.endPanelActivationTracking()
                }
                return
            }
            self.presenter.popoverClosedAt = .distantPast
            MenuPanelFocus.shared.focus(detailKind)
            self.presenter.showPopover(anchor: button, allowRecentClose: true, animate: false, activate: false)
            DispatchQueue.main.async {
                self.presenter.popoverIsSwitchingAnchor = false
                MenuPanelFocus.shared.setSwitchingMetricAnchor(false)
            }
        }
    }

    private func installPopoverDismissMonitor() {
        removePopoverDismissMonitor()
        // A global monitor only sees events delivered to OTHER apps, so a click in
        // another app or on the desktop dismisses the panel.
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            guard !PanelInteractionState.shared.preventsPopoverDismissal else { return }
            guard self.statusController.containsStatusItem(at: NSEvent.mouseLocation) == false else { return }
            self.closePopover(reason: .outsideClick)
        }

        // Local events cover our own Settings window. Keep Settings + panel open
        // when they sit side by side for live reordering, but close the panel if it
        // overlaps Settings and the user clicks Settings to get it out of the way.
        popoverLocalDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if self.presenter.shouldDismissPopover(forLocalEvent: event) {
                self.closePopover(reason: .outsideClick)
            }
            return event
        }

        popoverKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handlePopoverKeyDown(event)
        }
    }

    private func removePopoverDismissMonitor() {
        if let monitor = popoverDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverDismissMonitor = nil
        }
        if let monitor = popoverLocalDismissMonitor {
            NSEvent.removeMonitor(monitor)
            popoverLocalDismissMonitor = nil
        }
        if let monitor = popoverKeyboardMonitor {
            NSEvent.removeMonitor(monitor)
            popoverKeyboardMonitor = nil
        }
    }

    private func handlePopoverKeyDown(_ event: NSEvent) -> NSEvent? {
        panelKeys.handle(event) ? nil : event
    }

    private var popoverWindow: NSWindow? {
        popover.contentViewController?.view.window
    }

    /// The panel's keys (`MenuPanelKeyRoute`).
    private lazy var panelKeys: MenuPanelKeyRoute<NSEvent> = MenuPanelKeyRoute(panel: .init(
        isShown: { [weak self] in self?.popover.isShown == true },
        window: { [weak self] in self?.popoverWindow },
        isComposing: { [weak self] in (self?.popoverWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true },
        viewKeepsOpen: { PanelInteractionState.shared.viewKeepsPopoverOpen },
        isEditingText: { [weak self] in
            guard let self, let window = self.popoverWindow else { return false }
            return self.isTextEditingActive(in: window)
        },
        isKey: { [weak self] in
            guard let window = self?.popoverWindow else { return false }
            return NSApp.keyWindow === window
        },
        close: { [weak self] in self?.closePopover(reason: .escape) },
        deliver: { [weak self] event in self?.popoverWindow?.firstResponder?.keyDown(with: event) }))

    private func isTextEditingActive(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        guard let fieldEditor = window.fieldEditor(false, for: nil) else { return false }
        return responder === fieldEditor
    }

    @objc private func appBecameActive() {
        // Coming back to the app is a good moment to surface a fresh release.
        // (Menu bar icon recovery happens on a deliberate reopen, not here: this
        // fires on every activation, so rebuilding here would cause churn/flicker.)
        UpdateService.shared.checkIfStale()
        restoreAfterAppUpdateHandoff()
        if settingsWindow?.isVisible == true {
            NotificationCenter.default.post(name: LaunchAtLoginSupport.settingsRefreshRequested, object: nil)
        }
    }

    /// Some updates finish in another app. With no Dock icon there is no way
    /// back to the window that sent the person there, so returning brings it
    /// forward again, on the same page, while the list reads the truth again.
    private func restoreAfterAppUpdateHandoff() {
        guard AppFeature.appUpdates.isAvailable else { return }
        let service = AppUpdatesService.shared
        service.applicationBecameActive()
        // Only a window still on screen is brought back. A Settings window the
        // person closed themselves stays closed.
        guard service.consumeUpdateHandoffReturn(),
              settingsWindow?.isVisible == true else { return }
        openSettingsWindow()
    }

    /// Callers other than the dismissal paths are panel actions, so `reason`
    /// defaults to one that leaves activation alone.
    func closePopover(animated: Bool = true, after delay: TimeInterval = 0,
                      preservingNotch: Bool = false, reason: PanelCloseReason = .action,
                      completion: (() -> Void)? = nil) {
        if !preservingNotch, NotchSupport.isEnabled() { NotchService.shared.collapse() }
        if delay <= 0 {
            presenter.closePopoverNow(animated: animated, reason: reason, completion: completion)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.presenter.closePopoverNow(animated: animated, reason: reason, completion: completion)
        }
    }

    // The SwiftUI panel reports which monitor sections are actually visible; the
    // popover callback only handles update freshness.
    func popoverWillShow(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .menuPanelWillShow, object: nil)
        }
        SystemMonitor.shared.suppressGPUReadsForTransientUI()
        if !presenter.popoverIsSwitchingAnchor {
            UpdateService.shared.checkIfStale()
        }
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        presenter.popoverCloseIsAppRequested || !PanelInteractionState.shared.preventsPopoverDismissal
    }

    func popoverWillClose(_ notification: Notification) {
        presenter.popoverWillClose(notification)
    }

    func popoverDidClose(_ notification: Notification) {
        presenter.popoverDidClose(notification)
    }

    /// Remembers the app in front as the panel opens with activation, and
    /// follows it while the panel is shown. The observers live only as long as
    /// the panel: an anchor switch or an in-place reopen keeps them, a real
    /// close ends them.
    private func beginPanelActivationTracking() {
        endPanelActivationTracking()
        let ownPID = NSRunningApplication.current.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        // Opened while Vitruvian was already in front (from Settings, say):
        // there is nothing to hand back when the panel closes.
        panelActivationSource = front?.processIdentifier == ownPID ? nil : front
        let center = NSWorkspace.shared.notificationCenter
        panelActivationObservers = [
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.updatePanelActivationSource(.activeSpaceChanged) }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                               object: nil, queue: .main) { [weak self] note in
                // Read here: the notification itself never crosses to the main actor.
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    guard let app else { return }
                    self?.updatePanelActivationSource(.appActivated(app))
                }
            },
        ]
    }

    private func updatePanelActivationSource(_ change: PanelActivationChange<NSRunningApplication>) {
        let ownPID = NSRunningApplication.current.processIdentifier
        panelActivationSource = StatusItemAnchorSupport.panelActivationSource(
            after: change, current: panelActivationSource,
            isOwnApp: { $0.processIdentifier == ownPID })
    }

    /// Stops following activation and returns the app remembered last.
    @discardableResult
    private func endPanelActivationTracking() -> NSRunningApplication? {
        let center = NSWorkspace.shared.notificationCenter
        panelActivationObservers.forEach { center.removeObserver($0) }
        panelActivationObservers.removeAll()
        let source = panelActivationSource
        panelActivationSource = nil
        return source
    }

    /// Closing the panel leaves Vitruvian active, and macOS keeps reporting it
    /// as the frontmost app until something else is focused, which misleads
    /// window managers and anything that follows the active app.
    private func returnActivation(to source: NSRunningApplication?, after closeReason: PanelCloseReason?) {
        guard let source, closeReason?.dismissesWithoutTakeover == true else { return }
        // One turn later, so the close animation has finished and anything the
        // dismissal itself focused has become key.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown, !source.isTerminated,
                  StatusItemAnchorSupport.shouldReturnActivation(
                      to: source.processIdentifier,
                      ownPID: NSRunningApplication.current.processIdentifier,
                      frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      ownWindowIsKey: NSApp.keyWindow != nil || NSApp.modalWindow != nil,
                      closeReason: closeReason),
                  !self.handbackWouldSwitchDesktop(to: source.processIdentifier)
            else { return }
            ActivationHandoff.yield(to: source)
            if !source.activate(from: NSRunningApplication.current, options: []) {
                source.activate(options: [])
            }
        }
    }

    /// Reads the Spaces of the app's normal windows from the window server.
    /// Windows the app has ordered out (minimized, or kept after a close) do
    /// not make activation travel, so they are left out.
    private func handbackWouldSwitchDesktop(to pid: pid_t) -> Bool {
        guard SpaceWindowBridge.canResolveSpaces,
              let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let windowSpaces: [[UInt64]] = info.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            else { return nil }
            let windowID = CGWindowID(number)
            guard SpaceWindowBridge.isWindowOrderedIn(windowID) != false else { return nil }
            return SpaceWindowBridge.spaces(of: windowID)
        }
        return StatusItemAnchorSupport.handbackWouldSwitchDesktop(
            windowSpaces: windowSpaces,
            visibleSpaces: SpaceWindowBridge.topology()?.visibleSpaces)
    }

    // MARK: - Context menu (right click)

    private func showContextMenu(from button: NSStatusBarButton?) {
        // The panel uses applicationDefined dismissal, so a right-click while it's
        // open won't close it on its own — and the menu would try to open behind it.
        // Close it first so the context menu always appears.
        if popover.isShown {
            closePopover { [weak self] in self?.presentContextMenu(from: button) }
            return
        }

        presentContextMenu(from: button)
    }

    private func presentContextMenu(from button: NSStatusBarButton?) {
        let manager = KeepAwakeManager.shared
        let strings = L10n.shared.s
        let menu = NSMenu()

        if AppFeature.keepAwake.isAvailable {
            let toggleItem = NSMenuItem(title: manager.isActive ? strings.menuDisableAwake : strings.menuEnableAwake,
                                        action: #selector(menuToggleAwake),
                                        keyEquivalent: "")
            toggleItem.target = self
            menu.addItem(toggleItem)
        }

        if AppFeature.keepAwake.isAvailable, !manager.isActive {
            let durationsItem = NSMenuItem(title: strings.menuActivateFor, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let options: [(String, Int)] = [(strings.minutes15, 15), (strings.minutes30, 30),
                                            (strings.hour1, 60), (strings.hours2, 120),
                                            (strings.hours4, 240), (strings.hours8, 480),
                                            (strings.indefinitely, 0)]
            for (label, minutes) in options {
                let item = NSMenuItem(title: label, action: #selector(menuActivateDuration(_:)), keyEquivalent: "")
                item.target = self
                item.tag = minutes
                submenu.addItem(item)
            }
            durationsItem.submenu = submenu
            menu.addItem(durationsItem)
        }

        if AppFeature.cleaningMode.isAvailable {
            let cleaningItem = NSMenuItem(title: strings.cleaningMenuItem,
                                          action: #selector(menuCleaningMode), keyEquivalent: "")
            cleaningItem.target = self
            menu.addItem(cleaningItem)
        }

        if menu.items.isEmpty == false {
            menu.addItem(.separator())
        }

        let settingsItem = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        if AppFeature.uninstaller.isAvailable {
            let uninstallItem = NSMenuItem(title: strings.uninstallerMenuItem,
                                           action: #selector(menuOpenUninstaller), keyEquivalent: "")
            uninstallItem.target = self
            menu.addItem(uninstallItem)
        }

        if AppFeature.shelf.isAvailable, UserDefaults.standard[Preferences.shelfEnabled] {
            let shelfItem = NSMenuItem(title: strings.shelfMenuItem,
                                       action: #selector(menuOpenShelf), keyEquivalent: "")
            shelfItem.target = self
            menu.addItem(shelfItem)
        }

        let updatesItem = NSMenuItem(title: strings.menuCheckUpdates, action: #selector(menuCheckUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: strings.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        let host = statusController.menuHost(for: button)
        host.menu = menu
        host.button?.performClick(nil)
        DispatchQueue.main.async {
            host.menu = nil
        }
    }

    @objc private func menuToggleAwake() {
        KeepAwakeManager.shared.toggle()
    }

    @objc private func menuCleaningMode() {
        CleaningModeManager.shared.activate()
    }

    @objc private func menuActivateDuration(_ sender: NSMenuItem) {
        KeepAwakeManager.shared.activate(minutes: sender.tag)
    }

    @objc private func menuOpenSettings() {
        openSettingsWindow()
    }

    @objc private func menuOpenUninstaller() {
        SettingsRouter.shared.page = .uninstaller
        openSettingsWindow()
    }

    @objc private func menuOpenShelf() {
        ShelfService.shared.expandDocked()
    }

    @objc private func menuCheckUpdates() {
        UpdateService.shared.check(manual: true)
        openSettingsWindow()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: L10n.shared.s.aboutDescription,
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    // MARK: - Application menu

    /// Builds and installs the standard application menu (App / Edit / Go / Window).
    ///
    /// Because the app runs as an accessory, AppKit never gives it the default main
    /// menu a regular app gets, so `NSApp.mainMenu` stays nil and the standard key
    /// equivalents (which live on menu items) never resolve. That is why nothing
    /// happens for Cmd+H/M/W/Q or Cmd+C/V/X/A inside the Settings window. A minimal
    /// standard menu restores them. The menu bar only appears while one of the
    /// app's own windows is focused; otherwise the app is as invisible as before.
    /// Most items use the responder chain (nil target) so they act on the key
    /// window or the focused text field; About and Settings route to our handlers.
    func installMainMenu() {
        let strings = L10n.shared.s
        let mainMenu = NSMenu()

        // Application menu (the bold, app-named first menu).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(title: strings.menuAbout, action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settings = NSMenuItem(title: strings.menuSettings, action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())

        appMenu.addItem(NSMenuItem(title: strings.menuHide,
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: strings.menuHideOthers,
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: strings.menuShowAll,
                                   action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: strings.menuQuit,
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Edit menu, so text fields in Settings respond to the editing shortcuts.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: strings.menuEdit)
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(title: strings.menuUndo, action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: strings.menuRedo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: strings.menuCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: strings.menuCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: strings.menuPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: strings.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Drivers and other running copies of Vitruvian may translate side buttons
        // into menu commands before this process ever receives a raw mouse event.
        let navigationMenuItem = NSMenuItem()
        navigationMenuItem.submenu = SettingsWindow.navigationMenu(language: L10n.shared.language)
        mainMenu.addItem(navigationMenuItem)

        // Window menu (Minimize / Zoom / Close). Settings is .miniaturizable so
        // Cmd+M actually minimizes; AppKit manages enabling once windowsMenu is set.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: strings.menuWindow)
        windowMenuItem.submenu = windowMenu

        windowMenu.addItem(NSMenuItem(title: strings.menuMinimize,
                                      action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: strings.menuZoom,
                                      action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: strings.menuClose,
                                      action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    // MARK: - Windows

    func openSettingsWindow() {
        // Intentionally does NOT close the panel: the panel uses applicationDefined
        // dismissal, so it stays open beside Settings for a live preview.
        // Capture the destination before activation changes the key window.
        let targetScreen = (popover.isShown
            ? presenter.popoverAnchor?.screen ?? popover.contentViewController?.view.window?.screen
            : nil) ?? NSScreen.withMouse
        let createdWindow = settingsWindow == nil
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            // Empty on purpose: any automatic option here (.intrinsicContentSize,
            // .maxSize, .preferredContentSize) lets SwiftUI's content - which
            // varies wildly page to page, from a short toggle list to Kill
            // Process's few-hundred-row List - drive the window's size, either
            // growing it to fit content or freezing it at a stale snapshot.
            // The window's size is fully owned by SettingsWindowSupport's
            // explicit sizing below plus ordinary user drag-resize.
            host.sizingOptions = []
            let window = SettingsWindow(contentViewController: host)
            window.isMouseButtonCaptureActive = { MouseButtonShortcutService.isCaptureActive }
            // .miniaturizable so the Window menu's Minimize (Cmd+M) actually works.
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            host.view.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsWindowSupport.minContentWidth).isActive = true
            host.view.heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsWindowSupport.minContentHeight).isActive = true
            let minFrame = window.frameRect(forContentRect: NSRect(
                x: 0, y: 0,
                width: SettingsWindowSupport.minContentWidth,
                height: SettingsWindowSupport.minContentHeight
            )).size
            window.minSize = minFrame
            window.contentMinSize = NSSize(width: SettingsWindowSupport.minContentWidth,
                                           height: SettingsWindowSupport.minContentHeight)
            let visible = targetScreen?.visibleFrame ?? NSScreen.pointerVisibleFrame
            let size = SettingsWindowSupport.initialContentSize(
                savedWidth: UserDefaults.standard.double(forKey: DefaultsKey.settingsWindowWidth),
                savedHeight: UserDefaults.standard.double(forKey: DefaultsKey.settingsWindowHeight),
                availableHeight: Double(visible.height - 40))
            window.setContentSize(NSSize(width: size.width, height: size.height))
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.title = L10n.shared.s.settingsTitle
        if let window = settingsWindow {
            presenter.positionSettingsWindow(window, force: createdWindow, on: targetScreen)
        }
        settingsActivation.windowShown()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Reopening on the very page that was showing at close never runs
        // that page's own onAppear, since its view was never removed from
        // the hierarchy; the window itself is the only reliable signal here.
        SecureInputMonitor.shared.setSettingsWindowOpen(true)
        SettingsWindowVisibility.shared.set(true)
        NotificationCenter.default.post(name: LaunchAtLoginSupport.settingsRefreshRequested, object: nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.settingsWindow else { return }
            self.presenter.positionSettingsWindow(window, force: false, on: targetScreen)
        }
    }

    func openFeedbackWindow(kind: FeedbackKind = .bug) {
        closePopover()
        let host = NSHostingController(rootView: FeedbackView(initialKind: kind) { [weak self] in
            self?.feedbackWindow?.close()
        })
        if let window = feedbackWindow {
            window.contentViewController = host
        } else {
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable]
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.center()
            feedbackWindow = window
        }
        feedbackWindow?.title = FeatureStrings.feedback(L10n.shared.language).windowTitle
        NSApp.activate(ignoringOtherApps: true)
        feedbackWindow?.makeKeyAndOrderFront(nil)
    }

    /// Only the first launch of a newer version gets this bounded check
    /// (`StatusItemUpdateCheck`).
    private func recoverStatusItemAfterUpdate(previousVersion: String?) {
        let check = StatusItemUpdateCheck<NSStatusItem>(
            host: .init(item: { [weak self] in self?.statusController?.statusItem },
                        isTerminating: { [weak self] in self?.isTerminating ?? true },
                        isReshowing: { [weak self] in self?.isReshowingStatusItem ?? false },
                        panelIsShown: { [weak self] in self?.popover.isShown ?? false },
                        hasMenu: { $0.menu != nil },
                        isVisible: { $0.isVisible },
                        iconIsOnScreen: { [weak self] in self?.iconIsOnScreen() ?? false },
                        recreate: { [weak self] in self?.statusController?.recreateStatusItem() },
                        log: { [weak self] in self?.logStatusItemPlacement($0) }),
            system: .live(menuBarManager: { Self.runningMenuBarManagerName() }),
            interval: Self.reshowVerifyInterval)
        check.start(previousVersion: previousVersion)
    }

    /// Rebuilds the menu bar item so the icon reappears when the OS has dropped it
    /// from a crowded or notched menu bar. Backs the "Show menu bar icon" button.
    /// The rebuild can silently lose to a full bar or to a menu bar manager app
    /// stuffing the fresh item into its hidden section, so
    /// after the frame settles this checks the icon really made it on screen
    /// and, if not, says so instead of looking like the button did nothing.
    func reshowStatusItem() {
        // The button is an explicit "I want the icon back": neither hiding
        // option may immediately re-hide what the user just asked to see
        // (and then trip the "still hidden" alert).
        StatusItemRecovery.clearIconHiding(in: .standard)
        guard !isReshowingStatusItem else { return }
        isReshowingStatusItem = true
        statusController?.recreateStatusItem()
        verifyIconReappeared(attemptsLeft: Self.reshowVerifyAttempts)
    }

    /// macOS places a rebuilt status item on its own schedule, and a busy bar
    /// can take longer than one look to settle. Judging it once meant a slow
    /// placement read as a failure and the person was told the bar was full
    /// when it was not, so the answer is asked for several times before
    /// anything is said. A newborn item also reports a zero-height frame for
    /// a few seconds (#1394); that settling grace is separate from the
    /// "still hidden" countdown so recovery does not burn the arranged spot
    /// while macOS is still placing the window.
    private var isReshowingStatusItem = false
    private static let reshowVerifyAttempts = 6
    // A default argument, which is evaluated outside the main actor.
    nonisolated private static let reshowSettlingGraceAttempts = 8
    private static let reshowVerifyInterval: TimeInterval = 0.8

    private func verifyIconReappeared(attemptsLeft: Int,
                                      settlingGraceLeft: Int = AppDelegate.reshowSettlingGraceAttempts,
                                      placementWasReset: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reshowVerifyInterval) { [weak self] in
            guard let self else { return }
            let step = StatusItemRecovery.reshowStep(
                // A later choice to hide the icon cancels the explicit recovery.
                hidingChosen: UserDefaults.standard[Preferences.menuBarHideIconWithMetrics]
                    || MenuBarSpacingSupport.islandHidesStatusIcon(
                        in: .standard, hiddenInFullscreen: self.statusController?.islandHiddenInFullscreen == true),
                isOnScreen: self.iconIsOnScreen(),
                isSettling: self.iconIsSettling(),
                settlingGraceLeft: settlingGraceLeft,
                attemptsLeft: attemptsLeft,
                placementWasReset: placementWasReset,
                allowance: { MenuBarAllowanceSupport.currentAllowance() })
            switch step {
            case .stop:
                self.isReshowingStatusItem = false
            case .appeared:
                self.isReshowingStatusItem = false
                self.logStatusItemPlacement("appeared")
            case .waitForSettling:
                self.logStatusItemPlacement("settling")
                self.verifyIconReappeared(attemptsLeft: attemptsLeft,
                                          settlingGraceLeft: settlingGraceLeft - 1,
                                          placementWasReset: placementWasReset)
            case .lookAgain:
                self.verifyIconReappeared(attemptsLeft: attemptsLeft - 1,
                                          settlingGraceLeft: settlingGraceLeft,
                                          placementWasReset: placementWasReset)
            case .resetPlacement:
                // Keeping the arranged spot did not bring the icon back, so the
                // saved position is itself part of what macOS will not show. Start
                // the item over completely and look again before telling anyone
                // there is nothing left to try.
                self.logStatusItemPlacement("resetting placement")
                self.statusController?.resetStatusItemPlacementIdentity()
                self.verifyIconReappeared(attemptsLeft: Self.reshowVerifyAttempts,
                                          settlingGraceLeft: Self.reshowSettlingGraceAttempts,
                                          placementWasReset: true)
            case .reportDisallowed, .reportStillHidden:
                // With the app switched off under System Settings > Menu Bar >
                // "Allow in the Menu Bar" (macOS 26), macOS never places the item
                // whatever its identity, so the alert names the switch (#1394).
                self.isReshowingStatusItem = false
                self.logStatusItemPlacement(step == .reportDisallowed ? "disallowed by system" : "still hidden")
                let s = L10n.shared.s
                let body = StatusItemRecovery.alertBody(
                    for: step, strings: s,
                    menuBarManager: step == .reportStillHidden ? Self.runningMenuBarManagerName() : nil) ?? ""
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = s.menuBarIconStillHiddenTitle
                alert.informativeText = body
                alert.runModal()
            }
        }
    }

    /// Known menu bar organizers, by bundle id; any of them can be holding
    /// the icon in its hidden section, which explains it never reappearing
    /// on this machine. The hint names whichever one is running by its own
    /// localized app name.
    private static let menuBarManagerBundlePrefixes = [
        "com.jordanbaird.Ice",
        "com.surteesstudios.Bartender",
        "com.dwarvesv.minimalbar",
        "com.mortenjust.Dozer",
    ]

    private static func runningMenuBarManagerName() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            if menuBarManagerBundlePrefixes.contains(where: { bundleID.hasPrefix($0) }) {
                return app.localizedName
            }
        }
        return nil
    }

    /// Quits and reopens the app. Full Disk Access only applies to a fresh
    /// process, so this is how the uninstaller picks up a just-granted grant.
    func relaunchApp() {
        FeatureRuntime.shared.relaunchApp()
    }

    func showOnboarding(mode: OnboardingMode = .full) {
        closePopover()
        if let window = onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(mode: mode) { [weak self] in
            self?.introSequence.markOnboardingComplete()
            self?.onboardingWindow?.close()
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        let isFirstRun = !UserDefaults.standard.bool(forKey: DefaultsKey.hasOnboarded)
        window.title = mode.title(L10n.shared.s)
        window.styleMask = isFirstRun
            ? [.titled, .fullSizeContentView]
            : [.titled, .closable, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = isFirstRun
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.onboardingWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    private func brightnessSetupNeeded() -> Bool {
        let defaults = UserDefaults.standard
        return BrightnessUpdatePromptInfo.needsSetup(
            notchAvailable: AppFeature.notch.isAvailable,
            brightnessAvailable: AppFeature.brightness.isAvailable,
            notchEnabled: defaults[Preferences.notchEnabled],
            notchBrightness: defaults[Preferences.notchBrightness],
            brightnessEnabled: defaults[Preferences.brightnessControlEnabled])
    }

    private func queueBrightnessUpdatePromptIfNeeded(previousVersion: String?) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: DefaultsKey.brightnessUpdatePromptState) == nil,
              !AppInfo.isDeveloperBuild,
              BrightnessUpdatePromptInfo.isUpgrade(appVersion: AppInfo.version,
                                                   previousVersion: previousVersion) else { return }
        defaults.set(brightnessSetupNeeded() ? BrightnessUpdatePromptInfo.pending : BrightnessUpdatePromptInfo.handled,
                     forKey: DefaultsKey.brightnessUpdatePromptState)
    }

    private func showBrightnessUpdatePromptIfNeeded() {
        let defaults = UserDefaults.standard
        guard !isTerminating,
              defaults.string(forKey: DefaultsKey.brightnessUpdatePromptState)
                == BrightnessUpdatePromptInfo.pending else { return }
        guard brightnessSetupNeeded() else {
            defaults.set(BrightnessUpdatePromptInfo.handled, forKey: DefaultsKey.brightnessUpdatePromptState)
            return
        }
        let language = L10n.shared.language
        let strings = FeatureStrings.brightness(language)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = strings.islandPromptTitle
        alert.informativeText = strings.islandPromptMessage
        alert.addButton(withTitle: FeatureStrings.commandBar(language).actionOpenSettings)
        // The invitation is not repeated, so the other choice says what stays.
        alert.addButton(withTitle: strings.islandPromptKeepOff)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        defaults.set(BrightnessUpdatePromptInfo.handled, forKey: DefaultsKey.brightnessUpdatePromptState)
        if response == .alertFirstButtonReturn {
            SettingsRouter.shared.request(AppFeature.brightness.settingsDestination)
            openSettingsWindow()
        }
    }

    func showUpdateHighlights(isReview: Bool = false) {
        introSequence.showHighlights(isReview: isReview)
    }

    /// The window `introSequence` asks for; true when it opened a new one.
    private func openIntroWindow(_ intro: UpdateIntroSequence.Intro) -> Bool {
        switch intro {
        case .highlights: return openUpdateHighlightsWindow()
        case .support: return openSupportIntroWindow()
        case .showcase: return openUpdateShowcaseWindow()
        }
    }

    private func openUpdateHighlightsWindow() -> Bool {
        closePopover()
        if let window = updateHighlightsWindow {
            centerIntroWindow(window)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return false
        }
        let host = NSHostingController(rootView: UpdateHighlightsView(
            onFinish: { [weak self] in self?.updateHighlightsWindow?.close() }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSPanel(contentViewController: host)
        window.title = L10n.shared.s.highlightsTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.delegate = self
        centerIntroWindow(window)
        updateHighlightsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateHighlightsWindow else { return }
            self.centerIntroWindow(window)
        }
        return true
    }

    func openSettingsFromHighlights() {
        openSettingsWindow()
        // Run after Settings has applied its own initial placement. Ordering the
        // panel does not take keyboard focus away from the configuration controls.
        DispatchQueue.main.async { [weak self] in
            guard let self, let tour = self.updateHighlightsWindow, tour.isVisible else { return }
            self.positionTourBesideSettings(tour)
            tour.orderFront(nil)
        }
    }

    private func positionTourBesideSettings(_ tour: NSWindow) {
        guard let settings = settingsWindow, settings.isVisible else { return }
        let visible = tour.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let placement = SettingsWindowSupport.tourPlacement(
            settingsSize: settings.frame.size, tourSize: tour.frame.size, visibleFrame: visible)
        settings.setFrameOrigin(placement.settings.origin)
        tour.setFrameOrigin(placement.tour.origin)
    }

    private func openUpdateShowcaseWindow() -> Bool {
        closePopover()
        if let window = updateShowcaseWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return false
        }
        let host = NSHostingController(rootView: UpdateShowcaseIntroView(
            onClose: { [weak self] in
                self?.introSequence.markShowcaseSeen()
                self?.updateShowcaseWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.updateShowcaseTitle
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        updateShowcaseWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updateShowcaseWindow else { return }
            self.centerIntroWindow(window)
        }
        return true
    }

    private func openSupportIntroWindow() -> Bool {
        closePopover()
        if let window = supportIntroWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return false
        }
        let host = NSHostingController(rootView: UpdateSupportIntroView(
            onFinish: { [weak self] in
                self?.introSequence.allowSupportToClose()
                self?.supportIntroWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSPanel(contentViewController: host)
        window.title = L10n.shared.s.supportIntroTitle
        window.styleMask = [.titled, .fullSizeContentView]
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.delegate = self
        centerIntroWindow(window)
        supportIntroWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.supportIntroWindow else { return }
            self.centerIntroWindow(window)
            self.positionTourBesideSettings(window)
        }
        return true
    }

    /// Centers one of the windows whose content decides its own size (the
    /// onboarding, the tour, the release notes and the two intros). The size
    /// always comes from the view itself: asking for any other size leaves
    /// the layout engine correcting a window that was already placed, and on
    /// some systems that ends the app instead of settling. The origin is kept
    /// inside the visible area, so a window taller than the screen starts at
    /// the top instead of hanging below it.
    private func centerIntroWindow(_ window: NSWindow) {
        let visible = (window.screen ?? popover.contentViewController?.view.window?.screen)?.visibleFrame ?? NSScreen.pointerVisibleFrame
        if let host = window.contentViewController as? NSHostingController<UpdateHighlightsView>,
           host.rootView.availableSize != visible.size {
            host.rootView.availableSize = visible.size
        }
        window.contentView?.layoutSubtreeIfNeeded()
        if let fitting = window.contentViewController?.view.fittingSize,
           fitting.width > 0, fitting.height > 0 {
            window.setContentSize(fitting)
        }
        let size = window.frame.size
        let x = min(max(visible.midX - size.width / 2, visible.minX), max(visible.minX, visible.maxX - size.width))
        let y = min(max(visible.midY - size.height / 2, visible.minY), max(visible.minY, visible.maxY - size.height))
        window.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// The pre-install update preview, shown before any download from BOTH the
    /// Settings install button and the menu panel's update banner (the blue
    /// button most people use), so the changelog is always seen first. In the
    /// Developer build `downloadAndInstall()` is a no-op, so confirming is safe.
    func showUpdatePreview() {
        guard case let .available(version) = UpdateService.shared.state else { return }
        closePopover()
        if let window = updatePreviewWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: UpdatePreviewView(
            version: version,
            notes: UpdateService.shared.availableNotes,
            onUpdate: { [weak self] in
                self?.updatePreviewWindow?.close()
                UpdateService.shared.downloadAndInstall()
            },
            onCancel: { [weak self] in
                self?.updatePreviewWindow?.close()
            }
        ))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = L10n.shared.s.tabReleaseNotes
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        centerIntroWindow(window)
        updatePreviewWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, window === self.updatePreviewWindow else { return }
            self.centerIntroWindow(window)
        }
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if sender === settingsWindow {
            let minFrame = sender.frameRect(forContentRect: NSRect(
                x: 0, y: 0,
                width: SettingsWindowSupport.minContentWidth,
                height: SettingsWindowSupport.minContentHeight
            )).size
            return NSSize(
                width: max(frameSize.width, minFrame.width),
                height: max(frameSize.height, minFrame.height)
            )
        }
        return frameSize
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        saveSettingsWindowSize(window)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        // Minimized, on another Space or covered, Settings draws for nobody too.
        SettingsWindowVisibility.shared.set(window.isVisible && window.occlusionState.contains(.visible))
    }

    /// Remembers the user-chosen Settings size (as content size, so the
    /// restore is title bar independent).
    private func saveSettingsWindowSize(_ window: NSWindow) {
        guard let size = window.contentView?.frame.size else { return }
        guard SettingsWindowSupport.isValidContentSize(width: Double(size.width),
                                                      height: Double(size.height)) else { return }
        UserDefaults.standard.set(Double(size.width), forKey: DefaultsKey.settingsWindowWidth)
        UserDefaults.standard.set(Double(size.height), forKey: DefaultsKey.settingsWindowHeight)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === supportIntroWindow else { return true }
        return introSequence.shouldCloseSupport()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            // Covers size changes that end without a live resize (zoom).
            saveSettingsWindowSize(window)
            settingsActivation.windowClosed()
            // Whatever page was showing, its own onDisappear does not always
            // run before the window finishes closing; stop the poll from
            // here too rather than let it run until the app quits. The
            // page's own demand is left alone, so it resumes on its own the
            // moment the window reopens, on this page or any other.
            SecureInputMonitor.shared.setSettingsWindowOpen(false)
            SettingsWindowVisibility.shared.set(false)
            return
        }
        if window === onboardingWindow {
            onboardingWindow = nil
            // First run has no close action; it reaches here after completion.
            // A system relaunch while granting access must not mark the flow
            // complete, so it resumes at the same step.
            guard !isTerminating else { return }
            introSequence.markOnboardingComplete()
        }
        if window === supportIntroWindow {
            supportIntroWindow = nil
            introSequence.closed(.support)
        }
        if window === updateShowcaseWindow {
            updateShowcaseWindow = nil
            introSequence.closed(.showcase)
        }
        if window === updateHighlightsWindow {
            updateHighlightsWindow = nil
            introSequence.closed(.highlights)
        }
        if window === updatePreviewWindow {
            updatePreviewWindow = nil
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // The center picks the thread; the work below hops to the main one itself.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let transactionID = Notifier.whatsAppOrganizerTransactionID(from: response) {
            DispatchQueue.main.async {
                WhatsAppDownloadOrganizer.shared.undoLastRun(transactionID: transactionID)
            }
        }
        completionHandler()
    }
}
