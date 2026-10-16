// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Owns the courier-engine child process: starts it, waits for its ready line, says hello, and when it goes away
/// starts it again after a back-off. One engine at a time; the client of the engine that is up is `client`.
///
/// The engine is started as `courier-engine --data <dataDir> --parent-fd 0`, with the app's environment and the
/// Telegram credentials from the Keychain. Its standard input is a pipe only the app writes to, so the engine
/// stops when the app closes it, or dies.
///
/// - The ready line may take a while: the engine prints it once its networks have started. Two minutes.
/// - The last 500 lines of the engine's standard error are kept in memory, for a problem report. Never on disk.
/// - Any exit the app did not ask for is a crash, whatever its status (a Go panic exits 2, as a usage error does).
///   The wait before each restart is 1, 2, 4, 8, 16, then 30 seconds; it starts again from 1 after an engine that
///   stayed connected for a minute.
/// - An engine that exits 3 found its data directory locked by another engine: the restarts go on (the other may
///   go away), and the state says why, with the engine's own message.
/// - An engine that refuses hello as another protocol is not restarted: the app needs an update, and says so.
/// - Stopping sends SIGTERM and closes the pipe, waits ten seconds, then sends SIGKILL.
public final class EngineSupervisor: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        /// Starting the engine for the first time.
        case starting
        /// The engine is up and greeted; `client` talks to it.
        case connected
        /// The engine went away; this is the attempt to start it again. `problem` says why, when the app knows
        /// something the person can act on.
        case reconnecting(attempt: Int, problem: Problem? = nil)
        /// The engine speaks another protocol. Nothing is restarted.
        case updateNeeded
        case stopped
    }

    /// Why the engine cannot run, when the person can do something about it.
    public enum Problem: Equatable, Sendable {
        /// Another engine holds the data directory (exit 3): another copy of Courier, or the CLI, on the same
        /// folder. `message` is the engine's own line ("another Courier engine is using DIR"), nil when it said
        /// nothing the app could read.
        case dataDirectoryInUse(message: String?)
    }

    /// The engine's exit status when another engine holds its data directory.
    public static let lockedExitStatus: Int32 = 3

    /// How long a gone engine's standard error has to reach its end, so its last words are read before the app
    /// decides what its exit means.
    static let errorDrainWait: TimeInterval = 1

    /// How long things take. Tests shorten the waits and make the back-off sleep instant.
    public struct Timing: Sendable {
        /// How long the engine has to print its ready line.
        public var readyTimeout: TimeInterval
        /// How long a stopped engine has between SIGTERM and SIGKILL.
        public var stopGrace: TimeInterval
        /// How long an engine must stay connected for the back-off to start again from its first step.
        public var resetAfter: TimeInterval
        /// The back-off's wait. It must end early, by throwing, when its task is cancelled.
        public var sleep: @Sendable (TimeInterval) async throws -> Void
        /// Seconds on a clock that only goes forward.
        public var now: @Sendable () -> TimeInterval

        public init(readyTimeout: TimeInterval = 120, stopGrace: TimeInterval = 10, resetAfter: TimeInterval = 60,
                    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = EngineSupervisor.sleep,
                    now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            self.readyTimeout = readyTimeout
            self.stopGrace = stopGrace
            self.resetAfter = resetAfter
            self.sleep = sleep
            self.now = now
        }

        public static let standard = Timing()
    }

    /// How many lines of the engine's standard error are kept.
    public static let errorLineLimit = 500

    /// The wait before restart `attempt` (1 for the first): 1, 2, 4, 8, 16, then 30 seconds.
    public static func backoff(attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return min(30, pow(2, Double(min(attempt, 6) - 1)))
    }

    @Sendable public static func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    private let enginePath: String
    private let dataDir: URL
    private let baseEnvironment: [String: String]
    private let launcher: ProcessLaunching
    private let credentials: CredentialStore
    private let clientName: String
    private let timing: Timing

    private let lock = NSLock()
    private var current: State = .starting
    private var subscribers: [UUID: AsyncStream<State>.Continuation] = [:]
    private var currentClient: EngineClient?
    private var process: (any LaunchedProcess)?
    private var errorLines: [String] = []
    private var started = false
    private var looping = false
    private var stopping = false
    private var runTask: Task<Void, Never>?
    private var backoffTask: Task<Void, Error>?

    /// - Parameters:
    ///   - enginePath: the courier-engine executable.
    ///   - dataDir: the engine's data directory.
    ///   - environment: the engine's environment, before the Telegram credentials are added: the app's own.
    ///   - credentials: where the Telegram credentials are, read again at every launch.
    public init(enginePath: String, dataDir: URL, environment: [String: String], launcher: ProcessLaunching,
                credentials: CredentialStore = KeychainStore(service: TelegramCredentials.service),
                clientName: String = EngineClient.defaultClientName, timing: Timing = .standard) {
        self.enginePath = enginePath
        self.dataDir = dataDir
        self.baseEnvironment = environment
        self.launcher = launcher
        self.credentials = credentials
        self.clientName = clientName
        self.timing = timing
    }

    /// The states from now on, starting with the current one. Each access is a stream of its own.
    public var state: AsyncStream<State> {
        let (stream, continuation) = AsyncStream.makeStream(of: State.self)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.lock.withLock { self.subscribers.removeValue(forKey: id) }
        }
        lock.withLock {
            subscribers[id] = continuation
            continuation.yield(current)
        }
        return stream
    }

    public var currentState: State { lock.withLock { current } }

    /// The client of the engine that is up, while the state is `.connected`.
    public var client: EngineClient? { lock.withLock { currentClient } }

    /// The engine's last lines of standard error, oldest first. In memory only.
    public var recentErrorOutput: [String] { lock.withLock { errorLines } }

    /// Starts the engine. Once only.
    public func start() {
        lock.withLock {
            guard !started, !stopping else { return }
            started = true
            looping = true
            runTask = Task { await self.run() }
        }
    }

    /// Stops the engine and ends supervision: SIGTERM, then SIGKILL after the grace period.
    public func stop() {
        let (running, sleeper, idle) = lock.withLock { () -> ((any LaunchedProcess)?, Task<Void, Error>?, Bool) in
            stopping = true
            return (process, backoffTask, !looping)
        }
        sleeper?.cancel()
        if let running { Task { await self.end(running) } }
        if idle { publish(.stopped) }
    }

    /// Returns once supervision has ended and the engine is gone.
    public func waitUntilStopped() async {
        let task = lock.withLock { runTask }
        await task?.value
    }

    // MARK: - The loop

    private enum Outcome {
        case updateNeeded
        /// The engine is gone. `connectedAt` is when it was greeted, if it was; `status` its exit status, nil
        /// when it never started; `errors` what it wrote to standard error.
        case ended(connectedAt: TimeInterval?, status: Int32?, errors: [String])
    }

    private var isStopping: Bool { lock.withLock { stopping } }

    private func run() async {
        var attempt = 0
        loop: while !isStopping {
            let outcome = await runOnce()
            switch outcome {
            case .updateNeeded:
                publish(.updateNeeded)
                break loop
            case let .ended(connectedAt, status, errors):
                if isStopping { break loop }
                if let connectedAt, timing.now() - connectedAt >= timing.resetAfter { attempt = 0 }
                attempt += 1
                publish(.reconnecting(attempt: attempt, problem: Self.problem(status: status, errors: errors)))
                await backOff(Self.backoff(attempt: attempt))
            }
        }
        let wasStopped = lock.withLock { () -> Bool in
            looping = false
            return stopping
        }
        if wasStopped { publish(.stopped) }
    }

    private func backOff(_ seconds: TimeInterval) async {
        let sleep = timing.sleep
        let sleeper = Task { try await sleep(seconds) }
        let cancelled = lock.withLock { () -> Bool in
            if stopping { return true }
            backoffTask = sleeper
            return false
        }
        if cancelled { sleeper.cancel() }
        _ = await sleeper.result
        lock.withLock { backoffTask = nil }
    }

    /// What an exit means for the person, if anything.
    static func problem(status: Int32?, errors: [String]) -> Problem? {
        guard status == lockedExitStatus else { return nil }
        // Fatal start-up errors are plain text, "courier-engine: <message>"; warnings before them are JSON.
        let prefix = "courier-engine: "
        let message = errors.last { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        return .dataDirectoryInUse(message: message)
    }

    /// One engine, from launch to its exit.
    private func runOnce() async -> Outcome {
        let spec = LaunchSpec(executable: URL(fileURLWithPath: enginePath),
                              arguments: ["--data", dataDir.path, "--parent-fd", "0"],
                              environment: childEnvironment())
        let engine: any LaunchedProcess
        do {
            engine = try launcher.launch(spec)
        } catch {
            record("Courier could not start its engine: \(error.localizedDescription)")
            return .ended(connectedAt: nil, status: nil, errors: [])
        }
        let stopNow = lock.withLock { () -> Bool in
            process = engine
            return stopping
        }
        defer { lock.withLock { process = nil } }
        let lines = engine.standardErrorLines
        let errors = RunErrors()
        let drained = Task {
            for await line in lines {
                self.record(line)
                errors.append(line)
            }
        }
        /// After the engine is gone: its status, and its standard error once read to the end (within a bound).
        func ended(connectedAt: TimeInterval?) async -> Outcome {
            let status = await engine.waitForExit()
            _ = await Race.first(
                { await drained.value; return true },
                {
                    try? await EngineSupervisor.sleep(EngineSupervisor.errorDrainWait)
                    return false
                }
            )
            return .ended(connectedAt: connectedAt, status: status, errors: errors.lines)
        }
        if stopNow {
            await end(engine)
            return await ended(connectedAt: nil)
        }

        guard let socket = await readyLine(of: engine) else {
            await end(engine)
            return await ended(connectedAt: nil)
        }
        let client = EngineClient(socketPath: socket, client: clientName)
        do {
            try await client.connect()
        } catch EngineError.protocolMismatch {
            await end(engine)
            return .updateNeeded
        } catch {
            record("Courier could not connect to its engine: \(error.localizedDescription)")
            await end(engine)
            return await ended(connectedAt: nil)
        }
        let connectedAt = timing.now()
        let stoppedMeanwhile = lock.withLock { () -> Bool in
            if !stopping { currentClient = client }
            return stopping
        }
        if !stoppedMeanwhile { publish(.connected) }

        // Until the engine exits, or the connection ends with the engine still running: then it is stopped and
        // started again, as an engine that cannot be talked to is no use.
        let connectionEnded = await Race.first(
            { _ = await engine.waitForExit(); return false },
            { await client.waitUntilClosed(); return true }
        )
        lock.withLock { currentClient = nil }
        await client.close()
        if connectionEnded || stoppedMeanwhile { await end(engine) }
        return await ended(connectedAt: connectedAt)
    }

    private enum Ready: Sendable {
        case socket(String)
        case none
    }

    /// The socket the ready line names, or nil if the engine exits or the wait runs out first.
    private func readyLine(of engine: any LaunchedProcess) async -> String? {
        let output = engine.standardOutputLines
        let timeout = timing.readyTimeout
        let ready = await Race.first(
            {
                for await line in output {
                    if let ready = try? JSONDecoder().decode(ReadyLine.self, from: Data(line.utf8)), ready.ready {
                        return Ready.socket(ready.socket)
                    }
                }
                return Ready.none // end of file: the engine exited
            },
            {
                try? await EngineSupervisor.sleep(timeout)
                return Ready.none
            }
        )
        if case let .socket(path) = ready { return path }
        return nil
    }

    private struct ReadyLine: Decodable {
        let ready: Bool
        let socket: String
    }

    /// Asks the engine to stop, and makes it after the grace period. Returns once it has exited.
    private func end(_ engine: any LaunchedProcess) async {
        engine.terminate()
        engine.closeParentPipe()
        let grace = timing.stopGrace
        let exited = await Race.first(
            { _ = await engine.waitForExit(); return true },
            {
                try? await EngineSupervisor.sleep(grace)
                return false
            }
        )
        if !exited {
            record("Courier's engine did not stop within \(Int(grace)) seconds of SIGTERM, so it was killed.")
            engine.kill()
            _ = await engine.waitForExit()
        }
    }

    // MARK: -

    private func childEnvironment() -> [String: String] {
        var environment = baseEnvironment
        if let telegram = TelegramCredentials.load(from: credentials) {
            environment.merge(telegram.environment) { _, keychain in keychain }
        }
        return environment
    }

    private func record(_ line: String) {
        lock.withLock {
            errorLines.append(line)
            if errorLines.count > Self.errorLineLimit {
                errorLines.removeFirst(errorLines.count - Self.errorLineLimit)
            }
        }
    }

    private func publish(_ state: State) {
        lock.withLock {
            current = state
            for subscriber in subscribers.values { subscriber.yield(state) }
        }
    }
}

