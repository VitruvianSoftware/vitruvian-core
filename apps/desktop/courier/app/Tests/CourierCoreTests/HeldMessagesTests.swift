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

    private func timeline(_ statuses: [(id: String, status: String)], at clock: Date) -> [TimelineItem] {
        let events = statuses.enumerated().map { index, entry in
            Event(eventID: entry.id, roomID: "!a", sender: Timeline.meUserID, senderName: "me", mine: true,
                  type: "m.room.message", content: .object(["msgtype": .string("m.text"), "body": .string("x")]),
                  ts: 1_000_000 + Int64(index), seq: Int64(index), status: EventStatus(rawValue: entry.status))
        }
        return Timeline.build(events: events, me: Timeline.meUserID, now: clock)
    }

    /// Ruling 18: a waiting message is held whenever the timeline shows it waiting, though it left hold before: a
    /// hand-off that found the network down again (waiting, Sending…, waiting), and a held message whose window ended
    /// while the network was down. Only one taken back by Undo stays gone, whatever a stale page shows.
    func testAMessageWaitingAgainIsHeldAgain() async {
        let held = HeldMessages()
        var clock = Date(timeIntervalSince1970: 1_000)
        held.now = { clock }
        held.update(from: timeline([("$w", "waiting")], at: clock), in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), ["$w"])
        held.update(from: timeline([("$w", "pending")], at: clock), in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), [], "on its way")
        held.update(from: timeline([("$w", "waiting")], at: clock), in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), ["$w"], "the network went down again: Don't Send takes it back")

        // Held for undo, its window ends while the network is down: it waits, and can still be taken back.
        held.add("$h", in: "!a", copy: HeldCopy(text: "x"), holdMillis: 5000)
        clock += 10 // past the window and its margin
        XCTAssertEqual(held.ids(in: "!a"), ["$w"])
        held.update(from: timeline([("$w", "waiting"), ("$h", "waiting")], at: clock), in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), ["$w", "$h"])

        // Taken back by Undo: a stale page that still shows it waiting never holds it again.
        let sender = FakeSender()
        sender.undoResults["$w"] = .success(Draft(text: "x", entities: [], replyTo: nil, threadRoot: nil))
        held.sender = { sender }
        let undone = await held.undoNewest(in: "!a", id: "$w")
        XCTAssertEqual(undone, .undone(HeldCopy(text: "x")))
        held.update(from: timeline([("$w", "waiting"), ("$h", "waiting")], at: clock), in: "!a")
        XCTAssertEqual(held.ids(in: "!a"), ["$h"])
    }
}
