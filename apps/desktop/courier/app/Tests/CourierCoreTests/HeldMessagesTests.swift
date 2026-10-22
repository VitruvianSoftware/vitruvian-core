// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// What HeldMessages remembers stays bounded however long Courier runs. All data here is made up.
@MainActor
final class HeldMessagesTests: XCTestCase {
    /// Final fix wave: the messages that left hold (sent, undone, past their window) are remembered so a stale read
    /// never holds them again, but only the newest `maxSettled`, as MessageActionsModel caps its pending unsends.
    func testSettledIsCapped() {
        let held = HeldMessages()
        var clock = Date(timeIntervalSince1970: 1_000)
        held.now = { clock }
        let many = HeldMessages.maxSettled * 3
        for index in 0 ..< many {
            held.add("$\(index)", in: "!a", copy: HeldCopy(text: "x"), holdMillis: 0)
        }
        clock += 10 // every window, and its margin, is over
        XCTAssertEqual(held.ids(in: "!a"), [])
        XCTAssertLessThanOrEqual(held.settledCount, HeldMessages.maxSettled)

        // The newest that left hold are still known: a stale read showing one queued doesn't hold it again.
        held.add("$\(many - 1)", in: "!a", copy: HeldCopy(text: "x"), holdMillis: 10_000)
        XCTAssertEqual(held.ids(in: "!a"), [])
    }
}
