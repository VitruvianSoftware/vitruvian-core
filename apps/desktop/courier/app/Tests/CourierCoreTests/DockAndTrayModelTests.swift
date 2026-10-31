// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class DockAndTrayModelTests: XCTestCase {
    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

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

        let history = ["!curr", "!u2", "!rhid", "!u6", "!lp", "!r1", "!r2", "!r3", "!r4", "!r5", "!r6"]

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

        // 2. When unlocked, capped at 5 unread (excluding lowPriority and hidden) and 5 recent (excluding currentRoomID, unreadChats, and hidden; overflow unread chats !u6 and !lp stay eligible for recentChats)
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
        XCTAssertEqual(unlockedMenu.recentChats.map(\.roomID), ["!u6", "!lp", "!r1", "!r2", "!r3"])
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

    func testExternalMenuUnlockAndTwinMenuActionsShareOneModelAction() async throws {
        let suiteName = "courier.test.dock.actions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-dock"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        let appModel = AppModel(supervisor: supervisor)
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let inbox = InboxModel(appModel: appModel, preferences: inboxPrefs)
        let bio = FakeBiometricAuthService(available: true, result: .success(false))
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: bio
        )

        var shownMainCount = 0
        var shownSettingsCount = 0
        var hiddenAppCount = 0
        var closedWindowCount = 0
        var closedAllCount = 0
        var detachedRooms: [String] = []

        let coordinator = AppMenuCoordinator(
            inbox: inbox,
            lifecycle: lifecycle,
            showMainWindow: { shownMainCount += 1 },
            showSettingsWindow: { shownSettingsCount += 1 },
            hideApp: { hiddenAppCount += 1 },
            closeKeyWindow: { closedWindowCount += 1 },
            closeAllAppWindows: { closedAllCount += 1 },
            openDetachedChat: { detachedRooms.append($0) }
        )

        // 1. Lock App via twin action (Application menu / Tray menu)
        await coordinator.lockOrUnlockApp()
        XCTAssertTrue(lifecycle.isLocked)

        // While locked, coordinator actions for Settings, New Chat, Open Chat in New Window, and View toggles must be refused without unlocking
        let lockedSpaceBarBefore = inboxPrefs.showSpaceBar
        let lockedSidebarBefore = coordinator.isSidebarVisible
        coordinator.openSettings(.accounts)
        coordinator.newChat()
        coordinator.openChatInNewWindow()
        coordinator.toggleSpaceBar()
        coordinator.toggleSidebar()
        XCTAssertEqual(coordinator.activeSettingsSection, .inbox, "must not open settings while locked")
        XCTAssertEqual(shownSettingsCount, 0, "must not present Settings window while locked")
        XCTAssertNil(inbox.startNewChatDraft, "must not start a new chat while locked")
        XCTAssertTrue(detachedRooms.isEmpty, "must not open detached chat window while locked")
        XCTAssertEqual(inboxPrefs.showSpaceBar, lockedSpaceBarBefore, "must not toggle space bar while locked")
        XCTAssertEqual(coordinator.isSidebarVisible, lockedSidebarBefore, "must not toggle sidebar while locked")
        XCTAssertTrue(lifecycle.isLocked)

        // 2. Selecting a chat from Dock menu or Tray menu while locked must authenticate first and refuse to select on failure
        let failedOpen = await coordinator.openChatFromExternalMenu("!r1")
        XCTAssertFalse(failedOpen)
        XCTAssertNil(inbox.selectedRoomID, "must not select chat when Touch ID unlock fails")
        XCTAssertTrue(lifecycle.isLocked)

        // 3. When Touch ID succeeds, selecting from Dock/Tray menu unlocks and selects the chat
        bio.result = .success(true)
        let succeededOpen = await coordinator.openChatFromExternalMenu("!r1")
        XCTAssertTrue(succeededOpen)
        XCTAssertFalse(lifecycle.isLocked)
        XCTAssertEqual(inbox.selectedRoomID, "!r1")
        XCTAssertGreaterThanOrEqual(shownMainCount, 1)

        // 4. Minimize to Menu Bar (Application menu ⌘⌥Q and Tray menu ⌘⌥Q)
        coordinator.minimizeToMenuBar()
        XCTAssertEqual(hiddenAppCount, 1)

        // 5. Settings sections from Application and Help menus (About Courier, Accounts…, Keyboard Shortcuts, Report a Problem…, Privacy & Security, Changelog)
        for section in [SettingsSection.about, .accounts, .shortcuts, .reportProblem, .privacy, .changelog] {
            coordinator.openSettings(section)
            XCTAssertEqual(coordinator.activeSettingsSection, section)
        }
        XCTAssertEqual(shownSettingsCount, 6)

        // 6. File menu actions: New Chat (⌘N), Open Chat in New Window, Close Window (⌘W), Close All (⌘⌥W)
        coordinator.newChat()
        XCTAssertNotNil(inbox.startNewChatDraft)
        coordinator.openChatInNewWindow()
        XCTAssertEqual(detachedRooms, ["!r1"])
        XCTAssertEqual(coordinator.detachedChatRoomIDs, ["!r1"])
        coordinator.closeWindow()
        XCTAssertEqual(closedWindowCount, 1)
        coordinator.closeAllWindows()
        XCTAssertEqual(closedAllCount, 1)

        // 7. View menu actions: Show/Hide Space Bar (⌘S) and Show/Hide Sidebar (⌘⌥S)
        let initialSpaceBar = inboxPrefs.showSpaceBar
        coordinator.toggleSpaceBar()
        XCTAssertEqual(inboxPrefs.showSpaceBar, !initialSpaceBar)
        XCTAssertTrue(coordinator.isSidebarVisible)
        coordinator.toggleSidebar()
        XCTAssertFalse(coordinator.isSidebarVisible)
    }
}
