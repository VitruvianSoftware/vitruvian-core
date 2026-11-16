// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// How a row reads: its time, initials, preview label, unread count and network badge.
final class InboxPresentationTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    /// Friday 16 October 2026, 15:30 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_792_164_600) }

    private func time(daysAgo days: Int, hour: Int = 9, minute: Int = 5) -> Int64 {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private func text(_ ms: Int64) -> String {
        plain(RelativeTime.text(forMillis: ms, now: now, calendar: calendar, locale: locale))
    }

    /// ICU puts a narrow no-break space before AM and PM.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func row(_ json: [String: Any]) throws -> InboxRow {
        try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testTodayShowsTheTimeOfDay() {
        XCTAssertEqual(text(time(daysAgo: 0)), "9:05 AM")
        // The locale decides how: 24 hours in Germany.
        XCTAssertEqual(plain(RelativeTime.text(forMillis: time(daysAgo: 0, hour: 15), now: now, calendar: calendar,
                                               locale: Locale(identifier: "de_DE"))), "15:05")
    }

    func testYesterdayIsSaidAsSuch() {
        XCTAssertEqual(text(time(daysAgo: 1)), "Yesterday")
    }

    func testTwoToSixDaysShowTheWeekday() {
        XCTAssertEqual(text(time(daysAgo: 2)), "Wednesday")
        XCTAssertEqual(text(time(daysAgo: 6)), "Saturday")
    }

    func testEarlierThisYearShowsMonthAndDay() {
        XCTAssertEqual(text(time(daysAgo: 7)), "October 9")
        XCTAssertEqual(text(time(daysAgo: 200)), "March 30")
        XCTAssertEqual(plain(RelativeTime.text(forMillis: time(daysAgo: 7), now: now, calendar: calendar,
                                               locale: Locale(identifier: "en_GB"))), "9 October")
    }

    func testBeforeThisYearShowsTheYear() {
        XCTAssertEqual(text(time(daysAgo: 400)), "Sep 11, 2025")
        XCTAssertEqual(plain(RelativeTime.text(forMillis: time(daysAgo: 400), now: now, calendar: calendar,
                                               locale: Locale(identifier: "en_GB"))), "11 Sep 2025")
    }

    func testNoTimeAndTheFutureAreHandled() {
        XCTAssertEqual(text(0), "", "a chat with no message yet shows no time")
        // A clock a little ahead is still today; a day ahead is a date, not a weekday.
        XCTAssertEqual(text(time(daysAgo: 0, hour: 23, minute: 59)), "11:59 PM")
        XCTAssertEqual(text(time(daysAgo: -1)), "October 17")
    }

    func testFormattersAreKeptNotBuiltPerRow() {
        _ = text(time(daysAgo: 0))
        _ = text(time(daysAgo: 2))
        _ = text(time(daysAgo: 9))
        _ = text(time(daysAgo: 400))
        let kept = RelativeTime.cachedFormatterCount
        for index in 0 ..< 500 { _ = text(time(daysAgo: index % 12)) }
        XCTAssertEqual(RelativeTime.cachedFormatterCount, kept, "500 rows, no new formatter")
        XCTAssertEqual(text(time(daysAgo: 2)), "Wednesday")
    }

    func testTheTimeFollowsNow() {
        // The same message reads as today's time in the evening and as "Yesterday" the next morning.
        let sent = time(daysAgo: 0)
        XCTAssertEqual(text(sent), "9:05 AM")
        let tomorrow = now.addingTimeInterval(24 * 3600)
        XCTAssertEqual(RelativeTime.text(forMillis: sent, now: tomorrow, calendar: calendar, locale: locale), "Yesterday")
    }

    func testInitials() {
        XCTAssertEqual(InboxRow.initials(of: "Ada Lovelace"), "AL")
        XCTAssertEqual(InboxRow.initials(of: "ada"), "A")
        XCTAssertEqual(InboxRow.initials(of: "  grace   brewster   hopper "), "GB", "two letters at most")
        XCTAssertEqual(InboxRow.initials(of: "Zoë"), "Z")
        XCTAssertEqual(InboxRow.initials(of: ""), "?")
        XCTAssertEqual(InboxRow.initials(of: "+1 555 0100"), "+5", "a number has no letters, so its characters stand in")
    }

    func testPreviewLabelsAndText() throws {
        let image = try row(room("!a", ts: 1, preview: "", kind: "image"))
        XCTAssertEqual(image.previewLabel, .image)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "video")).previewLabel, .video)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "audio")).previewLabel, .voiceNote)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "file")).previewLabel, .file)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "sticker")).previewLabel, .sticker)
        XCTAssertNil(try row(room("!a", ts: 1, kind: "text")).previewLabel)
        XCTAssertNil(try row(room("!a", ts: 1, kind: "")).previewLabel)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "poll")).previewLabel, .poll)
        XCTAssertEqual(PreviewLabel.poll.title, "Poll")
        // Ruling 40: a timer-change note previews in Vitruvian Courier's words, never the bridge's English (the engine sends no
        // text for it).
        let note = try row(room("!a", ts: 1, preview: "", kind: "timer_change"))
        XCTAssertEqual(note.previewLabel, .timerChange)
        XCTAssertEqual(PreviewLabel.timerChange.title, "Disappearing messages changed")
        XCTAssertNil(try row(room("!a", ts: 1, kind: "location")).previewLabel, "a kind from a newer engine is just text")
    }

    func testUnreadBadge() throws {
        XCTAssertNil(try row(room("!a", ts: 1, unread: 0)).unreadBadge)
        XCTAssertEqual(try row(room("!a", ts: 1, unread: 7)).unreadBadge, "7")
        XCTAssertEqual(try row(room("!a", ts: 1, unread: 99)).unreadBadge, "99")
        XCTAssertEqual(try row(room("!a", ts: 1, unread: 100)).unreadBadge, "99+")
    }

    func testEveryNetworkHasANeutralBadge() {
        var seen = Set<String>()
        let networks = [
            "whatsapp", "signal", "telegram", "slack", "gmessages", "gchat",
            "discord", "facebook", "instagram", "twitter", "linkedin", "gvoice", "bluesky",
            "imessage",
        ]
        for network in networks {
            let appearance = NetworkAppearance.of(network)
            XCTAssertNotEqual(appearance, NetworkAppearance.fallback, network)
            XCTAssertTrue(appearance.symbol.hasSuffix(".fill") || !appearance.symbol.isEmpty)
            seen.insert("\(appearance.symbol)/\(appearance.red)/\(appearance.green)/\(appearance.blue)")
        }
        XCTAssertEqual(seen.count, networks.count, "each network is told apart")
        XCTAssertEqual(NetworkAppearance.of("a-network-added-later"), NetworkAppearance.fallback)
    }

    func testThreadPreviewWording() {
        let myReply = InboxRow(
            roomID: "!a", network: "signal", name: "Weekend Trail Crew", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "On my way", previewKind: .text,
            previewMine: true, unread: 0, muted: false, previewInThread: true
        )
        XCTAssertEqual(myReply.previewThreadPrefix, "You, in a thread: ")
        XCTAssertEqual(myReply.previewBody, "On my way")
        XCTAssertEqual(myReply.formattedPreviewText, "You, in a thread: On my way")

        let groupReply = InboxRow(
            roomID: "!a", network: "signal", name: "Weekend Trail Crew", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "Sounds good", previewKind: .text,
            previewMine: false, unread: 1, muted: false, previewInThread: true
        )
        XCTAssertEqual(groupReply.previewThreadPrefix, "In a thread: ")
        XCTAssertEqual(groupReply.previewBody, "Sounds good")
        XCTAssertEqual(groupReply.formattedPreviewText, "In a thread: Sounds good")

        let groupReplyWithColon = InboxRow(
            roomID: "!a", network: "signal", name: "Weekend Trail Crew", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "Note: bring water", previewKind: .text,
            previewMine: false, unread: 1, muted: false, previewInThread: true
        )
        XCTAssertEqual(groupReplyWithColon.previewThreadPrefix, "In a thread: ")
        XCTAssertEqual(groupReplyWithColon.previewBody, "Note: bring water")
        XCTAssertEqual(groupReplyWithColon.formattedPreviewText, "In a thread: Note: bring water")

        let directReply = InboxRow(
            roomID: "!b", network: "signal", name: "Ann", avatarPath: "",
            isDirect: true, lastTS: 1, preview: "See you at 8", previewKind: .text,
            previewMine: false, unread: 1, muted: false, previewInThread: true
        )
        XCTAssertEqual(directReply.previewThreadPrefix, "Ann, in a thread: ")
        XCTAssertEqual(directReply.previewBody, "See you at 8")
        XCTAssertEqual(directReply.formattedPreviewText, "Ann, in a thread: See you at 8")

        let nonThread = InboxRow(
            roomID: "!b", network: "signal", name: "Ann", avatarPath: "",
            isDirect: true, lastTS: 1, preview: "See you at 8", previewKind: .text,
            previewMine: false, unread: 1, muted: false, previewInThread: false
        )
        XCTAssertNil(nonThread.previewThreadPrefix)
        XCTAssertEqual(nonThread.formattedPreviewText, "See you at 8")

        let unnamedRoomReply = InboxRow(
            roomID: "!c", network: "signal", name: "", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "Pinned map", previewKind: .text,
            previewMine: false, unread: 1, muted: false, previewInThread: true
        )
        XCTAssertEqual(unnamedRoomReply.previewThreadPrefix, "In a thread: ")
        XCTAssertEqual(unnamedRoomReply.formattedPreviewText, "In a thread: Pinned map")

        let mediaReply = InboxRow(
            roomID: "!d", network: "signal", name: "Ann", avatarPath: "",
            isDirect: true, lastTS: 1, preview: "", previewKind: .image,
            previewMine: false, unread: 1, muted: false, previewInThread: true
        )
        XCTAssertEqual(mediaReply.formattedPreviewText, "Ann, in a thread: Image")
    }

    func testChatDisplayTitleGroupCountsAndMemberSources() {
        let eddie = GroupTitleMember(userID: "@eddie", name: "Eddie Stecker")
        let kent = GroupTitleMember(userID: "@kent", name: "Kent Hua")
        let github = GroupTitleMember(userID: "@gh", name: "GitHub", isBot: true)
        let alice = GroupTitleMember(userID: "@alice", name: "Alice Smith")
        let bob = GroupTitleMember(userID: "@bob", name: "Bob Jones")
        let me = GroupTitleMember(userID: Timeline.meUserID, name: "James Nguyen")

        // 2 members (confirmed by member list, and member list excluding me).
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua",
                members: [eddie, kent]
            ),
            "Eddie & Kent"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "James Nguyen, Eddie Stecker, Kent Hua",
                members: [me, eddie, kent]
            ),
            "Eddie & Kent"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "eddie stecker, KENT HUA",
                members: [eddie, kent]
            ),
            "Eddie & Kent"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "",
                members: [me, eddie, kent]
            ),
            "Eddie & Kent"
        )

        // 3 members.
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub",
                members: [eddie, kent, github]
            ),
            "Eddie, Kent & GitHub"
        )
        let threeMemberRow = InboxRow(
            roomID: "!g3", network: "slack", name: "Eddie Stecker, Kent Hua, GitHub", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "", previewKind: .none, previewMine: false,
            unread: 0, muted: false,
            memberPreview: [
                RowMember(userID: "@eddie", name: "Eddie Stecker"),
                RowMember(userID: "@kent", name: "Kent Hua"),
                RowMember(userID: "@gh", name: "GitHub"),
            ]
        )
        XCTAssertEqual(threeMemberRow.displayTitle, "Eddie, Kent & GitHub")

        // 4+ members (full list, bridge "and N others", Oxford-comma ", and N others", and complete member list).
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub, Alice Smith",
                members: [eddie, kent, github, alice]
            ),
            "Eddie, Kent, GitHub & 1 other"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub, Alice Smith, Bob Jones",
                members: [eddie, kent, github, alice, bob]
            ),
            "Eddie, Kent, GitHub & 2 others"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub and 2 others",
                members: [eddie, kent, github],
                isCompleteMemberList: false
            ),
            "Eddie, Kent, GitHub & 2 others"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub, and 2 others",
                members: [eddie, kent, github],
                isCompleteMemberList: false
            ),
            "Eddie, Kent, GitHub & 2 others"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub",
                members: [me, eddie, kent, github, alice, bob],
                isCompleteMemberList: true
            ),
            "Eddie, Kent, GitHub & 2 others"
        )

        // Two shown names + 1 other / N others via .stringsdict pluralization.
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua",
                members: [me, eddie, kent, alice],
                isCompleteMemberList: true
            ),
            "Eddie, Kent & Alice"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua and 1 other",
                members: [eddie, kent],
                isCompleteMemberList: false
            ),
            "Eddie, Kent & 1 other"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua and 3 others",
                members: [eddie, kent],
                isCompleteMemberList: false
            ),
            "Eddie, Kent & 3 others"
        )
    }

    func testChatDisplayTitleLeavesCustomTitlesDirectChatsAndBotsUntouched() {
        let members = [
            GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
            GroupTitleMember(userID: "@kent", name: "Kent Hua"),
            GroupTitleMember(userID: "@gh", name: "GitHub"),
        ]

        // Explicit custom titles, channels, local overrides, partial/unconfirmed member lists, and 1:1 chats are never rewritten.
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "Weekend Hikers", members: members, isCompleteMemberList: true),
            "Weekend Hikers"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "#general", members: members, isCompleteMemberList: true),
            "#general"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "Research & Development", members: members, isCompleteMemberList: true),
            "Research & Development"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "Design, Product, Eng, QA", members: members, isCompleteMemberList: false),
            "Design, Product, Eng, QA"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub, Alice Smith",
                members: members,
                isCompleteMemberList: false
            ),
            "Eddie Stecker, Kent Hua, GitHub, Alice Smith"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "Eddie Stecker, Kent Hua", localName: "My Squad", members: members),
            "Eddie Stecker, Kent Hua"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "Stecker, Eddie", isDirect: true, members: members),
            "Stecker, Eddie"
        )
        // First-name-only segment cannot match a full display name "Eddie Stecker".
        XCTAssertEqual(
            ChatDisplayTitle.format(name: "Eddie, Kent, GitHub", members: members, isCompleteMemberList: true),
            "Eddie, Kent, GitHub"
        )

        // Single-word names and bot names stay intact.
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "GitHub, Deploy Bot, Release Helper",
                members: [
                    GroupTitleMember(userID: "@gh", name: "GitHub"),
                    GroupTitleMember(userID: "@db", name: "Deploy Bot"),
                    GroupTitleMember(userID: "@rh", name: "Release Helper", isBot: true),
                ]
            ),
            "GitHub, Deploy Bot & Release Helper"
        )
    }

    @MainActor
    func testChatDisplayTitleNonLatinNamesDuplicatesAndRoomInfo() {
        // Non-Latin & diacritic names.
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "김민준, 이서연",
                members: [GroupTitleMember(name: "김민준"), GroupTitleMember(name: "이서연")]
            ),
            "김민준 & 이서연"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "田中 太郎, 佐藤 花子, 鈴木 一郎",
                members: [
                    GroupTitleMember(name: "田中 太郎"),
                    GroupTitleMember(name: "佐藤 花子"),
                    GroupTitleMember(name: "鈴木 一郎"),
                ]
            ),
            "田中, 佐藤 & 鈴木"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Élodie Moreau, Łukasz Kowalski",
                members: [
                    GroupTitleMember(name: "Élodie Moreau"),
                    GroupTitleMember(name: "Łukasz Kowalski"),
                ]
            ),
            "Élodie & Łukasz"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "李小明, 王芳, 张伟, 陈静",
                members: [
                    GroupTitleMember(name: "李小明"),
                    GroupTitleMember(name: "王芳"),
                    GroupTitleMember(name: "张伟"),
                    GroupTitleMember(name: "陈静"),
                ]
            ),
            "李小明, 王芳, 张伟 & 1 other"
        )

        // Duplicates: repeated identical member collapses; distinct members sharing a first name disambiguate.
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, Eddie Stecker",
                members: [
                    GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
                    GroupTitleMember(userID: "@kent", name: "Kent Hua"),
                ]
            ),
            "Eddie & Kent"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "",
                members: [
                    GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
                    GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
                    GroupTitleMember(userID: "@kent", name: "Kent Hua"),
                ]
            ),
            "Eddie & Kent"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Eddie Wu",
                members: [
                    GroupTitleMember(userID: "@eddie1", name: "Eddie Stecker"),
                    GroupTitleMember(userID: "@eddie2", name: "Eddie Wu"),
                ]
            ),
            "Eddie S. & Eddie W."
        )

        // RoomInfoResult.displayTitle & ConversationModel.applyingDisplayTitle for Chat Info.
        let unnamedInfo = RoomInfoResult(
            roomID: "!grp",
            name: "Eddie Stecker, Kent Hua, GitHub",
            remoteName: "Eddie Stecker, Kent Hua, GitHub",
            network: "slack",
            isDirect: false,
            members: [
                Member(userID: "@eddie", name: "Eddie Stecker"),
                Member(userID: "@kent", name: "Kent Hua"),
                Member(userID: "@gh", name: "GitHub", isBot: true),
            ],
            features: .noFeatures
        )
        XCTAssertEqual(unnamedInfo.displayTitle, "Eddie, Kent & GitHub")
        let appliedUnnamed = ConversationModel.applyingDisplayTitle(to: unnamedInfo)
        XCTAssertEqual(appliedUnnamed.name, "Eddie, Kent & GitHub")
        XCTAssertEqual(appliedUnnamed.remoteName, "Eddie, Kent & GitHub")

        let customInfo = RoomInfoResult(
            roomID: "!custom",
            name: "Design Systems",
            remoteName: "Design Systems",
            network: "slack",
            isDirect: false,
            members: unnamedInfo.members,
            features: .noFeatures
        )
        XCTAssertEqual(customInfo.displayTitle, "Design Systems")
        XCTAssertEqual(ConversationModel.applyingDisplayTitle(to: customInfo).name, "Design Systems")
    }

    func testChatDisplayTitleDoesNotShortenCustomTitlesWithoutMemberList() {
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Dev Team, Ops Team",
                isDirect: false,
                members: [],
                isCompleteMemberList: false
            ),
            "Dev Team, Ops Team"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Research Team, Sales & Marketing",
                isDirect: false,
                members: [],
                isCompleteMemberList: false
            ),
            "Research Team, Sales & Marketing"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Smith, Jones & Co",
                isDirect: false,
                members: [],
                isCompleteMemberList: true
            ),
            "Smith, Jones & Co"
        )

        let devOpsRow = InboxRow(
            roomID: "!g1", network: "slack", name: "Dev Team, Ops Team", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "", previewKind: .none, previewMine: false,
            unread: 0, muted: false
        )
        XCTAssertEqual(devOpsRow.displayTitle, "Dev Team, Ops Team")

        let researchRow = InboxRow(
            roomID: "!g2", network: "slack", name: "Research Team, Sales & Marketing", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "", previewKind: .none, previewMine: false,
            unread: 0, muted: false
        )
        XCTAssertEqual(researchRow.displayTitle, "Research Team, Sales & Marketing")

        let firmRow = InboxRow(
            roomID: "!g3", network: "slack", name: "Smith, Jones & Co", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "", previewKind: .none, previewMine: false,
            unread: 0, muted: false
        )
        XCTAssertEqual(firmRow.displayTitle, "Smith, Jones & Co")
    }

    func testChatDisplayTitleKeepsGenuineBridgeListsWithoutMemberList() {
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie, Kent, GitHub",
                members: [],
                isCompleteMemberList: false
            ),
            "Eddie, Kent, GitHub"
        )
        let singleWordRow = InboxRow(
            roomID: "!g4", network: "slack", name: "Eddie, Kent, GitHub", avatarPath: "",
            isDirect: false, lastTS: 1, preview: "", previewKind: .none, previewMine: false,
            unread: 0, muted: false
        )
        XCTAssertEqual(singleWordRow.displayTitle, "Eddie, Kent, GitHub")

        // When the member list confirms each segment, both single-word and multi-word bridge lists shorten.
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie, Kent, GitHub",
                members: [
                    GroupTitleMember(userID: "@eddie", name: "Eddie"),
                    GroupTitleMember(userID: "@kent", name: "Kent"),
                    GroupTitleMember(userID: "@gh", name: "GitHub", isBot: true),
                ],
                isCompleteMemberList: true
            ),
            "Eddie, Kent & GitHub"
        )
        XCTAssertEqual(
            ChatDisplayTitle.format(
                name: "Eddie Stecker, Kent Hua, GitHub",
                members: [
                    GroupTitleMember(userID: "@eddie", name: "Eddie Stecker"),
                    GroupTitleMember(userID: "@kent", name: "Kent Hua"),
                    GroupTitleMember(userID: "@gh", name: "GitHub", isBot: true),
                ],
                isCompleteMemberList: true
            ),
            "Eddie, Kent & GitHub"
        )
    }

    @MainActor
    func testInboxAndConversationShortenGroupTitleAfterFetchingFullRoomMembers() async throws {
        let botGroup = chatRow("!botgrp", name: "Eddie Stecker, Kent Hua, GitHub", network: "slack", direct: false)
        var partialPreviewRow = botGroup
        partialPreviewRow.memberPreview = [
            RowMember(userID: "@eddie", name: "Eddie Stecker"),
            RowMember(userID: "@kent", name: "Kent Hua"),
        ]
        // Without GitHub in memberPreview, InboxRow.displayTitle does not shorten on its own.
        XCTAssertEqual(partialPreviewRow.displayTitle, "Eddie Stecker, Kent Hua, GitHub")

        let h = try await startConversation(
            ["!botgrp": [textEvent(id: "$m1", room: "!botgrp", at: 1)]],
            rows: ["!botgrp": partialPreviewRow]
        )
        defer { Task { await h.stop() } }
        h.script.roomMembers["!botgrp"] = [
            [
                "user_id": "@eddie",
                "name": "Eddie Stecker",
                "avatar_path": "",
                "power_level": 0,
                "is_admin": false,
                "identifiers": [String](),
                "tz": "",
                "is_bot": false,
            ],
            [
                "user_id": "@kent",
                "name": "Kent Hua",
                "avatar_path": "",
                "power_level": 0,
                "is_admin": false,
                "identifiers": [String](),
                "tz": "",
                "is_bot": false,
            ],
            [
                "user_id": "@gh",
                "name": "GitHub",
                "avatar_path": "",
                "power_level": 0,
                "is_admin": false,
                "identifiers": [String](),
                "tz": "",
                "is_bot": true,
            ],
        ]

        let inbox = InboxModel(
            appModel: h.app,
            preferences: InboxPreferences(defaults: h.store.defaults),
            window: 0,
            sleep: { _ in }
        )
        inbox.setSnapshotRowsForTesting([partialPreviewRow])
        try await h.open("!botgrp")
        try await waitUntil {
            inbox.displayTitle(for: partialPreviewRow) == "Eddie, Kent & GitHub"
                && h.conversation.openChatDisplayTitle == "Eddie, Kent & GitHub"
        }
        XCTAssertEqual(inbox.displayTitle(for: partialPreviewRow), "Eddie, Kent & GitHub")
        XCTAssertEqual(h.conversation.openChatDisplayTitle, "Eddie, Kent & GitHub")
    }
}
