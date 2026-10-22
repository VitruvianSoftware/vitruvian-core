// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Quitting hands every held message to the engine and waits for its answer (never fire-and-forget), but no longer
/// than its bound, so a stuck engine can't keep Courier from quitting.
@MainActor
final class QuitTests: XCTestCase {
    private var servers: [TestEngineServer] = []
    private var apps: [AppModel] = []

    override func tearDown() async throws {
        for app in apps { await app.stop() }
        apps = []
        for server in servers { server.stop() }
        servers = []
    }

    private func start(_ handler: @escaping TestEngineServer.Handler) async throws -> (TestEngineServer, AppModel) {
        let server = try TestEngineServer(handler: handler)
        servers.append(server)
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        apps.append(app)
        app.start()
        try await waitUntil { app.client != nil }
        return (server, app)
    }

    func testQuitWaitsForSendHeld() async throws {
        let (server, app) = try await start { method, _ in
            method == "message.sendHeld" ? .later : TestEngineServer.standard(method, nil)
        }
        let done = Flag()
        let quitting = Task { @MainActor in
            await app.sendHeldMessages()
            done.set = true
        }
        try await waitUntil { server.receivedMethods().contains("message.sendHeld") }
        XCTAssertEqual(dicts(server.receivedParams("message.sendHeld")), dicts([[:]]), "every chat's held messages")
        XCTAssertFalse(done.set, "quitting waits for the engine's answer")
        let id = try XCTUnwrap(server.received.first { $0["method"] as? String == "message.sendHeld" }?["id"] as? Int)
        server.reply(to: id, with: [String: Any]())
        await quitting.value
        XCTAssertTrue(done.set)
        XCTAssertEqual(AppModel.sendHeldAtQuitTimeout, 5, "the bound quitting waits at most")
    }

    func testQuitDoesNotWaitPastItsBound() async throws {
        let (server, app) = try await start { method, _ in
            method == "message.sendHeld" ? .later : TestEngineServer.standard(method, nil)
        }
        // Never answered: the call gives up at its bound, and quitting goes on.
        await app.sendHeldMessages(timeout: 0.05)
        XCTAssertEqual(server.receivedMethods().filter { $0 == "message.sendHeld" }.count, 1)
    }

    func testQuitWithNoEngineDoesNothing() async {
        let launcher = FakeLauncher { _, _ in }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:], launcher: launcher,
            credentials: InMemoryCredentialStore(), clientName: "Courier/test", timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        await app.sendHeldMessages()
        XCTAssertNil(app.client)
    }
}

@MainActor
private final class Flag {
    var set = false
}
