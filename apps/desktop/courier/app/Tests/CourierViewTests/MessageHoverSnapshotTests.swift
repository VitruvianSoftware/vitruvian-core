// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// A message row under the pointer: the hover bar on the bubble's corner, the add-reaction chip, and who reacted. The
/// harness can't move a pointer, so `messageRowHoverOverride` draws a row as hovered. Look at message-hover-*: beside
/// a short bubble the bar sits on its outer side, level with it, and the message above stays readable; over a wide
/// one it sits on the top outer corner, inside the row; the card names who reacted.
@MainActor
final class MessageHoverSnapshotTests: XCTestCase {
    private static let width: CGFloat = 700

    private func reaction(_ id: String, to target: String, key: String, ts minutesAgo: Int, sender: String,
                          name: String, mine: Bool = false) -> Event {
        Fixture.event(id, type: "m.reaction", mine: mine, ts: minutesAgo, content: [
            "m.relates_to": .object([
                "rel_type": .string("m.annotation"), "event_id": .string(target), "key": .string(key),
            ]),
        ], sender: mine ? nil : sender, name: name)
    }

    private func timeline(_ events: [Event], hovered: String, card: String? = nil) -> some View {
        let ui = MessageUI()
        let actions = Courier.MessageActions(now: { Fixture.now })
        return VStack(spacing: 0) {
            ForEach(Fixture.items(events)) { item in
                TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 40)
        .padding(.bottom, 14)
        .environment(\.messageRowHoverOverride, MessageRowHoverOverride(messageID: hovered, reactionCardKey: card))
    }

    private func render<V: View>(_ name: String, _ view: () -> V) throws {
        let sizes = try Snapshot.render(name, width: Self.width, view)
        XCTAssertEqual(sizes.count, 2)
        for size in sizes { XCTAssertGreaterThan(size.height, 60) }
    }

    /// The key case: a short message from someone else. The bar is beside the bubble, not at the window's edge, and
    /// not over the message above.
    func testTheirShortMessageHovered() throws {
        let events = [
            Fixture.text("$h1", "Are we still on for the hike on Saturday?", mine: false, ts: 9),
            Fixture.text("$h2", "Hi!", mine: false, ts: 8),
            Fixture.text("$h3", "Yes, see you at eight.", mine: true, ts: 2),
        ]
        try render("message-hover-theirs-short") { timeline(events, hovered: "$h2") }
    }

    /// "Hi!" right under a longer message from the same sender: the bar goes beside "Hi!", and the message above
    /// stays readable.
    func testTheirShortMessageUnderTheirLongerOneHovered() throws {
        let events = [
            Fixture.text("$s1", "Are we still on for the hike on Saturday? I can drive if you need a lift.",
                         mine: false, ts: 9),
            Fixture.text("$s2", "Hi!", mine: false, ts: 8),
        ]
        try render("message-hover-theirs-short-after-same-sender") { timeline(events, hovered: "$s2") }
    }

    func testMyMessageHovered() throws {
        let events = [
            Fixture.text("$m1", "Are we still on for the hike on Saturday?", mine: false, ts: 9),
            Fixture.text("$m2", "Yes, see you at eight.", mine: true, ts: 3),
            Fixture.text("$m3", "On my way", mine: true, ts: 2),
        ]
        try render("message-hover-mine") { timeline(events, hovered: "$m3") }
    }

    /// Three chips, one of them mine, and the card open on the one twelve people gave: "… and 2 others".
    func testReactionCardOnAChipTwelvePeopleGave() throws {
        let names = ["Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal", "Ivy", "Jo", "Kit", "Lou", "Max"]
        var events = [
            Fixture.text("$c0", "Who's coming to the picnic?", mine: true, ts: 30),
            Fixture.text("$c1", "Dinner at mine on Friday? I'll cook.", mine: false, ts: 20),
        ]
        for (index, name) in names.enumerated() {
            events.append(reaction("$cr\(index)", to: "$c1", key: "👍", ts: 19 - index % 5,
                                   sender: "@\(name.lowercased()):courier.local", name: "\(name) Example"))
        }
        events.append(reaction("$cm", to: "$c1", key: "❤️", ts: 12, sender: "", name: "", mine: true))
        events.append(reaction("$cb", to: "$c1", key: "❤️", ts: 11, sender: "@bo:courier.local", name: "Bo Example"))
        events.append(reaction("$cc", to: "$c1", key: "😂", ts: 10, sender: "@cy:courier.local", name: "Cy Example"))
        let chips = try XCTUnwrap(Fixture.messages(events).first { $0.id == "$c1" }).reactions
        XCTAssertEqual(chips.map(\.count), [12, 2, 1])
        XCTAssertTrue(chips[0].summary(maxNames: 10).hasSuffix("2 others reacted with 👍"))
        try render("message-hover-reaction-card") { timeline(events, hovered: "$c1", card: "👍") }
    }

    /// A message nearly as wide as the timeline: no room beside it, so the bar sits over its top corner, inside the row.
    func testTheirLongMessageHovered() throws {
        let long = "The trail closes at sunset, so we should leave the car park by half past two at the latest. "
            + "Bring water, a warm layer, and something to eat at the top; the café there shuts early on Saturdays."
        let events = [
            Fixture.text("$l1", "Plan for Saturday:", mine: false, ts: 9),
            Fixture.text("$l2", long, mine: false, ts: 8),
        ]
        try render("message-hover-theirs-long") { timeline(events, hovered: "$l2") }
    }
}
