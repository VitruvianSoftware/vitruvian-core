// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// With "Show pinned chats as full rows" (Beeper's "Use regular style for pinned chats"), a pinned chat's row can be
/// dragged to reorder the pins, and no other row can. This opens the chat list in a window and asks the list's own
/// table which rows it would start a drag from: the hookup a person checks by dragging, without synthesized mouse
/// input (which a background Mac doesn't deliver reliably).
@MainActor
final class PinnedRowDragTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.pinned-row-drag.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func pinned(_ row: InboxRow) -> InboxRow {
        var row = row
        row.pinned = true
        return row
    }

    /// Opens the list with two pinned chats and one other, and returns its window and table.
    private func openList(fullRows: Bool) throws -> (NSWindow, NSOutlineView) {
        _ = NSApplication.shared
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-pinned-row-drag"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let store = defaults()
        let inboxPreferences = InboxPreferences(defaults: store)
        inboxPreferences.regularPinnedRows = fullRows
        let composerPreferences = ComposerPreferences(defaults: store)
        let inbox = InboxModel(appModel: app, preferences: inboxPreferences)
        let lifecycle = SystemLifecycleModel(loginItemService: SnapshotLoginItemService(),
                                             biometricService: SnapshotBiometricService(), defaults: store)
        let spaces = SpacesModel(appModel: app, inbox: inbox, lifecycle: lifecycle)
        spaces.setSpacesForTesting([Space(spaceID: "inbox", kind: .builtin, title: "Inbox")])
        inbox.setSnapshotRowsForTesting([
            pinned(Fixture.row("!p1", "Family", direct: false, ts: 5, preview: "I'm in")),
            pinned(Fixture.row("!p2", "Eli Example", ts: 9, preview: "Got a minute?")),
            Fixture.row("!r3", "Book club", direct: false, ts: 40, preview: "Chapter 4 next"),
        ])
        let list = InboxList(inbox: inbox, spaces: spaces, preferences: inboxPreferences,
                             composerPreferences: composerPreferences, ui: InboxUI())
        let size = NSSize(width: 360, height: 560)
        let hosting = NSHostingView(rootView: list)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        var table: NSOutlineView?
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            hosting.layoutSubtreeIfNeeded()
            if let found = hosting.first(NSOutlineView.self), found.numberOfRows >= (fullRows ? 3 : 1) {
                table = found
                break
            }
        }
        let outline = try XCTUnwrap(table ?? hosting.first(NSOutlineView.self), "the chat list should be a table")
        return (window, outline)
    }

    /// Which of the table's rows it would start a drag from: the ones whose data source writes a reorder item.
    private func draggableRows(_ outline: NSOutlineView) -> [Int] {
        (0 ..< outline.numberOfRows).filter { index in
            guard let item = outline.item(atRow: index) else { return false }
            return outline.dataSource?.outlineView?(outline, pasteboardWriterForItem: item) != nil
        }
    }

    func testFullRowPinnedChatsCanBeDraggedAndNoOtherRowCan() throws {
        let (window, outline) = try openList(fullRows: true)
        defer { window.close() }
        XCTAssertEqual(outline.numberOfRows, 3, "both pins and the other chat should be rows")
        XCTAssertEqual(draggableRows(outline), [0, 1], "only the two pinned rows should start a reorder drag")
    }

    func testWithCompactPinsNoRowCanBeDragged() throws {
        // The pins are the strip above the list (which has its own drag); the list holds only the other chat.
        let (window, outline) = try openList(fullRows: false)
        defer { window.close() }
        XCTAssertEqual(outline.numberOfRows, 1)
        XCTAssertEqual(draggableRows(outline), [], "with compact pins no list row should drag")
    }
}
