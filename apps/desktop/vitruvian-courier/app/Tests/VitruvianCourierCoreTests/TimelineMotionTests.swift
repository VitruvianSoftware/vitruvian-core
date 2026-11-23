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
        rows: [String: InboxRow] = [:]
    ) async throws -> ConversationHarness {
        let h = try await startConversation(events, rows: rows)
        harnesses.append(h)
        return h
    }

    // MARK: - Item 1: Atomic Room Switch & Initial Bottom Layout Rules

    func testKeepPreviousChatVisibleTruthTable() {
        XCTAssertTrue(
            TimelineLoadMotion.shouldKeepPreviousChatVisible(
                currentRoomID: "!a", isCurrentlyLoaded: true, targetRoomID: "!b", isTargetCached: false, hasClient: true
            )
        )
        XCTAssertFalse(
            TimelineLoadMotion.shouldKeepPreviousChatVisible(
                currentRoomID: nil, isCurrentlyLoaded: false, targetRoomID: "!b", isTargetCached: false, hasClient: true
            ),
            "very first chat from empty still shows its initial loading state"
        )
        XCTAssertFalse(
            TimelineLoadMotion.shouldKeepPreviousChatVisible(
                currentRoomID: "!a", isCurrentlyLoaded: true, targetRoomID: "!b", isTargetCached: true, hasClient: true
            ),
            "cached target switches synchronously"
        )
        XCTAssertFalse(
            TimelineLoadMotion.shouldKeepPreviousChatVisible(
                currentRoomID: "!a", isCurrentlyLoaded: true, targetRoomID: "!a", isTargetCached: false, hasClient: true
            )
        )
        XCTAssertFalse(
            TimelineLoadMotion.shouldKeepPreviousChatVisible(
                currentRoomID: "!a", isCurrentlyLoaded: true, targetRoomID: "!b", isTargetCached: false, hasClient: false
            )
        )
    }

    func testSwitchingToUncachedChatSwitchesHeaderTimelineAndComposerAtomically() async throws {
        let rowA = chatRow("!a", name: "Alice", network: "whatsapp", direct: true)
        let rowB = chatRow("!b", name: "Bob", network: "signal", direct: true)
        let h = try await start(
            ["!a": history(2, room: "!a"), "!b": history(2, room: "!b"), "!c": history(1, room: "!c")],
            rows: ["!a": rowA, "!b": rowB]
        )
        h.rows.rows = ["!a": rowA, "!b": rowB]
        try await h.open("!a")
        XCTAssertEqual(h.conversation.roomID, "!a")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "!a")
        XCTAssertEqual(h.conversation.composer.roomID, "!a")

        // Opening uncached !b keeps all three (!a's header, timeline, composer) together until !b's first page arrives.
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.server.receivedParams("room.events").contains { $0["room_id"] as? String == "!b" } }
        XCTAssertEqual(h.conversation.roomID, "!a")
        XCTAssertEqual(h.conversation.headerRow?.roomID, "!a")
        XCTAssertEqual(h.conversation.composer.roomID, "!a")
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!a$1", "!a$2"])
        XCTAssertTrue(h.conversation.isLoaded)
        XCTAssertTrue(h.conversation.isLoadingPendingRoom)
        XCTAssertEqual(h.conversation.pendingRoomID, "!b")

        // Switching again to !c while !b is still in flight drops !b's late answer.
        let dropped = expectation(description: "cancelled !b dropped")
        h.conversation.staleAnswerDropped = { dropped.fulfill() }
        h.app.selectedRoomID = "!c"
        try await waitUntil { h.conversation.roomID == "!c" && h.conversation.isLoaded }
        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        await fulfillment(of: [dropped], timeout: 5)
        h.conversation.staleAnswerDropped = nil
        XCTAssertEqual(h.conversation.roomID, "!c")
        XCTAssertEqual(h.conversation.composer.roomID, "!c")
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["!c$1"])
        XCTAssertFalse(h.conversation.isLoadingPendingRoom)
    }

    /// What the person can see is what is there when the main run loop turns, not what the model passes through
    /// while one turn's work runs. At every turn, header, timeline and composer must all be of the same chat, and a
    /// chat shown as loaded must have its messages.
    func testNoRenderedStateEverMixesChatsOrShowsAnEmptyNewChat() async throws {
        let rowA = chatRow("!a", name: "Alice", network: "whatsapp", direct: true)
        let rowB = chatRow("!b", name: "Bob", network: "signal", direct: true)
        let h = try await start(["!a": history(3, room: "!a"), "!b": history(3, room: "!b")],
                                rows: ["!a": rowA, "!b": rowB])
        h.rows.rows = ["!a": rowA, "!b": rowB]
        try await h.open("!a")

        struct Seen: Equatable { var room: String?; var header: String?; var composer: String?; var loaded: Bool; var ids: [String] }
        var seen: [Seen] = []
        let model = h.conversation
        let sub = model.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                seen.append(Seen(room: model.roomID, header: model.headerRow?.roomID, composer: model.composer.roomID,
                                 loaded: model.isLoaded, ids: h.messageIDs(model.items)))
            }
        }
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.server.receivedParams("room.events").contains { $0["room_id"] as? String == "!b" } }
        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { model.roomID == "!b" && model.isLoaded }
        try await Task.sleep(for: .milliseconds(100))
        sub.cancel()

        XCTAssertFalse(seen.isEmpty)
        for state in seen {
            XCTAssertTrue(state.loaded, "never an unloaded (empty) pane: \(state)")
            XCTAssertFalse(state.ids.isEmpty, "never an empty pane: \(state)")
            let chat = state.room
            XCTAssertEqual(state.composer, chat, "the composer is the timeline's chat: \(state)")
            XCTAssertTrue(state.ids.allSatisfy { $0.hasPrefix(chat ?? "?") }, "only this chat's messages: \(state)")
            if let header = state.header { XCTAssertEqual(header, chat, "the header is the timeline's chat: \(state)") }
        }
        XCTAssertEqual(seen.last?.room, "!b")
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

        let pivotFlipped = SentMessageRiseMotion.bottomRightPivotOffset(
            boundsSize: CGSize(width: 400, height: 60),
            layerAnchorPoint: CGPoint(x: 0.5, y: 0.5),
            isGeometryFlipped: true
        )
        XCTAssertEqual(pivotFlipped.pivotX, 200, accuracy: 0.001)
        XCTAssertEqual(pivotFlipped.pivotY, 30, accuracy: 0.001)
        XCTAssertEqual(pivotFlipped.verticalShift, 14, accuracy: 0.001)
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

    // MARK: - Item 8: Stable Sending -> Sent Layout

    func testStatusLineStabilityHidesEarlierSentWhileNewSendIsInFlight() {
        XCTAssertEqual(StatusLineStability.compactLineHeight, 16)

        func msg(_ id: String, status: StatusLine?, mine: Bool = true) -> TimelineItem {
            .message(TimelineMessage(
                id: id,
                roomID: "!a",
                sender: mine ? Timeline.meUserID : "@ann:example.test",
                senderName: mine ? "me" : "Ann",
                senderAvatarPath: "",
                mine: mine,
                ts: 1_000_000,
                kind: .text,
                body: "hi",
                rich: RichText(text: "hi", entities: []),
                isEdited: false,
                editCount: 0,
                editFailed: nil,
                failedEditID: nil,
                fileName: "",
                mimeType: "",
                byteSize: nil,
                width: nil,
                height: nil,
                mediaPath: "",
                statusLine: status,
                countsAsUnread: false,
                poll: nil,
                thread: nil,
                bookmarked: false,
                expiresAt: nil,
                timerChange: nil,
                call: nil,
                reply: nil,
                reactions: [],
                startsGroup: false
            ))
        }

        // Before new send: $1 holds Sent.
        XCTAssertEqual(StatusLineStability.receiptRowID(in: [msg("$1", status: .sent)]), "$1")

        // While $2 is Sending...: $1's Sent is cleared so Sending -> Sent never shifts the gap between $1 and $2.
        XCTAssertNil(StatusLineStability.receiptRowID(in: [msg("$1", status: .sent), msg("$2", status: .sending)]))
        XCTAssertNil(StatusLineStability.receiptRowID(in: [msg("$1", status: .seen(by: [], at: nil)), msg("$2", status: .queued)]))

        // Once $2 settles to Sent: $2 takes the receipt line while $1 stays without one.
        XCTAssertEqual(StatusLineStability.receiptRowID(in: [msg("$1", status: .sent), msg("$2", status: .sent)]), "$2")

        // Ruling 20 preserved: a failed or waiting message does not clear an older gone message's receipt line.
        XCTAssertEqual(
            StatusLineStability.receiptRowID(in: [msg("$1", status: .seen(by: ["Ana"], at: nil)), msg("$2", status: .waiting)]),
            "$1"
        )
        XCTAssertEqual(
            StatusLineStability.receiptRowID(in: [msg("$1", status: .sent), msg("$2", status: .failed(reason: "err"))]),
            "$1"
        )
    }

    func testConversationLastOutgoingIDAcrossSendingToSentTransition() async throws {
        let m1 = textEvent(id: "$1", room: "!a", at: 1, body: "first", mine: true, status: "sent")
        let h = try await start(["!a": [m1]])
        try await h.open("!a")
        XCTAssertEqual(h.conversation.lastOutgoingID, "$1")

        h.script.add("!a", textEvent(id: "$2", room: "!a", at: 2, body: "sending now", mine: true, status: "pending"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.messageIDs(h.conversation.items) == ["$1", "$2"] }
        XCTAssertNil(h.conversation.lastOutgoingID, "$1 clears its Sent label before $2 settles so the gap stays fixed")

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

    func testJumpHighlightTimingAndIntensityCurve() {
        XCTAssertEqual(JumpHighlightMotion.duration, .milliseconds(1500))
        XCTAssertEqual(JumpHighlightMotion.totalDuration, 1.5, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.fadeInDuration, 0.3, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.fadeOutDuration, 1.2, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.peakTintFraction, 0.40, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.peakTintOpacity, 0.112, accuracy: 0.0001)

        XCTAssertEqual(JumpHighlightMotion.opacity(at: 0), 0, accuracy: 0.0001)
        // Ease-out during fade-in rises faster than linear in the first half (t = 0.15 > 0.056).
        let midIn = JumpHighlightMotion.opacity(at: 0.15)
        XCTAssertGreaterThan(midIn, 0.056)
        XCTAssertLessThan(midIn, 0.112)
        // Peak at 20% of 1.5 s (t = 0.3 s) is 40% of 0.28 = 0.112.
        XCTAssertEqual(JumpHighlightMotion.opacity(at: 0.3), 0.112, accuracy: 0.0001)
        // Ease-out decays smoothly back to 0 at t = 1.5 s.
        let midOut = JumpHighlightMotion.opacity(at: 0.9)
        XCTAssertGreaterThan(midOut, 0)
        XCTAssertLessThan(midOut, 0.056)
        XCTAssertEqual(JumpHighlightMotion.opacity(at: 1.5), 0, accuracy: 0.0001)
        XCTAssertEqual(JumpHighlightMotion.opacity(at: 2.0), 0, accuracy: 0.0001)
    }
}
