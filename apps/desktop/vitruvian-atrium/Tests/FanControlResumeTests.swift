// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// Resuming fan control after a restart or wake runs the production lifecycle
/// against a recording host and a defaults domain of its own: nothing here
/// can reach the helper or the fans.
enum FanControlResumeContract {
    /// What the lifecycle reads from the service and asks it to do.
    final class Service {
        var helperEnabled = true
        var snapshot = FanControlSnapshot.empty
        var panelIsVisible = false
        var timerStopped = false
        var observing = true
        var applied: [FanControlConfiguration] = []
        var events: [String] = []
        var isWorking = false
        var thermallyDeferred = false
        /// The delay of every resume attempt scheduled and not cancelled.
        var scheduledResumes: [TimeInterval] = []
        var resumeFailed = false
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.fan-control-resume"
        let defaults = ScratchDefaults.suite(named: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let service = Service()
        let lifecycle = FanControlLifecycle(defaults: defaults, helperVersion: "bundled", host: .init(
            helperEnabled: { service.helperEnabled },
            snapshot: { service.snapshot },
            panelIsVisible: { service.panelIsVisible },
            apply: { configuration, _ in service.applied.append(configuration) },
            restore: { service.events.append($0 ? "restore superseding" : "restore") },
            restoreThenUnregister: { service.events.append("unregister") },
            refresh: { service.events.append("refresh") },
            stopTimer: { service.timerStopped = true },
            stopObservingSystemState: { service.observing = false },
            startObservingSystemState: { service.observing = true },
            isWorking: { service.isWorking },
            defersResume: { service.thermallyDeferred },
            scheduleResumeAttempt: { service.scheduledResumes.append($0) },
            cancelResumeAttempt: { service.scheduledResumes.removeAll() },
            resumeFailedChanged: { service.resumeFailed = $0 }))
        let manual = FanControlConfiguration.manual(level: 100)
        func reset(resume: Bool = true, stored: FanControlConfiguration? = manual,
                   recovery: Bool = false) {
            defaults.removePersistentDomain(forName: domain)
            defaults.set(true, forKey: AppFeature.fanControl.availabilityKey)
            defaults.set(resume, forKey: DefaultsKey.fanControlResume)
            defaults.set(recovery, forKey: DefaultsKey.fanControlRecoveryNeeded)
            defaults.set(FanControlMode.manual.rawValue, forKey: DefaultsKey.fanControlMode)
            if let stored {
                defaults.set(FanControlConfiguration.encodeResume(stored),
                             forKey: DefaultsKey.fanControlResumeConfiguration)
            }
            service.helperEnabled = true
            service.snapshot = .empty
            service.panelIsVisible = false
            service.timerStopped = false
            service.observing = true
            service.applied = []
            service.events = []
            service.isWorking = false
            service.thermallyDeferred = false
            lifecycle.cancelResumeRetry()
            service.scheduledResumes = []
        }
        var storedResume: String? { defaults.string(forKey: DefaultsKey.fanControlResumeConfiguration) }

        reset(resume: false, recovery: true)
        lifecycle.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events == ["restore"],
                     "without resume, a launch after an interrupted session only returns the fans to the system")
        reset(recovery: true)
        lifecycle.recoverIfNeeded()
        suite.expect(service.applied == [manual] && service.events.isEmpty,
                     "with resume on, a launch re-applies the kept control instead of restoring first")
        reset()
        service.helperEnabled = false
        lifecycle.recoverIfNeeded()
        suite.expect(service.applied.isEmpty && service.events.isEmpty,
                     "a resume never asks for helper approval on its own")
        reset()
        defaults.set(false, forKey: AppFeature.fanControl.availabilityKey)
        lifecycle.recoverIfNeeded()
        suite.expect(service.applied.isEmpty, "a feature removed from the hub resumes nothing")
        reset()
        defaults.set(#"{"curves":[],"manualLevel":100,"mode":"system"}"#,
                     forKey: DefaultsKey.fanControlResumeConfiguration)
        lifecycle.recoverIfNeeded()
        suite.expect(service.applied.isEmpty, "a damaged or System value is never re-applied")
        reset()
        defaults.set(FanControlMode.system.rawValue, forKey: DefaultsKey.fanControlMode)
        lifecycle.recoverIfNeeded()
        lifecycle.workspaceDidWake()
        lifecycle.stopIdleWorkIfPossible()
        suite.expect(service.applied.isEmpty && !service.observing,
                     "picking System in the card, with the fans already back there, is never undone by a resume")
        reset()
        defaults.set("registered before the update", forKey: DefaultsKey.fanControlHelperVersion)
        lifecycle.recoverIfNeeded()
        lifecycle.workspaceDidWake()
        suite.expect(service.applied.isEmpty,
                     "a helper replaced by an update is registered anew before any resume holds the fans")
        reset()
        defaults.set("bundled", forKey: DefaultsKey.fanControlHelperVersion)
        lifecycle.recoverIfNeeded()
        suite.expect(service.applied == [manual], "the registered helper resumes as before")

