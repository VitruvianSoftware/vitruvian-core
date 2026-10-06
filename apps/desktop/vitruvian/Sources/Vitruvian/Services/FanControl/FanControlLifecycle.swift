// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore

/// When fan control starts and stops on its own: bringing back the user's
/// manual speed or curve after a launch or wake while resume is on, keeping
/// or forgetting it as the preferences change, and winding down idle work.
/// `FanControlService` owns it and passes in what it reads and does; tests
/// pass doubles, so nothing here can reach the helper or the fans.
@MainActor
package struct FanControlLifecycle {
    /// What the service reads and does on the lifecycle's behalf.
    package struct Host {
        /// Whether the helper is registered and allowed to run, read afresh.
        package var helperEnabled: () -> Bool
        package var snapshot: () -> FanControlSnapshot
        package var panelIsVisible: () -> Bool
        package var apply: (FanControlConfiguration) -> Void
        /// Returns the fans to the system; `superseding` overrides a request
        /// already in flight.
        package var restore: (_ superseding: Bool) -> Void
        package var restoreThenUnregister: () -> Void
        package var refresh: () -> Void
        /// Stops the timer and drops the helper connection.
        package var stopTimer: () -> Void
        package var stopObservingSystemState: () -> Void

        package init(helperEnabled: @escaping () -> Bool,
                     snapshot: @escaping () -> FanControlSnapshot,
                     panelIsVisible: @escaping () -> Bool,
                     apply: @escaping (FanControlConfiguration) -> Void,
                     restore: @escaping (_ superseding: Bool) -> Void,
                     restoreThenUnregister: @escaping () -> Void,
                     refresh: @escaping () -> Void,
                     stopTimer: @escaping () -> Void,
                     stopObservingSystemState: @escaping () -> Void) {
            self.helperEnabled = helperEnabled
            self.snapshot = snapshot
            self.panelIsVisible = panelIsVisible
            self.apply = apply
            self.restore = restore
            self.restoreThenUnregister = restoreThenUnregister
            self.refresh = refresh
            self.stopTimer = stopTimer
            self.stopObservingSystemState = stopObservingSystemState
        }
    }

    private let defaults: UserDefaults
    /// The helper this build bundles.
    private let helperVersion: String
    private let host: Host

    package init(defaults: UserDefaults = .standard, helperVersion: String, host: Host) {
        self.defaults = defaults
        self.helperVersion = helperVersion
        self.host = host
    }

    package func recoverIfNeeded() {
        // Re-applying supersedes the recovery: a start that fails restores too.
        if let configuration = resumableConfiguration, resume(configuration) { return }
        guard defaults[Preferences.fanControlRecoveryNeeded] else { return }
        host.restore(false)
    }

    package func syncWithPreferences() {
        if AppFeature.fanControl.isAvailable(in: defaults) {
            if defaults[Preferences.fanControlRecoveryNeeded] {
                host.restore(false)
            }
        } else {
            defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            host.restoreThenUnregister()
        }
    }

    /// The user's own return to System, the one stop a resume must honor.
    package func returnToSystem() {
        defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        host.restore(false)
    }

    /// Turning resume on keeps the control already running; turning it off
    /// forgets it, so no later restart brings back an old choice.
    package func resumePreferenceDidChange() {
        guard defaults[Preferences.fanControlResume] else {
            defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
            return
        }
        // Only the control running now is kept, never an older one left
        // behind, for example by a restored backup.
        let snapshot = host.snapshot()
        if snapshot.isCooling, let configuration = snapshot.configuration {
            rememberForResume(configuration)
        } else {
            defaults.removeObject(forKey: DefaultsKey.fanControlResumeConfiguration)
        }
    }

    /// The manual speed or curve to bring back when the app opens or the Mac
    /// wakes, while resume is on and the user has not returned to System.
    private var resumableConfiguration: FanControlConfiguration? {
        // Picking System in the card is a return to System too, even when a
        // safety stop had already handed the fans back and left no button.
        guard AppFeature.fanControl.isAvailable(in: defaults),
              defaults[Preferences.fanControlResume],
              defaults.string(forKey: DefaultsKey.fanControlMode)
                != FanControlMode.system.rawValue else { return nil }
        return FanControlConfiguration.decodeResume(
            defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) ?? "")
    }

    /// A resume never asks for approval or opens System Settings: without an
    /// enabled helper the fans stay with the system until the user acts.
    private func resume(_ configuration: FanControlConfiguration) -> Bool {
        guard host.helperEnabled(), !helperAwaitsRegistration else { return false }
        host.apply(configuration)
        return true
    }

    /// An update brought a helper other than the registered one. Kept control
    /// would hold the recovery flag that blocks its registration swap, so a
    /// resume waits for Fan Control to open and register it first.
    private var helperAwaitsRegistration: Bool {
        let installed = defaults.string(forKey: DefaultsKey.fanControlHelperVersion) ?? ""
        return !installed.isEmpty && installed != helperVersion
    }

    package func rememberForResume(_ configuration: FanControlConfiguration) {
        guard defaults[Preferences.fanControlResume],
              let stored = FanControlConfiguration.encodeResume(configuration) else { return }
        defaults.set(stored, forKey: DefaultsKey.fanControlResumeConfiguration)
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
        if let configuration = resumableConfiguration, resume(configuration) { return }
        if defaults[Preferences.fanControlRecoveryNeeded] {
            host.restore(true)
        } else if host.panelIsVisible() {
            host.refresh()
        }
    }
}
