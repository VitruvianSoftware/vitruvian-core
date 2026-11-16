// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class ChatInfoPresentationTests: XCTestCase {
    private func makeEvent(
        id: String,
        msgtype: String,
        sender: String = "@alice:courier.local",
        senderName: String = "Alice",
        senderAvatarPath: String = "",
        mine: Bool = false,
        viewOnce: Bool? = nil
    ) -> Event {
        Event(
            eventID: id,
            roomID: "!room:courier.local",
            sender: sender,
            senderName: senderName,
            senderAvatarPath: senderAvatarPath,
            mine: mine,
            type: "m.room.message",
            content: .object(["msgtype": .string(msgtype), "body": .string(id)]),
            ts: 1_700_000_000_000,
            seq: 1,
            status: .sent,
            viewOnce: viewOnce
        )
    }

    // MARK: - RoomLink deduplication & domain

    func testRoomLinkDeduplicatedKeepsNewestRegardlessOfOrder() {
        let older = RoomLink(
            eventID: "$e1",
            sender: "@alice:courier.local",
            ts: 1_000,
            url: "https://example.com/guide",
            host: "example.com"
        )
        let newer = RoomLink(
            eventID: "$e2",
            sender: "@bob:courier.local",
            ts: 3_000,
            url: "https://example.com/guide",
            host: "example.com"
        )
        let other = RoomLink(
            eventID: "$e3",
            sender: "@alice:courier.local",
            ts: 2_000,
            url: "https://vitruviansoftware.dev/docs",
            host: "vitruviansoftware.dev"
        )

        let forward = RoomLink.deduplicated([older, other, newer])
        XCTAssertEqual(forward, [newer, other])

        let reversed = RoomLink.deduplicated([newer, other, older])
        XCTAssertEqual(reversed, [newer, other])
    }

    func testRoomLinkDeduplicatedTieBreaksByFirstEncountered() {
        let first = RoomLink(
            eventID: "$e1",
            sender: "@alice:courier.local",
            ts: 5_000,
            url: "https://example.com/same",
            host: "example.com"
        )
        let second = RoomLink(
            eventID: "$e2",
            sender: "@bob:courier.local",
            ts: 5_000,
            url: "https://example.com/same",
            host: "example.com"
        )

        let result = RoomLink.deduplicated([first, second])
        XCTAssertEqual(result, [first])
    }

    func testRoomLinkDisplayDomainFallsBackFromHostToParsedURL() {
        let withHost = RoomLink(
            eventID: "$1",
            sender: "@a",
            ts: 1,
            url: "https://docs.example.com/path",
            host: "docs.example.com"
        )
        XCTAssertEqual(withHost.displayDomain, "docs.example.com")

        let emptyHost = RoomLink(
            eventID: "$2",
            sender: "@a",
            ts: 2,
            url: "https://news.ycombinator.com/item?id=1",
            host: "  "
        )
        XCTAssertEqual(emptyHost.displayDomain, "news.ycombinator.com")

        let unparseable = RoomLink(
            eventID: "$3",
            sender: "@a",
            ts: 3,
            url: "not a url",
            host: ""
        )
        XCTAssertEqual(unparseable.displayDomain, "not a url")
    }

    // MARK: - Shared Media filtering & sender attribution

    func testSharedMediaEventsFiltersToImagesAndVideosOnly() {
        let img = makeEvent(id: "$img", msgtype: "m.image")
        let vid = makeEvent(id: "$vid", msgtype: "m.video")
        let linkPreviewText = makeEvent(id: "$txt", msgtype: "m.text")
        let file = makeEvent(id: "$file", msgtype: "m.file")
        let audio = makeEvent(id: "$aud", msgtype: "m.audio")
        let notice = makeEvent(id: "$notice", msgtype: "m.notice")
        let viewOnceImg = makeEvent(id: "$vo", msgtype: "m.image", viewOnce: true)

        let filtered = ChatInfoPresentation.sharedMediaEvents([
            img,
            linkPreviewText,
            vid,
            file,
            audio,
            notice,
            viewOnceImg,
        ])
        XCTAssertEqual(filtered.map(\.eventID), ["$img", "$vid"])
    }

    func testMediaSenderAttributionAndUnknownSender() {
        let members = [
            Member(userID: "@bob:courier.local", name: "Bob Builder", avatarPath: "/tmp/bob.png"),
        ]

        let explicit = makeEvent(
            id: "$1",
            msgtype: "m.image",
            sender: "@alice:courier.local",
            senderName: "Alice Example",
            senderAvatarPath: "/tmp/alice.png"
        )
        XCTAssertEqual(
            ChatInfoPresentation.mediaSender(for: explicit, members: members),
            ChatInfoPresentation.MediaSender(name: "Alice Example", initials: "A", avatarPath: "/tmp/alice.png")
        )

        let fromMember = makeEvent(
            id: "$2",
            msgtype: "m.video",
            sender: "@bob:courier.local",
            senderName: "",
            senderAvatarPath: ""
        )
        XCTAssertEqual(
            ChatInfoPresentation.mediaSender(for: fromMember, members: members),
            ChatInfoPresentation.MediaSender(name: "Bob Builder", initials: "B", avatarPath: "/tmp/bob.png")
        )

        let mine = makeEvent(
            id: "$3",
            msgtype: "m.image",
            sender: Timeline.meUserID,
            senderName: "",
            mine: true
        )
        XCTAssertEqual(
            ChatInfoPresentation.mediaSender(for: mine, members: members)?.name,
            String(localized: "You")
        )

        let unknown = makeEvent(
            id: "$4",
            msgtype: "m.image",
            sender: "",
            senderName: "",
            senderAvatarPath: "",
            mine: false
        )
        XCTAssertNil(ChatInfoPresentation.mediaSender(for: unknown, members: members))
    }

    // MARK: - Admin badge visibility

    func testShowsAdminBadgeOnlyWhenNotEveryoneIsAdmin() {
        let aliceAdmin = Member(userID: "@alice", name: "Alice", isAdmin: true)
        let bobMember = Member(userID: "@bob", name: "Bob", isAdmin: false)
        let carolAdmin = Member(userID: "@carol", name: "Carol", isAdmin: true)

        let mixed = [aliceAdmin, bobMember]
        XCTAssertTrue(ChatInfoPresentation.showsAdminBadge(for: aliceAdmin, in: mixed))
        XCTAssertFalse(ChatInfoPresentation.showsAdminBadge(for: bobMember, in: mixed))

        let allAdmins = [aliceAdmin, carolAdmin]
        XCTAssertFalse(ChatInfoPresentation.showsAdminBadge(for: aliceAdmin, in: allAdmins))
        XCTAssertFalse(ChatInfoPresentation.showsAdminBadge(for: carolAdmin, in: allAdmins))

        let singleAdmin = [aliceAdmin]
        XCTAssertFalse(ChatInfoPresentation.showsAdminBadge(for: aliceAdmin, in: singleAdmin))
        XCTAssertFalse(ChatInfoPresentation.showsAdminBadge(for: aliceAdmin, in: []))
    }

    // MARK: - Group composite header members

    func testGroupCompositeMembersMatchesInboxRowSemantics() {
        let members = [
            Member(userID: Timeline.meUserID, name: "Me", avatarPath: "/tmp/me.png"),
            Member(userID: "@a", name: "Alice", avatarPath: ""),
            Member(userID: "@b", name: "Bob", avatarPath: "/tmp/bob.png"),
            Member(userID: "@c", name: "Carol", avatarPath: "/tmp/carol.png"),
            Member(userID: "@d", name: "Dan", avatarPath: ""),
        ]

        let groupInfo = RoomInfoResult(
            roomID: "!g1",
            name: "Weekend Trail Crew",
            remoteName: "Weekend Trail Crew",
            network: "whatsapp",
            isDirect: false,
            members: members,
            features: .noFeatures
        )
        let composite = ChatInfoPresentation.groupCompositeMembers(for: groupInfo)
        XCTAssertEqual(composite.map(\.name), ["Bob", "Carol", "Alice"])
        XCTAssertEqual(composite.map(\.avatarPath), ["/tmp/bob.png", "/tmp/carol.png", nil])

        let channelInfo = RoomInfoResult(
            roomID: "!g2",
            name: "#engineering",
            remoteName: "#engineering",
            network: "slack",
            isDirect: false,
            members: members,
            features: .noFeatures
        )
        XCTAssertTrue(ChatInfoPresentation.groupCompositeMembers(for: channelInfo).isEmpty)

        let namedPeopleInfo = RoomInfoResult(
            roomID: "!g3",
            name: "Alice, Bob",
            remoteName: "Alice, Bob",
            network: "imessage",
            isDirect: false,
            members: [],
            features: .noFeatures
        )
        XCTAssertEqual(
            ChatInfoPresentation.groupCompositeMembers(for: namedPeopleInfo).map(\.name),
            ["Alice", "Bob"]
        )
    }
}
