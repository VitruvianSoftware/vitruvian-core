// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The client against a stand-in engine on a Unix socket: the handshake, the change feed, typed errors, and
/// answers matched to requests by id.
final class EngineClientTests: XCTestCase {
    private var server: TestEngineServer!

    override func setUpWithError() throws {
        server = try TestEngineServer()
    }

    override func tearDown() async throws {
        await MainActor.run {
            AppLockGate.shared.resetForTesting()
        }
        server.stop()
    }

    func testHelloSendsOnlyTheDocumentedParams() async throws {
        let client = EngineClient(socketPath: server.path, client: "Courier/9.9.9")
        let hello = try await client.connect()
        XCTAssertEqual(hello, HelloResult(protocol: CourierProtocol.version, engine: "test", networks: ["whatsapp", "signal"]))
        let request = try XCTUnwrap(server.received.first)
        XCTAssertEqual(request["method"] as? String, "hello")
        XCTAssertEqual(request["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(request["params"] as? NSDictionary, ["protocol": CourierProtocol.version, "client": "Courier/9.9.9"] as NSDictionary)
        await client.close()
    }

    func testHelloMismatchSurfacesUpdateNeeded() async throws {
        server.setHandler { method, _ in
            method == "hello" ? .error(code: -32001, message: "protocol mismatch", data: ["engine": 3]) : .result([:])
        }
        let client = EngineClient(socketPath: server.path)
        do {
            _ = try await client.connect()
            XCTFail("connect() succeeded against an engine that speaks protocol 2")
        } catch let error as EngineError {
            XCTAssertEqual(error, .protocolMismatch(engine: 3))
            XCTAssertTrue(error.isUpdateNeeded)
        }
        // Nothing else is sent to an engine that refused the handshake.
        do {
            let _: AccountsResult = try await client.call("accounts.list", Empty())
            XCTFail("a call went through after a refused handshake")
        } catch let error as EngineError {
            XCTAssertEqual(error, .notConnected)
        }
        XCTAssertEqual(server.receivedMethods(), ["hello"])
    }

    func testChangesStream() async throws {
        let client = EngineClient(socketPath: server.path)
        _ = try await client.connect()
        let changes = await client.changes
        server.notify(["kind": "room", "room_id": "!a:courier.local"])
        server.notify(["kind": "room"])
        server.notify(["kind": "event", "room_id": "!a:courier.local", "event_id": "$1"])
        server.notify(["kind": "status", "room_id": "!a:courier.local", "event_id": "$1"])
        server.notify(["kind": "read", "room_id": "!a:courier.local", "event_id": "$1"])
        server.notify(["kind": "bridge", "network": "signal"])
        server.notify(["kind": "resync"])
        // A kind this app does not know is a resync: re-reading is never wrong.
        server.notify(["kind": "something-new"])

        var seen: [Change] = []
        for await change in changes {
            seen.append(change)
            if seen.count == 8 { break }
        }
        XCTAssertEqual(seen, [
            .room(roomID: "!a:courier.local"),
            .room(roomID: nil),
            .event(roomID: "!a:courier.local", eventID: "$1"),
            .status(roomID: "!a:courier.local", eventID: "$1"),
            .read(roomID: "!a:courier.local", eventID: "$1"),
            .bridge(network: "signal"),
            .resync,
            .resync,
        ])
        await client.close()
    }

    func testUnreadableChangeIsAResync() async throws {
        let client = EngineClient(socketPath: server.path)
        _ = try await client.connect()
        let changes = await client.changes
        server.notify(["kind": 5])
        server.notify(["room_id": "!a:courier.local"])
        server.notify(["kind": "event", "room_id": "!a:courier.local", "event_id": "$1"])
        // Up to the last one sent, so a dropped notification fails the test rather than hanging it.
        var seen: [Change] = []
        for await change in changes {
            seen.append(change)
            if case .event = change { break }
        }
        XCTAssertEqual(seen, [.resync, .resync, .event(roomID: "!a:courier.local", eventID: "$1")])
        await client.close()
    }

    func testCallsTimeOutButLoginWaitDoesNot() async throws {
        server.setHandler { method, _ in method == "hello" ? TestEngineServer.helloOK : .later }
        let client = EngineClient(socketPath: server.path, callTimeout: 0.2)
        _ = try await client.connect()

        // login.wait waits for a phone, so it has no time limit.
        async let scanned: LoginStep = client.call("login.wait", LoginParams(loginID: "x"))
        let started = Date()
        do {
            let _: Empty = try await client.call("room.markRead", RoomParams(roomID: "!a"))
            XCTFail("a call the engine never answered returned")
        } catch let error as EngineError {
            XCTAssertEqual(error, .timedOut)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        // A caller can still give a call its own limit.
        do {
            let _: LoginStep = try await client.call("login.wait", LoginParams(loginID: "y"), timeout: 0.1)
            XCTFail("a call past its own limit returned")
        } catch let error as EngineError {
            XCTAssertEqual(error, .timedOut)
        }

        try await Task.sleep(nanoseconds: 300_000_000) // past the default limit
        let wait = try XCTUnwrap(server.received.first {
            ($0["params"] as? [String: Any])?["login_id"] as? String == "x"
        }?["id"] as? Int)
        server.reply(to: wait, with: ["login_id": "x", "step_id": "s", "type": "complete"])
        let step = try await scanned
        XCTAssertEqual(step.type, .complete)

        // An answer that comes after its call timed out is dropped; the connection carries on.
        let markRead = try XCTUnwrap(server.received.first { $0["method"] as? String == "room.markRead" }?["id"] as? Int)
        server.reply(to: markRead, with: [String: Any]())
        server.setHandler { _, _ in .result(["accounts": []]) }
        let accounts: AccountsResult = try await client.call("accounts.list", Empty())
        XCTAssertEqual(accounts.accounts, [])
        await client.close()
    }

    func testChangesStreamEndsWhenTheEngineGoes() async throws {
        let client = EngineClient(socketPath: server.path)
        _ = try await client.connect()
        let changes = await client.changes
        server.dropConnections()
        for await _ in changes {}
        let closed = await client.isClosed
        XCTAssertTrue(closed)
    }

    func testCallErrorsMapToTypedErrors() async throws {
        server.setHandler { method, _ in
            switch method {
            case "hello": return TestEngineServer.helloOK
            case "message.send": return .error(code: -32010, message: "this network isn't linked")
            case "room.events":
                return .error(code: -32602, message: "invalid params", data: ["reason": "limit must be 1 to 100"])
            case "room.markRead": return .error(code: -32020, message: "no such chat or message")
            default: return .error(code: -32099, message: "something new")
            }
        }
        let client = EngineClient(socketPath: server.path)

        // Before the handshake nothing is sent.
        await assertThrows(.notConnected) { let _: Empty = try await client.call("room.markRead", RoomParams(roomID: "!a")) }
        _ = try await client.connect()

        await assertThrows(.rpc(.notLinked, message: "this network isn't linked", reason: nil)) {
            let _: Sent = try await client.call("message.send", SendParams(roomID: "!a", text: "hi"))
        }
        await assertThrows(.rpc(.invalidParams, message: "invalid params", reason: "limit must be 1 to 100")) {
            let _: EventsPage = try await client.call("room.events", RoomEventsParams(roomID: "!a", limit: 500))
        }
        await assertThrows(.rpc(.notFound, message: "no such chat or message", reason: nil)) {
            let _: Empty = try await client.call("room.markRead", RoomParams(roomID: "!a"))
        }
        await assertThrows(.rpc(.other(-32099), message: "something new", reason: nil)) {
            let _: InboxResult = try await client.call("inbox.list", Empty())
        }
        // Optional params the caller left out are not on the wire (strict params refuse unknown keys, and a null
        // is not "left out").
        let send = try XCTUnwrap(server.received.first { $0["method"] as? String == "message.send" })
        XCTAssertEqual(send["params"] as? NSDictionary, ["room_id": "!a", "text": "hi"] as NSDictionary)
        await client.close()
    }

    func testAnswersAreMatchedByIDNotOrder() async throws {
        server.setHandler { method, _ in
            switch method {
            case "hello": return TestEngineServer.helloOK
            case "message.send": return .later
            default: return .result(["accounts": []])
            }
        }
        let client = EngineClient(socketPath: server.path)
        _ = try await client.connect()
        async let sent: Sent = client.call("message.send", SendParams(roomID: "!a", text: "slow"))
        // The send waits on its network; a later request is answered first.
        try await waitUntil { self.server.receivedMethods().contains("message.send") }
        let accounts: AccountsResult = try await client.call("accounts.list", Empty())
        XCTAssertEqual(accounts.accounts, [])
        let id = try XCTUnwrap(server.received.first { $0["method"] as? String == "message.send" }?["id"] as? Int)
        server.reply(to: id, with: ["event_id": "$sent"])
        let answer = try await sent
        XCTAssertEqual(answer.eventID, "$sent")
        await client.close()
    }

    func testEngineGoingFailsCallsInFlight() async throws {
        server.setHandler { method, _ in method == "hello" ? TestEngineServer.helloOK : .later }
        let client = EngineClient(socketPath: server.path)
        _ = try await client.connect()
        async let waiting: LoginStep = client.call("login.wait", LoginParams(loginID: "x"))
        try await waitUntil { self.server.receivedMethods().contains("login.wait") }
        server.dropConnections()
        do {
            _ = try await waiting
            XCTFail("a call in flight outlived the connection")
        } catch let error as EngineError {
            XCTAssertEqual(error, .disconnected)
        }
    }

    func testConnectToNothingFails() async {
        let client = EngineClient(socketPath: "/tmp/courier-test-nothing-\(UUID().uuidString.prefix(8)).sock")
        do {
            _ = try await client.connect()
            XCTFail("connected to a socket that does not exist")
        } catch {}
    }

    @MainActor
    func testEveryProtocolMethodIsClassifiedAndMutatingMethodsAreRefusedWhileLocked() async throws {
        let dir = try XCTUnwrap(ProtocolConformanceTests.protocolDirectory(), "protocol.json not found")
        let specData = try Data(contentsOf: dir.appendingPathComponent("protocol.json"))
        let spec = try XCTUnwrap(JSONSerialization.jsonObject(with: specData) as? [String: Any])
        let specMethods = try XCTUnwrap(spec["methods"] as? [String: [String: Any]])
        let allMethodNames = specMethods.keys.sorted()
        XCTAssertGreaterThanOrEqual(allMethodNames.count, 58)

        // 1. Every method in protocol.json must have an explicit classification (and no extra unknown keys).
        XCTAssertEqual(
            Set(ProtocolMethods.classifications.keys),
            Set(allMethodNames),
            "Every method in protocol.json must be classified as readOnlyOrBackground or userInitiatedMutation"
        )

        let expectedReadOnly: Set<String> = [
            "hello",
            "accounts.list",
            "inbox.list",
            "spaces.list",
            "autoArchive.list",
            "search.query",
            "room.events",
            "room.features",
            "room.members",
            "scheduled.list",
            "merge.list",
            // The app's own lock state, not the person's data: it must reach the engine while locked, or focus_app
            // couldn't say Courier is locked.
            "app.setLocked",
        ]
        // Go handlers that fetch from remote networks or write to SQLite/disk (including people.contacts, room.info,
        // stickers.list, accounts.subAccounts) must never be classified as readOnlyOrBackground.
        let goHandlersThatFetchOrWrite: Set<String> = [
            "people.contacts",
            "room.info",
            "stickers.list",
            "accounts.subAccounts",
            "message.history",
            "merge.suggest",
            "bridges.list",
            "spaces.setLayout",
            "spaces.update",
            "labels.create",
            "labels.update",
            "labels.delete",
            "room.setPinned",
            "room.setArchived",
            "room.setLowPriority",
            "room.setHidden",
            "room.setMarkedUnread",
            "room.setLabel",
            "room.setDraft",
            "room.acceptRequest",
            "reminder.set",
            "reminder.clear",
            "reminder.clearAll",
            "inbox.archiveMatching",
            "inbox.markAllRead",
            "autoArchive.set",
            "autoArchive.delete",
            "room.markRead",
            "room.setTyping",
            "room.setUnreadFrom",
            "room.directChat",
            "room.setMuted",
            "message.send",
            "message.sendFile",
            "message.sendVoice",
            "message.sendLocation",
            "message.sendSticker",
            "message.sendGIF",
            "message.markPlayed",
            "message.react",
            "message.retry",
            "message.discard",
            "room.setDisappearing",
            "message.edit",
            "message.unsend",
            "message.deleteForMe",
            "message.forward",
            "message.undo",
            "message.sendHeld",
            "message.setBookmarked",
            "message.schedule",
            "scheduled.update",
            "scheduled.sendNow",
            "scheduled.delete",
            "poll.create",
            "poll.vote",
            "login.start",
            "login.submit",
            "login.wait",
            "login.cancel",
            "room.setLocalOverride",
            "room.export",
            "room.reportSpam",
            "room.setName",
            "room.setTopic",
            "room.setAvatar",
            "room.invite",
            "room.kick",
            "room.setAdmin",
            "room.leave",
            "room.delete",
            "people.resolve",
            "room.createGroup",
            "blast.send",
            "merge.create",
            "merge.update",
            "merge.delete",
            "stickers.import",
            "bridges.restart",
            "accounts.remove",
            "accounts.setSubAccount",
            "diagnostics.export",
            "storage.usage",
            "storage.cleanup",
            "integrations.status",
            "integrations.tokens",
            "integrations.update",
            "integrations.createToken",
            "integrations.revokeToken",
            "integrations.setCanSend",
            "integrations.answerPairing",
        ]
        for method in goHandlersThatFetchOrWrite.sorted() {
            XCTAssertEqual(
                ProtocolMethods.classification(for: method),
                .userInitiatedMutation,
                "Go handler '\(method)' fetches over network or writes state and must be classified as userInitiatedMutation"
            )
        }
        let expectedMutating = Set(allMethodNames).subtracting(expectedReadOnly).sorted()

        for method in allMethodNames {
            let expected: ProtocolMethods.AccessClassification = expectedReadOnly.contains(method)
                ? .readOnlyOrBackground
                : .userInitiatedMutation
            XCTAssertEqual(
                ProtocolMethods.classification(for: method),
                expected,
                "Method '\(method)' must be classified as \(expected)"
            )
        }

        // 2. While locked, EngineClient centrally refuses every mutating method with EngineError.appLocked
        //    without sending the request over the socket.
        let suiteName = "courier.test.engineclient.lock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct AlwaysBiometric: BiometricAuthService {
            func canEvaluateBiometricsOrWatch() -> Bool { true }
            func authenticate(reason _: String) async throws -> Bool { true }
        }
        struct NoopLoginItem: LoginItemService {
            func status() -> LoginItemRegistrationStatus { .notRegistered }
            func register() throws {}
            func unregister() throws {}
        }

        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: NoopLoginItem(),
            biometrics: AlwaysBiometric()
        )
        server.setHandler { method, _ in
            method == "hello" ? TestEngineServer.helloOK : .result([:])
        }
        let client = EngineClient(socketPath: server.path)
        _ = try await client.connect()

        lifecycle.lockNow()
        XCTAssertTrue(lifecycle.isLocked)

        for method in expectedMutating {
            do {
                let _: JSONValue = try await client.call(method, Empty())
                XCTFail("Mutating method '\(method)' must be refused by EngineClient while locked")
            } catch let error as EngineError {
                XCTAssertEqual(
                    error,
                    .appLocked,
                    "Mutating method '\(method)' must throw EngineError.appLocked while locked"
                )
            }
        }

        // None of the mutating calls may have reached the engine server while locked.
        let sentMutating = server.receivedMethods().filter { !expectedReadOnly.contains($0) }
        XCTAssertEqual(
            sentMutating,
            [],
            "Zero mutating RPC requests may reach the engine socket while locked"
        )

        // Read-only background sync calls (e.g. accounts.list) still succeed while locked.
        let _: JSONValue = try await client.call("accounts.list", Empty())
        XCTAssertTrue(server.receivedMethods().contains("accounts.list"))
        await client.close()
    }

    @MainActor
    func testQuitWhileLockedFlushesHeldMessagesWhileRoomSpecificSendHeldRemainsRefused() async throws {
        var sendHeldPayloads: [[String: Any]] = []
        server.setHandler { method, params in
            if method == "hello" { return TestEngineServer.helloOK }
            if method == "message.sendHeld" {
                sendHeldPayloads.append(params ?? [:])
            }
            return .result([:])
        }

        let suiteName = "courier.test.quitlock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        struct AlwaysBiometric: BiometricAuthService {
            func canEvaluateBiometricsOrWatch() -> Bool { true }
            func authenticate(reason _: String) async throws -> Bool { true }
        }
        struct NoopLoginItem: LoginItemService {
            func status() -> LoginItemRegistrationStatus { .notRegistered }
            func register() throws {}
            func unregister() throws {}
        }

        AppLockGate.shared.resetForTesting()
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: NoopLoginItem(),
            biometrics: AlwaysBiometric()
        )
        let socket = server.path
        let launcher = FakeLauncher { _, process in process.printReady(socket: socket) }
        let supervisor = EngineSupervisor(
            enginePath: "/bin/true",
            dataDir: URL(fileURLWithPath: "/tmp"),
            environment: [:],
            launcher: launcher
        )
        let app = AppModel(supervisor: supervisor, lifecycle: lifecycle)
        let conv = ConversationModel(appModel: app)
        app.start()
        try await waitUntil { app.client != nil }
        let process: FakeProcess = try XCTUnwrap(launcher.processes.first)
        defer {
            process.exit(0)
            app.supervisor.stop()
        }

