// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// With Liquid Glass, every column's header in the window's toolbar, on the line of the traffic lights: the chat
/// list's name and menus, the chat's picture and name, and the thread's and Chat Info's titles each over its own pane
/// (PaneHeader.swift).
///
/// The toolbar only exists in a real window on screen, and glass only draws there, so this opens one, as the app lays
/// it out (a split view with the list and the chat, a thread and Chat Info open), and saves a picture of it as
/// `header-line-glass.png` for a person to look at: the titles' line and each pane title's edge against its pane are
/// what to check. Skipped unless `--test_env=COURIER_GLASS_SNAPSHOTS=1` on a Mac with a display, like the other glass
/// pictures (`LiquidGlassSnapshotTests`).
@MainActor
final class HeaderLineWindowTests: XCTestCase {
    private var suites: [String] = []

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["COURIER_GLASS_SNAPSHOTS"] == "1" else {
            throw XCTSkip("needs a window on screen: set COURIER_GLASS_SNAPSHOTS=1 on a Mac with a display")
        }
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass needs macOS 26") }
    }

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.header-line.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    func testEveryColumnHeaderIsOnTheToolbarLine() throws {
        let (window, conversation) = try openWindow(glass: true)
        defer { window.close() }
        try checkToolbarLine(window)

        // With the panes closed their item goes, and the chat's buttons are at the toolbar's edge again.
        conversation.setChatInfoForTesting(nil)
        conversation.thread.close()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let widest = toolbarItemViews(in: window).map(\.frame.width).max() ?? 0
        XCTAssertLessThan(widest, 300, "no panes' header should be left in the toolbar")
        try capture(window, as: "header-line-glass-chat-only.png")
    }

    /// Without glass: each column's header is a strip of the same height under the toolbar, so their titles share a
    /// line. A picture only, `header-line-plain.png`.
    func testWithoutGlassEveryStripIsTheSameHeight() throws {
        let (window, _) = try openWindow(glass: false)
        defer { window.close() }
        try capture(window, as: "header-line-plain.png")
    }

    private func openWindow(glass: Bool) throws -> (NSWindow, ConversationModel) {
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("courier-header-line"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let store = defaults()
        let inboxPreferences = InboxPreferences(defaults: store)
        let composerPreferences = ComposerPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: inboxPreferences)
        let lifecycle = SystemLifecycleModel(loginItemService: SnapshotLoginItemService(),
                                             biometricService: SnapshotBiometricService(), defaults: store)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        spaces.setSpacesForTesting([Space(spaceID: "inbox", kind: .builtin, title: "Inbox")])
        let row = Fixture.row("!r1", "#all-hands", network: "slack", direct: false, ts: 5,
                              preview: "See you there", mine: false)
        inbox.setSnapshotRowsForTesting([
            row,
            Fixture.row("!r2", "Alice Example", ts: 9, preview: "Thanks!", mine: false),
            Fixture.row("!r3", "Book club", direct: false, ts: 40, preview: "Chapter 4 next", mine: true),
        ])
        let conversation = ConversationModel(appModel: app, preferences: composerPreferences)
        let events = [
            Fixture.text("$1", "Shall we move the planning call to Thursday?", mine: false, ts: 30),
            Fixture.text("$2", "Thursday works for me.", mine: true, ts: 20),
        ]
        conversation.setSnapshotStateForTesting(roomID: "!r1", items: Fixture.items(events, isDirect: false), row: row)
        conversation.thread.setSnapshotStateForTesting(
            roomID: "!r1", rootID: "$1",
            items: Fixture.items([Fixture.text("$t1", "Yes, 10 am.", mine: false, ts: 10)], isDirect: false))
        conversation.setChatInfoForTesting(Fixture.groupChatInfoWithAdmins())
        final class NoPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let messageActions = MessageActionsModel(conversation: conversation, appModel: app,
                                                 preferences: composerPreferences, pasteboard: NoPasteboard())

        let root = NavigationSplitView {
            InboxList(inbox: inbox, spaces: spaces, preferences: inboxPreferences,
                      composerPreferences: composerPreferences, ui: InboxUI())
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            ConversationView(conversation: conversation, composer: conversation.composer, inbox: inbox,
                             messageActions: messageActions, scheduled: ScheduledModel(appModel: app),
                             preferences: composerPreferences, thread: conversation.thread,
                             focus: MessageFocus(), appModel: app)
        }
        .environment(\.liquidGlass, glass)

        let hosting = NSHostingController(rootView: root)
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1500, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1500, height: 760))
        window.makeKeyAndOrderFront(nil)
        // The panes are measured, then their toolbar item drawn at those widths.
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        return (window, conversation)
    }

    private func checkToolbarLine(_ window: NSWindow) throws {

        XCTAssertNotNil(window.toolbar, "the views' toolbar items should give the window a toolbar")
        // The panes' headers are a toolbar item (a header drawn in the toolbar's band by the pane itself showed but
        // took no clicks: the toolbar has them all): the last item, at the window's trailing edge.
        let items = toolbarItemViews(in: window)
        let panes = try XCTUnwrap(items.max { $0.frame.maxX < $1.frame.maxX }, "no toolbar items")
        XCTAssertGreaterThan(panes.frame.width, 500, "the item should span the thread and Chat Info panes")

        try capture(window, as: "header-line-glass.png")

        // A click on the panes' buttons goes to their header, not to the toolbar under it: Chat Info's close (the
        // item's last button, its glass group ending at the item's edge) and a point over the thread's half. (A
        // synthesized click doesn't press a SwiftUI button here, not even the chat's own Chat Info button in the
        // toolbar, so the click itself is checked by hand in the app.)
        let frameView = try XCTUnwrap(window.contentView?.superview)
        for point in [NSPoint(x: panes.frame.maxX - 18, y: panes.frame.midY),
                      NSPoint(x: panes.frame.minX + 60, y: panes.frame.midY)] {
            let hit = try XCTUnwrap(frameView.hitTest(point), "nothing at \(point)")
            XCTAssertTrue(String(describing: type(of: hit)).contains("ToolbarItemHostingView"),
                          "a click at \(point) goes to \(type(of: hit)), not the panes' header")
        }
    }

    private func capture(_ window: NSWindow, as name: String) throws {
        let url = Snapshot.directory.appendingPathComponent(name)
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try capture.run()
        capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0, "screencapture failed: allow Screen Recording for the test runner")
        print("header line picture: \(url.path)")
    }

    /// The window's toolbar items' views, with their frames in window coordinates.
    private func toolbarItemViews(in window: NSWindow) -> [(view: NSView, frame: NSRect)] {
        var found: [(view: NSView, frame: NSRect)] = []
        var stack: [NSView] = [window.contentView?.superview].compactMap { $0 }
        while let view = stack.popLast() {
            if String(describing: type(of: view)).contains("ToolbarItemHostingView") {
                found.append((view, view.convert(view.bounds, to: nil)))
            }
            stack.append(contentsOf: view.subviews)
        }
        return found
    }
}
