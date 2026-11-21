// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// D1: a chat's right-click menu in the inbox, as a plan: Copy ▸ (the name, and a link only where the network gives
/// one) and Delete Chat… (only where the chat's network can delete it).
final class ChatMenuPlanTests: XCTestCase {
    private func row(_ id: String = "!a", network: String = "whatsapp", direct: Bool = true, mergeID: String = "") -> InboxRow {
        var row = InboxRow(roomID: id, network: network, name: "Sam", avatarPath: "", isDirect: direct, lastTS: 1,
                           preview: "", previewKind: .text, previewMine: false, unread: 0, muted: false)
        row.mergeID = mergeID
        return row
    }

    private func features(canDelete: Bool, leavesGroup: Bool = false, canLeave: Bool = false) -> ChatFeatures {
        var features = ChatFeatures.noFeatures
        features.canDelete = canDelete
        features.deleteLeavesGroup = leavesGroup
        features.canLeave = canLeave
        return features
    }

    private func items(_ context: ChatMenuContext) -> [ChatMenuItem] {
        ChatMenuPlan.sections(context).flatMap { $0 }
    }

    private func titles(_ context: ChatMenuContext) -> [String] {
        items(context).map(\.title)
    }

    // MARK: Copy ▸

    func testCopyHasTheChatNameAndNoLinkWhereTheNetworkGivesNone() throws {
        var context = ChatMenuContext(rows: [row()])
        context.chatName = { _ in "Sam Lee" }
        let copy = try XCTUnwrap(items(context).first { $0.id == "copy" })
        XCTAssertEqual(copy.title, "Copy")
        XCTAssertEqual(copy.children.map(\.title), ["Chat Name"])
        XCTAssertEqual(copy.children.first?.command, .copyChatName("Sam Lee"))
    }

    func testCopyHasALinkOnlyForAChatWhoseNetworkGivesOne() throws {
        var context = ChatMenuContext(rows: [row("!tg", network: "telegram")])
        context.chatLink = { $0.network == "telegram" ? "https://t.me/sam" : nil }
        let withLink = try XCTUnwrap(items(context).first { $0.id == "copy" })
        XCTAssertEqual(withLink.children.map(\.title), ["Chat Name", "Link"])
        XCTAssertEqual(withLink.children.last?.command, .copyChatLink("https://t.me/sam"))

        context.rows = [row("!wa", network: "whatsapp")]
        let without = try XCTUnwrap(items(context).first { $0.id == "copy" })
        XCTAssertEqual(without.children.map(\.title), ["Chat Name"])
    }

    func testCopyIsForOneChatAtATime() {
        let context = ChatMenuContext(rows: [row("!a"), row("!b")])
        XCTAssertFalse(titles(context).contains("Copy"))
    }

    // MARK: Delete Chat…

    func testDeleteIsOfferedWhereTheNetworkCanDeleteAndNowhereElse() {
        var context = ChatMenuContext(rows: [row()])
        context.features = { _ in self.features(canDelete: true) }
        XCTAssertTrue(titles(context).contains("Delete Chat…"))

        context.features = { _ in self.features(canDelete: false) }
        XCTAssertFalse(titles(context).contains("Delete Chat…"), "a network that can't delete shows no dead item")

        context.features = { _ in nil }
        XCTAssertFalse(titles(context).contains("Delete Chat…"), "while the network hasn't said, nothing is claimed")
    }

    func testDeleteFollowsEachChatsOwnNetwork() {
        var context = ChatMenuContext(rows: [row("!wa", network: "whatsapp")])
        context.features = { $0.network == "whatsapp" ? self.features(canDelete: true) : self.features(canDelete: false) }
        XCTAssertTrue(titles(context).contains("Delete Chat…"))
        context.rows = [row("!gm", network: "gmessages")]
        XCTAssertFalse(titles(context).contains("Delete Chat…"))
    }

    func testDeleteSitsAboveReportAsSpamAndIsDestructive() throws {
        var context = ChatMenuContext(rows: [row()])
        context.features = { _ in self.features(canDelete: true) }
        let manage = try XCTUnwrap(ChatMenuPlan.sections(context).last)
        XCTAssertEqual(manage.map(\.title).suffix(2), ["Delete Chat…", "Report as Spam…"])
        XCTAssertTrue(manage.first { $0.title == "Delete Chat…" }?.isDestructive == true)
        XCTAssertEqual(manage.first { $0.title == "Delete Chat…" }?.command, .deleteChat(roomID: "!a"))
    }

