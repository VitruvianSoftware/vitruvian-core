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

import Foundation
import os
@testable import VitruvianCodeCore
import XCTest

enum ACPTestTimeoutError: Error, LocalizedError, Equatable {
    case timedOut(description: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let description, let seconds):
            return "Timed out after \(seconds)s waiting for \(description)."
        }
    }
}

/// Runs `operation` with a hard bounded timeout that fails the test immediately instead of hanging,
/// even if `operation` is suspended inside an uncancelled continuation.
func withACPTestTimeout<T: Sendable>(
    seconds: TimeInterval = 5.0,
    description: String = "async test operation",
    recordFailureOnTimeout: Bool = true,
    file: StaticString = #filePath,
    line: UInt = #line,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let completed = OSAllocatedUnfairLock(initialState: false)
    return try await withCheckedThrowingContinuation { continuation in
        let workTask = Task {
            do {
                let value = try await operation()
                let won = completed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                if won {
                    continuation.resume(returning: value)
                }
            } catch {
                let won = completed.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                if won {
                    continuation.resume(throwing: error)
                }
            }
        }
        Task {
            let nanos = UInt64(max(1_000_000, seconds * 1_000_000_000))
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            let won = completed.withLock { done -> Bool in
                guard !done else { return false }
                done = true
                return true
            }
            if won {
                workTask.cancel()
                if recordFailureOnTimeout {
                    XCTFail("Timed out after \(seconds)s waiting for \(description).", file: file, line: line)
                }
                continuation.resume(
                    throwing: ACPTestTimeoutError.timedOut(description: description, seconds: seconds)
                )
            }
        }
    }
}

/// Thread-safe in-memory byte pipe used to drive `ACPTransport` and `ACPConnection` without spawning OS processes.
final class InMemoryBytePipe: Sendable {
    private struct State: Sendable {
        var continuation: AsyncStream<Data>.Continuation?
        var isClosed = false
    }

    let stream: AsyncStream<Data>
    private let state: OSAllocatedUnfairLock<State>

    init() {
        var captured: AsyncStream<Data>.Continuation!
        self.stream = AsyncStream { cont in
            captured = cont
        }
        self.state = OSAllocatedUnfairLock(initialState: State(continuation: captured))
    }

    func write(_ data: Data) throws {
        let cont = try state.withLock { s -> AsyncStream<Data>.Continuation? in
            if s.isClosed {
                throw POSIXError(.EPIPE)
            }
            return s.continuation
        }
        cont?.yield(data)
    }

    func writeLine(_ line: String) throws {
        try write(Data((line + "\n").utf8))
    }

    func writeJSON(_ value: ACPJSONValue) throws {
        let encoded = try JSONEncoder().encode(value)
        var line = encoded
        line.append(0x0A)
        try write(line)
    }

    func finish() {
        let cont = state.withLock { s -> AsyncStream<Data>.Continuation? in
            guard !s.isClosed else { return nil }
            s.isClosed = true
            let current = s.continuation
            s.continuation = nil
            return current
        }
        cont?.finish()
    }
}

/// One step in a `testdata/acp/*.ndjson` scripted exchange.
enum ACPFixtureStep: Equatable, Sendable {
    case expectClientRequest(method: String)
    case expectClientResponse(id: ACPRPCID)
    case agentSend(ACPJSONValue)
    case agentStderr(String)
}

