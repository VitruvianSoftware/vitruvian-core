// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The General page's launch-at-login model over an inert system service and
/// queues the test runs one job at a time. No login item or user preference
/// is changed by these tests.
enum LaunchAtLoginSettingsTests {
    nonisolated enum Failure: LocalizedError {
        case approval, unavailable
        var errorDescription: String? { "test service failure" }
    }

    nonisolated final class System: @unchecked Sendable {
        var registration: LaunchAtLoginSupport.Registration = .off
        /// What a toggle leaves the system holding.
        var result: LaunchAtLoginSupport.Registration = .off
        var failure: Failure?
        var writes: [Bool] = []
        var worker: [@Sendable () -> Void] = []
        var main: [@MainActor @Sendable () -> Void] = []

        func drainWorker() { while !worker.isEmpty { worker.removeFirst()() } }
        @MainActor func drainMain() { while !main.isEmpty { main.removeFirst()() } }

        var environment: LaunchAtLoginSettingsModel.Environment {
            LaunchAtLoginSettingsModel.Environment(
                registration: { self.registration },
                setEnabled: { enabled in
                    self.writes.append(enabled)
                    self.registration = self.result
                    if let failure = self.failure { throw failure }
                },
                background: { self.worker.append($0) },
                main: { self.main.append($0) })
        }
    }

    static func run(_ suite: TestSuite) {
        let system = System()
        let model = LaunchAtLoginSettingsModel(wanted: false, environment: system.environment)
        // Like the real service: one serial worker, answers published on main.
        func settle() {
            system.drainWorker()
            system.drainMain()
        }
        func refresh(to registration: LaunchAtLoginSupport.Registration) {
            system.registration = registration
            model.refresh()
            settle()
        }
        func toggle(_ enabled: Bool) {
            model.setEnabled(enabled)
            settle()
        }

        system.registration = .needsApproval
        model.refresh()
        suite.expect(!model.isPending,
                     "a status read keeps the switch usable, so opening the page does not flash a spinner")
        settle()
        suite.expect(model.registration == .needsApproval,
                     "opening settings preserves pending approval instead of flattening it to off")
        refresh(to: .off)
        suite.expect(model.registration == .off && model.errorText == nil,
                     "removing the login item clears approval guidance without claiming it is enabled")
        suite.expect(system.writes.isEmpty, "refresh never registers or unregisters a login item")

        system.result = .off
        system.failure = .unavailable
        toggle(true)
        suite.expect(model.registration == .off && model.errorText == Failure.unavailable.localizedDescription,
                     "an unrelated registration failure still has an actionable error")
        system.failure = nil
        refresh(to: .enabled)
        suite.expect(model.registration == .enabled && model.errorText == nil,
                     "refresh after system approval enables the toggle and clears the old warning")

        system.result = .needsApproval
        system.failure = .approval
        model.setEnabled(true)
        suite.expect(model.isPending && model.errorText == nil && system.writes.count == 1,
                     "the switch waits for the system to answer a change, without the last attempt's error")
        suite.expect(model.registration == .enabled,
                     "the switch stays where the user put it instead of springing back while it waits")
        settle()
        suite.expect(model.registration == .needsApproval && model.errorText == nil && !model.isPending,
                     "pending approval is shown from current status without a duplicate operation error")
        system.failure = nil
        toggle(true)
        suite.expect(model.registration == .needsApproval,
                     "a successful register call does not imply that macOS allowed the item")

        system.registration = .enabled
        model.refresh()
        system.drainWorker() // The old enabled snapshot is waiting for publication.
        system.result = .off
        toggle(false)
        suite.expect(model.registration == .off && model.errorText == nil && !model.isPending,
                     "a stale refresh cannot undo a later user disable")

        system.registration = .needsApproval
        model.refresh()
        system.drainWorker()
        system.registration = .enabled
        model.refresh()
        system.drainWorker()
        let newest = system.main.removeLast()
        newest()
        system.drainMain()
        suite.expect(model.registration == .enabled,
                     "an older approval snapshot cannot overwrite a newer refresh")
        system.result = .enabled
        model.setEnabled(true)
        model.refresh() // An activation reads while the change is still queued.
        settle()
        suite.expect(model.registration == .enabled && !model.isPending,
                     "a read that replaces a change's answer reports the change and frees the switch")
        suite.expect(system.writes == [true, true, true, false, true],
                     "only explicit toggle actions write to the system service")

        refresh(to: .needsApproval)
        suite.expect(model.isOn, "an item awaiting approval is still registered, so its switch reads on")
        system.result = .off
        toggle(false)
        suite.expect(!model.isOn && model.registration == .off && model.errorText == nil && system.writes.last == false,
                     "switching off an item awaiting approval unregisters it and clears the note")
    }
}
