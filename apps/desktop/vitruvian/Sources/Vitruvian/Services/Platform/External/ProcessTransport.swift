// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import os

/// A tool's program as an ordinary child process: its standard input and
/// output are the link, its standard error is its log. It is started in
/// the tool's data folder with the environment the app itself has, and so
/// with every macOS permission the app has.
///
/// The main thread never reads or writes a pipe. What the tool writes is
/// read and taken apart on a queue of this transport's own, and handed to
/// the main thread a batch at a time; the queue waits for each batch to be
/// dealt with before it reads on, so a tool that writes faster than the app
/// reads waits on its pipe. What the app writes is queued and written on
/// another queue.
@MainActor
package final class ProcessTransport: ToolTransport {
    private let program: URL
    private let directory: URL
    private let limits: ToolLimits
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let writing = DispatchQueue(label: "com.vitruviansoftware.vitruvian.tool-input", qos: .utility)
    /// Bytes queued for the tool that it has not taken yet.
    private let unread = OSAllocatedUnfairLock(initialState: 0)
    private var wasStarted = false
    private var inputOpen = false

    /// `program` is the file to run and `directory` the folder it runs in.
    package init(program: URL, directory: URL, limits: ToolLimits = .standard) {
        self.program = program
        self.directory = directory
        self.limits = limits
    }

    /// The process's id, once it runs. For the log, and for tests.
    package var processIdentifier: pid_t? {
        wasStarted && process.processIdentifier > 0 ? process.processIdentifier : nil
    }

    /// The status the program ended with, once it has: its exit status, or
    /// 128 and the signal that ended it.
    package var exitStatus: Int32? {
        guard wasStarted, !process.isRunning, process.processIdentifier > 0 else { return nil }
        return Self.status(of: process)
    }

    package var isRunning: Bool { wasStarted && process.isRunning }

    package func start(onItems: @escaping @MainActor ([ToolInbound]) -> Void,
                       onErrorOutput: @escaping @MainActor (Data) -> Void,
                       onExit: @escaping @MainActor (Int32) -> Void) -> Bool {
        guard !wasStarted else { return false }
        process.executableURL = program
        process.currentDirectoryURL = directory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        // A tool that has gone fails a write instead of ending the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return false }
        let pump = OutputPump(output: output.fileHandleForReading, errorOutput: errorOutput.fileHandleForReading,
                              linesPerSecond: limits.linesHandedPerSecond, errorBytes: limits.logBytes,
                              onItems: onItems, onErrorOutput: onErrorOutput, onExit: onExit)
        process.terminationHandler = { process in pump.finish(status: Self.status(of: process)) }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            return false
        }
        wasStarted = true
        inputOpen = true
        pump.start()
        return true
    }

    package func send(_ line: Data) -> Bool {
        guard inputOpen else { return false }
        let count = line.count
        let queued = unread.withLock { bytes -> Int in
            bytes += count
            return bytes
        }
        guard queued <= limits.unreadBytes else {
            unread.withLock { $0 -= count }
            return false
        }
        let handle = input.fileHandleForWriting
        writing.async { [unread] in
            // Waits while the pipe is full; fails once the tool has gone.
            try? handle.write(contentsOf: line)
            unread.withLock { $0 -= count }
        }
        return true
    }

    package func closeInput() {
        guard inputOpen else { return }
        inputOpen = false
        let handle = input.fileHandleForWriting
        writing.async { try? handle.close() }
    }

    package func terminate() {
        if isRunning { process.terminate() }
    }

    package func kill() {
        if isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }

    nonisolated private static func status(of process: Process) -> Int32 {
        process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }
}

