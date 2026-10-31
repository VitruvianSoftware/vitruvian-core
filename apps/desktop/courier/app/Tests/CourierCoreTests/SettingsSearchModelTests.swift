// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

@MainActor
final class SettingsSearchModelTests: XCTestCase {
    override func setUp() {
        AppLockGate.shared.resetForTesting()
    }

    override func tearDown() {
        AppLockGate.shared.resetForTesting()
    }

    func testSearchSuggestionsMatchQueriesAndJumpSwitchesPanes() {
        let model = SettingsNavigationModel()
        XCTAssertEqual(model.selectedPane, .general)
        XCTAssertEqual(model.searchQuery, "")
        XCTAssertTrue(model.suggestions.isEmpty, "empty query shows no dropdown suggestions")

        model.searchQuery = "touch id"
        XCTAssertTrue(model.suggestions.contains { $0.id == "general.requireTouchID" && $0.pane == .general })

        model.searchQuery = "otp"
        let otpPanes = Set(model.suggestions.map(\.pane))
        XCTAssertTrue(otpPanes.contains(.general) || otpPanes.contains(.notifications))
        XCTAssertTrue(model.suggestions.contains { $0.title.localizedCaseInsensitiveContains("OTP") })

        model.searchQuery = "delay"
        let delayMatch = model.suggestions.first { $0.id == "notifications.delay" }
        XCTAssertNotNil(delayMatch)
        XCTAssertEqual(delayMatch?.pane, .notifications)
        XCTAssertEqual(delayMatch?.badge, .labs)

        model.searchQuery = "dock"
        XCTAssertTrue(model.suggestions.contains { $0.id == "appearance.dockBadgeCount" && $0.pane == .appearance })
        XCTAssertTrue(model.suggestions.contains { $0.id == "accounts.dockCleanup" && $0.pane == .accounts })

        model.searchQuery = "composer"
        XCTAssertTrue(model.suggestions.contains { $0.id == "appearance.primaryComposerButton" && $0.pane == .appearance })
        XCTAssertTrue(model.suggestions.contains { $0.id == "appearance.secondaryComposerButton" && $0.pane == .appearance })

        if let target = delayMatch {
            model.jump(to: target)
            XCTAssertEqual(model.selectedPane, .notifications)
            XCTAssertEqual(model.highlightedSettingID, "notifications.delay")
            XCTAssertEqual(model.searchQuery, "", "jumping clears the search field")
        }

        model.openPane(.accounts, accountKey: "whatsapp:wa-1")
        XCTAssertEqual(model.selectedPane, .accounts)
        XCTAssertEqual(model.selectedAccountKey, "whatsapp:wa-1")
    }

    func testEveryVisibleSettingInCatalogIsFindableAndEveryPaneIsCovered() {
        let model = SettingsNavigationModel()
        let catalog = SettingsNavigationModel.allSettings
        XCTAssertFalse(catalog.isEmpty)

        // Every pane in SettingsPaneID has at least one setting definition in the single source-of-truth catalog.
        for pane in SettingsPaneID.allCases {
            XCTAssertTrue(
                catalog.contains { $0.pane == pane },
                "Expected catalog to contain settings for pane \(pane.rawValue)"
            )
            XCTAssertFalse(pane.title.isEmpty)
            XCTAssertFalse(pane.symbolName.isEmpty)
        }

        // Every setting in the catalog is findable by its title and by its keywords.
        for definition in catalog {
            model.searchQuery = definition.title
            XCTAssertTrue(
                model.suggestions.contains(definition),
                "Setting \(definition.id) (\(definition.title)) was not findable by title"
            )
            for keyword in definition.keywords {
                model.searchQuery = keyword
                XCTAssertTrue(
                    model.suggestions.contains(definition),
                    "Setting \(definition.id) was not findable by keyword '\(keyword)'"
                )
            }
        }
    }
}
