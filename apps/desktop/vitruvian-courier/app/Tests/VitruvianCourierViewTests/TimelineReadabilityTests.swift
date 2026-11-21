// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Message timeline readability: custom-emoji reactions never show their address, a post of several files shows its
/// time once, plain text bubbles stop at a readable width, right-to-left text keeps its time clear of the last line,
/// and the thread line can be read.
/// Look at timeline-custom-emoji-*, timeline-run-times-*, timeline-wide-text-*, timeline-long-word-*, timeline-rtl-*.
@MainActor
final class TimelineReadabilityTests: XCTestCase {
    private let mxc = "mxc://courier.local/" + String(repeating: "06da", count: 16)

    private func reaction(_ key: String, on target: String, id: String = "$r1") -> Event {
        Fixture.event(id, type: "m.reaction", mine: false, ts: 1, content: [
            "m.relates_to": .object([
                "rel_type": .string("m.annotation"), "event_id": .string(target), "key": .string(key),
            ]),
        ])
    }

    private func row(_ events: [Event], selecting id: String? = nil) -> some View {
        let ui = MessageUI()
        var actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        actions.openThread = { _ in }
        return VStack(spacing: 0) {
            ForEach(Fixture.items(events)) { item in
                TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
            }
        }
        .padding(14)
    }

    // MARK: 1. Custom emoji

    func testCustomEmojiReactionNeverShowsItsAddress() throws {
        let events = [Fixture.text("$m1", "Shipped it", mine: false, ts: 3), reaction(mxc, on: "$m1")]
        let message = try XCTUnwrap(Fixture.messages(events).first)
        let chip = try XCTUnwrap(message.reactions.first)
        XCTAssertTrue(chip.isCustomImage)
        XCTAssertEqual(chip.spokenKey, "Custom emoji")
        for words in [chip.summary(), chip.tooltipText(), chip.spokenKey] {
            XCTAssertFalse(words.contains("mxc://"), words)
        }
        let plain = ReactionChip(key: "👍", count: 1, mine: false)
        XCTAssertFalse(plain.isCustomImage)
        XCTAssertEqual(plain.spokenKey, "👍")
        _ = try Snapshot.render("timeline-custom-emoji", width: 480) { row(events) }
        // Drawn as text the address would make the row far wider than the same row with a one-character emoji.
        func rowWidth(_ key: String) -> CGFloat {
            let events = [Fixture.text("$m1", "Shipped it", mine: false, ts: 3), reaction(key, on: "$m1")]
            return NSHostingView(rootView: row(events).fixedSize()).fittingSize.width
        }
        XCTAssertLessThan(rowWidth(mxc), rowWidth("👍") + 40, "the custom emoji is a picture, not its address")
    }

    /// The picture is the chip's, not a tooltip of its own: pointing at it still says who reacted.
    func testCustomEmojiChipKeepsItsWhoReactedTooltip() throws {
        let events = [Fixture.text("$m1", "Shipped it", mine: false, ts: 3), reaction(mxc, on: "$m1")]
        let chip = try XCTUnwrap(Fixture.messages(events).first?.reactions.first)
        XCTAssertTrue(chip.tooltipText().contains("Ann Example"), chip.tooltipText())
        // The chip's help is `tooltipText`; the picture adds none of its own (ReactionKeyView has no `.help`), so
        // this is what pointing at the picture says. The view's own help can't be read in a headless test.
        XCTAssertFalse(chip.tooltipText().contains("mxc://"))
        XCTAssertNotEqual(chip.tooltipText(), chip.spokenKey)
    }

    // MARK: 2. One time per run

    func testAPostOfSeveralFilesShowsItsTimeOnceOnTheLastItem() throws {
        let files = (0 ..< 4).map { Fixture.mediaEvent("$f\($0)", msgtype: "m.file", body: "report-\($0).pdf", size: 1000, ts: 5) }
        XCTAssertEqual(Fixture.messages(files).map(\.showsTime), [false, false, false, true])
        // A run that spans minutes keeps every time.
        let spread = [10, 8, 6].enumerated().map {
            Fixture.mediaEvent("$s\($0.offset)", msgtype: "m.file", body: "f\($0.offset).pdf", size: 1000, ts: $0.element)
        }
        XCTAssertEqual(Fixture.messages(spread).map(\.showsTime), [true, true, true])
        // A different sender in the same minute doesn't hide the first one's time.
        let two = [Fixture.text("$a", "one", mine: false, ts: 4),
                   Fixture.text("$b", "two", mine: true, ts: 4)]
        XCTAssertEqual(Fixture.messages(two).map(\.showsTime), [true, true])
        _ = try Snapshot.render("timeline-run-times", width: 520) { row(files) }
    }

