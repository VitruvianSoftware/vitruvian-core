// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

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
    }

    static func run(_ suite: TestSuite) {
        let domain = "vitruvian.tests.fan-control-resume"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        let service = Service()
        let lifecycle = FanControlLifecycle(defaults: defaults, helperVersion: "bundled", host: .init(
            helperEnabled: { service.helperEnabled },
            snapshot: { service.snapshot },
            panelIsVisible: { service.panelIsVisible },
            apply: { service.applied.append($0) },
            restore: { service.events.append($0 ? "restore superseding" : "restore") },
            restoreThenUnregister: { service.events.append("unregister") },
            refresh: { service.events.append("refresh") },
            stopTimer: { service.timerStopped = true },
            stopObservingSystemState: { service.observing = false }))
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

        reset()
        defaults.set(false, forKey: AppFeature.fanControl.availabilityKey)
        lifecycle.syncWithPreferences()
        suite.expect(storedResume == nil && service.events == ["unregister"],
                     "removing the feature forgets the kept control before unregistering the helper")
        reset()
    }
}
