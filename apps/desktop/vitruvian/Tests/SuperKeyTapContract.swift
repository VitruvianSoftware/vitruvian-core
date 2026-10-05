// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The real service starts its tap thread against a macOS that refuses every
/// event tap. The thread body runs inline, hidutil is a recording, and the
/// settings are a private suite: no tap, key mapping or thread is created.
enum SuperKeyTapContract {
    /// What the service asked of the system, from whichever thread asked.
    nonisolated final class Machine: @unchecked Sendable {
        private let lock = NSLock()
        private var _tapRequests: [CGEventTapLocation] = []
        private var _hidutil: [[String]] = []
        private var _pending: [@MainActor @Sendable () -> Void] = []
        var trusted = true

        var tapRequests: [CGEventTapLocation] { lock.withLock { _tapRequests } }
        var hidutilCalls: [[String]] { lock.withLock { _hidutil } }

        func system(defaults: UserDefaults) -> SuperKeyService.System {
            SuperKeyService.System(
                defaults: defaults,
                createTap: { [self] location, _, _, _, _, _ in
                    lock.withLock { _tapRequests.append(location) }
                    return nil
                },
                runThread: { $0.main() },
                main: { [self] work in lock.withLock { _pending.append(work) } },
                isTrusted: { [self] in trusted },
                hidutil: { [self] arguments in
                    lock.withLock { _hidutil.append(arguments) }
                    return (1, "")
                })
        }

        /// Runs what the tap thread handed to the main queue.
        @MainActor func drainMain() {
            let work = lock.withLock { () -> [@MainActor @Sendable () -> Void] in
                defer { _pending.removeAll() }
                return _pending
            }
            work.forEach { $0() }
        }

        /// Waits for the mapping queue to ask hidutil, which it does off the
        /// main thread.
        func waitForHidutil(_ count: Int) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while hidutilCalls.count < count, Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            return hidutilCalls.count >= count
        }
    }

    /// A private settings suite, removed when `body` returns.
    static func withDefaults(mappingApplied: Bool, _ body: (UserDefaults) -> Void) {
        let name = "vitru.tests.super-key-tap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        if mappingApplied { defaults.set(true, forKey: DefaultsKey.superKeyMappingApplied) }
        body(defaults)
    }

    static func run(_ suite: TestSuite) {
        withDefaults(mappingApplied: false) { defaults in
            let machine = Machine()
            let service = SuperKeyService(system: machine.system(defaults: defaults))
            service.start()
            suite.expect(machine.tapRequests == [.cgSessionEventTap] && service.mappingFailure == nil,
                         "the keyboard tap is asked for on the tap thread, which reports back on the main queue")
            machine.drainMain()
            suite.expect(!service.isRunning && !SuperKeyService.isEngaged
                         && service.mappingFailure == .keyboardTapRefused,
                         "a refused keyboard tap stops the key and reports why, found \(String(describing: service.mappingFailure))")
            suite.expect(machine.hidutilCalls.isEmpty, "a key never mapped leaves hidutil alone")
        }
        withDefaults(mappingApplied: true) { defaults in
            let machine = Machine()
            let service = SuperKeyService(system: machine.system(defaults: defaults))
            service.start()
            machine.drainMain()
            suite.expect(machine.waitForHidutil(1) && machine.hidutilCalls.first?.contains("--get") == true,
                         "a refused tap takes out a mapping an earlier run may have left")
        }
        withDefaults(mappingApplied: true) { defaults in
            let machine = Machine()
            machine.trusted = false
            let service = SuperKeyService(system: machine.system(defaults: defaults))
            service.start()
            suite.expect(machine.tapRequests.isEmpty && !service.isRunning && machine.waitForHidutil(1),
                         "without Accessibility no tap is asked for, and a leftover mapping still comes out")
        }
    }
}
