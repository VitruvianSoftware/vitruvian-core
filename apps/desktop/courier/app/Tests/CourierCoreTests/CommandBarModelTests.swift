// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class CommandBarModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "CommandBarModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
        if let suiteName {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
    }

    func testRankingPrefersExactAndPrefixMatchesAndBoostsRecentCommandsOnEmptyQuery() {
        var archiveCount = 0
        var archiveAllCount = 0
        var settingsCount = 0

        let commands: [CourierCommand] = [
            CourierCommand(
                id: "inbox.archiveAll",
                title: "Archive all chats",
                category: .inbox,
                keywords: ["sweep", "clean"],
                shortcut: nil,
                run: { archiveAllCount += 1 }
            ),
            CourierCommand(
                id: "chat.archive",
                title: "Archive",
                category: .chat,
                keywords: ["done", "archive chat"],
                shortcut: "E",
                run: { archiveCount += 1 }
            ),
            CourierCommand(
                id: "settings.open",
                title: "Settings",
                category: .settings,
                keywords: ["preferences"],
                shortcut: "⌘,",
                run: { settingsCount += 1 }
            ),
        ]

        let model = CommandBarModel(defaults: defaults, commandsProvider: { commands })
        model.open()
        XCTAssertTrue(model.isPresented)

        // Exact title match "Archive" must rank above prefix match "Archive all chats".
        model.query = "archive"
        XCTAssertEqual(model.displayedCommands.first?.id, "chat.archive")
        XCTAssertEqual(model.displayedCommands.map(\.id), ["chat.archive", "inbox.archiveAll"])

        // Executing "Settings" records it in recentCommandIDs (persisted in UserDefaults, max 8).
        model.query = "settings"
        model.executeSelected()
        XCTAssertEqual(settingsCount, 1)
        XCTAssertFalse(model.isPresented, "Executing a leaf command closes the command bar")
        XCTAssertEqual(model.recentCommandIDs.first, "settings.open")

        // Re-opening with an empty query boosts recent commands to the top of displayedCommands.
        model.open()
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.displayedCommands.first?.id, "settings.open")
        _ = (archiveCount, archiveAllCount)
    }

    func testNestedSubCommandsDrillDownAndBackspaceOnEmptyQueryPopsToParent() {
        var selectedFilter: String?
        let filterCommand = CourierCommand(
            id: "inbox.filterChats",
            title: "Filter Chats",
            category: .inbox,
            keywords: ["filter", "unread", "dms"],
            shortcut: "⌘P",
            children: [
                CourierCommand(
                    id: "inbox.filter.unread",
                    title: "Unread",
                    category: .inbox,
                    run: { selectedFilter = "unread" }
                ),
                CourierCommand(
                    id: "inbox.filter.dms",
                    title: "Direct Messages (DMs)",
                    category: .inbox,
                    run: { selectedFilter = "dms" }
                ),
            ],
            run: {}
        )

        let model = CommandBarModel(defaults: defaults, commandsProvider: { [filterCommand] })
        model.open()
        XCTAssertTrue(model.breadcrumb.isEmpty)
        XCTAssertEqual(model.displayedCommands.map(\.id), ["inbox.filterChats"])

        // Executing a parent command with children pushes onto breadcrumb and clears query.
        model.query = "filter"
        model.executeSelected()
        XCTAssertTrue(model.isPresented, "Drilling into sub-commands keeps the command bar open")
        XCTAssertEqual(model.breadcrumb.map(\.id), ["inbox.filterChats"])
        XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.displayedCommands.map(\.id), ["inbox.filter.unread", "inbox.filter.dms"])

        // Backspace on empty query pops back to parent level.
        let popped = model.handleBackspaceOnEmptyQuery()
        XCTAssertTrue(popped)
        XCTAssertTrue(model.breadcrumb.isEmpty)
        XCTAssertEqual(model.displayedCommands.map(\.id), ["inbox.filterChats"])

        // Drill in again, filter to "dms", and execute child command.
        model.executeSelected()
        model.query = "dms"
        XCTAssertEqual(model.displayedCommands.map(\.id), ["inbox.filter.dms"])
        model.executeSelected()
        XCTAssertEqual(selectedFilter, "dms")
        XCTAssertFalse(model.isPresented)
    }

    func testOpenRecentlyViewedChatsFiltersAndSelectsRoomInInbox() {
        var openedRoomID: String?
        let recentRows = [
            InboxRow(
                roomID: "!r1:courier.local",
                network: "whatsapp",
                name: "Alice Johnson",
                avatarPath: "",
                isDirect: true,
                lastTS: 2000,
                preview: "See you soon",
                previewKind: .text,
                previewMine: false,
                unread: 1,
                muted: false
            ),
            InboxRow(
                roomID: "!r2:courier.local",
                network: "signal",
                name: "Design Critique",
                avatarPath: "",
                isDirect: false,
                lastTS: 1000,
                preview: "Updated mocks",
                previewKind: .text,
                previewMine: false,
                unread: 0,
                muted: false
            ),
        ]

        let model = CommandBarModel(
            defaults: defaults,
            commandsProvider: { [] },
            recentChatsProvider: { recentRows },
            onSelectRecentChat: { roomID in openedRoomID = roomID }
        )
        model.openInRecentChatsMode()
        XCTAssertTrue(model.isPresented)
        XCTAssertEqual(model.mode, .recentChats)
        XCTAssertEqual(model.displayedRecentChats.map(\.roomID), ["!r1:courier.local", "!r2:courier.local"])

        model.query = "design"
        XCTAssertEqual(model.displayedRecentChats.map(\.roomID), ["!r2:courier.local"])

        model.executeSelected()
        XCTAssertEqual(openedRoomID, "!r2:courier.local")
        XCTAssertFalse(model.isPresented)
    }

    func testDestructiveCommandSetsPendingConfirmationBeforeRunningAction() {
        var didArchiveAll = false
        let destructive = CourierCommand(
            id: "inbox.archiveAll",
            title: "Archive all chats",
            category: .inbox,
            confirmation: "Archive all chats in your inbox?",
            run: { didArchiveAll = true }
        )

        let model = CommandBarModel(defaults: defaults, commandsProvider: { [destructive] })
        model.open()
        model.executeSelected()

        XCTAssertFalse(didArchiveAll, "Destructive command must not run before confirmation")
        XCTAssertEqual(model.pendingConfirmation?.id, "inbox.archiveAll")

        model.confirmPendingCommand()
        XCTAssertTrue(didArchiveAll, "Confirming must execute the destructive command")
        XCTAssertNil(model.pendingConfirmation)
        XCTAssertFalse(model.isPresented)
    }

    func testAppLockDismissesCommandBarAndRefusesOpenOrExecute() {
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: FakeBiometricAuthService(available: true, result: .success(true))
        )
        var ran = false
        let cmd = CourierCommand(
            id: "chat.archive",
            title: "Archive",
            category: .chat,
            run: { ran = true }
        )
        let model = CommandBarModel(
            defaults: defaults,
            lifecycle: lifecycle,
            commandsProvider: { [cmd] }
        )
        model.open()
        XCTAssertTrue(model.isPresented)

        lifecycle.lockNow()
        XCTAssertFalse(model.isPresented, "Locking the app must immediately dismiss the command bar")

        model.open()
        XCTAssertFalse(model.isPresented, "CommandBarModel.open must be a no-op while locked")
        model.executeSelected()
        XCTAssertFalse(ran, "CommandBarModel.executeSelected must be a no-op while locked")
    }

    func testSearchPlaceholderForEveryDrillableCommandHasNoDoubledVerbOrEllipsis() async throws {
        let h = try await startInbox(rooms: [room("!a", ts: 100)], autoRelease: true)
        defer {
            Task { await h.app.stop() }
            h.cleanUp()
        }
        let spaces = SpacesModel(appModel: h.app, inbox: h.inbox, sleep: { _ in })
        let appearance = AppearancePreferences(defaults: defaults)
        let all = CommandSet.all(inbox: h.inbox, spaces: spaces, appearance: appearance)

        let drillable = all.filter { !$0.children.isEmpty }
        let drillableIDs = Set(drillable.map { $0.id })
        let expectedDrillableIDs: Set<String> = [
            "Filter Chats",
            "chat.remindLater",
            "chat.label",
            "chat.disappearingMessages",
            "nav.goToSpace",
            "appearance.setTheme",
        ]
        XCTAssertEqual(
            drillableIDs,
            expectedDrillableIDs,
            "All 6 multi-step commands must be drillable"
        )

        let model = CommandBarModel(defaults: defaults, commandsProvider: { all })
        model.open()
        XCTAssertEqual(model.searchPlaceholder, "Type a command or search…")

        model.openInRecentChatsMode()
        XCTAssertEqual(model.searchPlaceholder, "Filter recent chats…")

        let expectedPlaceholders: [String: String] = [
            "Filter Chats": "Filter Chats…",
            "chat.remindLater": "Remind Later…",
            "chat.label": "Label…",
            "chat.disappearingMessages": "Disappearing Messages…",
            "nav.goToSpace": "Go to Space…",
            "appearance.setTheme": "Set Theme…",
        ]

        for cmd in drillable {
            model.open()
            let runnable = CourierCommand(
                id: cmd.id,
                title: cmd.title,
                category: cmd.category,
                icon: cmd.icon,
                shortcut: cmd.shortcut,
                children: cmd.children,
                isEnabled: { true },
                run: cmd.run
            )
            model.execute(runnable)
            XCTAssertEqual(model.breadcrumb.last?.id, Optional(cmd.id))
            let placeholder = model.searchPlaceholder
            XCTAssertEqual(
                placeholder,
                expectedPlaceholders[cmd.id],
                "Unexpected placeholder for drillable command '\(cmd.title)'"
            )
            XCTAssertFalse(placeholder.contains("Filter Filter"), "Doubled verb in '\(placeholder)'")
            XCTAssertFalse(placeholder.contains("Filter Remind"), "Doubled verb in '\(placeholder)'")
            XCTAssertFalse(placeholder.contains("Filter Set"), "Doubled verb in '\(placeholder)'")
            XCTAssertFalse(placeholder.contains("Filter Go"), "Doubled verb in '\(placeholder)'")
            XCTAssertFalse(placeholder.contains("Filter Label"), "Doubled verb in '\(placeholder)'")
            XCTAssertFalse(placeholder.contains("……"), "Doubled ellipsis in '\(placeholder)'")
        }
    }
}