    /// A reply and an edited message inside a run take part like any other: the earlier ones lose the time (an edited
    /// one keeps its "Edited"), the last keeps it.
    func testRepliesAndEditsInARun() throws {
        var reply = Fixture.event("$r", mine: true, ts: 5, content: [
            "msgtype": .string("m.text"), "body": .string("a reply"),
            "m.relates_to": .object(["m.in_reply_to": .object(["event_id": .string("$a")])]),
        ])
        reply.seq = 10_003
        var first = Fixture.text("$a", "first", mine: true, ts: 5)
        first.seq = 10_001
        var edited = Fixture.text("$e", "second", mine: true, ts: 5)
        edited.seq = 10_002
        var edit = Fixture.edit("$e2", of: "$e", "second, fixed", ts: 5)
        edit.seq = 10_004
        let messages = Fixture.messages([first, edited, edit, reply])
        XCTAssertEqual(messages.map(\.id), ["$a", "$e", "$r"])
        XCTAssertEqual(messages.map(\.showsTime), [false, false, true])
        XCTAssertTrue(messages[1].isEdited, "the edited one still carries its Edited label")
        XCTAssertNotNil(messages[2].reply)
    }

    /// The minute is the clock's: 12:00:59.900 and 12:01:00.100 are different minutes, 12:01:00.100 and 12:01:00.900 are not.
    func testMinuteBoundaryAtSubSecondPrecision() {
        let boundary = Fixture.millis(5)
        XCTAssertEqual(boundary % 60_000, 0)
        func message(_ id: String, at ts: Int64, seq: Int64) -> Event {
            var event = Fixture.text(id, id, mine: false, ts: 5)
            event.ts = ts
            event.seq = seq
            return event
        }
        let across = [message("$x", at: boundary - 100, seq: 1), message("$y", at: boundary + 100, seq: 2)]
        XCTAssertEqual(Fixture.messages(across).map(\.showsTime), [true, true])
        let within = [message("$x", at: boundary + 100, seq: 1), message("$y", at: boundary + 900, seq: 2)]
        XCTAssertEqual(Fixture.messages(within).map(\.showsTime), [false, true])
    }

    // MARK: 3. Width cap

    private final class Box { var frame: CGRect = .zero }

    private func bubbleFrame(_ item: TimelineItem, window: CGFloat, snapshot: String = "timeline-wide-text") throws -> CGRect {
        let box = Box()
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        _ = try Snapshot.render("\(snapshot)-\(Int(window))", width: window) {
            TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
                .overlayPreferenceValue(RowAnchorsKey.self) { anchors in
                    GeometryReader { geo in
                        Color.clear.onAppear { if let a = anchors.bubble { box.frame = geo[a] } }
                    }
                }
        }
        return box.frame
    }

    private func bubbleWidth(_ event: Event, window: CGFloat, snapshot: String = "timeline-wide-text") throws -> CGFloat {
        let item = try XCTUnwrap(Fixture.items([event]).first { if case .message = $0 { true } else { false } })
        return try bubbleFrame(item, window: window, snapshot: snapshot).width
    }