enum ACPFixtureLoader {
    /// Resolves `testdata/acp/<name>` under both Bazel (`TEST_SRCDIR`) and SwiftPM (`#filePath`).
    static func loadSteps(
        named file: String,
        filePath: StaticString = #filePath,
        line: UInt = #line
    ) -> [ACPFixtureStep] {
        let relative = "apps/desktop/vitruvian-code/testdata/acp/\(file)"
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/\(relative)")
            }
        }
        let testsDir = (#filePath as NSString).deletingLastPathComponent
        let appRoot = ((testsDir as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        candidates.append("\(appRoot)/testdata/acp/\(file)")

        guard let resolvedPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            XCTFail("ACP fixture \(file) is missing; looked in \(candidates)", file: filePath, line: line)
            return []
        }
        guard let rawText = try? String(contentsOfFile: resolvedPath, encoding: .utf8) else {
            XCTFail("ACP fixture \(resolvedPath) could not be read as UTF-8", file: filePath, line: line)
            return []
        }

        var steps: [ACPFixtureStep] = []
        let rawLines = rawText.components(separatedBy: .newlines)
        for (idx, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONDecoder().decode(ACPJSONValue.self, from: data),
                  let obj = json.objectValue,
                  let direction = obj["direction"]?.stringValue else {
                XCTFail("Malformed fixture line \(idx + 1) in \(file): \(trimmed)", file: filePath, line: line)
                return []
            }
            switch direction {
            case "client":
                guard let method = obj["method"]?.stringValue else {
                    XCTFail("Missing method on client step line \(idx + 1) in \(file)", file: filePath, line: line)
                    return []
                }
                steps.append(.expectClientRequest(method: method))
            case "client_response":
                guard let rawID = obj["id"], let rpcID = ACPRPCID(jsonValue: rawID) else {
                    XCTFail("Missing id on client_response step line \(idx + 1) in \(file)", file: filePath, line: line)
                    return []
                }
                steps.append(.expectClientResponse(id: rpcID))
            case "agent":
                guard let send = obj["send"] else {
                    XCTFail("Missing send payload on agent step line \(idx + 1) in \(file)", file: filePath, line: line)
                    return []
                }
                steps.append(.agentSend(send))
            case "agent_stderr":
                steps.append(.agentStderr(obj["line"]?.stringValue ?? ""))
            default:
                XCTFail("Unknown fixture direction '\(direction)' in \(file)", file: filePath, line: line)
                return []
            }
        }
        if steps.isEmpty {
            XCTFail("ACP fixture \(file) contains zero steps", file: filePath, line: line)
        }
        return steps
    }
}

