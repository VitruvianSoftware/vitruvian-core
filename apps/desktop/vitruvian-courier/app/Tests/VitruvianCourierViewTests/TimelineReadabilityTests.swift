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
    }

    private static func texts(of view: NSView) -> [String] {
        var found: [String] = []
        for string in [view.accessibilityLabel(), view.accessibilityValue() as? String, view.toolTip] {
            if let string { found.append(string) }
        }
        for child in view.subviews { found += texts(of: child) }
        for child in view.accessibilityChildren() ?? [] {
            if let element = child as? NSObject {
                for key in ["accessibilityLabel", "accessibilityValue", "accessibilityHelp"] {
                    if let text = element.value(forKey: key) as? String { found.append(text) }
                }
            }
        }
        return found
    }

    // MARK: 2. One time per run

    func testAPostOfSeveralFilesShowsItsTimeOnceOnTheLastItem() {
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
        _ = try? Snapshot.render("timeline-run-times", width: 520) { row(files) }
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

    // MARK: 4/5. Time size and thread line

    func testTimeIsDrawnAt11Points() {
        XCTAssertEqual(MessageRowView.metaPointSize, 11, "one step up from the 10 pt caption")
        XCTAssertEqual(MessageRowView.metaFont, Font.system(size: 11))
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

    func testThreadCountIsMediumWeightAt12Points() {
        XCTAssertEqual(ThreadSummaryLine.countWeight, .medium)
        XCTAssertEqual(ThreadSummaryLine.pointSize, 12)
    }

    func testThreadLineRenders() throws {
        let thread = ThreadSummary(replies: 1, lastTS: Fixture.millis(1), lastSenders: ["Chandini"])
        let event = Fixture.text("$t", "Can someone look at this?", mine: false, ts: 3, thread: thread)
        _ = try Snapshot.render("timeline-thread-line", width: 480) { row([event]) }
    }
}
