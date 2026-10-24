// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import XCTest

@testable import CourierCore

/// The supervisor with a fake launcher: nothing here starts a process. Engines that answer are TestEngineServers
/// whose socket the fake prints in its ready line.
final class EngineSupervisorTests: XCTestCase {
    private let dataDir = URL(fileURLWithPath: "/tmp/courier-test-data")
    private var servers: [TestEngineServer] = []

    override func tearDown() {
        for server in servers { server.stop() }
        servers = []
    }

    private func makeServer(_ handler: @escaping TestEngineServer.Handler = TestEngineServer.standard) throws -> TestEngineServer {
        let server = try TestEngineServer(handler: handler)
        servers.append(server)
        return server
    }

    private func makeSupervisor(_ launcher: FakeLauncher, time: FakeTime, timing: EngineSupervisor.Timing? = nil,
                                credentials: CredentialStore = InMemoryCredentialStore(),
                                environment: [String: String] = ["HOME": "/Users/example", "PATH": "/usr/bin"]) -> EngineSupervisor {
        EngineSupervisor(enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine", dataDir: dataDir,
                         environment: environment, launcher: launcher, credentials: credentials,
                         clientName: "Courier/test", timing: timing ?? time.timing())
    }

    func testBackoffSchedule() {
        XCTAssertEqual((1 ... 8).map { EngineSupervisor.backoff(attempt: $0) }, [1, 2, 4, 8, 16, 30, 30, 30])
    }