        reset(resume: false, stored: nil)
        lifecycle.rememberForResume(manual)
        suite.expect(storedResume == nil, "applied control is not kept while resume is off")
        reset(stored: nil)
        lifecycle.rememberForResume(.manual(level: 60))
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == .manual(level: 60),
                     "applied control is kept while resume is on")

        reset(stored: nil)
        service.snapshot.isCooling = true
        service.snapshot.configuration = manual
        lifecycle.resumePreferenceDidChange()
        suite.expect(FanControlConfiguration.decodeResume(storedResume ?? "") == manual,
                     "turning resume on keeps the control already running")
        defaults.set(false, forKey: DefaultsKey.fanControlResume)
        lifecycle.resumePreferenceDidChange()
        suite.expect(storedResume == nil, "turning resume off forgets the kept control")
        reset(stored: nil)
        lifecycle.resumePreferenceDidChange()
        suite.expect(storedResume == nil, "turning resume on with the fans on System keeps nothing")
        reset(stored: nil)
        service.snapshot.configuration = manual
        lifecycle.resumePreferenceDidChange()
        suite.expect(storedResume == nil,
                     "turning resume on keeps nothing once a control has stopped cooling")
        reset()
        lifecycle.resumePreferenceDidChange()
        suite.expect(storedResume == nil,
                     "turning resume on with the fans on System drops an older kept control, such as a restored one")

        reset()
        lifecycle.returnToSystem()
        suite.expect(storedResume == nil && service.events == ["restore"],
                     "returning to System forgets the kept control and restores the fans")

        reset()
        lifecycle.stopIdleWorkIfPossible()
        suite.expect(service.timerStopped && service.observing,
                     "idle work stops while a pending resume keeps watching for the next wake")
        reset(resume: false)
        lifecycle.stopIdleWorkIfPossible()
        suite.expect(!service.observing, "without a pending resume the sleep observers stop too")
        reset(resume: false)
        service.panelIsVisible = true
        lifecycle.stopIdleWorkIfPossible()
        suite.expect(!service.timerStopped && service.observing, "an open panel keeps its updates running")

