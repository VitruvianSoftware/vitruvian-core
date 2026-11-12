// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Runs the updater's administrator install with the authorization, the
/// Extra Brightness overlay, the main queue and quitting replaced by doubles
/// that log what ran. The real authorization holds the main thread until it
/// is answered, so anything the prompt needs off the screen must go first.
enum UpdateAdminInstallContract {
    /// What ran, the overlay's state, the pending answer and the main queue.
    /// Only the test's own thread touches it.
    nonisolated final class Record: @unchecked Sendable {
        var events: [String] = []
        var overlayOnScreen = true
        var answer: ((Bool) -> Void)?
        var main: [() -> Void] = []
        func flush() {
            while !main.isEmpty { main.removeFirst()() }
        }
    }

    static func run(_ suite: TestSuite) {
        let dmg = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-admin-install-\(UUID().uuidString).dmg").path
        for granted in [false, true] {
            let record = Record()
            let service = UpdateService(adminInstall: .init(
                authorize: { _, _, completion in
                    record.events.append(record.overlayOnScreen ? "prompt under overlay" : "prompt")
                    record.answer = completion
                },
                hideOverlay: { record.overlayOnScreen = false },
                restoreOverlay: { record.overlayOnScreen = true; record.events.append("overlay") },
                main: { work in record.main.append { MainActor.assumeIsolated { work() } } },
                quit: { record.events.append("quit") }))
            service.launchAdminInstaller(appPath: "/Applications/Vitruvian.app", dmgPath: dmg,
                                         pid: 42, resultPath: "/tmp/update-result", expectedVersion: "9.9.9")
            suite.expect(record.events == ["prompt"],
                         "the brightness overlay leaves the screen before the prompt holds the main thread")
            record.answer?(granted)
            suite.expect(record.events == ["prompt"], "the answer is acted on from the main queue")
            record.flush()
            if granted {
                suite.expect(record.events == ["prompt", "quit"] && !record.overlayOnScreen,
                             "an approved install quits without bringing the overlay back")
            } else {
                suite.expect(record.events == ["prompt", "overlay"] && record.overlayOnScreen
                                 && service.state == .available(version: "9.9.9"),
                             "a declined prompt brings the overlay back and keeps the update offer")
            }
        }
    }
}
