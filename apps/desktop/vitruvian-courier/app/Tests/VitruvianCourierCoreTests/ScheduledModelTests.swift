// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The open chat's scheduled messages against a stand-in engine: the list follows the engine's `scheduled`
/// changes for that chat, and each button sends its method. All data here is made up.
@MainActor
final class ScheduledModelTests: XCTestCase {
    private var servers: [TestEngineServer] = []
    private var apps: [AppModel] = []

    override func tearDown() async throws {
        for app in apps { await app.stop() }
        apps = []
        for server in servers { server.stop() }
        servers = []
    }

    private func start() async throws -> (ScheduledScript, TestEngineServer, AppModel, ScheduledModel) {
        let script = ScheduledScript()
        let server = try TestEngineServer(handler: script.handle)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        apps.append(app)
        let model = ScheduledModel(appModel: app)
        app.start()
        try await waitUntil { app.client != nil }
        return (script, server, app, model)
    }

    private func lists(_ server: TestEngineServer) -> [[String: Any]] { server.receivedParams("scheduled.list") }

    func testListFollowsChanges() async throws {
        let (script, server, app, model) = try await start()
        script.lists["!a"] = [scheduledJSON(2, room: "!a", due: 3000), scheduledJSON(1, room: "!a", due: 2000)]
        script.lists["!b"] = [scheduledJSON(9, room: "!b", due: 1000)]

        app.selectedRoomID = "!a"
        try await waitUntil { model.scheduled.map(\.outboxID) == [1, 2] }
        XCTAssertEqual(Set(lists(server).compactMap { $0["room_id"] as? String }), ["!a"],
                       "the open chat's, soonest first")

        // A change in another chat reads nothing; one in this chat reads it again, each time.
        server.notify(["kind": "scheduled", "room_id": "!b"])
        script.lists["!a"] = [scheduledJSON(1, room: "!a", due: 2000, state: "canceled")]
        server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { model.scheduled.first?.state == .canceled }
        XCTAssertEqual(model.scheduled.count, 1)
        script.lists["!a"] = []
        server.notify(["kind": "scheduled", "room_id": "!a"])
        server.notify(["kind": "scheduled", "room_id": "!a"])
        try await waitUntil { model.scheduled.isEmpty }
        XCTAssertFalse(lists(server).contains { $0["room_id"] as? String == "!b" })

        // Another chat shows its own at once; no chat shows none.
        app.selectedRoomID = "!b"
        try await waitUntil { model.scheduled.map(\.outboxID) == [9] }
        app.selectedRoomID = nil
        XCTAssertTrue(model.scheduled.isEmpty)
    }

    /// Final fix wave: "Edit" on a scheduled message changes its words and keeps their formatting, as the composer's
    /// ranges follow its text: a bold message edited for a typo stays bold.
    @MainActor
    func testEditingTheWordsKeepsTheirFormatting() {
        let bold = TextEntity(kind: .bold, offset: 0, length: 5)
        let link = TextEntity(kind: .link, offset: 9, length: 4, url: "https://example.test")
        let message = ScheduledMessage(outboxID: 1, roomID: "!a", text: "Lnuch at noun", entities: [bold, link],
                                       dueAt: 2000, condition: .ifNoReply, state: .waiting, setAt: 1000)
        // The typo in the bold word: it stays bold, and the link after it moves with it.
        XCTAssertEqual(ScheduledModel.edited(message, to: "Lunch at noun"),
                       RichText(text: "Lunch at noun", entities: [bold, link]))
        // A word fixed inside the link: the link takes it.
        XCTAssertEqual(ScheduledModel.edited(message, to: "Lnuch at noon"),
                       RichText(text: "Lnuch at noon", entities: [bold, link]))
        // Words added at the end are plain; unchanged words keep everything.
        XCTAssertEqual(ScheduledModel.edited(message, to: "Lnuch at noun, please"),
                       RichText(text: "Lnuch at noun, please", entities: [bold, link]))
        XCTAssertEqual(ScheduledModel.edited(message, to: message.text), RichText(text: message.text,
                                                                               entities: [bold, link]))
        // The bold word deleted: its range goes, the rest follow.
        XCTAssertEqual(ScheduledModel.edited(message, to: " at noun"),
                       RichText(text: " at noun", entities: [TextEntity(kind: .link, offset: 4, length: 4,
                                                                         url: "https://example.test")]))
        // An emoji changed for another: its two UTF-16 units are one change, and the bold around it holds.
        let emoji = ScheduledMessage(outboxID: 2, roomID: "!a", text: "hi 😀 there",
                                     entities: [TextEntity(kind: .bold, offset: 0, length: 5)],
                                     dueAt: 2000, condition: .ifNoReply, state: .waiting, setAt: 1000)
        XCTAssertEqual(ScheduledModel.edited(emoji, to: "hi 😁 there"),
                       RichText(text: "hi 😁 there", entities: [TextEntity(kind: .bold, offset: 0, length: 5)]))
    }

