// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// Settings ▸ About with its Updates section, as a check leaves it. Look at settings-about-update-*: an update on
/// offer (Download and Install, Release Notes), up to date, and a check that failed. Nothing reaches the network.
@MainActor
final class UpdatesSnapshotTests: XCTestCase {
    private struct Releases: UpdateEnvironment {
        let tags: [String]
        let status: Int

        func send(_: URLRequest) async throws -> UpdateReply {
            var body = Data()
            for tag in tags {
                let line = "\(String(repeating: "0", count: 40)) refs/tags/\(tag)\n"
                body += Data(String(format: "%04x", line.utf8.count + 4).utf8) + Data(line.utf8)
            }
            return UpdateReply(status: status, body: body + Data("0000".utf8))
        }

        func download(_: URL, to _: URL, progress _: @escaping @Sendable (Double) -> Void) async throws {}
        func sha256(of _: URL) throws -> String { "" }
        func satisfies(_: URL, requirement _: String) -> Bool { false }
        func passesGatekeeper(_: URL) -> Bool { false }
        func mount(_: URL) throws -> URL { URL(fileURLWithPath: "/nonexistent") }
        func unmount(_: URL) {}
        func bundleVersion(of _: URL) -> String? { nil }
        func copy(_: URL, to _: URL) throws {}
        func isWritableDirectory(_: URL) -> Bool { false }
        func remove(_: URL) {}
        func launchInstaller(script _: String, arguments _: [String]) throws {}
    }

    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
    }

    private func updates(_ releases: Releases) async -> UpdateModel {
        let suite = "courier.snapshots.updates.\(UUID().uuidString)"
        suites.append(suite)
        let model = UpdateModel(currentVersion: "0.7.0", appURL: URL(fileURLWithPath: "/Applications/Courier.app"),
                                environment: releases, defaults: UserDefaults(suiteName: suite)!,
                                now: { Date(timeIntervalSince1970: 1_800_000_000) }, quit: {})
        await model.check()
        return model
    }

    func testAboutPaneUpdatesSectionSnapshots() async throws {
        let lifecycle = SystemLifecycleModel(
            loginItemService: SnapshotLoginItemService(),
            biometricService: SnapshotBiometricService(),
            defaults: UserDefaults(suiteName: "courier.snapshots.updates.lifecycle.\(UUID().uuidString)")!
        )
        let cases: [(String, Releases)] = [
            ("available", Releases(tags: ["courier-v0.7.0", "courier-v0.8.0"], status: 200)),
            ("current", Releases(tags: ["courier-v0.7.0"], status: 200)),
            ("failed", Releases(tags: [], status: 429)),
        ]
        for (name, releases) in cases {
            let model = await updates(releases)
            let sizes = try Snapshot.render("settings-about-update-\(name)", width: 640, height: 520) {
                AboutSettingsPane(lifecycle: lifecycle, appVersion: "0.7.0", buildNumber: "0.7.0", updates: model)
            }
            XCTAssertEqual(sizes.count, 2)
        }
    }
}