/// Scripted in-memory ACP agent used by `ACPConnectionTests` and fixture playback tests.
actor ScriptedACPAgent {
    private let clientToAgent = InMemoryBytePipe()
    private let agentToClient = InMemoryBytePipe()
    private let agentStderr = InMemoryBytePipe()

    private var receivedMessages: [ACPJSONValue] = []
    private var messageWaiters: [UUID: (Int, CheckedContinuation<ACPJSONValue?, Never>)] = [:]
    private var exitWaiters: [UUID: CheckedContinuation<AgentProcessExit, Never>] = [:]
    private var resolvedExit: AgentProcessExit?
    private var recordedTerminations: [TimeInterval] = []
    private var capturedLaunchSpec: AgentProcessLaunchSpec?
    private var readerTask: Task<Void, Never>?

    init() {
        let incomingStream = clientToAgent.stream
        Task {
            await self.startReadingClientStream(incomingStream)
        }
    }

    private func startReadingClientStream(_ stream: AsyncStream<Data>) {
        guard readerTask == nil else { return }
        readerTask = Task {
            for await line in AgentProcess.lines(from: stream) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty,
                      let data = trimmed.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(ACPJSONValue.self, from: data) else {
                    continue
                }
                self.recordClientMessage(decoded)
            }
        }
    }

    private func recordClientMessage(_ message: ACPJSONValue) {
        let index = receivedMessages.count
        receivedMessages.append(message)
        var toResume: [CheckedContinuation<ACPJSONValue?, Never>] = []
        for (waiterID, entry) in messageWaiters where entry.0 == index {
            messageWaiters.removeValue(forKey: waiterID)
            toResume.append(entry.1)
        }
        for continuation in toResume {
            continuation.resume(returning: message)
        }
    }

    private func cancelMessageWaiter(_ id: UUID) {
        if let removed = messageWaiters.removeValue(forKey: id) {
            removed.1.resume(returning: nil)
        }
    }

    nonisolated func makeProcessFactory() -> ACPConnection.ProcessFactory {
        { spec in
            let stdoutStream = self.agentToClient.stream
            let stderrStream = self.agentStderr.stream
            let stdinPipe = self.clientToAgent
            Task {
                await self.recordLaunchSpec(spec)
            }
            return ACPLaunchedProcess(
                stdout: stdoutStream,
                stderr: stderrStream,
                writeStdin: { data in try stdinPipe.write(data) },
                closeStdin: { stdinPipe.finish() },
                waitForExit: { await self.waitForSimulatedExit(timeout: 15.0) },
                terminate: { grace in await self.recordTermination(grace: grace) }
            )
        }
    }

    private func recordLaunchSpec(_ spec: AgentProcessLaunchSpec) {
        capturedLaunchSpec = spec
    }

    func launchSpec() -> AgentProcessLaunchSpec? {
        capturedLaunchSpec
    }

    func terminations() -> [TimeInterval] {
        recordedTerminations
    }

    func allClientMessages() -> [ACPJSONValue] {
        receivedMessages
    }

    func clientMessage(
        at index: Int,
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ACPJSONValue {
        let maybeMessage = try await withACPTestTimeout(
            seconds: timeout,
            description: "client message #\(index)",
            file: file,
            line: line
        ) {
            await self.waitClientMessage(at: index)
        }
        guard let message = maybeMessage else {
            throw ACPTestTimeoutError.timedOut(description: "client message #\(index)", seconds: timeout)
        }
        return message
    }

    private func waitClientMessage(at index: Int) async -> ACPJSONValue? {
        if index < receivedMessages.count {
            return receivedMessages[index]
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if index < receivedMessages.count {
                    continuation.resume(returning: receivedMessages[index])
                } else if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    messageWaiters[waiterID] = (index, continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelMessageWaiter(waiterID) }
        }
    }

    func sendToClient(_ payload: ACPJSONValue) throws {
        try agentToClient.writeJSON(payload)
    }

    func sendRawLineToClient(_ line: String) throws {
        try agentToClient.writeLine(line)
    }

    func writeStderrLine(_ line: String) throws {
        try agentStderr.writeLine(line)
    }

    func simulateExit(_ exit: AgentProcessExit) {
        agentToClient.finish()
        agentStderr.finish()
        clientToAgent.finish()
        if resolvedExit == nil {
            resolvedExit = exit
            let pending = Array(exitWaiters.values)
            exitWaiters.removeAll()
            for waiter in pending {
                waiter.resume(returning: exit)
            }
        }
    }

    private func removeExitWaiter(_ id: UUID) -> CheckedContinuation<AgentProcessExit, Never>? {
        exitWaiters.removeValue(forKey: id)
    }

    private func waitForSimulatedExit(timeout: TimeInterval) async -> AgentProcessExit {
        if let resolvedExit {
            return resolvedExit
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let resolvedExit {
                    continuation.resume(returning: resolvedExit)
                } else if Task.isCancelled {
                    continuation.resume(returning: AgentProcessExit(exitCode: 0, signal: nil))
                } else {
                    exitWaiters[waiterID] = continuation
                    let nanos = UInt64(max(1_000_000, timeout * 1_000_000_000))
                    Task {
                        try? await Task.sleep(nanoseconds: nanos)
                        guard !Task.isCancelled else { return }
                        if let expired = self.removeExitWaiter(waiterID) {
                            expired.resume(returning: self.resolvedExit ?? AgentProcessExit(exitCode: 0, signal: nil))
                        }
                    }
                }
            }
        } onCancel: {
            Task {
                if let cancelled = await self.removeExitWaiter(waiterID) {
                    let fallback = await self.resolvedExit ?? AgentProcessExit(exitCode: 0, signal: nil)
                    cancelled.resume(returning: fallback)
                }
            }
        }
    }

    private func recordTermination(grace: TimeInterval) {
        recordedTerminations.append(grace)
        simulateExit(AgentProcessExit(exitCode: 0, signal: nil))
    }

    /// Plays an `.ndjson` fixture step list from `startMessageIndex`, substituting `"$id"` with the latest matched client request ID.
    func playSteps(
        _ steps: [ACPFixtureStep],
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        var cursor = 0
        var lastRequestID: ACPJSONValue = .int(1)
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        for step in steps {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                XCTFail("Timed out after \(timeout)s playing fixture steps.", file: file, line: line)
                throw ACPTestTimeoutError.timedOut(description: "playSteps", seconds: timeout)
            }
            switch step {
            case .expectClientRequest(let expectedMethod):
                let message = try await clientMessage(at: cursor, timeout: remaining, file: file, line: line)
                cursor += 1
                guard let obj = message.objectValue,
                      let actualMethod = obj["method"]?.stringValue else {
                    throw ACPTransportError.decodingFailed("Expected client request \(expectedMethod), got \(message.serializedJSONString())")
                }
                guard actualMethod == expectedMethod else {
                    throw ACPTransportError.decodingFailed("Expected client method \(expectedMethod), got \(actualMethod)")
                }
                if let id = obj["id"] {
                    lastRequestID = id
                }

            case .expectClientResponse(let expectedID):
                let message = try await clientMessage(at: cursor, timeout: remaining, file: file, line: line)
                cursor += 1
                guard let obj = message.objectValue,
                      let rawID = obj["id"],
                      ACPRPCID(jsonValue: rawID) == expectedID else {
                    throw ACPTransportError.decodingFailed("Expected client response for id \(expectedID.stringDescription), got \(message.serializedJSONString())")
                }

            case .agentSend(let template):
                let resolved = Self.substituteID(in: template, with: lastRequestID)
                try sendToClient(resolved)

            case .agentStderr(let lineText):
                try writeStderrLine(lineText)
            }
        }
    }

    private static func substituteID(in value: ACPJSONValue, with idValue: ACPJSONValue) -> ACPJSONValue {
        switch value {
        case .string("$id"):
            return idValue
        case .array(let items):
            return .array(items.map { substituteID(in: $0, with: idValue) })
        case .object(let dict):
            return .object(dict.mapValues { substituteID(in: $0, with: idValue) })
        default:
            return value
        }
    }
}

