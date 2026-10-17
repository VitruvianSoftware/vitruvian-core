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
        var rows: [String: InboxRow] = ["!a": inboxRow("!a", name: "Chat A")]
    }

    private func start(connected: Bool = true) async throws -> Harness {
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
            appModel: app, delivery: delivery, row: { window.rows[$0] }, windowIsKey: { window.isKey },
            showWindow: { window.shown += 1 }, clock: { clock.date })
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

    var events: [String: [[String: Any]]] {
        get { lock.withLock { _events } }
        set { lock.withLock { _events = newValue } }
    }

    var rooms: [[String: Any]] {
        get { lock.withLock { _rooms } }
        set { lock.withLock { _rooms = newValue } }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": [account("whatsapp", "CONNECTED")]])
        case "inbox.list": return .result(["rooms": rooms])
        case "room.events":
            let room = params?["room_id"] as? String ?? ""
            return .result(["events": events[room] ?? [], "before": NSNull()])
        case "message.send": return .result(["event_id": "$sent"])
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
