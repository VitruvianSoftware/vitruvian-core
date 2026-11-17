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

    // MARK: - Link titles, my own picture

    func testLinkShowsItsPreviewTitleUnlessItOnlyRepeatsTheDomain() {
        func link(_ title: String?) -> RoomLink {
            RoomLink(eventID: "$e", sender: "@a:courier.local", ts: 1, url: "https://share.google/abc", host: "share.google", title: title)
        }
        XCTAssertEqual(link("  Courier release notes ").displayTitle, "Courier release notes")
        XCTAssertNil(link(nil).displayTitle)
        XCTAssertNil(link("   ").displayTitle)
        XCTAssertNil(link("Share.Google").displayTitle, "a title that is only the domain adds nothing")
    }

    func testLinkTitleSurvivesDeduplicationAndTheWire() throws {
        let newestNoTitle = RoomLink(eventID: "$2", sender: "@a:courier.local", ts: 20, url: "https://x.test/a", host: "x.test")
        let olderTitled = RoomLink(eventID: "$1", sender: "@a:courier.local", ts: 10, url: "https://x.test/a", host: "x.test", title: "Spec")
        let merged = RoomLink.deduplicated([olderTitled, newestNoTitle])
        XCTAssertEqual(merged.map(\.eventID), ["$2"], "the newest message is kept")
        XCTAssertEqual(merged.first?.displayTitle, "Spec", "and it keeps the title another copy had")

        let json = Data(#"{"event_id":"$1","sender":"@a:courier.local","ts":5,"url":"https://x.test/a","host":"x.test","title":"Spec"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(RoomLink.self, from: json).title, "Spec")
        let old = Data(#"{"event_id":"$1","sender":"@a:courier.local","ts":5,"url":"https://x.test/a","host":"x.test"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(RoomLink.self, from: old).title, "an engine before the field")
    }

    func testTimelineAvatarComesOnlyFromTheChatsOwnAccount() {
        func row(_ id: String, network: String, login: String) -> InboxRow {
            InboxRow(roomID: id, network: network, name: id, avatarPath: "", isDirect: true, lastTS: 0, preview: "",
                     previewKind: .text, previewMine: false, unread: 0, muted: false, archived: false,
                     lowPriority: false, hidden: false, markedUnread: false, request: false, loginName: login)
        }
        func mine(_ room: String, _ avatar: String, ts: Int64) -> Event {
            var e = makeEvent(id: "$\(room)\(ts)", msgtype: "m.text", sender: Timeline.meUserID, senderName: "Me",
                              senderAvatarPath: avatar, mine: true)
            e.roomID = room
            e.ts = ts
            return e
        }
        let rows = [
            "!chat": row("!chat", network: "whatsapp", login: "work-phone"),
            "!sameAccount": row("!sameAccount", network: "whatsapp", login: "work-phone"),
            "!otherAccount": row("!otherAccount", network: "whatsapp", login: "personal-phone"),
            "!otherNetwork": row("!otherNetwork", network: "signal", login: "work-phone"),
            "!noLogin": row("!noLogin", network: "whatsapp", login: ""),
        ]
        func avatar(_ events: [Event], chat: String = "!chat") -> String {
            ChatInfoPresentation.ownAvatarFromTimeline(events: events, chatRoomID: chat,
                                                       chatNetwork: rows[chat]?.network ?? "whatsapp") { rows[$0] }
        }
        // Two accounts on one network: the other account's newer picture is not mine here.
        XCTAssertEqual(avatar([mine("!sameAccount", "/work.png", ts: 10), mine("!otherAccount", "/personal.png", ts: 99)]),
                       "/work.png")
        XCTAssertEqual(avatar([mine("!otherAccount", "/personal.png", ts: 99)]), "", "initials, not another account's face")
        XCTAssertEqual(avatar([mine("!otherNetwork", "/signal.png", ts: 99)]), "")
        XCTAssertEqual(avatar([mine("!noLogin", "/unknown.png", ts: 99)]), "", "an unknown account is not a match")
        XCTAssertEqual(avatar([mine("!chat", "/here.png", ts: 1)]), "/here.png", "a message in the chat itself counts")
        // A chat whose own account is unknown takes nothing from other rooms.
        XCTAssertEqual(avatar([mine("!sameAccount", "/work.png", ts: 10)], chat: "!noLogin"), "")
        XCTAssertEqual(avatar([mine("!noLogin", "/own.png", ts: 10)], chat: "!noLogin"), "/own.png")
        // Newest wins among the matches.
        XCTAssertEqual(avatar([mine("!chat", "/old.png", ts: 1), mine("!sameAccount", "/new.png", ts: 5)]), "/new.png")
    }

    func testOwnAvatarComesFromMemberThenMyMessagesThenFallback() {
        let me = Timeline.meUserID
        func info(meAvatar: String = "", media: [Event] = []) -> RoomInfoResult {
            RoomInfoResult(roomID: "!r:courier.local", name: "Chat", remoteName: "Chat", network: "whatsapp", isDirect: false,
                           members: [Member(userID: me, name: "Me", avatarPath: meAvatar)], sharedMedia: media,
                           features: .noFeatures)
        }
        let mine = makeEvent(id: "$m", msgtype: "m.image", sender: me, senderName: "Me", senderAvatarPath: "/own-event.png", mine: true)
        XCTAssertEqual(ChatInfoPresentation.ownAvatarPath(in: info(meAvatar: "/own-member.png", media: [mine])), "/own-member.png")
        XCTAssertEqual(ChatInfoPresentation.ownAvatarPath(in: info(media: [mine])), "/own-event.png")
        XCTAssertEqual(ChatInfoPresentation.ownAvatarPath(in: info(), fallback: "/seen.png"), "/seen.png")
        XCTAssertEqual(ChatInfoPresentation.ownAvatarPath(in: info()), "")

        // Several of my messages carry a picture: the newest wins, whatever the order they are listed in.
        var older = makeEvent(id: "$old", msgtype: "m.image", sender: me, senderName: "Me", senderAvatarPath: "/old.png", mine: true)
        older.ts = 1_000
        var newer = makeEvent(id: "$new", msgtype: "m.image", sender: me, senderName: "Me", senderAvatarPath: "/new.png", mine: true)
        newer.ts = 2_000
        XCTAssertEqual(ChatInfoPresentation.newestOwnAvatar(in: [older, newer]), "/new.png")
        XCTAssertEqual(ChatInfoPresentation.newestOwnAvatar(in: [newer, older]), "/new.png")

        // My Participants row and my Shared Media badge use it; someone else's never do.
        XCTAssertEqual(ChatInfoPresentation.participantAvatarPath(for: Member(userID: me, name: "Me"), ownAvatarPath: "/own.png"), "/own.png")
        XCTAssertEqual(ChatInfoPresentation.participantAvatarPath(for: Member(userID: "@bob:courier.local", name: "Bob"), ownAvatarPath: "/own.png"), "")
        XCTAssertEqual(ChatInfoPresentation.participantAvatarPath(for: Member(userID: me, name: "Me", avatarPath: "/theirs.png"), ownAvatarPath: "/own.png"), "/theirs.png")
        let bare = makeEvent(id: "$b", msgtype: "m.image", sender: me, senderName: "", mine: true)
        XCTAssertEqual(ChatInfoPresentation.mediaSender(for: bare, members: [], ownAvatarPath: "/own.png")?.avatarPath, "/own.png")
        XCTAssertEqual(ChatInfoPresentation.mediaSender(for: bare, members: [], ownAvatarPath: "")?.avatarPath, "")
        let other = makeEvent(id: "$o", msgtype: "m.image")
        XCTAssertEqual(ChatInfoPresentation.mediaSender(for: other, members: [], ownAvatarPath: "/own.png")?.avatarPath, "")
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
        var linkPreviewWithBeeper = Event(
            eventID: "$lp",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice",
            mine: false,
            type: "m.room.message",
            content: .object([
                "msgtype": .string("m.text"),
                "body": .string("https://example.com"),
                "com.beeper.linkpreviews": .array([.object(["url": .string("https://example.com")])]),
            ]),
            ts: 1_700_000_000_000,
            seq: 2,
            status: .sent,
            linkPreviews: [LinkPreviewItem(matchedURL: "https://example.com")]
        )
        linkPreviewWithBeeper.linkPreviews = [LinkPreviewItem(matchedURL: "https://example.com")]
        let sticker = Event(
            eventID: "$stk",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice",
            mine: false,
            type: "m.sticker",
            content: .object(["msgtype": .string("m.image"), "body": .string("sticker")]),
            ts: 1_700_000_000_000,
            seq: 3,
            status: .sent
        )
        let file = makeEvent(id: "$file", msgtype: "m.file")
        let audio = makeEvent(id: "$aud", msgtype: "m.audio")
        let notice = makeEvent(id: "$notice", msgtype: "m.notice")
        let viewOnceImg = makeEvent(id: "$vo", msgtype: "m.image", viewOnce: true)
        let contentViewOnceImg = Event(
            eventID: "$vo2",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice",
            mine: false,
            type: "m.room.message",
            content: .object([
                "msgtype": .string("m.image"),
                "body": .string("secret.jpg"),
                "com.beeper.view_once": .bool(true),
            ]),
            ts: 1_700_000_000_000,
            seq: 4,
            status: .sent
        )

        var tenMedia: [Event] = []
        for idx in 1...10 {
            tenMedia.append(makeEvent(id: "$m\(idx)", msgtype: idx.isMultiple(of: 3) ? "m.video" : "m.image"))
        }

        let filtered = ChatInfoPresentation.sharedMediaEvents([
            img,
            linkPreviewText,
            linkPreviewWithBeeper,
            vid,
            sticker,
            file,
            audio,
            notice,
            viewOnceImg,
            contentViewOnceImg,
        ])
        XCTAssertEqual(filtered.map(\.eventID), ["$img", "$vid"])

        let mixedTen = ChatInfoPresentation.sharedMediaEvents(
            tenMedia + [linkPreviewText, linkPreviewWithBeeper, sticker, file, viewOnceImg]
        )
        XCTAssertEqual(mixedTen.count, 10, "Shared Media count must reflect only image/video events and exclude link previews")
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
            ChatInfoPresentation.MediaSender(name: "Alice Example", initials: "A", avatarPath: "/tmp/alice.png", identity: "@alice:courier.local")
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
            ChatInfoPresentation.MediaSender(name: "Bob Builder", initials: "B", avatarPath: "/tmp/bob.png", identity: "@bob:courier.local")
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

    // MARK: - Header avatar precedence & archive decision

    func testDisplayAvatarPathPrefersLocalAvatarOverNetworkAvatar() {
        let both = RoomInfoResult(
            roomID: "!r1",
            name: "Group",
            remoteName: "Group",
            avatarPath: "/tmp/network.png",
            localAvatarURI: "/tmp/local.png",
            network: "whatsapp",
            isDirect: false,
            features: .noFeatures
        )
        XCTAssertEqual(ChatInfoPresentation.displayAvatarPath(for: both), "/tmp/local.png")

        let networkOnly = RoomInfoResult(
            roomID: "!r2",
            name: "Group",
            remoteName: "Group",
            avatarPath: "/tmp/network.png",
            localAvatarURI: "",
            network: "whatsapp",
            isDirect: false,
            features: .noFeatures
        )
        XCTAssertEqual(ChatInfoPresentation.displayAvatarPath(for: networkOnly), "/tmp/network.png")

        let neither = RoomInfoResult(
            roomID: "!r3",
            name: "Group",
            remoteName: "Group",
            avatarPath: "",
            localAvatarURI: "",
            network: "whatsapp",
            isDirect: false,
            features: .noFeatures
        )
        XCTAssertEqual(ChatInfoPresentation.displayAvatarPath(for: neither), "")
    }

    func testShouldArchiveDecisions() {
        func makeRow(_ id: String, archived: Bool) -> InboxRow {
            InboxRow(
                roomID: id,
                network: "whatsapp",
                name: id,
                avatarPath: "",
                isDirect: true,
                lastTS: 1,
                preview: "",
                previewKind: .text,
                previewMine: false,
                unread: 0,
                muted: false,
                archived: archived
            )
        }

        XCTAssertTrue(ChatInfoPresentation.shouldArchive([]), "empty target list defaults to archive")
        XCTAssertTrue(ChatInfoPresentation.shouldArchive([makeRow("!a", archived: false)]), "unarchived row -> archive")
        XCTAssertTrue(
            ChatInfoPresentation.shouldArchive([makeRow("!a", archived: true), makeRow("!b", archived: false)]),
            "mixed rows -> archive"
        )
        XCTAssertFalse(ChatInfoPresentation.shouldArchive([makeRow("!a", archived: true)]), "all archived (single) -> unarchive")
        XCTAssertFalse(
            ChatInfoPresentation.shouldArchive([makeRow("!a", archived: true), makeRow("!b", archived: true)]),
            "all archived (multiple) -> unarchive"
        )
    }
}
