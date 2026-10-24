// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Combine
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Launch never waits for Bluetooth. macOS holds the first Bluetooth read
/// until the person answers its permission prompt, and asks again after an
/// update to an ad hoc signed app; on the main thread that read froze the
/// whole launch behind a prompt that could be hidden under another window.
/// The service hands every Bluetooth query to its connection monitor, whose
/// worker here runs only when the test drains it.
enum NotchAccessoryLaunchTests {
    private nonisolated final class Source: NotchAccessoryConnectionSource {
        var starts = 0
        var stops = 0
        func start(isCancelled: @escaping () -> Bool, onEvent: @escaping (NotchAccessoryConnectionEvent) -> Void) {
            starts += 1
        }
        func stop() { stops += 1 }
    }

    private final class Fixture {
        var enabled = true
        var monitoring: [Bool] = []
        /// Work handed to the Bluetooth thread, run when the test says.
        var worker: [() -> Void] = []
        var sources: [Source] = []
        lazy var service = NotchAccessoryService(environment: NotchAccessoryEnvironment(
            isEnabled: { [unowned self] in self.enabled },
            makeConnectionMonitor: { [unowned self] in
                NotchAccessoryConnectionMonitor(
                    perform: { [unowned self] in self.worker.append($0) },
                    deliver: { $0() },
                    makeSource: { [unowned self] _ in
                        let source = Source()
                        self.sources.append(source)
                        return source
                    })
            },
            batterySamples: { Empty(completeImmediately: false).eraseToAnyPublisher() },
            setBatteryMonitoring: { [unowned self] in self.monitoring.append($0) }))

        /// The Bluetooth thread catches up.
        func drain() { while !worker.isEmpty { worker.removeFirst()() } }
    }

    static func run(_ suite: TestSuite) {
        let fixture = Fixture()
        fixture.service.syncWithPreferences()
        suite.expect(fixture.sources.isEmpty && !fixture.worker.isEmpty,
                     "turning accessories on returns with the Bluetooth work still waiting on its own thread")
        suite.expect(fixture.monitoring == [true],
                     "battery readings start at once: they do not wait for Bluetooth")
        fixture.drain()
        suite.expect(fixture.sources.count == 1 && fixture.sources[0].starts == 1,
                     "the Bluetooth thread then reads and watches connections")

        fixture.service.syncWithPreferences()
        fixture.drain()
        suite.expect(fixture.sources.count == 1, "a second sync while running watches nothing again")

        fixture.enabled = false
        fixture.service.syncWithPreferences()
        fixture.drain()
        suite.expect(fixture.monitoring == [true, false] && fixture.sources[0].stops == 1,
                     "switching accessories off stops the battery readings and the Bluetooth watch")

        // A restart before the Bluetooth thread catches up starts nothing for
        // the activation it replaced.
        fixture.enabled = true
        fixture.service.syncWithPreferences()
        fixture.service.suspend()
        fixture.service.syncWithPreferences()
        fixture.drain()
        suite.expect(fixture.sources.count == 2 && fixture.sources[1].starts == 1,
                     "a restart watches connections once, for its own activation")
        fixture.service.stop()
        fixture.drain()
        suite.expect(fixture.sources[1].stops == 1, "stopping the service stops its Bluetooth watch")
    }
}