/// Bounded-timeout reader over `AsyncStream<AgentEvent>`.
actor ACPEventStreamReader {
    private var buffered: [AgentEvent] = []
    private var isStreamEnded = false
    private var cursor = 0
    private var indexWaiters: [UUID: (Int, CheckedContinuation<AgentEvent?, Never>)] = [:]

    init(_ stream: AsyncStream<AgentEvent>) {
        Task {
            await self.drain(stream)
        }
    }

    private func drain(_ stream: AsyncStream<AgentEvent>) async {
        for await event in stream {
            let idx = buffered.count
            buffered.append(event)
            var toResume: [CheckedContinuation<AgentEvent?, Never>] = []
            for (waiterID, entry) in indexWaiters where entry.0 == idx {
                indexWaiters.removeValue(forKey: waiterID)
                toResume.append(entry.1)
            }
            for cont in toResume {
                cont.resume(returning: event)
            }
        }
        isStreamEnded = true
        let remaining = Array(indexWaiters.values)
        indexWaiters.removeAll()
        for (_, cont) in remaining {
            cont.resume(returning: nil)
        }
    }

    private func cancelIndexWaiter(_ id: UUID) {
        if let removed = indexWaiters.removeValue(forKey: id) {
            removed.1.resume(returning: nil)
        }
    }

    private func eventAt(_ index: Int) async -> AgentEvent? {
        if index < buffered.count {
            return buffered[index]
        }
        if isStreamEnded {
            return nil
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                if index < buffered.count {
                    cont.resume(returning: buffered[index])
                } else if isStreamEnded || Task.isCancelled {
                    cont.resume(returning: nil)
                } else {
                    indexWaiters[waiterID] = (index, cont)
                }
            }
        } onCancel: {
            Task { await self.cancelIndexWaiter(waiterID) }
        }
    }

    func next(
        timeout: TimeInterval = 3.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> AgentEvent? {
        let targetIndex = cursor
        cursor += 1
        return try await withACPTestTimeout(
            seconds: timeout,
            description: "next AgentEvent #\(targetIndex)",
            file: file,
            line: line
        ) {
            await self.eventAt(targetIndex)
        }
    }

    func collectUntilFinished(
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [AgentEvent] {
        var collected: [AgentEvent] = []
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                XCTFail("Timed out after \(timeout)s waiting for .finished event.", file: file, line: line)
                throw ACPTestTimeoutError.timedOut(description: "collectUntilFinished", seconds: timeout)
            }
            guard let event = try await next(timeout: remaining, file: file, line: line) else {
                return collected
            }
            collected.append(event)
            if case .finished = event {
                return collected
            }
        }
    }

    func collectAllUntilEnd(
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [AgentEvent] {
        var collected: [AgentEvent] = []
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                XCTFail("Timed out after \(timeout)s waiting for event stream end.", file: file, line: line)
                throw ACPTestTimeoutError.timedOut(description: "collectAllUntilEnd", seconds: timeout)
            }
            guard let event = try await next(timeout: remaining, file: file, line: line) else {
                return collected
            }
            collected.append(event)
        }
    }
}
