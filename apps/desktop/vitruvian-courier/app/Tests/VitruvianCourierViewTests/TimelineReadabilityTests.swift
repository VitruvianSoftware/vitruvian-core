// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// Message timeline readability: custom-emoji reactions never show their address, a post of several files shows its
/// time once, plain text bubbles stop at a readable width, and the thread line can be read.
/// Look at timeline-custom-emoji-*, timeline-run-times-*, timeline-wide-text-*, timeline-thread-line-*.
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
        // Nothing on screen (labels, help) carries the address.
        let host = NSHostingView(rootView: row(events).frame(width: 480))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 200)
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(Self.texts(of: host).contains { $0.contains("mxc://") }, "the address is never drawn")
        // Drawn as text the address would make the row far wider than the same row with a one-character emoji.
        func rowWidth(_ key: String) -> CGFloat {
            let events = [Fixture.text("$m1", "Shipped it", mine: false, ts: 3), reaction(key, on: "$m1")]
            return NSHostingView(rootView: row(events).fixedSize()).fittingSize.width
        }
        XCTAssertLessThan(rowWidth(mxc), rowWidth("👍") + 40, "the custom emoji is a picture, not its address")
    }

    /// Every label, value, help and tooltip in the view and its accessibility tree.
    private static func texts(of view: NSView) -> [String] {
        var found: [String] = []
        if let tip = view.toolTip { found.append(tip) }
        found += accessibilityTexts(of: view, depth: 0)
        for child in view.subviews { found += texts(of: child) }
        return found
    }

    private static func accessibilityTexts(of element: NSObject, depth: Int) -> [String] {
        guard depth < 12 else { return [] }
        var found: [String] = []
        for key in ["accessibilityLabel", "accessibilityValue", "accessibilityHelp", "accessibilityTitle"] {
            if let text = element.value(forKey: key) as? String { found.append(text) }
        }
        for child in (element.value(forKey: "accessibilityChildren") as? [NSObject]) ?? [] {
            found += accessibilityTexts(of: child, depth: depth + 1)
        }
        return found
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

    private final class Box { var width: CGFloat = 0 }

    private func bubbleWidth(_ event: Event, window: CGFloat) throws -> CGFloat {
        let box = Box()
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        let item = try XCTUnwrap(Fixture.items([event]).first { if case .message = $0 { true } else { false } })
        _ = try Snapshot.render("timeline-wide-text-\(Int(window))", width: window) {
            TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
                .overlayPreferenceValue(RowAnchorsKey.self) { anchors in
                    GeometryReader { geo in
                        Color.clear.onAppear { if let a = anchors.bubble { box.width = geo[a].width } }
                    }
                }
        }
        return box.width
    }

    func testPlainTextBubbleStopsAtAReadableWidth() throws {
        let long = String(repeating: "A long line of chat text that would stretch across a very wide window. ", count: 20)
        let wide = try bubbleWidth(Fixture.text("$w", long, mine: false, ts: 2), window: 1400)
        XCTAssertGreaterThan(wide, 300)
        XCTAssertLessThanOrEqual(wide, MessageRowView.textBubbleMaxWidth + 1, "capped at the text width")
        let narrow = try bubbleWidth(Fixture.text("$n", long, mine: false, ts: 2), window: 320)
        XCTAssertLessThanOrEqual(narrow, 320, "a narrow window still fits")
        XCTAssertGreaterThan(narrow, 150)
    }

    /// One very long word with no spaces breaks inside the bubble: not past the cap, not past a narrow window.
    func testAVeryLongWordStaysInsideTheBubble() throws {
        let word = String(repeating: "W", count: 400)
        let wide = try bubbleWidth(Fixture.text("$lw1", word, mine: false, ts: 2), window: 1400)
        XCTAssertLessThanOrEqual(wide, MessageRowView.textBubbleMaxWidth + 1)
        let narrow = try bubbleWidth(Fixture.text("$lw2", word, mine: false, ts: 2), window: 320)
        XCTAssertLessThanOrEqual(narrow, 320)
    }

    // MARK: 4/5. Time size and thread line

    private func fittingHeight(_ event: Event, showTimes: Bool) -> CGFloat {
        let ui = MessageUI()
        var actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        actions.showMessageTimestamps = showTimes
        let item = Fixture.items([event]).first { if case .message = $0 { true } else { false } }!
        let host = NSHostingView(rootView: TimelineItemView(item: item, isSelected: false, showsSent: false,
                                                            actions: actions, ui: ui)
                .frame(width: 420).fixedSize(horizontal: false, vertical: true))
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

    /// Right-to-left text ends on its left but the time is drawn at the right corner, so such a message gives the
    /// time a line of its own; left-to-right text keeps it on the end of its last line.
    func testRightToLeftTextGetsTheTimeOnItsOwnLine() {
        XCTAssertTrue(MessageRowView.containsRightToLeft("مرحبا بالعالم"))
        XCTAssertTrue(MessageRowView.containsRightToLeft("שלום עולם"))
        XCTAssertFalse(MessageRowView.containsRightToLeft("Hello"))
        let arabic = Fixture.text("$ar", "مرحبا بالعالم هذا اختبار", mine: false, ts: 5)
        let english = Fixture.text("$en", "Hello world, this is a test", mine: false, ts: 5)
        let arabicAdded = fittingHeight(arabic, showTimes: true) - fittingHeight(arabic, showTimes: false)
        let englishAdded = fittingHeight(english, showTimes: true) - fittingHeight(english, showTimes: false)
        XCTAssertGreaterThan(arabicAdded, lineHeight(11), "the time has its own line under the Arabic text")
        XCTAssertLessThan(englishAdded, 1, "the time shares the English text's last line")
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
        XCTAssertEqual(drawn, added(weight: .medium, size: 12), accuracy: 0.001, "the default is 12 pt medium")
        XCTAssertNotEqual(drawn, added(weight: .semibold, size: 12), accuracy: 0.5, "not semibold")
        XCTAssertNotEqual(drawn, added(weight: .medium, size: 10), accuracy: 0.5, "not 10 pt")
    }
}
