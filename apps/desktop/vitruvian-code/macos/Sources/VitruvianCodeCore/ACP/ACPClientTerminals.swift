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

import Foundation
import os

/// Manages ACP client-hosted terminals (`terminal/*`), ported from `clientTerminals.ts`.
public actor ACPClientTerminals {
    /// Constants copied from `clientTerminals.ts:16-21` and `clientTerminals.ts:154`.
    public static let maxLiveTerminals = 16
    public static let maxUnreleasedTerminals = 64
    public static let maxRetainedTerminals = 32
    public static let maxRetainedOutputBytes = 16 * 1024 * 1024
    public static let defaultOutputByteLimit = 4 * 1024 * 1024
    public static let maxOutputByteLimit = 8 * 1024 * 1024
    public static let defaultKillGrace: TimeInterval = 5.0
    public static let defaultWaitForExitTimeout: TimeInterval = 90.0

    private final class TerminalEntry: Sendable {
        struct MutableState: Sendable {
            var chunks: [Data] = []
            var byteLength = 0
            var truncated = false
            var exitStatus: ACPTerminalExitStatus?
            var stdoutDone = false
            var stderrDone = false
            var released = false
            var drainWaiters: [CheckedContinuation<Void, Never>] = []
        }

        let id: String
        let sessionId: String
        let process: AgentProcess
        let outputByteLimit: Int
        private let state = OSAllocatedUnfairLock(initialState: MutableState())

        init(id: String, sessionId: String, process: AgentProcess, outputByteLimit: Int) {
            self.id = id
            self.sessionId = sessionId
            self.process = process
            self.outputByteLimit = outputByteLimit
        }

        var currentByteLength: Int {
            state.withLock { $0.byteLength }
        }

        var isReleased: Bool {
            state.withLock { $0.released }
        }

        var hasExitStatus: Bool {
            state.withLock { $0.exitStatus != nil }
        }

        func markReleased() {
            state.withLock { $0.released = true }
        }

        func appendChunk(_ data: Data) {
            guard !data.isEmpty else { return }
            state.withLock { s in
                guard outputByteLimit > 0 else {
                    s.truncated = true
                    return
                }
                if data.count >= outputByteLimit {
                    let drop = data.count - outputByteLimit
                    let alignedStart = ACPClientTerminals.alignUTF8Start(data, offset: drop)
                    let slice = Data(data[alignedStart...])
                    s.chunks = slice.isEmpty ? [] : [slice]
                    s.byteLength = slice.count
                    s.truncated = true
                    return
                }
                s.chunks.append(data)
                s.byteLength += data.count
                if s.byteLength > outputByteLimit {
                    Self.trimStartLocked(&s, excess: s.byteLength - outputByteLimit)
                }
            }
        }

        /// Trims up to `maxBytesToDrop` from the oldest buffered output (`clientTerminals.ts:103-112, 159-170`).
        func trimFromStart(maxBytesToDrop: Int) -> Int {
            guard maxBytesToDrop > 0 else { return 0 }
            return state.withLock { s in
                let before = s.byteLength
                guard before > 0 else { return 0 }
                Self.trimStartLocked(&s, excess: maxBytesToDrop)
                return before - s.byteLength
            }
        }

        private static func trimStartLocked(_ s: inout MutableState, excess: Int) {
            guard excess > 0 else { return }
            var remainingToDrop = excess
            var droppedAny = false
            while remainingToDrop > 0, let first = s.chunks.first {
                droppedAny = true
                if first.count <= remainingToDrop {
                    s.chunks.removeFirst()
                    s.byteLength -= first.count
                    remainingToDrop -= first.count
                } else {
                    let aligned = ACPClientTerminals.alignUTF8Start(first, offset: remainingToDrop)
                    if aligned >= first.count {
                        s.chunks.removeFirst()
                        s.byteLength -= first.count
                    } else {
                        let tail = Data(first[aligned...])
                        s.chunks[0] = tail
                        s.byteLength -= aligned
                    }
                    remainingToDrop = 0
                }
            }
            if droppedAny {
                s.truncated = true
            }
        }

        func markStreamFinished(isStdout: Bool) {
            let waiters: [CheckedContinuation<Void, Never>] = state.withLock { s in
                if isStdout {
                    s.stdoutDone = true
                } else {
                    s.stderrDone = true
                }
                guard s.stdoutDone && s.stderrDone else { return [] }
                let pending = s.drainWaiters
                s.drainWaiters.removeAll()
                return pending
            }
            for waiter in waiters {
                waiter.resume()
            }
        }

        func waitForOutputDrain() async {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { s -> Bool in
                    if s.stdoutDone && s.stderrDone {
                        return true
                    }
                    s.drainWaiters.append(continuation)
                    return false
                }
                if ready {
                    continuation.resume()
                }
            }
        }

        func recordExit(_ exit: AgentProcessExit) {
            state.withLock { s in
                if s.exitStatus == nil {
                    s.exitStatus = ACPTerminalExitStatus(
                        exitCode: exit.exitCode.map(Int.init),
                        signal: exit.signalName
                    )
                }
            }
        }

        func snapshot() -> ACPTerminalOutputResult {
            let (combined, wasTruncated, status) = state.withLock { s -> (Data, Bool, ACPTerminalExitStatus?) in
                var buffer = Data(capacity: s.byteLength)
                for chunk in s.chunks {
                    buffer.append(chunk)
                }
                return (buffer, s.truncated, s.exitStatus)
            }
            return ACPTerminalOutputResult(
                output: String(decoding: combined, as: UTF8.self),
                truncated: wasTruncated,
                exitStatus: status
            )
        }
    }

    private let baseEnvironment: [String: String]
    private let killGrace: TimeInterval
    private let waitForExitTimeout: TimeInterval
    private let maxRetainedTerminalsLimit: Int
    private let maxRetainedOutputBytesLimit: Int
    private var entries: [String: TerminalEntry] = [:]
    private var orderedIDs: [String] = []
    private var nextTerminalNumber = 1

    public init(
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        killGrace: TimeInterval = ACPClientTerminals.defaultKillGrace,
        waitForExitTimeout: TimeInterval = ACPClientTerminals.defaultWaitForExitTimeout,
        maxRetainedTerminals: Int = ACPClientTerminals.maxRetainedTerminals,
        maxRetainedOutputBytes: Int = ACPClientTerminals.maxRetainedOutputBytes
    ) {
        self.baseEnvironment = baseEnvironment
        self.killGrace = killGrace
        self.waitForExitTimeout = waitForExitTimeout
        self.maxRetainedTerminalsLimit = max(0, maxRetainedTerminals)
        self.maxRetainedOutputBytesLimit = max(0, maxRetainedOutputBytes)
    }

    /// Computes the capped per-terminal byte limit (`clientTerminals.ts:28-35`).
    public static func effectiveOutputByteLimit(_ requested: Int?) -> Int {
        guard let requested else { return defaultOutputByteLimit }
        return min(max(0, requested), maxOutputByteLimit)
    }

    /// Advances `offset` past UTF-8 continuation bytes so truncation starts at a scalar boundary (`clientTerminals.ts:64-72`).
    static func alignUTF8Start(_ data: Data, offset: Int) -> Int {
        let base = data.startIndex
        var idx = min(data.count, max(0, offset))
        while idx < data.count && (data[base + idx] & 0b1100_0000) == 0b1000_0000 {
            idx += 1
        }
        return idx
    }

    /// Enforces `maxRetainedOutputBytes` across all buffered terminals by trimming oldest output first (`clientTerminals.ts:159-170`).
    private func enforceTotalOutputLimit() {
        let totalBytes = orderedIDs.reduce(0) { total, id in
            total + (entries[id]?.currentByteLength ?? 0)
        }
        var excess = totalBytes - maxRetainedOutputBytesLimit
        guard excess > 0 else { return }
        for id in orderedIDs {
            guard let entry = entries[id] else { continue }
            let dropped = entry.trimFromStart(maxBytesToDrop: excess)
            excess -= dropped
            if excess <= 0 {
                break
            }
        }
    }

    /// Prunes oldest released terminal snapshots when released count > `maxRetainedTerminals`
    /// or total released bytes > `maxRetainedOutputBytes` (`clientTerminals.ts:172-181`).
    private func pruneReleasedSnapshots() {
        var releasedEntries: [TerminalEntry] = orderedIDs.compactMap { id in
            guard let entry = entries[id], entry.isReleased else { return nil }
            return entry
        }
        var retainedBytes = releasedEntries.reduce(0) { $0 + $1.currentByteLength }
        while releasedEntries.count > maxRetainedTerminalsLimit || retainedBytes > maxRetainedOutputBytesLimit {
            let oldest = releasedEntries.removeFirst()
            retainedBytes -= oldest.currentByteLength
            entries.removeValue(forKey: oldest.id)
            orderedIDs.removeAll { $0 == oldest.id }
        }
    }

    private func validateSessionID(_ requestedSessionID: String?, expectedSessionID: String?) throws -> String {
        let trimmed = requestedSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Missing sessionId on terminal request.")
        }
        if let expectedSessionID, !expectedSessionID.isEmpty, trimmed != expectedSessionID {
            throw ACPRPCError(
                code: ACPRPCError.invalidParams,
                message: "Terminal request sessionId '\(trimmed)' does not match active session '\(expectedSessionID)'."
            )
        }
        return trimmed
    }

    private func requireActiveEntry(
        sessionId: String?,
        terminalId: String,
        expectedSessionID: String?
    ) throws -> TerminalEntry {
        let validSessionID = try validateSessionID(sessionId, expectedSessionID: expectedSessionID)
        guard let entry = entries[terminalId],
              !entry.isReleased,
              entry.sessionId == validSessionID else {
            throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Unknown terminalId: \(terminalId)")
        }
        return entry
    }

    /// Reads an active or retained post-release terminal output snapshot when `sessionId` matches (`clientTerminals.ts:355-363`).
    public func readOutputSnapshot(sessionId: String, terminalId: String) -> ACPTerminalOutputResult? {
        guard let entry = entries[terminalId], entry.sessionId == sessionId else {
            return nil
        }
        return entry.snapshot()
    }

    public func create(
        _ params: ACPTerminalCreateParams,
        policy: ACPClientPolicy,
        files: ACPClientFiles,
        expectedSessionID: String? = nil
    ) async throws -> ACPTerminalCreateResult {
        guard policy.terminal else {
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: terminal/create")
        }
        let validSessionID = try validateSessionID(params.sessionId, expectedSessionID: expectedSessionID)

        let unreleasedEntries = entries.values.filter { !$0.isReleased }
        let liveCount = unreleasedEntries.filter { !$0.hasExitStatus && $0.process.currentExit == nil }.count
        if liveCount >= Self.maxLiveTerminals || unreleasedEntries.count >= Self.maxUnreleasedTerminals {
            throw ACPRPCError(
                code: ACPRPCError.internalError,
                message: "Maximum number of concurrent client terminals reached."
            )
        }

        let resolvedCwd: String
        if let requestedCwd = params.cwd, !requestedCwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedCwd = try files.resolveContainedPath(requestedCwd)
        } else {
            resolvedCwd = try files.resolveContainedPath(files.workingDirectory)
        }

        let command = params.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw ACPRPCError(code: ACPRPCError.invalidParams, message: "Terminal command must not be empty.")
        }

        var mergedEnv = baseEnvironment
        for pair in params.env ?? [] {
            mergedEnv[pair.name] = pair.value
        }

        let launchSpec: AgentProcessLaunchSpec
        if let args = params.args {
            launchSpec = AgentProcessLaunchSpec(
                executable: command,
                arguments: args,
                environment: mergedEnv,
                workingDirectory: resolvedCwd
            )
        } else {
            launchSpec = AgentProcessLaunchSpec(
                executable: "/bin/sh",
                arguments: ["-c", command],
                environment: mergedEnv,
                workingDirectory: resolvedCwd
            )
        }

        let terminalId = "term-\(nextTerminalNumber)"
        nextTerminalNumber += 1
        let byteLimit = Self.effectiveOutputByteLimit(params.outputByteLimit)

        let process: AgentProcess
        do {
            process = try AgentProcess(launchSpec)
        } catch {
            throw ACPRPCError(
                code: ACPRPCError.internalError,
                message: "Failed to launch terminal command: \(error.localizedDescription)"
            )
        }
        process.closeInput()

        let entry = TerminalEntry(
            id: terminalId,
            sessionId: validSessionID,
            process: process,
            outputByteLimit: byteLimit
        )
        entries[terminalId] = entry
        orderedIDs.append(terminalId)

        Task.detached { [weak self] in
            for await chunk in process.stdout {
                entry.appendChunk(chunk)
                await self?.enforceTotalOutputLimit()
            }
            entry.markStreamFinished(isStdout: true)
        }
        Task.detached { [weak self] in
            for await chunk in process.stderr {
                entry.appendChunk(chunk)
                await self?.enforceTotalOutputLimit()
            }
            entry.markStreamFinished(isStdout: false)
        }
        Task.detached {
            while !Task.isCancelled {
                if let exit = try? await process.waitForExit(timeout: AgentProcess.defaultWaitTimeout) {
                    entry.recordExit(exit)
                    break
                }
                if let exit = process.currentExit {
                    entry.recordExit(exit)
                    break
                }
            }
        }

        return ACPTerminalCreateResult(terminalId: terminalId)
    }

    public func output(
        _ params: ACPTerminalOutputParams,
        policy: ACPClientPolicy,
        expectedSessionID: String? = nil
    ) async throws -> ACPTerminalOutputResult {
        guard policy.terminal else {
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: terminal/output")
        }
        let entry = try requireActiveEntry(
            sessionId: params.sessionId,
            terminalId: params.terminalId,
            expectedSessionID: expectedSessionID
        )
        if let exit = entry.process.currentExit {
            entry.recordExit(exit)
            await entry.waitForOutputDrain()
        }
        return entry.snapshot()
    }

    public func waitForExit(
        _ params: ACPTerminalWaitForExitParams,
        policy: ACPClientPolicy,
        expectedSessionID: String? = nil
    ) async throws -> ACPTerminalExitStatus {
        guard policy.terminal else {
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: terminal/wait_for_exit")
        }
        let entry = try requireActiveEntry(
            sessionId: params.sessionId,
            terminalId: params.terminalId,
            expectedSessionID: expectedSessionID
        )
        let exit: AgentProcessExit
        do {
            exit = try await entry.process.waitForExit(timeout: waitForExitTimeout)
        } catch {
            throw ACPRPCError(
                code: ACPRPCError.internalError,
                message: "Timed out waiting for terminal '\(params.terminalId)' to exit."
            )
        }
        entry.recordExit(exit)
        await entry.waitForOutputDrain()
        return ACPTerminalExitStatus(
            exitCode: exit.exitCode.map(Int.init),
            signal: exit.signalName
        )
    }

    public func kill(
        _ params: ACPTerminalKillParams,
        policy: ACPClientPolicy,
        expectedSessionID: String? = nil
    ) async throws -> ACPEmptyObject {
        guard policy.terminal else {
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: terminal/kill")
        }
        let entry = try requireActiveEntry(
            sessionId: params.sessionId,
            terminalId: params.terminalId,
            expectedSessionID: expectedSessionID
        )
        await entry.process.terminate(grace: killGrace)
        if let exit = entry.process.currentExit {
            entry.recordExit(exit)
        }
        return ACPEmptyObject()
    }

    public func release(
        _ params: ACPTerminalReleaseParams,
        policy: ACPClientPolicy,
        expectedSessionID: String? = nil
    ) async throws -> ACPEmptyObject {
        guard policy.terminal else {
            throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: terminal/release")
        }
        let entry = try requireActiveEntry(
            sessionId: params.sessionId,
            terminalId: params.terminalId,
            expectedSessionID: expectedSessionID
        )
        entry.markReleased()
        await entry.process.terminate(grace: killGrace)
        await entry.waitForOutputDrain()
        if let exit = entry.process.currentExit {
            entry.recordExit(exit)
        }
        pruneReleasedSnapshots()
        return ACPEmptyObject()
    }

    /// Terminates and frees every active or retained terminal when the session closes.
    public func closeAll() async {
        let current = Array(entries.values)
        entries.removeAll()
        orderedIDs.removeAll()
        for entry in current {
            entry.markReleased()
            await entry.process.terminate(grace: killGrace)
        }
    }
}
