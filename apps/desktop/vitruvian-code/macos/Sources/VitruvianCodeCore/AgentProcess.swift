// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import Darwin
import Foundation
import os

/// The write end of an agent's standard input. Writes and the close may come
/// from different threads (the session's, and the reader's at exit), so both
/// take a lock; a write after the close is dropped. A write to an agent that
/// has already gone fails with EPIPE rather than raising SIGPIPE, which would
/// end the app.
final class AgentInput: Sendable {
    private let handleLock: OSAllocatedUnfairLock<FileHandle?>

    init(_ handle: FileHandle) {
        _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.handleLock = OSAllocatedUnfairLock(initialState: handle)
    }

    func write(_ data: Data) {
        handleLock.withLock { handle in
            try? handle?.write(contentsOf: data)
        }
    }

    func writeThrowing(_ data: Data) throws {
        try handleLock.withLock { handle in
            guard let handle else {
                throw POSIXError(.EPIPE)
            }
            try handle.write(contentsOf: data)
        }
    }

    func close() {
        handleLock.withLock { handle in
            try? handle?.close()
            handle = nil
        }
    }
}

/// Parameters for launching an agent or terminal subprocess in its own process group.
public struct AgentProcessLaunchSpec: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: String?

    public init(
        executable: String,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// How an `AgentProcess` ended.
public struct AgentProcessExit: Equatable, Sendable {
    public let exitCode: Int32?
    public let signal: Int32?

    public init(exitCode: Int32?, signal: Int32? = nil) {
        self.exitCode = exitCode
        self.signal = signal
    }

    /// Shell-style exit status (`0` on clean exit, `128 + signal` when ended by a signal).
    public var terminationStatus: Int32 {
        if let exitCode { return exitCode }
        if let signal { return 128 + signal }
        return -1
    }

    public var signalName: String? {
        guard let signal else { return nil }
        switch signal {
        case SIGHUP: return "SIGHUP"
        case SIGINT: return "SIGINT"
        case SIGQUIT: return "SIGQUIT"
        case SIGILL: return "SIGILL"
        case SIGABRT: return "SIGABRT"
        case SIGKILL: return "SIGKILL"
        case SIGSEGV: return "SIGSEGV"
        case SIGPIPE: return "SIGPIPE"
        case SIGALRM: return "SIGALRM"
        case SIGTERM: return "SIGTERM"
        default: return "SIG\(signal)"
        }
    }
}

/// Errors thrown while starting or waiting on an `AgentProcess`.
public enum AgentProcessError: Error, Equatable, Sendable, LocalizedError {
    case pipeFailed(Int32)
    case spawnSetupFailed(Int32)
    case spawnFailed(executable: String, errno: Int32)
    case waitTimedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .pipeFailed(let code):
            return "Failed to create process pipe (\(String(cString: strerror(code))))."
        case .spawnSetupFailed(let code):
            return "Failed to configure posix_spawn (\(String(cString: strerror(code))))."
        case .spawnFailed(let executable, let code):
            return "Failed to launch \(executable): \(String(cString: strerror(code)))."
        case .waitTimedOut(let seconds):
            return "Timed out after \(seconds)s waiting for child process to exit."
        }
    }
}

/// A child process launched in its own process group (`POSIX_SPAWN_SETPGROUP`, pgroup 0)
/// with piped standard input, standard output and standard error read off the main actor.
public final class AgentProcess: Sendable {
    public typealias SignalSender = @Sendable (pid_t, Int32) -> Int32

    /// Matches T3 Code's `processGroupTerminationGrace ?? "1 second"` (`AcpSessionRuntime.ts:1611`).
    public static let defaultTerminationGrace: TimeInterval = 1.0
    /// Default bounded wait for `waitForExit(timeout:)`.
    public static let defaultWaitTimeout: TimeInterval = 10.0
    /// Bounded wait after sending `SIGKILL` during `terminate(grace:)`.
    public static let defaultPostKillWaitTimeout: TimeInterval = 0.5

    public let pid: pid_t
    public var processGroupID: pid_t { pid }
    public let stdout: AsyncStream<Data>
    public let stderr: AsyncStream<Data>

    private let input: AgentInput
    private let exitState = ExitState()
    private let signalProcessGroup: SignalSender

