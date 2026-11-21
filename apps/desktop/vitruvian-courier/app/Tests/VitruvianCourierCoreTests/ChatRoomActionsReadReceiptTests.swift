// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Edit Chat… and Report as Spam… from the inbox's menu must never open the chat they are for: opening it marks it
/// read, and that sends the people in it a read receipt (never to be sent to a stranger being reported).
@MainActor
final class ChatRoomActionsReadReceiptTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    private func start() async throws -> ConversationHarness {
        let events = (1 ... 3).map { textEvent(id: "$\($0)", room: "!stranger", at: Int64($0)) }
        let other = (1 ... 3).map { textEvent(id: "$o\($0)", room: "!open", at: Int64($0)) }
        let h = try await startConversation(["!stranger": events, "!open": other])
        harnesses.append(h)
        return h
    }

    private func marked(_ h: ConversationHarness) -> [String] {
        h.server.receivedParams("room.markRead").compactMap { $0["room_id"] as? String }
    }

    func testReportAsSpamOnAnUnreadChatWithNoChatOpenSendsNoReadReceipt() async throws {
        let h = try await start()
        await ChatRoomActions.reportSpam(roomID: "!stranger", conversation: h.conversation)
        XCTAssertEqual(h.conversation.activeReportSpamDraft?.roomID, "!stranger", "the sheet is up for that chat")
        XCTAssertNil(h.app.selectedRoomID, "the chat was not opened for it")
        XCTAssertNil(h.conversation.roomID)
        XCTAssertEqual(h.conversation.readsSent, 0)
        XCTAssertEqual(marked(h), [], "nothing told the engine, so nothing told the stranger, that it was read")
    }

    func testEditChatOnAnUnreadChatWithNoChatOpenSendsNoReadReceipt() async throws {
        let h = try await start()
        await ChatRoomActions.editChat(roomID: "!stranger", conversation: h.conversation)
        XCTAssertEqual(h.conversation.activeEditGroupDraft?.roomID, "!stranger")
        XCTAssertNil(h.app.selectedRoomID)
        XCTAssertEqual(h.conversation.readsSent, 0)
        XCTAssertEqual(marked(h), [])
    }

    func testBothSheetsLeaveAnotherOpenChatOpenAndSendNoReceiptForTheOneRightClicked() async throws {
        let h = try await start()
        try await h.open("!open")
        let readsBefore = h.conversation.readsSent

        await ChatRoomActions.reportSpam(roomID: "!stranger", conversation: h.conversation)
        XCTAssertEqual(h.conversation.activeReportSpamDraft?.roomID, "!stranger")
        h.conversation.activeReportSpamDraft = nil
        await ChatRoomActions.editChat(roomID: "!stranger", conversation: h.conversation)
        XCTAssertEqual(h.conversation.activeEditGroupDraft?.roomID, "!stranger")

        XCTAssertEqual(h.app.selectedRoomID, "!open", "the open chat stays open")
        XCTAssertEqual(h.conversation.roomID, "!open")
        XCTAssertEqual(h.conversation.readsSent, readsBefore, "no read sent by either sheet")
        XCTAssertFalse(marked(h).contains("!stranger"), "the right-clicked chat was never marked read")
    }
}
