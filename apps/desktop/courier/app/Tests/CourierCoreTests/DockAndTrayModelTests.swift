// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class DockAndTrayModelTests: XCTestCase {
    private func makeRow(
        _ id: String,
        name: String,
        ts: Int64,
        unread: Int = 0,
        markedUnread: Bool = false,
        lowPriority: Bool = false,
        hidden: Bool = false,
        archived: Bool = false
    ) -> InboxRow {
        InboxRow(
            roomID: id,
            network: "signal",
            name: name,
            avatarPath: "",
            isDirect: true,
            lastTS: ts,
            preview: "Hello",
            previewKind: .text,
            previewMine: false,
            unread: unread,
            muted: false,
            pinned: false,
            archived: archived,
            lowPriority: lowPriority,
            hidden: hidden,
            markedUnread: markedUnread,
            request: false
        )
    }

    func testDockMenuModelPopulatesTop5UnreadAndTop5RecentTruncatesTitlesAndRedactsWhenLocked() {
        let longTitle = "Design & Architecture Sync With The Cross-Platform Engineering Team"
        XCTAssertGreaterThan(longTitle.count, 40)

        let rows: [InboxRow] = [
            makeRow("!u1", name: longTitle, ts: 600, unread: 2),
            makeRow("!u2", name: "Alice Example", ts: 500, unread: 1),
            makeRow("!u3", name: "Bob Example", ts: 400, unread: 0, markedUnread: true),
            makeRow("!u4", name: "Carol Example", ts: 300, unread: 3),
            makeRow("!u5", name: "Dan Example", ts: 200, unread: 1),
            makeRow("!u6", name: "Sixth Unread Overflow", ts: 100, unread: 1),
            makeRow("!lp", name: "Low Priority Unread", ts: 700, unread: 4, lowPriority: true),
            makeRow("!hid", name: "Hidden Unread", ts: 800, unread: 2, hidden: true),
            makeRow("!r1", name: "Recent One", ts: 90, unread: 0),
            makeRow("!r2", name: "Recent Two", ts: 80, unread: 0),
            makeRow("!r3", name: "Recent Three", ts: 70, unread: 0),
            makeRow("!r4", name: "Recent Four", ts: 60, unread: 0),
            makeRow("!r5", name: "Recent Five", ts: 50, unread: 0),
            makeRow("!r6", name: "Recent Six Overflow", ts: 40, unread: 0),
            makeRow("!curr", name: "Currently Open Chat", ts: 95, unread: 0),
            makeRow("!rhid", name: "Recent Hidden", ts: 85, unread: 0, hidden: true),
        ]

        let history = ["!curr", "!u2", "!rhid", "!r1", "!r2", "!r3", "!r4", "!r5", "!r6"]

        // 1. When locked, both unreadChats and recentChats are empty
        let lockedMenu = DockMenuModel.build(
            isLocked: true,
            inboxRows: rows,
            recentlyViewedRoomIDs: history,
            currentRoomID: "!curr"
        )
        XCTAssertTrue(lockedMenu.isEmpty)
        XCTAssertTrue(lockedMenu.unreadChats.isEmpty)
        XCTAssertTrue(lockedMenu.recentChats.isEmpty)

        // 2. When unlocked, capped at 5 unread (excluding lowPriority and hidden) and 5 recent (excluding currentRoomID, unreadChats, and hidden)
        let unlockedMenu = DockMenuModel.build(
            isLocked: false,
            inboxRows: rows,
            recentlyViewedRoomIDs: history,
            currentRoomID: "!curr"
        )
        XCTAssertFalse(unlockedMenu.isEmpty)
        XCTAssertEqual(unlockedMenu.unreadChats.map(\.roomID), ["!u1", "!u2", "!u3", "!u4", "!u5"])
        XCTAssertEqual(unlockedMenu.unreadChats.first?.title.count, 40)
        XCTAssertEqual(unlockedMenu.unreadChats.first?.title.last, "…")
        XCTAssertEqual(unlockedMenu.recentChats.map(\.roomID), ["!r1", "!r2", "!r3", "!r4", "!r5"])
    }

    func testMenuBarIconPreferenceAndDockBadgeModes() throws {
        let suiteName = "courier.test.dock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = DockAndTrayPreferences(defaults: defaults)
        XCTAssertEqual(prefs.badgeMode, .unreadChats)
        XCTAssertTrue(prefs.showMenuBarIcon)

        prefs.badgeMode = .allChats
        prefs.showMenuBarIcon = false

        let reloaded = DockAndTrayPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.badgeMode, .allChats)
        XCTAssertFalse(reloaded.showMenuBarIcon)
    }
}
