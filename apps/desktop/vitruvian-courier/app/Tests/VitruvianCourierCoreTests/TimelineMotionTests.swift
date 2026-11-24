// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import VitruvianCourierCore

@MainActor
final class TimelineMotionTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    override func tearDown() async throws {
        for h in harnesses { await h.stop() }
        harnesses = []
    }

    private func history(_ count: Int, room: String) -> [[String: Any]] {
        (1 ... count).map { textEvent(id: "\(room)$\($0)", room: room, at: Int64($0), body: "Message \($0)") }
    }

    private func start(
        _ events: [String: [[String: Any]]],
        rows: [String: InboxRow] = [:],
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> ConversationHarness {
        let h = try await startConversation(events, rows: rows, sleep: sleep)
        harnesses.append(h)
        return h
    }

    // MARK: - Item 1: A chat's identity switches at once; only its messages wait

    /// Straight after the selection moves, before the new chat's page can have arrived, everything that acts on a
    /// chat points at the new one: header, composer (so send, paste, drop and the draft), the commands' target and
    /// the scheduled strip. The old chat's messages are gone.
    func testEveryChatTargetSwitchesInTheSameTurnAsTheSelection() async throws {
        let rowA = chatRow("!a", name: "Alice", network: "whatsapp", direct: true)
        let rowB = chatRow("!b", name: "Bob", network: "signal", direct: true)
        let h = try await start(["!a": history(2, room: "!a"), "!b": history(2, room: "!b")],
                                rows: ["!a": rowA, "!b": rowB])
        let scheduled = ScheduledModel(appModel: h.app)
        try await h.open("!a")
        h.conversation.composer.text = "half written for Alice"

        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        // No waiting: this is the turn the selection moved in.
        XCTAssertEqual(h.conversation.roomID, "!b", "commands, hotkeys and chat info act on the open chat")
        XCTAssertEqual(h.conversation.composer.roomID, "!b", "send, paste, drop and the draft")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "!b", "the header")
        XCTAssertEqual(scheduled.roomID, "!b", "the scheduled strip")
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertTrue(h.conversation.items.isEmpty, "the old chat's messages are never shown under the new chat")
        XCTAssertNotEqual(h.conversation.composer.text, "half written for Alice", "the old chat's draft stays with it")

        // A send now goes to the new chat, though its messages have not arrived.
        h.script.overrides["message.send"] = .result(["event_id": "$sentB"])
        var sending: Task<Void, Never>?
        for _ in 0 ..< 50 where sending == nil {
            h.conversation.composer.text = "to Bob"
            sending = h.conversation.composer.submit()
            if sending == nil { try await Task.sleep(for: .milliseconds(20)) }
        }
        XCTAssertNotNil(sending, "the composer sends")
        await sending?.value
        let sent = h.server.receivedParams("message.send")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["room_id"] as? String, "!b", "the send went to the new chat")
        XCTAssertEqual(sent.first?["text"] as? String, "to Bob")
    }

    func testPlaceholdersWaitThenAreMessageShaped() {
        XCTAssertEqual(TimelineLoadMotion.placeholderDelay, .milliseconds(120), "neutral for the first 120 ms")
        let rows = TimelineLoadMotion.placeholderRows()
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows, TimelineLoadMotion.placeholderRows(), "the same every time")
        XCTAssertTrue(rows.contains { $0.fromMe } && rows.contains { !$0.fromMe })
    }

    // MARK: - Item 1: Reading a first page ahead of time

    private func fiveChats() -> [String: [[String: Any]]] {
        var events: [String: [[String: Any]]] = [:]
        for room in ["!a", "!b", "!c", "!d", "!e"] { events[room] = history(3, room: room) }
        return events
    }

    private func roomEventsRooms(_ h: ConversationHarness) -> [String] {
        h.server.receivedParams("room.events").compactMap { $0["room_id"] as? String }
    }

    func testHoverReadsTheFirstPageAfter80msAndThenOpeningShowsItAtOnce() async throws {
        let time = FakeTime()
        let h = try await start(fiveChats(), sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")
        let before = h.server.receivedMethods().count

        h.conversation.hoverPrefetch("!b", inside: true)
        try await waitUntil { time.pendingSleeps == [0.08] }
        time.advance(0.079)
        await Task.yield()
        XCTAssertFalse(roomEventsRooms(h).contains("!b"), "not before the pointer has rested 80 ms")
        time.advance(0.001)
        try await waitUntil { h.conversation.prefetchedRoomsForTesting == ["!b"] }

        // Read-only: the only thing asked of the engine was the page itself.
        XCTAssertEqual(Array(h.server.receivedMethods().dropFirst(before)), ["room.events"])

        // Opening it draws its messages in the same turn, while the newest page is read again.
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        XCTAssertTrue(h.conversation.isLoaded, "from the page read ahead, with no wait")
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!b$1", "!b$2", "!b$3"])
        XCTAssertEqual(h.conversation.roomID, "!b")
        XCTAssertEqual(h.conversation.prefetchedRoomsForTesting, [], "now kept like any opened chat")
    }

    func testMovingOnOrLeavingDropsTheHoverRead() async throws {
        let time = FakeTime()
        let h = try await start(fiveChats(), sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")

        h.conversation.hoverPrefetch("!b", inside: true)
        try await waitUntil { time.pendingSleeps == [0.08] }
        h.conversation.hoverPrefetch("!c", inside: true) // superseded: the wait for !b is dropped
        try await waitUntil { time.pendingSleeps == [0.08] }
        time.advance(0.1)
        try await waitUntil { h.conversation.prefetchedRoomsForTesting == ["!c"] }
        XCTAssertFalse(roomEventsRooms(h).contains("!b"))

        h.conversation.hoverPrefetch("!d", inside: true)
        try await waitUntil { time.pendingSleeps == [0.08] }
        h.conversation.hoverPrefetch("!d", inside: false) // the pointer left
        time.advance(0.1)
        await Task.yield()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(roomEventsRooms(h).contains("!d"))
    }

    func testALateAnswerNeverOverwritesTheChatOpenedMeanwhile() async throws {
        let time = FakeTime()
        let h = try await start(fiveChats(), sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")
        h.script.hold("!b")
        h.conversation.hoverPrefetch("!b", inside: true)
        try await waitUntil { time.pendingSleeps == [0.08] }
        time.advance(0.1)
        try await waitUntil { self.roomEventsRooms(h).contains("!b") } // the read ahead is in flight

        h.app.selectedRoomID = "!b" // opened before its answer: it reads its own page
        try await waitUntil { self.roomEventsRooms(h).filter { $0 == "!b" }.count == 2 }
        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { h.conversation.isLoaded }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!b$1", "!b$2", "!b$3"], "each message once")
        XCTAssertEqual(h.conversation.prefetchedRoomsForTesting, [], "the late read ahead was not kept")
    }

    func testTheWarmUpIsBoundedSkipsHeldChatsAndOnlyReads() async throws {
        let time = FakeTime()
        var events: [String: [[String: Any]]] = [:]
        let rooms = (1 ... 24).map { "!r\($0)" }
        for room in rooms { events[room] = history(2, room: room) }
        let h = try await start(events, sleep: { try await time.sleep(for: $0) })
        try await h.open("!r1")
        let before = h.server.receivedMethods().count

        h.conversation.warmFirstPages(of: rooms) // the open chat is in the list: skipped
        for _ in 0 ..< 60 {
            if time.pendingSleeps.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
            time.advance(3)
        }
        try await waitUntil { h.conversation.prefetchedRoomsForTesting.count == ConversationModel.prefetchLimit - 1 }
        XCTAssertFalse(h.conversation.prefetchedRoomsForTesting.contains("!r1"))
        XCTAssertLessThanOrEqual(h.conversation.prefetchedRoomsForTesting.count, ConversationModel.prefetchLimit)
        let after = Array(h.server.receivedMethods().dropFirst(before))
        XCTAssertTrue(after.allSatisfy { $0 == "room.events" }, "read-only: \(Set(after))")
        XCTAssertLessThanOrEqual(after.count, ConversationModel.prefetchLimit)
    }

    func testReadsAheadNeverEvictAChatThatWasOpenedAndStayWithinTheCacheLimit() async throws {
        let time = FakeTime()
        var events: [String: [[String: Any]]] = [:]
        for index in 1 ... 30 { events["!r\(index)"] = history(2, room: "!r\(index)") }
        let h = try await start(events, sleep: { try await time.sleep(for: $0) })
        try await h.open("!r1")
        try await h.open("!r2") // !r1 is kept now, as an opened chat
        h.conversation.warmFirstPages(of: (3 ... 30).map { "!r\($0)" })
        for _ in 0 ..< 60 {
            if time.pendingSleeps.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
            time.advance(3)
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(h.conversation.isCached("!r1"), "a chat opened before is not pushed out by reads ahead")
        XCTAssertLessThanOrEqual(h.conversation.prefetchedRoomsForTesting.count, ConversationModel.prefetchLimit)
    }

    /// Chat B's enter can come before chat A's exit. A's exit then cancels only A's own wait, never B's.
    func testLeavingOneChatNeverCancelsTheReadOfTheOneEnteredNext() async throws {
        let time = FakeTime()
        let h = try await start(fiveChats(), sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")

        h.conversation.hoverPrefetch("!b", inside: true)
        try await waitUntil { time.pendingSleeps == [0.08] }
        h.conversation.hoverPrefetch("!c", inside: true) // the pointer is on !c now
        h.conversation.hoverPrefetch("!b", inside: false) // !b's exit arrives late
        try await waitUntil { time.pendingSleeps == [0.08] }
        time.advance(0.1)
        try await waitUntil { h.conversation.prefetchedRoomsForTesting == ["!c"] }

        h.conversation.hoverPrefetch("!c", inside: false) // its own exit does cancel it
        h.conversation.hoverPrefetch("!d", inside: true)
        h.conversation.hoverPrefetch("!d", inside: false)
        time.advance(0.1)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(roomEventsRooms(h).contains("!d"))
    }

    /// One read ahead at a time, whether from a hover or the idle warm-up, and the hover goes next.
    func testOnlyOneReadAheadIsInFlightAndAHoverGoesBeforeTheWarmUp() async throws {
        let time = FakeTime()
        var events = fiveChats()
        for room in ["!w1", "!w2", "!w3", "!h"] { events[room] = history(2, room: room) }
        let h = try await start(events, sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")

        h.script.hold("!w1")
        h.conversation.warmFirstPages(of: ["!w1", "!w2", "!w3"])
        try await waitUntil { time.pendingSleeps == [2] }
        time.advance(2)
        try await waitUntil { self.roomEventsRooms(h).contains("!w1") } // the warm-up's read is in flight

        h.conversation.hoverPrefetch("!h", inside: true)
        try await waitUntil { time.pendingSleeps.contains(0.08) }
        time.advance(0.08)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(roomEventsRooms(h).filter { ["!w1", "!w2", "!w3", "!h"].contains($0) }, ["!w1"],
                       "the hover waits: only one read ahead is asked of the engine at a time")

        h.server.releaseHeld(method: "room.events", room: "!w1",
                             with: ["events": h.script.newestFirst("!w1", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { h.conversation.prefetchedRoomsForTesting.contains("!h") }
        XCTAssertEqual(roomEventsRooms(h).filter { ["!w1", "!w2", "!w3", "!h"].contains($0) }, ["!w1", "!h"],
                       "the hover goes before the next of the warm-up")
        for _ in 0 ..< 10 {
            if time.pendingSleeps.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
            time.advance(1)
        }
        try await waitUntil { h.conversation.prefetchedRoomsForTesting.count == 4 }
    }

    /// A page read ahead is dropped when anything changes in its chat, so opening it never shows a message that was
    /// removed or replaced meanwhile.
    func testAChangeInAChatDropsItsPageReadAhead() async throws {
        let time = FakeTime()
        let h = try await start(fiveChats(), sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")

        for (index, change) in [["kind": "event", "room_id": "!b", "event_id": "$new"],
                                ["kind": "status", "room_id": "!b", "event_id": "!b$1"],
                                ["kind": "room", "room_id": "!b"]].enumerated() {
            h.conversation.hoverPrefetch("!b", inside: true)
            try await waitUntil { time.pendingSleeps.contains(0.08) }
            time.advance(0.08)
            try await waitUntil { h.conversation.prefetchedRoomsForTesting == ["!b"] }
            h.server.notify(change)
            try await waitUntil { h.conversation.prefetchedRoomsForTesting.isEmpty }
            XCTAssertFalse(h.conversation.isCached("!b"), "change \(index): nothing stale is left to open")
            h.conversation.hoverPrefetch("!b", inside: false)
        }

        // Opened now, it reads its page fresh: not drawn from anything.
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertTrue(h.conversation.items.isEmpty)
    }

    /// A change that lands while the page is still being read drops that page when it arrives.
    func testAChangeWhileThePageIsBeingReadDropsIt() async throws {
        let time = FakeTime()
        let h = try await start(fiveChats(), sleep: { try await time.sleep(for: $0) })
        try await h.open("!a")
        h.script.hold("!b")
        h.conversation.hoverPrefetch("!b", inside: true)
        try await waitUntil { time.pendingSleeps.contains(0.08) }
        time.advance(0.08)
        try await waitUntil { self.roomEventsRooms(h).contains("!b") }
        h.server.notify(["kind": "event", "room_id": "!b", "event_id": "$gone"])
        try await Task.sleep(for: .milliseconds(100))
        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(h.conversation.prefetchedRoomsForTesting, [], "the page read before the change is not kept")
    }

    /// At the limit the idle warm-up neither churns nor pushes anything out; only a hover makes room, by dropping the
    /// oldest page read ahead, never a chat that was opened.
    func testEvictionPastTheLimitDoesNotChurnOrDropAnOpenedChat() async throws {
        let time = FakeTime()
        var events: [String: [[String: Any]]] = [:]
        for index in 1 ... 32 { events["!r\(index)"] = history(2, room: "!r\(index)") }
        let h = try await start(events, sleep: { try await time.sleep(for: $0) })
        try await h.open("!r1")
        try await h.open("!r2") // !r1 is kept as an opened chat

        func hover(_ room: String) async throws {
            h.conversation.hoverPrefetch(room, inside: true)
            try await waitUntil { time.pendingSleeps.contains(0.08) }
            time.advance(0.08)
            try await waitUntil { h.conversation.prefetchedRoomsForTesting.contains(room) }
            h.conversation.hoverPrefetch(room, inside: false)
        }
        func runWarmUp() async throws {
            for _ in 0 ..< 80 {
                if time.pendingSleeps.isEmpty { try await Task.sleep(for: .milliseconds(30)) }
                time.advance(3)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let hovered = ["!r25", "!r26", "!r27", "!r28"]
        for room in hovered { try await hover(room) }

        // Sixteen to warm, room for twelve: the four that were hovered stay, nothing is pushed out for the rest.
        let warmList = (3 ... 18).map { "!r\($0)" }
        h.conversation.warmFirstPages(of: warmList)
        try await runWarmUp()
        XCTAssertEqual(h.conversation.prefetchedRoomsForTesting.count, ConversationModel.prefetchLimit)
        XCTAssertTrue(hovered.allSatisfy { h.conversation.prefetchedRoomsForTesting.contains($0) },
                      "the warm-up pushed a hovered page out")
        let held = h.conversation.prefetchedRoomsForTesting
        let readsBefore = h.count("room.events")

        // Warming the same list again reads nothing: no page is read only to push another out.
        h.conversation.warmFirstPages(of: warmList)
        try await runWarmUp()
        XCTAssertEqual(h.count("room.events"), readsBefore, "no read at the limit")
        XCTAssertEqual(h.conversation.prefetchedRoomsForTesting, held)

        // A hover does make room: the oldest page read ahead goes, the opened chats stay.
        try await hover("!r30")
        XCTAssertEqual(h.conversation.prefetchedRoomsForTesting.count, ConversationModel.prefetchLimit)
        XCTAssertFalse(h.conversation.prefetchedRoomsForTesting.contains(held[0]), "the oldest went")
        XCTAssertTrue(h.conversation.isCached("!r1"), "an opened chat is never the one dropped")
        XCTAssertTrue(h.conversation.isCached("!r2") || h.conversation.roomID == "!r2")
    }

    func testTheReceiptLineMoveIsEasedOnlyAtTheBottomAndNotUnderReduceMotion() {
        func eases(_ ids: [String], at bottom: Bool = true, rm: Bool = false) -> Bool {
            StatusLineStability.easesReceiptMove(changedHeightIDs: ids, previousReceiptID: "$1", currentReceiptID: "$2",
                                                 isAtBottom: bottom, reduceMotion: rm)
        }
        XCTAssertEqual(StatusLineStability.receiptEaseDuration, 0.15, accuracy: 0.0001)
        XCTAssertTrue(eases(["$1"]))
        XCTAssertTrue(eases(["$1", "$2"]))
        XCTAssertFalse(eases(["$1"], rm: true), "instant under Reduce Motion")
        XCTAssertFalse(eases(["$1"], at: false), "nothing the person is reading is moved")
        XCTAssertFalse(eases(["$1", "$9"]), "some other row changed height: not this move")
        XCTAssertFalse(eases([]))
        XCTAssertFalse(StatusLineStability.easesReceiptMove(changedHeightIDs: ["$1"], previousReceiptID: "$1",
                                                            currentReceiptID: "$1", isAtBottom: true, reduceMotion: false))
    }

    /// The jump from a search result ends "away" at once, the bottom is reached a moment later: the button keeps
    /// its "Jump to latest" words so its width does not snap.
    func testJumpButtonHoldsItsWordsBetweenTheJumpAndReachingTheBottom() {
        let away = JumpToLatestLabel(isAwayFromLatest: true, hasNewerWhileAway: false, newMessageCount: 0)
        let plain = JumpToLatestLabel(isAwayFromLatest: false, hasNewerWhileAway: false, newMessageCount: 0)
        let counted = JumpToLatestLabel(isAwayFromLatest: false, hasNewerWhileAway: false, newMessageCount: 3)
        XCTAssertEqual(JumpToLatestLabel.displayed(current: plain, lastShown: away, held: away, isVisible: true), away)
        XCTAssertEqual(JumpToLatestLabel.displayed(current: counted, lastShown: away, held: away, isVisible: true), counted,
                       "new messages say their own count")
        XCTAssertEqual(JumpToLatestLabel.displayed(current: plain, lastShown: away, held: nil, isVisible: true), plain)
        XCTAssertEqual(JumpToLatestLabel.displayed(current: plain, lastShown: away, held: away, isVisible: false), away)
    }

    // MARK: - Item 6: Jump-to-Latest Motion Constants

    func testJumpToLatestMotionConstantsAndDelay() {
        XCTAssertEqual(JumpToLatestMotion.fadeDuration, 0.15, accuracy: 0.0001)
        XCTAssertEqual(JumpToLatestMotion.appearDelay, 0.05, accuracy: 0.0001)
        XCTAssertEqual(JumpToLatestMotion.disappearDelay, 0, accuracy: 0.0001)
        XCTAssertEqual(JumpToLatestMotion.delay(appearing: true, reduceMotion: false), 0.05, accuracy: 0.0001)
        XCTAssertEqual(JumpToLatestMotion.delay(appearing: false, reduceMotion: false), 0, accuracy: 0.0001)
        XCTAssertEqual(JumpToLatestMotion.delay(appearing: true, reduceMotion: true), 0, accuracy: 0.0001)
        XCTAssertLessThan(JumpToLatestMotion.duration(reduceMotion: true), JumpToLatestMotion.fadeDuration)
    }

    /// The count resets to 0 as the bottom comes into view, while the button is still fading out: it keeps the words
    /// it had, so its width does not snap.
    func testJumpButtonKeepsItsWordsWhileFadingOut() {
        let withCount = JumpToLatestLabel(isAwayFromLatest: false, hasNewerWhileAway: false, newMessageCount: 2)
        let reset = JumpToLatestLabel(isAwayFromLatest: false, hasNewerWhileAway: false, newMessageCount: 0)
        XCTAssertEqual(JumpToLatestLabel.displayed(current: reset, lastShown: withCount, isVisible: false), withCount)
        XCTAssertEqual(JumpToLatestLabel.displayed(current: withCount, lastShown: reset, isVisible: true), withCount,
                       "while it shows, it follows the live state")
    }

    // MARK: - Item 7: Sent Message Rise-In Eligibility & Transform

    func testSentMessageRiseConstantsAndReduceMotion() {
        XCTAssertEqual(SentMessageRiseMotion.duration, 0.26, accuracy: 0.0001)
        XCTAssertEqual(SentMessageRiseMotion.controlPoints.0, 0.22, accuracy: 0.0001)
        XCTAssertEqual(SentMessageRiseMotion.controlPoints.1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(SentMessageRiseMotion.controlPoints.2, 0.36, accuracy: 0.0001)
        XCTAssertEqual(SentMessageRiseMotion.controlPoints.3, 1.0, accuracy: 0.0001)

        let normal = SentMessageRiseMotion.initialTransform(reduceMotion: false)
        XCTAssertEqual(normal.opacity, 0, accuracy: 0.0001)
        XCTAssertEqual(normal.offsetY, 14, accuracy: 0.0001)
        XCTAssertEqual(normal.scale, 0.97, accuracy: 0.0001)
        XCTAssertTrue(normal.usesMovementAndScale)

        let reduced = SentMessageRiseMotion.initialTransform(reduceMotion: true)
        XCTAssertEqual(reduced.opacity, 0, accuracy: 0.0001)
        XCTAssertEqual(reduced.offsetY, 0, accuracy: 0.0001)
        XCTAssertEqual(reduced.scale, 1.0, accuracy: 0.0001)
        XCTAssertFalse(reduced.usesMovementAndScale)
    }

    /// The rise starts 14 pt below the resting place and scales about the bottom-right corner, whichever way the
    /// layer's parent counts y.
    func testRisePivotAndShiftFollowTheWayYPointsOnScreen() {
        let size = CGSize(width: 400, height: 60)
        let down = SentMessageRiseMotion.bottomRightPivotOffset(boundsSize: size, superlayerYPointsDown: true)
        XCTAssertEqual(down.pivotX, 200, accuracy: 0.001)
        XCTAssertEqual(down.pivotY, 30, accuracy: 0.001, "bottom is +y: below the centre")
        XCTAssertEqual(down.verticalShift, 14, accuracy: 0.001, "lower is +y")
        let up = SentMessageRiseMotion.bottomRightPivotOffset(boundsSize: size, superlayerYPointsDown: false)
        XCTAssertEqual(up.pivotX, 200, accuracy: 0.001)
        XCTAssertEqual(up.pivotY, -30, accuracy: 0.001, "bottom is -y: below the centre")
        XCTAssertEqual(up.verticalShift, -14, accuracy: 0.001, "lower is -y")
    }

    func testSentMessageRiseEligibilityTrackerPlaysOnceAndRespectsGuards() {
        var tracker = SentMessageRiseTracker()

        // Normal local send at bottom plays exactly once.
        tracker.noteLocalSubmit(isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false)
        XCTAssertFalse(
            tracker.recordLocalSend(
                eventID: "$m1", isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
        XCTAssertTrue(
            tracker.consumeIfEligible(
                eventID: "$m1", isInitialRender: false, isHistoryLoad: false,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
        XCTAssertFalse(
            tracker.consumeIfEligible(
                eventID: "$m1", isInitialRender: false, isHistoryLoad: false,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            ),
            "never replays on cell reuse or scroll back"
        )

        // Initial render, history load, scrolled up, and away states block animation.
        tracker.noteLocalSubmit(isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false)
        tracker.recordLocalSend(
            eventID: "$m2", isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
        )
        XCTAssertFalse(
            tracker.consumeIfEligible(
                eventID: "$m2", isInitialRender: true, isHistoryLoad: false,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
        XCTAssertFalse(
            tracker.consumeIfEligible(
                eventID: "$m2", isInitialRender: false, isHistoryLoad: true,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
        XCTAssertFalse(
            tracker.consumeIfEligible(
                eventID: "$m2", isInitialRender: false, isHistoryLoad: false,
                isAtBottom: false, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )

        // Room reopen clears pending sends so historical items never animate on reopen.
        tracker.resetForRoomSwitchOrReopen()
        XCTAssertFalse(
            tracker.consumeIfEligible(
                eventID: "$m2", isInitialRender: false, isHistoryLoad: false,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )

        // Reversed ordering (live insert noticed before onSent returns) also authorizes once.
        tracker.noteLocalSubmit(isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false)
        tracker.noteNewlyInsertedMineMessage(
            eventID: "$m3", isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
        )
        XCTAssertTrue(
            tracker.recordLocalSend(
                eventID: "$m3", isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
        XCTAssertTrue(
            tracker.consumeIfEligible(
                eventID: "$m3", isInitialRender: false, isHistoryLoad: false,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
    }

    /// Sending while scrolled up only jumps to the latest. Landing at the bottom afterwards, before the send has an
    /// id, must not turn that send into one that rises.
    func testASendBegunScrolledUpNeverRisesEvenAfterTheJumpLands() {
        var tracker = SentMessageRiseTracker()
        tracker.noteLocalSubmit(isLoaded: true, isAtBottom: false, isAwayFromLatest: false, isHeldAwayFromLatest: false)
        // The jump has landed by the time the engine answers: the live state says "at the bottom".
        XCTAssertFalse(
            tracker.recordLocalSend(
                eventID: "$up", isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
        XCTAssertFalse(
            tracker.consumeIfEligible(
                eventID: "$up", isInitialRender: false, isHistoryLoad: false,
                isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )

        // A credit left over from an earlier submit at the bottom is taken back by a submit made scrolled up.
        tracker.noteLocalSubmit(isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false)
        tracker.noteLocalSubmit(isLoaded: true, isAtBottom: false, isAwayFromLatest: false, isHeldAwayFromLatest: false)
        XCTAssertFalse(
            tracker.recordLocalSend(
                eventID: "$up2", isLoaded: true, isAtBottom: true, isAwayFromLatest: false, isHeldAwayFromLatest: false
            )
        )
    }

    /// The same, through the real composer: a send from the bottom rises, a send from scrolled up does not.
    func testComposerSendRisesFromTheBottomButNotFromScrolledUp() async throws {
        let h = try await start(["!a": history(120, room: "!a")])
        try await h.open("!a")

        h.script.overrides["message.send"] = .result(["event_id": "$atBottom"])
        h.conversation.composer.text = "from the bottom"
        await h.conversation.composer.submit()?.value
        XCTAssertTrue(h.conversation.consumeSentMessageRise(eventID: "$atBottom", isInitialRender: false, isHistoryLoad: false))
        XCTAssertFalse(h.conversation.consumeSentMessageRise(eventID: "$atBottom", isInitialRender: false, isHistoryLoad: false),
                       "once")

        h.conversation.scrolled(toBottom: false)
        h.script.overrides["message.send"] = .result(["event_id": "$scrolledUp"])
        h.conversation.composer.text = "from up there"
        await h.conversation.composer.submit()?.value
        h.conversation.scrolled(toBottom: true) // the jump to the latest has landed
        XCTAssertFalse(h.conversation.consumeSentMessageRise(eventID: "$scrolledUp", isInitialRender: false, isHistoryLoad: false),
                       "scrolled up: it jumps to the latest and does not rise")
    }

    // MARK: - Item 8: Stable Sending -> Sent Layout

    /// The receipt line stays on the earlier message while a newer one is queued, sending or fails, so starting or
    /// failing a send never moves it; it moves once, when the newer message has gone.
    func testReceiptLineStaysPutWhileANewerMessageIsInFlightOrFails() async throws {
        XCTAssertEqual(StatusLineStability.compactLineHeight, 16)
        let m1 = textEvent(id: "$1", room: "!a", at: 1, body: "first", mine: true, status: "sent")
        let h = try await start(["!a": [m1]])
        try await h.open("!a")
        XCTAssertEqual(h.conversation.lastOutgoingID, "$1")

        h.script.add("!a", textEvent(id: "$2", room: "!a", at: 2, body: "sending now", mine: true, status: "pending"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.messageIDs(h.conversation.items) == ["$1", "$2"] }
        XCTAssertEqual(h.conversation.lastOutgoingID, "$1", "a send starting does not move the receipt line")

        h.script.add("!a", textEvent(id: "$2", room: "!a", at: 2, body: "sending now", mine: true, status: "failed"))
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$2"])
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(h.conversation.lastOutgoingID, "$1", "a failed send does not move it either")

        h.script.add("!a", textEvent(id: "$2", room: "!a", at: 2, body: "sending now", mine: true, status: "sent"))
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.conversation.lastOutgoingID == "$2" }
    }

    // MARK: - Item 9: Bottom Anchoring Maths

    func testBottomAnchoringMathsShortChatAndResizeAndPrepend() {
        // Short chat: 120 pt content in 500 pt viewport (56 pt top inset, 8 pt bottom inset -> 436 pt usable).
        XCTAssertTrue(TimelineBottomAnchoring.isShortChat(viewportHeight: 500, topInset: 56, bottomInset: 8, contentHeight: 120))
        XCTAssertEqual(
            TimelineBottomAnchoring.extraTopOffset(viewportHeight: 500, topInset: 56, bottomInset: 8, contentHeight: 120),
            316, accuracy: 0.001
        )
        let shortBounds = TimelineBottomAnchoring.originYBounds(
            viewportHeight: 500, topInset: 56, bottomInset: 8, contentHeight: 120
        )
        XCTAssertEqual(shortBounds.min, -372, accuracy: 0.001)
        XCTAssertEqual(shortBounds.max, -372, accuracy: 0.001)
        // Clamping any scroll attempt keeps the short chat anchored flush at the bottom.
        XCTAssertEqual(
            TimelineBottomAnchoring.clampedOriginY(-56, viewportHeight: 500, topInset: 56, bottomInset: 8, contentHeight: 120),
            -372, accuracy: 0.001
        )

        // Composer growth / typing line increases bottomInset from 8 to 88 -> extra decreases by 80, bottom stays flush.
        let composerGrown = TimelineBottomAnchoring.originYBounds(
            viewportHeight: 500, topInset: 56, bottomInset: 88, contentHeight: 120
        )
        XCTAssertEqual(composerGrown.min, -292, accuracy: 0.001)
        XCTAssertEqual(composerGrown.max, -292, accuracy: 0.001)

        // Prepending older messages turns short chat (120 pt) into tall chat (900 pt): unconstrained top scroll returns.
        XCTAssertFalse(TimelineBottomAnchoring.isShortChat(viewportHeight: 500, topInset: 56, bottomInset: 8, contentHeight: 900))
        let tallBounds = TimelineBottomAnchoring.originYBounds(
            viewportHeight: 500, topInset: 56, bottomInset: 8, contentHeight: 900
        )
        XCTAssertEqual(tallBounds.min, -56, accuracy: 0.001)
        XCTAssertEqual(tallBounds.max, 408, accuracy: 0.001)
    }

    // MARK: - Item 20: Gentler Jump Highlight Timing

    func testJumpHighlightTiming() {
        XCTAssertEqual(JumpHighlightMotion.duration, .milliseconds(1500))
        XCTAssertEqual(JumpHighlightMotion.totalDuration, 1.5, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.fadeInDuration, 0.3, accuracy: 0.0001, "20% of the time")
        XCTAssertEqual(JumpHighlightMotion.fadeOutDuration, 1.2, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.peakTintFraction, 0.40, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.peakTintOpacity, 0.112, accuracy: 0.0001, "40% of the 0.28 tint")
    }

    func testReduceMotionHasNoTintRamp() {
        XCTAssertTrue(JumpHighlightMotion.rampsTint(reduceMotion: false))
        XCTAssertFalse(JumpHighlightMotion.rampsTint(reduceMotion: true))
    }
}