    public init(
        _ spec: AgentProcessLaunchSpec,
        signalProcessGroup: @escaping SignalSender = { Darwin.kill(-$0, $1) },
        onExit: (@Sendable (AgentProcessExit) -> Void)? = nil
    ) throws {
        self.signalProcessGroup = signalProcessGroup
        var stdinPipe: [Int32] = [-1, -1]
        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]

        func closeIfOpen(_ fd: inout Int32) {
            if fd >= 0 {
                _ = Darwin.close(fd)
                fd = -1
            }
        }

        func closeAllPipes() {
            closeIfOpen(&stdinPipe[0])
            closeIfOpen(&stdinPipe[1])
            closeIfOpen(&stdoutPipe[0])
            closeIfOpen(&stdoutPipe[1])
            closeIfOpen(&stderrPipe[0])
            closeIfOpen(&stderrPipe[1])
        }

        guard Darwin.pipe(&stdinPipe) == 0 else {
            throw AgentProcessError.pipeFailed(errno)
        }
        guard Darwin.pipe(&stdoutPipe) == 0 else {
            let code = errno
            closeAllPipes()
            throw AgentProcessError.pipeFailed(code)
        }
        guard Darwin.pipe(&stderrPipe) == 0 else {
            let code = errno
            closeAllPipes()
            throw AgentProcessError.pipeFailed(code)
        }

        for parentFD in [stdinPipe[1], stdoutPipe[0], stderrPipe[0]] {
            let flags = fcntl(parentFD, F_GETFD)
            if flags >= 0 {
                _ = fcntl(parentFD, F_SETFD, flags | FD_CLOEXEC)
            }
        }

        var attr: posix_spawnattr_t?
        let attrInit = posix_spawnattr_init(&attr)
        guard attrInit == 0 else {
            closeAllPipes()
            throw AgentProcessError.spawnSetupFailed(attrInit)
        }
        defer { posix_spawnattr_destroy(&attr) }

        let flagsRC = posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        guard flagsRC == 0 else {
            closeAllPipes()
            throw AgentProcessError.spawnSetupFailed(flagsRC)
        }
        let pgroupRC = posix_spawnattr_setpgroup(&attr, 0)
        guard pgroupRC == 0 else {
            closeAllPipes()
            throw AgentProcessError.spawnSetupFailed(pgroupRC)
        }

