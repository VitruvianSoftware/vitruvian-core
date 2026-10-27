// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The conversation model against a stand-in engine that keeps a few chats' events and pages them as the real
/// engine does. All data here is made up.
@MainActor
final class ConversationModelTests: XCTestCase {
    private var servers: [TestEngineServer] = []
    /// Stopped even when a test fails before its own `stop`, so its engine can't hold on into the next test.
    private var apps: [AppModel] = []
    private var timed: [ConversationHarness] = []

    override func tearDown() async throws {
        for harness in timed { await harness.stop() }
        timed = []
        for app in apps { await app.stop() }
        apps = []
        for server in servers { server.stop() }
        servers = []
    }

    // MARK: - Harness

    @MainActor private struct Harness {
        let script: ConversationScript
        let server: TestEngineServer
        let app: AppModel
        let conversation: ConversationModel
        let unread: UnreadBox

        func count(_ method: String) -> Int { server.receivedMethods().filter { $0 == method }.count }
        func messageIDs() -> [String] {
            conversation.items.compactMap { if case let .message(m) = $0 { m.id } else { nil } }
        }
    }

    /// What the inbox would say a chat's unread count is when it is opened.
    private final class UnreadBox: @unchecked Sendable {
        var counts: [String: Int] = [:]
    }

    /// How many times the app model's connect hooks have run.
    @MainActor private final class ConnectCount {
        var count = 0
    }

    private func start(_ events: [String: [[String: Any]]], windowIsKey: Bool = true,
                       presence: StaticPresence? = nil, time: FakeTime? = nil) async throws -> Harness {
        let script = ConversationScript(events: events)
        let server = try TestEngineServer(handler: script.handle)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        apps.append(app)
        let unread = UnreadBox()
        let clock = time ?? FakeTime()
        let conversation = ConversationModel(appModel: app, unreadCount: { unread.counts[$0] ?? 0 },
                                             attention: Attention(source: presence ?? StaticPresence(), pollInterval: nil),
                                             sleep: { try await clock.sleep(for: $0) })
        conversation.setWindowKey(windowIsKey)
        // The app model's connect hooks run in order: once this one has, the conversation's has too. Waiting for it
        // means no read of the greeting can land in the middle of a test (it once read a held window a second time,
        // and a test that waited for exactly one read timed out under load).
        let connected = ConnectCount()
        app.onConnect { _ in connected.count += 1 }
        app.start()
        try await waitUntil { app.client != nil && connected.count > 0 }
        return Harness(script: script, server: server, app: app, conversation: conversation, unread: unread)
    }

    private func stop(_ harness: Harness) async {
        await harness.app.stop()
    }

    /// n events in a chat, `$1` oldest, each a minute after the last, from someone else unless `mineEvery` says so.
    private func history(_ count: Int, room: String = "!a") -> [[String: Any]] {
        (1 ... count).map { textEvent(id: "$\($0)", room: room, at: Int64($0), body: "Message \($0)") }
    }

    // MARK: - Disappearing messages

    /// The chat's timers, as ChatFeatures.disappearing writes them.
    private let afterSend: [String: Any] = ["type": "after_send", "timers_ms": [86_400_000, 604_800_000, 7_776_000_000]]

    private final class Toasts {
        var lines: [String] = []
    }

    /// !a on a clock the test moves (and sleeps on the same clock), with these features; its toasts are kept.
    private func startTimed(_ events: [[String: Any]], features: [String: Any]? = nil, clock: TestClock,
                            time: FakeTime = FakeTime(), sleep: (@Sendable (Duration) async throws -> Void)? = nil,
                            extra: [String: [[String: Any]]] = [:]) async throws -> (ConversationHarness, Toasts) {
        var all = extra
        all["!a"] = events
        let h = try await startConversation(
            all, features: features.map { ["!a": $0] } ?? [:],
            rows: ["!a": chatRow("!a", name: "Ann", network: "whatsapp")], now: { clock.date },
            sleep: sleep ?? { try await time.sleep(for: $0) })
        timed.append(h)
        let toasts = Toasts()
        h.conversation.onToast = { toasts.lines.append($0) }
        try await h.open("!a")
        return (h, toasts)
    }