    func testDirectChatBubblesStartAtLeftMarginWhileGroupKeepsAvatarColumnInChatAndThreadPane() throws {
        let runEvents = [
            Fixture.text("$m1", "First message in run", mine: false, ts: 4),
            Fixture.text("$m2", "Second message in run", mine: false, ts: 3),
        ]
        let directMsgs = Fixture.items(runEvents, isDirect: true).filter { if case .message = $0 { true } else { false } }
        let groupMsgs = Fixture.items(runEvents, isDirect: false).filter { if case .message = $0 { true } else { false } }
        XCTAssertEqual(directMsgs.count, 2)
        XCTAssertEqual(groupMsgs.count, 2)

        // Direct chat: neither the first nor second incoming bubble in a run reserves an avatar column (minX == 0).
        let directFirst = try bubbleFrame(directMsgs[0], window: 520, snapshot: "timeline-direct-margin-first")
        let directSecond = try bubbleFrame(directMsgs[1], window: 520, snapshot: "timeline-direct-margin-second")
        XCTAssertEqual(directFirst.minX, 0, accuracy: 0.5, "1:1 first incoming bubble starts at the left margin")
        XCTAssertEqual(directSecond.minX, 0, accuracy: 0.5, "1:1 continuation bubble also starts at the left margin")

        // Group chat: 28pt avatar + 8pt HStack spacing = 36pt offset on both first-of-run and continuation bubbles.
        let groupFirst = try bubbleFrame(groupMsgs[0], window: 520, snapshot: "timeline-group-margin-first")
        let groupSecond = try bubbleFrame(groupMsgs[1], window: 520, snapshot: "timeline-group-margin-second")
        XCTAssertEqual(groupFirst.minX, 36, accuracy: 0.5, "group first incoming bubble sits beside the 28pt avatar")
        XCTAssertEqual(groupSecond.minX, 36, accuracy: 0.5, "group continuation bubble aligns with the avatar column")

        // ThreadPane follows the exact same rule (14pt horizontal padding inside the pane -> 14pt in 1:1 vs 50pt in group).
        final class NoOpPasteboard: TextPasteboard { func setString(_: String) {} }
        func threadBubbleMinX(isDirect: Bool) throws -> CGFloat {
            let suiteName = "courier.thread.margin.\(UUID().uuidString)"
            let defaults = ScratchDefaults.suite(named: suiteName)!
            defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
            let prefs = ComposerPreferences(defaults: defaults)
            let app = AppModel(supervisor: EngineSupervisor(
                enginePath: "/nonexistent/vitruvian-courier-engine",
                dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("courier-thread-margin"),
                environment: [:], launcher: FoundationProcessLauncher()
            ))
            let conv = ConversationModel(appModel: app, preferences: prefs)
            let row = Fixture.row("!t", "Ann", direct: isDirect, ts: 5, preview: "hi")
            let items = Fixture.items([Fixture.text("$tr", "In thread", mine: false, ts: 2)], isDirect: isDirect)
            conv.setSnapshotStateForTesting(roomID: "!t", items: items, row: row)
            conv.thread.setSnapshotStateForTesting(roomID: "!t", rootID: "$tr", items: items)
            let msgActions = MessageActionsModel(conversation: conv, appModel: app, preferences: prefs, pasteboard: NoOpPasteboard())
            let focus = MessageFocus()
            let box = Box()
            _ = try Snapshot.render("thread-pane-margin-\(isDirect ? "direct" : "group")", width: 420, height: 260) {
                ThreadPane(thread: conv.thread, conversation: conv, composer: conv.thread.composer,
                           messageActions: msgActions, preferences: prefs, focus: focus)
                    .overlayPreferenceValue(RowAnchorsKey.self) { anchors in
                        GeometryReader { geo in
                            Color.clear.onAppear { if let a = anchors.bubble { box.frame = geo[a] } }
                        }
                    }
            }
            return box.frame.minX
        }
        XCTAssertEqual(try threadBubbleMinX(isDirect: true), 14, accuracy: 0.5,
                       "1:1 ThreadPane incoming bubble starts at the pane's 14pt left margin")
        XCTAssertEqual(try threadBubbleMinX(isDirect: false), 50, accuracy: 0.5,
                       "group ThreadPane incoming bubble sits after 14pt padding + 28pt avatar + 8pt gap")
    }

    func testAVideoCardBubbleIsCappedToTheCardWidthNotTheRow() throws {
        let long = String(repeating: "A long line of chat text that would stretch across a very wide window. ", count: 20)
        let ytURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        var youtube = Fixture.text("$yt-wide", "\(long)\n\(ytURL)", mine: false, ts: 2)
        youtube.linkPreviews = [LinkPreviewItem(matchedURL: ytURL, url: ytURL, title: "A video")]
        let ytWidth = try bubbleWidth(youtube, window: 1400, snapshot: "timeline-wide-youtube")
        XCTAssertLessThanOrEqual(ytWidth, EmbedConsentCard.maxWidth + 32 + 1, "the bubble is capped to the card width")
        XCTAssertGreaterThanOrEqual(ytWidth, EmbedConsentCard.maxWidth)
    }

