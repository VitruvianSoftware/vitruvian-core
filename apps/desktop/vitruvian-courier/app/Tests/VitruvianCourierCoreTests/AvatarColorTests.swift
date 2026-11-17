// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// A person has one initials colour everywhere: it comes from their stable ID, never from a name that each screen
/// can spell differently. All data here is made up.
final class AvatarColorTests: XCTestCase {
    private func row(roomID: String, name: String, peer: [RowMember] = []) -> InboxRow {
        InboxRow(roomID: roomID, network: "whatsapp", name: name, avatarPath: "", isDirect: true, lastTS: 1,
                 preview: "hi", previewKind: .text, previewMine: false, unread: 0, muted: false, memberPreview: peer)
    }

    private func info(roomID: String, name: String, members: [Member] = []) -> RoomInfoResult {
        RoomInfoResult(roomID: roomID, name: name, remoteName: name, network: "whatsapp", isDirect: true,
                       members: members, features: .noFeatures)
    }

    /// One person, one colour: the same user in a one-to-one inbox row, its header, chat info, a group message and a
    /// member list resolves to the same colour, whatever each place calls them.
    func testTheSameUserHasOneColourInOneToOneRowHeaderChatInfoGroupMessageAndMemberList() {
        let toan = "@toan:example.test"
        let inbox = row(roomID: "!dm:example.test", name: "Toan Vu", peer: [RowMember(userID: toan, name: "Toan Vu")])
        let header = inbox // the header draws the same row
        let chatInfo = info(roomID: "!dm:example.test", name: "toan vu (work)", members: [
            Member(userID: Timeline.meUserID, name: "Me"),
            Member(userID: "@whatsappbot:courier.local", name: "WhatsApp bridge bot"),
            Member(userID: toan, name: "Toan"),
        ])
        let memberList = Member(userID: toan, name: "T. Vu")
        let event = Event(eventID: "$1", roomID: "!group", sender: toan, senderName: "Toan (mobile)", mine: false,
                          type: "m.room.message",
                          content: try! JSONDecoder().decode(JSONValue.self, from: Data(#"{"msgtype":"m.text","body":"hi"}"#.utf8)),
                          ts: 1, seq: 0, status: .sent)
        guard case let .message(groupMessage)? = Timeline.build(events: [event], me: Timeline.meUserID, now: Date(), isDirect: false).last
        else { return XCTFail("a message") }

        let want = AvatarColor.hsb(forIdentity: toan)
        for (place, identity) in [
            ("inbox row", inbox.avatarIdentity), ("header", header.avatarIdentity), ("chat info", chatInfo.avatarIdentity),
            ("group message", groupMessage.senderAvatar().seed), ("member list", memberList.avatarIdentity),
        ] {
            XCTAssertEqual(AvatarColor.hsb(forIdentity: identity), want, place)
        }
    }

    /// Until a counterpart is known, a one-to-one chat is coloured by its room ID, the same in its row and chat info.
    func testAOneToOneChatWithNoKnownCounterpartFallsBackToItsRoomID() {
        let lonely = row(roomID: "!dm:example.test", name: "Toan Vu")
        let botOnly = info(roomID: "!dm:example.test", name: "Toan Vu", members: [
            Member(userID: Timeline.meUserID, name: "Me"),
            Member(userID: "@whatsappbot:courier.local", name: "Bridge bot"),
            Member(userID: "@robot:courier.local", name: "Robot", isBot: true),
        ])
        XCTAssertEqual(lonely.avatarIdentity, "!dm:example.test")
        XCTAssertEqual(botOnly.avatarIdentity, "!dm:example.test")
    }

    func testTheEditSheetDraftColoursAChatTheSameAsItsRow() {
        let chatInfo = info(roomID: "!dm:example.test", name: "Toan", members: [
            Member(userID: Timeline.meUserID, name: "Me"), Member(userID: "@toan:example.test", name: "Toan"),
        ])
        XCTAssertEqual(EditGroupDraft(info: chatInfo).avatarIdentity, "@toan:example.test")
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

    func testGroupCompositeMembersAndMediaSendersUseUserIDsAcrossRenames() throws {
        let inboxGroup = InboxRow(
            roomID: "!crew:example.test", network: "whatsapp", name: "Launch crew", avatarPath: "", isDirect: false,
            lastTS: 1, preview: "hi", previewKind: .text, previewMine: false, unread: 0, muted: false,
            memberPreview: [
                RowMember(userID: "@toan:example.test", name: "Toan Vu"),
                RowMember(userID: "@bo:example.test", name: "Bo Example"),
            ]
        )
        guard case let .people(previewPeople) = inboxGroup.groupAvatarStyle else {
            return XCTFail("expected composite people style")
        }
        XCTAssertEqual(previewPeople.map(\.identity), ["@toan:example.test", "@bo:example.test"])

        let groupInfo = RoomInfoResult(
            roomID: "!crew:example.test", name: "Launch crew", remoteName: "Launch crew", network: "whatsapp",
            isDirect: false,
            members: [
                Member(userID: Timeline.meUserID, name: "Me"),
                Member(userID: "@toan:example.test", name: "toan vu (renamed)"),
                Member(userID: "@bo:example.test", name: "B. Example"),
            ],
            features: .noFeatures
        )
        let composite = ChatInfoPresentation.groupCompositeMembers(for: groupInfo)
        XCTAssertEqual(composite.map(\.identity), ["@toan:example.test", "@bo:example.test"])
        XCTAssertEqual(
            AvatarColor.hsb(forIdentity: previewPeople[0].identity),
            AvatarColor.hsb(forIdentity: composite[0].identity),
            "inbox composite circle and Chat Info composite circle share the member's userID colour"
        )

        let mediaContent = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"msgtype":"m.image","body":"photo.jpg"}"#.utf8))
        let theirMedia = Event(
            eventID: "$img1", roomID: "!crew:example.test", sender: "@toan:example.test",
            senderName: "Yet Another Spelling", mine: false, type: "m.room.message",
            content: mediaContent, ts: 2, seq: 1, status: .sent
        )
        let resolvedTheir = try XCTUnwrap(
            ChatInfoPresentation.mediaSender(for: theirMedia, members: groupInfo.members, ownAvatarPath: "/tmp/me.png")
        )
        XCTAssertEqual(resolvedTheir.identity, "@toan:example.test")

        let ownMedia = Event(
            eventID: "$img2", roomID: "!crew:example.test", sender: Timeline.meUserID,
            senderName: "", mine: true, type: "m.room.message",
            content: mediaContent, ts: 3, seq: 2, status: .sent
        )
        let resolvedOwn = try XCTUnwrap(
            ChatInfoPresentation.mediaSender(for: ownMedia, members: [], ownAvatarPath: "/tmp/me.png")
        )
        XCTAssertEqual(resolvedOwn.identity, Timeline.meUserID)
    }

    func testRedactedMessageAndReactionSeedsKeyOnUserIDNotDisplayName() throws {
        let content = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"msgtype":"m.text","body":"hi"}"#.utf8))
        let first = Event(
            eventID: "$1", roomID: "!g", sender: "@toan:example.test", senderName: "Toan Vu",
            mine: false, type: "m.room.message", content: content, ts: 1, seq: 0, status: .sent
        )
        let renamed = Event(
            eventID: "$2", roomID: "!g", sender: "@toan:example.test", senderName: "Toan (Mobile)",
            mine: false, type: "m.room.message", content: content, ts: 600_000, seq: 1, status: .sent
        )
        let built = Timeline.build(events: [first, renamed], me: Timeline.meUserID, now: Date(), isDirect: false)
            .compactMap { item -> TimelineMessage? in
                if case let .message(msg) = item { return msg }
                return nil
            }
        XCTAssertEqual(built.count, 2)
        XCTAssertEqual(
            built[0].senderAvatar(redacted: true).seed,
            built[1].senderAvatar(redacted: true).seed,
            "redacted sender avatar colour stays constant when the sender's display name changes"
        )

        let chip = ReactionChip(key: "🔥", count: 1, mine: false, reactors: [
            Reactor(userID: "@toan:example.test", name: "Totally Different Name", isMe: false),
        ])
        guard case let .avatars(items, _) = chip.pillDisplay(redacted: true) else {
            return XCTFail("expected redacted reaction avatar")
        }
        XCTAssertEqual(items[0].seed, built[0].senderAvatar(redacted: true).seed)
    }
}
