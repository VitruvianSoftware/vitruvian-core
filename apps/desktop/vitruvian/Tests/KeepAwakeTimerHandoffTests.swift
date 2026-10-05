// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production handoff a timed session makes when it runs out. It is the
/// one place that decides whether a session the user started by hand carries
/// on as an automatic one, and it has to ask the same question the automation
/// asks itself: under All, one matching condition is not a session (issue #1587).
enum KeepAwakeTimerHandoffTests {
    private struct Dock {
        var trigger: KeepAwakeManager.SessionTrigger? = .manual
        var suppressed = false
        var batteryAllows = true
        var enabled: Set<KeepAwakeAutomationCondition> = [.externalDisplay, .power]
        var matching: Set<KeepAwakeAutomationCondition> = [.externalDisplay]
        var requireAll: Bool

        func handoff(in defaults: UserDefaults, reads: inout Int) -> Set<KeepAwakeAutomationCondition>? {
            KeepAwakeManager.timerHandoff(trigger: trigger, suppressed: suppressed, in: defaults,
                                          batteryAllows: { batteryAllows },
                                          matching: { reads += 1; return matching },
                                          enabled: { enabled }, requireAll: { requireAll })
        }

        func handoff(in defaults: UserDefaults) -> Set<KeepAwakeAutomationCondition>? {
            var reads = 0
            return handoff(in: defaults, reads: &reads)
        }
    }

    static func run(expect: (Bool, String) -> Void) {
        let domain = "com.vitruviansoftware.vitruvian.tests.keep-awake-handoff"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)

        // A dock where both conditions are selected and only the monitor is
        // attached: the Mac is on battery with an external display connected,
        // which is the state the timer runs out in.
        expect(Dock(requireAll: true).handoff(in: defaults) == nil,
               "a timer running out on battery hands nothing over to an All automation")
        expect(Dock(requireAll: false).handoff(in: defaults) == [.externalDisplay],
               "the same timer still hands over under Any, which is today's behaviour")
        var plugged = Dock(requireAll: true)
        plugged.matching = [.externalDisplay, .power]
        expect(plugged.handoff(in: defaults) == [.externalDisplay, .power],
               "All hands the session over once every selected condition is met")

        // The guards the handoff already had stay in force under either mode.
        for requireAll in [false, true] {
            let mode = requireAll ? "All" : "Any"
            var met = Dock(requireAll: requireAll)
            met.matching = met.enabled

            var automatic = met
            automatic.trigger = .automation
            var reads = 0
            expect(automatic.handoff(in: defaults, reads: &reads) == nil && reads == 0,
                   "\(mode): a session already running automatically is never handed to itself, nor reads the conditions")

            var suppressed = met
            suppressed.suppressed = true
            expect(suppressed.handoff(in: defaults) == nil,
                   "\(mode): a session switched off by hand is not restarted by the timer")

            var drained = met
            drained.batteryAllows = false
            expect(drained.handoff(in: defaults) == nil, "\(mode): battery protection outranks the handoff")

            defaults.set(false, forKey: AppFeature.keepAwake.availabilityKey)
            expect(met.handoff(in: defaults) == nil, "\(mode): a Keep Awake removed from the hub hands nothing over")
            defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)
            expect(met.handoff(in: defaults) == met.enabled, "\(mode): every selected condition met hands over")
        }
    }
}