    /// The bubble the hover pill is placed by is the bubble's own frame. A text bubble sits in a frame as wide as its text
    /// may go (640 pt), and the pill was placed by that: ~500 pt to the right of a short "Okay".
    func testAShortMessagesAnchorIsItsBubbleNotItsRowsFrame() throws {
        for mine in [false, true] {
            let width = try bubbleWidth(Fixture.text("$ok\(mine)", "Okay", mine: mine, ts: 2), window: 1400,
                                        snapshot: "timeline-short-okay-\(mine)")
            XCTAssertGreaterThan(width, 20)
            XCTAssertLessThan(width, 200, "the frame of a bubble holding four letters, not of the room for 640 pt of text")
        }
    }

    func testPlainTextBubbleStopsAtAReadableWidth() throws {
        let long = String(repeating: "A long line of chat text that would stretch across a very wide window. ", count: 20)
        let wide = try bubbleWidth(Fixture.text("$w", long, mine: false, ts: 2), window: 1400)
        XCTAssertGreaterThan(wide, 300)
        XCTAssertLessThanOrEqual(wide, BubbleWidth.maxWidth(rowWidth: 1400) + 1, "capped at the text width")
        let narrow = try bubbleWidth(Fixture.text("$n", long, mine: false, ts: 2), window: 320)
        XCTAssertLessThanOrEqual(narrow, 320, "a narrow window still fits")
        XCTAssertGreaterThan(narrow, 150)
    }

    /// One very long word with no spaces breaks inside the bubble: not past the cap, not past a narrow window, and the
    /// text itself wraps onto more lines (it is not just a clipped frame).
    func testAVeryLongWordStaysInsideTheBubble() throws {
        let word = String(repeating: "W", count: 400)
        let wide = try bubbleWidth(Fixture.text("$lw1", word, mine: false, ts: 2), window: 1400, snapshot: "timeline-long-word")
        XCTAssertLessThanOrEqual(wide, BubbleWidth.maxWidth(rowWidth: 1400) + 1)
        let narrow = try bubbleWidth(Fixture.text("$lw2", word, mine: false, ts: 2), window: 320, snapshot: "timeline-long-word")
        XCTAssertLessThanOrEqual(narrow, 320)
        let oneLine = fittingHeight(Fixture.text("$lw3", "W", mine: false, ts: 2), showTimes: false, width: 320)
        let wrapped = fittingHeight(Fixture.text("$lw4", word, mine: false, ts: 2), showTimes: false, width: 320)
        XCTAssertGreaterThan(wrapped, oneLine + 2 * lineHeight(13), "the word wraps onto several lines")
    }

    // MARK: 4/5. Time size and thread line

    private func fittingHeight(_ event: Event, showTimes: Bool, width: CGFloat = 420) -> CGFloat {
        let ui = MessageUI()
        var actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        actions.showMessageTimestamps = showTimes
        let item = Fixture.items([event]).first { if case .message = $0 { true } else { false } }!
        let host = NSHostingView(rootView: TimelineItemView(item: item, isSelected: false, showsSent: false,
                                                            actions: actions, ui: ui)
                .frame(width: width).fixedSize(horizontal: false, vertical: true))
        return host.fittingSize.height
    }

