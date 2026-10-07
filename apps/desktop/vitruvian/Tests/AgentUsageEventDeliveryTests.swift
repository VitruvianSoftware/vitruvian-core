// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The production delivery rule against preferences in a test domain. No
/// agent logs, network or notification windows.
enum AgentUsageEventDeliveryTests {
    static func run(_ suite: TestSuite) {
        let domain = "com.vitruviansoftware.vitruvian.tests.agent-usage-events"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(10.0, forKey: DefaultsKey.notchAgentsFinishMinimum)
        defaults.set(1.0, forKey: DefaultsKey.notchAgentsDailyBudget)
        var running = true
        var session = 1
        var providers: [AgentProvider] = [.claude, .codex, .copilot]
        func delivered(_ events: [AgentUsageEvent], queuedIn queued: Int = 1) -> [AgentUsageEvent] {
            events.filter {
                AgentUsageService.delivers($0, queuedIn: queued, running: running, session: session,
                                           providers: providers, in: defaults)
            }
        }
        let finished = AgentUsageEvent.finished(provider: .claude, duration: 20, cost: 0.5,
                                                  tokens: 30, project: "example")
        let window = AgentLimitWindow(id: "test", kind: .session, minutes: 300, scope: nil,
                                      usedPercent: 90, resetsAt: nil)
        let events: [AgentUsageEvent] = [finished, .limitWarning(provider: .claude, window: window),
                                       .limitReset(provider: .claude, window: window),
                                       .budgetReached(spent: 2, budget: 1)]
        // Stop/restart can finish on main before any queued event is delivered.
        session += 1
        suite.expect(delivered(events).isEmpty,
                     "events queued by a previous agent reading cannot leak into a restarted session")
        suite.expect(delivered(events, queuedIn: session) == events,
                     "the current session still delivers completion, warning, renewal and budget events")

        session = 1
        running = false
        suite.expect(delivered([finished]).isEmpty, "stopping without restarting still drops queued events")
        running = true

        providers = [.codex]
        suite.expect(delivered(Array(events[0...2])).isEmpty, "delivery still respects disabled providers")
        providers = [.claude, .codex, .copilot]
        defaults.set(30.0, forKey: DefaultsKey.notchAgentsFinishMinimum)
        defaults.set(false, forKey: DefaultsKey.notchAgentsLimitAlert)
        defaults.removeObject(forKey: DefaultsKey.notchAgentsDailyBudget)
        suite.expect(delivered(events).isEmpty, "duration and disabled-alert preferences still filter current events")
    }
}
