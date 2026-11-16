// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// The bridge's network tag ("Toan Vu (WA)") is taken off a person's name, and only that tag: a person's own
/// brackets stay. One-to-one chats show the whole name the network gave; first names are for group titles.
@MainActor
final class NetworkTagTests: XCTestCase {
    func testTheKnownNetworkTagsAreTakenOff() {
        XCTAssertEqual(NetworkTag.stripped("Toan Vu (WA)"), "Toan Vu")
        XCTAssertEqual(NetworkTag.stripped("Thắng Nguyễn Duy (WA)"), "Thắng Nguyễn Duy")
        XCTAssertEqual(NetworkTag.stripped("Adam (TG)"), "Adam")
        XCTAssertEqual(NetworkTag.stripped("Ana Pop (LinkedIn)"), "Ana Pop")
        XCTAssertEqual(NetworkTag.stripped("Pat (Twitter)"), "Pat")
        XCTAssertEqual(NetworkTag.stripped("Sam (Bluesky)"), "Sam")
        XCTAssertEqual(NetworkTag.stripped("+12066409886 (WA)"), "+12066409886")
        XCTAssertEqual(NetworkTag.stripped("Toan Vu (wa)"), "Toan Vu", "the tag's case does not matter")
        XCTAssertEqual(NetworkTag.stripped("  Toan Vu  ( WA )  "), "Toan Vu", "nor the spaces round it")
    }

    /// Only the tags the bridges add are removed. Everything else in brackets is part of the name.
    func testAPersonsOwnBracketsStay() {
        for name in ["Room (2)", "Alex (Work)", "Fred Fireflies (bot)", "James (you)", "Pat (EST)", "Walt (ex. Wallet)",
                     "Dr. Lee (Dentist)", "Mom (home)", "(213) 447-6502"] {
            XCTAssertEqual(NetworkTag.stripped(name), name, "\(name) has no network tag")
        }
    }

    func testOnlyTheTrailingTagGoesAndOnlyOne() {
        XCTAssertEqual(NetworkTag.stripped("(WA) Toan"), "(WA) Toan", "a tag in front is not the bridge's")
        XCTAssertEqual(NetworkTag.stripped("Toan (WA) Vu"), "Toan (WA) Vu")
        XCTAssertEqual(NetworkTag.stripped("Toan (WA) (WA)"), "Toan (WA)", "one tag, not every one")
        XCTAssertEqual(NetworkTag.stripped("Alex (Work) (WA)"), "Alex (Work)")
    }

    func testANameIsNeverEmptied() {
        XCTAssertEqual(NetworkTag.stripped("(WA)"), "(WA)")
        XCTAssertEqual(NetworkTag.stripped(" (WA)"), " (WA)")
        XCTAssertEqual(NetworkTag.stripped(""), "")
    }

    // MARK: - One-to-one chats

    private func direct(_ name: String, local: String = "") -> InboxRow {
        InboxRow(roomID: "!a", network: "whatsapp", name: name, avatarPath: "", isDirect: true, lastTS: 0, preview: "",
                 previewKind: .text, previewMine: false, unread: 0, muted: false, localName: local)
    }

    func testAOneToOneChatShowsTheFullNameWithoutTheTag() {
        XCTAssertEqual(direct("Toan Vu (WA)").displayTitle, "Toan Vu")
        XCTAssertEqual(direct("Thắng Nguyễn Duy (WA)").displayTitle, "Thắng Nguyễn Duy")
        XCTAssertEqual(direct("Hans Wunsch").displayTitle, "Hans Wunsch", "a full name is never shortened to a first name")
        XCTAssertEqual(direct("Raymond Walintukan").displayTitle, "Raymond Walintukan")
        XCTAssertEqual(direct("Fred Fireflies (bot)").displayTitle, "Fred Fireflies (bot)")
        XCTAssertEqual(direct("Room (2)").displayTitle, "Room (2)")
        XCTAssertEqual(direct("+12066409886 (WA)").displayTitle, "+12066409886")
    }

    /// The header and the composer's "Message … on WhatsApp" are built from the same title.
    func testTheComposerPlaceholderNamesThePersonWithoutTheTag() {
        let title = direct("Toan Vu (WA)").displayTitle
        XCTAssertEqual(ConversationModel.composerPlaceholder(chatName: title, network: "whatsapp"),
                       "Message Toan Vu on WhatsApp")
    }

    func testTheChatInfoTitleAgreesWithTheRow() {
        let info = RoomInfoResult(roomID: "!a", name: "Toan Vu (WA)", remoteName: "Toan Vu (WA)", network: "whatsapp",
                                  isDirect: true, features: .noFeatures)
        XCTAssertEqual(info.displayTitle, "Toan Vu")
        let shown = ConversationModel.applyingDisplayTitle(to: info)
        XCTAssertEqual(shown.name, "Toan Vu")
        XCTAssertEqual(shown.remoteName, "Toan Vu", "so the chat info does not read the tag's removal as a rename")
    }

    // MARK: - Groups keep their first names

    func testGroupTitlesStillUseFirstNamesAndLoseMemberTags() {
        let members = [
            GroupTitleMember(userID: "@a", name: "Toan Vu (WA)"),
            GroupTitleMember(userID: "@b", name: "Adam Smith (WA)"),
            GroupTitleMember(userID: Timeline.meUserID, name: "Me"),
        ]
        let title = ChatDisplayTitle.format(name: "Toan Vu (WA), Adam Smith (WA)", isDirect: false, members: members)
        XCTAssertEqual(title, "Toan & Adam")
    }

    func testAGroupsOwnNameIsLeftAlone() {
        XCTAssertEqual(ChatDisplayTitle.format(name: "Book club (2)", isDirect: false), "Book club (2)")
    }

    // MARK: - Messages and people

    func testSenderNamesInTheTimelineLoseTheTagToo() {
        let event = Event(eventID: "$1", roomID: "!a", sender: "@a:courier.local", senderName: "Toan Vu (WA)",
                          senderAvatarPath: "", mine: false, type: "m.room.message",
                          content: .object(["msgtype": .string("m.text"), "body": .string("hi")]), ts: 1_700_000_000_000,
                          seq: 1, status: .sent)
        let names = Timeline.build(events: [event], me: Timeline.meUserID, now: Date(timeIntervalSince1970: 1_900_000_000))
            .compactMap { item -> String? in if case let .message(m) = item { m.senderName } else { nil } }
        XCTAssertEqual(names, ["Toan Vu"])
    }

    func testNumberDetectionStillSeesThroughATag() {
        XCTAssertTrue(ContactListOrdering.isNumberOrHandle("+12134476502 (WA)"))
        XCTAssertFalse(ContactListOrdering.isNumberOrHandle("Alice (WA)"))
    }
}