    func testLaunchesTheEngineWithItsDataDirAndParentPipe() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }

        let spec = try XCTUnwrap(launcher.specs.first)
        XCTAssertEqual(spec.executable.path, "/Applications/Courier.app/Contents/Helpers/courier-engine")
        XCTAssertEqual(spec.arguments, ["--data", "/tmp/courier-test-data", "--parent-fd", "0"])
        XCTAssertEqual(spec.environment["HOME"], "/Users/example")
        XCTAssertEqual(recorder.states.first, .starting)
        XCTAssertEqual(server.receivedMethods().first, "hello")
        let client = supervisor.client
        XCTAssertNotNil(client)

        supervisor.stop()
        await supervisor.waitUntilStopped()
        try await waitUntil { recorder.last == .stopped }
        let process = try XCTUnwrap(launcher.processes.first)
        XCTAssertTrue(process.terminated)
        XCTAssertTrue(process.parentClosed)
        XCTAssertFalse(process.killed)
        XCTAssertNil(supervisor.client)
        XCTAssertEqual(launcher.count, 1)
    }

    func testCrashRestartsWithBackoff() async throws {
        let launcher = FakeLauncher { index, process in
            // Seven crashes in a row (a panic exits 2, which reads as a crash too); the eighth engine stays up.
            if index < 7 {
                process.printError("panic: example")
                process.exit(index == 3 ? 2 : 1)
            }
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { launcher.count == 8 }

        XCTAssertEqual(time.sleeps, [1, 2, 4, 8, 16, 30, 30])
        try await waitUntil { recorder.states.contains(.reconnecting(attempt: 7)) }
        XCTAssertEqual(Array(recorder.states.filter { $0 != .starting }.prefix(7)),
                       (1 ... 7).map { EngineSupervisor.State.reconnecting(attempt: $0) })
        XCTAssertEqual(supervisor.recentErrorOutput.suffix(1), ["panic: example"])

        supervisor.stop()
        await supervisor.waitUntilStopped()
        try await waitUntil { recorder.last == .stopped }
        XCTAssertEqual(launcher.count, 8, "nothing is started after stop")
    }

    func testBackoffResetsAfterAMinuteConnected() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { index, process in
            switch index {
            case 0: process.exit(1) // a crash before it was ever up: 1 s
            default: process.printReady(socket: server.path)
            }
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        supervisor.start()

        // Up for 61 s, then a crash: the count starts again, so 1 s.
        try await waitUntil { launcher.count == 2 && recorder.last == .connected }
        time.advance(61)
        launcher.processes[1].exit(1)
        // Up for 10 s, then a crash: the second in a row, so 2 s.
        try await waitUntil { launcher.count == 3 && recorder.last == .connected }
        time.advance(10)
        launcher.processes[2].exit(1)
        try await waitUntil { launcher.count == 4 && recorder.last == .connected }

        XCTAssertEqual(time.sleeps, [1, 1, 2])
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testReconnectRereadsState() async throws {
        let room = "!room:courier.local"
        // The first engine holds the message as pending; the one after the restart has heard back from the
        // network, so its store says sent.
        let first = try makeServer { method, _ in
            switch method {
            case "hello": return TestEngineServer.helloOK
            case "accounts.list": return .result(["accounts": [Self.account("CONNECTING")]])
            default: return .result(["events": [eventJSON(id: "$pending", room: room, status: "pending")], "before": NSNull(), "after": NSNull()])
            }
        }
        let second = try makeServer { method, _ in
            switch method {
            case "hello": return TestEngineServer.helloOK
            case "accounts.list": return .result(["accounts": [Self.account("CONNECTED")]])
            default: return .result(["events": [eventJSON(id: "$pending", room: room, status: "sent")], "before": NSNull(), "after": NSNull()])
            }
        }
        let launcher = FakeLauncher { index, process in
            process.printReady(socket: index == 0 ? first.path : second.path)
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        let model = await AppModel(supervisor: supervisor)

        let reads = Reads()
        await model.onConnect { client in
            let page: EventsPage? = try? await client.call("room.events", RoomEventsParams(roomID: room))
            reads.append(page?.events ?? [])
        }
        await model.start()
        try await waitUntil { reads.all.count == 1 }
        XCTAssertEqual(reads.all[0].map(\.status), [.pending])
        try await waitUntil { await model.accounts.first?.state == .connecting }

        // The engine dies with the message still pending.
        launcher.processes[0].exit(1)
        first.dropConnections()

        try await waitUntil { reads.all.count == 2 }
        XCTAssertEqual(reads.all[1].map(\.eventID), ["$pending"], "the message is neither lost nor duplicated")
        XCTAssertEqual(reads.all[1].map(\.status), [.sent])
        try await waitUntil { await model.accounts.first?.state == .connected }
        let state = await model.engineState
        XCTAssertEqual(state, .connected)
        XCTAssertTrue(recorder.states.contains(.reconnecting(attempt: 1)))
        XCTAssertEqual(second.receivedMethods().filter { $0 == "accounts.list" }.count, 1)

        await model.stop()
        try await waitUntil { recorder.last == .stopped }
    }

    func testResyncRereadsState() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = makeSupervisor(launcher, time: FakeTime())
        let model = await AppModel(supervisor: supervisor)
        let reads = Reads()
        await model.onConnect { _ in reads.append([]) }
        await model.start()
        try await waitUntil { reads.all.count == 1 }
        server.notify(["kind": "resync"])
        try await waitUntil { reads.all.count == 2 }
        await model.stop()
    }

    func testLockedDataDirectorySaysWhyAndKeepsTrying() async throws {
        let server = try makeServer()
        let message = "another Courier engine is using /tmp/courier-test-data"
        let launcher = FakeLauncher { index, process in
            guard index < 2 else {
                process.printReady(socket: server.path)
                return
            }
            // As the engine does: JSON warnings, then the fatal error as plain text, then exit 3.
            process.printError(#"{"level":"warn","message":"example warning"}"#)
            process.printError("courier-engine: \(message)")
            process.exit(3)
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }

        let problem = EngineSupervisor.Problem.dataDirectoryInUse(message: message)
        XCTAssertEqual(recorder.states, [
            .starting,
            .reconnecting(attempt: 1, problem: problem),
            .reconnecting(attempt: 2, problem: problem),
            .connected,
        ])
        // The other engine may go away, so the restarts went on, on the usual schedule.
        XCTAssertEqual(launcher.count, 3)
        XCTAssertEqual(time.sleeps, [1, 2])
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testEngineThatStopsBeforeReadyShowsItsReason() async throws {
        let server = try makeServer()
        let message = "the socket path /tmp/x/engine.sock is 195 bytes, and a Unix socket path can be at most 103"
        let launcher = FakeLauncher { index, process in
            guard index < 2 else {
                process.printReady(socket: server.path)
                return
            }
            // Not exit 3: any exit before the ready line, with the engine's own last line.
            process.printError(#"{"level":"warn","message":"example warning"}"#)
            process.printError("courier-engine: \(message)")
            process.exit(1)
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }

        let problem = EngineSupervisor.Problem.engineFailed(message: message)
        XCTAssertEqual(recorder.states, [
            .starting,
            .reconnecting(attempt: 1, problem: problem),
            .reconnecting(attempt: 2, problem: problem),
            .connected,
        ])
        XCTAssertEqual(time.sleeps, [1, 2], "the back-off goes on")
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testAnExitAfterReadyIsAPlainCrash() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = makeSupervisor(launcher, time: FakeTime())
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }
        launcher.processes[0].printError("courier-engine: something said on the way out")
        launcher.processes[0].exit(1)
        try await waitUntil { launcher.count == 2 && recorder.last == .connected }
        XCTAssertTrue(recorder.states.contains(.reconnecting(attempt: 1)), "no problem is named")
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testWhichExitsAreAProblem() {
        let line = "courier-engine: another Courier engine is using /tmp/x"
        XCTAssertEqual(EngineSupervisor.problem(status: 3, errors: ["{}", line]),
                       .dataDirectoryInUse(message: "another Courier engine is using /tmp/x"))
        XCTAssertEqual(EngineSupervisor.problem(status: 3, errors: []), .dataDirectoryInUse(message: nil))
        // Before ready, any exit with the engine's own line has it shown; without one, or after ready, none.
        XCTAssertEqual(EngineSupervisor.problem(status: 1, errors: [line]), .engineFailed(message: "another Courier engine is using /tmp/x"))
        XCTAssertEqual(EngineSupervisor.problem(status: 2, errors: ["{}", line]), .engineFailed(message: "another Courier engine is using /tmp/x"))
        XCTAssertNil(EngineSupervisor.problem(status: 1, errors: [line], wasConnected: true))
        XCTAssertNil(EngineSupervisor.problem(status: 2, errors: ["goroutine 1 [running]:"]))
        XCTAssertNil(EngineSupervisor.problem(status: nil, errors: []))
    }

    func testSlowReadDoesNotHoldUpStateChanges() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let supervisor = makeSupervisor(launcher, time: FakeTime())
        let model = await AppModel(supervisor: supervisor)
        let seen = await StatesSeen(model)
        let gate = Gate()
        let reads = Reads()
        await model.onConnect { _ in
            reads.append([])
            if reads.all.count == 1 { await gate.wait() } // the first read hangs
        }
        await model.start()
        try await waitUntil { reads.all.count == 1 }

        // The engine dies while the model is still reading from it: the model must hear at once.
        launcher.processes[0].exit(1)
        try await waitUntil { await seen.all.contains(.reconnecting(attempt: 1)) }
        try await waitUntil { await seen.all.last == .connected && reads.all.count == 2 }
        await gate.open()
        await model.stop()
    }

    func testHandshakeMismatchStopsWithUpdateNeeded() async throws {
        let server = try makeServer { method, _ in
            method == "hello" ? .error(code: -32001, message: "protocol mismatch", data: ["engine": 3]) : .result([:])
        }
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .updateNeeded }
        try await waitUntil { launcher.processes.first?.terminated == true }
        // An engine of another protocol will not change by being restarted.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(launcher.count, 1)
        XCTAssertEqual(time.sleeps, [])
        XCTAssertNil(supervisor.client)
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testReadyLineTimeoutRestarts() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { index, process in
            if index == 0 { process.exitsOnTerminate = true } else { process.printReady(socket: server.path) }
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time, timing: time.timing(readyTimeout: 0.2))
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }
        XCTAssertTrue(launcher.processes[0].terminated, "an engine that never said ready is stopped")
        XCTAssertEqual(time.sleeps, [1])
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testStopKillsAnEngineThatIgnoresSIGTERM() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in
            process.exitsOnTerminate = false
            process.printReady(socket: server.path)
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time, timing: time.timing(stopGrace: 0.2))
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }
        supervisor.stop()
        await supervisor.waitUntilStopped()
        let process = try XCTUnwrap(launcher.processes.first)
        XCTAssertTrue(process.terminated)
        XCTAssertTrue(process.killed)
        try await waitUntil { recorder.last == .stopped }
    }

    func testStderrKeepsTheLast500Lines() async throws {
        let launcher = FakeLauncher { index, process in
            guard index == 0 else { return }
            for line in 0 ..< 600 { process.printError("line \(line)") }
            process.exit(1)
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time)
        supervisor.start()
        try await waitUntil { launcher.count == 2 }
        try await waitUntil { supervisor.recentErrorOutput.last == "line 599" }
        let lines = supervisor.recentErrorOutput
        XCTAssertEqual(lines.count, 500)
        XCTAssertEqual(lines.first, "line 100")
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testTelegramCredentialsGoOnlyToChildEnvironment() async throws {
        let apiID = "1234567"
        let apiHash = "0123456789abcdef0123456789abcdef"
        let keychain = InMemoryCredentialStore([
            TelegramCredentials.apiIDAccount: apiID,
            TelegramCredentials.apiHashAccount: apiHash,
        ])
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in
            process.printError(#"{"level":"warn","message":"example warning"}"#)
            process.printReady(socket: server.path)
        }
        let time = FakeTime()
        let supervisor = makeSupervisor(launcher, time: time, credentials: keychain)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }

        let spec = try XCTUnwrap(launcher.specs.first)
        XCTAssertEqual(spec.environment["COURIER_TELEGRAM_API_ID"], apiID)
        XCTAssertEqual(spec.environment["COURIER_TELEGRAM_API_HASH"], apiHash)
        // In the child's environment and nowhere else: not its arguments, not anything the supervisor prints or
        // keeps, and not the app's own environment.
        for secret in [apiID, apiHash] {
            XCTAssertFalse(spec.arguments.contains { $0.contains(secret) })
            XCTAssertFalse(String(describing: spec).contains(secret))
            XCTAssertFalse(String(reflecting: spec).contains(secret))
            XCTAssertFalse(supervisor.recentErrorOutput.contains { $0.contains(secret) })
            XCTAssertFalse(ProcessInfo.processInfo.environment.values.contains(secret))
            XCTAssertFalse(String(describing: recorder.states).contains(secret))
        }
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    /// Telegram's set-up saves the credentials and restarts the engine: the next engine starts at once, with no
    /// back-off and no problem shown, and has them in its environment.
    func testRestartStartsANewEngineWithTheNewCredentials() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let time = FakeTime()
        let keychain = InMemoryCredentialStore()
        let supervisor = makeSupervisor(launcher, time: time, credentials: keychain)
        let recorder = StateRecorder(supervisor)
        supervisor.start()
        try await waitUntil { recorder.last == .connected }
        XCTAssertNil(launcher.specs.first?.environment["COURIER_TELEGRAM_API_ID"])

        let madeUpHash = String(repeating: "0a", count: 16)
        try TelegramCredentials(apiID: "1234567", apiHash: madeUpHash).save(to: keychain)
        supervisor.restart()
        try await waitUntil { launcher.count == 2 && recorder.last == .connected }

        XCTAssertTrue(launcher.processes[0].terminated, "the old engine was asked to stop")
        XCTAssertEqual(launcher.specs[1].environment["COURIER_TELEGRAM_API_ID"], "1234567")
        XCTAssertEqual(launcher.specs[1].environment["COURIER_TELEGRAM_API_HASH"], madeUpHash)
        XCTAssertEqual(time.sleeps, [], "a restart that was asked for does not back off")
        XCTAssertFalse(recorder.states.contains { if case .reconnecting = $0 { true } else { false } },
                       "nor does it read as a crash: \(recorder.states)")

        // A crash after it is an ordinary crash again, from the first step.
        launcher.processes[1].exit(1)
        try await waitUntil { launcher.count == 3 && recorder.last == .connected }
        XCTAssertEqual(time.sleeps, [1])

        // A restart during a back-off starts the engine at once.
        let slow = FakeTime()
        let crashing = FakeLauncher { index, process in
            if index == 0 { process.exit(1) } else { process.printReady(socket: server.path) }
        }
        let held = makeSupervisor(crashing, time: slow, timing: EngineSupervisor.Timing(
            readyTimeout: 10, stopGrace: 2, sleep: { _ in try await Task.sleep(nanoseconds: 60_000_000_000) }))
        let heldStates = StateRecorder(held)
        held.start()
        try await waitUntil { heldStates.last == .reconnecting(attempt: 1) }
        held.restart()
        try await waitUntil { crashing.count == 2 && heldStates.last == .connected }

        supervisor.stop()
        held.stop()
        await supervisor.waitUntilStopped()
        await held.waitUntilStopped()
    }

    func testNoTelegramCredentialsMeansNoTelegramVariables() async throws {
        let server = try makeServer()
        let launcher = FakeLauncher { _, process in process.printReady(socket: server.path) }
        let time = FakeTime()
        // Half a pair is no pair: the engine would refuse it anyway.
        let keychain = InMemoryCredentialStore([TelegramCredentials.apiIDAccount: "1234567"])
        let supervisor = makeSupervisor(launcher, time: time, credentials: keychain)
        supervisor.start()
        try await waitUntil { launcher.count == 1 }
        let spec = try XCTUnwrap(launcher.specs.first)
        XCTAssertNil(spec.environment["COURIER_TELEGRAM_API_ID"])
        XCTAssertNil(spec.environment["COURIER_TELEGRAM_API_HASH"])
        supervisor.stop()
        await supervisor.waitUntilStopped()
    }

    func testDataDirAndEnginePathOverrides() {
        let home = URL(fileURLWithPath: "/Users/example")
        XCTAssertEqual(EngineLocation.dataDirectory(environment: [:], home: home).path,
                       "/Users/example/Library/Application Support/Courier")
        XCTAssertEqual(EngineLocation.dataDirectory(environment: ["COURIER_DATA_DIR": "/tmp/c"], home: home).path, "/tmp/c")
        let bundle = URL(fileURLWithPath: "/Applications/Courier.app")
        XCTAssertEqual(EngineLocation.enginePath(environment: [:], bundleURL: bundle),
                       "/Applications/Courier.app/Contents/Helpers/courier-engine")
        XCTAssertEqual(EngineLocation.enginePath(environment: ["COURIER_ENGINE_PATH": "/tmp/e"], bundleURL: bundle), "/tmp/e")
    }

    private static func account(_ state: String) -> [String: Any] {
        ["network": "whatsapp", "display_name": "WhatsApp", "flows": ["qr"], "state": state, "error": "",
         "remote_name": "", "not_started": "", "syncs": [String](), "logins": [[String: Any]]()]
    }
}

/// Every engineState the model published, in order.
@MainActor
final class StatesSeen {
    private(set) var all: [EngineSupervisor.State] = []
    private var subscription: AnyCancellable?

    init(_ model: AppModel) {
        subscription = model.$engineState.sink { [weak self] in self?.all.append($0) }
    }
}

/// Holds a task until the test opens it.
actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// What the onConnect hook read, each time.
final class Reads: @unchecked Sendable {
    private let lock = NSLock()
    private var reads: [[Event]] = []
    func append(_ events: [Event]) { lock.withLock { reads.append(events) } }
    var all: [[Event]] { lock.withLock { reads } }
}
