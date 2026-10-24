// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

@testable import CourierCore

/// A launcher that starts nothing: each launch makes a FakeProcess and hands it to `script`, which decides what
/// the "engine" does (print the ready line, crash, ignore SIGTERM).
final class FakeLauncher: ProcessLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var _specs: [LaunchSpec] = []
    private var _processes: [FakeProcess] = []
    private let script: @Sendable (_ index: Int, _ process: FakeProcess) -> Void

    init(script: @escaping @Sendable (_ index: Int, _ process: FakeProcess) -> Void) {
        self.script = script
    }

    var specs: [LaunchSpec] { lock.withLock { _specs } }
    var processes: [FakeProcess] { lock.withLock { _processes } }
    var count: Int { lock.withLock { _processes.count } }

    func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess {
        let process = FakeProcess()
        let index = lock.withLock { () -> Int in
            _specs.append(spec)
            _processes.append(process)
            return _processes.count - 1
        }
        script(index, process)
        return process
    }
}

final class FakeProcess: LaunchedProcess, @unchecked Sendable {
    let standardOutputLines: AsyncStream<String>
    let standardErrorLines: AsyncStream<String>
    private let output: AsyncStream<String>.Continuation
    private let errorOutput: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []
    private var _terminated = false
    private var _killed = false
    private var _parentClosed = false
    /// Whether SIGTERM ends it (exit 0), as it does the real engine.
    var exitsOnTerminate = true

    init() {
        (standardOutputLines, output) = AsyncStream.makeStream(of: String.self)
        (standardErrorLines, errorOutput) = AsyncStream.makeStream(of: String.self)
    }

    var terminated: Bool { lock.withLock { _terminated } }
    var killed: Bool { lock.withLock { _killed } }
    var parentClosed: Bool { lock.withLock { _parentClosed } }
    var exitStatus: Int32? { lock.withLock { status } }

    func printReady(socket: String) {
        output.yield(#"{"ready":true,"socket":"\#(socket)","protocol":\#(CourierProtocol.version)}"#)
    }

    func printError(_ line: String) {
        errorOutput.yield(line)
    }

    func exit(_ code: Int32) {
        let resumed = lock.withLock { () -> [CheckedContinuation<Int32, Never>]? in
            guard status == nil else { return nil }
            status = code
            defer { waiters = [] }
            return waiters
        }
        guard let resumed else { return }
        output.finish()
        errorOutput.finish()
        for waiter in resumed { waiter.resume(returning: code) }
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            let done = lock.withLock { () -> Int32? in
                if let status { return status }
                waiters.append(continuation)
                return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }

    func terminate() {
        lock.withLock { _terminated = true }
        if exitsOnTerminate { exit(0) }
    }

    func kill() {
        lock.withLock { _killed = true }
        exit(128 + 9)
    }

    func closeParentPipe() {
        lock.withLock { _parentClosed = true }
    }
}

/// The Keychain, in memory.
final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: String]

    init(_ items: [String: String] = [:]) { self.items = items }

    func read(account: String) throws -> String? { lock.withLock { items[account] } }
    func write(_ value: String, account: String) throws { lock.withLock { items[account] = value } }
    func delete(account: String) throws { _ = lock.withLock { items.removeValue(forKey: account) } }
}

/// Back-off sleeps that return at once and are written down; and a clock the test moves.
final class FakeTime: @unchecked Sendable {
    private let lock = NSLock()
    private var _sleeps: [TimeInterval] = []
    private var _now: TimeInterval = 1000

    var sleeps: [TimeInterval] { lock.withLock { _sleeps } }
    var now: TimeInterval { lock.withLock { _now } }

    /// Moves the clock on, ending every `sleep(for:)` that is due by then.
    func advance(_ seconds: TimeInterval) {
        let due = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            _now += seconds
            let now = _now
            // A microsecond of slack: at a clock of 1.7e9 s, 0.1 + 0.05 is not exactly 0.15.
            let ended = sleepers.filter { $0.deadline <= now + 1e-6 }
            sleepers.removeAll { $0.deadline <= now + 1e-6 }
            return ended.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }

    private var sleepers: [(id: UUID, seconds: TimeInterval, deadline: TimeInterval,
                            continuation: CheckedContinuation<Void, Error>)] = []
    private var cancelledSleeps: Set<UUID> = []

    /// The lengths of the sleeps waiting for the clock, in the order they began.
    var pendingSleeps: [TimeInterval] { lock.withLock { sleepers.map(\.seconds) } }

    /// A sleep on this clock: it ends when `advance` reaches it, and throws when its task is cancelled.
    func sleep(for duration: Duration) async throws {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    if cancelledSleeps.remove(id) != nil {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        sleepers.append((id, seconds, _now + seconds, continuation))
                    }
                }
            }
        } onCancel: {
            let waiting = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                    cancelledSleeps.insert(id)
                    return nil
                }
                return sleepers.remove(at: index).continuation
            }
            waiting?.resume(throwing: CancellationError())
        }
    }

    func timing(readyTimeout: TimeInterval = 10, stopGrace: TimeInterval = 2) -> EngineSupervisor.Timing {
        EngineSupervisor.Timing(
            readyTimeout: readyTimeout,
            stopGrace: stopGrace,
            sleep: { [self] seconds in
                lock.withLock { _sleeps.append(seconds) }
                try Task.checkCancellation()
                await Task.yield()
            },
            now: { [self] in now }
        )
    }
}

/// Collects a supervisor's states as they come.
final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _states: [EngineSupervisor.State] = []
    private var task: Task<Void, Never>?

    init(_ supervisor: EngineSupervisor) {
        let stream = supervisor.state
        task = Task { [weak self] in
            for await state in stream { self?.append(state) }
        }
    }

    deinit { task?.cancel() }

    private func append(_ state: EngineSupervisor.State) { lock.withLock { _states.append(state) } }

    var states: [EngineSupervisor.State] { lock.withLock { _states } }
    var last: EngineSupervisor.State? { states.last }
}

/// A room.events event as the engine writes it.
func eventJSON(id: String, room: String, status: String, body: String = "Hello") -> [String: Any] {
    [
        "event_id": id, "room_id": room, "sender": "@me:courier.local", "sender_name": "me",
        "sender_avatar_path": "", "mine": true, "type": "m.room.message",
        "content": ["msgtype": "m.text", "body": body], "ts": 1_760_600_000_000, "seq": 7,
        "status": status, "status_reason": "", "media_path": "",
        "bookmarked": false, "poll": NSNull(), "thread": NSNull(), "expires_at": 0,
        "delivered": false, "read_by": [[String: Any]](),
    ]
}