    func testHeaderShowsTheTimer() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, _) = try await startTimed(
            history(2), features: featuresJSON(disappearing: afterSend,
                                               currentTimer: ["type": "after_send", "timer_ms": 604_800_000]),
            clock: clock)
        XCTAssertEqual(h.conversation.timerLine, "Messages disappear after 7 days")

        // The engine says the timer is off (a room change): the line goes.
        h.script.features["!a"] = featuresJSON(disappearing: afterSend, currentTimer: nil)
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { h.conversation.timerLine == nil }

        // And back to a day.
        h.script.features["!a"] = featuresJSON(disappearing: afterSend,
                                               currentTimer: ["type": "after_send", "timer_ms": 86_400_000])
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { h.conversation.timerLine == "Messages disappear after 1 day" }
    }

    func testAChatWithoutTimersOffersNoneAndNoLine() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, _) = try await startTimed(history(1), features: featuresJSON(), clock: clock)
        XCTAssertNil(h.conversation.timerLine)
        XCTAssertTrue(h.conversation.timerChoices.isEmpty, "Google Messages and Slack have no timer to set")
        await h.conversation.setTimer(DisappearingChoice(type: .afterSend, timerMS: 86_400_000))
        XCTAssertEqual(h.count("room.setDisappearing"), 0, "nothing the chat doesn't offer is sent")
    }

    func testSettingSendsTheMethod() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, toasts) = try await startTimed(
            history(2), features: featuresJSON(disappearing: afterSend,
                                               currentTimer: ["type": "after_send", "timer_ms": 86_400_000]),
            clock: clock)
        let choices = h.conversation.timerChoices
        XCTAssertEqual(choices.map(\.title), ["Off", "1 day", "7 days", "90 days"])
        XCTAssertEqual(choices.map(\.isCurrent), [false, true, false, false], "the engine's timer is the one ticked")

        let week = try XCTUnwrap(choices.first { $0.timerMS == 604_800_000 })
        await h.conversation.setTimer(week)
        let sent = try XCTUnwrap(h.server.receivedParams("room.setDisappearing").first)
        XCTAssertEqual(Set(sent.keys), ["room_id", "type", "timer_ms"])
        XCTAssertEqual(sent["room_id"] as? String, "!a")
        XCTAssertEqual(sent["type"] as? String, "after_send")
        XCTAssertEqual((sent["timer_ms"] as? NSNumber)?.int64Value, 604_800_000)
        XCTAssertEqual(h.conversation.timerLine, "Messages disappear after 1 day",
                       "the header shows the engine's timer, not the one asked for, until the engine reports it")
        XCTAssertTrue(toasts.lines.isEmpty)

        // The engine reports it (a room change): now the header and the tick move.
        h.script.features["!a"] = featuresJSON(disappearing: afterSend,
                                               currentTimer: ["type": "after_send", "timer_ms": 604_800_000])
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { h.conversation.timerLine == "Messages disappear after 7 days" }
        XCTAssertEqual(h.conversation.timerChoices.map(\.isCurrent), [false, false, true, false])

        // Off is a type of "" and no time.
        await h.conversation.setTimer(try XCTUnwrap(h.conversation.timerChoices.first))
        let off = try XCTUnwrap(h.server.receivedParams("room.setDisappearing").last)
        XCTAssertEqual(off["type"] as? String, "")
        XCTAssertEqual((off["timer_ms"] as? NSNumber)?.int64Value, 0)
    }

    func testARefusedTimerIsToldAndTheHeaderKeepsTheEnginesTimer() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, toasts) = try await startTimed(
            history(1), features: featuresJSON(disappearing: afterSend,
                                               currentTimer: ["type": "after_send", "timer_ms": 86_400_000]),
            clock: clock)
        h.script.overrides["room.setDisappearing"] = .error(code: -32023, message: "network said no")
        let week = try XCTUnwrap(h.conversation.timerChoices.first { $0.timerMS == 604_800_000 })
        await h.conversation.setTimer(week)
        XCTAssertEqual(toasts.lines, ["Couldn’t change the timer: WhatsApp said no."])
        XCTAssertEqual(h.conversation.timerLine, "Messages disappear after 1 day")
        XCTAssertEqual(h.conversation.timerChoices.map(\.isCurrent), [false, true, false, false])
        XCTAssertFalse(h.conversation.isChangingTimer)
    }

    func testCountdownFollowsTheClock() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let soon = clock.millis + 90 * 60_000
        let (h, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: soon),
             textEvent(id: "$2", room: "!a", at: 2),
             expiring(textEvent(id: "$3", room: "!a", at: 3), at: clock.millis + 30_000)],
            features: featuresJSON(disappearing: afterSend), clock: clock, time: time)
        let first = try XCTUnwrap(h.message("$1"))
        XCTAssertEqual(h.conversation.disappearsIn(first), "Disappears in 1 hour, 30 minutes")
        XCTAssertNil(h.conversation.disappearsIn(try XCTUnwrap(h.message("$2"))),
                     "a message with no time running (after reading, not yet read) says nothing")
        XCTAssertEqual(h.conversation.disappearsIn(try XCTUnwrap(h.message("$3"))), "Disappears in 1 minute",
                       "coarse: never seconds, and never 0 minutes while it is still there")

        // A minute passes: the countdown is read from the clock, whole minutes, rounded up.
        clock.advance(30 * 60)
        XCTAssertEqual(h.conversation.disappearsIn(first), "Disappears in 1 hour")
        clock.advance(59 * 60 + 10)
        XCTAssertEqual(h.conversation.disappearsIn(first), "Disappears in 1 minute")

        // The view redraws when the model says the clock moved.
        let before = h.conversation.countdownClock
        time.advance(60)
        try await waitUntil { h.conversation.countdownClock > before }
    }

    func testRebuildsWhenTheNextMessageExpires() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let (h, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: clock.millis + 120_000),
             expiring(textEvent(id: "$2", room: "!a", at: 2), at: clock.millis + 300_000),
             textEvent(id: "$3", room: "!a", at: 3)], clock: clock, time: time)
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$1", "$2", "$3"])
        h.conversation.selectedMessageID = "$1"
        let reads = h.count("room.events")

        // The first one's time comes: the engine is not asked, the model just builds again.
        clock.advance(120)
        time.advance(120)
        try await waitUntil { h.messageIDs(h.conversation.items) == ["$2", "$3"] }
        XCTAssertNil(h.conversation.selectedMessageID, "a message that left is not selected")
        XCTAssertEqual(h.count("room.events"), reads, "no read of the engine is needed to hide a message")

        // And the next, once its wake is set: a wake set after the clock moved would wait from the new time.
        try await waitUntil { time.pendingSleeps.count == 1 }
        clock.advance(180)
        time.advance(180)
        try await waitUntil { h.messageIDs(h.conversation.items) == ["$3"] }

        // Nothing left to wait for: nothing is scheduled.
        try await waitUntil { time.pendingSleeps.isEmpty }
    }

    func testAMessageLeavesTheThreadPaneOnTime() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let (h, _) = try await startTimed(
            [threadRoot(id: "$r", room: "!a", at: 1, replies: 2),
             expiring(threadReply(id: "$t1", root: "$r", room: "!a", at: 2), at: clock.millis + 120_000),
             threadReply(id: "$t2", root: "$r", room: "!a", at: 3)],
            features: featuresJSON(replyIsThread: true), clock: clock, time: time)
        let thread = h.conversation.thread
        h.conversation.openThread("$r")
        try await waitUntil { thread.isLoaded }
        XCTAssertEqual(h.messageIDs(thread.items), ["$r", "$t1", "$t2"])

        clock.advance(120)
        time.advance(120)
        try await waitUntil { h.messageIDs(thread.items) == ["$r", "$t2"] }
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$r"], "the chat only had the root")
    }

    func testTheWakeIsOneAndEndsWithTheChat() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let (h, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: clock.millis + 600_000),
             expiring(textEvent(id: "$2", room: "!a", at: 2), at: clock.millis + 900_000)],
            clock: clock, time: time, extra: ["!b": [textEvent(id: "$b1", room: "!b", at: 1)]])
        XCTAssertEqual(time.pendingSleeps.count, 1, "one wake, however many messages are timed")

        // Every rebuild takes the old wake back before it makes its own.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs(h.conversation.items).contains("$4") }
        XCTAssertEqual(time.pendingSleeps.count, 1)

        // Another chat open: nothing waits for the one that closed.
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.conversation.roomID == "!b" && h.conversation.isLoaded }
        XCTAssertTrue(time.pendingSleeps.isEmpty)

        // Closing the chat itself, with its wake pending, takes the wake back.
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.roomID == "!a" && h.conversation.isLoaded }
        try await waitUntil { time.pendingSleeps.count == 1 }
        h.app.selectedRoomID = nil
        XCTAssertNil(h.conversation.roomID)
        XCTAssertTrue(time.pendingSleeps.isEmpty, "the wake of a closed chat is cancelled, not left to fire")
    }

    func testOneWakeHidesEverythingThatRanOutWhileTheClockJumped() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let (h, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: clock.millis + 120_000),
             expiring(textEvent(id: "$2", room: "!a", at: 2), at: clock.millis + 300_000),
             expiring(textEvent(id: "$3", room: "!a", at: 3), at: clock.millis + 540_000),
             expiring(textEvent(id: "$4", room: "!a", at: 4), at: clock.millis + 3_600_000),
             textEvent(id: "$5", room: "!a", at: 5)], clock: clock, time: time)
        let reads = h.count("room.events")
        XCTAssertEqual(time.pendingSleeps.count, 1)

        // The Mac slept for 20 minutes: when the one wake comes, all three are gone and the fourth still is there.
        clock.advance(20 * 60)
        time.advance(61)
        try await waitUntil { h.messageIDs(h.conversation.items) == ["$4", "$5"] }
        XCTAssertEqual(h.count("room.events"), reads)
        try await waitUntil { time.pendingSleeps.count == 1 }
    }

    func testANinetyDayTimerWakesAtTheNextVisibleChange() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let (h, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: clock.millis + 90 * 86_400_000)],
            clock: clock, time: time)
        let message = try XCTUnwrap(h.message("$1"))
        XCTAssertEqual(h.conversation.disappearsIn(message), "Disappears in 90 days")
        // It reads in days and hours, so it changes once an hour, not once a minute.
        XCTAssertEqual(time.pendingSleeps.count, 1)
        XCTAssertEqual(try XCTUnwrap(time.pendingSleeps.first), 3600.05, accuracy: 0.001)

        // Half an hour on: still "90 days" (rounded up to the hour). Past the hour it reads the next hour down.
        clock.advance(30 * 60)
        XCTAssertEqual(h.conversation.disappearsIn(message), "Disappears in 90 days")
        clock.advance(31 * 60)
        XCTAssertEqual(h.conversation.disappearsIn(message), "Disappears in 89 days, 23 hours")

        // The last day reads in hours and minutes: every minute.
        let (g, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: clock.millis + 23 * 3_600_000 + 59 * 60_000)],
            clock: clock, time: FakeTime())
        XCTAssertEqual(g.conversation.disappearsIn(try XCTUnwrap(g.message("$1"))),
                       "Disappears in 23 hours, 59 minutes")
    }

    func testAClockThatStepsBackIsWaitedOutNotAbandoned() async throws {
        let clock = TestClock(1_760_600_600)
        let time = FakeTime()
        let (h, _) = try await startTimed(
            [expiring(textEvent(id: "$1", room: "!a", at: 1), at: clock.millis + 60_000)], clock: clock, time: time)
        XCTAssertEqual(time.pendingSleeps.count, 1)

        // The wake comes, but the clock went back (set by hand, say): it is set again, not dropped.
        clock.advance(-300)
        time.advance(61)
        try await waitUntil { time.pendingSleeps.count == 1 }
        XCTAssertEqual(h.messageIDs(h.conversation.items), ["$1"])
        let rearmed = try XCTUnwrap(time.pendingSleeps.first)
        XCTAssertGreaterThanOrEqual(rearmed, 0.1, "never nearer than the floor")

        // The clock reaches the time: the message goes.
        clock.advance(300 + 120)
        time.advance(rearmed + 1)
        try await waitUntil { h.messageIDs(h.conversation.items).isEmpty }
    }

    func testATimerNoteOfMineIsNeverEditedOrActedOn() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, _) = try await startTimed(
            [textEvent(id: "$1", room: "!a", at: 1, body: "my words", mine: true),
             timerNote(id: "$n", room: "!a", at: 2, by: Timeline.meUserID, timerMS: 86_400_000)],
            features: featuresJSON(), clock: clock)
        let note = try XCTUnwrap(h.message("$n"))
        XCTAssertTrue(note.mine)
        XCTAssertNotNil(note.timerChange)
        let offered = MessageActions.available(for: note, in: h.conversation.features, network: "whatsapp",
                                               now: clock.date)
        XCTAssertEqual(offered.actions, [.deleteForMe], "a note can only leave this Mac")
        XCTAssertTrue(offered.unavailable.isEmpty)
        XCTAssertEqual(h.conversation.availableActions(for: note).actions, [.deleteForMe])
        XCTAssertEqual(h.conversation.lastOutgoingID, "$1", "the note has no Sent mark; the message before it keeps it")

        // ⌘T goes to the message before it, selected note or not.
        h.conversation.selectedMessageID = "$n"
        XCTAssertTrue(h.conversation.editSelectedOrLast())
        guard case let .editing(eventID, original) = h.conversation.composer.mode else {
            return XCTFail("not editing")
        }
        XCTAssertEqual(eventID, "$1")
        XCTAssertEqual(original.text, "my words")

        // ↑ with "Edit your last message" skips it too.
        _ = h.conversation.composer.escape()
        h.preferences.upArrow = .editLast
        XCTAssertTrue(h.conversation.composer.editLast(in: h.conversation.items))
        guard case let .editing(again, _) = h.conversation.composer.mode else { return XCTFail("not editing") }
        XCTAssertEqual(again, "$1")
    }

    func testACallNoteOfMineIsNeverEditedOrActedOn() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, _) = try await startTimed(
            [textEvent(id: "$1", room: "!a", at: 1, body: "my words", mine: true),
             callNote(id: "$c", room: "!a", at: 2, by: Timeline.meUserID, body: "Call missed",
                      call: ("missed", "voice"))],
            features: featuresJSON(), clock: clock)
        let note = try XCTUnwrap(h.message("$c"))
        XCTAssertTrue(note.mine)
        XCTAssertEqual(note.call, CallNote(state: .missed, media: .voice))
        XCTAssertEqual(note.body, "Voice call not answered")
        XCTAssertEqual(h.conversation.availableActions(for: note).actions, [.deleteForMe])
        XCTAssertEqual(h.conversation.lastOutgoingID, "$1", "the note has no Sent mark; the message before it keeps it")
        h.conversation.selectedMessageID = "$c"
        XCTAssertTrue(h.conversation.editSelectedOrLast())
        guard case let .editing(eventID, _) = h.conversation.composer.mode else { return XCTFail("not editing") }
        XCTAssertEqual(eventID, "$1", "⌘T goes to the message before it")
    }

    /// A call note names the caller only once the chat is known to be a group: while its row is unknown nothing is
    /// shown, so a one-to-one chat never flashes a name it doesn't need.
    func testACallNoteNamesTheCallerOnlyInAKnownGroup() async throws {
        let h = try await startConversation(["!g": [callNote(id: "$c", room: "!g", at: 1)]])
        try await h.open("!g")
        let note = try XCTUnwrap(h.message("$c"))
        XCTAssertNil(h.conversation.callCaller(for: note), "the chat's row isn't known yet")
        h.conversation.learnChat(chatRow("!g", name: "Team", direct: false))
        XCTAssertEqual(h.conversation.callCaller(for: note), "Ann")
        h.conversation.learnChat(chatRow("!g", name: "Ann", direct: true))
        XCTAssertNil(h.conversation.callCaller(for: note))
    }

    func testTimerChangesAreNotesNamingWhoMadeThem() async throws {
        let clock = TestClock(1_760_600_600)
        let (h, _) = try await startTimed(
            [textEvent(id: "$1", room: "!a", at: 1),
             timerNote(id: "$n1", room: "!a", at: 2, timerMS: 86_400_000),
             timerNote(id: "$n2", room: "!a", at: 3, by: Timeline.meUserID, timerMS: 604_800_000),
             timerNote(id: "$n3", room: "!a", at: 4, timerMS: 0),
             timerNote(id: "$n4", room: "!a", at: 5, by: "@bridge:example.test", name: "Bridge bot",
                       timerMS: 3_600_000, implicit: true),
             timerNote(id: "$n5", room: "!a", at: 6, by: "@bridge:example.test", name: "Bridge bot", timerMS: 0,
                       implicit: true)],
            clock: clock)
        XCTAssertNil(h.conversation.timerChangeNote(for: try XCTUnwrap(h.message("$1"))), "an ordinary message")
        XCTAssertEqual(h.conversation.timerChangeNote(for: try XCTUnwrap(h.message("$n1"))),
                       "Ann set messages to disappear after 1 day.")
        XCTAssertEqual(h.conversation.timerChangeNote(for: try XCTUnwrap(h.message("$n2"))),
                       "You set messages to disappear after 7 days.")
        XCTAssertEqual(h.conversation.timerChangeNote(for: try XCTUnwrap(h.message("$n3"))),
                       "Ann turned off disappearing messages.")
        XCTAssertEqual(h.conversation.timerChangeNote(for: try XCTUnwrap(h.message("$n4"))),
                       "Messages now disappear after 1 hour.", "an automatic change names no one")
        XCTAssertEqual(h.conversation.timerChangeNote(for: try XCTUnwrap(h.message("$n5"))),
                       "Disappearing messages were turned off.")
        XCTAssertEqual(ConversationModel.changeSettingTitle, "Change Setting")
    }

    // MARK: - Opening

    func testOpeningLoadsTheNewestPageAndMarksRead() async throws {
        let h = try await start(["!a": history(3)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.messageIDs(), ["$1", "$2", "$3"], "oldest first, newest last")
        XCTAssertFalse(h.conversation.hasOlder)

        try await waitUntil { h.count("room.markRead") == 1 }
        XCTAssertEqual(h.server.receivedParams("room.markRead").first as? [String: String], ["room_id": "!a"])
        let first = h.server.receivedParams("room.events").first
        XCTAssertEqual(Set((first ?? [:]).keys), ["room_id", "limit"], "only documented keys, and no cursor for the newest page")
        await stop(h)
    }

    func testOpeningWithTheWindowNotKeyDoesNotMarkReadUntilItIs() async throws {
        let h = try await start(["!a": history(2)], windowIsKey: false)
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 0, "an open chat in a window nobody is looking at is not read")

        h.conversation.setWindowKey(true)
        try await waitUntil { h.count("room.markRead") == 1 }

        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 1, "already read: coming back to the window says nothing more")
        await stop(h)
    }

    func testTheNewDividerIsPlacedFromTheInboxsUnreadCountAndStays() async throws {
        let h = try await start(["!a": history(5)])
        h.unread.counts["!a"] = 2
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$4", "the two newest are new")

        // Reading it (the inbox's count drops to 0) and a refetch do not move the divider while the chat is open.
        h.unread.counts["!a"] = 0
        h.script.add("!a", textEvent(id: "$6", room: "!a", at: 6))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$6"])
        try await waitUntil { h.messageIDs().contains("$6") }
        XCTAssertEqual(h.conversation.items.map(\.id).firstIndex(of: "new"), divider)

        // Opening it again later has no divider: nothing is unread.
        h.app.selectedRoomID = nil
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.messageIDs().contains("$6") }
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" })
        await stop(h)
    }

    /// Ruling 35: a chat opened from outside the inbox's list has no count when it opens; the inbox looks its row up
    /// and passes the count on, and the divider goes where it would have, whichever comes first.
    func testAnUnreadCountLearnedAfterOpeningPlacesTheDivider() async throws {
        let h = try await start(["!a": history(5), "!b": history(5, room: "!b")])
        // The count arrives after the newest page.
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" })
        h.conversation.learnUnreadCount(2, of: "!b")
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" }, "another chat's count changes nothing")
        h.conversation.learnUnreadCount(2, of: "!a")
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$4", "the two newest are new")

        // The count arrives before it.
        h.script.hold("!b")
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.server.receivedParams("room.events").contains { $0["room_id"] as? String == "!b" } }
        h.conversation.learnUnreadCount(1, of: "!b")
        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { h.conversation.isLoaded && h.conversation.items.contains { $0.id == "new" } }
        let idsB = h.conversation.items.map(\.id)
        XCTAssertEqual(idsB[try XCTUnwrap(idsB.firstIndex(of: "new")) + 1], "$5")
        await stop(h)
    }

    func testNothingOpenShowsNothing() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.app.selectedRoomID = nil
        XCTAssertTrue(h.conversation.items.isEmpty)
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertNil(h.conversation.roomID)
        await stop(h)
    }

    // MARK: - Paging and merging

    func testScrollingToTheTopLoadsTheNextPageWithTheCursor() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.messageIDs().count, 50)
        XCTAssertTrue(h.conversation.hasOlder)

        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }
        let params = try XCTUnwrap(h.server.receivedParams("room.events").last)
        XCTAssertEqual(Set(params.keys), ["room_id", "before", "limit"])
        let before = try XCTUnwrap(params["before"] as? [String: Any])
        XCTAssertEqual(before["ts"] as? Int64, ConversationScript.timestamp(71), "the oldest event of the page we have")
        XCTAssertEqual(before["seq"] as? Int64, 71)
        XCTAssertEqual(h.messageIDs().first, "$21")
        XCTAssertEqual(h.messageIDs().last, "$120")
        XCTAssertTrue(h.conversation.hasOlder)

        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 120 }
        XCTAssertFalse(h.conversation.hasOlder, "the engine said there is nothing older")
        let calls = h.count("room.events")
        h.conversation.loadOlder()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.count("room.events"), calls, "no more pages, no more calls")
        await stop(h)
    }

    func testAnEventChangeRefetchesTheNewestPageAndKeepsOlderPages() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }

        // A message arrives, and one of the loaded ones changes status.
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.script.replace("!a", textEvent(id: "$120", room: "!a", at: 120, body: "Message 120, changed"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$121"])
        try await waitUntil { h.messageIDs().last == "$121" }

        XCTAssertEqual(h.messageIDs().count, 101, "the older pages stayed")
        XCTAssertEqual(h.messageIDs().first, "$21")
        let last = h.server.receivedParams("room.events").last ?? [:]
        XCTAssertNil(last["before"], "the refetch is of the newest page")
        guard case let .message(changed)? = h.conversation.items.first(where: { $0.id == "$120" }) else {
            return XCTFail("$120 is missing")
        }
        XCTAssertEqual(changed.body, "Message 120, changed")
        await stop(h)
    }

    func testResyncDropsOlderPages() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }

        h.server.notify(["kind": "resync"])
        try await waitUntil { h.messageIDs().count == 50 }
        XCTAssertEqual(h.messageIDs().first, "$71")
        XCTAssertTrue(h.conversation.hasOlder, "the older pages can be loaded again")
        await stop(h)
    }

    func testADiscardedMessageIsGoneAfterTheNextRead() async throws {
        let failed = textEvent(id: "$3", room: "!a", at: 3, mine: true, status: "failed", reason: "no network")
        let h = try await start(["!a": [textEvent(id: "$1", room: "!a", at: 1), textEvent(id: "$2", room: "!a", at: 2), failed]])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.messageIDs() == ["$1", "$2", "$3"] }

        await h.conversation.discard("$3")
        h.script.remove("!a", "$3")
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        await stop(h)
    }

    /// Protocol 4: a page may hold fewer events than asked for, even none, and still have older ones (here, every
    /// message of the newest page was deleted for me). Only the cursors say what there is.
    func testAPageWithFewerEventsThanAskedStillPagesByItsCursor() async throws {
        let h = try await start(["!a": history(60)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 60 }

        // Every message of the newest page is deleted for me: the page comes back empty, with older ones before it.
        h.script.deleteForMe((11 ... 60).map { "$\($0)" })
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$60"])
        try await waitUntil { h.messageIDs().count == 10 }
        XCTAssertEqual(h.messageIDs().first, "$1", "the older page stays: the empty page covers only its own")
        XCTAssertEqual(h.messageIDs().last, "$10")

        // Opened afresh, the empty newest page still offers the older ones.
        h.app.selectedRoomID = nil
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded && h.conversation.hasOlder }
        XCTAssertEqual(h.messageIDs(), [])
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 10 }
        XCTAssertFalse(h.conversation.hasOlder)
        await stop(h)
    }

    func testABurstLargerThanAPageDoesNotLeaveAHole() async throws {
        let h = try await start(["!a": history(60)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.messageIDs().last == "$60" }
        for n in 61 ... 130 { h.script.add("!a", textEvent(id: "$\(n)", room: "!a", at: Int64(n))) }
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$130"])
        try await waitUntil { h.messageIDs().last == "$130" }
        XCTAssertEqual(h.messageIDs().first, "$81", "the newest page only: what was loaded no longer joins it")
        XCTAssertEqual(h.messageIDs().count, 50)
        XCTAssertTrue(h.conversation.hasOlder)
        await stop(h)
    }

    func testAResyncDropsOlderPagesEvenWhenAnotherReadLandsFirst() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }

        // The resync's own read is held; another read (a send settling, "Try again"), started after it, answers
        // first. (The engine's changes wait behind the resync, so this is how one gets ahead.)
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.server.notify(["kind": "resync"])
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.conversation.reload()
        try await waitUntil { h.messageIDs().last == "$121" }
        XCTAssertEqual(h.messageIDs().count, 50, "the older pages are gone, whichever answer came first")
        XCTAssertTrue(h.conversation.hasOlder)

        // The held answer, late, changes nothing.
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 50), "before": NSNull(), "after": NSNull()])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs().count, 50)
        await stop(h)
    }

    func testAFailedOlderPageIsOfferedAgainAndCanBeLoaded() async throws {
        let h = try await start(["!a": history(120)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }

        h.script.failOlder = true
        h.conversation.loadOlder()
        try await waitUntil { h.conversation.olderFailed }
        XCTAssertFalse(h.conversation.isLoadingOlder)
        XCTAssertTrue(h.conversation.hasOlder)
        XCTAssertEqual(h.messageIDs().count, 50)

        h.script.failOlder = false
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().count == 100 }
        XCTAssertFalse(h.conversation.olderFailed)
        await stop(h)
    }

    // MARK: - Answers that are not today's

    func testAnAnswerForAChatThatIsNoLongerOpenIsDropped() async throws {
        let h = try await start(["!a": history(3, room: "!a"), "!b": history(2, room: "!b")])
        h.script.hold("!a")
        h.script.hold("!b")
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.count("room.events") == 1 }
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.count("room.events") == 2 }

        // Chat a's answer comes first, after the person moved on. It is the first answer of all, so only the
        // check of which chat is open can turn it away. The model says when it has turned it away.
        let dropped = expectation(description: "chat a's answer was dropped")
        h.conversation.staleAnswerDropped = { dropped.fulfill() }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 50), "before": NSNull(), "after": NSNull()])
        await fulfillment(of: [dropped], timeout: 30)
        h.conversation.staleAnswerDropped = nil
        XCTAssertEqual(h.conversation.roomID, "!b")
        XCTAssertTrue(h.conversation.items.isEmpty, "chat a's late answer does not land in chat b")
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertEqual(h.count("room.markRead"), 0)

        h.server.releaseHeld(method: "room.events", room: "!b",
                             with: ["events": h.script.newestFirst("!b", limit: 50), "before": NSNull(), "after": NSNull()])
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        for case let .message(m) in h.conversation.items { XCTAssertEqual(m.roomID, "!b") }
        await stop(h)
    }

    func testAnEngineRestartReadsTheChatAgainAndTheOldEnginesLateAnswerIsDropped() async throws {
        let pending = textEvent(id: "$3", room: "!a", at: 3, mine: true, status: "pending")
        let first = ConversationScript(events: ["!a": [textEvent(id: "$1", room: "!a", at: 1), pending]])
        let sentNow = textEvent(id: "$3", room: "!a", at: 3, mine: true, status: "sent")
        let second = ConversationScript(events: ["!a": [
            textEvent(id: "$1", room: "!a", at: 1), sentNow, textEvent(id: "$4", room: "!a", at: 4),
        ]])
        let firstServer = try TestEngineServer(handler: first.handle)
        let secondServer = try TestEngineServer(handler: second.handle)
        servers += [firstServer, secondServer]
        let launcher = FakeLauncher { index, process in
            process.printReady(socket: index == 0 ? firstServer.path : secondServer.path)
        }
        let supervisor = EngineSupervisor(
            enginePath: "/x/courier-engine", dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"),
            environment: [:], launcher: launcher, credentials: InMemoryCredentialStore(), clientName: "Courier/test",
            timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        let conversation = ConversationModel(appModel: app)
        app.start()
        try await waitUntil { app.client != nil }
        app.selectedRoomID = "!a"
        try await waitUntil { conversation.isLoaded }
        func statuses() -> [StatusLine?] {
            conversation.items.compactMap { if case let .message(m) = $0, m.id == "$3" { m.statusLine } else { nil } }
        }
        XCTAssertEqual(statuses(), [.sending], "the first engine's store has it pending")

        // The first engine is asked again, sits on the question, and dies.
        first.hold("!a")
        firstServer.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { firstServer.receivedMethods().filter { $0 == "room.events" }.count == 2 }
        launcher.processes[0].exit(1)
        firstServer.dropConnections()

        try await waitUntil { conversation.items.contains { $0.id == "$4" } }
        XCTAssertEqual(statuses(), [.sent], "shown as the new engine's store has it: not lost, not twice")
        XCTAssertEqual(conversation.items.filter { $0.id == "$3" }.count, 1)

        // The old engine's late answer has nowhere to go.
        firstServer.releaseHeld(method: "room.events", room: "!a",
                                with: ["events": first.newestFirst("!a", limit: 50), "before": NSNull(), "after": NSNull()])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(statuses(), [.sent])
        await app.stop()
    }

    // MARK: - Reading and counting while open

    func testAMessageArrivingWhileOpenAndKeyMarksRead() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.count("room.markRead") == 1 }

        h.script.add("!a", textEvent(id: "$3", room: "!a", at: 3))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.count("room.markRead") == 2 }

        // My own message, a reaction and a status change are not messages to read.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4, mine: true, status: "pending"))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 2)
        await stop(h)
    }

    func testAKeyWindowNobodyIsLookingAtDoesNotMarkReadUntilTheyAre() async throws {
        let presence = StaticPresence()
        presence.isScreenLocked = true
        let h = try await start(["!a": history(2)], presence: presence)
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 0, "the window is key, but the screen is locked")

        // Unlocked: the chat is read then.
        presence.isScreenLocked = false
        presence.onChange?()
        try await waitUntil { h.count("room.markRead") == 1 }

        // Away from the keyboard: a new message waits, and is read when they come back.
        presence.secondsSinceLastInput = Attention.idleLimit + 1
        h.conversation.attention.reevaluate()
        h.script.add("!a", textEvent(id: "$3", room: "!a", at: 3))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.messageIDs().last == "$3" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 1, "nobody has touched the Mac for three minutes")
        presence.secondsSinceLastInput = 0
        h.conversation.attention.reevaluate()
        try await waitUntil { h.count("room.markRead") == 2 }

        // The view went away (⌘W): an open chat in a closed window is not being read.
        h.conversation.setWindowKey(false)
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 2)
        await stop(h)
    }

    func testAMessageArrivingWhileTheWindowIsNotKeyWaitsForIt() async throws {
        let h = try await start(["!a": history(2)], windowIsKey: false)
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.script.add("!a", textEvent(id: "$3", room: "!a", at: 3))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.messageIDs().last == "$3" }
        XCTAssertEqual(h.count("room.markRead"), 0)
        h.conversation.setWindowKey(true)
        try await waitUntil { h.count("room.markRead") == 1 }
        await stop(h)
    }

    func testMessagesWhileScrolledUpAreCountedUntilJumpToBottom() async throws {
        let h = try await start(["!a": history(3)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.conversation.newMessageCount, 0)

        // At the bottom, a new message is simply seen.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        XCTAssertEqual(h.conversation.newMessageCount, 0)

        h.conversation.scrolled(toBottom: false)
        h.script.add("!a", textEvent(id: "$5", room: "!a", at: 5))
        h.script.add("!a", textEvent(id: "$6", room: "!a", at: 6, mine: true))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$5"])
        try await waitUntil { h.messageIDs().last == "$6" }
        XCTAssertEqual(h.conversation.newMessageCount, 1, "only messages from others count")

        // A timer-change note is no new message; any other action message (a call notice) is.
        var call = textEvent(id: "$8", room: "!a", at: 8)
        call["content"] = ["msgtype": "m.notice", "body": "Missed call",
                           "com.beeper.action_message": ["type": "call"]] as [String: Any]
        h.script.add("!a", timerNote(id: "$7", room: "!a", at: 7, timerMS: 86_400_000))
        h.script.add("!a", call)
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$8"])
        try await waitUntil { h.messageIDs().last == "$8" }
        XCTAssertEqual(h.conversation.newMessageCount, 2, "the call notice counts, the timer note doesn't")

        let token = h.conversation.jumpToBottomRequest
        h.conversation.jumpToBottom()
        XCTAssertEqual(h.conversation.jumpToBottomRequest, token + 1, "⌘↓ asks the view to scroll")
        h.conversation.scrolled(toBottom: true)
        XCTAssertEqual(h.conversation.newMessageCount, 0)
        await stop(h)
    }

    // MARK: - Opening at a message

    func testJumpOpensAroundTheMessage() async throws {
        let h = try await start(["!a": history(200)])
        h.unread.counts["!a"] = 3
        h.app.open(.message(roomID: "!a", eventID: "$100"))
        XCTAssertEqual(h.app.selectedRoomID, "!a")
        try await waitUntil { h.conversation.isLoaded }

        let first = try XCTUnwrap(h.server.receivedParams("room.events").first)
        XCTAssertEqual(Set(first.keys), ["room_id", "around", "limit"], "the first read is the page around the message")
        XCTAssertEqual(first["around"] as? String, "$100")
        XCTAssertEqual(first["limit"] as? Int, ConversationModel.pageSize)
        XCTAssertEqual(h.count("room.events"), 1, "the newest page is not read")
        XCTAssertEqual(h.messageIDs().first, "$76")
        XCTAssertEqual(h.messageIDs().last, "$125")

        XCTAssertEqual(h.conversation.highlightedMessageID, "$100")
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$100")
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertTrue(h.conversation.hasOlder)
        XCTAssertFalse(h.conversation.hasNewerWhileAway)
        XCTAssertFalse(h.conversation.items.contains { $0.id == "new" }, "no New divider while away")

        // The newest messages have not been seen: the chat is not marked read, even when the person comes back.
        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.count("room.markRead"), 0)
        await stop(h)
    }

    func testPagesForADroppedWindowAreDropped() async throws {
        let h = try await start(["!a": history(120)])

        // The page around the message is late; the person sends (back to the latest) before it comes.
        h.script.hold("!a")
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.count("room.events") == 1 }
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs().last == "$120" }
        // The model says when it has turned the late page away: waited for, not a while.
        var dropped = expectation(description: "the late window was dropped")
        dropped.assertForOverFulfill = false
        h.conversation.staleAnswerDropped = { dropped.fulfill() }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 115).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(6), "seq": 6],
                                    "after": ["ts": ConversationScript.timestamp(55), "seq": 55]])
        await fulfillment(of: [dropped], timeout: 30)
        h.conversation.staleAnswerDropped = nil
        XCTAssertEqual(h.messageIDs().first, "$71", "the late window lands nowhere")
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)

        // A newer page of a window that "Jump to latest" let go of joins nothing either.
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.conversation.loadNewer()
        try await waitUntil { h.count("room.events") >= reads + 1 }
        XCTAssertTrue(h.conversation.isLoadingNewer)
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs().first == "$71" }
        dropped = expectation(description: "the let-go window's newer page was dropped")
        dropped.assertForOverFulfill = false
        h.conversation.staleAnswerDropped = { dropped.fulfill() }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 65).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(56), "seq": 56],
                                    "after": ["ts": ConversationScript.timestamp(105), "seq": 105]])
        await fulfillment(of: [dropped], timeout: 30)
        h.conversation.staleAnswerDropped = nil
        XCTAssertEqual(h.messageIDs(), (71 ... 120).map { "$\($0)" })
        XCTAssertFalse(h.conversation.isLoadingNewer)
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        await stop(h)
    }

    func testNewMessagesWhileAwayDoNotMoveTheView() async throws {
        let h = try await start(["!a": history(200)])
        h.app.open(.message(roomID: "!a", eventID: "$100"))
        try await waitUntil { h.conversation.isLoaded }
        let items = h.conversation.items
        let scroll = h.conversation.scrollToMessageRequest

        h.script.add("!a", textEvent(id: "$201", room: "!a", at: 201))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$201"])
        h.server.notify(["kind": "status", "room_id": "!a", "event_id": "$100"])
        h.server.notify(["kind": "read", "room_id": "!a", "event_id": "$100"])
        h.server.notify(["kind": "room", "room_id": "!a"])
        try await waitUntil { h.conversation.hasNewerWhileAway }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(h.count("room.events"), 1, "no newest-page read while away")
        XCTAssertEqual(h.conversation.items, items, "nothing is spliced in and nothing moves")
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.conversation.scrollToMessageRequest, scroll)
        XCTAssertEqual(h.count("room.markRead"), 0)

        // Jump to latest: the newest page, without the window, and read now.
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs().last == "$201" }
        XCTAssertEqual(h.messageIDs().first, "$152", "the window is dropped")
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("room.events").last).keys), ["room_id", "limit"])
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertFalse(h.conversation.hasNewerWhileAway)
        XCTAssertEqual(h.conversation.jumpToBottomRequest, 1, "the view scrolls down once the newest page is in")
        try await waitUntil { h.count("room.markRead") == 1 }
        await stop(h)
    }

    func testLoadNewerReachesTheLatestAndResumesLiveUpdates() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertEqual(h.messageIDs().first, "$6")
        XCTAssertEqual(h.messageIDs().last, "$55")

        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$105" }
        let params = try XCTUnwrap(h.server.receivedParams("room.events").last)
        XCTAssertEqual(Set(params.keys), ["room_id", "after", "limit"])
        let after = try XCTUnwrap(params["after"] as? [String: Any])
        XCTAssertEqual(after["ts"] as? Int64, ConversationScript.timestamp(55), "the newest event of the window")
        XCTAssertEqual(after["seq"] as? Int64, 55)
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.count("room.markRead"), 0)

        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$120" }
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.messageIDs(), (6 ... 120).map { "$\($0)" }, "the pages join without gaps or repeats")
        try await waitUntil { h.count("room.markRead") == 1 }

        let calls = h.count("room.events")
        h.conversation.loadNewer()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.count("room.events"), calls, "at the latest: nothing newer to read")

        // Live again: a new message reads the newest page, and the window's older part stays.
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$121"])
        try await waitUntil { h.messageIDs().last == "$121" }
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("room.events").last).keys), ["room_id", "limit"])
        XCTAssertEqual(h.messageIDs().first, "$6")

        // And older pages go on from the window's start.
        h.conversation.loadOlder()
        try await waitUntil { h.messageIDs().first == "$1" }
        XCTAssertEqual(h.messageIDs(), (1 ... 121).map { "$\($0)" })
        XCTAssertFalse(h.conversation.hasOlder)
        await stop(h)
    }

    func testSendingReturnsToTheLatest() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        XCTAssertTrue(h.conversation.isAwayFromLatest)

        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        XCTAssertEqual(h.server.receivedParams("message.send").first as? [String: String],
                       ["room_id": "!a", "text": "On my way"])
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$sent"])
        try await waitUntil { h.messageIDs().last == "$sent" }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs().filter { $0 == "$sent" }.count, 1, "the sent message shows once")
        XCTAssertEqual(h.messageIDs().suffix(2), ["$120", "$sent"])
        XCTAssertFalse(h.messageIDs().contains("$30"), "the newest messages, without the window")
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        try await waitUntil { h.conversation.jumpToBottomRequest == 1 }
        try await waitUntil { h.count("room.markRead") == 1 }
        await stop(h)
    }

    func testAReadForAChatLeftBehindLandsNowhere() async throws {
        let h = try await start(["!a": history(120), "!b": history(2, room: "!b")])

        // The page around a message in chat a is late; the person opens chat b meanwhile.
        h.script.hold("!a")
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.count("room.events") == 1 }
        h.app.selectedRoomID = "!b"
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 115).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(6), "seq": 6],
                                    "after": ["ts": ConversationScript.timestamp(55), "seq": 55]])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.messageIDs(), ["$1", "$2"])
        for case let .message(m) in h.conversation.items { XCTAssertEqual(m.roomID, "!b") }
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertNil(h.conversation.scrollToMessageRequest)

        // A newer page of chat a is late; the person closes the chat meanwhile.
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.conversation.loadNewer()
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.app.selectedRoomID = nil
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 65).suffix(50).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(56), "seq": 56],
                                    "after": ["ts": ConversationScript.timestamp(105), "seq": 105]])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(h.conversation.items.isEmpty)
        XCTAssertFalse(h.conversation.isLoaded)
        XCTAssertFalse(h.conversation.isLoadingNewer)
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertEqual(h.count("room.markRead"), 1, "only chat b was read")
        await stop(h)
    }

    func testTryAgainWhileAwayReadsTheWindowAgain() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$105" }
        let serial = try XCTUnwrap(h.conversation.scrollToMessageRequest?.serial)

        h.conversation.reload()
        try await waitUntil { h.messageIDs().last == "$55" }
        let params = try XCTUnwrap(h.server.receivedParams("room.events").last)
        XCTAssertEqual(Set(params.keys), ["room_id", "around", "limit"])
        XCTAssertEqual(params["around"] as? String, "$30")
        XCTAssertEqual(h.messageIDs().first, "$6")
        XCTAssertTrue(h.conversation.isAwayFromLatest)
        XCTAssertGreaterThan(try XCTUnwrap(h.conversation.scrollToMessageRequest?.serial), serial)
        XCTAssertEqual(h.count("room.markRead"), 0)
        await stop(h)
    }

    func testTheNewDividerAfterAWindowCountsWhatCameWhileAway() async throws {
        let h = try await start(["!a": history(120)])
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.loadNewer()
        try await waitUntil { h.messageIDs().last == "$105" }

        // The last newer page is on its way when two messages come; the inbox counts them unread. The page
        // reaches the newest message it knew of, without them.
        let reads = h.count("room.events")
        h.script.hold("!a")
        h.conversation.loadNewer()
        try await waitUntil { h.count("room.events") == reads + 1 }
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.script.add("!a", textEvent(id: "$122", room: "!a", at: 122))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$122"])
        try await waitUntil { h.conversation.hasNewerWhileAway }
        h.unread.counts["!a"] = 2
        h.server.releaseHeld(method: "room.events", room: "!a",
                             with: ["events": h.script.newestFirst("!a", limit: 17).suffix(15).map { $0 },
                                    "before": ["ts": ConversationScript.timestamp(106), "seq": 106],
                                    "after": NSNull()])
        try await waitUntil { h.messageIDs().last == "$122" }
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$121", "above the two that came while away, not two higher")
        await stop(h)
    }

    func testJumpToAMessageInTheOpenChat() async throws {
        let h = try await start(["!a": history(120), "!b": history(2, room: "!b")])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        try await waitUntil { h.count("room.markRead") == 1 }
        h.conversation.reply(to: "$120")
        h.conversation.composer.text = "Half-written"

        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        XCTAssertEqual(h.messageIDs().first, "$6")
        XCTAssertEqual(h.messageIDs().last, "$55")
        XCTAssertEqual(h.server.receivedParams("room.events").last?["around"] as? String, "$30")
        XCTAssertEqual(h.conversation.highlightedMessageID, "$30")
        let request = try XCTUnwrap(h.conversation.scrollToMessageRequest)
        XCTAssertEqual(request.messageID, "$30")
        XCTAssertEqual(h.conversation.composer.text, "Half-written", "the composer is not reopened")
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$120")

        // The same message again is asked for again.
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { (h.conversation.scrollToMessageRequest?.serial ?? 0) > request.serial }
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$30")

        // A chat result opens the chat as the inbox does: at the newest.
        h.app.open(.chat(roomID: "!b"))
        XCTAssertEqual(h.app.selectedRoomID, "!b")
        try await waitUntil { h.messageIDs() == ["$1", "$2"] }
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("room.events").last).keys), ["room_id", "limit"])
        await stop(h)
    }

    func testHighlightClearsAfterThreeSeconds() async throws {
        XCTAssertEqual(ConversationModel.highlightDuration, .seconds(3))
        let time = FakeTime()
        let h = try await start(["!a": history(120)], time: time)
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.highlightedMessageID == "$30" }
        try await waitUntil { time.pendingSleeps == [3] }
        time.advance(2.9)
        await Task.yield()
        XCTAssertEqual(h.conversation.highlightedMessageID, "$30")
        time.advance(0.1)
        try await waitUntil { h.conversation.highlightedMessageID == nil }
        XCTAssertEqual(h.conversation.scrollToMessageRequest?.messageID, "$30", "only the tint goes")

        // A second jump has its own three seconds: the first one's end doesn't cut it short.
        h.app.open(.message(roomID: "!a", eventID: "$40"))
        try await waitUntil { h.conversation.highlightedMessageID == "$40" && time.pendingSleeps == [3] }
        time.advance(2)
        h.app.open(.message(roomID: "!a", eventID: "$45"))
        try await waitUntil { h.conversation.highlightedMessageID == "$45" && time.pendingSleeps == [3] }
        time.advance(1)
        await Task.yield()
        XCTAssertEqual(h.conversation.highlightedMessageID, "$45")
        time.advance(2)
        try await waitUntil { h.conversation.highlightedMessageID == nil }
        await stop(h)
    }

    func testMissingMessageOpensTheNewestPage() async throws {
        let h = try await start(["!a": history(3)])
        h.unread.counts["!a"] = 1
        h.app.open(.message(roomID: "!a", eventID: "$gone"))
        try await waitUntil { h.messageIDs() == ["$1", "$2", "$3"] }

        XCTAssertEqual(h.conversation.problem, .messageGone, "a calm notice, not an error")
        XCTAssertFalse(h.conversation.isAwayFromLatest)
        XCTAssertNil(h.conversation.highlightedMessageID)
        XCTAssertNil(h.conversation.scrollToMessageRequest)
        let reads = h.server.receivedParams("room.events")
        XCTAssertEqual(reads.first?["around"] as? String, "$gone")
        XCTAssertEqual(Set(try XCTUnwrap(reads.last).keys), ["room_id", "limit"])
        XCTAssertTrue(h.conversation.items.contains { $0.id == "new" }, "opened as the newest page is")
        try await waitUntil { h.count("room.markRead") == 1 }

        // A new message doesn't take the notice away; another chat does.
        h.script.add("!a", textEvent(id: "$4", room: "!a", at: 4))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$4"])
        try await waitUntil { h.messageIDs().last == "$4" }
        XCTAssertEqual(h.conversation.problem, .messageGone)
        h.app.selectedRoomID = nil
        XCTAssertNil(h.conversation.problem)
        await stop(h)
    }

    func testAFailedNewestPageAfterAMissingMessageSaysOnlyThatItFailed() async throws {
        let h = try await start(["!a": history(3)])
        h.script.failNewest = true
        h.app.open(.message(roomID: "!a", eventID: "$gone"))
        try await waitUntil { h.conversation.problem == .loadFailed }

        // Try again reads the newest page; the old notice doesn't come back with it.
        h.script.failNewest = false
        h.conversation.reload()
        try await waitUntil { h.messageIDs() == ["$1", "$2", "$3"] }
        XCTAssertNil(h.conversation.problem)
        await stop(h)
    }

    // MARK: - Actions

    func testActionsSendOnlyDocumentedKeys() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }

        await h.conversation.react(to: "$1", key: "❤️")
        await h.conversation.retry("$2")
        await h.conversation.discard("$2")
        XCTAssertEqual(h.server.receivedParams("message.react").first as? [String: String],
                       ["room_id": "!a", "event_id": "$1", "key": "❤️"])
        XCTAssertEqual(h.server.receivedParams("message.retry").first as? [String: String], ["event_id": "$2"])
        XCTAssertEqual(h.server.receivedParams("message.discard").first as? [String: String], ["event_id": "$2"])
        await stop(h)
    }

    func testTheQuickReactionsStartWithAHeart() {
        XCTAssertEqual(ConversationModel.quickReactions, ["❤️", "👍", "😂", "😮", "😢", "🙏"])
    }

    func testSendingThroughTheComposerReachesTheEngineWithTheReply() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }

        h.conversation.reply(to: "$1")
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$1")
        XCTAssertEqual(h.conversation.composer.replyTarget?.text, "Message 1")
        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        XCTAssertEqual(h.server.receivedParams("message.send").first as? [String: String],
                       ["room_id": "!a", "text": "On my way", "reply_to": "$1"])
        XCTAssertEqual(h.conversation.jumpToBottomRequest, 1, "sending scrolls to the newest message")
        await stop(h)
    }

    func testReplyToTheSelectedMessage() async throws {
        let h = try await start(["!a": history(2)])
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        h.conversation.replyToSelected()
        XCTAssertNil(h.conversation.composer.replyTarget, "nothing selected")
        h.conversation.selectedMessageID = "$2"
        h.conversation.replyToSelected()
        XCTAssertEqual(h.conversation.composer.replyTarget?.eventID, "$2")
        await stop(h)
    }
}