        reset()
        lifecycle.workspaceDidWake()
        suite.expect(service.applied == [manual] && service.events.isEmpty,
                     "waking re-applies the kept control")
        reset(resume: false, recovery: true)
        lifecycle.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events == ["restore superseding"],
                     "without resume, waking still returns an interrupted session to the system")
        reset(resume: false)
        service.panelIsVisible = true
        lifecycle.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events == ["refresh"],
                     "without resume, waking only refreshes a visible panel")
        reset(resume: false)
        lifecycle.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.events.isEmpty,
                     "without resume, waking with the panel closed does nothing")

        // A resume can fail for a moment right after a wake, before the fans and
        // sensors answer again. One refusal must not leave the fans on System
        // while the card still shows the curve as chosen.
        reset()
        lifecycle.workspaceDidWake()
        lifecycle.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "a resume refused right after a wake is tried again shortly")
        lifecycle.retryResume()
        suite.expect(service.applied == [manual, manual],
                     "the retry re-applies the kept control")
        reset()
        for _ in FanControlResumePolicy.retryDelays { lifecycle.resumeDidFail(.controlFailed) }
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && !service.resumeFailed,
                     "failed resumes back off through every planned retry")
        lifecycle.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes == FanControlResumePolicy.retryDelays && service.resumeFailed,
                     "resuming gives up after the last retry and says so instead of looking active")
        lifecycle.workspaceDidWake()
        suite.expect(lifecycle.resumeFailures == 0 && !service.resumeFailed && service.applied == [manual],
                     "a later wake starts a fresh resume with the full retry budget")
        reset(resume: false, stored: nil)
        lifecycle.resumeDidFail(.controlFailed)
        suite.expect(service.scheduledResumes.isEmpty && !service.resumeFailed,
                     "without resume a failed apply is never retried")
        reset()
        lifecycle.resumeDidFail(.controlFailed)
        lifecycle.returnToSystem()
        lifecycle.retryResume()
        suite.expect(service.scheduledResumes.isEmpty && service.applied.isEmpty,
                     "returning to System cancels a pending resume retry")
        reset()
        lifecycle.resumeDidFail(.controlFailed)
        defaults.set(false, forKey: DefaultsKey.fanControlResume)
        lifecycle.resumePreferenceDidChange()
        suite.expect(service.scheduledResumes.isEmpty, "turning resume off cancels a pending retry")
        reset()
        lifecycle.resumeDidFail(.controlFailed)
        lifecycle.workspaceWillSleep()
        suite.expect(service.scheduledResumes.isEmpty, "sleep cancels a pending retry; the wake resumes anew")
        reset()
        service.snapshot.isCooling = true
        lifecycle.retryResume()
        suite.expect(service.applied.isEmpty, "a retry does nothing once the control is running again")
        reset()
        service.thermallyDeferred = true
        lifecycle.retryResume()
        suite.expect(service.applied.isEmpty
                        && service.scheduledResumes == [FanControlResumePolicy.retryDelays[0]],
                     "under thermal pressure a retry waits instead of fighting the system")
        reset()
        service.isWorking = true
        lifecycle.retryResume()
        suite.expect(service.applied.isEmpty && service.scheduledResumes.count == 1,
                     "a retry waits for a request already in flight")
        service.snapshot.isCooling = true
        lifecycle.retryResume()
        suite.expect(service.scheduledResumes.count == 2 && lifecycle.resumeFailures == 0,
                     "a stale active snapshot during restoration does not lose the retry")
        service.isWorking = false
        service.snapshot = .empty
        service.thermallyDeferred = true
        for _ in 0..<20 { lifecycle.retryResume() }
        service.thermallyDeferred = false
        lifecycle.retryResume()
        suite.expect(service.applied == [manual] && lifecycle.resumeFailures == 0,
                     "waiting for restoration and thermal pressure preserves the full retry budget")
        reset()
        service.thermallyDeferred = true
        lifecycle.workspaceDidWake()
        suite.expect(service.applied.isEmpty && service.scheduledResumes.count == 1,
                     "a wake under thermal pressure defers even its initial application")
        reset()
        lifecycle.resumeDidFail(.controlFailed)
        lifecycle.forgetResume()
        defaults.set(FanControlMode.manual.rawValue, forKey: DefaultsKey.fanControlMode)
        lifecycle.retryResume()
        suite.expect(storedResume == nil && service.applied.isEmpty,
                     "selecting System then Manual cannot bring back an unapplied curve")

        for reason: FanControlStopReason? in [.hardwareChanged, .temperatureUnavailable, .thermalPressure,
                                               .recovery, .appDisconnected, .timeLimit, nil, .heartbeatLost] {
            reset()
            lifecycle.sessionStopped(wasCooling: true, reason: reason)
            // The second poll finds the session already stopped.
            lifecycle.sessionStopped(wasCooling: false, reason: reason)
            suite.expect(service.scheduledResumes.count == (reason == .heartbeatLost ? 1 : 0)
                            && service.resumeFailed == (reason != .heartbeatLost),
                         "polling a stopped session twice honors its reason and schedules at most once")
        }
        reset()
        lifecycle.resumeDidFail(.controlFailed, stopReason: .hardwareChanged)
        suite.expect(service.resumeFailed && service.scheduledResumes.isEmpty,
                     "a refused application that lost hardware ownership leaves control with the system")
        reset(resume: false, stored: nil)
        lifecycle.sessionStopped(wasCooling: true, reason: .heartbeatLost)
        suite.expect(service.scheduledResumes.isEmpty, "a heartbeat loss only resumes opted-in control")
        suite.expect(FanControlResumePolicy.defersResume(thermalState: .serious)
                        && FanControlResumePolicy.defersResume(thermalState: .critical)
                        && !FanControlResumePolicy.defersResume(thermalState: .fair)
                        && FanControlResumePolicy.retryDelay(afterFailures: FanControlResumePolicy.retryDelays.count) == nil,
                     "serious thermal pressure defers a resume, and the retries run out")

        reset()
        defaults.set(false, forKey: AppFeature.fanControl.availabilityKey)
        lifecycle.syncWithPreferences()
        suite.expect(storedResume == nil && service.events == ["unregister"],
                     "removing the feature forgets the kept control before unregistering the helper")
        reset()
    }
}
