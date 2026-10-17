// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The notification coordinator against a stand-in engine and a fake notification centre: live events notify once,
/// backfill and the chat in front do not, and the buttons on a notification reach the engine.
@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    private var servers: [TestEngineServer] = []

    override func tearDown() async throws {
        for server in servers { server.stop() }
        servers = []
    }

    /// The moment the app connects, in ms.
    private let connectedMillis: Int64 = 2_000_000

    private struct Harness {
        let script: NotificationScript
        let server: TestEngineServer
        let app: AppModel
        let delivery: FakeDelivery
        let coordinator: NotificationCoordinator
        let clock: FakeClock
        let window: WindowState
    }

    /// Mutable things the coordinator asks about, which the app's views own.
    @MainActor
    final class WindowState {
        var isKey = false
        var shown = 0
        var drafts: [(room: String, text: String, mayHaveBeenSent: Bool)] = []
        var rows: [String: InboxRow] = ["!a": inboxRow("!a", name: "Chat A")]
    }

    private func start(connected: Bool = true, window gather: TimeInterval = 0.02,
                       replyTimeout: TimeInterval? = nil) async throws -> Harness {
        let script = NotificationScript()
        let server = try TestEngineServer(handler: script.handle)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let clock = FakeClock(millis: connectedMillis)
        let app = AppModel(supervisor: supervisor, clock: { clock.date })
        let delivery = FakeDelivery()
        let window = WindowState()
        let coordinator = NotificationCoordinator(
            appModel: app, delivery: delivery, row: { window.rows[$0] }, isLooking: { window.isKey },
            restoreDraft: { window.drafts.append(($0, $1, $2)) }, showWindow: { window.shown += 1 },
            window: gather, replyTimeout: replyTimeout, clock: { clock.date })
        if connected {
            app.start()
            try await waitUntil { app.client != nil }
        }
        return Harness(script: script, server: server, app: app, delivery: delivery, coordinator: coordinator,
                       clock: clock, window: window)
    }

    private func finish(_ h: Harness) async { await h.app.stop() }

    /// Lets a fetch that should lead to nothing finish before the test says nothing happened.
    private func settle(_ h: Harness, fetches: Int = 1) async throws {
        try await waitUntil { h.server.receivedMethods().filter { $0 == "room.events" }.count >= fetches }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Live events

    func testALiveEventNotifiesOnce() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 3000, text: "hello")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body, "hello")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a")

        // The same event again (a status change, a second notification) does not notify again.
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h, fetches: 2)
        XCTAssertEqual(h.delivery.delivered.count, 1)

        let fetch = h.server.receivedParams("room.events").first
        XCTAssertEqual(fetch?["room_id"] as? String, "!a")
        XCTAssertEqual(fetch?["limit"] as? Int, 10)
        await finish(h)
    }

    func testBackfilledEventsDoNotNotify() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        // The first sync's history: older than the connection, in a burst of changes.
        h.script.events["!a"] = (1 ... 10).map { message("$old\($0)", ts: connectedMillis - Int64($0) * 60_000, text: "old") }
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$old1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    func testEachNewEventInAPageNotifiesOldestFirst() async throws {
        let h = try await start()
        h.clock.advance(seconds: 10)
        // room.events is newest first.
        h.script.events["!a"] = [
            message("$3", ts: connectedMillis + 3000, text: "third"),
            message("$2", ts: connectedMillis + 2000, text: "second"),
            message("$1", ts: connectedMillis + 1000, text: "first"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await waitUntil { h.delivery.delivered.count == 3 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["first", "second", "third"])
        await finish(h)
    }

    func testYourOwnMessagesAndMutedChatsAreSilent() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "mine", mine: true)]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        h.window.rows["!a"] = inboxRow("!a", name: "Chat A", muted: true)
        h.script.events["!a"] = [message("$2", ts: connectedMillis + 2000, text: "theirs")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await settle(h, fetches: 2)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    func testTheChatInFrontIsSilentAndStaysSilentLater() async throws {
        let h = try await start()
        h.window.rows["!b"] = inboxRow("!b", name: "Chat B")
        h.clock.advance(seconds: 5)
        h.app.selectedRoomID = "!a"
        h.window.isKey = true
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "you are looking at me")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)

        // Another chat does notify while the window is key.
        h.script.events["!b"] = [message("$b1", ts: connectedMillis + 2000, text: "elsewhere", room: "!b")]
        h.server.notify(["kind": "event", "room_id": "!b", "event_id": "$b1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat B")

        // The person looks away; the next event in the first chat brings only itself, not the one already seen.
        h.window.isKey = false
        h.script.events["!a"] = [
            message("$2", ts: connectedMillis + 3000, text: "now"),
            message("$1", ts: connectedMillis + 1000, text: "you are looking at me"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["elsewhere", "now"])
        await finish(h)
    }

    func testAChatTheInboxHasNotListedYetIsLookedUp() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        h.script.rooms = [inboxRowJSON("!new", name: "New Chat")]
        h.script.events["!new"] = [message("$1", ts: connectedMillis + 1000, text: "first words", room: "!new")]
        h.server.notify(["kind": "event", "room_id": "!new", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        XCTAssertEqual(h.delivery.delivered[0].title, "New Chat")
        await finish(h)
    }

    func testNothingNotifiesBeforeTheAppHasConnected() async throws {
        let h = try await start(connected: false)
        // No engine yet, so no client and no connection time: nothing to read from.
        h.coordinator.handle(.event(roomID: "!a", eventID: "$1"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    // MARK: - Reading a chat clears its notifications

    func testReadingAChatClearsItsNotifications() async throws {
        let h = try await start()
        h.server.notify(["kind": "read", "room_id": "!a"])
        try await waitUntil { h.delivery.cleared == ["!a"] }
        await finish(h)
    }

    // MARK: - The buttons

    func testClickingOpensTheChatAndTheWindow() async throws {
        let h = try await start()
        h.coordinator.open(roomID: "!a")
        XCTAssertEqual(h.app.selectedRoomID, "!a")
        XCTAssertEqual(h.window.shown, 1)
        await finish(h)
    }

    func testMarkAsReadTellsTheEngineAndClears() async throws {
        let h = try await start()
        await h.coordinator.markRead(roomID: "!a")
        XCTAssertEqual(h.server.receivedParams("room.markRead").first?["room_id"] as? String, "!a")
        XCTAssertEqual(h.delivery.cleared, ["!a"])
        await finish(h)
    }

    func testReplySendsTheTypedText() async throws {
        let h = try await start()
        await h.coordinator.reply(roomID: "!a", text: "  on my way  ")
        let sent = h.server.receivedParams("message.send")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["room_id"] as? String, "!a")
        XCTAssertEqual(sent.first?["text"] as? String, "on my way")

        await h.coordinator.reply(roomID: "!a", text: "   ")
        XCTAssertEqual(h.server.receivedParams("message.send").count, 1, "an empty reply sends nothing")
        await finish(h)
    }

    func testAReplyWithNoEngineWaitsInTheChat() async throws {
        let h = try await start(connected: false)
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.window.drafts.map(\.room), ["!a"])
        XCTAssertEqual(h.window.drafts.map(\.text), ["on my way"])
        XCTAssertEqual(h.window.drafts.map(\.mayHaveBeenSent), [false])
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body, "Your reply wasn’t sent — it’s waiting in the chat.")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a", "a click opens that chat")
        XCTAssertEqual(h.delivery.delivered[0].threadIdentifier, "!a")
    }

    func testAReplyTheEngineRefusesWaitsInTheChat() async throws {
        let h = try await start()
        h.script.failSend = true
        await h.coordinator.reply(roomID: "!a", text: "  on my way ")
        XCTAssertEqual(h.window.drafts.map(\.text), ["on my way"])
        XCTAssertEqual(h.window.drafts.map(\.mayHaveBeenSent), [false])
        XCTAssertEqual(h.delivery.delivered.map(\.roomID), ["!a"])
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["Your reply wasn’t sent — it’s waiting in the chat."])
        await finish(h)
    }

    func testAReplyThatTimedOutSaysItMayHaveGone() async throws {
        let h = try await start(replyTimeout: 0.2)
        h.script.hold("message.send") // the engine never answers
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertEqual(h.window.drafts.map(\.text), ["on my way"])
        XCTAssertEqual(h.window.drafts.map(\.mayHaveBeenSent), [true], "the draft carries the may-have-been-sent notice")
        XCTAssertEqual(h.delivery.delivered.count, 1)
        XCTAssertEqual(h.delivery.delivered[0].title, "Chat A")
        XCTAssertEqual(h.delivery.delivered[0].body,
                       "Your reply may not have been sent — check the chat before sending again.")
        XCTAssertEqual(h.delivery.delivered[0].roomID, "!a", "a click opens that chat")
        XCTAssertEqual(h.delivery.delivered[0].threadIdentifier, "!a")
        await finish(h)
    }

    func testAReplyThatWasSentLeavesNothingBehind() async throws {
        let h = try await start()
        await h.coordinator.reply(roomID: "!a", text: "on my way")
        XCTAssertTrue(h.window.drafts.isEmpty)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    // MARK: - A burst of changes

    func testABurstOfEventsInOneChatReadsItAtMostTwice() async throws {
        let h = try await start(window: 0.3)
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = (1 ... 50).reversed().map {
            message("$\($0)", ts: connectedMillis + Int64($0), text: "m\($0)")
        }
        for number in 1 ... 50 { h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$\(number)"]) }
        // Ten come back for each read; the burst's last ten are announced.
        try await waitUntil { h.delivery.delivered.count >= 10 }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertLessThanOrEqual(h.server.receivedMethods().filter { $0 == "room.events" }.count, 2)
        await finish(h)
    }

    func testABurstForAChatTheInboxHasNotListedReadsTheInboxAtMostTwice() async throws {
        let h = try await start(window: 0.3)
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        h.script.rooms = [inboxRowJSON("!new", name: "New Chat")]
        h.script.events["!new"] = [message("$1", ts: connectedMillis + 1000, text: "hi", room: "!new")]
        for number in 1 ... 50 { h.server.notify(["kind": "event", "room_id": "!new", "event_id": "$\(number)"]) }
        try await waitUntil { h.delivery.delivered.count == 1 }
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertLessThanOrEqual(h.server.receivedMethods().filter { $0 == "inbox.list" }.count, 2)
        await finish(h)
    }

    func testSeveralUnlistedChatsShareOneInboxRead() async throws {
        let h = try await start(window: 0.1)
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        let ids = (1 ... 5).map { "!n\($0)" }
        h.script.rooms = ids.map { inboxRowJSON($0, name: "Chat \($0)") }
        for id in ids {
            h.script.events[id] = [message("$\(id)", ts: connectedMillis + 1000, text: "hi", room: id)]
            h.server.notify(["kind": "event", "room_id": id, "event_id": "$\(id)"])
        }
        try await waitUntil { h.delivery.delivered.count == 5 }
        XCTAssertLessThanOrEqual(h.server.receivedMethods().filter { $0 == "inbox.list" }.count, 2)
        await finish(h)
    }

    func testARoomMissingFromAnInboxReadThatStartedTooEarlyGetsAFreshRead() async throws {
        let h = try await start(window: 0.02)
        h.clock.advance(seconds: 5)
        h.window.rows = [:]
        h.script.hold("inbox.list") // the first inbox read is slow
        h.script.events["!x"] = [message("$x", ts: connectedMillis + 1000, text: "from x", room: "!x")]
        h.server.notify(["kind": "event", "room_id": "!x", "event_id": "$x"])
        try await waitUntil { h.server.receivedMethods().contains("inbox.list") }

        // !y appears while that read is on its way, and its read joins it.
        h.script.rooms = [inboxRowJSON("!x", name: "Chat X"), inboxRowJSON("!y", name: "Chat Y")]
        h.script.events["!y"] = [message("$y", ts: connectedMillis + 2000, text: "from y", room: "!y")]
        h.server.notify(["kind": "event", "room_id": "!y", "event_id": "$y"])
        try await waitUntil { h.server.receivedParams("room.events").contains { $0["room_id"] as? String == "!y" } }
        try await Task.sleep(nanoseconds: 100_000_000)

        // The slow read answers from before !y existed.
        let held = h.server.received.first { $0["method"] as? String == "inbox.list" }
        h.server.reply(to: held?["id"] as? Int ?? -1, with: ["rooms": [inboxRowJSON("!x", name: "Chat X")]])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(Set(h.delivery.delivered.map(\.title)), ["Chat X", "Chat Y"])
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "inbox.list" }.count, 2, "one stale, one fresh")
        await finish(h)
    }

    func testAChangeWhileTheChatIsBeingReadMakesExactlyOneFollowUpRead() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.hold("room.events")
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "one")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.server.receivedMethods().contains("room.events") }

        // Two more changes while that read is in flight.
        h.script.events["!a"] = [
            message("$3", ts: connectedMillis + 3000, text: "three"), message("$2", ts: connectedMillis + 2000, text: "two"),
            message("$1", ts: connectedMillis + 1000, text: "one"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$3"])
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "room.events" }.count, 1, "nothing new is read while it is in flight")

        // The held read answers with what the engine had when it was asked.
        let held = h.server.received.first { $0["method"] as? String == "room.events" }
        h.server.reply(to: held?["id"] as? Int ?? -1, with: [
            "events": [message("$1", ts: connectedMillis + 1000, text: "one")], "before": NSNull(),
        ])
        try await waitUntil { h.delivery.delivered.count == 3 }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(h.server.receivedMethods().filter { $0 == "room.events" }.count, 2, "exactly one follow-up read")
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["one", "two", "three"], "each announced once")
        await finish(h)
    }

    func testAChangeDuringAReadIsReadOnceMoreAndNotAnnouncedTwice() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        h.script.events["!a"] = [message("$1", ts: connectedMillis + 1000, text: "one")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$1"])
        try await waitUntil { h.delivery.delivered.count == 1 }
        h.script.events["!a"] = [
            message("$2", ts: connectedMillis + 2000, text: "two"), message("$1", ts: connectedMillis + 1000, text: "one"),
        ]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$2"])
        try await waitUntil { h.delivery.delivered.count == 2 }
        XCTAssertEqual(h.delivery.delivered.map(\.body), ["one", "two"])
        await finish(h)
    }

    // MARK: - Deleted before it was seen

    func testAMessageDeletedBeforeItWasAnnouncedIsSilent() async throws {
        let h = try await start()
        h.clock.advance(seconds: 5)
        let redaction: [String: Any] = [
            "event_id": "$r", "room_id": "!a", "sender": "@other:courier.local", "sender_name": "Sam",
            "sender_avatar_path": "", "mine": false, "type": "m.room.redaction", "content": ["redacts": "$1"],
            "ts": connectedMillis + 2000, "seq": 2, "status": "sent", "status_reason": "", "media_path": "",
        ]
        h.script.events["!a"] = [redaction, message("$1", ts: connectedMillis + 1000, text: "oops")]
        h.server.notify(["kind": "event", "room_id": "!a", "event_id": "$r"])
        try await settle(h)
        XCTAssertTrue(h.delivery.delivered.isEmpty)
        await finish(h)
    }

    func testTheConnectionTimeIsWhenTheEngineWasGreeted() async throws {
        let h = try await start()
        XCTAssertEqual(h.app.connectedAt, h.clock.date)
        await finish(h)
    }
}