// MARK: - Protocol 5: typing, receipts, Mark as Unread, Reply Privately

extension ConversationModelTests {
    /// A conversation with the inbox's rows, its toasts kept; stopped at teardown.
    private func startWithRows(_ events: [String: [[String: Any]]], rows: [String: InboxRow],
                               features: [String: [String: Any]] = [:]) async throws -> (ConversationHarness, Toasts) {
        let h = try await startConversation(events, features: features, rows: rows)
        timed.append(h)
        let toasts = Toasts()
        h.conversation.onToast = { toasts.lines.append($0) }
        return (h, toasts)
    }

    /// An inbox row as the engine writes it, with who is typing.
    private func typingRow(_ id: String, _ typing: [String]) -> [String: Any] {
        var row = room(id, ts: 1, name: "Ann")
        row["typing"] = typing
        return row
    }

    func testTypingLineFollowsTheRow() async throws {
        var opened = chatRow("!a", name: "Ann")
        opened.typing = ["Ana"]
        let (h, _) = try await startWithRows(["!a": history(2), "!b": history(2, room: "!b")],
                                             rows: ["!a": opened, "!b": chatRow("!b", name: "Bo")])
        h.script.rooms = [typingRow("!a", ["Ana"]), typingRow("!b", ["Bo"])]
        try await h.open("!a")
        XCTAssertEqual(h.conversation.typingLine, "Ana is typing…", "as the row words it")

        // A typing change reads the row again: whoever stopped is gone, and more than one is counted.
        h.script.rooms = [typingRow("!a", []), typingRow("!b", ["Bo"])]
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.conversation.typingLine == nil }
        h.script.rooms = [typingRow("!a", ["Ana", "Bo", "Cy"]), typingRow("!b", ["Bo"])]
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.conversation.typingLine == "3 people are typing…" }

        // Another chat's typing reads nothing: the read for this one is the only one after it.
        let reads = h.count("inbox.list")
        h.script.rooms = [typingRow("!a", ["Cy"]), typingRow("!b", ["Bo"])]
        h.server.notify(["kind": "typing", "room_id": "!b"])
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.conversation.typingLine == "Cy is typing…" }
        XCTAssertEqual(h.count("inbox.list"), reads + 1)

        // A read that fails shows no one: a typing line never sticks.
        h.script.overrides["inbox.list"] = .error(code: -32603, message: "internal error")
        h.server.notify(["kind": "typing", "room_id": "!a"])
        try await waitUntil { h.conversation.typingLine == nil }
        h.script.overrides = [:]

        // Another chat open: its own row's (no one is typing in it as the inbox has it).
        try await h.open("!b")
        XCTAssertNil(h.conversation.typingLine)
    }

    func testAReceiptChangeRefetchesTheNewestPage() async throws {
        let (h, _) = try await startWithRows(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1), textEvent(id: "$2", room: "!a", at: 2, mine: true)]],
            rows: ["!a": chatRow("!a", name: "Ann")])
        try await h.open("!a")
        XCTAssertEqual(h.message("$2")?.statusLine, .sent)

        var delivered = textEvent(id: "$2", room: "!a", at: 2, mine: true)
        delivered["delivered"] = true
        h.script.replace("!a", delivered)
        h.server.notify(["kind": "receipt", "room_id": "!a"])
        try await waitUntil { h.message("$2")?.statusLine == .delivered }

        // Another chat's receipt reads nothing.
        let reads = h.newestRequests()
        var seen = delivered
        seen["read_by"] = [["user_id": "@ann:example.test", "name": "Ann", "ts": ConversationScript.timestamp(3)]]
        h.script.replace("!a", seen)
        h.server.notify(["kind": "receipt", "room_id": "!b"])
        h.server.notify(["kind": "receipt", "room_id": "!a"])
        try await waitUntil {
            h.message("$2")?.statusLine == .seen(by: [], at: ConversationScript.timestamp(3))
        }
        XCTAssertEqual(h.newestRequests(), reads + 1)
    }

    func testMarkUnreadDoesWhatAfterToggleReadSays() async throws {
        let (h, toasts) = try await startWithRows(["!a": history(3), "!b": history(2, room: "!b")],
                                                  rows: ["!a": chatRow("!a", name: "Ann"),
                                                         "!b": chatRow("!b", name: "Bo")])
        try await h.open("!a")
        // The inbox's rule, worked out before the mark and done after it.
        var steps: [String] = []
        h.conversation.planAfterToggleRead = { [h] in
            steps.append("planned, \(h.count("room.setUnreadFrom")) marks")
            return { [h] in
                steps.append("done, \(h.count("room.setUnreadFrom")) marks")
                h.app.selectedRoomID = "!b"
            }
        }
        await h.conversation.markUnread(from: "$2")
        XCTAssertEqual(dicts(h.server.receivedParams("room.setUnreadFrom")), dicts([["event_id": "$2"]]),
                       "the message only: the engine finds its chat")
        XCTAssertEqual(steps, ["planned, 0 marks", "done, 1 marks"])
        XCTAssertEqual(h.conversation.roomID, "!b", "where the rule said to go")

        // A refusal is a toast, and nothing moves.
        try await h.open("!a")
        steps = []
        h.script.overrides["room.setUnreadFrom"] = .error(code: -32020, message: "no such chat or message")
        await h.conversation.markUnread(from: "$1")
        XCTAssertEqual(steps, ["planned, 1 marks"])
        XCTAssertEqual(h.conversation.roomID, "!a")
        XCTAssertEqual(toasts.lines, ["That chat or message is no longer there."])
        // A message the chat doesn't have does nothing.
        h.script.overrides = [:]
        await h.conversation.markUnread(from: "$nope")
        XCTAssertEqual(h.count("room.setUnreadFrom"), 2)
    }

    /// Inferred (02 §3.4.2 item 8): Mark as Unread with "Stay on it" keeps the chat unread while it stays open, even
    /// back at the newest message, until a new message comes or it is opened again.
    func testMarkUnreadWithStayStopsAutoReadUntilReopened() async throws {
        let (h, _) = try await startWithRows(["!a": history(120), "!b": history(2, room: "!b")],
                                             rows: ["!a": chatRow("!a", name: "Ann"), "!b": chatRow("!b", name: "Bo")])
        h.conversation.planAfterToggleRead = { {} } // "Stay on it"
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        XCTAssertEqual(h.count("room.markRead"), 0, "away from the newest, nothing is read")
        await h.conversation.markUnread(from: "$30")
        XCTAssertEqual(h.count("room.setUnreadFrom"), 1)

        // Back at the newest message: as opened there it would be read, but it stays unread.
        h.conversation.jumpToBottom()
        try await waitUntil { h.messageIDs(h.conversation.items).last == "$120" }
        // A new message ends it. The first read comes after the page that brought it: none went for the jump.
        let pagesBefore = h.newestRequests()
        h.script.add("!a", textEvent(id: "$121", room: "!a", at: 121))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$121"])
        try await waitUntil { h.count("room.markRead") >= 1 }
        let log = h.server.received.map { request -> String in
            let params = request["params"] as? [String: Any] ?? [:]
            let newest = params["before"] == nil && params["after"] == nil && params["around"] == nil
            let method = request["method"] as? String ?? ""
            return method == "room.events" && newest ? "newest" : method
        }
        let firstRead = try XCTUnwrap(log.firstIndex(of: "room.markRead"))
        let newPage = try XCTUnwrap(log.indices.filter { log[$0] == "newest" }.dropFirst(pagesBefore).first)
        XCTAssertGreaterThan(firstRead, newPage, "nothing marked the chat read before the new message came")

        // Marked unread again and staying: opening it again reads it.
        try await waitUntil { h.count("room.markRead") == 1 }
        await h.conversation.markUnread(from: "$121")
        try await h.open("!b")
        try await waitUntil { h.count("room.markRead") == 2 }
        XCTAssertEqual(h.server.receivedParams("room.markRead").last as? [String: String], ["room_id": "!b"])
        try await h.open("!a")
        try await waitUntil { h.count("room.markRead") == 3 }
        XCTAssertEqual(h.server.receivedParams("room.markRead").last as? [String: String], ["room_id": "!a"])
    }

    // MARK: - Incognito

    /// A change in the chat, and its newest page read and applied: what the model did about it is done.
    private func change(_ h: ConversationHarness, _ room: String = "!a", adding event: [String: Any]? = nil,
                        replacing replaced: [String: Any]? = nil) async throws {
        if let event { h.script.add(room, event) }
        if let replaced { h.script.replace(room, replaced) }
        let applied = h.conversation.pagesApplied
        h.server.notify(["kind": "event", "room_id": room, "event_id": "$change"])
        try await waitUntil { h.conversation.pagesApplied > applied }
    }

    /// Review Focus 4. While Incognito is on, opening a chat and reading it marks nothing read. It becomes read
    /// when I send a message in it (the networks mark it read then anyway) or by hand (⌘⇧U, Mark as Read), and
    /// Incognito is still on for what comes after.
    func testIncognitoDoesNotMarkReadUntilReplyOrCommand() async throws {
        let (h, _) = try await startWithRows(["!a": history(3)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.isEntitled = { $0 == .incognito }
        h.preferences.incognito = true
        XCTAssertTrue(h.conversation.incognitoIsOn)
        try await h.open("!a")
        XCTAssertEqual(h.conversation.readsSent, 0, "opened and looked at: still unread")

        // A message comes while I look: still nothing. Nor does coming back to the window.
        try await change(h, adding: textEvent(id: "$4", room: "!a", at: 4))
        XCTAssertEqual(h.messageIDs(h.conversation.items).last, "$4")
        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        XCTAssertEqual(h.conversation.readsSent, 0)

        // My message from this Mac waiting to go is not a reply yet; once it has gone, the chat is read (Ruling 24).
        h.script.overrides["message.send"] = .result(["event_id": "$5"])
        h.script.add("!a", textEvent(id: "$5", room: "!a", at: 5, mine: true, status: "pending"))
        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        try await change(h)
        XCTAssertEqual(h.conversation.readsSent, 0)
        try await change(h, replacing: textEvent(id: "$5", room: "!a", at: 5, mine: true, status: "sent"))
        XCTAssertEqual(h.conversation.readsSent, 1)
        try await waitUntil { h.count("room.markRead") == 1 }
        XCTAssertEqual(h.server.receivedParams("room.markRead").first as? [String: String], ["room_id": "!a"])

        // Incognito is still on: what they write next stays unread, and a status change of my message is no reply.
        try await change(h, adding: textEvent(id: "$6", room: "!a", at: 6))
        try await change(h, replacing: textEvent(id: "$5", room: "!a", at: 5, mine: true, status: "sent"))
        XCTAssertEqual(h.conversation.readsSent, 1)

        // ⌘⇧U (the inbox's Mark as Read) still reads it.
        let inboxDefaults = TestDefaults()
        defer { inboxDefaults.remove() }
        let inbox = InboxModel(appModel: h.app, preferences: InboxPreferences(defaults: inboxDefaults.defaults),
                               sleep: { _ in })
        await inbox.setRead(true, ids: ["!a"])
        try await waitUntil { h.count("room.markRead") == 2 }
        XCTAssertEqual(h.conversation.readsSent, 1, "the inbox's own call")
    }

    /// Review Focus 4. Turning Incognito off sends nothing for chats I looked at while it was on: not on turning
    /// it off, not when I come back to the window, not when the chat is read again for a status change. The next
    /// message that comes is read as usual.
    func testTurningIncognitoOffSendsNothingForChatsAlreadyOpen() async throws {
        let (h, _) = try await startWithRows(["!a": history(3), "!b": history(2, room: "!b")],
                                             rows: ["!a": chatRow("!a", name: "Ann"), "!b": chatRow("!b", name: "Bo")])
        h.conversation.isEntitled = { _ in true }
        h.preferences.incognito = true
        // Opened while nobody looks, then looked at.
        h.conversation.setWindowKey(false)
        try await h.open("!a")
        h.conversation.setWindowKey(true)
        XCTAssertEqual(h.conversation.readsSent, 0)

        h.conversation.setIncognito(false)
        XCTAssertFalse(h.preferences.incognito)
        XCTAssertFalse(h.conversation.incognitoIsOn)
        XCTAssertEqual(h.conversation.readsSent, 0, "turning it off sends nothing")
        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        h.script.add("!a", textEvent(id: "$3r", room: "!a", at: 3, mine: true, status: "pending"))
        try await change(h)
        XCTAssertEqual(h.conversation.readsSent, 0, "nothing waited for the person to come back")

        // Something new to read: read as usual again.
        try await change(h, adding: textEvent(id: "$4", room: "!a", at: 4))
        XCTAssertEqual(h.conversation.readsSent, 1)
        // And a chat opened now is read on opening.
        try await h.open("!b")
        XCTAssertEqual(h.conversation.readsSent, 2)
        try await waitUntil { h.count("room.markRead") == 2 }
        XCTAssertEqual(h.server.receivedParams("room.markRead").map { $0["room_id"] as? String }, ["!a", "!b"])
    }

    /// The same for a chat opened at a message while Incognito is on: jumping to the newest message reads nothing, and
    /// nothing waits to be read when Incognito is turned off before the person looks again.
    func testIncognitoOffAfterLeavingAWindowSendsNothing() async throws {
        let (h, _) = try await startWithRows(["!a": history(120)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.isEntitled = { _ in true }
        h.preferences.incognito = true
        h.app.open(.message(roomID: "!a", eventID: "$30"))
        try await waitUntil { h.conversation.isAwayFromLatest }
        h.conversation.setWindowKey(false)
        let applied = h.conversation.pagesApplied
        h.conversation.jumpToBottom()
        try await waitUntil { h.conversation.pagesApplied > applied && !h.conversation.isAwayFromLatest }
        h.conversation.setIncognito(false)
        h.conversation.setWindowKey(true)
        XCTAssertEqual(h.conversation.readsSent, 0)
    }

    /// A reply sent from an older part of the chat (opened at a message) jumps to the newest and reads the chat, as
    /// any reply does: in Incognito, and after Mark as Unread with "Stay on it". The newest page the jump asks for is
    /// held until the send is done, so it is the first page after the window and already has the reply as sent.
    func testAReplyFromAnOlderMessageReadsTheChat() async throws {
        func replyFromAWindow(_ h: ConversationHarness, before: () async -> Void) async throws {
            h.app.open(.message(roomID: "!a", eventID: "$30"))
            try await waitUntil { h.conversation.isAwayFromLatest }
            await before()
            let pages = h.newestRequests()
            h.script.hold("!a")
            h.conversation.composer.text = "On my way"
            await h.conversation.composer.submit()?.value
            try await waitUntil { h.newestRequests() > pages }
            h.server.releaseHeld(method: "room.events", room: "!a",
                                 with: ["events": h.script.newestFirst("!a", limit: 50), "before": NSNull(),
                                        "after": NSNull()])
            try await waitUntil { h.messageIDs(h.conversation.items).last == "$sent" && !h.conversation.isAwayFromLatest }
            try await waitUntil { h.conversation.readsSent == 1 }
            try await waitUntil { h.count("room.markRead") == 1 }
        }
        let (h, _) = try await startWithRows(["!a": history(120)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.isEntitled = { _ in true }
        h.preferences.incognito = true
        try await replyFromAWindow(h) {}

        let (held, _) = try await startWithRows(["!a": history(120)], rows: ["!a": chatRow("!a", name: "Ann")])
        held.conversation.planAfterToggleRead = { {} } // "Stay on it"
        try await replyFromAWindow(held) { await held.conversation.markUnread(from: "$30") }
    }

    /// A reply reads the chat once. Their next message, or a later read of the page, doesn't count the same reply
    /// again: in Incognito it stays unread, and a later Mark as Unread hold holds.
    func testAReplyIsCountedOnce() async throws {
        let (h, _) = try await startWithRows(["!a": history(3)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.isEntitled = { _ in true }
        h.preferences.incognito = true
        try await h.open("!a")
        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        try await change(h)
        XCTAssertEqual(h.conversation.readsSent, 1, "the reply read the chat")

        try await change(h, adding: textEvent(id: "$4", room: "!a", at: 10))
        XCTAssertEqual(h.messageIDs(h.conversation.items).last, "$4")
        XCTAssertEqual(h.conversation.readsSent, 1, "their new message stays unread in Incognito")

        // Incognito off, Mark as Unread with "Stay on it": a later read of the page doesn't end the hold.
        h.conversation.setIncognito(false)
        h.conversation.planAfterToggleRead = { {} }
        await h.conversation.markUnread(from: "$4")
        let applied = h.conversation.pagesApplied
        h.server.notify(["kind": "receipt", "room_id": "!a"])
        try await waitUntil { h.conversation.pagesApplied > applied }
        XCTAssertEqual(h.conversation.readsSent, 1)
    }

    /// A reply in the thread pane is a reply too: it reads a chat Incognito keeps unread, once its thread's page shows
    /// it went (the chat's own page leaves such replies out).
    func testAThreadReplyReadsTheChat() async throws {
        let (h, _) = try await startWithRows(
            ["!a": [threadRoot(id: "$r", room: "!a", at: 1, replies: 0), textEvent(id: "$2", room: "!a", at: 2)]],
            rows: ["!a": chatRow("!a", name: "Ann")], features: ["!a": featuresJSON(replyIsThread: true)])
        h.conversation.isEntitled = { _ in true }
        h.preferences.incognito = true
        try await h.open("!a")
        h.conversation.openThread("$r")
        try await waitUntil { h.conversation.thread.isLoaded }
        XCTAssertEqual(h.conversation.readsSent, 0)

        h.script.overrides["message.send"] = .result(["event_id": "$t1"])
        h.script.add("!a", threadReply(id: "$t1", root: "$r", room: "!a", at: 3, body: "In the thread", mine: true))
        h.conversation.thread.composer.text = "In the thread"
        await h.conversation.thread.composer.submit()?.value
        try await waitUntil { h.messageIDs(h.conversation.thread.items).contains("$t1") }
        try await waitUntil { h.conversation.readsSent == 1 }
        XCTAssertFalse(h.messageIDs(h.conversation.items).contains("$t1"), "not in the chat's own page")
    }

    /// A4: quitting while I type tells the chat I stopped, from the chat's composer and the thread pane's, before the
    /// held messages go and the engine stops (AppModel.quit, what Courier ▸ Quit runs).
    func testQuitStopsTypingOnBothComposersFirst() async throws {
        let (h, _) = try await startWithRows(
            ["!a": [threadRoot(id: "$r", room: "!a", at: 1, replies: 0), textEvent(id: "$2", room: "!a", at: 2)]],
            rows: ["!a": chatRow("!a", name: "Ann")], features: ["!a": featuresJSON(replyIsThread: true)])
        try await h.open("!a")
        h.conversation.openThread("$r")
        try await waitUntil { h.conversation.thread.isLoaded }
        h.conversation.composer.text = "h"
        h.conversation.thread.composer.text = "i"
        try await waitUntil { h.count("room.setTyping") == 2 }

        await h.app.quit(h.conversation)
        let methods = h.server.receivedMethods().filter { ["room.setTyping", "message.sendHeld"].contains($0) }
        XCTAssertEqual(methods, ["room.setTyping", "room.setTyping", "room.setTyping", "room.setTyping",
                                 "message.sendHeld"], "the stops go before the held messages")
        XCTAssertEqual(h.server.receivedParams("room.setTyping").map { $0["typing"] as? Bool },
                       [true, true, false, false], "a stop from each composer")
        XCTAssertNil(h.app.client, "then the engine stops")
    }

    /// In Incognito the chat stays unread, so its "New" divider stays where opening put it, through new messages.
    func testTheNewDividerStaysInIncognito() async throws {
        let h = try await start(["!a": history(5)])
        let defaults = TestDefaults()
        defer { defaults.remove() }
        let preferences = ComposerPreferences(defaults: defaults.defaults)
        preferences.incognito = true
        h.conversation.preferences = preferences
        h.conversation.isEntitled = { _ in true }
        h.unread.counts["!a"] = 2
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded }
        let ids = h.conversation.items.map(\.id)
        let divider = try XCTUnwrap(ids.firstIndex(of: "new"))
        XCTAssertEqual(ids[divider + 1], "$4")
        XCTAssertEqual(h.conversation.readsSent, 0)

        let applied = h.conversation.pagesApplied
        h.unread.counts["!a"] = 3
        h.script.add("!a", textEvent(id: "$6", room: "!a", at: 6))
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$6"])
        try await waitUntil { h.conversation.pagesApplied > applied }
        XCTAssertEqual(h.conversation.items.map(\.id).firstIndex(of: "new"), divider)
        XCTAssertEqual(h.conversation.readsSent, 0)

        // Opened again, still unread: the divider is there again, above all three.
        h.app.selectedRoomID = nil
        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded && h.messageIDs().contains("$6") }
        let again = h.conversation.items.map(\.id)
        XCTAssertEqual(again[try XCTUnwrap(again.firstIndex(of: "new")) + 1], "$4")
        XCTAssertEqual(h.conversation.readsSent, 0)
        await stop(h)
    }

    /// Incognito is part of a plan: without it the saved setting does nothing (chats are read as usual, and the mark
    /// isn't shown), and it can't be turned on. Turning it on asks whether to also hide typing; Hide Typing turns
    /// "Show recipients I'm typing" off.
    func testIncognitoNeedsTheEntitlement() async throws {
        let (h, _) = try await startWithRows(["!a": history(3)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.preferences.incognito = true
        XCTAssertFalse(h.conversation.incognitoIsOn, "no plan given: no incognito")
        try await h.open("!a")
        XCTAssertEqual(h.conversation.readsSent, 1)
        try await waitUntil { h.count("room.markRead") == 1 }

        h.preferences.incognito = false
        h.conversation.setIncognito(true)
        XCTAssertFalse(h.preferences.incognito, "not without the plan")
        XCTAssertFalse(h.conversation.asksToHideTyping)

        h.conversation.isEntitled = { _ in true }
        h.conversation.setIncognito(true)
        XCTAssertTrue(h.preferences.incognito)
        XCTAssertTrue(h.conversation.incognitoIsOn)
        XCTAssertTrue(h.conversation.asksToHideTyping)
        XCTAssertEqual(ConversationModel.hideTypingQuestion, "Also hide that you’re typing?")
        XCTAssertEqual(ConversationModel.hideTypingButton, "Hide Typing")
        XCTAssertEqual(ConversationModel.keepShowingTypingButton, "Keep Showing")
        h.conversation.answerHideTyping(true)
        XCTAssertFalse(h.conversation.asksToHideTyping)
        XCTAssertFalse(h.preferences.showTyping)
        XCTAssertFalse(h.conversation.composer.sendsTyping())
        XCTAssertFalse(h.conversation.thread.composer.sendsTyping())

        // Off and on again with typing already hidden: nothing to ask. Keep Showing changes nothing.
        h.conversation.setIncognito(false)
        h.preferences.showTyping = true
        h.conversation.setIncognito(true)
        XCTAssertTrue(h.conversation.asksToHideTyping)
        h.conversation.answerHideTyping(false)
        XCTAssertTrue(h.preferences.showTyping)
        h.conversation.setIncognito(false)
        h.preferences.showTyping = false
        h.conversation.setIncognito(true)
        XCTAssertFalse(h.conversation.asksToHideTyping, "typing is hidden already")
    }

    /// C21: my typing goes out from either composer only while "Show recipients I'm typing" is on, read at each
    /// keystroke, so a change in Settings counts at once; Incognito alone doesn't hide it (its Hide Typing turns
    /// the setting off).
    func testSendsTypingFollowsTheShowTypingSettingOnBothComposers() async throws {
        let (h, _) = try await startWithRows(["!a": history(2)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.isEntitled = { _ in true }
        let composers = [h.conversation.composer, h.conversation.thread.composer]
        XCTAssertEqual(composers.map { $0.sendsTyping() }, [true, true], "on by default")
        h.preferences.showTyping = false
        XCTAssertEqual(composers.map { $0.sendsTyping() }, [false, false])
        h.preferences.incognito = true
        h.preferences.showTyping = true
        XCTAssertEqual(composers.map { $0.sendsTyping() }, [true, true], "Incognito alone doesn't hide typing")

        // Another settings object given later is the one read.
        let other = TestDefaults()
        defer { other.remove() }
        let replaced = ComposerPreferences(defaults: other.defaults)
        replaced.showTyping = false
        h.conversation.preferences = replaced
        XCTAssertEqual(composers.map { $0.sendsTyping() }, [false, false])

        // And it is what the composer obeys: with it on, typing in the open chat sends a start.
        replaced.showTyping = true
        try await h.open("!a")
        h.conversation.composer.text = "h"
        try await waitUntil { h.count("room.setTyping") == 1 }
    }

    /// Mark as Unread from a message keeps the chat unread while it stays open; a message I send in it from this Mac
    /// ends that, as a reply reads a chat (Global Constraints: "Reading the chat (⌘⇧U, Mark as Read, or a reply)
    /// clears it").
    func testMyReplyEndsTheMarkUnreadHold() async throws {
        let (h, _) = try await startWithRows(["!a": history(3)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.planAfterToggleRead = { {} } // "Stay on it"
        try await h.open("!a")
        try await waitUntil { h.count("room.markRead") == 1 }
        await h.conversation.markUnread(from: "$2")
        let reads = h.conversation.readsSent
        h.script.overrides["message.send"] = .result(["event_id": "$m"])
        h.script.add("!a", textEvent(id: "$m", room: "!a", at: 4, mine: true, status: "pending"))
        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        try await change(h)
        XCTAssertEqual(h.conversation.readsSent, reads, "not gone yet")
        try await change(h, replacing: textEvent(id: "$m", room: "!a", at: 4, mine: true, status: "sent"))
        XCTAssertEqual(h.conversation.readsSent, reads + 1)
        try await waitUntil { h.count("room.markRead") == 2 }
    }

    /// Ruling 24: a scheduled (Send Later) message going out in an Incognito chat is not me replying from this Mac.
    /// It sends no room.markRead (so no read receipt reaches the other side), and Incognito still holds after it.
    func testAScheduledMessageGoingOutInIncognitoSendsNoReadAndKeepsTheHold() async throws {
        let (h, _) = try await startWithRows(["!a": history(3)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.isEntitled = { $0 == .incognito }
        h.preferences.incognito = true
        try await h.open("!a")
        XCTAssertEqual(h.conversation.readsSent, 0)

        // The engine sends the scheduled message at its time: it appears as mine, waiting, then gone.
        try await change(h, adding: textEvent(id: "$later", room: "!a", at: 4, mine: true, status: "pending"))
        try await change(h, replacing: textEvent(id: "$later", room: "!a", at: 4, mine: true, status: "sent"))
        XCTAssertEqual(h.messageIDs(h.conversation.items).last, "$later")
        XCTAssertEqual(h.conversation.readsSent, 0, "a scheduled message is not a reply")

        // The hold is still on: their next message stays unread too.
        try await change(h, adding: textEvent(id: "$5", room: "!a", at: 5))
        XCTAssertEqual(h.conversation.readsSent, 0)
        XCTAssertEqual(h.count("room.markRead"), 0)
    }

    /// Ruling 24: a message of mine sent from another device (my phone) doesn't end a Mark-as-Unread hold and sends
    /// no room.markRead. The phone's own read receipt moves my marker. A reply from this Mac afterwards still ends it.
    func testAMessageOfMineFromAnotherDeviceKeepsTheMarkUnreadHold() async throws {
        let (h, _) = try await startWithRows(["!a": history(3)], rows: ["!a": chatRow("!a", name: "Ann")])
        h.conversation.planAfterToggleRead = { {} } // "Stay on it"
        try await h.open("!a")
        try await waitUntil { h.count("room.markRead") == 1 }
        await h.conversation.markUnread(from: "$2")
        let reads = h.conversation.readsSent

        try await change(h, adding: textEvent(id: "$phone", room: "!a", at: 4, mine: true))
        XCTAssertEqual(h.messageIDs(h.conversation.items).last, "$phone")
        XCTAssertEqual(h.conversation.readsSent, reads, "a message from my phone is not a reply from this Mac")
        h.conversation.setWindowKey(false)
        h.conversation.setWindowKey(true)
        XCTAssertEqual(h.conversation.readsSent, reads, "the hold holds")
        XCTAssertEqual(h.count("room.markRead"), 1)

        // A reply from this Mac ends it.
        h.conversation.composer.text = "On my way"
        await h.conversation.composer.submit()?.value
        try await change(h)
        XCTAssertEqual(h.conversation.readsSent, reads + 1)
        try await waitUntil { h.count("room.markRead") == 2 }
    }

    func testReplyPrivatelyOpensTheChatWithTheQuote() async throws {
        var quotes = featuresJSON()
        quotes["formatting"] = ["bold", "blockquote"]
        let (h, toasts) = try await startWithRows(
            ["!g": [textEvent(id: "$1", room: "!g", at: 1, body: "Lunch at noon?")], "!d": history(1, room: "!d")],
            rows: ["!g": chatRow("!g", name: "Book club", direct: false), "!d": chatRow("!d", name: "Ann")],
            features: ["!g": featuresJSON(), "!d": quotes])
        h.script.accounts = [account("whatsapp", "CONNECTED")]
        await h.app.refreshAccounts()
        h.script.directChat = "!d"
        try await h.open("!g")
        let message = try XCTUnwrap(h.message("$1"))
        XCTAssertTrue(h.conversation.availableActions(for: message).actions.contains(.replyPrivately))

        await h.conversation.replyPrivately(to: "$1")
        XCTAssertEqual(dicts(h.server.receivedParams("room.directChat")),
                       dicts([["room_id": "!g", "user_id": "@ann:example.test"]]))
        XCTAssertEqual(h.app.selectedRoomID, "!d", "the one-to-one chat opens")
        // Once its features are read: a quote range, a blank line, the caret after it.
        try await waitUntil { h.conversation.composer.text == "Lunch at noon?\n\n" }
        XCTAssertEqual(h.conversation.composer.roomID, "!d")
        XCTAssertEqual(h.conversation.composer.entities, [TextEntity(kind: .blockquote, offset: 0, length: 14)])
        XCTAssertEqual(h.conversation.composer.caretRequest?.location, 16)

        // A refusal is a toast in Courier's words, and the group stays open.
        try await h.open("!g")
        h.script.overrides["room.directChat"] = .error(code: -32023, message: "this network can't do that")
        await h.conversation.replyPrivately(to: "$1")
        XCTAssertEqual(h.app.selectedRoomID, "!g")
        XCTAssertEqual(toasts.lines, ["WhatsApp can’t start a chat with this person."])

        // Not in a one-to-one chat: nothing is asked.
        try await h.open("!d")
        await h.conversation.replyPrivately(to: "$1")
        XCTAssertEqual(h.count("room.directChat"), 2)
    }

    /// Ruling 20: each refusal in Courier's words; the quote falls back to "> " lines when the private chat's features
    /// can't be read (C19); and Reply Privately is there only while the network runs, not while it starts or when it
    /// didn't start.
    func testReplyPrivatelyRefusalsFallbackAndANetworkThatDoesNotRun() async throws {
        let (h, toasts) = try await startWithRows(
            ["!g": [textEvent(id: "$1", room: "!g", at: 1, body: "Lunch at noon?")], "!d": history(1, room: "!d")],
            rows: ["!g": chatRow("!g", name: "Book club", direct: false), "!d": chatRow("!d", name: "Ann")],
            features: ["!g": featuresJSON()]) // !d's can't be read
        h.script.directChat = "!d"
        try await h.open("!g")
        let message = try XCTUnwrap(h.message("$1"))
        for state in ["STARTING", "NOT_STARTED"] {
            h.script.accounts = [account("whatsapp", state)]
            await h.app.refreshAccounts()
            XCTAssertFalse(h.conversation.availableActions(for: message).actions.contains(.replyPrivately), state)
            await h.conversation.replyPrivately(to: "$1")
        }
        XCTAssertEqual(h.count("room.directChat"), 0, "not offered, so nothing is asked")
        h.script.accounts = [account("whatsapp", "CONNECTED")]
        await h.app.refreshAccounts()
        XCTAssertTrue(h.conversation.availableActions(for: message).actions.contains(.replyPrivately))

        for (code, message) in [(-32020, "no such chat or message"), (-32018, "the network isn't connected yet"),
                                (-32016, "this network isn't running")] {
            h.script.overrides["room.directChat"] = .error(code: code, message: message)
            await h.conversation.replyPrivately(to: "$1")
        }
        XCTAssertEqual(toasts.lines, ["That person isn’t in this chat any more.", "The network isn’t connected yet.",
                                      "This chat’s network isn’t running."])
        XCTAssertEqual(h.app.selectedRoomID, "!g")

        h.script.overrides = [:]
        await h.conversation.replyPrivately(to: "$1")
        try await waitUntil { h.conversation.composer.text == "> Lunch at noon?\n\n" }
        XCTAssertEqual(h.conversation.composer.roomID, "!d")
        XCTAssertEqual(h.conversation.composer.entities, [])
    }

    func testMergedChatActiveReplyRoomCyclesAndPersists() async throws {
        let h = try await start([
            "!wa:courier.local": [textEvent(id: "$w1", room: "!wa:courier.local", at: 1, body: "On WhatsApp")],
            "!sig:courier.local": [textEvent(id: "$s1", room: "!sig:courier.local", at: 2, body: "On Signal")],
        ])
        let merged = MergedChat(
            mergeID: "merge:alice",
            name: "Alice Example",
            avatarPath: "",
            lastRoomID: "!wa:courier.local",
            roomIDs: ["!wa:courier.local", "!sig:courier.local"],
            networks: ["whatsapp", "signal"],
            createdTS: 1_700_000_000_000
        )
        h.script.mergedRooms["merge:alice"] = ["!wa:courier.local", "!sig:courier.local"]

        h.conversation.openMergedChat(merged)
        XCTAssertEqual(h.conversation.activeReplyRoomID, "!wa:courier.local")
        XCTAssertEqual(h.conversation.activeReplyNetwork, "whatsapp")
        try await waitUntil { h.messageIDs() == ["$w1", "$s1"] }

        h.conversation.cycleMergedReplyNetwork()
        XCTAssertEqual(h.conversation.activeReplyRoomID, "!sig:courier.local")
        XCTAssertEqual(h.conversation.activeReplyNetwork, "signal")
        XCTAssertEqual(h.conversation.composer.roomID, "!sig:courier.local")
        try await waitUntil { h.count("merge.update") == 1 }
        XCTAssertEqual(h.server.receivedParams("merge.update").last?["last_room_id"] as? String, "!sig:courier.local")

        // Ruling: an incoming message on WhatsApp while the pill says Signal must NOT silently switch where my reply goes.
        h.script.add("!wa:courier.local", textEvent(id: "$w2", room: "!wa:courier.local", at: 3, body: "Ping on WA"))
        h.server.notify(["kind": "event", "room_id": "!wa:courier.local", "event_id": "$w2"])
        try await waitUntil { h.messageIDs() == ["$w1", "$s1", "$w2"] }
        XCTAssertEqual(h.conversation.activeReplyRoomID, "!sig:courier.local",
                       "incoming on WhatsApp while the pill says Signal -> still Signal")
        XCTAssertEqual(h.conversation.activeReplyNetwork, "signal")
        XCTAssertEqual(h.conversation.composer.roomID, "!sig:courier.local")

        h.conversation.cycleMergedReplyNetwork()
        XCTAssertEqual(h.conversation.activeReplyRoomID, "!wa:courier.local")
        XCTAssertEqual(h.conversation.activeReplyNetwork, "whatsapp")
        await stop(h)
    }

    func testOpeningMemberRoomDirectlyClearsMergedState() async throws {
        let h = try await start([
            "!wa:courier.local": [textEvent(id: "$w1", room: "!wa:courier.local", at: 1, body: "On WhatsApp")],
            "!sig:courier.local": [textEvent(id: "$s1", room: "!sig:courier.local", at: 2, body: "On Signal")],
        ])
        let merged = MergedChat(
            mergeID: "merge:alice",
            name: "Alice Example",
            avatarPath: "",
            lastRoomID: "!wa:courier.local",
            roomIDs: ["!wa:courier.local", "!sig:courier.local"],
            networks: ["whatsapp", "signal"],
            createdTS: 1_700_000_000_000
        )
        h.script.mergedRooms["merge:alice"] = ["!wa:courier.local", "!sig:courier.local"]

        // 1. Open through the merged row: mergedChat state is active.
        h.conversation.openMergedChat(merged)
        h.app.selectedRoomID = "merge:alice"
        try await waitUntil { h.messageIDs() == ["$w1", "$s1"] }
        XCTAssertEqual(h.conversation.mergedChat?.mergeID, "merge:alice")
        XCTAssertEqual(h.conversation.activeReplyRoomID, "!wa:courier.local")

        // 2. Open a member room directly via AppModel.open(.chat) (as chat search does):
        // opens as a single room and clears the merged state.
        h.app.open(.chat(roomID: "!wa:courier.local"))
        try await waitUntil { h.conversation.roomID == "!wa:courier.local" && h.messageIDs() == ["$w1"] }
        XCTAssertNil(h.conversation.mergedChat, "opening a member room directly must clear mergedChat")
        XCTAssertNil(h.conversation.activeReplyRoomID)
        XCTAssertNil(h.conversation.activeReplyNetwork)
        XCTAssertEqual(h.conversation.composer.roomID, "!wa:courier.local")

        // 3. Re-open merged chat, then open a member room directly via notification / AppModel.open(.message):
        h.conversation.openMergedChat(merged)
        h.app.selectedRoomID = "merge:alice"
        try await waitUntil { h.conversation.mergedChat?.mergeID == "merge:alice" }

        h.app.open(.message(roomID: "!sig:courier.local", eventID: "$s1"))
        try await waitUntil { h.conversation.roomID == "!sig:courier.local" && h.messageIDs() == ["$s1"] }
        XCTAssertNil(h.conversation.mergedChat, "opening a member room at a message must clear mergedChat")
        XCTAssertNil(h.conversation.activeReplyRoomID)
        XCTAssertNil(h.conversation.activeReplyNetwork)
        await stop(h)
    }

    func testSaveGroupEditJustForMeNameOnlyPreservesExistingLocalAvatarAndComparesNetworkAvatar() async throws {
        let (h, _) = try await startWithRows(
            ["!g:courier.local": history(1, room: "!g:courier.local")],
            rows: ["!g:courier.local": chatRow("!g:courier.local", name: "Saturday Hike", network: "whatsapp", direct: false)]
        )
        h.script.roomInfos["!g:courier.local"] = [
            "room_id": "!g:courier.local",
            "name": "Saturday Hike",
            "remote_name": "Saturday Hike",
            "local_name": "",
            "topic": "",
            "avatar_path": "/tmp/local-override-avatar.png",
            "local_avatar_uri": "mxc://courier.local/local-override-avatar",
            "network": "whatsapp",
            "account_id": "whatsapp_1",
            "is_direct": false,
            "encrypted": true,
            "disappearing_ms": 0,
            "pinned_event_ids": [String](),
            "members": [[String: Any]](),
            "shared_media": [[String: Any]](),
            "shared_files": [[String: Any]](),
            "shared_links": [[String: Any]](),
            "features": featuresJSON(),
        ]
        try await h.open("!g:courier.local")

        await h.conversation.beginEditChat(roomID: "!g:courier.local")
        var draft = try XCTUnwrap(h.conversation.activeEditGroupDraft)
        XCTAssertEqual(draft.scope, .justForMe)
        // User edits ONLY the name and does not touch the avatar.
        draft.name = "My Hike Nickname"
        let saved = await h.conversation.saveGroupEdit(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setLocalOverride").suffix(1)),
            dicts([[
                "room_id": "!g:courier.local",
                "local_name": "My Hike Nickname",
                "local_avatar_path": "mxc://courier.local/local-override-avatar",
            ]]),
            "name-only Just for Me save must leave an existing local avatar untouched"
        )

        // When no local avatar override exists, avatar_path is the network's avatar; a name-only save compares against
        // the network avatar and sends local_avatar_path: "".
        h.script.roomInfos["!g:courier.local"]?["avatar_path"] = "/tmp/network-avatar.png"
        h.script.roomInfos["!g:courier.local"]?["local_avatar_uri"] = ""
        await h.conversation.beginEditChat(roomID: "!g:courier.local")
        var draft2 = try XCTUnwrap(h.conversation.activeEditGroupDraft)
        draft2.name = "Another Nickname"
        let saved2 = await h.conversation.saveGroupEdit(draft2)
        XCTAssertTrue(saved2)
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setLocalOverride").suffix(1)),
            dicts([[
                "room_id": "!g:courier.local",
                "local_name": "Another Nickname",
                "local_avatar_path": "",
            ]])
        )
        await h.stop()
    }

    func testChatInfoLoadsRoomInfoBookmarksAndExportsToURL() async throws {
        let h = try await start(["!a": history(2, room: "!a")])
        h.script.roomInfos["!a"] = [
            "room_id": "!a",
            "name": "Alice (Work)",
            "remote_name": "Alice Example",
            "local_name": "Alice (Work)",
            "topic": "",
            "avatar_path": "",
            "local_avatar_uri": "",
            "network": "whatsapp",
            "account_id": "whatsapp_1",
            "is_direct": true,
            "encrypted": true,
            "disappearing_ms": 0,
            "pinned_event_ids": ["$1"],
            "members": [
                [
                    "user_id": "@wa_alice:courier.local",
                    "name": "Alice Example",
                    "avatar_path": "",
                    "power_level": 0,
                    "is_admin": false,
                    "identifiers": ["+1 555-010-0101"],
                    "tz": "America/Los_Angeles",
                    "is_bot": false,
                ] as [String: Any],
            ],
            "shared_media": [[String: Any]](),
            "shared_files": [[String: Any]](),
            "shared_links": [
                [
                    "event_id": "$1",
                    "sender": "@wa_alice:courier.local",
                    "ts": 1_760_600_000_000,
                    "url": "https://example.com/spec",
                    "host": "example.com",
                ] as [String: Any],
            ],
            "features": featuresJSON(),
        ]
        h.script.bookmarksByRoom["!a"] = [
            [
                "event_id": "$1",
                "room_id": "!a",
                "room_name": "Alice (Work)",
                "network": "whatsapp",
                "is_direct": true,
                "place": "inbox",
                "sender": "@wa_alice:courier.local",
                "sender_name": "Alice Example",
                "mine": false,
                "ts": 1_760_600_000_000,
                "seq": 1,
                "kind": "text",
                "snippet": "Remember the trail map",
                "ranges": [[String: Any]](),
                "media_path": "",
                "partial": false,
            ] as [String: Any],
        ]

        h.app.selectedRoomID = "!a"
        try await waitUntil { h.conversation.isLoaded && h.conversation.roomID == "!a" }

        XCTAssertFalse(h.conversation.isShowingChatInfo)
        h.conversation.toggleChatInfo()
        XCTAssertTrue(h.conversation.isShowingChatInfo)
        try await waitUntil { h.conversation.chatInfo?.roomID == "!a" && h.conversation.chatInfoBookmarks.count == 1 }
        XCTAssertEqual(h.conversation.chatInfo?.name, "Alice (Work)")
        XCTAssertEqual(h.conversation.chatInfo?.remoteName, "Alice Example")
        XCTAssertEqual(h.conversation.chatInfoBookmarks.first?.snippet, "Remember the trail map")

        await h.conversation.refreshChatInfo(force: true)
        XCTAssertEqual(h.server.receivedParams("room.info").last?["refresh"] as? Bool, true)

        let exportURL = URL(fileURLWithPath: "/tmp/courier-export-test.txt")
        let written = try await h.conversation.exportChat(to: exportURL)
        XCTAssertEqual(written, 2)
        XCTAssertEqual(h.server.receivedParams("room.export").last?["room_id"] as? String, "!a")
        XCTAssertEqual(h.server.receivedParams("room.export").last?["path"] as? String, exportURL.path)
        await stop(h)
    }

    func testSaveGroupEditJustForMeSendsEmptyLocalOverrideWhenUnchangedFromRemote() async throws {
        let (h, _) = try await startWithRows(
            ["!g:courier.local": history(1, room: "!g:courier.local")],
            rows: ["!g:courier.local": chatRow("!g:courier.local", name: "Saturday Hike", network: "whatsapp", direct: false)]
        )
        try await h.open("!g:courier.local")

        let unchangedDraft = EditGroupDraft(
            roomID: "!g:courier.local",
            scope: .justForMe,
            name: "Saturday Hike",
            topic: "",
            avatarPath: "/tmp/remote-avatar.png",
            features: h.conversation.features,
            remoteName: "Saturday Hike",
            remoteTopic: "",
            remoteAvatarPath: "/tmp/remote-avatar.png"
        )
        let saved = await h.conversation.saveGroupEdit(unchangedDraft)
        XCTAssertTrue(saved)
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setLocalOverride").suffix(1)),
            dicts([["room_id": "!g:courier.local", "local_name": "", "local_avatar_path": ""]])
        )
    }

    func testEditGroupSavesForEveryoneOrJustForMe() async throws {
        var groupFeatures = featuresJSON()
        groupFeatures["can_set_name"] = true
        groupFeatures["can_set_topic"] = true
        groupFeatures["can_set_avatar"] = true
        groupFeatures["can_invite"] = true
        groupFeatures["can_kick"] = true
        groupFeatures["can_set_admin"] = true
        groupFeatures["can_leave"] = true
        groupFeatures["can_delete"] = true
        groupFeatures["delete_leaves_group"] = true

        let (h, toasts) = try await startWithRows(
            ["!g:courier.local": history(2, room: "!g:courier.local")],
            rows: ["!g:courier.local": chatRow("!g:courier.local", name: "Saturday Hike", network: "whatsapp", direct: false)],
            features: ["!g:courier.local": groupFeatures]
        )
        try await h.open("!g:courier.local")
        try await waitUntil { h.conversation.features.canSetName && h.conversation.features.canSetTopic }

        var everyoneDraft = EditGroupDraft(
            roomID: "!g:courier.local",
            scope: .forEveryone,
            name: "Sunday Summit",
            topic: "Bring 2L of water",
            features: h.conversation.features
        )
        XCTAssertTrue(everyoneDraft.canEditForEveryone)
        let savedEveryone = await h.conversation.saveGroupEdit(everyoneDraft)
        XCTAssertTrue(savedEveryone)
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setName")),
            dicts([["room_id": "!g:courier.local", "text": "Sunday Summit"]])
        )
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setTopic")),
            dicts([["room_id": "!g:courier.local", "text": "Bring 2L of water"]])
        )

        let justForMeDraft = EditGroupDraft(
            roomID: "!g:courier.local",
            scope: .justForMe,
            name: "Trail Crew (Local)",
            topic: "Ignored in local override",
            avatarPath: "/tmp/local-avatar.png",
            features: h.conversation.features
        )
        let savedLocal = await h.conversation.saveGroupEdit(justForMeDraft)
        XCTAssertTrue(savedLocal)
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setLocalOverride").suffix(1)),
            dicts([["room_id": "!g:courier.local", "local_name": "Trail Crew (Local)", "local_avatar_path": "/tmp/local-avatar.png"]])
        )

        let resetLocal = await h.conversation.resetLocalOverride(roomID: "!g:courier.local")
        XCTAssertTrue(resetLocal)
        XCTAssertEqual(
            dicts(h.server.receivedParams("room.setLocalOverride").suffix(1)),
            dicts([["room_id": "!g:courier.local", "local_name": "", "local_avatar_path": ""]])
        )

        // Member & room actions and confirmations.
        let invited = await h.conversation.inviteParticipants(userIDs: ["@wa_carol:courier.local"], in: "!g:courier.local")
        XCTAssertTrue(invited)
        let inviteParams = try XCTUnwrap(h.server.receivedParams("room.invite").last)
        XCTAssertEqual(inviteParams["room_id"] as? String, "!g:courier.local")
        XCTAssertEqual(inviteParams["user_ids"] as? [String], ["@wa_carol:courier.local"])

        let promoted = await h.conversation.setParticipantAdmin(userID: "@wa_bob:courier.local", isAdmin: true, in: "!g:courier.local")
        XCTAssertTrue(promoted)
        let adminParams = try XCTUnwrap(h.server.receivedParams("room.setAdmin").last)
        XCTAssertEqual(adminParams["user_id"] as? String, "@wa_bob:courier.local")
        XCTAssertEqual(adminParams["is_admin"] as? Bool, true)

        let kicked = await h.conversation.removeParticipant(userID: "@wa_bob:courier.local", in: "!g:courier.local")
        XCTAssertTrue(kicked)
        let kickParams = try XCTUnwrap(h.server.receivedParams("room.kick").last)
        XCTAssertEqual(kickParams["user_id"] as? String, "@wa_bob:courier.local")

        XCTAssertTrue(
            ConversationModel.removeParticipantConfirmation(memberName: "Bob Example", groupName: "Saturday Hike").contains("Bob Example")
        )
        XCTAssertTrue(
            ConversationModel.leaveGroupConfirmation(groupName: "Saturday Hike").title.contains("Saturday Hike")
        )
        let deleteConfirm = ConversationModel.deleteChatConfirmation(
            chatName: "Saturday Hike",
            isDirect: false,
            features: h.conversation.features
        )
        XCTAssertTrue(deleteConfirm.title.contains("Saturday Hike"))
        XCTAssertTrue(deleteConfirm.detail.contains("This also leaves the group."))

        // -32027 network_refused shows Task 8's message, never generic "%@: %@".
        h.script.overrides["room.setName"] = .error(code: -32027, message: "bridge rejected")
        everyoneDraft.name = "Refused Name"
        let refused = await h.conversation.saveGroupEdit(everyoneDraft)
        XCTAssertFalse(refused)
        XCTAssertEqual(toasts.lines.last, "WhatsApp didn’t accept that change.")
    }

    func testReportSpamSheetDefaultsLeaveOrDeleteToFalse() async throws {
        let (h, _) = try await startWithRows(
            ["!g:courier.local": history(2, room: "!g:courier.local")],
            rows: ["!g:courier.local": chatRow("!g:courier.local", name: "Spam Group", network: "whatsapp", direct: false)]
        )
        try await h.open("!g:courier.local")

        var draft = ReportSpamDraft(roomID: "!g:courier.local", canLeave: true, canDelete: false, network: "whatsapp")
        XCTAssertFalse(draft.alsoLeaveOrDelete, "the leave/delete checkbox is unticked by default")
        XCTAssertEqual(draft.leaveOrDeleteLabel, "Also leave the group on WhatsApp")

        let confirmedUntouched = await h.conversation.reportSpam(draft)
        XCTAssertTrue(confirmedUntouched)
        let firstParams = try XCTUnwrap(h.server.receivedParams("room.reportSpam").last)
        XCTAssertEqual(firstParams["room_id"] as? String, "!g:courier.local")
        XCTAssertEqual(firstParams["leave_or_delete"] as? Bool, false)

        draft.alsoLeaveOrDelete = true
        let confirmedToggled = await h.conversation.reportSpam(draft)
        XCTAssertTrue(confirmedToggled)
        let secondParams = try XCTUnwrap(h.server.receivedParams("room.reportSpam").last)
        XCTAssertEqual(secondParams["room_id"] as? String, "!g:courier.local")
        XCTAssertEqual(secondParams["leave_or_delete"] as? Bool, true)
    }

    func testDeleteChatConfirmationUsesDeleteLeavesGroupFlag() {
        // Signal and Telegram groups have both can_leave and can_delete, and their delete does NOT leave the group.
        let signalOrTelegramGroup = ChatFeatures(
            source: .network,
            canLeave: true,
            canDelete: true,
            deleteLeavesGroup: false
        )
        let nonLeavingGroupConfirm = ConversationModel.deleteChatConfirmation(
            chatName: "Signal Crew",
            isDirect: false,
            features: signalOrTelegramGroup
        )
        XCTAssertEqual(nonLeavingGroupConfirm.title, "Delete “Signal Crew”?")
        XCTAssertFalse(
            nonLeavingGroupConfirm.detail.contains("This also leaves the group."),
            "Groups with delete_leaves_group == false must not claim delete leaves the group"
        )

        // Only when delete_leaves_group == true (WhatsApp groups) does the confirmation warn that deleting leaves the group,
        // and the app keys solely off deleteLeavesGroup rather than canLeave/canDelete.
        let whatsAppGroup = ChatFeatures(
            source: .network,
            canLeave: false,
            canDelete: true,
            deleteLeavesGroup: true
        )
        let leavingGroupConfirm = ConversationModel.deleteChatConfirmation(
            chatName: "Saturday Hike",
            isDirect: false,
            features: whatsAppGroup
        )
        XCTAssertEqual(leavingGroupConfirm.title, "Delete “Saturday Hike”?")
        XCTAssertEqual(leavingGroupConfirm.detail, "This also leaves the group.")

        let dmConfirm = ConversationModel.deleteChatConfirmation(
            chatName: "Alice Example",
            isDirect: true,
            features: ChatFeatures(source: .network, canDelete: true, deleteLeavesGroup: false)
        )
        XCTAssertEqual(dmConfirm.title, "Delete “Alice Example”?")
        XCTAssertFalse(dmConfirm.detail.contains("This also leaves the group."))
    }
}

// MARK: - Fixtures

/// A text message as the engine writes it. `at` is the minute (and the engine's seq) it arrived.
func textEvent(id: String, room: String, at n: Int64, body: String? = nil, mine: Bool = false, status: String = "sent",
          reason: String = "") -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": mine ? "@me:courier.local" : "@ann:example.test",
        "sender_name": mine ? "me" : "Ann", "sender_avatar_path": "", "mine": mine, "type": "m.room.message",
        "content": ["msgtype": "m.text", "body": body ?? "Message \(n)"], "ts": ConversationScript.timestamp(n),
        "seq": n, "status": status, "status_reason": reason, "media_path": "",
        "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
        "delivered": false, "read_by": [[String: Any]](),
    ]
}

/// What the stand-in engine keeps for each chat, and pages out newest first as room.events does.
final class ConversationScript: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String: [[String: Any]]]
    private var held: Set<String> = []
    /// Deleted for me: paged as stored, then left out of the page, as the engine does.
    private var deletedForMe: Set<String> = []
    private var _failOlder = false
    private var _failNewest = false
    private var _features: [String: [String: Any]] = [:]
    private var _rooms: [[String: Any]] = []
    private var _overrides: [String: TestEngineServer.Reply] = [:]
    private var _forwardFailures: [String: Int] = [:]
    private var _emptyOlderPages = 0
    private var _accounts: [[String: Any]] = []
    private var _directChat = "!direct"
    private var _mergedRooms: [String: [String]] = [:]
    private var _roomInfos: [String: [String: Any]] = [:]
    private var _bookmarksByRoom: [String: [[String: Any]]] = [:]
    private var _inGroupsByQuery: [String: [[String: Any]]] = [:]

    var roomInfos: [String: [String: Any]] {
        get { lock.withLock { _roomInfos } }
        set { lock.withLock { _roomInfos = newValue } }
    }

    var bookmarksByRoom: [String: [[String: Any]]] {
        get { lock.withLock { _bookmarksByRoom } }
        set { lock.withLock { _bookmarksByRoom = newValue } }
    }

    var inGroupsByQuery: [String: [[String: Any]]] {
        get { lock.withLock { _inGroupsByQuery } }
        set { lock.withLock { _inGroupsByQuery = newValue } }
    }

    var mergedRooms: [String: [String]] {
        get { lock.withLock { _mergedRooms } }
        set { lock.withLock { _mergedRooms = newValue } }
    }

    /// The next older pages answer with no events but a cursor further back, as the engine's may (a page cut to stay
    /// under 1 MiB, or messages deleted for me left out).
    var emptyOlderPages: Int {
        get { lock.withLock { _emptyOlderPages } }
        set { lock.withLock { _emptyOlderPages = newValue } }
    }

    init(events: [String: [[String: Any]]]) { self.events = events }

    /// What room.features answers for each chat; a chat not here answers `{}`, which the app can't read (so it keeps
    /// `noFeatures`).
    var features: [String: [String: Any]] {
        get { lock.withLock { _features } }
        set { lock.withLock { _features = newValue } }
    }

    /// What accounts.list answers.
    var accounts: [[String: Any]] {
        get { lock.withLock { _accounts } }
        set { lock.withLock { _accounts = newValue } }
    }

    /// The chat room.directChat answers with.
    var directChat: String {
        get { lock.withLock { _directChat } }
        set { lock.withLock { _directChat = newValue } }
    }

    /// The rows inbox.list answers a lookup by id with.
    var rooms: [[String: Any]] {
        get { lock.withLock { _rooms } }
        set { lock.withLock { _rooms = newValue } }
    }

    /// Answers that win over everything else, by method (an error, say).
    var overrides: [String: TestEngineServer.Reply] {
        get { lock.withLock { _overrides } }
        set { lock.withLock { _overrides = newValue } }
    }

    /// message.forward fails for these chats, with these codes; every other chat gets a copy.
    var forwardFailures: [String: Int] {
        get { lock.withLock { _forwardFailures } }
        set { lock.withLock { _forwardFailures = newValue } }
    }

    /// A reply that stays in its thread (m.thread, not also sent to the channel): its root; nil for anything else.
    static func threadOnlyRoot(_ event: [String: Any]) -> String? {
        guard let content = event["content"] as? [String: Any],
              let link = content["m.relates_to"] as? [String: Any], link["rel_type"] as? String == "m.thread",
              content["com.beeper.broadcast_outside_thread"] as? Bool != true else { return nil }
        return link["event_id"] as? String
    }

    /// Minute n of an October afternoon, in milliseconds.
    static func timestamp(_ n: Int64) -> Int64 { 1_760_600_000_000 + n * 60_000 }

    /// room.events with a cursor fails while set.
    var failOlder: Bool {
        get { lock.withLock { _failOlder } }
        set { lock.withLock { _failOlder = newValue } }
    }

    /// room.events for the newest page (no cursor, no around) fails while set.
    var failNewest: Bool {
        get { lock.withLock { _failNewest } }
        set { lock.withLock { _failNewest = newValue } }
    }

    func add(_ room: String, _ event: [String: Any]) { lock.withLock { events[room, default: []].append(event) } }

    func replace(_ room: String, _ event: [String: Any]) {
        lock.withLock {
            events[room, default: []].removeAll { $0["event_id"] as? String == event["event_id"] as? String }
            events[room, default: []].append(event)
        }
    }

    func deleteForMe(_ ids: [String]) { lock.withLock { deletedForMe.formUnion(ids) } }

    func remove(_ room: String, _ id: String) {
        lock.withLock { events[room, default: []].removeAll { $0["event_id"] as? String == id } }
    }

    /// room.events for this chat is not answered until the test releases it.
    func hold(_ room: String) { lock.withLock { _ = held.insert(room) } }

    func newestFirst(_ room: String, limit: Int) -> [[String: Any]] {
        let all = lock.withLock { events[room] ?? [] }
        return Array(all.sorted { Self.key($0) > Self.key($1) }.prefix(limit))
    }

    private static func key(_ event: [String: Any]) -> (Int64, Int64) {
        (event["ts"] as? Int64 ?? 0, event["seq"] as? Int64 ?? 0)
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        if method != "hello", let reply = overrides[method] { return reply }
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": accounts])
        case "room.directChat": return .result(["room_id": directChat])
        case "inbox.list":
            let ids = params?["room_ids"] as? [String] ?? []
            return .result(["rooms": rooms.filter { ids.contains($0["room_id"] as? String ?? "") },
                            "next_cursor": NSNull()])
        case "room.features":
            let room = params?["room_id"] as? String ?? ""
            return .result(features[room] ?? [String: Any]())
        case "room.info":
            let room = params?["room_id"] as? String ?? ""
            return .result(roomInfos[room] ?? [String: Any]())
        case "room.export":
            let room = params?["room_id"] as? String ?? ""
            let count = lock.withLock { events[room]?.count ?? 0 }
            return .result(["messages_written": count])
        case "search.query":
            let filters = params?["filters"] as? [String: Any]
            let roomIDs = filters?["room_ids"] as? [String] ?? []
            let hits = roomIDs.flatMap { bookmarksByRoom[$0] ?? [] }
            let queryText = params?["text"] as? String ?? ""
            let groupHits = inGroupsByQuery[queryText]
            return .result([
                "chats": NSNull(),
                "in_groups": groupHits ?? (NSNull() as Any),
                "bookmarks": ["hits": hits, "next_cursor": NSNull()] as [String: Any],
                "media": NSNull(),
                "messages": NSNull(),
                "last_archived": NSNull(),
                "complete": true,
                "hint": "",
            ])
        case "message.unsend": return .result(["event_id": "$redaction"])
        case "message.deleteForMe":
            // A store write with no change notice, as the engine's.
            deleteForMe([params?["event_id"] as? String ?? ""])
            return .result([String: Any]())
        case "message.setBookmarked":
            let id = params?["event_id"] as? String ?? ""
            lock.withLock {
                for (room, list) in events {
                    events[room] = list.map { event in
                        guard event["event_id"] as? String == id else { return event }
                        var marked = event
                        marked["bookmarked"] = params?["on"] as? Bool ?? false
                        return marked
                    }
                }
            }
            return .result([String: Any]())
        case "message.markPlayed":
            let id = params?["event_id"] as? String ?? ""
            lock.withLock {
                for (room, list) in events {
                    events[room] = list.map { event in
                        guard event["event_id"] as? String == id else { return event }
                        var marked = event
                        marked["played"] = true
                        return marked
                    }
                }
            }
            return .result([String: Any]())
        case "message.edit": return .result(["event_id": "$edit"])
        case "poll.vote": return .result(["event_id": "$vote"])
        case "poll.create": return .result(["event_id": "$poll"])
        case "message.history": return .result(["versions": [[String: Any]]()])
        case "scheduled.list": return .result(["scheduled": [[String: Any]]()])
        case "stickers.list": return .result(stickersListJSON())
        case "message.forward":
            let ids = params?["room_ids"] as? [String] ?? []
            let failing = forwardFailures
            return .result([
                "sent": ids.filter { failing[$0] == nil }.map { ["room_id": $0, "event_id": "$copy-\($0)"] },
                "failed": ids.compactMap { id in failing[id].map { ["room_id": id, "code": $0] } },
            ])
        case "room.events":
            let mergeID = params?["merge_id"] as? String
            let room = params?["room_id"] as? String ?? mergeID
            guard let room else { return .error(code: -32602, message: "room_id") }
            if lock.withLock({ held.remove(room) != nil }) { return .later }
            if let root = params?["thread"] as? String { return thread(root, in: room, params: params) }
            if params?["before"] != nil, failOlder { return .error(code: -32603, message: "internal error") }
            if params?["before"] == nil, params?["after"] == nil, params?["around"] == nil, failNewest {
                return .error(code: -32603, message: "internal error")
            }
            let limit = params?["limit"] as? Int ?? 50
            if let around = params?["around"] as? String { return self.around(around, in: room, limit: limit) }
            if let after = params?["after"] as? [String: Any],
               let ts = (after["ts"] as? NSNumber)?.int64Value, let seq = (after["seq"] as? NSNumber)?.int64Value {
                return newer(than: (ts, seq), in: room, limit: limit)
            }
            let combinedEvents: [[String: Any]] = lock.withLock {
                if let mergeID, let memberRooms = _mergedRooms[mergeID] {
                    return memberRooms.flatMap { events[$0] ?? [] }
                }
                return events[room] ?? []
            }
            var all = combinedEvents.filter { Self.threadOnlyRoot($0) == nil }
                .sorted { Self.key($0) > Self.key($1) }
            if let before = params?["before"] as? [String: Any],
               let ts = (before["ts"] as? NSNumber)?.int64Value, let seq = (before["seq"] as? NSNumber)?.int64Value {
                all = all.filter { Self.key($0) < (ts, seq) }
                let empty = lock.withLock { () -> Bool in
                    guard _emptyOlderPages > 0 else { return false }
                    _emptyOlderPages -= 1
                    return true
                }
                if empty, !all.isEmpty {
                    // A cursor a little further back that still leaves every older event to come.
                    return .result(["events": [[String: Any]](), "before": ["ts": ts, "seq": seq - 1],
                                    "after": NSNull()])
                }
            }
            let page = Array(all.prefix(limit))
            var next: Any = NSNull()
            if all.count > limit, let last = page.last { next = ["ts": Self.key(last).0, "seq": Self.key(last).1] }
            let gone = lock.withLock { deletedForMe }
            let shown = page.filter { !gone.contains($0["event_id"] as? String ?? "") }
            return .result(["events": shown, "before": next, "after": NSNull()])
        case "message.send":
            // Stored as the engine stores it: mine, a minute after the chat's newest event.
            guard let room = params?["room_id"] as? String else { return .error(code: -32602, message: "room_id") }
            lock.withLock {
                let next = (events[room] ?? []).map { Self.key($0).1 }.max().map { $0 + 1 } ?? 1
                events[room, default: []].append(textEvent(id: "$sent", room: room, at: next,
                                                            body: params?["text"] as? String, mine: true))
            }
            return .result(["event_id": "$sent"])
        case "message.sendFile", "message.react":
            return .result(["event_id": "$sent"])
        case "merge.update":
            let mergeID = params?["merge_id"] as? String ?? "merge:1"
            let name = params?["name"] as? String ?? ""
            let roomIDs = params?["room_ids"] as? [String] ?? []
            let lastRoomID = params?["last_room_id"] as? String ?? roomIDs.first ?? ""
            return .result([
                "merge_id": mergeID,
                "name": name,
                "avatar_path": "",
                "last_room_id": lastRoomID,
                "room_ids": roomIDs,
                "networks": roomIDs.map { $0.contains("sig") ? "signal" : "whatsapp" },
                "created_ts": 1_700_000_000_000,
            ])
        default:
            return .result([String: Any]())
        }
    }

    private static func cursor(_ event: [String: Any]) -> [String: Any] {
        ["ts": key(event).0, "seq": key(event).1]
    }

    /// room.events around: the event in the middle, a little more of the rest newer than older, and the other
    /// side filling the page near either end (as the engine's EventsAround does).
    private func around(_ id: String, in room: String, limit: Int) -> TestEngineServer.Reply {
        let stored = lock.withLock { events[room] ?? [] }
        guard let target = stored.first(where: { $0["event_id"] as? String == id }) else {
            return .error(code: -32020, message: "no such chat or message")
        }
        // A reply that stays in its thread centres the page on its root (Ruling 23); the main timeline leaves such
        // replies out.
        let centre = Self.threadOnlyRoot(target) ?? id
        let main = stored.filter { Self.threadOnlyRoot($0) == nil }.sorted { Self.key($0) < Self.key($1) }
        guard let index = main.firstIndex(where: { $0["event_id"] as? String == centre }) else {
            return .error(code: -32020, message: "no such chat or message")
        }
        return page(of: main, around: index, limit: limit)
    }

    private func page(of all: [[String: Any]], around index: Int, limit: Int) -> TestEngineServer.Reply {
        let rest = limit - 1
        var older = min(rest / 2, index)
        let newer = min(rest - older, all.count - 1 - index)
        older = min(rest - newer, index)
        let page = Array(all[(index - older) ... (index + newer)])
        let before: Any = index - older > 0 ? Self.cursor(page[0]) : NSNull()
        let after: Any = index + newer < all.count - 1 ? Self.cursor(page[page.count - 1]) : NSNull()
        return .result(["events": Array(page.reversed()), "before": before, "after": after])
    }

    /// room.events with thread: the thread's replies newest first, paged with before; the oldest page ends with the
    /// root.
    private func thread(_ root: String, in room: String, params: [String: Any]?) -> TestEngineServer.Reply {
        let limit = params?["limit"] as? Int ?? 50
        let stored = lock.withLock { events[room] ?? [] }
        guard let rootEvent = stored.first(where: { $0["event_id"] as? String == root }) else {
            return .error(code: -32020, message: "no such chat or message")
        }
        let replies = stored.filter { Self.threadOnlyRoot($0) == root }
        let replyIDs = Set(replies.compactMap { $0["event_id"] as? String })
        // What the chat carries for the replies (their edits, reactions and deletions) comes with them.
        let carried = stored.filter { event in
            let content = event["content"] as? [String: Any]
            let link = content?["m.relates_to"] as? [String: Any]
            let target = link?["rel_type"] as? String == "m.thread" ? nil : link?["event_id"] as? String
            return replyIDs.contains(target ?? "") || replyIDs.contains(content?["redacts"] as? String ?? "")
        }
        let gone = lock.withLock { deletedForMe }
        var all = (replies + carried + [rootEvent]).filter { !gone.contains($0["event_id"] as? String ?? "") }
            .sorted { Self.key($0) > Self.key($1) }
        if let before = params?["before"] as? [String: Any],
           let ts = (before["ts"] as? NSNumber)?.int64Value, let seq = (before["seq"] as? NSNumber)?.int64Value {
            all = all.filter { Self.key($0) < (ts, seq) }
        }
        let page = Array(all.prefix(limit))
        var next: Any = NSNull()
        if all.count > limit, let last = page.last { next = Self.cursor(last) }
        return .result(["events": page, "before": next, "after": NSNull()])
    }

    /// room.events after: the `limit` events just newer than the cursor, newest first.
    private func newer(than key: (Int64, Int64), in room: String, limit: Int) -> TestEngineServer.Reply {
        let all = lock.withLock { events[room] ?? [] }.sorted { Self.key($0) < Self.key($1) }.filter { Self.key($0) > key }
        let page = Array(all.prefix(limit))
        let before: Any = page.first.map(Self.cursor) ?? NSNull()
        let after: Any = all.count > limit ? Self.cursor(page[page.count - 1]) : NSNull()
        return .result(["events": Array(page.reversed()), "before": before, "after": after])
    }
}

extension TestEngineServer {
    /// Answers the requests for `method` about this room that the handler held.
    func releaseHeld(method: String, room: String, with result: Any) {
        for request in received where request["method"] as? String == method {
            let params = request["params"] as? [String: Any]
            if params?["room_id"] as? String == room, let id = request["id"] as? Int { reply(to: id, with: result) }
        }
    }
}
