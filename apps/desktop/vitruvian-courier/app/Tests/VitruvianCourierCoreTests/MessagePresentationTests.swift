// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// What the bubbles, the message menu and the formatting bar show, worked out before any view draws it.
final class MessagePresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_600_600)

    private func entity(_ kind: TextEntity.Kind, _ offset: Int, _ length: Int, url: String? = nil,
                        user: String? = nil) -> TextEntity {
        TextEntity(kind: kind, offset: offset, length: length, url: url, userID: user)
    }

    private func message(_ id: String = "$1", mine: Bool, body: String = "hello", status: EventStatus = .sent,
                         thread: ThreadSummary? = nil, bookmarked: Bool = false, edited: Bool = false,
                         minutesAgo: Int64 = 1) -> TimelineMessage {
        let ts = Int64(now.timeIntervalSince1970 * 1000) - minutesAgo * 60_000
        var events = [Event(eventID: id, roomID: "!a", sender: mine ? Timeline.meUserID : "@ann:example.test",
                            senderName: mine ? "me" : "Ann", mine: mine, type: "m.room.message",
                            content: .object(["msgtype": .string("m.text"), "body": .string(body)]), ts: ts, seq: 1,
                            status: status, bookmarked: bookmarked, thread: thread)]
        if edited {
            events.append(Event(eventID: "$e", roomID: "!a", sender: events[0].sender, senderName: "me", mine: mine,
                                type: "m.room.message",
                                content: .object([
                                    "msgtype": .string("m.text"), "body": .string("* changed"),
                                    "m.new_content": .object(["msgtype": .string("m.text"), "body": .string("changed")]),
                                    "m.relates_to": .object(["rel_type": .string("m.replace"), "event_id": .string(id)]),
                                ]), ts: ts + 1, seq: 2, status: .sent))
        }
        for case let .message(found) in Timeline.build(events: events, me: Timeline.meUserID, now: now) {
            return found
        }
        fatalError("no message")
    }

    private let whatsApp = ChatFeatures(reply: true, edit: true, editMaxAgeMS: 15 * 60_000, unsend: true,
                                        unsendMaxAgeMS: 2 * 86_400_000, formatting: [.bold, .italic, .link],
                                        source: .stored)

    // MARK: Rich text

    func testBlocksAndRunsFollowTheRanges() {
        // "Hi bold link @Ann\n> quoted\n• one\n• two\ncode()\nend"
        let text = "Hi bold link @Ann\nquoted\none\ntwo\ncode()\nend"
        let rich = RichText(text: text, entities: [
            entity(.bold, 3, 4), entity(.link, 8, 4, url: "https://example.test"),
            entity(.mention, 13, 4, user: "@ann:example.test"),
            entity(.blockquote, 18, 6), entity(.bulletList, 25, 7), entity(.pre, 33, 6),
        ])
        let blocks = RichTextLayout.blocks(of: rich)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph, .quote, .bulletList, .code, .paragraph])
        XCTAssertEqual(blocks[0].lines, [[
            RichTextLayout.Run(text: "Hi "), RichTextLayout.Run(text: "bold", bold: true), RichTextLayout.Run(text: " "),
            RichTextLayout.Run(text: "link", link: URL(string: "https://example.test")), RichTextLayout.Run(text: " "),
            RichTextLayout.Run(text: "@Ann", mention: "@ann:example.test"),
        ]])
        XCTAssertEqual(blocks[1].lines, [[RichTextLayout.Run(text: "quoted")]])
        XCTAssertEqual(blocks[2].lines.count, 2, "each item a line")
        XCTAssertEqual(blocks[3].lines, [[RichTextLayout.Run(text: "code()")]])
        XCTAssertEqual(blocks[4].lines, [[RichTextLayout.Run(text: "end")]])
    }

    func testOverlappingStylesAndSpoilersAreRunsOfTheirOwn() {
        let rich = RichText(text: "abcdef", entities: [entity(.bold, 0, 4), entity(.italic, 2, 4), entity(.spoiler, 5, 1)])
        let runs = RichTextLayout.blocks(of: rich)[0].lines[0]
        XCTAssertEqual(runs, [
            RichTextLayout.Run(text: "ab", bold: true), RichTextLayout.Run(text: "cd", bold: true, italic: true),
            RichTextLayout.Run(text: "e", italic: true), RichTextLayout.Run(text: "f", italic: true, spoiler: true),
        ])
    }

    func testTwoListsInARowAreTwoBlocksAndAnEmptyLineStaysAParagraphLine() {
        let rich = RichText(text: "a\nb\n\nc", entities: [entity(.orderedList, 0, 1), entity(.orderedList, 2, 1)])
        let blocks = RichTextLayout.blocks(of: rich)
        XCTAssertEqual(blocks.map(\.kind), [.orderedList, .orderedList, .paragraph])
        XCTAssertEqual(blocks[2].lines, [[], [RichTextLayout.Run(text: "c")]])
        XCTAssertEqual(RichTextLayout.blocks(of: RichText(text: "")), [])
    }

    // MARK: The message menu

    private func moreItem(in sections: [[MessageMenuItem]]) -> MessageMenuItem? {
        sections.flatMap { $0 }.first { $0.command == .more }
    }

    func testTheMenuIsInItsOrderWithGreyedLinesAndInfo() {
        let mine = message(mine: true, edited: true, minutesAgo: 30)
        let available = MessageActions.available(for: mine, in: whatsApp, network: "whatsapp", now: now)
        let sections = MessageMenu.sections(for: mine, available: available, features: whatsApp,
                                            disappearsIn: "Disappears in 1 hour", time: { _ in "14:02" })
        XCTAssertEqual(sections.map { $0.map(\.title) }, [
            ["Reply…", "React…", "Edit…"], ["Copy", "Forward…"],
            ["Bookmark", "Mark as Unread", "More"], ["Unsend", "Delete for Me…"],
            ["Sent 14:02", "Disappears in 1 hour"],
        ])
        XCTAssertEqual(moreItem(in: sections)?.children.map(\.title), ["Copy with Timestamp", "Edit History"])
        let edit = sections[0][2]
        XCTAssertFalse(edit.isEnabled, "30 minutes is past WhatsApp's 15")
        XCTAssertEqual(edit.help, "WhatsApp only lets you edit for 15 minutes")
        XCTAssertEqual(edit.key, .commandT)
        let markUnread = sections[2][1]
        XCTAssertTrue(markUnread.isEnabled)
        XCTAssertEqual(markUnread.help, "From this message. On this Mac only.")
        XCTAssertTrue(sections[4].allSatisfy { !$0.isEnabled && $0.command == .info })

        // Someone else's, in a group: Reply Privately… after Reply….
        let theirs = message(mine: false, minutesAgo: 1)
        let inGroup = MessageActions.available(for: theirs, in: whatsApp, network: "whatsapp", now: now,
                                               isDirect: false, networkRunning: true)
        let groupSections = MessageMenu.sections(for: theirs, available: inGroup, features: whatsApp, disappearsIn: nil,
                                                 time: { _ in "14:02" })
        XCTAssertEqual(groupSections.first?.map(\.title), ["Reply…", "Reply Privately…", "React…"])
    }

    func testSomeoneElsesThreadRootOffersShowRepliesAndInsertAsDraft() {
        let slack = ChatFeatures(thread: true, replyIsThread: true, unsend: true, source: .stored)
        let root = message(mine: false, body: "see https://example.test",
                           thread: ThreadSummary(replies: 2, lastTS: 0, lastSenders: ["Bo"]), bookmarked: true)
        let available = MessageActions.available(for: root, in: slack, network: "slack", now: now)
        let sections = MessageMenu.sections(for: root, available: available, features: slack, disappearsIn: nil,
                                            time: { _ in "9:00" })
        let titles = sections.map { $0.map(\.title) }
        XCTAssertEqual(titles, [
            ["Reply in Thread…", "Show Replies", "React…"],
            ["Copy", "Forward…"],
            ["Remove Bookmark", "Mark as Unread", "More"], ["Delete for Me…"], ["Received 9:00"],
        ])
        XCTAssertEqual(moreItem(in: sections)?.children.map(\.title),
                       ["Copy with Timestamp", "Insert as Draft", "Open Link"])
        let gm = ChatFeatures(reply: true, deleteReachesPhone: true, source: .stored)
        XCTAssertEqual(MessageMenu.title(of: .deleteForMe, features: gm), "Delete from This Mac and Your Phone…")
    }

    /// Everything the menu can hold at once, drawn in five sections: Reply first, then Copy/Forward, Bookmark/Unread/More,
    /// Unsend/Delete, and the greyed lines last.
    func testTheFullMenuIsFiveSectionsWithReplyFirstAndInfoLast() {
        let root = message(mine: true, body: "bonjour", thread: ThreadSummary(replies: 1, lastTS: 0, lastSenders: ["Bo"]),
                           edited: true)
        let available = MessageActions.available(for: root, in: whatsApp, network: "whatsapp", now: now)
        let sections = MessageMenu.sections(
            for: root, available: available, features: whatsApp, disappearsIn: "Disappears in 1 hour",
            time: { _ in "14:02" }, includeDiagnostics: true, isAIAvailable: true, responseLanguage: "English",
            translationLanguages: ["English", "Spanish"], canReadAloud: true)
        XCTAssertEqual(sections.map { $0.map(\.title) }, [
            ["Reply…", "Show Replies", "React…", "Edit…"],
            ["Copy", "Forward…"],
            ["Bookmark", "Mark as Unread", "More"],
            ["Unsend", "Delete for Me…"],
            ["Sent 14:02", "Disappears in 1 hour"],
        ])
        XCTAssertEqual(moreItem(in: sections)?.children.map(\.title), [
            "Copy with Timestamp", "Read Aloud", "Translate", "Translate Into…", "Edit History",
            "Report a Problem…", "Copy Message Details",
        ])
        XCTAssertLessThanOrEqual(sections.count, 5)
        XCTAssertEqual(sections.first?.first?.command, .action(.reply), "Reply is the first line")
        XCTAssertTrue(sections.last?.allSatisfy { $0.command == .info && !$0.isEnabled } ?? false)
    }

    /// Items that don't apply are absent, and a section with nothing left in it leaves no divider.
    func testItemsThatDontApplyAreAbsentAndEmptySectionsLeaveNoDivider() {
        let theirs = message(mine: false, body: "hello")
        let available = MessageActions.available(for: theirs, in: whatsApp, network: "whatsapp", now: now)
        let plain = MessageMenu.sections(for: theirs, available: available, features: whatsApp, disappearsIn: nil,
                                         time: { _ in "14:02" })
        let topTitles = plain.flatMap { $0.map(\.title) }
        let moreTitles = moreItem(in: plain)?.children.map(\.title) ?? []
        let allTitles = topTitles + moreTitles
        for absent in ["Edit…", "Unsend", "Show Replies", "Read Aloud", "Translate", "Report a Problem…",
                       "Copy Message Details", "Transcribe", "Edit History", "Open Link"]
        {
            XCTAssertFalse(allTitles.contains(absent), "\(absent) is not offered here: \(allTitles)")
        }
        XCTAssertEqual(moreTitles, ["Copy with Timestamp", "Insert as Draft"])
        XCTAssertTrue(plain.allSatisfy { !$0.isEmpty }, "no empty section, so no double divider")

        // Reading aloud and diagnostics each add their line inside More only when asked for.
        let more = MessageMenu.sections(for: theirs, available: available, features: whatsApp, disappearsIn: nil,
                                        time: { _ in "14:02" }, includeDiagnostics: true, canReadAloud: true)
        XCTAssertEqual(more.map { $0.map(\.title) }.dropLast().last, ["Delete for Me…"],
                       "someone else's message has nothing to unsend, so Delete for Me… is alone in the removing section")
        let moreChildren = moreItem(in: more)?.children ?? []
        XCTAssertTrue(moreChildren.contains { $0.command == .readAloud })
        XCTAssertTrue(moreChildren.contains { $0.command == .reportProblem })
        XCTAssertTrue(moreChildren.contains { $0.command == .copyMessageDetails })
    }

    /// Reply and Copy keep their shortcuts: Reply is ⌘R and its registry key, Copy is ⌘C. The rest keep theirs.
    func testTheMenuKeepsItsShortcuts() {
        let root = message(mine: true, body: "see https://example.test",
                           thread: ThreadSummary(replies: 1, lastTS: 0, lastSenders: ["Bo"]), minutesAgo: 1)
        let available = MessageActions.available(for: root, in: whatsApp, network: "whatsapp", now: now)
        let sections = MessageMenu.sections(for: root, available: available, features: whatsApp, disappearsIn: nil,
                                            time: { _ in "14:02" })
        let topItems = sections.flatMap { $0 }
        let allItems = topItems + (moreItem(in: sections)?.children ?? [])
        func key(_ title: String) -> MenuKey? { allItems.first { $0.title == title }?.key }
        XCTAssertEqual(key("Reply…"), .commandR)
        XCTAssertEqual(MenuKey.commandR.hotkeyID, "Message: Quote & Reply")
        XCTAssertEqual(key("Copy"), .commandC)
        XCTAssertEqual(key("Edit…"), .commandT)
        XCTAssertEqual(key("Show Replies"), .commandDown)
        XCTAssertEqual(key("Open Link"), .commandShiftH)
        XCTAssertEqual(key("Forward…"), .commandShiftF)
    }

    func testAMessageNotSentHasNoSentAtLine() {
        let failed = message(mine: true, status: .failed)
        let available = MessageActions.available(for: failed, in: whatsApp, network: "whatsapp", now: now)
        let sections = MessageMenu.sections(for: failed, available: available, features: whatsApp, disappearsIn: nil,
                                            time: { _ in "now" })
        XCTAssertEqual(sections.map { $0.map(\.title) }, [["Copy"], ["More"]])
        XCTAssertEqual(moreItem(in: sections)?.children.map(\.title), ["Copy with Timestamp"])
    }

    func testTimestampLineOmitsDuplicateAt() {
        let mine = message(mine: true)
        let theirs = message(mine: false)
        let formatted = "Nov 19, 2026 at 11:47 PM"
        let mineSections = MessageMenu.sections(
            for: mine,
            available: MessageActions.available(for: mine, in: whatsApp, network: "whatsapp", now: now),
            features: whatsApp,
            disappearsIn: nil,
            time: { _ in formatted }
        )
        let theirSections = MessageMenu.sections(
            for: theirs,
            available: MessageActions.available(for: theirs, in: whatsApp, network: "whatsapp", now: now),
            features: whatsApp,
            disappearsIn: nil,
            time: { _ in formatted }
        )
        XCTAssertEqual(mineSections.last?.first?.title, "Sent Nov 19, 2026 at 11:47 PM")
        XCTAssertEqual(theirSections.last?.first?.title, "Received Nov 19, 2026 at 11:47 PM")
    }

    // MARK: The formatting bar

    func testTheBarGreysWhatTheChatDoesntKeep() {
        let items = FormattingBar.items(features: whatsApp, network: "whatsapp")
        XCTAssertEqual(items.map(\.title), ["Bold", "Italic", "Strikethrough", "Code", "Code Block", "Quote",
                                           "Bulleted List", "Numbered List", "Link", "Spoiler"])
        XCTAssertEqual(items.filter(\.isEnabled).map(\.kind), [.bold, .italic, .link])
        XCTAssertEqual(items[0].help, "Bold (⌘B)")
        XCTAssertEqual(items[9].help, "Spoiler (Unavailable for WhatsApp)")
        XCTAssertFalse(items.contains { $0.keys.contains("⌘K") || $0.keys.contains("⌘F") }, "⌘K and ⌘F are search's")

        let unknown = FormattingBar.items(features: .noFeatures, network: "beeper-xyz")
        XCTAssertEqual(unknown[0].help, "Not available until this network connects", "no raw id reaches a person")
        let stranger = ChatFeatures(source: .stored)
        XCTAssertEqual(FormattingBar.items(features: stranger, network: "beeper-xyz")[0].help,
                       "Bold (Unavailable for this network)")
    }

    // MARK: Lines

    func testThreadPollAndVoteLines() {
        XCTAssertEqual(MessageLines.replies(ThreadSummary(replies: 1, lastTS: 0, lastSenders: ["Ann"])), "1 Reply")
        XCTAssertEqual(MessageLines.replies(ThreadSummary(replies: 4, lastTS: 0, lastSenders: [])), "4 Replies")
        XCTAssertEqual(MessageLines.repliers(ThreadSummary(replies: 1, lastTS: 0, lastSenders: ["Ann"])), "Ann")
        XCTAssertEqual(MessageLines.repliers(ThreadSummary(replies: 3, lastTS: 0, lastSenders: ["Ann", "Bo"])),
                       "Ann & 1 other")
        XCTAssertEqual(MessageLines.repliers(ThreadSummary(replies: 5, lastTS: 0, lastSenders: ["Ann", "Bo", "Cy"])),
                       "Ann & 2 others")
        XCTAssertNil(MessageLines.repliers(ThreadSummary(replies: 0, lastTS: 0, lastSenders: [])))

        // Replies not read in the thread: "2 new", and what VoiceOver reads.
        let read = ThreadSummary(replies: 3, lastTS: 0, lastSenders: ["Ann"])
        XCTAssertNil(MessageLines.newReplies(read))
        XCTAssertEqual(MessageLines.summaryAccessibilityLabel(read), "3 Replies, show replies")
        let new = ThreadSummary(replies: 3, lastTS: 0, lastSenders: ["Ann"], unread: 2)
        XCTAssertEqual(MessageLines.newReplies(new), "2 new")
        XCTAssertEqual(MessageLines.summaryAccessibilityLabel(new), "3 Replies, 2 new, show replies")
        let mention = ThreadSummary(replies: 3, lastTS: 0, lastSenders: ["Ann"], unread: 1, unreadMentionsMe: true)
        XCTAssertEqual(MessageLines.summaryAccessibilityLabel(mention), "3 Replies, 1 new, mentions you, show replies")
        XCTAssertEqual(MessageLines.votes(1), "1 vote")
        XCTAssertEqual(MessageLines.votes(3), "3 votes")

        var poll = PollTally(question: "Lunch?", options: [PollOption(id: "a", text: "Soup", votes: 3),
                                                          PollOption(id: "b", text: "Salad", votes: 1)],
                             maxSelections: 1, voters: 4, mine: [], ended: false)
        XCTAssertEqual(MessageLines.pollHint(poll), "Select one option")
        XCTAssertEqual(MessageLines.share(of: poll.options[0], in: poll), 0.75)
        poll.maxSelections = 2
        XCTAssertEqual(MessageLines.pollHint(poll), "Select one or more options")
        poll.ended = true
        XCTAssertEqual(MessageLines.pollHint(poll), "Poll ended")
        poll.options = [PollOption(id: "a", text: "Soup", votes: 0)]
        XCTAssertEqual(MessageLines.share(of: poll.options[0], in: poll), 0)
    }

    func testTheLinkDialogTakesWebAndMailAddressesOnly() {
        XCTAssertEqual(LinkAddress.url(from: "example.test/a_b")?.absoluteString, "https://example.test/a_b")
        XCTAssertEqual(LinkAddress.url(from: " http://example.test ")?.absoluteString, "http://example.test")
        XCTAssertEqual(LinkAddress.url(from: "mailto:ann@example.test")?.absoluteString, "mailto:ann@example.test")
        XCTAssertNil(LinkAddress.url(from: "javascript:alert(1)"))
        XCTAssertNil(LinkAddress.url(from: "file:///etc/hosts"))
        XCTAssertNil(LinkAddress.url(from: "two words"))
        XCTAssertNil(LinkAddress.url(from: ""))
    }

    func testAHostAndPortIsAWebAddress() {
        XCTAssertEqual(LinkAddress.url(from: "example.test:8080/x")?.absoluteString, "https://example.test:8080/x")
        XCTAssertEqual(LinkAddress.url(from: "localhost:3000")?.absoluteString, "https://localhost:3000")
        XCTAssertNil(LinkAddress.url(from: "javascript:alert(1)"), "a scheme, and not one Vitruvian Courier sends")
        XCTAssertEqual(LinkAddress.url(from: "mailto:2fast@x.test")?.absoluteString, "mailto:2fast@x.test",
                       "a known scheme stays one, digit or not")
    }

    func testScheduleTimesInRangeOnly() {
        XCTAssertEqual(ScheduleTime.problem(with: now.addingTimeInterval(-60), now: now),
                       "That time has passed. Choose a later one.")
        XCTAssertEqual(ScheduleTime.problem(with: now.addingTimeInterval(30), now: now),
                       "Pick a time at least a minute from now.", "under a minute ahead is too soon")
        XCTAssertNil(ScheduleTime.problem(with: now.addingTimeInterval(3600), now: now))
        let sixYears = Calendar.current.date(byAdding: .year, value: 6, to: now)!
        XCTAssertEqual(ScheduleTime.problem(with: sixYears, now: now), "Choose a time within 5 years.")
    }

    func testAHiddenSpoilerReadsAsSpoiler() {
        let rich = RichText(text: "It was the butler, obviously", entities: [entity(.spoiler, 11, 6)])
        XCTAssertEqual(RichTextLayout.spoken(rich, revealed: false), "It was the Spoiler, obviously")
        XCTAssertEqual(RichTextLayout.spoken(rich, revealed: true), "It was the butler, obviously")
    }

    // MARK: Stickers and GIFs (4.5c Task 10)

    func testStickerEventProducesStickerAttachmentAndSuppressesBubbleBackgroundWhileKeepingReactionsTimestampAndReplyHeader() {
        let baseTS = Int64(now.timeIntervalSince1970 * 1000) - 120_000
        let quoteEvent = Event(
            eventID: "$quote-1",
            roomID: "!a",
            sender: "@ann:example.test",
            senderName: "Ann Example",
            mine: false,
            type: "m.room.message",
            content: .object(["msgtype": .string("m.text"), "body": .string("See you on the trail!")]),
            ts: baseTS,
            seq: 1,
            status: .sent
        )
        let stickerTS = baseTS + 15_000
        let stickerEvent = stickerEventFixture(
            id: "$sticker-1",
            room: "!a",
            mine: true,
            ts: stickerTS,
            seq: 2,
            name: "Party Parrot",
            emoji: "🦜",
            mediaURL: "mxc://courier.local/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            mimeType: "image/webp",
            width: 128,
            height: 128,
            size: 4096,
            replyTo: "$quote-1"
        )
        let reactionEvent = Event(
            eventID: "$react-1",
            roomID: "!a",
            sender: "@ann:example.test",
            senderName: "Ann Example",
            mine: false,
            type: "m.reaction",
            content: .object([
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"),
                    "event_id": .string("$sticker-1"),
                    "key": .string("🎉"),
                ]),
            ]),
            ts: stickerTS + 2_000,
            seq: 3,
            status: .sent
        )

        let builtRows: [MessageRow] = Timeline.build(
            events: [quoteEvent, stickerEvent, reactionEvent],
            me: Timeline.meUserID,
            now: now
        ).compactMap { if case let .message(m) = $0 { m } else { nil } }

        XCTAssertEqual(builtRows.count, 2)
        let textRow = builtRows[0]
        let stickerRow = builtRows[1]

        XCTAssertNil(textRow.sticker)
        XCTAssertFalse(textRow.suppressesBubbleBackground)

        XCTAssertEqual(stickerRow.kind, .sticker)
        XCTAssertEqual(
            stickerRow.sticker,
            StickerAttachment(
                mediaURL: "mxc://courier.local/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                name: "Party Parrot",
                emoji: "🦜",
                mimeType: "image/webp",
                width: 128,
                height: 128
            )
        )
        XCTAssertTrue(stickerRow.suppressesBubbleBackground, "m.sticker suppresses the coloured text bubble background")
        XCTAssertEqual(stickerRow.ts, stickerTS, "sticker keeps its timestamp")
        XCTAssertEqual(
            stickerRow.reactions,
            [ReactionChip(key: "🎉", count: 1, mine: false,
                          reactors: [Reactor(userID: "@ann:example.test", name: "Ann Example", isMe: false)])],
            "sticker keeps its reactions"
        )
        XCTAssertEqual(
            stickerRow.reply,
            .quoted(QuotedMessage(eventID: "$quote-1", senderName: "Ann Example", mine: false, text: "See you on the trail!", kind: .text)),
            "sticker keeps its reply header"
        )

        // Redacted and view-once events stay hidden as before.
        let redaction = Event(
            eventID: "$red-1",
            roomID: "!a",
            sender: Timeline.meUserID,
            senderName: "me",
            mine: true,
            type: "m.room.redaction",
            content: .object(["redacts": .string("$sticker-1")]),
            ts: stickerTS + 5_000,
            seq: 4,
            status: .sent
        )
        let redactedRows: [MessageRow] = Timeline.build(
            events: [stickerEvent, redaction],
            me: Timeline.meUserID,
            now: now
        ).compactMap { if case let .message(m) = $0 { m } else { nil } }
        XCTAssertEqual(redactedRows.first?.kind, .deleted)
        XCTAssertNil(redactedRows.first?.sticker)
        XCTAssertFalse(redactedRows.first?.suppressesBubbleBackground ?? true)

        let viewOnceSticker = stickerEventFixture(
            id: "$sticker-vo",
            room: "!a",
            mine: false,
            ts: stickerTS + 10_000,
            seq: 5,
            viewOnce: true
        )
        let voRows: [MessageRow] = Timeline.build(
            events: [viewOnceSticker],
            me: Timeline.meUserID,
            now: now
        ).compactMap { if case let .message(m) = $0 { m } else { nil } }
        XCTAssertEqual(voRows.first?.viewOnce, true)
        XCTAssertNil(voRows.first?.sticker)
        XCTAssertFalse(voRows.first?.suppressesBubbleBackground ?? true)

        // Non-wire top-level `content["emoji"]` or `info["emoji"]` fields (never emitted by the Go engine)
        // are ignored; only `info["fi.mau.bridged_sticker"]["emoji"]` is read.
        var nonWireEmojiSticker = stickerEventFixture(
            id: "$sticker-nonwire",
            room: "!a",
            mine: false,
            ts: stickerTS + 15_000,
            seq: 6,
            emoji: nil
        )
        if case var .object(c) = nonWireEmojiSticker.content,
           case var .object(infoObj) = c["info"] {
            infoObj["emoji"] = .string("👻")
            c["info"] = .object(infoObj)
            c["emoji"] = .string("👻")
            nonWireEmojiSticker.content = .object(c)
        }
        let nonWireRows: [MessageRow] = Timeline.build(
            events: [nonWireEmojiSticker],
            me: Timeline.meUserID,
            now: now
        ).compactMap { if case let .message(m) = $0 { m } else { nil } }
        XCTAssertNil(nonWireRows.first?.sticker?.emoji, "Timeline must only read emoji from info.fi.mau.bridged_sticker.emoji")
    }

    func testGIFEventProducesGIFAttachmentWithOptionalCaption() {
        let baseTS = Int64(now.timeIntervalSince1970 * 1000) - 60_000
        let uncaptionedGIF = gifEventFixture(
            id: "$gif-1",
            room: "!a",
            mine: false,
            ts: baseTS,
            seq: 1,
            msgtype: "m.image",
            fileName: "animation.gif",
            caption: nil,
            mediaURL: "mxc://courier.local/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
            mimeType: "image/gif",
            width: 320,
            height: 240
        )
        let captionedGIF = gifEventFixture(
            id: "$gif-2",
            room: "!a",
            mine: true,
            ts: baseTS + 5_000,
            seq: 2,
            msgtype: "m.video",
            fileName: "animation.mp4",
            caption: "Trail summit celebration",
            mediaURL: "mxc://courier.local/1122334455667788112233445566778811223344556677881122334455667788",
            mimeType: "video/mp4",
            width: 480,
            height: 270
        )

        let rows: [MessageRow] = Timeline.build(
            events: [uncaptionedGIF, captionedGIF],
            me: Timeline.meUserID,
            now: now
        ).compactMap { if case let .message(m) = $0 { m } else { nil } }

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(
            rows[0].gif,
            GIFAttachment(
                mediaURL: "mxc://courier.local/fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
                caption: nil,
                mimeType: "image/gif",
                width: 320,
                height: 240
            )
        )
        XCTAssertEqual(rows[0].body, "")
        XCTAssertFalse(rows[0].suppressesBubbleBackground)

        XCTAssertEqual(
            rows[1].gif,
            GIFAttachment(
                mediaURL: "mxc://courier.local/1122334455667788112233445566778811223344556677881122334455667788",
                caption: "Trail summit celebration",
                mimeType: "video/mp4",
                width: 480,
                height: 270
            )
        )
        XCTAssertEqual(rows[1].body, "Trail summit celebration")
    }

    func testHoveringUnselectedMessageShowsHoverPillAndHidesWhenPointerLeaves() {
        XCTAssertEqual(ActionBarVisibility.hoverFadeDuration, 0.12, accuracy: 0.001)
        var pointer = ActionBarPointer()
        XCTAssertEqual(
            ActionBarVisibility.mode(canAct: true, isSelected: false, menuOpen: false, pickingReaction: false,
                                     pointer: pointer, timelineCovered: false),
            .hidden
        )
        pointer.rowHover(true)
        XCTAssertEqual(
            ActionBarVisibility.mode(canAct: true, isSelected: false, menuOpen: false, pickingReaction: false,
                                     pointer: pointer, timelineCovered: false),
            .hoverPill
        )
        pointer.rowHover(false)
        XCTAssertEqual(
            ActionBarVisibility.mode(canAct: true, isSelected: false, menuOpen: false, pickingReaction: false,
                                     pointer: pointer, timelineCovered: false),
            .hoverPill,
            "stays up while pointer crosses from row onto hover pill"
        )
        pointer.barHover(true)
        pointer.settle()
        XCTAssertEqual(
            ActionBarVisibility.mode(canAct: true, isSelected: false, menuOpen: false, pickingReaction: false,
                                     pointer: pointer, timelineCovered: false),
            .hoverPill
        )
        pointer.barHover(false)
        pointer.settle()
        XCTAssertEqual(
            ActionBarVisibility.mode(canAct: true, isSelected: false, menuOpen: false, pickingReaction: false,
                                     pointer: pointer, timelineCovered: false),
            .hidden
        )
    }
}
