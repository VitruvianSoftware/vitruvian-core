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

    /// Review Focus 1: a message waiting for its network is held however long that takes, so Don't Send (Undo) can
    /// always take it back; one held for undo whose window ended while the network was down becomes one.
    func testAWaitingMessageIsHeldWithNoWindow() {
        let held = HeldMessages()
        var clock = Date(timeIntervalSince1970: 1_000)
        held.now = { clock }
        func timeline(_ statuses: [(String, String, String)]) -> [TimelineItem] {
            let events = statuses.enumerated().map { index, entry in
                Event(eventID: entry.0, roomID: "!a", sender: Timeline.meUserID, senderName: "me", mine: true,
                      type: "m.room.message", content: .object(["msgtype": .string("m.text"), "body": .string("x")]),
                      ts: 1_000_000 + Int64(index), seq: Int64(index), status: EventStatus(rawValue: entry.1),
                      statusReason: entry.2)
            }
            return Timeline.build(events: events, me: Timeline.meUserID, now: clock)
        }
        held.add("$held", in: "!a", copy: HeldCopy(text: "x"), holdMillis: 5000)
        let shown = timeline([("$held", "waiting", ""), ("$late", "waiting", "no account"), ("$sent", "sent", "")])
        held.update(from: shown, in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), ["$held", "$late"])
        clock += 24 * 3600 // a day: far past any window
        XCTAssertEqual(held.ids(in: "!a"), ["$held", "$late"], "they wait as long as their network does")
        // Gone once it has gone.
        held.update(from: timeline([("$held", "sent", ""), ("$late", "waiting", "no account")]), in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), ["$late"])
    }
}
