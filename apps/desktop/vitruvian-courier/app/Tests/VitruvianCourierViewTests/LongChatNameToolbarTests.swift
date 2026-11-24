// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// With Liquid Glass the chat's picture and name are a toolbar item. A name too long for the toolbar used to make the
/// item wider than the window had room for, and the toolbar then moved it, and the Chat Info button with it, into its
/// ">>" overflow menu: the chat had no header at all. The name truncates instead, as Beeper's does, so the header and
/// the ⓘ button always stay on the toolbar.
///
/// This opens a real window at the app's default size (`App.swift`) with the chat list beside the chat, as the app
/// lays it out, because only a real window's toolbar decides what overflows.
@MainActor
final class LongChatNameToolbarTests: XCTestCase {
    private static let sidebarWidth: CGFloat = 320
    private var suites: [String] = []
    private var window: NSWindow?

    override func setUpWithError() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("the header is in the toolbar only with Liquid Glass (macOS 26)") }
    }

    override func tearDown() {
        window?.close()
        window = nil
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
    }

    func testA200CharacterNameKeepsTheHeaderAndChatInfoOnTheToolbar() throws {
        let name = String(String(repeating: "The Extremely Long Group Name For Planning The Garden Festival ", count: 4)
            .prefix(200))
        XCTAssertEqual(name.count, 200)
        let window = try openWindow(chatName: name)
        try checkHeaderAndButtonsFit(in: window)

        // Narrower and wider again (a person resizing the window): the header follows and nothing is left in the
        // overflow menu.
        for width: CGFloat in [860, 1020, 780] {
            window.setContentSize(NSSize(width: width, height: 660))
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            try checkHeaderAndButtonsFit(in: window)
        }
    }

    private func checkHeaderAndButtonsFit(in window: NSWindow) throws {
        let chat = try chatItems(in: window)

        let overflowed = chat.filter { !$0.isVisible }
        XCTAssertTrue(overflowed.isEmpty, "the chat's toolbar items in the overflow menu: \(overflowed.map(\.id))")
        // The header (the chat's first item) starts in the chat column and stops short of its buttons; the last
        // button (Chat Info) ends inside the window.
        let header = try XCTUnwrap(chat.first?.frame, "no chat header on the toolbar")
        let lastButton = try XCTUnwrap(chat.last?.frame, "no Chat Info button on the toolbar")
        XCTAssertGreaterThanOrEqual(header.minX, Self.sidebarWidth - 1, "the header should start in the chat column")
        XCTAssertGreaterThan(header.width, ChatHeaderWidth.minimum - 1, "the header should show the picture and name")
        XCTAssertLessThan(header.maxX, lastButton.minX, "the header should end before the chat's buttons")
        XCTAssertLessThanOrEqual(lastButton.maxX, window.frame.width, "Chat Info runs past the window's edge")
    }

    /// A short name is drawn whole, not cut short by the limit the long one needs.
    func testAShortNameIsNotTruncated() throws {
        let window = try openWindow(chatName: "Book club")
        let chat = try chatItems(in: window)
        XCTAssertTrue(chat.allSatisfy(\.isVisible), "the chat's toolbar items in the overflow menu")
        let header = try XCTUnwrap(chat.first?.frame)
        XCTAssertLessThan(header.width, 250, "a short name's header should be only as wide as its name")
        // As wide as the name needs: the cap is far wider, so it changes nothing here.
        let fitting = try XCTUnwrap(chat.first?.view)
        XCTAssertEqual(header.width, fitting.fittingSize.width, accuracy: 2)
    }

    /// The cap itself: the column's room after the header's start and its buttons, never below the minimum, and
    /// none before the column is measured.
    func testTheHeaderCapIsTheRoomTheColumnLeaves() {
        XCTAssertEqual(ChatHeaderWidth.maximum(columnMinX: 0, columnMaxX: 0, headerMinX: nil, buttons: 1),
                       ChatHeaderWidth.minimum)
        // Measured: 1020-wide window, list 320 wide, header at 336, Chat Info only.
        XCTAssertEqual(ChatHeaderWidth.maximum(columnMinX: 320, columnMaxX: 1020, headerMinX: 336, buttons: 1),
                       1020 - 336 - ChatHeaderWidth.perButton - ChatHeaderWidth.slack)
        // Not yet on the toolbar, chat list hidden: starts after the traffic lights and sidebar button.
        XCTAssertEqual(ChatHeaderWidth.maximum(columnMinX: 0, columnMaxX: 800, headerMinX: nil, buttons: 2),
                       800 - ChatHeaderWidth.leadingChromeWithoutSidebar - 2 * ChatHeaderWidth.perButton
                           - ChatHeaderWidth.slack)
        XCTAssertEqual(ChatHeaderWidth.maximum(columnMinX: 320, columnMaxX: 400, headerMinX: 336, buttons: 2),
                       ChatHeaderWidth.minimum)
    }

    // MARK: - Window

    private func openWindow(chatName: String) throws -> NSWindow {
        _ = NSApplication.shared
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-long-name"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let suite = "courier.long-name.\(UUID().uuidString)"
        suites.append(suite)
        let store = try XCTUnwrap(ScratchDefaults.suite(named: suite))
        let inboxPreferences = InboxPreferences(defaults: store)
        let composerPreferences = ComposerPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: inboxPreferences)
        let lifecycle = SystemLifecycleModel(loginItemService: SnapshotLoginItemService(),
                                             biometricService: SnapshotBiometricService(), defaults: store)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        spaces.setSpacesForTesting([Space(spaceID: "inbox", kind: .builtin, title: "Inbox")])
        let row = Fixture.row("!long", chatName, network: "slack", direct: false, ts: 5, preview: "See you there")
        inbox.setSnapshotRowsForTesting([row, Fixture.row("!r2", "Alice Example", ts: 9, preview: "Thanks!")])
        let conversation = ConversationModel(appModel: app, preferences: composerPreferences)
        conversation.setSnapshotStateForTesting(
            roomID: "!long",
            items: Fixture.items([Fixture.text("$1", "Who is bringing the scones?", mine: false, ts: 30)],
                                 isDirect: false),
            row: row, features: Fixture.features)
        final class NoPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let messageActions = MessageActionsModel(conversation: conversation, appModel: app,
                                                 preferences: composerPreferences, pasteboard: NoPasteboard())

        let root = NavigationSplitView {
            InboxList(inbox: inbox, spaces: spaces, preferences: inboxPreferences,
                      composerPreferences: composerPreferences, ui: InboxUI())
                .navigationSplitViewColumnWidth(min: 260, ideal: Self.sidebarWidth, max: 480)
        } detail: {
            ConversationView(conversation: conversation, composer: conversation.composer, inbox: inbox,
                             messageActions: messageActions, scheduled: ScheduledModel(appModel: app),
                             preferences: composerPreferences, thread: conversation.thread,
                             focus: MessageFocus(), appModel: app)
        }
        .environment(\.liquidGlass, true)

        let hosting = NSHostingController(rootView: root)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        // The app's default window size (`App.swift`).
        let size = NSSize(width: 1020, height: 660)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentViewController = hosting
        window.setContentSize(size)
        window.orderFrontRegardless()
        self.window = window
        // The chat column is measured, then the toolbar lays its items out again.
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        return window
    }

    private struct ChatItem {
        let id: String
        let isVisible: Bool
        let view: NSView?
        var frame: NSRect { view.map { $0.convert($0.bounds, to: nil) } ?? .zero }
    }

    /// The chat's own toolbar items (its header, then its buttons), in order: the items after the split view's
    /// separator, spaces left out. The chat list's items come before it.
    private func chatItems(in window: NSWindow) throws -> [ChatItem] {
        let toolbar = try XCTUnwrap(window.toolbar, "the views' toolbar items should give the window a toolbar")
        let separator = try XCTUnwrap(
            toolbar.items.lastIndex { $0.itemIdentifier.rawValue.contains("splitViewSeparator") },
            "no split view separator in the toolbar: \(toolbar.items.map(\.itemIdentifier.rawValue))")
        let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
        let items = toolbar.items[(separator + 1)...]
            .filter { $0.itemIdentifier != .space && $0.itemIdentifier != .flexibleSpace }
            .map { ChatItem(id: $0.itemIdentifier.rawValue, isVisible: visible.contains($0.itemIdentifier), view: $0.view) }
        XCTAssertGreaterThanOrEqual(items.count, 2, "the chat's header and Chat Info should be toolbar items")
        return items
    }
}
