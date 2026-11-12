// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import Foundation

/// What to start: the program, its arguments and its whole environment.
public struct LaunchSpec: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]

    public init(executable: URL, arguments: [String], environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

/// The environment holds the Telegram credentials, so printing a spec names its variables and never their values.
extension LaunchSpec: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "LaunchSpec(\(executable.path) \(arguments.joined(separator: " ")), environment: \(environment.keys.sorted()))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["executable": executable, "arguments": arguments,
                                "environment": environment.keys.sorted()])
    }
}

/// A started child process, as the supervisor sees it.
public protocol LaunchedProcess: AnyObject, Sendable {
    /// Standard output, a line at a time; it finishes at end of file.
    var standardOutputLines: AsyncStream<String> { get }
    /// Standard error, a line at a time; it finishes at end of file.
    var standardErrorLines: AsyncStream<String> { get }
    /// The exit status once it has ended: its own status, or 128 plus the signal that ended it.
    func waitForExit() async -> Int32
    /// SIGTERM.
    func terminate()
    /// SIGKILL.
    func kill()
    /// Closes the app's end of the parent pipe, the child's standard input: the engine stops at end of file.
    func closeParentPipe()
}

/// Starts child processes. Tests give the supervisor a fake one.
public protocol ProcessLaunching: Sendable {
    func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess
}

/// Starts a real process with Foundation.
///
/// The child's standard input is the read end of a pipe whose write end only the app holds, for the child's whole
/// life: the engine runs with `--parent-fd 0` and stops when it reads end of file, which is when the app closes the
/// pipe or the app dies. (Foundation's Process passes only standard input, output and error to the child, so the
/// pipe has to be one of them.)
public struct FoundationProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(_ spec: LaunchSpec) throws -> any LaunchedProcess {
        try FoundationProcess(spec)
    }
}

final class FoundationProcess: LaunchedProcess, @unchecked Sendable {
    let standardOutputLines: AsyncStream<String>
    let standardErrorLines: AsyncStream<String>
    private let process = Process()
    private let parent = Pipe()
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    init(_ spec: LaunchSpec) throws {
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.environment = spec.environment
        process.standardInput = parent
        process.standardOutput = output
        process.standardError = errorOutput
        standardOutputLines = Self.lines(of: output.fileHandleForReading)
        standardErrorLines = Self.lines(of: errorOutput.fileHandleForReading)
        process.terminationHandler = { [weak self] process in
            let code = process.terminationReason == .uncaughtSignal
                ? 128 + process.terminationStatus : process.terminationStatus
            self?.finish(code)
        }
        try process.run()
        // The child has its copy of the read end; the app keeps only the write end, and never writes to it.
        try? parent.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errorOutput.fileHandleForWriting.close()
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

    func terminate() { signal(SIGTERM) }

    func kill() { signal(SIGKILL) }

    func closeParentPipe() {
        try? parent.fileHandleForWriting.close()
    }

    private func signal(_ number: Int32) {
        // Only while the child has not been collected: after that its pid may name another process.
        lock.withLock {
            guard status == nil, process.processIdentifier > 0 else { return }
            Darwin.kill(process.processIdentifier, number)
        }
    }

    private func finish(_ code: Int32) {
        let resumed = lock.withLock { () -> [CheckedContinuation<Int32, Never>] in
            status = code
            defer { waiters = [] }
            return waiters
        }
        closeParentPipe()
        for waiter in resumed { waiter.resume(returning: code) }
    }

    /// The handle's lines, without their newlines. A last line with no newline is kept.
    private static func lines(of handle: FileHandle) -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let buffer = LineBuffer()
        // The handler runs on one queue of the handle's own, one call at a time.
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if let rest = buffer.rest() { continuation.yield(rest) }
                continuation.finish()
                return
            }
            for line in buffer.append(data) { continuation.yield(line) }
        }
        return stream
    }
}

/// Bytes read so far, cut into lines.
private final class LineBuffer: @unchecked Sendable {
    private var data = Data()

    /// Adds bytes and returns the lines they complete, without their newlines.
    func append(_ bytes: Data) -> [String] {
        data.append(bytes)
        var lines: [String] = []
        while let newline = data.firstIndex(of: 0x0A) {
            lines.append(String(decoding: data[data.startIndex ..< newline], as: UTF8.self))
            data = Data(data[data.index(after: newline)...])
        }
        return lines
    }

    /// What is left after the last newline, if anything.
    func rest() -> String? {
        defer { data = Data() }
        return data.isEmpty ? nil : String(decoding: data, as: UTF8.self)
    }
}
