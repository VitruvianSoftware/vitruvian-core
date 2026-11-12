// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianServices

/// The production hand-off and return over workspace replies the test gives.
/// No application or store URL is opened, and nothing is scanned.
enum AppUpdateHandoffTests {
    final class Workspace {
        var replies: [@Sendable (Bool) -> Void] = []
    }

    static func service(_ workspace: Workspace, _ scans: AppUpdateRulesContract.Scans) -> AppUpdatesService {
        AppUpdatesService(environment: .init(
            defaults: AppUpdateRulesContract.defaults, isAvailable: { true },
            notify: { _, _ in },
            scan: { request, _ in scans.requests.append(request) },
            open: { _, reply in workspace.replies.append(reply) }))
    }

    private static func drain(_ suite: TestSuite) {
        var finished = false
        DispatchQueue.main.async { finished = true }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !finished, Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        suite.expect(finished, "workspace failure replies return to the main queue")
    }

    static func run(_ suite: TestSuite) {
        for succeeded in [true, false] {
            let workspace = Workspace()
            let scans = AppUpdateRulesContract.Scans()
            let service = service(workspace, scans)
            service.openAppStoreUpdates()
            suite.expect(service.updateHandoffPending && workspace.replies.count == 1,
                         "an asynchronous handoff is pending before its workspace reply")
            workspace.replies[0](succeeded)
            drain(suite)
            service.applicationBecameActive()
            suite.expect(scans.requests.count == (succeeded ? 1 : 0)
                         && service.consumeUpdateHandoffReturn() == succeeded
                         && !service.consumeUpdateHandoffReturn(),
                         "only a successful handoff refreshes and restores the window once")
        }
        for failedIndex in [0, 1] {
            let workspace = Workspace()
            let service = service(workspace, AppUpdateRulesContract.Scans())
            service.openAppStoreUpdates()
            service.openAppStoreUpdates()
            workspace.replies[1 - failedIndex](true)
            workspace.replies[failedIndex](false)
            drain(suite)
            suite.expect(service.updateHandoffPending && service.consumeUpdateHandoffReturn(),
                         "failure of request \(failedIndex) cannot erase the other successful handoff")
        }
        let failedWorkspace = Workspace()
        let failed = service(failedWorkspace, AppUpdateRulesContract.Scans())
        failed.openAppStoreUpdates()
        failed.openAppStoreUpdates()
        failedWorkspace.replies.reversed().forEach { $0(false) }
        drain(suite)
        suite.expect(!failed.updateHandoffPending && !failed.consumeUpdateHandoffReturn(),
                     "two failed requests leave no pending handoff")

        let returnedWorkspace = Workspace()
        let returned = service(returnedWorkspace, AppUpdateRulesContract.Scans())
        returned.openAppStoreUpdates()
        suite.expect(returned.consumeUpdateHandoffReturn(),
                     "a return may be consumed before the workspace completion arrives")
        returned.openAppStoreUpdates()
        returnedWorkspace.replies[0](false)
        drain(suite)
        suite.expect(returned.updateHandoffPending && returned.consumeUpdateHandoffReturn(),
                     "a failed request from an earlier return cannot clear a new handoff")
        returnedWorkspace.replies[1](true)
        drain(suite)
        suite.expect(!returned.updateHandoffPending,
                     "a late success does not restore an already consumed return")
    }
}