    private func lineHeight(_ size: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: size))
    }

    private func width<V: View>(_ view: V) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
    }

    /// The time label the bubble draws is 11 pt: as wide as 11 pt text, not as 10 pt text (the heights of the two
    /// are the same line, so the width tells them apart).
    func testTheTimeInTheBubbleIsDrawnAt11Points() {
        XCTAssertEqual(MessageRowView.metaPointSize, 11)
        let words = "12:59 PM"
        let drawn = width(MessageTimeLabel(text: words))
        XCTAssertEqual(drawn, width(Text(words).font(.system(size: 11))), accuracy: 0.01)
        XCTAssertGreaterThan(abs(drawn - width(Text(words).font(.system(size: 10)))), 1, "11 pt and 10 pt differ")
    }

    /// The last line's first strong letter decides: right-to-left text, and text that begins right to left even when it
    /// ends on a Latin word, give the time a line of its own; left-to-right text, even with a Hebrew word at its end,
    /// keeps it on the end of its last line.
    func testRightToLeftIsDecidedByTheLastLine() {
        XCTAssertTrue(MessageRowView.endsRightToLeft("مرحبا بالعالم"), "pure Arabic")
        XCTAssertTrue(MessageRowView.endsRightToLeft("שלום עולם"), "pure Hebrew")
        XCTAssertFalse(MessageRowView.endsRightToLeft("Hello world"), "pure Latin")
        XCTAssertFalse(MessageRowView.endsRightToLeft("Hello world שלום"), "Latin ending with a Hebrew word")
        XCTAssertTrue(MessageRowView.endsRightToLeft("שלום hello"), "Hebrew ending with a Latin word")
        XCTAssertTrue(MessageRowView.endsRightToLeft("Hello\nשלום"), "the last line decides")
        XCTAssertFalse(MessageRowView.endsRightToLeft("שלום\nHello"), "the last line decides")
        XCTAssertTrue(MessageRowView.endsRightToLeft("\u{200F}123 !"), "a right-to-left mark")
        XCTAssertFalse(MessageRowView.endsRightToLeft("\u{200E}שלום"), "a left-to-right mark")
        XCTAssertTrue(MessageRowView.endsRightToLeft("\u{10800}\u{10801}"), "a script outside the first plane")
        XCTAssertTrue(MessageRowView.endsRightToLeft("\u{1E900}\u{1E901}"), "Adlam")
        XCTAssertFalse(MessageRowView.endsRightToLeft("123 :)"), "no letters")
    }

    func testRightToLeftTextGetsTheTimeOnItsOwnLine() throws {
        let arabic = Fixture.text("$ar", "مرحبا بالعالم هذا اختبار", mine: false, ts: 5)
        let english = Fixture.text("$en", "Hello world, this is a test", mine: false, ts: 5)
        let mixed = Fixture.text("$mx", "Meet at the cafe, it is called קפה", mine: false, ts: 5)
        func added(_ event: Event) -> CGFloat {
            fittingHeight(event, showTimes: true) - fittingHeight(event, showTimes: false)
        }
        XCTAssertGreaterThan(added(arabic), lineHeight(11), "the time has its own line under the Arabic text")
        XCTAssertLessThan(added(english), 1, "the time shares the English text's last line")
        XCTAssertLessThan(added(mixed), 1, "one Hebrew word doesn't change an English message")
        _ = try Snapshot.render("timeline-rtl-bubble", width: 420) { row([arabic, english, mixed]) }
    }

    /// The text reserves room for the time at 10 pt; the time is drawn at 11 pt. The reserve must be at least as wide
    /// as the time, or the time overlaps the end of the last line.
    func testReservedRoomIsAtLeastAsWideAsTheTime() {
        func width(_ text: String, _ size: CGFloat) -> CGFloat {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)]).size().width
        }
        for words in ["2:56 AM", "12:59 PM", "Edited  12:59 PM", "Hide Edits  10:59 PM", "Edited"] {
            let reserved = width("\u{2003}" + MessageRowView.reservedMeta(words), 10)
            let drawn = width(words, MessageRowView.metaPointSize)
            XCTAssertGreaterThanOrEqual(reserved, drawn, "\(words): the reserve leaves room for the 11 pt time")
        }
    }

    func testTimeAndEditedTuckIntoLastLineWhenRoomExistsAndWrapWhenFull() {
        let reserved = MessageRowView.reservedMeta("Edited  11:47 PM")
        XCTAssertFalse(reserved.contains(" "), "reservedMeta must replace spaces with NBSP so timestamp never splits mid-line")
        XCTAssertTrue(reserved.contains("\u{2060}\u{200A}"), "trailing hair spaces stay glued via word joiner")

        func addedHeight(_ event: Event, width: CGFloat) -> CGFloat {
            fittingHeight(event, showTimes: true, width: width) - fittingHeight(event, showTimes: false, width: width)
        }

        // 1. Short message + Edited tucks onto the same line.
        let shortEdited = [
            Fixture.text("$short-ed", "Hi!", mine: false, ts: 5),
            Fixture.edit("$short-ed-e", of: "$short-ed", "Hey!", ts: 4),
        ]
        let shortItem = Fixture.items(shortEdited).first { if case .message = $0 { true } else { false } }!
        let shortWithTime = NSHostingView(rootView: TimelineItemView(
            item: shortItem, isSelected: false, showsSent: false,
            actions: { var a = VitruvianCourier.MessageActions(now: { Fixture.now }); a.showMessageTimestamps = true; return a }(),
            ui: MessageUI()
        ).frame(width: 420).fixedSize(horizontal: false, vertical: true)).fittingSize.height
        let shortWithoutTime = NSHostingView(rootView: TimelineItemView(
            item: shortItem, isSelected: false, showsSent: false,
            actions: { var a = VitruvianCourier.MessageActions(now: { Fixture.now }); a.showMessageTimestamps = false; return a }(),
            ui: MessageUI()
        ).frame(width: 420).fixedSize(horizontal: false, vertical: true)).fittingSize.height
        XCTAssertLessThan(shortWithTime - shortWithoutTime, 1, "short edited text tucks Edited + time onto line 1")

        // 2. Multi-line message with a short last line keeps the time on that last line.
        let multiShortEnd = Fixture.text("$multi-short", "First part of the message wraps onto another line\ndone.", mine: false, ts: 5)
        XCTAssertLessThan(addedHeight(multiShortEnd, width: 420), 1, "short last line shares its line with the time")

        // 3. Message whose last line fills the available width wraps the time onto a new line below.
        let tight = Fixture.text("$tight", "This line fills almost all of the narrow bubble width", mine: false, ts: 5)
        XCTAssertGreaterThan(addedHeight(tight, width: 250), lineHeight(11) * 0.8, "full last line wraps the time below")

        // 4. Bullet list whose last item has room tucks the time onto that last bullet line.
        let listEvent = Fixture.event("$list", mine: false, ts: 5, content: [
            "msgtype": .string("m.text"),
            "body": .string("Bread\nMilk"),
            "format": .string("org.matrix.custom.html"),
            "formatted_body": .string("<ul><li>Bread</li><li>Milk</li></ul>"),
        ])
        XCTAssertLessThan(addedHeight(listEvent, width: 420), 1, "bullet list with room tucks time onto its last item")
    }

    // MARK: Thread line

    /// How much red (the accent) a view draws, as the sum of how far each pixel's red is above its green and blue.
    private func redInk<V: View>(_ view: V) -> Double {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.padding(4).background(Color.white))
        host.appearance = NSAppearance(named: .aqua)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        for _ in 0 ..< 15 {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004))
            host.layoutSubtreeIfNeeded()
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 0 }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var ink = 0.0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                ink += max(0, Double(c.redComponent - max(c.greenComponent, c.blueComponent)))
            }
        }
        window.contentView = nil
        return ink
    }

    /// The line as the app draws it (no parameters) draws the reply count exactly as 12 pt medium text in the accent
    /// colour would, and differently from semibold or from 10 pt. Measured as what a longer count adds, since the
    /// icon and chevron have ink of their own.
    func testThreadCountIsMediumTwelvePointInTheAccentColour() {
        func added(weight: Font.Weight? = nil, size: CGFloat? = nil) -> Double {
            func line(_ replies: Int) -> Double {
                let summary = ThreadSummary(replies: replies, lastTS: Fixture.millis(1), lastSenders: [])
                let view: ThreadSummaryLine
                if let weight, let size {
                    view = ThreadSummaryLine(summary: summary, open: {}, countWeight: weight, pointSize: size)
                } else {
                    view = ThreadSummaryLine(summary: summary, open: {})
                }
                return redInk(view.environment(\.themeAccentHex, "#FF0000"))
            }
            return line(12) - line(1)
        }
        let drawn = added()
        XCTAssertGreaterThan(drawn, 0, "the count is drawn in the accent colour")
        // Ratios, not absolute ink: the amount depends on the machine's text rendering, how the shapes compare does not.
        let medium = added(weight: .medium, size: 12)
        XCTAssertLessThan(abs(drawn / medium - 1), 0.01, "the default is 12 pt medium")
        XCTAssertGreaterThan(abs(added(weight: .semibold, size: 12) / medium - 1), 0.03, "semibold looks different")
        XCTAssertGreaterThan(abs(added(weight: .medium, size: 10) / medium - 1), 0.03, "10 pt looks different")
    }
}