/// Reads a tool's standard output and standard error, on a queue of its
/// own. Everything it holds is touched on that queue only.
private final class OutputPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.tool-output", qos: .utility)
    private let output: FileHandle
    private let errorOutput: FileHandle
    private let linesPerSecond: Int
    private let errorBytes: Int
    private let onItems: @MainActor ([ToolInbound]) -> Void
    private let onErrorOutput: @MainActor (Data) -> Void
    private let onExit: @MainActor (Int32) -> Void

    private var reader = ToolLineReader()
    private var outputSource: (any DispatchSourceRead)?
    private var errorSource: (any DispatchSourceRead)?
    /// The second being counted, and how many lines the main thread was
    /// handed in it.
    private var secondStart = DispatchTime.now().uptimeNanoseconds
    private var handed = 0
    /// Standard error not handed on yet: the newest of it.
    private var errorTail = Data()
    private var errorFlushQueued = false
    private var finished = false

    init(output: FileHandle, errorOutput: FileHandle, linesPerSecond: Int, errorBytes: Int,
         onItems: @escaping @MainActor ([ToolInbound]) -> Void,
         onErrorOutput: @escaping @MainActor (Data) -> Void,
         onExit: @escaping @MainActor (Int32) -> Void) {
        self.output = output
        self.errorOutput = errorOutput
        self.linesPerSecond = max(1, linesPerSecond)
        self.errorBytes = max(1, errorBytes)
        self.onItems = onItems
        self.onErrorOutput = onErrorOutput
        self.onExit = onExit
    }

    func start() {
        queue.async { [self] in
            // A program can end, and `finish` run, before this does: there
            // is then nothing left to watch, and a source on a stream that
            // has ended would fire for ever.
            guard !finished else { return }
            outputSource = watch(output, isError: false)
            errorSource = watch(errorOutput, isError: true)
        }
    }

    /// The program has ended: read what it left, then say so. Its last
    /// lines and its end reach the main thread in that order.
    func finish(status: Int32) {
        queue.async { [self] in
            guard !finished else { return }
            read(output, isError: false, chunks: .max)
            read(errorOutput, isError: true, chunks: .max)
            finished = true
            outputSource?.cancel()
            errorSource?.cancel()
            outputSource = nil
            errorSource = nil
            flushErrors()
            let onExit = self.onExit
            DispatchQueue.main.async { MainActor.assumeIsolated { onExit(status) } }
        }
    }

    private func watch(_ handle: FileHandle, isError: Bool) -> any DispatchSourceRead {
        let descriptor = handle.fileDescriptor
        // A read never waits: it takes what is there.
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        // A few chunks a turn, so one stream cannot keep the other, or the
        // program's end, from being seen.
        source.setEventHandler { [self] in read(handle, isError: isError, chunks: 8) }
        source.resume()
        return source
    }

    private func read(_ handle: FileHandle, isError: Bool, chunks: Int) {
        guard !finished else { return }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var taken = 0
        while taken < chunks {
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count == 0 {
                // The stream is closed. Stop watching it, or it would be
                // reported as readable for ever.
                if isError { errorSource?.cancel() } else { outputSource?.cancel() }
                return
            }
            // Nothing more for now, or an error: either way, not this turn.
            guard count > 0 else { return }
            taken += 1
            let bytes = Data(buffer[0..<count])
            if isError { keep(bytes) } else { hand(reader.read(bytes)) }
        }
    }

    /// Hands lines to the main thread and waits until it has dealt with
    /// them. No more than `linesPerSecond` in a second: past that the
    /// queue waits, and the tool with it.
    private func hand(_ items: [ToolInbound]) {
        var rest = items[...]
        while !rest.isEmpty {
            let now = DispatchTime.now().uptimeNanoseconds
            if now - secondStart >= 1_000_000_000 {
                secondStart = now
                handed = 0
            }
            let room = linesPerSecond - handed
            guard room > 0 else {
                usleep(useconds_t((secondStart + 1_000_000_000 - now) / 1_000) + 1)
                continue
            }
            let batch = Array(rest.prefix(room))
            rest = rest.dropFirst(batch.count)
            handed += batch.count
            let onItems = self.onItems
            DispatchQueue.main.sync { MainActor.assumeIsolated { onItems(batch) } }
        }
    }

    /// Keeps the newest standard error, and hands it on a little later, so
    /// a tool that writes a great deal of it costs the main thread ten
    /// short calls a second and no more.
    private func keep(_ bytes: Data) {
        errorTail.append(bytes)
        if errorTail.count > errorBytes { errorTail = errorTail.suffix(errorBytes) }
        guard !errorFlushQueued else { return }
        errorFlushQueued = true
        queue.asyncAfter(deadline: .now() + 0.1) { [self] in flushErrors() }
    }

    private func flushErrors() {
        errorFlushQueued = false
        guard !errorTail.isEmpty else { return }
        let tail = errorTail
        errorTail = Data()
        let onErrorOutput = self.onErrorOutput
        DispatchQueue.main.async { MainActor.assumeIsolated { onErrorOutput(tail) } }
    }
}