    func testDeleteIsLeftOutOfSeveralChatsAndOfAMergedChat() {
        var context = ChatMenuContext(rows: [row("!a"), row("!b")])
        context.features = { _ in self.features(canDelete: true) }
        XCTAssertFalse(titles(context).contains("Delete Chat…"), "one chat at a time")

        context.rows = [row("merge:1", mergeID: "merge:1")]
        XCTAssertFalse(titles(context).contains("Delete Chat…"), "a merged chat is deleted from its own chats")
    }

    func testDeleteIsLeftOutWhenTheAppHasNoWayToAsk() {
        var context = ChatMenuContext(rows: [row()])
        context.features = { _ in self.features(canDelete: true) }
        context.canDeleteChats = false
        XCTAssertFalse(titles(context).contains("Delete Chat…"))
    }

    func testLeaveGroupNeedsAGroupTheNetworkLetsYouLeaveAndAHandler() {
        var context = ChatMenuContext(rows: [row(direct: false)])
        context.features = { _ in self.features(canDelete: false, canLeave: true) }
        XCTAssertFalse(titles(context).contains("Leave Group…"), "no handler in the inbox, so no dead item")
        context.canLeaveGroups = true
        XCTAssertTrue(titles(context).contains("Leave Group…"))
        context.rows = [row()]
        XCTAssertFalse(titles(context).contains("Leave Group…"), "a one-to-one chat has no group to leave")
    }

    // MARK: Confirmation

    func testDeleteConfirmationNamesTheNetworkAndSaysWhatItDoes() {
        let plain = ChatDeleteConfirmation.text(networkName: "WhatsApp", features: features(canDelete: true))
        XCTAssertEqual(plain.title, "Delete this chat?")
        XCTAssertEqual(plain.detail, "It’s removed from this Mac and from WhatsApp where the network allows it.")

        let leaving = ChatDeleteConfirmation.text(networkName: "WhatsApp", features: features(canDelete: true, leavesGroup: true))
        XCTAssertEqual(leaving.detail,
                       "It’s removed from this Mac and from WhatsApp where the network allows it. This also leaves the group.")

        let unknown = ChatDeleteConfirmation.text(networkName: nil, features: features(canDelete: true))
        XCTAssertEqual(unknown.detail, "It’s removed from this Mac and from its network where the network allows it.")
    }

    // MARK: The rest of the menu stays as it was

    func testTheMenuKeepsItsOrderAndItsKeys() {
        var context = ChatMenuContext(rows: [row()])
        context.canSearchInChat = true
        context.reminderPresets = ["In an Hour", "Tomorrow"]
        let sections = ChatMenuPlan.sections(context)
        XCTAssertEqual(
            sections.map { $0.map(\.title) },
            [
                ["Archive", "Mute", "Mark as Unread", "Pin", "Search…", "Hide", "Move to Low Priority", "Label", "Remind Me",
                 "Open in New Window", "Chat Theme…", "Copy"],
                ["Begin Selecting"],
                ["Merge with Another Chat…", "Edit Chat…", "Report as Spam…"],
            ]
        )
        XCTAssertEqual(sections[0].first?.key, ChatMenuKey("e"))
        XCTAssertEqual(sections[0][1].key, ChatMenuKey("m", shift: true))

        context.showsKeys = false
        XCTAssertTrue(items(context).allSatisfy { $0.key == nil }, "the hover button's menu shows no keys")
    }

    func testRequestsGetAcceptAndDeclineFirst() {
        var request = row()
        request.request = true
        let sections = ChatMenuPlan.sections(ChatMenuContext(rows: [request]))
        XCTAssertEqual(sections.first?.map(\.title), ["Accept", "Decline"])
    }

    func testSeveralChatsGetTheBulkItemsOnly() {
        var context = ChatMenuContext(rows: [row("!a"), row("!b")])
        context.isSelecting = true
        let all = titles(context)
        XCTAssertTrue(all.contains("Archive"))
        XCTAssertFalse(all.contains("Open in New Window"))
        XCTAssertFalse(all.contains("Begin Selecting"), "already selecting")
        XCTAssertFalse(all.contains("Edit Chat…"))
    }

    func testALabelTheChatsAllHaveIsTickedAndTurnsOffOnChoosing() throws {
        var labelled = row()
        labelled.labels = [7]
        var context = ChatMenuContext(rows: [labelled])
        context.labels = [(7, "Work"), (8, "Family")]
        let label = try XCTUnwrap(items(context).first { $0.id == "label" })
        XCTAssertEqual(label.children.map(\.title), ["Work", "Family", "New Label…"])
        XCTAssertTrue(label.children[0].isOn)
        XCTAssertEqual(label.children[0].command, .toggleLabel(id: 7, on: false))
        XCTAssertFalse(label.children[1].isOn)
        XCTAssertEqual(label.children[1].command, .toggleLabel(id: 8, on: true))
    }
}