        var actions: posix_spawn_file_actions_t?
        let actionsInit = posix_spawn_file_actions_init(&actions)
        guard actionsInit == 0 else {
            closeAllPipes()
            throw AgentProcessError.spawnSetupFailed(actionsInit)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        for rc in [
            posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], STDIN_FILENO),
            posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO),
        ] where rc != 0 {
            closeAllPipes()
            throw AgentProcessError.spawnSetupFailed(rc)
        }

        // Close every original pipe descriptor in the child, including the parent's ends.
        for fd in [stdinPipe[0], stdinPipe[1], stdoutPipe[0], stdoutPipe[1], stderrPipe[0], stderrPipe[1]]
        where fd > STDERR_FILENO {
            let rc = posix_spawn_file_actions_addclose(&actions, fd)
            if rc != 0 {
                closeAllPipes()
                throw AgentProcessError.spawnSetupFailed(rc)
            }
        }

        if let workingDirectory = spec.workingDirectory, !workingDirectory.isEmpty {
            let chdirRC = posix_spawn_file_actions_addchdir_np(&actions, workingDirectory)
            guard chdirRC == 0 else {
                closeAllPipes()
                throw AgentProcessError.spawnSetupFailed(chdirRC)
            }
        }

        let allArguments = [spec.executable] + spec.arguments
        var argv: [UnsafeMutablePointer<CChar>?] = allArguments.map { strdup($0) }
        argv.append(nil)
        defer {
            for ptr in argv where ptr != nil {
                free(ptr)
            }
        }

        var envp: [UnsafeMutablePointer<CChar>?] = spec.environment.map { key, value in
            strdup("\(key)=\(value)")
        }
        envp.append(nil)
        defer {
            for ptr in envp where ptr != nil {
                free(ptr)
            }
        }

        var spawnedPID: pid_t = 0
        let spawnRC: Int32 = spec.executable.contains("/")
            ? posix_spawn(&spawnedPID, spec.executable, &actions, &attr, &argv, &envp)
            : posix_spawnp(&spawnedPID, spec.executable, &actions, &attr, &argv, &envp)

        // Close the child's pipe ends in the parent regardless of outcome.
        closeIfOpen(&stdinPipe[0])
        closeIfOpen(&stdoutPipe[1])
        closeIfOpen(&stderrPipe[1])

        guard spawnRC == 0 else {
            closeAllPipes()
            throw AgentProcessError.spawnFailed(executable: spec.executable, errno: spawnRC)
        }

        let childPID = spawnedPID
        self.pid = childPID
        let inputWriter = AgentInput(FileHandle(fileDescriptor: stdinPipe[1], closeOnDealloc: true))
        self.input = inputWriter

        let stdoutFD = stdoutPipe[0]
        let stderrFD = stderrPipe[0]
        self.stdout = Self.makePipeStream(fd: stdoutFD)
        self.stderr = Self.makePipeStream(fd: stderrFD)

        let state = self.exitState
        Thread.detachNewThread {
            var rawStatus: Int32 = 0
            while true {
                let waited = Darwin.waitpid(childPID, &rawStatus, 0)
                if waited == childPID {
                    break
                }
                if waited < 0 && errno == EINTR {
                    continue
                }
                break
            }
            // Report the exit before closing stdin: a write blocked on a full
            // pipe (a grandchild still holds the read end and isn't reading)
            // holds the input lock, and the close would wait on it.
            let exit = Self.decodeWaitStatus(rawStatus)
            state.finish(with: exit)
            onExit?(exit)
            inputWriter.close()
        }
    }

    /// Writes raw bytes to the child's standard input.
    public func write(_ data: Data) throws {
        try input.writeThrowing(data)
    }

    /// Writes raw bytes to the child's standard input, dropping errors if already closed.
    public func sendInput(_ data: Data) {
        input.write(data)
    }

    /// Closes the child's standard input pipe.
    public func closeInput() {
        input.close()
    }

    /// Waits up to `timeout` seconds for the child process to exit and returns its exit status.
    public func waitForExit(
        timeout: TimeInterval = AgentProcess.defaultWaitTimeout
    ) async throws -> AgentProcessExit {
        if let exit = await exitState.wait(timeout: timeout) {
            return exit
        }
        throw AgentProcessError.waitTimedOut(timeout)
    }

    /// Latest exit status if the child has already exited, or `nil` while running.
    public var currentExit: AgentProcessExit? {
        exitState.current()
    }

    /// Sends `SIGTERM` to the entire process group (`-pgid`), waits up to `grace`
    /// for the leader and every group member to exit, and sends `SIGKILL` to the
    /// group if anything remains (`AcpSessionRuntime.ts:1609-1615`).
    public func terminate(
        grace: TimeInterval = AgentProcess.defaultTerminationGrace,
        postKillTimeout: TimeInterval = AgentProcess.defaultPostKillWaitTimeout
    ) async {
        let pgid = self.pid
        guard pgid > 0 else {
            input.close()
            return
        }
        // Signal before closing stdin, and close it only once the group is
        // gone: a write blocked on a full pipe holds the input lock, so an
        // earlier close would wait for it and the group would never be
        // signalled. Ending the group closes the pipe's read end, which fails
        // the blocked write with EPIPE and frees the lock.
        defer { input.close() }

        if signalProcessGroup(pgid, SIGTERM) != 0 && errno == ESRCH && exitState.current() != nil {
            return
        }

        let clampedGrace = max(0, grace)
        let deadline = ProcessInfo.processInfo.systemUptime + clampedGrace
        while ProcessInfo.processInfo.systemUptime < deadline {
            if exitState.current() != nil && !Self.processGroupExists(pgid) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let clampedKillWait = max(0.02, postKillTimeout)
        let killDeadline = ProcessInfo.processInfo.systemUptime + clampedKillWait
        if exitState.current() == nil || Self.processGroupExists(pgid) {
            _ = signalProcessGroup(pgid, SIGKILL)
        }

        _ = await exitState.wait(timeout: clampedKillWait)
        while Self.processGroupExists(pgid) && ProcessInfo.processInfo.systemUptime < killDeadline {
            _ = signalProcessGroup(pgid, SIGKILL)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Splits a byte stream into UTF-8 lines off the main actor.
    public static func lines(from bytes: AsyncStream<Data>) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task.detached {
                var buffer = Data()
                for await chunk in bytes {
                    var start = chunk.startIndex
                    while let newline = chunk[start...].firstIndex(of: 0x0A) {
                        var lineBytes = buffer
                        buffer.removeAll(keepingCapacity: true)
                        lineBytes.append(contentsOf: chunk[start..<newline])
                        if lineBytes.last == 0x0D {
                            lineBytes.removeLast()
                        }
                        continuation.yield(String(decoding: lineBytes, as: UTF8.self))
                        start = chunk.index(after: newline)
                    }
                    if start < chunk.endIndex {
                        buffer.append(contentsOf: chunk[start...])
                    }
                }
                if !buffer.isEmpty {
                    if buffer.last == 0x0D {
                        buffer.removeLast()
                    }
                    continuation.yield(String(decoding: buffer, as: UTF8.self))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// True while at least one process in `pgid` still exists in the kernel table.
    public static func processGroupExists(_ pgid: pid_t) -> Bool {
        guard pgid > 0 else { return false }
        if Darwin.kill(-pgid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func makePipeStream(fd: Int32) -> AsyncStream<Data> {
        AsyncStream { continuation in
            Thread.detachNewThread {
                var scratch = [UInt8](repeating: 0, count: 65_536)
                while true {
                    let count = scratch.withUnsafeMutableBytes { rawBuffer -> Int in
                        guard let base = rawBuffer.baseAddress else { return 0 }
                        return Darwin.read(fd, base, rawBuffer.count)
                    }
                    if count > 0 {
                        continuation.yield(Data(scratch[0..<count]))
                    } else if count == 0 {
                        break
                    } else if errno == EINTR {
                        continue
                    } else {
                        break
                    }
                }
                _ = Darwin.close(fd)
                continuation.finish()
            }
        }
    }

    private static func decodeWaitStatus(_ status: Int32) -> AgentProcessExit {
        let low7 = status & 0x7f
        if low7 == 0 {
            return AgentProcessExit(exitCode: (status >> 8) & 0xff, signal: nil)
        }
        if low7 != 0x7f {
            return AgentProcessExit(exitCode: nil, signal: low7)
        }
        return AgentProcessExit(exitCode: -1, signal: nil)
    }

    private final class ExitState: Sendable {
        private struct State: Sendable {
            var result: AgentProcessExit?
            var waiters: [UUID: CheckedContinuation<AgentProcessExit?, Never>] = [:]
        }

        private let stateLock = OSAllocatedUnfairLock(initialState: State())

        func current() -> AgentProcessExit? {
            stateLock.withLock { $0.result }
        }

        func finish(with exit: AgentProcessExit) {
            let pending: [CheckedContinuation<AgentProcessExit?, Never>] = stateLock.withLock { state in
                guard state.result == nil else { return [] }
                state.result = exit
                let continuations = Array(state.waiters.values)
                state.waiters.removeAll()
                return continuations
            }
            for waiter in pending {
                waiter.resume(returning: exit)
            }
        }

        private func removeWaiter(id: UUID) -> CheckedContinuation<AgentProcessExit?, Never>? {
            stateLock.withLock { state in
                state.waiters.removeValue(forKey: id)
            }
        }

        func wait(timeout: TimeInterval) async -> AgentProcessExit? {
            if let existing = current() {
                return existing
            }
            if Task.isCancelled || timeout <= 0 {
                return current()
            }
            let waiterID = UUID()
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let immediate: (alreadyDone: Bool, value: AgentProcessExit?) = stateLock.withLock { state in
                        if let existing = state.result {
                            return (true, existing)
                        }
                        if Task.isCancelled {
                            return (true, nil)
                        }
                        state.waiters[waiterID] = continuation
                        return (false, nil)
                    }
                    if immediate.alreadyDone {
                        continuation.resume(returning: immediate.value)
                        return
                    }
                    let nanos = UInt64(max(1_000_000, timeout * 1_000_000_000))
                    Task.detached { [weak self] in
                        try? await Task.sleep(nanoseconds: nanos)
                        guard !Task.isCancelled else { return }
                        if let expired = self?.removeWaiter(id: waiterID) {
                            expired.resume(returning: nil)
                        }
                    }
                }
            } onCancel: {
                if let cancelled = self.removeWaiter(id: waiterID) {
                    cancelled.resume(returning: nil)
                }
            }
        }
    }
}
