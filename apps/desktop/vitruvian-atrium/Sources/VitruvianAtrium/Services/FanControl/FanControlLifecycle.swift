// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore

/// When fan control starts and stops on its own: bringing back the user's
/// manual speed or curve after a launch or wake while resume is on, keeping
/// or forgetting it as the preferences change, and winding down idle work.
/// `FanControlService` owns it and passes in what it reads and does; tests
/// pass doubles, so nothing here can reach the helper or the fans. A resume
/// the hardware refuses is retried on `FanControlResumePolicy.retryDelays`,
/// and the lifecycle keeps count of the attempts.
@MainActor
package final class FanControlLifecycle {
    /// What the service reads and does on the lifecycle's behalf.
    package struct Host {
        /// Whether the helper is registered and allowed to run, read afresh.
        package var helperEnabled: () -> Bool
        package var snapshot: () -> FanControlSnapshot
        package var panelIsVisible: () -> Bool
        /// Applies a configuration; `resuming` marks a resume, whose failure
        /// comes back through `resumeDidFail`.
        package var apply: (_ configuration: FanControlConfiguration, _ resuming: Bool) -> Void
        /// Returns the fans to the system; `superseding` overrides a request
        /// already in flight.
        package var restore: (_ superseding: Bool) -> Void
        package var restoreThenUnregister: () -> Void
        package var refresh: () -> Void
        /// Stops the timer and drops the helper connection.
        package var stopTimer: () -> Void
        package var stopObservingSystemState: () -> Void
        package var startObservingSystemState: () -> Void
        /// A request to the helper is still waiting for its reply.
        package var isWorking: () -> Bool
        /// The system is under enough thermal pressure that the helper hands
        /// the fans back on its own, so a resume waits.
        package var defersResume: () -> Bool
        /// Calls `retryResume` once `delay` seconds have passed, replacing any
        /// attempt already scheduled.
        package var scheduleResumeAttempt: (_ delay: TimeInterval) -> Void
        package var cancelResumeAttempt: () -> Void
        /// Every retry is spent, or a stop left the fans with the system:
        /// the card says so instead of showing the kept control as running.
        package var resumeFailedChanged: (Bool) -> Void

        package init(helperEnabled: @escaping () -> Bool,
                     snapshot: @escaping () -> FanControlSnapshot,
                     panelIsVisible: @escaping () -> Bool,
                     apply: @escaping (FanControlConfiguration, Bool) -> Void,
                     restore: @escaping (_ superseding: Bool) -> Void,
                     restoreThenUnregister: @escaping () -> Void,
                     refresh: @escaping () -> Void,
                     stopTimer: @escaping () -> Void,
                     stopObservingSystemState: @escaping () -> Void,
                     startObservingSystemState: @escaping () -> Void = {},
                     isWorking: @escaping () -> Bool = { false },
                     defersResume: @escaping () -> Bool = { false },
                     scheduleResumeAttempt: @escaping (TimeInterval) -> Void = { _ in },
                     cancelResumeAttempt: @escaping () -> Void = {},
                     resumeFailedChanged: @escaping (Bool) -> Void = { _ in }) {
            self.helperEnabled = helperEnabled
            self.snapshot = snapshot
            self.panelIsVisible = panelIsVisible
            self.apply = apply
            self.restore = restore
            self.restoreThenUnregister = restoreThenUnregister
            self.refresh = refresh
            self.stopTimer = stopTimer
            self.stopObservingSystemState = stopObservingSystemState
            self.startObservingSystemState = startObservingSystemState
            self.isWorking = isWorking
            self.defersResume = defersResume
            self.scheduleResumeAttempt = scheduleResumeAttempt
            self.cancelResumeAttempt = cancelResumeAttempt
            self.resumeFailedChanged = resumeFailedChanged
        }
    }

    private let defaults: UserDefaults
    /// The helper this build bundles.
    private let helperVersion: String
    private let host: Host
    /// Resume attempts refused in a row since the last launch, wake or success.
    package private(set) var resumeFailures = 0
    package private(set) var resumeFailed = false {
        didSet { if resumeFailed != oldValue { host.resumeFailedChanged(resumeFailed) } }
    }

    package init(defaults: UserDefaults = .standard, helperVersion: String, host: Host) {
        self.defaults = defaults
        self.helperVersion = helperVersion
        self.host = host
    }

    package func recoverIfNeeded() {
        // Re-applying supersedes the recovery: a start that fails restores too.
        if let configuration = resumableConfiguration, beginResume(configuration) { return }
        guard defaults[Preferences.fanControlRecoveryNeeded] else { return }
        host.restore(false)
    }

    package func syncWithPreferences() {
        if AppFeature.fanControl.isAvailable(in: defaults) {
            if defaults[Preferences.fanControlRecoveryNeeded] {
                host.restore(false)
            }
        } else {
            defaults.removeValue(for: Preferences.fanControlResumeConfiguration)
            cancelResumeRetry()
            host.restoreThenUnregister()
        }
    }

    /// Picking System forgets the kept control and any retry of it, even when
    /// the fans are already back with the system.
    package func forgetResume() {
        defaults.removeValue(for: Preferences.fanControlResumeConfiguration)
        cancelResumeRetry()
    }

    /// The user's own return to System, the one stop a resume must honor.
    package func returnToSystem() {
        forgetResume()
        host.restore(false)
    }

    /// Turning resume on keeps the control already running; turning it off
    /// forgets it, so no later restart brings back an old choice.
    package func resumePreferenceDidChange() {
        guard defaults[Preferences.fanControlResume] else {
            defaults.removeValue(for: Preferences.fanControlResumeConfiguration)
            cancelResumeRetry()
            return
        }
        // Only the control running now is kept, never an older one left
        // behind, for example by a restored backup.
        let snapshot = host.snapshot()
        if snapshot.isCooling, let configuration = snapshot.configuration {
            rememberForResume(configuration)
        } else {
            defaults.removeValue(for: Preferences.fanControlResumeConfiguration)
        }
    }

    /// The manual speed or curve to bring back when the app opens or the Mac
    /// wakes, while resume is on and the user has not returned to System.
    private var resumableConfiguration: FanControlConfiguration? {
        // Picking System in the card is a return to System too, even when a
        // safety stop had already handed the fans back and left no button.
        guard AppFeature.fanControl.isAvailable(in: defaults),
              defaults[Preferences.fanControlResume],
              defaults[Preferences.fanControlMode]
                != FanControlMode.system.rawValue else { return nil }
        return FanControlConfiguration.decodeResume(
            defaults[Preferences.fanControlResumeConfiguration])
    }

    /// A resume never asks for approval or opens System Settings: without an
    /// enabled helper the fans stay with the system until the user acts.
    private func resume(_ configuration: FanControlConfiguration) -> Bool {
        guard host.helperEnabled(), !helperAwaitsRegistration else { return false }
        host.apply(configuration, true)
        return true
    }

    /// A launch or wake starts over with the full retry budget.
    private func beginResume(_ configuration: FanControlConfiguration) -> Bool {
        cancelResumeRetry()
        guard !host.isWorking(), !host.defersResume() else {
            host.startObservingSystemState()
            host.scheduleResumeAttempt(FanControlResumePolicy.retryDelays[0])
            return true
        }
        return resume(configuration)
    }

    /// The user's own choice, a return to System or a fresh launch or wake
    /// replaces any resume still waiting to retry.
    package func cancelResumeRetry() {
        host.cancelResumeAttempt()
        resumeFailures = 0
        resumeFailed = false
    }

    /// A kept control is running again.
    package func resumeSucceeded() {
        resumeFailures = 0
        resumeFailed = false
    }

    /// One refused resume used to leave the fans on System for good while the
    /// card still showed the curve, so a hot Mac kept its fans at idle speed.
    package func resumeDidFail(_ failure: FanControlErrorCode, stopReason: FanControlStopReason? = nil) {
        guard resumableConfiguration != nil else { return }
        guard failure == .controlFailed || failure == .helperUnavailable,
              stopReason != .hardwareChanged, stopReason != .temperatureUnavailable,
              stopReason != .thermalPressure else {
            resumeFailed = true
            return
        }
        scheduleResumeRetry()
    }

    private func scheduleResumeRetry() {
        guard let delay = FanControlResumePolicy.retryDelay(afterFailures: resumeFailures) else {
            resumeFailed = true
            return
        }
        resumeFailures += 1
        host.scheduleResumeAttempt(delay)
    }

    /// The scheduled attempt. A request in flight or thermal pressure only
    /// postpones it, without spending the retry budget.
    package func retryResume() {
        guard let configuration = resumableConfiguration else { return }
        guard !host.isWorking(), !host.defersResume() else {
            host.scheduleResumeAttempt(FanControlResumePolicy.retryDelays[0])
            return
        }
        guard !host.snapshot().isCooling else { return }
        if !resume(configuration) { resumeFailed = true }
    }

    /// A status reply found the session stopped. Panel refreshes and heartbeats
    /// can each be the first to see it; only a lost heartbeat is resumed.
    package func sessionStopped(wasCooling: Bool, reason: FanControlStopReason?) {
        guard wasCooling, resumableConfiguration != nil else { return }
        if reason == .heartbeatLost {
            scheduleResumeRetry()
        } else {
            // A protection stop or an unknown reason leaves control with macOS.
            host.cancelResumeAttempt()
            resumeFailed = true
        }
    }

    /// A retry must not re-apply control on the way into sleep; the wake
    /// starts a fresh resume.
    package func workspaceWillSleep() {
        host.cancelResumeAttempt()
    }

    /// An update brought a helper other than the registered one. Kept control
    /// would hold the recovery flag that blocks its registration swap, so a
    /// resume waits for Fan Control to open and register it first.
    private var helperAwaitsRegistration: Bool {
        let installed = defaults[Preferences.fanControlHelperVersion]
        return !installed.isEmpty && installed != helperVersion
    }

    package func rememberForResume(_ configuration: FanControlConfiguration) {
        guard defaults[Preferences.fanControlResume],
              let stored = FanControlConfiguration.encodeResume(configuration) else { return }
        defaults[Preferences.fanControlResumeConfiguration] = stored
    }

    package func stopIdleWorkIfPossible() {
        guard !host.panelIsVisible(), !host.snapshot().isCooling,
              !defaults[Preferences.fanControlRecoveryNeeded] else { return }
        host.stopTimer()
        // A resume waits for the next wake, which only these observers see.
        guard resumableConfiguration == nil else { return }
        host.stopObservingSystemState()
    }

    package func workspaceDidWake() {
        if let configuration = resumableConfiguration, beginResume(configuration) { return }
        if defaults[Preferences.fanControlRecoveryNeeded] {
            host.restore(true)
        } else if host.panelIsVisible() {
            host.refresh()
        }
    }
}
