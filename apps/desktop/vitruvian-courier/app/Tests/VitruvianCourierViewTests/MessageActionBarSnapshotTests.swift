// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// The selected message: its action bar on the bubble's corner, the add-reaction chip, and who reacted. A click (or the
/// arrow keys) selects a message, and only the selected one shows its bar, so these draw a row with `isSelected`; the
/// harness can't rest a pointer on a reaction chip, so `reactionCardOverride` opens a card. Look at message-bar-*:
/// beside a short bubble the bar sits on its outer side, level with it, and the message above stays readable; over a
/// wide one it sits on the top outer corner, inside the row; the card names who reacted.
@MainActor
final class MessageActionBarSnapshotTests: XCTestCase {
    private static let width: CGFloat = 700

    private func reaction(_ id: String, to target: String, key: String, ts minutesAgo: Int, sender: String,
                          name: String, mine: Bool = false) -> Event {
        Fixture.event(id, type: "m.reaction", mine: mine, ts: minutesAgo, content: [
            "m.relates_to": .object([
                "rel_type": .string("m.annotation"), "event_id": .string(target), "key": .string(key),
            ]),
        ], sender: mine ? nil : sender, name: name)
    }

    private func timeline(_ events: [Event], selected: String, card: String? = nil, bottom: CGFloat = 14) -> some View {
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        return VStack(spacing: 0) {
            ForEach(Fixture.items(events)) { item in
                TimelineItemView(item: item, isSelected: item.id == selected, showsSent: false, actions: actions,
                                 ui: ui)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 40)
        .padding(.bottom, bottom)
        .environment(\.reactionCardOverride, card.map { ReactionCardOverride(messageID: selected, reactionKey: $0) })
    }

    private func render<V: View>(_ name: String, _ view: () -> V) throws {
        let sizes = try Snapshot.render(name, width: Self.width, view)
        XCTAssertEqual(sizes.count, 2)
        for size in sizes { XCTAssertGreaterThan(size.height, 60) }
    }

    /// The key case: a short message from someone else. The bar is beside the bubble, not at the window's edge, and
    /// not over the message above.
    func testTheirShortMessageSelected() throws {
        let events = [
            Fixture.text("$h1", "Are we still on for the hike on Saturday?", mine: false, ts: 9),
            Fixture.text("$h2", "Hi!", mine: false, ts: 8),
            Fixture.text("$h3", "Yes, see you at eight.", mine: true, ts: 2),
        ]
        try render("message-bar-theirs-short") { timeline(events, selected: "$h2") }
    }

    /// "Hi!" right under a longer message from the same sender: the bar goes beside "Hi!", and the message above
    /// stays readable.
    func testTheirShortMessageUnderTheirLongerOneSelected() throws {
        let events = [
            Fixture.text("$s1", "Are we still on for the hike on Saturday? I can drive if you need a lift.",
                         mine: false, ts: 9),
            Fixture.text("$s2", "Hi!", mine: false, ts: 8),
        ]
        try render("message-bar-theirs-short-after-same-sender") { timeline(events, selected: "$s2") }
    }

    func testMyMessageSelected() throws {
        let events = [
            Fixture.text("$m1", "Are we still on for the hike on Saturday?", mine: false, ts: 9),
            Fixture.text("$m2", "Yes, see you at eight.", mine: true, ts: 3),
            Fixture.text("$m3", "On my way", mine: true, ts: 2),
        ]
        try render("message-bar-mine") { timeline(events, selected: "$m3") }
    }

    /// The events for the reaction card: three chips on "$c1", one of them mine, the first from twelve people.
    private func reactedEvents() -> [Event] {
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
        return events
    }

    /// The card open on the chip twelve people gave: "… and 2 others". The message is selected too, so its bar and
    /// the add-reaction chip after the chips show.
    func testReactionCardOnAChipTwelvePeopleGave() throws {
        let events = reactedEvents()
        let chips = try XCTUnwrap(Fixture.messages(events).first { $0.id == "$c1" }).reactions
        XCTAssertEqual(chips.map(\.count), [12, 2, 1])
        XCTAssertTrue(chips[0].summary(maxNames: 10).hasSuffix("2 others reacted with 👍"))
        try render("message-bar-reaction-card") { timeline(events, selected: "$c1", card: "👍") }
    }

    /// A short message, its bar beside it: the card above the chip would cover the bar's first reactions, so it goes
    /// below the chip (ReactionCardPlacement).
    func testReactionCardGoesBelowTheChipToKeepOffTheBar() throws {
        var events = [
            Fixture.text("$w0", "Do you still have the spare poles?", mine: true, ts: 30),
            Fixture.text("$w1", "Weather looks fine.", mine: false, ts: 20),
        ]
        for (index, name) in ["Bo", "Cy", "Di"].enumerated() {
            events.append(reaction("$wr\(index)", to: "$w1", key: "👍", ts: 19 - index,
                                   sender: "@\(name.lowercased()):courier.local", name: "\(name) Example"))
        }
        try render("message-bar-reaction-card-below") { timeline(events, selected: "$w1", card: "👍", bottom: 110) }
    }

    /// A message nearly as wide as the timeline: no room beside it, so the bar sits over its top corner, inside the row.
    func testTheirLongMessageSelected() throws {
        let long = "The trail closes at sunset, so we should leave the car park by half past two at the latest. "
            + "Bring water, a warm layer, and something to eat at the top; the café there shuts early on Saturdays."
        let events = [
            Fixture.text("$l1", "Plan for Saturday:", mine: false, ts: 9),
            Fixture.text("$l2", long, mine: false, ts: 8),
        ]
        try render("message-bar-theirs-long") { timeline(events, selected: "$l2") }
    }

    /// Nothing selected: no bar, no add-reaction chip and no tint on any row (pointing at a message shows nothing).
    func testNothingSelectedShowsNoBar() throws {
        let events = [
            Fixture.text("$n1", "Are we still on for the hike on Saturday?", mine: false, ts: 9),
            Fixture.text("$n2", "Yes, see you at eight.", mine: true, ts: 3),
        ]
        try render("message-bar-none") { timeline(events, selected: "") }
    }
}