        lifecycle.lockNow()
        XCTAssertTrue(AppLockGate.shared.isLocked)

        // Room-specific 'send now' (⌘⇧Z) is a user-initiated mutation and must remain refused while locked.
        let client: EngineClient = try XCTUnwrap(app.client)
        do {
            let _: Empty = try await client.call("message.sendHeld", RoomOptionalParams(roomID: "!r1:courier.local"))
            XCTFail("Room-specific message.sendHeld must be refused while locked")
        } catch let error as EngineError {
            XCTAssertEqual(error, .appLocked)
        }
        XCTAssertTrue(sendHeldPayloads.isEmpty, "Refused room-specific sendHeld must not reach the engine")

        // Quitting while locked must still flush held messages via the room-less message.sendHeld call.
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            process.exit(0)
        }
        await app.quit(conv)
        XCTAssertEqual(sendHeldPayloads.count, 1, "Quitting while locked must send room-less message.sendHeld to the engine")
        XCTAssertNil(sendHeldPayloads.first?["room_id"], "Quit flush message.sendHeld must be room-less")
    }

    @MainActor
    func testAppLockGateSharedIsNeverRepointedByStraySystemLifecycleModelInit() throws {
        struct AlwaysBiometric: BiometricAuthService {
            func canEvaluateBiometricsOrWatch() -> Bool { true }
            func authenticate(reason _: String) async throws -> Bool { true }
        }
        struct NoopLoginItem: LoginItemService {
            func status() -> LoginItemRegistrationStatus { .notRegistered }
            func register() throws {}
            func unregister() throws {}
        }

        let primarySuite = "courier.test.lockgate.primary.\(UUID().uuidString)"
        let primaryDefaults = try XCTUnwrap(UserDefaults(suiteName: primarySuite))
        defer { primaryDefaults.removePersistentDomain(forName: primarySuite) }

        let straySuite = "courier.test.lockgate.stray.\(UUID().uuidString)"
        let strayDefaults = try XCTUnwrap(UserDefaults(suiteName: straySuite))
        defer { strayDefaults.removePersistentDomain(forName: straySuite) }

        AppLockGate.shared.resetForTesting()
        let primary = SystemLifecycleModel(
            defaults: primaryDefaults,
            loginItem: NoopLoginItem(),
            biometrics: AlwaysBiometric()
        )
        primary.lockNow()
        XCTAssertTrue(primary.isLocked)
        XCTAssertTrue(AppLockGate.shared.lifecycle === primary)
        XCTAssertTrue(AppLockGate.shared.isLocked)

        // Creating a stray unlocked SystemLifecycleModel while primary is bound must NOT re-point AppLockGate.shared.
        let stray = SystemLifecycleModel(
            defaults: strayDefaults,
            loginItem: NoopLoginItem(),
            biometrics: AlwaysBiometric()
        )
        XCTAssertFalse(stray.isLocked)
        XCTAssertTrue(
            AppLockGate.shared.lifecycle === primary,
            "AppLockGate.shared.lifecycle must remain bound to the primary SystemLifecycleModel when a stray instance is initialized"
        )
        XCTAssertTrue(
            AppLockGate.shared.isLocked,
            "AppLockGate.shared.isLocked must remain true when a stray unlocked SystemLifecycleModel is initialized"
        )
    }

    // MARK: -

    private func assertThrows(_ expected: EngineError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("did not throw \(expected)", file: file, line: line)
        } catch let error as EngineError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("threw \(error), not \(expected)", file: file, line: line)
        }
    }
}

/// Polls until the condition holds, for at most `timeout` seconds. The timeout is only a backstop for a test that
/// would otherwise hang: a passing test returns as soon as its condition holds, so it is generous enough not to fire
/// on a machine busy with other tests.
func waitUntil(timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line,
               _ condition: @escaping () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("timed out waiting", file: file, line: line)
    throw CancellationError()
}
