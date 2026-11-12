// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The inbox's settings, in a suite-named UserDefaults of the test's own (never the real one).
final class InboxPreferencesTests: XCTestCase {
    private var store: TestDefaults!

    override func setUp() {
        store = TestDefaults()
    }

    override func tearDown() {
        store.remove()
    }

    func testDefaultsMatchTheInventory() {
        let preferences = InboxPreferences(defaults: store.defaults)
        XCTAssertTrue(preferences.showSpaceBar)
        XCTAssertFalse(preferences.regularPinnedRows)
        XCTAssertTrue(preferences.showUnreadCounts)
        XCTAssertTrue(preferences.showPreviews)
        XCTAssertFalse(preferences.compactList)
        XCTAssertTrue(preferences.showNetworkIcons)
        XCTAssertTrue(preferences.colorNetworkIcons)
        XCTAssertEqual(preferences.hoverAction, .archive)
        XCTAssertEqual(preferences.doubleClickAction, .nothing, "Open in New Window comes with 4.5")
        XCTAssertEqual(preferences.remindDefault, .ifNoReply)
        XCTAssertFalse(preferences.archiveAfterReminder)
        XCTAssertFalse(preferences.markReadOnArchive)
        XCTAssertEqual(preferences.afterArchive, .selectNext)
        XCTAssertEqual(preferences.afterToggleRead, .selectNext)
        XCTAssertTrue(preferences.requestNotifications)
        XCTAssertNil(preferences.lastUsedReminder)
        // 02 §1.5: "Notify when someone starts typing (supported platforms only)" is off.
        XCTAssertFalse(preferences.typingNotifications)
        XCTAssertTrue(store.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("courier.") }.isEmpty,
                      "reading the defaults writes nothing")
    }

    func testValuesPersistUnderTheirKeys() {
        let preferences = InboxPreferences(defaults: store.defaults)
        let when = Date(timeIntervalSince1970: 1_760_700_000)
        preferences.showSpaceBar = false
        preferences.regularPinnedRows = true
        preferences.showUnreadCounts = false
        preferences.showPreviews = false
        preferences.compactList = true
        preferences.showNetworkIcons = false
        preferences.colorNetworkIcons = false
        preferences.hoverAction = .toggleRead
        preferences.doubleClickAction = .toggleLowPriority
        preferences.remindDefault = .always
        preferences.archiveAfterReminder = true
        preferences.markReadOnArchive = true
        preferences.afterArchive = .closeChat
        preferences.afterToggleRead = .selectPrevious
        preferences.requestNotifications = false
        preferences.lastUsedReminder = when
        preferences.typingNotifications = true

        let defaults = store.defaults
        XCTAssertEqual(defaults.object(forKey: "courier.inbox.showSpaceBar") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "courier.inbox.regularPinnedRows") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "courier.inbox.compactList") as? Bool, true)
        XCTAssertEqual(defaults.string(forKey: "courier.inbox.hoverAction"), "toggleRead")
        XCTAssertEqual(defaults.string(forKey: "courier.inbox.doubleClickAction"), "toggleLowPriority")
        XCTAssertEqual(defaults.string(forKey: "courier.inbox.remindDefault"), "always")
        XCTAssertEqual(defaults.string(forKey: "courier.inbox.afterArchive"), "closeChat")
        XCTAssertEqual(defaults.string(forKey: "courier.inbox.afterToggleRead"), "selectPrevious")
        XCTAssertEqual(defaults.object(forKey: "courier.inbox.lastUsedReminder") as? Date, when)

        let again = InboxPreferences(defaults: defaults)
        XCTAssertFalse(again.showSpaceBar)
        XCTAssertTrue(again.regularPinnedRows)
        XCTAssertFalse(again.showUnreadCounts)
        XCTAssertFalse(again.showPreviews)
        XCTAssertTrue(again.compactList)
        XCTAssertFalse(again.showNetworkIcons)
        XCTAssertFalse(again.colorNetworkIcons)
        XCTAssertEqual(again.hoverAction, .toggleRead)
        XCTAssertEqual(again.doubleClickAction, .toggleLowPriority)
        XCTAssertEqual(again.remindDefault, .always)
        XCTAssertTrue(again.archiveAfterReminder)
        XCTAssertTrue(again.markReadOnArchive)
        XCTAssertEqual(again.afterArchive, .closeChat)
        XCTAssertEqual(again.afterToggleRead, .selectPrevious)
        XCTAssertFalse(again.requestNotifications)
        XCTAssertEqual(again.lastUsedReminder, when)
        XCTAssertTrue(again.typingNotifications)
        XCTAssertEqual(defaults.object(forKey: "courier.inbox.typingNotifications") as? Bool, true)

        // Clearing the last reminder time removes its key.
        again.lastUsedReminder = nil
        XCTAssertNil(defaults.object(forKey: "courier.inbox.lastUsedReminder"))
    }

    func testAValueThisVersionDoesNotKnowFallsBackToTheDefault() {
        store.defaults.set("unknownFutureAction", forKey: "courier.inbox.doubleClickAction")
        XCTAssertEqual(InboxPreferences(defaults: store.defaults).doubleClickAction, .nothing)
    }
}
