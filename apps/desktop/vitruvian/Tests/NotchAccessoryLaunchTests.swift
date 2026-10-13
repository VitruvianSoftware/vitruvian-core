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
enum NotchAccessoryLaunchTests {
    /// A first Bluetooth read that does not return until the test lets it,
    /// the way the real one waits for the prompt. It gives up after
    /// `patience`, so code that reads on the main thread fails these checks
    /// instead of hanging the run.
    private nonisolated final class HeldRead: @unchecked Sendable {
        private let lock = NSLock()
        private let gate = DispatchSemaphore(value: 0)
        private var startedCount = 0
        private var finishedCount = 0
        private var mainThreadReads = 0
        let patience: TimeInterval

        init(patience: TimeInterval = 3) { self.patience = patience }

        var started: Int { lock.withLock { startedCount } }
        var finished: Int { lock.withLock { finishedCount } }
        var readsOnMainThread: Int { lock.withLock { mainThreadReads } }

        /// Each read reports one device of its own, named for its turn.
        func read() -> NotchAccessoryBaseline {
            let turn = lock.withLock {
                startedCount += 1
                if Thread.isMainThread { mainThreadReads += 1 }
                return startedCount
            }
            _ = gate.wait(timeout: .now() + patience)
            lock.withLock { finishedCount += 1 }
            return NotchAccessoryBaseline(addresses: ["device-\(turn)"])
        }

        /// The person answers the prompt: one waiting read returns.
        func answer() { gate.signal() }
    }

    private final class Fixture {
        let held = HeldRead()
        var enabled = true
        var registrations = 0
        var monitoring: [Bool] = []
        lazy var service = NotchAccessoryService(environment: NotchAccessoryEnvironment(
            isEnabled: { [unowned self] in self.enabled },
            readBaseline: { [held] in held.read() },
            registerForConnections: { [unowned self] _, _ in
                self.registrations += 1
                return nil
            },
            batterySamples: { Empty(completeImmediately: false).eraseToAnyPublisher() },
            setBatteryMonitoring: { [unowned self] in self.monitoring.append($0) }))

        /// Whether the service already counts this device as connected, which
        /// is what a silent baseline means: its connection is not announced.
        func knows(_ address: String) -> Bool {
            var state = service.connectionState
            return !state.connected(address)
        }

        /// Lets the main queue run until `done`, or for two seconds.
        func pump(until done: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !done(), Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
            }
        }

        /// Lets every read that has returned reach the main thread.
        func settle(reads: Int) {
            pump { held.finished == reads }
            var delivered = false
            DispatchQueue.main.async { delivered = true }
            pump { delivered }
        }
    }

    static func run(_ suite: TestSuite) {
        returnsBeforeTheAnswer(suite)
        stopDropsALateAnswer(suite)
        restartKeepsOnlyItsOwnAnswer(suite)
    }

    private static func returnsBeforeTheAnswer(_ suite: TestSuite) {
        let fixture = Fixture()
        let began = ProcessInfo.processInfo.systemUptime
        fixture.service.syncWithPreferences()
        let waited = ProcessInfo.processInfo.systemUptime - began
        suite.expect(waited < fixture.held.patience / 2,
                     "turning accessories on returns while the Bluetooth read is still held (\(waited)s)")
        fixture.pump { fixture.held.started == 1 }
        suite.expect(fixture.held.started == 1 && fixture.held.readsOnMainThread == 0,
                     "the first Bluetooth read runs, and never on the main thread")
        suite.expect(fixture.monitoring == [true],
                     "battery readings start at once: they do not wait for the Bluetooth answer")
        suite.expect(fixture.registrations == 0 && !fixture.knows("device-1"),
                     "nothing is watched before the read returns")

        fixture.held.answer()
        fixture.settle(reads: 1)
        suite.expect(fixture.knows("device-1"),
                     "once the read returns, who was already connected is the silent baseline")
        suite.expect(fixture.registrations == 1, "and new connections are watched from then on")

        fixture.service.syncWithPreferences()
        fixture.settle(reads: 1)
        suite.expect(fixture.held.started == 1 && fixture.registrations == 1,
                     "a second sync while running reads nothing again")
        fixture.service.stop()
    }

    private static func stopDropsALateAnswer(_ suite: TestSuite) {
        let fixture = Fixture()
        fixture.service.syncWithPreferences()
        fixture.pump { fixture.held.started == 1 }
        fixture.enabled = false
        fixture.service.syncWithPreferences()
        suite.expect(fixture.monitoring == [true, false], "switching accessories off stops the service")

        fixture.held.answer()
        fixture.settle(reads: 1)
        suite.expect(fixture.held.finished == 1, "the held read did return")
        suite.expect(fixture.registrations == 0 && !fixture.knows("device-1"),
                     "an answer that arrives after a stop is dropped: no baseline, nothing watched")
    }

    private static func restartKeepsOnlyItsOwnAnswer(_ suite: TestSuite) {
        let fixture = Fixture()
        fixture.service.syncWithPreferences()
        fixture.pump { fixture.held.started == 1 }
        fixture.service.suspend()
        fixture.service.syncWithPreferences()

        fixture.held.answer()
        fixture.settle(reads: 1)
        suite.expect(fixture.registrations == 0 && !fixture.knows("device-1"),
                     "the read from before a restart does not become the new baseline")

        fixture.pump { fixture.held.started == 2 }
        fixture.held.answer()
        fixture.settle(reads: 2)
        suite.expect(fixture.knows("device-2") && !fixture.knows("device-1") && fixture.registrations == 1,
                     "the restart's own read does, once")
        fixture.service.stop()
    }
}
