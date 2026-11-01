// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Settings ▸ Integrations' model against a stand-in engine: the status line, the port that saves only when it is
/// valid, Remote Access that asks first, a new connection's secret that shows once, and the pairing prompt, one at
/// a time, gone when the request ends. All data here is made up.
@MainActor
final class IntegrationsModelTests: XCTestCase {
    private var server: TestEngineServer?
    private var app: AppModel?

    override func setUp() {
        AppLockGate.shared.resetForTesting()
    }

    override func tearDown() async throws {
        await app?.stop()
        server?.stop()
        AppLockGate.shared.resetForTesting()
    }

    /// The engine's state, as the stand-in keeps it.
    private final class Engine: @unchecked Sendable {
        let lock = NSLock()
        var status: [String: Any] = ["enabled": false, "port": 23390, "remote": false, "listening": false, "error": ""]
        var tokens: [[String: Any]] = []
        var portInUse: Int?

        func handle(_ method: String, _ params: [String: Any]?) -> TestEngineServer.Reply {
            lock.withLock {
                switch method {
                case "hello": return TestEngineServer.helloOK
                case "accounts.list": return .result(["accounts": [[String: Any]]()])
                case "integrations.status": return .result(status)
                case "integrations.tokens": return .result(tokens)
                case "integrations.update":
                    for key in ["enabled", "port", "remote"] { if let value = params?[key] { status[key] = value } }
                    let enabled = status["enabled"] as? Bool ?? false
                    let port = status["port"] as? Int ?? 0
                    let blocked = enabled && portInUse == port
                    status["listening"] = enabled && !blocked
                    status["error"] = blocked ? "Port \(port) is in use by another app" : ""
                    return .result(status)
                case "integrations.createToken":
                    let token: [String: Any] = ["id": "tok_\(tokens.count + 1)", "name": params?["name"] ?? "",
                                                "canSend": params?["canSend"] ?? false, "createdMs": 1_793_500_000_000,
                                                "lastUsedMs": NSNull()]
                    tokens.append(token)
                    return .result(["token": token, "secret": "courier_madeupmadeupmadeupmadeupmadeupmadeupmad"]) // gitleaks:allow
                case "integrations.revokeToken":
                    tokens.removeAll { $0["id"] as? String == params?["id"] as? String }
                    return .result([String: Any]())
                default:
                    return .result([String: Any]())
                }
            }
        }
    }

