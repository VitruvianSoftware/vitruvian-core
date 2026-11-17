// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// A person has one initials colour everywhere: it comes from their stable ID, never from a name that each screen
/// can spell differently. All data here is made up.
final class AvatarColorTests: XCTestCase {
    private func row(roomID: String, name: String) -> InboxRow {
        InboxRow(roomID: roomID, network: "whatsapp", name: name, avatarPath: "", isDirect: true, lastTS: 1,
                 preview: "hi", previewKind: .text, previewMine: false, unread: 0, muted: false)
    }

    private func info(roomID: String, name: String) -> RoomInfoResult {
        RoomInfoResult(roomID: roomID, name: name, remoteName: name, network: "whatsapp", isDirect: true,
                       members: [], features: .noFeatures)
    }

    /// The reported bug: the inbox row and header called the chat "Toan Vu", chat info called it something a little
    /// different, and the two got different colours.
    func testAChatHasOneColourInTheInboxHeaderAndChatInfoWhateverItsNameSaysThere() {
        let inbox = row(roomID: "!toan:example.test", name: "Toan Vu")
        let header = inbox // the header draws the same row
        let chatInfo = info(roomID: "!toan:example.test", name: "toan vu (work)")
        XCTAssertEqual(inbox.avatarIdentity, "!toan:example.test")
        XCTAssertEqual(AvatarColor.hsb(forIdentity: inbox.avatarIdentity), AvatarColor.hsb(forIdentity: header.avatarIdentity))
        XCTAssertEqual(AvatarColor.hsb(forIdentity: inbox.avatarIdentity), AvatarColor.hsb(forIdentity: chatInfo.avatarIdentity))
    }

    func testAMemberHasOneColourInTheMemberListAndBesideMessagesAndOnReactions() {
        let member = Member(userID: "@toan:example.test", name: "Toan Vu", avatarPath: "")
        let renamed = Member(userID: "@toan:example.test", name: "Toan", avatarPath: "")
        XCTAssertEqual(member.avatarIdentity, "@toan:example.test")
        XCTAssertEqual(AvatarColor.hsb(forIdentity: member.avatarIdentity), AvatarColor.hsb(forIdentity: renamed.avatarIdentity))

        // Beside messages.
        let event = Event(eventID: "$1", roomID: "!g", sender: "@toan:example.test", senderName: "Toan Vu", mine: false,
                          type: "m.room.message", content: try! JSONDecoder().decode(JSONValue.self, from: Data(#"{"msgtype":"m.text","body":"hi"}"#.utf8)), ts: 1, seq: 0, status: .sent)
        let messages = Timeline.build(events: [event], me: Timeline.meUserID, now: Date(), isDirect: false)
        guard case let .message(message)? = messages.last else { return XCTFail("a message") }
        XCTAssertEqual(message.senderAvatar().seed, member.avatarIdentity, "beside messages: the sender's ID")
        XCTAssertEqual(message.senderAvatar(redacted: false).seed, "@toan:example.test")

        // On a reaction pill.
        let chip = ReactionChip(key: "👍", count: 1, mine: false, reactors: [
            Reactor(userID: "@toan:example.test", name: "Toan Vu", isMe: false),
        ])
        guard case let .avatars(items, _) = chip.pillDisplay() else { return XCTFail("avatars") }
        XCTAssertEqual(items[0].seed, member.avatarIdentity, "on reactions: the reactor's ID")
    }

    func testTheColourIsStableAndSpreadsAcrossPeople() {
        XCTAssertEqual(AvatarColor.hsb(forIdentity: "@a:x"), AvatarColor.hsb(forIdentity: "@a:x"))
        let hues = Set((0 ..< 40).map { AvatarColor.hsb(forIdentity: "@user\($0):x").hue })
        XCTAssertGreaterThan(hues.count, 15, "different people get different colours")
    }

    func testANameIsOnlyTheFallbackWhenNoIDIsKnown() {
        XCTAssertEqual(AvatarColor.identity(id: "", fallbackName: "Toan Vu"), "Toan Vu")
        XCTAssertEqual(AvatarColor.identity(id: "@t:x", fallbackName: "Toan Vu"), "@t:x")
    }
}