// MARK: - Fixtures

@MainActor
final class FakeDelivery: NotificationDelivering {
    private(set) var delivered: [NotificationContent] = []
    private(set) var cleared: [String] = []
    private(set) var permissionRequests = 0

    func requestPermission() { permissionRequests += 1 }
    func deliver(_ content: NotificationContent) { delivered.append(content) }
    func clear(roomID: String) { cleared.append(roomID) }
}

final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var millis: Int64

    init(millis: Int64) { self.millis = millis }

    var date: Date { lock.withLock { Date(timeIntervalSince1970: Double(millis) / 1000) } }

    func advance(seconds: Double) { lock.withLock { millis += Int64(seconds * 1000) } }
}

/// What the stand-in engine answers for the notification tests.
final class NotificationScript: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String: [[String: Any]]] = [:]
    private var _rooms: [[String: Any]] = []
    private var _failSend = false
    private var _held: Set<String> = []

    var events: [String: [[String: Any]]] {
        get { lock.withLock { _events } }
        set { lock.withLock { _events = newValue } }
    }

    var rooms: [[String: Any]] {
        get { lock.withLock { _rooms } }
        set { lock.withLock { _rooms = newValue } }
    }

    /// The next call of `method` is not answered until the test answers it (or never).
    func hold(_ method: String) { lock.withLock { _ = _held.insert(method) } }

    private func takeHold(_ method: String) -> Bool { lock.withLock { _held.remove(method) != nil } }

    /// message.send is refused.
    var failSend: Bool {
        get { lock.withLock { _failSend } }
        set { lock.withLock { _failSend = newValue } }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        if method != "hello", takeHold(method) { return .later }
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": [account("whatsapp", "CONNECTED")]])
        case "inbox.list": return .result(["rooms": rooms])
        case "room.events":
            let room = params?["room_id"] as? String ?? ""
            return .result(["events": events[room] ?? [], "before": NSNull()])
        case "message.send":
            return failSend ? .error(code: -32000, message: "example failure") : .result(["event_id": "$sent"])
        default: return .result([String: Any]())
        }
    }
}

/// An event as the engine writes it.
func message(_ id: String, ts: Int64, text: String, mine: Bool = false, room: String = "!a") -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": mine ? Timeline.meUserID : "@other:courier.local",
        "sender_name": "Sam", "sender_avatar_path": "", "mine": mine, "type": "m.room.message",
        "content": ["msgtype": "m.text", "body": text], "ts": ts, "seq": 1, "status": "sent", "status_reason": "",
        "media_path": "",
    ]
}

func inboxRow(_ id: String, name: String, direct: Bool = true, muted: Bool = false) -> InboxRow {
    InboxRow(roomID: id, network: "whatsapp", name: name, avatarPath: "", isDirect: direct, lastTS: 0, preview: "",
             previewKind: .text, previewMine: false, unread: 0, muted: muted)
}

func inboxRowJSON(_ id: String, name: String) -> [String: Any] {
    room(id, ts: 1, name: name)
}