    private func start(_ engine: Engine = Engine(), address: String? = "192.168.1.20") async throws -> IntegrationsModel {
        let server = try TestEngineServer(handler: engine.handle)
        self.server = server
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-integrations-\(UUID().uuidString)"), environment: [:],
            launcher: launcher, credentials: InMemoryCredentialStore(), clientName: "Courier/test",
            timing: FakeTime().timing())
        let app = AppModel(supervisor: supervisor)
        self.app = app
        let model = IntegrationsModel(appModel: app, enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
                                      networkAddress: { address })
        app.start()
        try await waitUntil { model.status != nil }
        return model
    }

    func testStatusLineSaysHowItIsListening() {
        XCTAssertEqual(IntegrationsModel.statusLine(for: nil), "Off")
        XCTAssertEqual(IntegrationsModel.statusLine(for: IntegrationsStatus(enabled: false, listening: false)), "Off")
        XCTAssertEqual(IntegrationsModel.statusLine(for: IntegrationsStatus(enabled: true, listening: true)),
                       "Listening on 127.0.0.1:23390")
        XCTAssertEqual(IntegrationsModel.statusLine(for: IntegrationsStatus(enabled: true, remote: true, listening: true)),
                       "Listening on all addresses, port 23390")
        XCTAssertEqual(
            IntegrationsModel.statusLine(for: IntegrationsStatus(enabled: true, listening: false,
                                                                 error: "Port 23390 is in use by another app")),
            "Port 23390 is in use by another app")
    }

    func testTurningOnAndAPortInUse() async throws {
        let engine = Engine()
        engine.portInUse = 23390
        let model = try await start(engine)
        XCTAssertEqual(model.statusLine, "Off")
        await model.setEnabled(true)
        XCTAssertEqual(model.statusLine, "Port 23390 is in use by another app")
        XCTAssertTrue(model.statusIsProblem)
        model.portText = "24000"
        await model.savePort()
        XCTAssertEqual(model.statusLine, "Listening on 127.0.0.1:24000")
        XCTAssertEqual(model.endpoint, "http://127.0.0.1:24000/v0/mcp")
        XCTAssertFalse(model.statusIsProblem)
    }

    func testInvalidPortsAreNotSaved() async throws {
        let model = try await start()
        for bad in ["80", "65536", "abc", "", "1023", "24000.5"] {
            model.portText = bad
            await model.savePort()
            XCTAssertNotNil(model.portError, bad)
        }
        let updates = server!.receivedParams("integrations.update")
        XCTAssertEqual(updates.count, 0, "nothing invalid reached the engine")
        XCTAssertEqual(IntegrationsModel.validPort("1024"), 1024)
        XCTAssertEqual(IntegrationsModel.validPort("65535"), 65535)
        model.portText = "30000"
        await model.savePort()
        XCTAssertNil(model.portError)
        XCTAssertEqual(server!.receivedParams("integrations.update").map { $0["port"] as? Int }, [30000])
    }

    func testRemoteAccessAsksFirstAndShowsTheNetworkAddress() async throws {
        let model = try await start()
        await model.setEnabled(true)
        await model.requestRemoteAccess(true)
        XCTAssertTrue(model.isConfirmingRemoteAccess)
        XCTAssertFalse(model.isRemote, "nothing changes before the confirm")
        model.cancelRemoteAccess()
        XCTAssertFalse(model.isRemote)
        await model.requestRemoteAccess(true)
        await model.confirmRemoteAccess()
        XCTAssertTrue(model.isRemote)
        XCTAssertEqual(model.statusLine, "Listening on all addresses, port 23390")
        XCTAssertEqual(model.endpoint, "http://192.168.1.20:23390/v0/mcp")
        XCTAssertEqual(model.localEndpoint, "http://127.0.0.1:23390/v0/mcp", "setup on this Mac stays on loopback")
        await model.requestRemoteAccess(false)
        XCTAssertFalse(model.isRemote, "off needs no confirm")
        XCTAssertEqual(model.endpoint, "http://127.0.0.1:23390/v0/mcp")
        XCTAssertTrue(IntegrationsModel.remoteAccessWarning.contains("Traffic is not encrypted."))
    }

    func testANewConnectionShowsItsSecretOnceAndClearsItOnDismiss() async throws {
        let model = try await start()
        model.beginNewConnection()
        XCTAssertFalse(model.canCreateConnection, "a name is needed")
        model.newConnectionName = "Example client"
        model.newConnectionCanSend = true
        await model.createConnection()
        let created = try XCTUnwrap(model.createdConnection)
        XCTAssertTrue(created.secret.hasPrefix("courier_"))
        XCTAssertEqual(model.tokens.map(\.name), ["Example client"])
        XCTAssertEqual(server!.receivedParams("integrations.createToken").first?["canSend"] as? Bool, true)

        let http = model.claudeHTTPCommand(secret: created.secret)
        XCTAssertEqual(http, "claude mcp add --transport http courier http://127.0.0.1:23390/v0/mcp --header \"Authorization: Bearer \(created.secret)\"")
        XCTAssertEqual(model.claudeStdioCommand(secret: created.secret),
                       "claude mcp add courier -e COURIER_TOKEN=\(created.secret) -- /Applications/Courier.app/Contents/Helpers/courier-engine mcp-stdio")
        XCTAssertEqual(model.cursorLink(secret: created.secret)?.scheme, "cursor")
        let vscode = try XCTUnwrap(model.vsCodeLink(secret: created.secret))
        XCTAssertTrue(vscode.absoluteString.hasPrefix("vscode:mcp/install?"))
        let json = try XCTUnwrap(vscode.absoluteString.dropFirst("vscode:mcp/install?".count).removingPercentEncoding)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(config["url"] as? String, "http://127.0.0.1:23390/v0/mcp")
        XCTAssertEqual(config["type"] as? String, "http")

        model.dismissNewConnection()
        XCTAssertNil(model.createdConnection, "the secret goes with the sheet")
        XCTAssertFalse(model.isPresentingNewConnection)
        model.beginNewConnection()
        XCTAssertNil(model.createdConnection, "and doesn't come back")
    }

    func testRevokeAsksThenRemoves() async throws {
        let model = try await start()
        model.beginNewConnection()
        model.newConnectionName = "Example client"
        await model.createConnection()
        model.dismissNewConnection()
        let token = try XCTUnwrap(model.tokens.first)
        model.tokenPendingRevoke = token
        await model.confirmRevoke()
        XCTAssertEqual(server!.receivedParams("integrations.revokeToken").map { $0["id"] as? String }, [token.id])
        XCTAssertEqual(model.tokens, [])
    }

    func testPairingShowsOneAtATimeAndEndsWithTheRequest() async throws {
        let model = try await start()
        server!.notify(method: "integrations.pairRequest", params: ["requestID": "pair_1", "clientName": "Example app"])
        try await waitUntil { model.pairRequest != nil }
        XCTAssertEqual(IntegrationsModel.pairingQuestion(model.pairRequest!),
                       "“Example app” wants to read your chats in Courier.")

        // A second request while the first shows replaces nothing.
        model.receive(.pairRequest(PairRequest(requestID: "pair_2", clientName: "Other app")))
        XCTAssertEqual(model.pairRequest?.requestID, "pair_1")
        // Another request's end leaves this one.
        model.receive(.pairEnded(PairEnded(requestID: "pair_2")))
        XCTAssertEqual(model.pairRequest?.requestID, "pair_1")
        // Its own end (it timed out, the client left, or it was answered elsewhere) takes it away.
        server!.notify(method: "integrations.pairEnded", params: ["requestID": "pair_1"])
        try await waitUntil { model.pairRequest == nil }
        XCTAssertEqual(server!.receivedParams("integrations.answerPairing").count, 0, "nothing was answered")

        model.receive(.pairRequest(PairRequest(requestID: "pair_3", clientName: "Example app")))
        await model.answerPairing(.allowAndSend)
        XCTAssertNil(model.pairRequest)
        let answer = try XCTUnwrap(server!.receivedParams("integrations.answerPairing").first)
        XCTAssertEqual(answer["requestID"] as? String, "pair_3")
        XCTAssertEqual(answer["allow"] as? Bool, true)
        XCTAssertEqual(answer["canSend"] as? Bool, true)

        model.receive(.pairRequest(PairRequest(requestID: "pair_4", clientName: "Example app")))
        await model.answerPairing(.deny)
        let denied = try XCTUnwrap(server!.receivedParams("integrations.answerPairing").last)
        XCTAssertEqual(denied["allow"] as? Bool, false)
        XCTAssertNil(denied["canSend"])
    }
}
