// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import IOKit.pwr_mgt
import os
import VitruvianCore
import VitruvianDesign

/// Core of the energy feature: manages "keep awake" sessions through IOKit power
/// assertions, the closed-lid mode (pmset disablesleep, administrator password)
/// and the battery protection watchdog.
@MainActor
package final class KeepAwakeManager: ObservableObject {
    /// What the manager asks of the system. `live` is the system's own; a test
    /// passes doubles, so it can neither disable sleep, sleep the Mac nor dim
    /// its panel.
    package struct System: @unchecked Sendable {
        package var defaults: UserDefaults
        /// Where settings changes are announced.
        package var notificationCenter: NotificationCenter
        /// The `pmset disablesleep` override and its sudoers rule.
        package var sleep: SleepOverride
        /// `pmset -g`, read off the main thread.
        package var pmsetReport: @Sendable () -> (status: Int32, output: String)
        package var background: @Sendable (DispatchQoS.QoSClass, @escaping @Sendable () -> Void) -> Void
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var after: @Sendable (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
        /// Blocks the main thread between quit's lid-sleep attempts.
        package var wait: @MainActor (TimeInterval) -> Void
        /// Puts a session, battery or pointer timer on the main run loop.
        package var schedule: @MainActor (Timer) -> Void
        /// Takes a power assertion of an IOKit type and name; nil when refused.
        package var assert: @MainActor (_ type: String, _ name: String) -> IOPMAssertionID?
        package var releaseAssertion: @MainActor (IOPMAssertionID) -> Void
        package var battery: @MainActor () -> BatteryInfo?
        /// Reports each screen lock (true) and unlock (false); the returned
        /// closure stops it.
        package var watchLock: @MainActor (_ changed: @escaping @MainActor @Sendable (Bool) -> Void) -> () -> Void
        /// The login session's state, read when lock monitoring starts.
        package var session: @MainActor () -> [String: Any]?
        package var lidClosed: @MainActor () -> Bool?
        /// Whether the system's own policy sleeps the Mac when its lid closes.
        package var clamshellCausesSleep: @MainActor () -> Bool?
        /// Every process's power assertions, or nil when they cannot be read.
        package var powerAssertions: @MainActor () -> [[String: Any]]?
        /// Asks the system to sleep: its IOKit result, or nil without a power manager.
        package var sleepSystem: @MainActor () -> IOReturn?
        /// Runs `changed` on the main queue for each of the power manager's
        /// general-interest notifications, the lid's among them. The returned
        /// closure stops it; nil when it could not start.
        package var watchLid: @MainActor (_ changed: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)?
        package var panelBrightness: @MainActor () -> Double?
        /// Writes the built-in panel's brightness; false when it found no panel.
        package var setPanelBrightness: @MainActor (Double) -> Bool

        package init(defaults: UserDefaults, notificationCenter: NotificationCenter, sleep: SleepOverride,
                     pmsetReport: @escaping @Sendable () -> (status: Int32, output: String),
                     background: @escaping @Sendable (DispatchQoS.QoSClass, @escaping @Sendable () -> Void) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     after: @escaping @Sendable (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void,
                     wait: @escaping @MainActor (TimeInterval) -> Void,
                     schedule: @escaping @MainActor (Timer) -> Void,
                     assert: @escaping @MainActor (String, String) -> IOPMAssertionID?,
                     releaseAssertion: @escaping @MainActor (IOPMAssertionID) -> Void,
                     battery: @escaping @MainActor () -> BatteryInfo?,
                     watchLock: @escaping @MainActor (@escaping @MainActor @Sendable (Bool) -> Void) -> () -> Void,
                     session: @escaping @MainActor () -> [String: Any]?,
                     lidClosed: @escaping @MainActor () -> Bool?,
                     clamshellCausesSleep: @escaping @MainActor () -> Bool?,
                     powerAssertions: @escaping @MainActor () -> [[String: Any]]?,
                     sleepSystem: @escaping @MainActor () -> IOReturn?,
                     watchLid: @escaping @MainActor (@escaping @MainActor @Sendable () -> Void) -> (() -> Void)?,
                     panelBrightness: @escaping @MainActor () -> Double?,
                     setPanelBrightness: @escaping @MainActor (Double) -> Bool) {
            self.defaults = defaults
            self.notificationCenter = notificationCenter
            self.sleep = sleep
            self.pmsetReport = pmsetReport
            self.background = background
            self.main = main
            self.after = after
            self.wait = wait
            self.schedule = schedule
            self.assert = assert
            self.releaseAssertion = releaseAssertion
            self.battery = battery
            self.watchLock = watchLock
            self.session = session
            self.lidClosed = lidClosed
            self.clamshellCausesSleep = clamshellCausesSleep
            self.powerAssertions = powerAssertions
            self.sleepSystem = sleepSystem
            self.watchLid = watchLid
            self.panelBrightness = panelBrightness
            self.setPanelBrightness = setPanelBrightness
        }
    }

    package static let shared = KeepAwakeManager(system: .live)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian",
                                    category: "keep-awake")

    package enum EndReason { case manual, timer, battery, quit }
    package enum SessionTrigger { case manual, automation }

    @Published package private(set) var isActive = false
    @Published package private(set) var endDate: Date? // nil = indefinite
    @Published package private(set) var sessionTrigger: SessionTrigger?
    /// The preset a manual session started from; nil for an end time or automation.
    @Published package private(set) var sessionMinutes: Int?
    @Published package private(set) var runningAppBundleIDs: [String] = []
    @Published package private(set) var activeAutomationConditions = Set<KeepAwakeAutomationCondition>()
    @Published package private(set) var clamshellActive = false {
        didSet {
            guard clamshellActive != oldValue else { return }
            syncLidDimmingObserver()
        }
    }
    @Published package private(set) var passwordlessClamshell = false
    @Published package private(set) var clamshellSetupInProgress = false
    @Published package private(set) var clamshellSetupFailed = false

    /// Persistent preference: when on, every keep-awake session also disables
    /// lid sleep, and ending the session restores it — no per-session setup.
    @Published package var clamshellPreferred: Bool {
        didSet {
            guard clamshellPreferred != oldValue else { return }
            system.defaults.set(clamshellPreferred, forKey: DefaultsKey.clamshellPreferred)
            clamshellSetupFailed = false
            guard !isTerminating else { return }
            if clamshellPreferred {
                if !sessionPausedForScreenLock { applyClamshellPreference() }
            } else if clamshellNeedsRestore {
                clamshellSetupInProgress = false
                clamshellSetupID = nil
                disableClamshell(synchronous: false)
            } else {
                clamshellSetupInProgress = false
                clamshellSetupID = nil
            }
        }
    }

    /// Persistent preference: dims the built-in display to zero while the
    /// closed-lid mode is actually in effect, restoring the captured
    /// brightness when the lid opens again.
    @Published package var dimScreenOnLidClose: Bool {
        didSet {
            guard dimScreenOnLidClose != oldValue else { return }
            system.defaults.set(dimScreenOnLidClose, forKey: DefaultsKey.dimScreenOnLidClose)
            if !dimScreenOnLidClose { applyDimmingAction(LidDimmingSupport.restoring(saved: savedDisplayBrightness)) }
            syncLidDimmingObserver()
        }
    }

    package var onSessionEnded: ((EndReason) -> Void)?

    nonisolated private let system: System
    private var systemAssertion = IOPMAssertionID(0)
    private var displayAssertion = IOPMAssertionID(0)
    private var hasSystemAssertion = false
    private var hasDisplayAssertion = false
    private var endTimer: Timer?
    private var batteryTimer: Timer?
    private var mouseJiggleTimer: Timer?
    private var pendingMouseReturn: DispatchWorkItem?
    private var defaultsObserver: AnyCancellable?
    private var screenParametersObserver: NSObjectProtocol?
    private var endLockWatch: (() -> Void)?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var runningAppsObservers: [NSObjectProtocol] = []
    private var automationEvaluationWorkItem: DispatchWorkItem?
    private var lastExternalDisplayConnected: Bool?
    private var screenLocked = false
    private var sessionPausedForScreenLock = false
    private var automationSuppressedUntilConditionsClear = false
    private var recoveryCompleted = false
    private var isTerminating = false
    private var clamshellEnablePending = false
    private var clamshellRestorePending = false
    private var clamshellOperationGeneration = 0
    private var clamshellSetupID: UUID?
    private var lidSleepGeneration = 0
    private var lidSleepAttemptsRemaining = 0
    private var endLidWatch: (() -> Void)?
    private var lidClosedForDimming: Bool?
    private var savedDisplayBrightness: Double?
    /// Guards the closed-lid setup against an infinite retry loop: if `pmset
    /// disablesleep` keeps failing while the sudoers rule still checks out as
    /// installed, re-preparing would bounce here forever (and flicker the
    /// caption). One automatic re-acquire per user attempt, then we give up.
    private var clamshellSetupRetried = false
    /// A reply to a settings change already waiting for the next run loop turn.
    private var preferenceSyncScheduled = false

    package init(system: System) {
        self.system = system
        clamshellPreferred = system.defaults.bool(forKey: DefaultsKey.clamshellPreferred)
        dimScreenOnLidClose = system.defaults.bool(forKey: DefaultsKey.dimScreenOnLidClose)
        refreshPasswordlessStatus()
        // Every settings write announces itself, including the ones made from
        // inside this class, so a burst folds into a single reply on the next
        // turn of the run loop rather than one full pass per write.
        defaultsObserver = system.notificationCenter
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, !self.preferenceSyncScheduled else { return }
                self.preferenceSyncScheduled = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.preferenceSyncScheduled = false
                    self.syncWithPreferences()
                }
            }
    }

    /// Refreshes (in the background) whether the closed-lid sudoers rule is installed.
    package func refreshPasswordlessStatus() {
        guard !isTerminating, !clamshellRestorePending else { return }
        let generation = clamshellOperationGeneration
        let system = self.system
        system.background(.utility) {
            let configured = system.sleep.isConfigured()
            system.main {
                guard !self.isTerminating, !self.clamshellRestorePending,
                      self.clamshellOperationGeneration == generation else { return }
                self.passwordlessClamshell = configured
            }
        }
    }

    /// Clearing permissions, or an uninstall that stopped, restored normal
    /// sleep directly and left this app running. Discard the old session state
    /// without asking for the rule again: a rule that is still installed rearms
    /// the current session, and a removed one is requested by the next session.
    package func resumeAfterSystemTeardown() {
        let restorePending = clamshellRestorePending
        if !restorePending { clamshellOperationGeneration &+= 1 }
        // An installation prompt may already be open. Its existing reply can
        // finish setup without showing a second authorization request.
        clamshellEnablePending = false
        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        clamshellActive = false
        passwordlessClamshell = false
        let generation = clamshellOperationGeneration
        let checksSleep = system.defaults.bool(forKey: DefaultsKey.sleepDisabledFlag)
        let system = self.system
        system.background(.utility) {
            // A session can start while the removal waits for its password and
            // turn sleep off again through the rule. Only a reading that answered
            // "on" lets the recovery marker go.
            var sleepRestored = true
            if checksSleep {
                let report = system.pmsetReport()
                sleepRestored = report.status == 0
                    && !SudoersSupport.sleepDisabled(inPmsetOutput: report.output)
            }
            let configured = !restorePending && system.sleep.isConfigured()
            system.main {
                guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                if checksSleep, sleepRestored {
                    system.defaults.set(false, forKey: DefaultsKey.sleepDisabledFlag)
                }
                // A prior restore can still finish with an authorized off. Its
                // reply rearms this session in order after that operation.
                guard !restorePending, !self.clamshellRestorePending else { return }
                self.passwordlessClamshell = configured
                if configured, self.clamshellPreferred, AppFeature.keepAwake.isAvailable(in: system.defaults) {
                    self.enableClamshell()
                }
            }
        }
    }

    // MARK: - Session

    package func toggle() {
        if isActive {
            if sessionTrigger == .automation || automationConditionsHold() {
                automationSuppressedUntilConditionsClear = true
            }
            deactivate(reason: .manual)
        } else {
            startLastPick()
        }
    }

    /// Keep Awake leaving the hub ends any running session; everything else
    /// (saved duration, tint, shortcut setting) stays for its return.
    package func syncWithFeatures() {
        guard AppFeature.keepAwake.isAvailable(in: system.defaults) else {
            stopAutomationMonitoring()
            if isActive { deactivate(reason: .manual) }
            return
        }
        syncWithPreferences()
    }

    package func syncWithPreferences() {
        guard !isTerminating else { return }
        syncAutomationMonitoring()
        if isActive, !sessionPausedForScreenLock { applyAssertions() }
        syncMouseJiggleTimer()
    }

    /// Called by automation controls so a deliberate preference change can
    /// resume evaluation after a manually stopped automatic session.
    package func automationPreferencesDidChange() {
        automationSuppressedUntilConditionsClear = false
        syncWithPreferences()
    }

    /// `minutes <= 0` activates indefinitely.
    package func activate(minutes: Int) {
        automationSuppressedUntilConditionsClear = false
        let minutes = Defaults.sanitizedDefaultDuration(minutes)
        let end = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes) * 60) : nil
        activate(end: end, trigger: .manual)
        sessionMinutes = isActive ? minutes : nil
        guard isActive else { return }
        // Every entry point records the pick, so each switch restarts the same session.
        system.defaults.set(minutes, forKey: DefaultsKey.defaultDuration)
        system.defaults.set(false, forKey: DefaultsKey.keepAwakeSwitchUsesUntil)
    }

    package func activate(until date: Date) {
        guard date > Date() else { return }
        automationSuppressedUntilConditionsClear = false
        activate(end: date, trigger: .manual)
        // An end time replaces any running preset, so no duration chip stays selected.
        sessionMinutes = nil
        guard isActive else { return }
        system.defaults.set(true, forKey: DefaultsKey.keepAwakeSwitchUsesUntil)
        system.defaults.set(date.timeIntervalSinceReferenceDate, forKey: DefaultsKey.keepAwakeUntilTime)
    }

    /// Restarts the last pick: the saved end time while it is still ahead,
    /// otherwise the saved duration. A passed end time never rolls to
    /// tomorrow here, which would silently start a session of almost a day.
    package func startLastPick() {
        let defaults = system.defaults
        let end = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: DefaultsKey.keepAwakeUntilTime))
        if defaults.bool(forKey: DefaultsKey.keepAwakeSwitchUsesUntil), end > Date() {
            activate(until: end)
        } else {
            activate(minutes: Defaults.sanitizedDefaultDuration(defaults.integer(forKey: DefaultsKey.defaultDuration)))
        }
    }

    private func activate(end: Date?, trigger: SessionTrigger) {
        guard !isTerminating, AppFeature.keepAwake.isAvailable(in: system.defaults) else { return }
        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        endTimer?.invalidate()
        endTimer = nil
        syncScreenLockMonitoring()
        sessionPausedForScreenLock = screenLocked
            && system.defaults.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked)
        if !sessionPausedForScreenLock { applyAssertions() }
        sessionTrigger = trigger
        if trigger == .manual {
            activeAutomationConditions.removeAll()
        }
        isActive = true
        if let end {
            endDate = end
            scheduleEnd(at: end)
        } else {
            endDate = nil
        }
        if !sessionPausedForScreenLock { startBatteryWatch() }
        syncMouseJiggleTimer()
        if clamshellPreferred, !sessionPausedForScreenLock {
            applyClamshellPreference()
        }
    }

    package func activateOnLaunchIfNeeded() {
        guard AppFeature.keepAwake.isAvailable(in: system.defaults),
              system.defaults.bool(forKey: DefaultsKey.keepAwakeAutoStart),
              !isActive else { return }
        activate(minutes: Defaults.sanitizedDefaultDuration(
            system.defaults.integer(forKey: DefaultsKey.defaultDuration)))
    }

    package func extend(minutes: Int) {
        guard isActive, let current = endDate else { return }
        let newEnd = max(current, Date()).addingTimeInterval(TimeInterval(minutes) * 60)
        endDate = newEnd
        scheduleEnd(at: newEnd)
    }

    package func deactivate(reason: EndReason) {
        let hadSession = isActive
        if reason == .quit {
            isTerminating = true
            clamshellSetupID = nil
            clamshellSetupInProgress = false
            stopAutomationMonitoring()
        }
        endTimer?.invalidate()
        endTimer = nil
        endDate = nil
        releaseAssertions()
        sessionTrigger = nil
        sessionMinutes = nil
        activeAutomationConditions.removeAll()
        isActive = false
        sessionPausedForScreenLock = false
        stopBatteryWatch()
        stopMouseJiggleTimer()
        // An enable can still be on the serialized native queue even though
        // its main-thread reply has not marked the session active yet.
        if clamshellNeedsRestore {
            disableClamshell(synchronous: reason == .quit)
        } else if reason == .quit, lidSleepAttemptsRemaining > 0 {
            sleepIfLidAlreadyClosed(attemptsLeft: lidSleepAttemptsRemaining, synchronous: true)
        }
        if hadSession, reason != .quit, reason != .manual {
            onSessionEnded?(reason)
        }
    }

    // MARK: - Automatic sessions

    private func syncAutomationMonitoring() {
        let available = AppFeature.keepAwake.isAvailable(in: system.defaults)
        let selectedApps = Defaults.sanitizedBundleIdentifierList(
            system.defaults.stringArray(forKey: DefaultsKey.keepAwakeRunningAppBundleIDs) ?? [])
        if runningAppBundleIDs != selectedApps { runningAppBundleIDs = selectedApps }
        syncScreenLockMonitoring()
        let observeScreens = available
            && system.defaults.bool(forKey: DefaultsKey.keepAwakeExternalDisplay)
        let observePower = available
            && system.defaults.bool(forKey: DefaultsKey.keepAwakeConnectedToPower)
        let observeRunningApps = available
            && system.defaults.bool(forKey: DefaultsKey.keepAwakeRunningApps)
            && !runningAppBundleIDs.isEmpty

        setScreenMonitoringEnabled(observeScreens)
        setPowerMonitoringEnabled(observePower)
        setRunningAppsMonitoringEnabled(observeRunningApps)
        evaluateAutomation()
    }

    private func syncScreenLockMonitoring() {
        let enabled = AppFeature.keepAwake.isAvailable(in: system.defaults)
            && system.defaults.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked)

        if enabled {
            guard endLockWatch == nil else { return }
            endLockWatch = system.watchLock { [weak self] locked in
                self?.screenLockStateDidChange(locked: locked)
            }
            screenLocked = KeepAwakeAutomationSupport.isScreenLocked(sessionDictionary: system.session())
            syncSessionWithScreenLock()
        } else {
            guard let endLockWatch else { return }
            endLockWatch()
            self.endLockWatch = nil
            screenLocked = false
            syncSessionWithScreenLock()
        }
    }

    private func screenLockStateDidChange(locked: Bool) {
        guard screenLocked != locked else { return }
        screenLocked = locked
        syncSessionWithScreenLock()
        evaluateAutomation()
    }

    private func syncSessionWithScreenLock() {
        guard isActive else {
            sessionPausedForScreenLock = false
            return
        }
        let shouldPause = screenLocked
            && system.defaults.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked)
        guard shouldPause != sessionPausedForScreenLock else { return }

        if shouldPause {
            sessionPausedForScreenLock = true
            releaseAssertions()
            if clamshellNeedsRestore { disableClamshell(synchronous: false) }
            stopBatteryWatch()
            stopMouseJiggleTimer()
            return
        }

        sessionPausedForScreenLock = false
        if let endDate, endDate <= Date() {
            if !continueAutomaticallyAfterTimerIfNeeded() { deactivate(reason: .timer) }
            return
        }
        if sessionTrigger == .automation, !automationConditionsHold() {
            deactivate(reason: .manual)
            return
        }
        startBatteryWatch()
        guard isActive else { return }
        applyAssertions()
        syncMouseJiggleTimer()
        if clamshellPreferred { applyClamshellPreference() }
    }

    private func setScreenMonitoringEnabled(_ enabled: Bool) {
        if enabled {
            guard screenParametersObserver == nil else { return }
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.scheduleAutomationEvaluation(after: 0.35) }
            }
        } else if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
            lastExternalDisplayConnected = nil
        }
    }

    private func setPowerMonitoringEnabled(_ enabled: Bool) {
        if enabled {
            guard powerSourceRunLoopSource == nil else { return }
            let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let manager = Unmanaged<KeepAwakeManager>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.scheduleAutomationEvaluation(after: 0.1)
                }
            }, context)?.takeRetainedValue()
            if let powerSourceRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            }
        } else if let powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
            self.powerSourceRunLoopSource = nil
        }
    }

    private func setRunningAppsMonitoringEnabled(_ enabled: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        if enabled {
            guard runningAppsObservers.isEmpty else { return }
            let handler: @Sendable (Notification) -> Void = { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.scheduleAutomationEvaluation(after: 0.1) }
            }
            runningAppsObservers = [
                center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                   object: nil, queue: .main, using: handler),
                center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                   object: nil, queue: .main, using: handler),
            ]
        } else {
            guard !runningAppsObservers.isEmpty else { return }
            for observer in runningAppsObservers { center.removeObserver(observer) }
            runningAppsObservers.removeAll()
        }
    }

    private func scheduleAutomationEvaluation(after delay: TimeInterval) {
        automationEvaluationWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.automationEvaluationWorkItem = nil
            self?.evaluateAutomation()
        }
        automationEvaluationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func stopAutomationMonitoring() {
        automationEvaluationWorkItem?.cancel()
        automationEvaluationWorkItem = nil
        setScreenMonitoringEnabled(false)
        setPowerMonitoringEnabled(false)
        setRunningAppsMonitoringEnabled(false)
        endLockWatch?()
        endLockWatch = nil
        screenLocked = false
        sessionPausedForScreenLock = false
        activeAutomationConditions.removeAll()
    }

    private func evaluateAutomation() {
        guard recoveryCompleted, !isTerminating else { return }
        let matches = currentMatchingAutomationConditions()
        let enabled = currentEnabledAutomationConditions()
        let requireAll = automationRequiresAllConditions()
        let satisfied = KeepAwakeAutomationSupport.conditionsSatisfied(
            matching: matches, enabled: enabled, requireAll: requireAll)

        if automationSuppressedUntilConditionsClear {
            if !satisfied {
                automationSuppressedUntilConditionsClear = false
            }
            if sessionTrigger == .automation {
                deactivate(reason: .manual)
            }
            return
        }

        if screenLocked,
           system.defaults.bool(forKey: DefaultsKey.keepAwakePauseWhenLocked) {
            if sessionTrigger == .automation { activeAutomationConditions = matches }
            return
        }

        if sessionTrigger == .automation {
            activeAutomationConditions = matches
        }
        let action = KeepAwakeAutomationSupport.action(
            featureAvailable: AppFeature.keepAwake.isAvailable(in: system.defaults),
            matchingConditions: matches,
            enabledConditions: enabled,
            requireAll: requireAll,
            sessionActive: isActive,
            automaticSessionActive: isActive && sessionTrigger == .automation
        )
        switch action {
        case .none:
            break
        case .activate:
            guard automaticSessionAllowedByBatteryProtection() else { return }
            activeAutomationConditions = matches
            activate(end: nil, trigger: .automation)
        case .deactivate:
            deactivate(reason: .manual)
        }
    }

    private func automationRequiresAllConditions() -> Bool {
        system.defaults.bool(forKey: DefaultsKey.keepAwakeAutomationRequireAll)
    }

    private func currentEnabledAutomationConditions() -> Set<KeepAwakeAutomationCondition> {
        KeepAwakeAutomationSupport.enabledConditions(
            externalDisplayEnabled: system.defaults.bool(forKey: DefaultsKey.keepAwakeExternalDisplay),
            powerEnabled: system.defaults.bool(forKey: DefaultsKey.keepAwakeConnectedToPower),
            runningAppsEnabled: system.defaults.bool(forKey: DefaultsKey.keepAwakeRunningApps),
            hasSelectedApps: !runningAppBundleIDs.isEmpty
        )
    }

    /// Whether the automation currently asks for a session, in either match
    /// mode. Every caller that used to read "any condition matches" has to ask
    /// this instead: under All, a session that stops being wanted still has a
    /// non-empty matching set (issue #1587).
    private func automationConditionsHold() -> Bool {
        KeepAwakeAutomationSupport.conditionsSatisfied(
            matching: currentMatchingAutomationConditions(),
            enabled: currentEnabledAutomationConditions(),
            requireAll: automationRequiresAllConditions())
    }

    private func currentMatchingAutomationConditions() -> Set<KeepAwakeAutomationCondition> {
        let externalDisplayEnabled = system.defaults.bool(forKey: DefaultsKey.keepAwakeExternalDisplay)
        let externalDisplayConnected: Bool
        if externalDisplayEnabled {
            if let current = Self.hasExternalDisplay() {
                lastExternalDisplayConnected = current
            }
            externalDisplayConnected = lastExternalDisplayConnected ?? false
        } else {
            externalDisplayConnected = false
        }

        let powerEnabled = system.defaults.bool(forKey: DefaultsKey.keepAwakeConnectedToPower)
        let connectedToPower = powerEnabled
            && (system.battery().map { !$0.isOnBattery } ?? false)

        let runningAppsEnabled = system.defaults.bool(forKey: DefaultsKey.keepAwakeRunningApps)
        let selectedAppsRunning: Bool
        if runningAppsEnabled, !runningAppBundleIDs.isEmpty {
            let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            selectedAppsRunning = KeepAwakeAutomationSupport.selectedAppsAreRunning(
                selectedBundleIDs: runningAppBundleIDs,
                runningBundleIDs: running
            )
        } else {
            selectedAppsRunning = false
        }

        return KeepAwakeAutomationSupport.matchingConditions(
            externalDisplayEnabled: externalDisplayEnabled,
            externalDisplayConnected: externalDisplayConnected,
            powerEnabled: powerEnabled,
            connectedToPower: connectedToPower,
            runningAppsEnabled: runningAppsEnabled,
            selectedAppsRunning: selectedAppsRunning
        )
    }

    private static func hasExternalDisplay() -> Bool? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
        guard count > 0 else { return false }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        let builtInFlags = displays.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 }
        return KeepAwakeAutomationSupport.hasExternalDisplay(builtInFlags: builtInFlags)
    }

    private func automaticSessionAllowedByBatteryProtection() -> Bool {
        let limit = Defaults.sanitizedBatteryLimit(
            system.defaults.integer(forKey: DefaultsKey.batteryLimit)
        )
        guard limit > 0,
              let battery = system.battery(),
              battery.isOnBattery else { return true }
        return battery.percent > limit
    }

    private func continueAutomaticallyAfterTimerIfNeeded() -> Bool {
        guard let matches = Self.timerHandoff(
                trigger: sessionTrigger, suppressed: automationSuppressedUntilConditionsClear,
                in: system.defaults,
                batteryAllows: { automaticSessionAllowedByBatteryProtection() },
                matching: { currentMatchingAutomationConditions() },
                enabled: { currentEnabledAutomationConditions() },
                requireAll: { automationRequiresAllConditions() }) else { return false }
        activeAutomationConditions = matches
        activate(end: nil, trigger: .automation)
        return true
    }

    /// The conditions a timed session that ran out carries on with as an
    /// automatic one, or nil when it ends. The conditions are read only once
    /// the session, the feature, a manual stop and the battery allow it.
    package static func timerHandoff(trigger: SessionTrigger?, suppressed: Bool,
                                     in defaults: UserDefaults = .standard,
                                     batteryAllows: () -> Bool,
                                     matching: () -> Set<KeepAwakeAutomationCondition>,
                                     enabled: () -> Set<KeepAwakeAutomationCondition>,
                                     requireAll: () -> Bool) -> Set<KeepAwakeAutomationCondition>? {
        guard trigger == .manual,
              AppFeature.keepAwake.isAvailable(in: defaults),
              !suppressed,
              batteryAllows() else { return nil }
        // The same full match the automation itself would need to start a
        // session: under All, a timed session must not be handed over on one
        // condition the automation would never have acted on (issue #1587).
        let matches = matching()
        guard KeepAwakeAutomationSupport.conditionsSatisfied(
                matching: matches,
                enabled: enabled(),
                requireAll: requireAll()) else { return nil }
        return matches
    }

    private func scheduleEnd(at date: Date) {
        endTimer?.invalidate()
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            // Added to the main run loop, so it fires on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.continueAutomaticallyAfterTimerIfNeeded() {
                    self.deactivate(reason: .timer)
                }
            }
        }
        system.schedule(t)
        endTimer = t
    }

    // MARK: - IOKit assertions

    private func applyAssertions() {
        if !hasSystemAssertion,
           let id = system.assert("PreventUserIdleSystemSleep", "Vitruvian: keep the Mac awake") {
            systemAssertion = id
            hasSystemAssertion = true
        }
        let allowDisplaySleep = system.defaults.bool(
            forKey: DefaultsKey.keepAwakeAllowDisplaySleep
        )
        if allowDisplaySleep, hasDisplayAssertion {
            system.releaseAssertion(displayAssertion)
            hasDisplayAssertion = false
        } else if !allowDisplaySleep, !hasDisplayAssertion,
                  let id = system.assert("PreventUserIdleDisplaySleep", "Vitruvian: keep the display on") {
            displayAssertion = id
            hasDisplayAssertion = true
        }
    }

    private func releaseAssertions() {
        if hasSystemAssertion {
            system.releaseAssertion(systemAssertion)
            hasSystemAssertion = false
        }
        if hasDisplayAssertion {
            system.releaseAssertion(displayAssertion)
            hasDisplayAssertion = false
        }
    }

    // MARK: - Closed lid (pmset disablesleep)

    private var clamshellNeedsRestore: Bool {
        clamshellActive || clamshellEnablePending || clamshellRestorePending
            || system.defaults.bool(forKey: DefaultsKey.sleepDisabledFlag)
    }

    private func applyClamshellPreference() {
        guard !isTerminating, !clamshellRestorePending else { return }
        // A fresh user-driven attempt (toggle on, or a new session) gets one
        // automatic setup retry again.
        clamshellSetupRetried = false
        if passwordlessClamshell {
            if isActive, !sessionPausedForScreenLock {
                enableClamshell()
            }
        } else {
            prepareClamshellPreference()
        }
    }

    private func prepareClamshellPreference() {
        guard !isTerminating, !clamshellRestorePending,
              clamshellPreferred, !clamshellSetupInProgress else { return }
        let requestID = UUID()
        clamshellSetupID = requestID
        clamshellSetupInProgress = true
        clamshellSetupFailed = false

        let system = self.system
        system.background(.userInitiated) {
            let configured = system.sleep.isConfigured()
            system.main {
                guard !self.isTerminating, self.clamshellSetupID == requestID else { return }
                if configured {
                    self.finishClamshellSetup(ok: true, requestID: requestID)
                } else {
                    system.sleep.install { ok in
                        system.main {
                            self.finishClamshellSetup(ok: ok, requestID: requestID)
                        }
                    }
                }
            }
        }
    }

    private func finishClamshellSetup(ok: Bool, requestID: UUID) {
        guard !isTerminating, clamshellSetupID == requestID else { return }
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        passwordlessClamshell = ok

        guard ok else {
            markClamshellSetupFailed()
            return
        }

        if isActive, clamshellPreferred, !sessionPausedForScreenLock {
            enableClamshell()
        }
    }

    /// Turns the preference back off and surfaces the error, ending any retry
    /// loop. Setting `clamshellPreferred` false runs its `didSet`, which clears
    /// the in-progress/failed flags, so the failure flag is raised afterwards.
    private func markClamshellSetupFailed() {
        clamshellSetupInProgress = false
        guard clamshellPreferred else { return }
        clamshellPreferred = false
        clamshellSetupFailed = true
    }

    private func enableClamshell() {
        guard !isTerminating, isActive, clamshellPreferred, !sessionPausedForScreenLock,
              !clamshellActive, !clamshellEnablePending, !clamshellRestorePending else { return }
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        clamshellEnablePending = true
        // Persist before submitting the write: quitting or crashing before
        // its reply must not leave an unrecorded system-wide sleep override.
        system.defaults.set(true, forKey: DefaultsKey.sleepDisabledFlag)
        let system = self.system
        system.sleep.disableSleep(true) { ok in
            system.main {
                guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                self.clamshellEnablePending = false
                guard ok else {
                    // Repair the passwordless path once per deliberate attempt.
                    self.passwordlessClamshell = false
                    guard self.isActive, self.clamshellPreferred, !self.sessionPausedForScreenLock else { return }
                    if self.clamshellSetupRetried {
                        self.markClamshellSetupFailed()
                    } else {
                        self.clamshellSetupRetried = true
                        self.prepareClamshellPreference()
                    }
                    return
                }
                self.passwordlessClamshell = true
                if self.isActive, self.clamshellPreferred, !self.sessionPausedForScreenLock {
                    self.clamshellActive = true
                } else {
                    self.disableClamshell(synchronous: false)
                }
            }
        }
    }

    private func disableClamshell(synchronous: Bool) {
        // A new session waits for an outstanding restore, including its
        // authorization fallback, so an old off cannot overwrite a new on.
        guard synchronous || !clamshellRestorePending else { return }
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        lidSleepGeneration &+= 1
        lidSleepAttemptsRemaining = 0
        clamshellActive = false
        clamshellEnablePending = false
        clamshellRestorePending = true
        if synchronous {
            // This drains earlier native writes, including a pending enable.
            // Complete here: no main-queue callback survives process teardown.
            let ok = system.sleep.disableSleep(false)
            finishClamshellRestore(ok: ok, usedPasswordless: true,
                                  generation: generation, synchronous: true)
        } else {
            let system = self.system
            system.sleep.disableSleep(false) { ok in
                system.main {
                    guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                    if ok {
                        self.finishClamshellRestore(ok: true, usedPasswordless: true,
                                                   generation: generation, synchronous: false)
                    } else {
                        // Never wait for a prompt on the override's serial lane:
                        // quit drains that lane while running on the main thread.
                        system.sleep.restoreWithAuthorization(
                            prompt: L10n.shared.s.adminPromptClamshellOff,
                            shouldProceed: { !self.isTerminating && self.clamshellOperationGeneration == generation }
                        ) { restored in
                            system.main {
                                guard !self.isTerminating else { return }
                                self.finishClamshellRestore(ok: restored, usedPasswordless: false,
                                                           generation: generation, synchronous: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func finishClamshellRestore(ok: Bool, usedPasswordless: Bool,
                                        generation: Int, synchronous: Bool) {
        guard clamshellOperationGeneration == generation else { return }
        clamshellRestorePending = false
        if !usedPasswordless { passwordlessClamshell = false }
        // Keep the recovery marker on failure; never request sleep while the
        // system-wide override may still be set.
        guard ok else { return }
        system.defaults.set(false, forKey: DefaultsKey.sleepDisabledFlag)
        if !isTerminating, isActive, clamshellPreferred, !sessionPausedForScreenLock {
            enableClamshell()
        } else {
            sleepIfLidAlreadyClosed(synchronous: synchronous)
        }
    }

    /// Clearing `disablesleep` only clears a kernel flag. macOS evaluates the
    /// lid when it opens or closes, so a lid that shut during the session is
    /// never looked at again and the Mac stays awake until the battery runs
    /// out (#1729). Request the sleep that closing the lid would have caused.
    /// `pmset` returns before powerd has handed the cleared flag to the
    /// kernel, which refuses sleep until it has, so a refusal is retried.
    private func sleepIfLidAlreadyClosed(attemptsLeft: Int = 10, synchronous: Bool = false,
                                          generation: Int? = nil) {
        let generation = generation ?? lidSleepGeneration
        guard generation == lidSleepGeneration else { return }
        lidSleepAttemptsRemaining = 0
        guard !isActive || sessionPausedForScreenLock, !clamshellActive else { return }
        guard system.lidClosed() == true, lidSleepIsAllowed() else { return }
        guard let result = system.sleepSystem() else { return }
        guard result != kIOReturnSuccess, attemptsLeft > 1 else { return }
        if synchronous {
            // The existing bounded retry must finish before quit returns.
            // Re-read the lid and external protections after every refusal.
            system.wait(0.5)
            sleepIfLidAlreadyClosed(attemptsLeft: attemptsLeft - 1, synchronous: true,
                                    generation: generation)
        } else {
            lidSleepAttemptsRemaining = attemptsLeft - 1
            system.after(0.5) { [weak self] in
                guard let self, !self.isTerminating else { return }
                self.sleepIfLidAlreadyClosed(attemptsLeft: attemptsLeft - 1, generation: generation)
            }
        }
    }

    private func lidSleepIsAllowed() -> Bool {
        let allowsSleep = system.clamshellCausesSleep()
        guard allowsSleep == true else { return false }

        // The kernel does not republish its lid policy for every assertion
        // change. Read live protections as well, especially display hot-plug.
        guard let assertions = system.powerAssertions() else { return false }
        return KeepAwakeAutomationSupport.lidSleepIsAllowed(
            systemAllowsSleep: allowsSleep, assertions: assertions)
    }

    /// If the app died unexpectedly while sleep was disabled, restores normal
    /// behavior on the next launch.
    package func recoverIfNeeded(completion: (() -> Void)? = nil) {
        guard !isTerminating else { return }
        recoverDimmedDisplayIfNeeded()
        guard system.defaults.bool(forKey: DefaultsKey.sleepDisabledFlag) else {
            finishRecovery(completion)
            return
        }
        // A manual session may start while launch recovery is asking for
        // authorization. Its enable must wait until that older off is done.
        clamshellSetupID = nil
        clamshellSetupInProgress = false
        clamshellOperationGeneration &+= 1
        let generation = clamshellOperationGeneration
        clamshellRestorePending = true
        // Recovery finishes on the main thread, so the caller's completion
        // never leaves it.
        nonisolated(unsafe) let completion = completion
        let system = self.system
        let finish: @MainActor @Sendable (Bool) -> Void = { ok in
            guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
            self.clamshellRestorePending = false
            if ok { system.defaults.set(false, forKey: DefaultsKey.sleepDisabledFlag) }
            self.finishRecovery(completion)
            if ok, self.isActive, self.clamshellPreferred, !self.sessionPausedForScreenLock {
                self.enableClamshell()
            }
        }
        system.background(.utility) {
            let report = system.pmsetReport()
            let stillDisabled = SudoersSupport.sleepDisabled(inPmsetOutput: report.output)
            // An unreadable report is not evidence that a persisted override
            // has disappeared. Keep its recovery marker unless an off succeeds.
            if report.status == 0, !stillDisabled {
                system.main { finish(true) }
            } else if system.sleep.disableSleep(false) {
                system.main { finish(true) }
            } else {
                system.main {
                    guard !self.isTerminating, self.clamshellOperationGeneration == generation else { return }
                    system.sleep.restoreWithAuthorization(
                        prompt: L10n.shared.s.adminPromptRecover,
                        shouldProceed: { !self.isTerminating && self.clamshellOperationGeneration == generation }
                    ) { ok in
                        system.main { finish(ok) }
                    }
                }
            }
        }
    }

    private func finishRecovery(_ completion: (() -> Void)?) {
        guard !isTerminating else { return }
        recoveryCompleted = true
        completion?()
        syncWithPreferences()
    }

    /// A crash or force quit while the lid was closed can leave the built-in
    /// panel dimmed with nothing left running to bring it back. Closed-lid
    /// sleep already recovers its own override the same way: the intent is
    /// written down before acting, and undone on the next launch.
    private func recoverDimmedDisplayIfNeeded() {
        guard let saved = system.defaults.object(forKey: DefaultsKey.dimmedDisplaySavedBrightness) as? Double
        else { return }
        // Set before attempting, not just on failure: if the write does not
        // report success until later, `syncLidDimmingObserver` still has to
        // see this as owed right away to arm the lid observer for a retry.
        savedDisplayBrightness = saved
        applyDimmingAction(.restore(saved))
        syncLidDimmingObserver()
    }

    // MARK: - Closed-lid screen dimming

    /// Runs whenever the closed-lid mode or the dimming preference changes.
    /// An `IOPMrootDomain` general-interest notification is cheaper than
    /// polling and is already how `BrightnessService` watches the lid for
    /// its own deferred-restoration case; this registers its own interest
    /// independently since the two features dim different things for
    /// different reasons. A restore still owed keeps the observer armed past
    /// the mode ending, the same way `BrightnessService`'s own deferred
    /// display restoration outlives whatever asked for it.
    private func syncLidDimmingObserver() {
        let armed = clamshellActive && dimScreenOnLidClose
        if !armed { applyDimmingAction(LidDimmingSupport.restoring(saved: savedDisplayBrightness)) }
        guard armed || savedDisplayBrightness != nil else {
            endLidWatch?()
            endLidWatch = nil
            lidClosedForDimming = nil
            return
        }
        guard endLidWatch == nil else { return }
        guard let end = system.watchLid({ [weak self] in self?.lidStateMayHaveChangedForDimming() }) else { return }
        endLidWatch = end
        lidClosedForDimming = system.lidClosed()
        // The option can be enabled from an external display while the lid is
        // already shut. No transition follows registration in that case.
        if armed, lidClosedForDimming == true, savedDisplayBrightness == nil {
            applyDimmingAction(LidDimmingSupport.lidClosed(
                currentBrightness: system.panelBrightness()))
        }
    }

    /// General interest fires on far more than lid transitions, so the
    /// current state is compared against what was last seen rather than
    /// assumed from the notification itself. The armed check also catches a
    /// callback already queued when the feature was torn down: it lands here
    /// as a no-op instead of acting on a mode that already ended.
    private func lidStateMayHaveChangedForDimming() {
        guard (clamshellActive && dimScreenOnLidClose) || savedDisplayBrightness != nil else { return }
        let closed = system.lidClosed() ?? false
        guard closed != lidClosedForDimming else { return }
        lidClosedForDimming = closed
        if closed {
            if clamshellActive, dimScreenOnLidClose {
                applyDimmingAction(LidDimmingSupport.lidClosed(currentBrightness: system.panelBrightness()))
            }
        } else {
            applyDimmingAction(LidDimmingSupport.restoring(saved: savedDisplayBrightness))
        }
    }

    private func applyDimmingAction(_ action: LidDimmingSupport.Action) {
        switch action {
        case .dim(let save):
            savedDisplayBrightness = save
            system.defaults.set(save, forKey: DefaultsKey.dimmedDisplaySavedBrightness)
            _ = system.setPanelBrightness(0)
            Self.log.log("lid closed: dimmed the built-in display, saved \(save)")
        case .restore(let value):
            attemptDisplayRestore(value)
        case .none:
            break
        }
    }

    /// Keeps the saved level and its recovery marker until a write actually
    /// reports success — clearing them on a merely attempted write, the same
    /// way `BrightnessService`'s deferred restoration never drops a display
    /// it could not yet bring back, would leave the panel at zero forever if
    /// it is not in the online list yet (right as the lid opens) or the
    /// write itself fails. A few retries a half second apart cover that
    /// startup race; if the panel is still not back after those, whatever
    /// keeps `syncLidDimmingObserver` armed for an owed restore is what
    /// finds the next real lid-open event to try again.
    private func attemptDisplayRestore(_ value: Double, attemptsLeft: Int = 6) {
        guard system.setPanelBrightness(value) else {
            Self.log.log("restoring the built-in display to \(value) found no panel yet, \(attemptsLeft - 1) retries left")
            guard attemptsLeft > 1 else { return }
            system.after(0.5) { [weak self] in
                self?.attemptDisplayRestore(value, attemptsLeft: attemptsLeft - 1)
            }
            return
        }
        savedDisplayBrightness = nil
        system.defaults.removeObject(forKey: DefaultsKey.dimmedDisplaySavedBrightness)
        Self.log.log("restored the built-in display to \(value)")
        syncLidDimmingObserver()
    }

    // MARK: - Battery protection

    private func startBatteryWatch() {
        stopBatteryWatch()
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            // Added to the main run loop, so it fires on the main thread.
            MainActor.assumeIsolated { self?.checkBattery() }
        }
        t.tolerance = 5
        system.schedule(t)
        batteryTimer = t
        checkBattery()
    }

    private func stopBatteryWatch() {
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    private func checkBattery() {
        guard isActive, batteryProtectionPercent() != nil else { return }
        deactivate(reason: .battery)
    }

    /// The battery level while battery protection would end any session at
    /// once (on battery, at or below the limit); nil when a session can run.
    package func batteryProtectionPercent() -> Int? {
        let limit = Defaults.sanitizedBatteryLimit(system.defaults.integer(forKey: DefaultsKey.batteryLimit))
        guard limit > 0,
              let battery = system.battery(),
              battery.isOnBattery,
              battery.percent <= limit else { return nil }
        return battery.percent
    }

    // MARK: - Optional pointer activity

    private func syncMouseJiggleTimer() {
        guard isActive,
              !sessionPausedForScreenLock,
              system.defaults.bool(forKey: DefaultsKey.keepAwakeMouseJiggleEnabled)
        else {
            stopMouseJiggleTimer()
            return
        }

        let minutes = Defaults.sanitizedKeepAwakeMouseJiggleInterval(
            system.defaults.integer(forKey: DefaultsKey.keepAwakeMouseJiggleInterval)
        )
        let interval = TimeInterval(minutes * 60)
        if mouseJiggleTimer?.timeInterval == interval { return }

        stopMouseJiggleTimer()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Added to the main run loop, so it fires on the main thread.
            MainActor.assumeIsolated { self?.jiggleMousePointer() }
        }
        timer.tolerance = min(10, interval * 0.1)
        system.schedule(timer)
        mouseJiggleTimer = timer
    }

    private func stopMouseJiggleTimer() {
        mouseJiggleTimer?.invalidate()
        mouseJiggleTimer = nil
        pendingMouseReturn?.cancel()
        pendingMouseReturn = nil
    }

    private func jiggleMousePointer() {
        guard isActive,
              system.defaults.bool(forKey: DefaultsKey.keepAwakeMouseJiggleEnabled),
              let original = Self.currentMouseLocation(),
              let target = Self.mouseJiggleTarget(from: original)
        else {
            syncMouseJiggleTimer()
            return
        }

        guard Self.postMouseMove(to: target) else { return }

        pendingMouseReturn?.cancel()
        let returnMove = DispatchWorkItem { [weak self] in
            self?.pendingMouseReturn = nil
            guard let current = Self.currentMouseLocation() else { return }
            guard abs(current.x - target.x) <= 2,
                  abs(current.y - target.y) <= 2 else { return }
            _ = Self.postMouseMove(to: original)
        }
        pendingMouseReturn = returnMove
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: returnMove)
    }

    private static func currentMouseLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private static func mouseJiggleTarget(from original: CGPoint) -> CGPoint? {
        guard let bounds = displayBounds(containing: original) else { return nil }
        let safeFrame = bounds.insetBy(dx: 2, dy: 2)
        let x = min(max(original.x, safeFrame.minX), safeFrame.maxX)
        let y = min(max(original.y, safeFrame.minY), safeFrame.maxY)

        if x + 1 <= safeFrame.maxX {
            return CGPoint(x: x + 1, y: y)
        }
        if x - 1 >= safeFrame.minX {
            return CGPoint(x: x - 1, y: y)
        }
        if y + 1 <= safeFrame.maxY {
            return CGPoint(x: x, y: y + 1)
        }
        if y - 1 >= safeFrame.minY {
            return CGPoint(x: x, y: y - 1)
        }
        return nil
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return nil
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return nil
        }

        for display in displays.prefix(Int(count)) {
            let bounds = CGDisplayBounds(display)
            if point.x >= bounds.minX, point.x <= bounds.maxX,
               point.y >= bounds.minY, point.y <= bounds.maxY {
                return bounds
            }
        }
        return nil
    }

    private static func postMouseMove(to point: CGPoint) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(mouseEventSource: source,
                                  mouseType: .mouseMoved,
                                  mouseCursorPosition: point,
                                  mouseButton: .left) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}

extension KeepAwakeManager.System {
    /// The system's own: the shared settings, `pmset`, IOKit's power
    /// management and the built-in panel.
    package static var live: KeepAwakeManager.System {
        KeepAwakeManager.System(
            defaults: .standard,
            notificationCenter: .default,
            sleep: .live,
            pmsetReport: { Shell.run("/usr/bin/pmset", ["-g"]) },
            background: { qos, work in DispatchQueue.global(qos: qos).async(execute: work) },
            main: { work in DispatchQueue.main.async { work() } },
            after: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
            },
            wait: { Thread.sleep(forTimeInterval: $0) },
            schedule: { RunLoop.main.add($0, forMode: .common) },
            assert: { type, name in
                var id = IOPMAssertionID(0)
                let ok = IOPMAssertionCreateWithName(type as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     name as CFString,
                                                     &id)
                return ok == kIOReturnSuccess ? id : nil
            },
            releaseAssertion: { _ = IOPMAssertionRelease($0) },
            battery: { SystemInfo.batterySnapshot() },
            watchLock: { changed in
                let center = DistributedNotificationCenter.default()
                let observers = [
                    center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                       object: nil, queue: .main) { _ in
                        // Delivered on the main queue.
                        MainActor.assumeIsolated { changed(true) }
                    },
                    center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                       object: nil, queue: .main) { _ in
                        // Delivered on the main queue.
                        MainActor.assumeIsolated { changed(false) }
                    },
                ]
                return { observers.forEach { center.removeObserver($0) } }
            },
            session: { CGSessionCopyCurrentDictionary() as? [String: Any] },
            lidClosed: { BrightnessService.lidClosed() },
            clamshellCausesSleep: {
                let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                          IOServiceMatching("IOPMrootDomain"))
                guard service != 0 else { return nil }
                defer { IOObjectRelease(service) }
                return IORegistryEntryCreateCFProperty(
                    service, kAppleClamshellCausesSleepKey as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
            },
            powerAssertions: {
                var snapshot: Unmanaged<CFDictionary>?
                let result = IOPMCopyAssertionsByProcess(&snapshot)
                let values = snapshot?.takeRetainedValue()
                guard result == kIOReturnSuccess,
                      let assertions = values as? [AnyHashable: [[String: Any]]]
                else { return nil }
                return assertions.values.flatMap { $0 }
            },
            sleepSystem: {
                let rootDomain = IOPMFindPowerManagement(kIOMainPortDefault)
                guard rootDomain != 0 else { return nil }
                let result = IOPMSleepSystem(rootDomain)
                IOServiceClose(rootDomain)
                return result
            },
            watchLid: { changed in watchPowerManagement(changed) },
            panelBrightness: { LidDisplayDimmer.currentBrightness() },
            setPanelBrightness: { LidDisplayDimmer.setBrightness($0) })
    }

    /// `IOPMrootDomain`'s general interest, which the lid's transitions are
    /// part of. The watch holds the handler that the IOKit context points at,
    /// so a notification already queued when it stops finds nothing.
    @MainActor
    private static func watchPowerManagement(_ changed: @escaping @MainActor @Sendable () -> Void) -> (() -> Void)? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return nil }
        let handler = PowerManagementInterest(changed)
        var notification: io_object_t = 0
        let result = IOServiceAddInterestNotification(
            port, root, kIOGeneralInterest, { context, _, _, _ in
                guard let context else { return }
                let handler = Unmanaged<PowerManagementInterest>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak handler] in handler?.changed() }
            }, Unmanaged.passUnretained(handler).toOpaque(), &notification)
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            return nil
        }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let watched = notification
        return {
            withExtendedLifetime(handler) {
                if watched != 0 { IOObjectRelease(watched) }
                IONotificationPortDestroy(port)
            }
        }
    }
}

/// What a power-management notification runs; see `watchPowerManagement`.
@MainActor
private final class PowerManagementInterest {
    let changed: @MainActor @Sendable () -> Void
    init(_ changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }
}
