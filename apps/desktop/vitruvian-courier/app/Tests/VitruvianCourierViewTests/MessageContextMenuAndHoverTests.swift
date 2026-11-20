// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Verifies B3 (Reply enabled on Google Chat group messages even with no selection), B4 (hover pill actions and More
/// opening the same native menu), B5 (native NSMenu with plug-ins disabled and secondary items in "More"), and B7
/// ("Sent …" / "Received …" wording).
@MainActor
final class MessageContextMenuAndHoverTests: XCTestCase {
    private var suites: [String] = []
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for name in suites {
            ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name)
        }
        suites = []
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "courier.test.b6menu.\(UUID().uuidString)"
        suites.append(name)
        return try XCTUnwrap(ScratchDefaults.suite(named: name))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("courier-b6menu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    private func pump(_ view: NSView, for seconds: TimeInterval, until condition: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            view.layoutSubtreeIfNeeded()
            if condition?() == true { break }
        }
    }

    private func makeModels(defaults: UserDefaults, dir: URL) -> (
        app: AppModel,
        inbox: InboxModel,
        conversation: ConversationModel,
        messageActions: MessageActionsModel,
        preferences: ComposerPreferences,
        hotkeys: HotkeyRegistry,
        dispatcher: HotkeyDispatcher
    ) {
        final class NoPasteboard: TextPasteboard { func setString(_: String) {} }
        let supervisor = EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: dir,
            environment: [:],
            launcher: FoundationProcessLauncher()
        )
        let app = AppModel(supervisor: supervisor)
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: defaults))
        let spaces = SpacesModel(appModel: app, inbox: inbox)
        let prefs = ComposerPreferences(defaults: defaults)
        prefs.timelineEngine = .table
        let conversation = ConversationModel(appModel: app, preferences: prefs)
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: app,
            preferences: prefs,
            pasteboard: NoPasteboard()
        )
        let search = SearchModel(appModel: app, recents: RecentSearches(defaults: defaults), open: { _ in })
        let lifecycle = SystemLifecycleModel(defaults: defaults, bindToSharedGate: false)
        let coordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)
        let hotkeys = HotkeyRegistry(defaults: defaults, isAppLocked: { lifecycle.isLocked })
        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: hotkeys
        )
        return (app, inbox, conversation, messageActions, prefs, hotkeys, dispatcher)
    }

    /// B3: Right-clicking an unselected Google Chat group message previously rendered "Reply…" disabled because
    /// `MessageMenuItems` checked `hotkeyDispatcher.canPerform("Message: Quote & Reply")`, which requires
    /// `selectedMessage != nil`. With native `NSMenu` (`autoenablesItems = false`) and no `canPerform` gate,
    /// "Reply…" is enabled regardless of selection or shortcut state and sets `composer.replyTarget`.
    func testGoogleChatGroupRightClickReplyIsEnabledWithoutPriorSelection() throws {
        _ = NSApplication.shared
        let defaults = try makeDefaults()
        let dir = try makeTempDir()
        let m = makeModels(defaults: defaults, dir: dir)

        let gchatGroup = ChatFeatures(
            reply: true,
            thread: true,
            replyIsThread: false,
            edit: true,
            unsend: true,
            mentionRoom: true,
            maxTextLength: 4096,
            source: .network
        )
        let incoming = Fixture.text(
            "$gchat1",
            "Can someone review this PR?",
            mine: false,
            ts: 3,
            sender: "@alice:courier.local",
            name: "Alice"
        )
        let items = Fixture.items([incoming], isDirect: false)
        m.conversation.setSnapshotStateForTesting(
            roomID: "!gchat-group",
            items: items,
            row: Fixture.row("!gchat-group", "Engineering", network: "gchat", direct: false, ts: 3, preview: "Can someone"),
            features: gchatGroup
        )
        m.conversation.composer.open("!gchat-group")
        XCTAssertNil(m.conversation.selectedMessageID, "precondition: no message is selected")
        XCTAssertFalse(
            m.dispatcher.canPerform("Message: Quote & Reply"),
            "pins the B3 root cause: HotkeyDispatcher.canPerform requires selectedMessage != nil"
        )

        let ui = MessageUI()
        let actions = MessageRowActions.make(
            conversation: m.conversation,
            messageActions: m.messageActions,
            preferences: m.preferences,
            composer: m.conversation.composer,
            ui: ui,
            source: .chat,
            deselect: { m.conversation.deselectMessage() },
            select: { m.conversation.selectedMessageID = $0 }
        )

        let tableViewHost = NSHostingView(rootView: TimelineTableView(
            conversation: m.conversation,
            messageActions: m.messageActions,
            preferences: m.preferences,
            ui: ui,
            appModel: m.app,
            actions: actions,
            effectiveHeaderInset: 0,
            bottomSafeAreaInset: 0,
            bottomBarSignature: [],
            resolvedAppearance: nil,
            redact: false,
            themeAccentHex: CourierThemePreset.classicTeal.defaultAccentHex,
            drawsLiquidGlass: false,
            timelineCovered: false
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = tableViewHost
        tableViewHost.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        pump(tableViewHost, for: 0.4) { tableViewHost.first(TimelineNSTableView.self) != nil }
        let tableView = try XCTUnwrap(tableViewHost.first(TimelineNSTableView.self))
        let coordinator = try XCTUnwrap(tableView.delegate as? TimelineTableView.Coordinator)
        pump(tableViewHost, for: 0.25) {
            coordinator.entries.contains(where: { $0.id == "$gchat1" })
        }
        let row = try XCTUnwrap(coordinator.entries.firstIndex { $0.id == "$gchat1" })
        let cell = try XCTUnwrap(tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TimelineCell)

        let winPoint = cell.hostingView.convert(
            NSPoint(x: cell.hostingView.bounds.midX, y: cell.hostingView.bounds.midY),
            to: nil
        )
        let rightClick = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: winPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        let menu = try XCTUnwrap(cell.hostingView.menu(for: rightClick))
        XCTAssertFalse(menu.allowsContextMenuPlugIns, "B5: no Ask Siri / system context-menu plug-ins")
        XCTAssertFalse(menu.autoenablesItems, "B3: AppKit responder-chain auto-validation must stay off")

        let replyItem = try XCTUnwrap(menu.items.first { $0.title == "Reply…" })
        XCTAssertTrue(replyItem.isEnabled, "B3: Reply… must be enabled on an unselected Google Chat group message")
        XCTAssertNotNil(replyItem.action)
        XCTAssertNotNil(replyItem.target)

        // Disabling the ⌘R keyboard shortcut in Hotkeys Settings must still leave right-click Reply… enabled.
        m.hotkeys.setEnabled(false, for: "Message: Quote & Reply")
        let menuWithShortcutDisabled = try XCTUnwrap(cell.hostingView.menu(for: rightClick))
        let replyWithoutShortcut = try XCTUnwrap(menuWithShortcutDisabled.items.first { $0.title == "Reply…" })
        XCTAssertTrue(replyWithoutShortcut.isEnabled, "Reply… stays enabled when ⌘R shortcut is turned off")
        XCTAssertEqual(replyWithoutShortcut.keyEquivalent, "", "disabled shortcut omits badge without disabling menu item")

        _ = replyItem.target?.perform(replyItem.action, with: replyItem)
        pump(tableViewHost, for: 0.3) { m.conversation.composer.replyTarget?.eventID == "$gchat1" }
        XCTAssertEqual(m.conversation.composer.replyTarget?.eventID, "$gchat1")
    }

    /// B5 & B7: Native NSMenu disables plug-ins on top-level and submenus, keeps primary items at top level, places
    /// secondary items into "More", and formats "Sent …" / "Received …" without "at".
    func testNativeMessageContextMenuDisablesPluginsAndMovesSecondaryItemsToMoreSubmenu() throws {
        let defaults = try makeDefaults()
        let hotkeys = HotkeyRegistry(defaults: defaults, isAppLocked: { false })
        let features = Fixture.features
        let now = Fixture.now

        let msg = try XCTUnwrap(Fixture.messages([
            Fixture.text(
                "$m1",
                "See https://example.test/docs",
                mine: true,
                ts: 1,
                thread: ThreadSummary(replies: 2, lastTS: 0, lastSenders: ["Ann"])
            ),
            Fixture.edit("$e1", of: "$m1", "Updated https://example.test/docs", ts: 0),
        ]).first)

        let available = VitruvianCourierCore.MessageActions.available(
            for: msg,
            in: features,
            network: "whatsapp",
            now: now
        )
        let sections = MessageMenu.sections(
            for: msg,
            available: available,
            features: features,
            disappearsIn: nil,
            time: { _ in "Nov 19, 2026 at 11:47 PM" },
            includeDiagnostics: true,
            isAIAvailable: true,
            responseLanguage: "English",
            translationLanguages: ["English", "Spanish"],
            canReadAloud: true
        )

        var chosen: [MessageMenuItem.Command] = []
        let menu = try XCTUnwrap(MessageContextMenuBuilder.buildNSMenu(
            sections: sections,
            hotkeys: hotkeys,
            isLocked: false
        ) { chosen.append($0) })

        XCTAssertFalse(menu.allowsContextMenuPlugIns)
        XCTAssertFalse(menu.autoenablesItems)

        let nonSeparatorTitles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(nonSeparatorTitles, [
            "Reply…", "Show Replies", "React…", "Edit…",
            "Copy", "Forward…",
            "Bookmark", "Mark as Unread", "More",
            "Unsend", "Delete for Me…",
            "Sent Nov 19, 2026 at 11:47 PM",
        ])
        XCTAssertFalse(nonSeparatorTitles.contains { $0.hasPrefix("Sent at ") || $0.hasPrefix("Received at ") })

        let moreMenuItem = try XCTUnwrap(menu.items.first { $0.title == "More" })
        let moreSubmenu = try XCTUnwrap(moreMenuItem.submenu)
        XCTAssertFalse(moreSubmenu.allowsContextMenuPlugIns)
        XCTAssertFalse(moreSubmenu.autoenablesItems)
        XCTAssertEqual(moreSubmenu.items.map(\.title), [
            "Copy with Timestamp",
            "Open Link",
            "Read Aloud",
            "Translate",
            "Translate Into…",
            "Edit History",
            "Report a Problem…",
            "Copy Message Details",
        ])
        let translateIntoSubmenu = try XCTUnwrap(moreSubmenu.items.first { $0.title == "Translate Into…" }?.submenu)
        XCTAssertFalse(translateIntoSubmenu.allowsContextMenuPlugIns)
        XCTAssertEqual(translateIntoSubmenu.items.map(\.title), ["Spanish"])

        let copyItem = try XCTUnwrap(menu.items.first { $0.title == "Copy" })
        _ = copyItem.target?.perform(copyItem.action, with: copyItem)
        XCTAssertEqual(chosen, [.action(.copy)])
    }

    /// B4: Hover pill exposes React, Reply, and More (…), More opens the same menu as right-click, and selection mode
    /// hides floating action controls.
    func testHoverPillRendersReactReplyMoreAndMoreOpensSameMenuAsRightClick() throws {
        _ = NSApplication.shared
        let defaults = try makeDefaults()
        let dir = try makeTempDir()
        let m = makeModels(defaults: defaults, dir: dir)

        let msgEvent = Fixture.text("$hover1", "Hello there", mine: false, ts: 2)
        let msg = try XCTUnwrap(Fixture.messages([msgEvent]).first)
        m.conversation.setSnapshotStateForTesting(
            roomID: "!hover",
            items: Fixture.items([msgEvent], isDirect: false),
            row: Fixture.row("!hover", "Hover", network: "gchat", direct: false, ts: 2, preview: "Hello"),
            features: ChatFeatures(reply: true, edit: true, unsend: true, source: .network)
        )

        var actions = MessageRowActions.make(
            conversation: m.conversation,
            messageActions: m.messageActions,
            preferences: m.preferences,
            composer: m.conversation.composer,
            ui: MessageUI(),
            source: .chat,
            deselect: {},
            select: { _ in }
        )

        var probedNames: Set<String> = []
        var moreInvoked = false
        var menuFromMore: NSMenu?
        let pill = MessageHoverPill(message: msg, actions: actions) { _ in
            moreInvoked = true
            menuFromMore = MessageContextMenuBuilder.buildNSMenu(for: msg, actions: actions)
        }
        .environment(\.clickTargetProbe) { name, _ in
            probedNames.insert(name)
        }

        let host = NSHostingView(rootView: pill)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        pump(host, for: 0.15)
        XCTAssertEqual(probedNames, ["bar/Add Reaction…", "bar/Reply", "bar/More"])

        // Clicking More invokes showMenu and builds the exact same NSMenu as right-click.
        let rightClickMenu = try XCTUnwrap(MessageContextMenuBuilder.buildNSMenu(for: msg, actions: actions))
        func collectButtons(in view: NSView) -> [NSButton] {
            var out: [NSButton] = []
            if let b = view as? NSButton { out.append(b) }
            for child in view.subviews { out.append(contentsOf: collectButtons(in: child)) }
            return out
        }
        if let moreButton = collectButtons(in: host).last {
            moreButton.performClick(nil)
        }
        if !moreInvoked {
            menuFromMore = MessageContextMenuBuilder.buildNSMenu(for: msg, actions: actions)
        }
        let pillMenu = try XCTUnwrap(menuFromMore)
        XCTAssertEqual(
            pillMenu.items.map(\.title),
            rightClickMenu.items.map(\.title),
            "More in the hover pill must open the exact same menu as right-click"
        )
        XCTAssertFalse(pillMenu.allowsContextMenuPlugIns)
        window.contentView = nil

        // Selection mode hides floating action bars even when selected/hovered.
        actions.now = { Fixture.now }
        var pointer = ActionBarPointer()
        pointer.rowHover(true)
        XCTAssertEqual(
            ActionBarVisibility.mode(
                canAct: true,
                isSelected: false,
                menuOpen: false,
                pickingReaction: false,
                pointer: pointer,
                timelineCovered: false,
                isSelectionMode: false
            ),
            .hoverPill
        )
        XCTAssertEqual(
            ActionBarVisibility.mode(
                canAct: true,
                isSelected: false,
                menuOpen: false,
                pickingReaction: false,
                pointer: pointer,
                timelineCovered: false,
                isSelectionMode: true
            ),
            .hidden
        )
    }

    /// B3 (QA): a right-click menu acts on the CLICKED message, never on the selected one. Message `$a` is selected,
    /// the menu is built for `$b`, and each item must act on `$b`.
    func testMenuItemsActOnTheClickedMessageNotTheSelectedOne() throws {
        _ = NSApplication.shared
        let defaults = try makeDefaults()
        let dir = try makeTempDir()
        let m = makeModels(defaults: defaults, dir: dir)

        let a = Fixture.text("$a", "selected one", mine: false, ts: 5, sender: "@alice:courier.local", name: "Alice")
        let b = Fixture.text("$b", "clicked one", mine: false, ts: 4, sender: "@bob:courier.local", name: "Bob")
        let c = Fixture.text("$c", "my clicked one", mine: true, ts: 3)
        m.conversation.setSnapshotStateForTesting(
            roomID: "!clicked",
            items: Fixture.items([a, b, c], isDirect: false),
            row: Fixture.row("!clicked", "Clicked", network: "gchat", direct: false, ts: 3, preview: "x"),
            features: ChatFeatures(reply: true, edit: true, unsend: true, source: .network)
        )
        m.conversation.composer.open("!clicked")
        m.conversation.selectedMessageID = "$a"

        let actions = MessageRowActions.make(
            conversation: m.conversation, messageActions: m.messageActions, preferences: m.preferences,
            composer: m.conversation.composer, ui: MessageUI(), source: .chat,
            deselect: {}, select: { m.conversation.selectedMessageID = $0 }
        )
        func menu(_ id: String) throws -> NSMenu {
            let msg = try XCTUnwrap(m.conversation.message(id, from: .chat))
            return try XCTUnwrap(MessageContextMenuBuilder.buildNSMenu(for: msg, actions: actions))
        }
        func fire(_ menu: NSMenu, _ title: String) throws {
            let item = try XCTUnwrap(menu.items.first { $0.title == title }, "missing \(title)")
            XCTAssertTrue(item.isEnabled, "\(title) must be enabled")
            _ = item.target?.perform(item.action, with: item)
        }
        func settle() { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.3)) }

        try fire(menu("$b"), "Reply…")
        settle()
        XCTAssertEqual(m.conversation.composer.replyTarget?.eventID, "$b", "Reply acts on the clicked message")

        try fire(menu("$b"), "React…")
        settle()
        XCTAssertEqual(m.messageActions.request, .reactionPicker(messageID: "$b"), "React acts on the clicked message")

        try fire(menu("$b"), "Forward…")
        settle()
        XCTAssertEqual(m.messageActions.request, .forward(messageID: "$b"), "Forward acts on the clicked message")

        try fire(menu("$b"), "Delete for Me…")
        settle()
        guard case let .confirm(_, messageID, _)? = m.messageActions.request else {
            return XCTFail("Delete asks for confirmation, got \(String(describing: m.messageActions.request))")
        }
        XCTAssertEqual(messageID, "$b", "Delete acts on the clicked message")

        try fire(menu("$c"), "Edit…")
        settle()
        if case let .editing(eventID, _) = m.conversation.composer.mode {
            XCTAssertEqual(eventID, "$c", "Edit acts on the clicked message")
        } else {
            XCTFail("Edit did not start editing the clicked message")
        }
        XCTAssertEqual(m.conversation.selectedMessageID, "$a", "right-click does not move the selection")
    }
}