    func testActionsSendTheirMethods() async throws {
        let (script, server, app, model) = try await start()
        script.lists["!a"] = [scheduledJSON(1, room: "!a", due: 2000)]
        app.selectedRoomID = "!a"
        try await waitUntil { model.scheduled.count == 1 }
        let toasts = ToastBox()
        model.onToast = { toasts.all.append($0) }

        await model.sendNow(1)
        XCTAssertEqual(dicts(server.receivedParams("scheduled.sendNow")), dicts([["outbox_id": 1]]))

        await model.reschedule(1, to: Date(timeIntervalSince1970: 1_800_000_000))
        await model.edit(1, text: RichText(text: "Later, then", entities: [TextEntity(kind: .bold, offset: 0, length: 5)]))
        await model.edit(1, text: RichText(text: "Plain"))
        XCTAssertEqual(dicts(server.receivedParams("scheduled.update")), dicts([
            ["outbox_id": 1, "due_at": 1_800_000_000_000],
            ["outbox_id": 1, "text": "Later, then", "entities": [["type": "bold", "offset": 0, "length": 5]]],
            ["outbox_id": 1, "text": "Plain"],
        ]))

        await model.delete(1)
        XCTAssertEqual(dicts(server.receivedParams("scheduled.delete")), dicts([["outbox_id": 1]]))
        XCTAssertTrue(toasts.all.isEmpty)

        // A refusal is a toast in Courier's words; the list is read again either way.
        script.fail = true
        let reads = lists(server).count
        await model.sendNow(1)
        XCTAssertEqual(toasts.all, ["That chat or message is no longer there."])
        try await waitUntil { self.lists(server).count > reads }
    }
}

@MainActor
final class ToastBox {
    var all: [String] = []
}

/// What the stand-in engine answers scheduled.list with, by chat; the other scheduled methods answer as the engine
/// does, or fail with not_found while `fail` is set.
final class ScheduledScript: @unchecked Sendable {
    private let lock = NSLock()
    private var _lists: [String: [[String: Any]]] = [:]
    private var _fail = false

    var lists: [String: [[String: Any]]] {
        get { lock.withLock { _lists } }
        set { lock.withLock { _lists = newValue } }
    }

    var fail: Bool {
        get { lock.withLock { _fail } }
        set { lock.withLock { _fail = newValue } }
    }

    func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
        switch method {
        case "hello": return TestEngineServer.helloOK
        case "accounts.list": return .result(["accounts": [[String: Any]]()])
        case "scheduled.list":
            let room = params?["room_id"] as? String
            let all = room.map { lists[$0] ?? [] } ?? lists.values.flatMap { $0 }
            return .result(["scheduled": all])
        case "scheduled.update":
            if fail { return .error(code: -32020, message: "no such message") }
            return .result(scheduledJSON(params?["outbox_id"] as? Int64 ?? 0, room: "!a", due: 2000))
        case "scheduled.sendNow", "scheduled.delete":
            if fail { return .error(code: -32020, message: "no such message") }
            return .result([String: Any]())
        default: return .result([String: Any]())
        }
    }
}

/// A ScheduledMessage as the engine writes it.
func scheduledJSON(_ id: Int64, room: String, due: Int64, state: String = "waiting", setAt: Int64 = 1000,
                   text: String = "Later") -> [String: Any] {
    [
        "outbox_id": id, "room_id": room, "text": text, "entities": [[String: Any]](), "reply_to": NSNull(),
        "thread_root": NSNull(), "due_at": due, "condition": "if_no_reply", "state": state, "set_at": setAt,
    ]
}
