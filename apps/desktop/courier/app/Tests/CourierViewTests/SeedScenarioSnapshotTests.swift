// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import XCTest

@testable import Courier

/// The group-threads scenario's group chat (the one the test copy opens with `--seed group-threads`), drawn light and
/// dark as seed-group-threads-*.png: the same made-up chat a person sees in the running copy. Like the other
/// snapshots, the asserts check only that it drew, and that the scenario became the timeline it describes.
@MainActor
final class SeedScenarioSnapshotTests: XCTestCase {
    func testGroupThreadsGroupChat() throws {
        let scenario = try SeedScenario.load("group-threads")
        let events = try scenario.events(chat: "grp-launch")
        let messages = Fixture.messages(events)
        // m1…m9: the group's messages outside its two threads.
        XCTAssertEqual(messages.count, 9)
        let roots = events.filter { $0.thread != nil }
        XCTAssertEqual(roots.map { $0.thread?.replies }, [3, 2], "both threads' roots carry their summaries")
        XCTAssertTrue(events.contains { $0.type == "m.reaction" })
        XCTAssertTrue(events.contains { $0.mine })
        XCTAssertTrue(events.contains { $0.senderName == "Ann Example" })

        let ui = MessageUI()
        var actions = Courier.MessageActions(now: { Fixture.now })
        actions.openThread = { _ in }
        let sizes = try Snapshot.render("seed-group-threads", width: 620) {
            VStack(spacing: 0) {
                ForEach(Fixture.items(events)) { item in
                    TimelineItemView(item: item, isSelected: false, showsSent: false, actions: actions, ui: ui)
                }
            }
            .padding(14)
        }
        XCTAssertEqual(sizes.count, 2)
        for size in sizes {
            XCTAssertGreaterThan(size.width, 100)
            XCTAssertGreaterThan(size.height, 300, "nine messages, not an empty timeline")
        }
    }
}