/// One engine's standard error, for deciding what its exit means.
private final class RunErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [String] = []

    func append(_ line: String) {
        lock.withLock {
            all.append(line)
            if all.count > EngineSupervisor.errorLineLimit { all.removeFirst() }
        }
    }

    var lines: [String] { lock.withLock { all } }
}

/// Runs operations side by side and returns the first one's answer. The others are cancelled, and an operation
/// that does not heed cancellation (waiting for an exit, say) runs on unobserved until it ends by itself.
enum Race {
    static func first<T: Sendable>(_ a: @escaping @Sendable () async -> T,
                                   _ b: @escaping @Sendable () async -> T) async -> T {
        let box = Box<T>()
        return await withCheckedContinuation { continuation in
            box.begin(continuation)
            for operation in [a, b] {
                box.add(Task { box.finish(await operation()) })
            }
        }
    }

    private final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Never>?
        private var tasks: [Task<Void, Never>] = []
        private var done = false

        func begin(_ continuation: CheckedContinuation<T, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        func add(_ task: Task<Void, Never>) {
            let late = lock.withLock { () -> Bool in
                if !done { tasks.append(task) }
                return done
            }
            if late { task.cancel() }
        }

        func finish(_ value: T) {
            let (continuation, tasks) = lock.withLock { () -> (CheckedContinuation<T, Never>?, [Task<Void, Never>]) in
                guard !done else { return (nil, []) }
                done = true
                defer {
                    self.continuation = nil
                    self.tasks = []
                }
                return (self.continuation, self.tasks)
            }
            for task in tasks { task.cancel() }
            continuation?.resume(returning: value)
        }
    }
}
