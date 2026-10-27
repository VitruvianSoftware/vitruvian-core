// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

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

    func testTheMenuIsInItsOrderWithGreyedLinesAndInfo() {
        let mine = message(mine: true, edited: true, minutesAgo: 30)
        let available = MessageActions.available(for: mine, in: whatsApp, network: "whatsapp", now: now)
        let sections = MessageMenu.sections(for: mine, available: available, features: whatsApp,
                                            disappearsIn: "Disappears in 1 hour", time: { _ in "14:02" })
        XCTAssertEqual(sections.map { $0.map(\.title) }, [
            ["Edit…", "Reply…"], ["React…"], ["Bookmark"], ["Mark as Unread"], ["Unsend", "Delete for Me…"],
            ["Copy", "Copy with Timestamp"], ["Forward…"], ["Edit History"], ["Sent at 14:02", "Disappears in 1 hour"],
        ])
        let edit = sections[0][0]
        XCTAssertFalse(edit.isEnabled, "30 minutes is past WhatsApp's 15")
        XCTAssertEqual(edit.help, "WhatsApp only lets you edit for 15 minutes")
        XCTAssertEqual(edit.key, .commandT)
        let markUnread = sections[3][0]
        XCTAssertTrue(markUnread.isEnabled)
        XCTAssertEqual(markUnread.help, "From this message. On this Mac only.")
        XCTAssertTrue(sections[8].allSatisfy { !$0.isEnabled && $0.command == .info })

        // Someone else's, in a group: Reply Privately… after Reply….
        let theirs = message(mine: false, minutesAgo: 1)
        let inGroup = MessageActions.available(for: theirs, in: whatsApp, network: "whatsapp", now: now,
                                               isDirect: false, networkRunning: true)
        let groupSections = MessageMenu.sections(for: theirs, available: inGroup, features: whatsApp, disappearsIn: nil,
                                                 time: { _ in "14:02" })
        XCTAssertEqual(groupSections.first?.map(\.title), ["Reply…", "Reply Privately…"])
    }

    func testSomeoneElsesThreadRootOffersShowRepliesAndInsertAsDraft() {
        let slack = ChatFeatures(thread: true, replyIsThread: true, unsend: true, source: .stored)
        let root = message(mine: false, body: "see https://example.test",
                           thread: ThreadSummary(replies: 2, lastTS: 0, lastSenders: ["Bo"]), bookmarked: true)
        let available = MessageActions.available(for: root, in: slack, network: "slack", now: now)
        let titles = MessageMenu.sections(for: root, available: available, features: slack, disappearsIn: nil,
                                          time: { _ in "9:00" }).map { $0.map(\.title) }
        XCTAssertEqual(titles, [
            ["Reply in Thread…", "Show Replies"], ["React…"], ["Remove Bookmark"], ["Mark as Unread"],
            ["Delete for Me…"],
            ["Copy", "Copy with Timestamp", "Insert as Draft", "Open Link"], ["Forward…"], ["Received at 9:00"],
        ])
        let gm = ChatFeatures(reply: true, deleteReachesPhone: true, source: .stored)
        XCTAssertEqual(MessageMenu.title(of: .deleteForMe, features: gm), "Delete from This Mac and Your Phone…")
    }

    func testAMessageNotSentHasNoSentAtLine() {
        let failed = message(mine: true, status: .failed)
        let available = MessageActions.available(for: failed, in: whatsApp, network: "whatsapp", now: now)
        let sections = MessageMenu.sections(for: failed, available: available, features: whatsApp, disappearsIn: nil,
                                            time: { _ in "now" })
        XCTAssertEqual(sections.map { $0.map(\.title) }, [["Copy", "Copy with Timestamp"]])
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
        XCTAssertNil(LinkAddress.url(from: "javascript:alert(1)"), "a scheme, and not one Courier sends")
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
        XCTAssertEqual(stickerRow.reactions, [ReactionChip(key: "🎉", count: 1, mine: false)], "sticker keeps its reactions")
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
}
