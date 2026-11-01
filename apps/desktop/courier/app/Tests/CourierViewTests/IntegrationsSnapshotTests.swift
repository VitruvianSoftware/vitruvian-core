// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// Settings ▸ Integrations drawn light and dark for a person to look at: off; on with two connections; the port in
/// use; Remote Access on; and the new-connection sheet showing a (made-up) secret. All data here is made up.
@MainActor
final class IntegrationsSnapshotTests: XCTestCase {
    private static let enginePath = "/Applications/Courier.app/Contents/Helpers/courier-engine"
    private static let madeUpSecret = "courier_Zm9yLXNuYXBzaG90cy1vbmx5LW5vdC1hLXJlYWwtdG9rZW4" // gitleaks:allow (made up)

    private func model(_ status: IntegrationsStatus?, tokens: [APIToken] = [],
                       created: CreateTokenResult? = nil) -> IntegrationsModel {
        let model = IntegrationsModel(appModel: nil, enginePath: Self.enginePath, networkAddress: { "192.168.1.20" })
        model.setForTesting(status: status, tokens: tokens, created: created)
        return model
    }

    private static let twoTokens = [
        APIToken(id: "tok_1", name: "Claude Code", canSend: false, createdMs: 1_793_500_000_000,
                 lastUsedMs: 1_793_560_000_000),
        APIToken(id: "tok_2", name: "Example desktop client with a long name", canSend: true,
                 createdMs: 1_793_400_000_000, lastUsedMs: nil),
    ]

    private func check(_ sizes: [NSSize], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(sizes.count, 2, file: file, line: line)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 100, file: file, line: line)
            XCTAssertGreaterThan(size.height, 30, file: file, line: line)
        }
    }

    func testIntegrationsPane() throws {
        let off = model(IntegrationsStatus())
        check(try Snapshot.render("integrations-off", width: 620, height: 900) {
            IntegrationsSettingsPane(model: off)
        })

        let on = model(IntegrationsStatus(enabled: true, listening: true), tokens: Self.twoTokens)
        check(try Snapshot.render("integrations-on-two-tokens", width: 620, height: 900) {
            IntegrationsSettingsPane(model: on)
        })

        let busy = model(IntegrationsStatus(enabled: true, listening: false,
                                            error: "Port 23390 is in use by another app"),
                         tokens: [Self.twoTokens[0]])
        check(try Snapshot.render("integrations-port-in-use", width: 620, height: 900) {
            IntegrationsSettingsPane(model: busy)
        })

        let remote = model(IntegrationsStatus(enabled: true, remote: true, listening: true), tokens: Self.twoTokens)
        check(try Snapshot.render("integrations-remote-access", width: 620, height: 900) {
            IntegrationsSettingsPane(model: remote)
        })
    }

    func testNewConnectionSheet() throws {
        let empty = model(IntegrationsStatus(enabled: true, listening: true))
        empty.newConnectionName = "Claude Code"
        check(try Snapshot.render("integrations-new-connection", width: 560) {
            NewConnectionSheet(model: empty)
        })

        let created = CreateTokenResult(
            token: APIToken(id: "tok_3", name: "Claude Code", createdMs: 1_793_500_000_000),
            secret: Self.madeUpSecret
        )
        let made = model(IntegrationsStatus(enabled: true, listening: true), created: created)
        check(try Snapshot.render("integrations-new-connection-secret", width: 560) {
            NewConnectionSheet(model: made)
        })
    }
}
