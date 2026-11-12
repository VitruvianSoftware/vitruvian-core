// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import XCTest

@testable import VitruvianCourier

/// Settings ▸ Appearance ▸ Use Liquid Glass on: a chat pane with the floating composer over the messages, and the
/// selected message's glass action bar with a who-reacted card. (The chat's name in the window's toolbar can't be drawn
/// here: there is no window toolbar offscreen.)
///
/// These show the layout only, not the glass. Liquid Glass is composited by the window server: drawn offscreen, as
/// here, a glass shape comes out as nothing at all (no material, no edge: the message box, its plus and the send button
/// are invisible, and the card's names sit straight on the row), checked on macOS 27.2; and the messages in the pane's
/// scroll view don't draw offscreen either, so the pane shows the composer's layout (where the reply and the text sit,
/// its insets) over an empty pane. Look at the glass itself in the test copy (README). They are skipped unless `--test_env=VITRUVIAN_COURIER_GLASS_SNAPSHOTS=1`, because on CI's headless Mac a
/// glass render never returned (the view tests timed out, PR #4238).
@MainActor
final class LiquidGlassSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["VITRUVIAN_COURIER_GLASS_SNAPSHOTS"] == "1" else {
            throw XCTSkip("glass renders need the window server: set VITRUVIAN_COURIER_GLASS_SNAPSHOTS=1 on a Mac with a display")
        }
        guard #available(macOS 26.0, *) else { throw XCTSkip("Liquid Glass needs macOS 26") }
    }

    private func composer(text: String) -> ComposerModel {
        let composer = ComposerModel(sender: SnapshotMessageSender(), draftDelay: 0, sleep: { _ in },
                                     now: { Fixture.now })
        composer.open(Fixture.room)
        composer.features = Fixture.features
        composer.network = "whatsapp"
        composer.text = text
        return composer
    }

    private func preferences() -> ComposerPreferences {
        let name = "courier.glass-snapshots.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return ComposerPreferences(defaults: ScratchDefaults.suite(named: name)!)
    }

    private func conversation() -> [Event] {
        [
            Fixture.text("$g1", "Are we still on for the hike on Saturday?", mine: false, ts: 40),
            Fixture.text("$g2", "Yes! I'll bring the map.", mine: true, ts: 38),
            Fixture.text("$g3", "The trail closes at sunset, so we should leave the car park by half past two at "
                + "the latest. Bring water and a warm layer.", mine: false, ts: 30),
            Fixture.text("$g4", "Half past two works.", mine: true, ts: 25),
            Fixture.text("$g5", "Shall I pick you up?", mine: false, ts: 20),
            Fixture.text("$g6", "Please, at two.", mine: true, ts: 12),
            Fixture.text("$g7", "See you then 👋", mine: false, ts: 5),
        ]
    }

    /// The pane as ConversationView lays it out with glass: the messages in a scroll view, the composer in a bar of
    /// its safe area (`courierEdgeBar`), floating over the messages' bottom.
    private func pane(composer: ComposerModel, preferences: ComposerPreferences, textHeight: CGFloat,
                      selected: String = "") -> some View {
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Fixture.items(conversation())) { item in
                    TimelineItemView(item: item, isSelected: item.id == selected, showsSent: false, actions: actions,
                                     ui: ui)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.bottom)
        .courierEdgeBar(.bottom) {
            ComposerView(composer: composer, preferences: preferences, textHeight: .constant(textHeight),
                         menus: ComposerMenus(sendLater: {}, createPoll: {}, pollsUnavailable: nil))
        }
        .environment(\.liquidGlass, true)
    }

    /// One line in the box: a capsule, with the plus a round button beside it, 12 points in from the sides and bottom.
    func testChatPaneWithTheFloatingComposer() throws {
        let preferences = preferences()
        let model = composer(text: "On my way")
        let sizes = try Snapshot.render("liquid-glass-on-chat-pane", width: 560, height: 420) {
            pane(composer: model, preferences: preferences, textHeight: ComposerTextView.minimumHeight)
        }
        XCTAssertEqual(sizes.count, 2)
    }

    /// Replying, two lines high: the reply sits in the same glass shape above the text, which has rounded corners now.
    func testChatPaneWithAGrownComposerAndAReply() throws {
        let preferences = preferences()
        let model = composer(text: "Sounds good.\nI'll bring snacks too.")
        model.startReply(to: QuotedMessage(eventID: "$g5", senderName: "Ann Example", mine: false,
                                           text: "Shall I pick you up?", kind: .text))
        let sizes = try Snapshot.render("liquid-glass-on-chat-pane-reply", width: 560, height: 420) {
            pane(composer: model, preferences: preferences, textHeight: 52, selected: "$g5")
        }
        XCTAssertEqual(sizes.count, 2)
    }

    /// The selected message's action bar as a glass capsule, and the who-reacted card as rounded glass.
    func testSelectedMessageBarAndReactionCard() throws {
        var events = [
            Fixture.text("$b0", "Who's coming to the picnic?", mine: true, ts: 30),
            Fixture.text("$b1", "Dinner at mine on Friday? I'll cook.", mine: false, ts: 20),
        ]
        for (index, name) in ["Bo", "Cy", "Di"].enumerated() {
            events.append(Fixture.event("$br\(index)", type: "m.reaction", mine: false, ts: 19 - index, content: [
                "m.relates_to": .object([
                    "rel_type": .string("m.annotation"), "event_id": .string("$b1"), "key": .string("👍"),
                ]),
            ], sender: "@\(name.lowercased()):courier.local", name: "\(name) Example"))
        }
        let ui = MessageUI()
        let actions = VitruvianCourier.MessageActions(now: { Fixture.now })
        let sizes = try Snapshot.render("liquid-glass-on-message-bar", width: 700) {
            VStack(spacing: 0) {
                ForEach(Fixture.items(events)) { item in
                    TimelineItemView(item: item, isSelected: item.id == "$b1", showsSent: false, actions: actions,
                                     ui: ui)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 60)
            .padding(.bottom, 14)
            .environment(\.reactionCardOverride, ReactionCardOverride(messageID: "$b1", reactionKey: "👍"))
            .environment(\.liquidGlass, true)
        }
        XCTAssertEqual(sizes.count, 2)
    }
}
