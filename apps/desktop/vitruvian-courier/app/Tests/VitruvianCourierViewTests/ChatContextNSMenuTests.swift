// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// D1: a chat's right-click menu is a native NSMenu with the system's context-menu plug-ins off (no "Ask Siri"),
/// holding Copy ▸ and, where the chat's network can delete it, Delete Chat….
@MainActor
final class ChatContextNSMenuTests: XCTestCase {
    private func row(network: String = "whatsapp") -> InboxRow {
        InboxRow(roomID: "!a", network: network, name: "Sam", avatarPath: "", isDirect: true, lastTS: 1, preview: "",
                 previewKind: .text, previewMine: false, unread: 0, muted: false)
    }

    private func menu(_ context: ChatMenuContext, chosen: @escaping (ChatMenuCommand) -> Void = { _ in }) throws -> NSMenu {
        try XCTUnwrap(ChatContextNSMenu.build(ChatMenuPlan.sections(context), run: chosen))
    }

    func testTheMenuHasNoSystemPlugInsAndEverySubmenuToo() throws {
        var context = ChatMenuContext(rows: [row()])
        context.labels = [(1, "Work")]
        context.reminderPresets = ["Tomorrow"]
        let menu = try menu(context)
        XCTAssertFalse(menu.allowsContextMenuPlugIns, "no Ask Siri")
        XCTAssertFalse(menu.autoenablesItems)
        let submenus = menu.items.compactMap(\.submenu)
        XCTAssertEqual(submenus.map(\.title), ["Label", "Remind Me", "Copy"])
        for submenu in submenus {
            XCTAssertFalse(submenu.allowsContextMenuPlugIns, "\(submenu.title)")
            XCTAssertFalse(submenu.autoenablesItems)
        }
    }

    func testCopyIsASubmenuWithTheChatName() throws {
        var context = ChatMenuContext(rows: [row()])
        context.chatName = { _ in "Sam Lee" }
        var chosen: [ChatMenuCommand] = []
        let menu = try menu(context) { chosen.append($0) }
        let copy = try XCTUnwrap(menu.items.first { $0.title == "Copy" }?.submenu)
        XCTAssertEqual(copy.items.map(\.title), ["Chat Name"])
        let name = try XCTUnwrap(copy.items.first)
        XCTAssertTrue(name.isEnabled)
        _ = name.target?.perform(name.action, with: name)
        XCTAssertEqual(chosen, [.copyChatName("Sam Lee")])
    }

    func testDeleteIsInTheMenuOnlyForANetworkThatCanDelete() throws {
        var deletable = ChatFeatures.noFeatures
        deletable.canDelete = true
        var context = ChatMenuContext(rows: [row()])
        context.features = { _ in deletable }
        let withDelete = try menu(context).items.map(\.title)
        XCTAssertTrue(withDelete.contains("Delete Chat…"))
        XCTAssertEqual(withDelete.suffix(2), ["Delete Chat…", "Report as Spam…"])

        context.features = { _ in .noFeatures }
        XCTAssertFalse(try menu(context).items.map(\.title).contains("Delete Chat…"))
    }

    func testChoosingDeleteReportsTheCommandAndALabelShowsATick() throws {
        var deletable = ChatFeatures.noFeatures
        deletable.canDelete = true
        var labelled = row()
        labelled.labels = [1]
        var context = ChatMenuContext(rows: [labelled])
        context.features = { _ in deletable }
        context.labels = [(1, "Work")]
        var chosen: [ChatMenuCommand] = []
        let menu = try menu(context) { chosen.append($0) }
        let delete = try XCTUnwrap(menu.items.first { $0.title == "Delete Chat…" })
        _ = delete.target?.perform(delete.action, with: delete)
        XCTAssertEqual(chosen, [.deleteChat(roomID: "!a")])

        let work = try XCTUnwrap(menu.items.first { $0.title == "Label" }?.submenu?.items.first)
        XCTAssertEqual(work.state, .on)
    }

    func testAGreyedLineIsDisabledAndHasNoAction() throws {
        var context = ChatMenuContext(rows: [row()])
        context.lowPriorityEntitled = false
        let menu = try menu(context)
        let plan = try XCTUnwrap(menu.items.first { $0.title == "Available with a plan" })
        XCTAssertFalse(plan.isEnabled)
        XCTAssertNil(plan.action)
    }

    func testTheRightClickOverlayAsksForItsMenuOnlyOnARightClick() throws {
        var asked = 0
        let overlay = ChatNativeContextMenu.CatcherView()
        overlay.frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        overlay.makeMenu = {
            asked += 1
            return NSMenu()
        }
        // No right-click in flight: the overlay lets every other event through.
        XCTAssertNil(overlay.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertNotNil(overlay.menu(for: try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))))
        XCTAssertEqual(asked, 1)
    }
}
