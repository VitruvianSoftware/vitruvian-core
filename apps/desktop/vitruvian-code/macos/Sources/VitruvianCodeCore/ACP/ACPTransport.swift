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

/// Errors produced by `ACPTransport`.
public enum ACPTransportError: Error, Equatable, Sendable, LocalizedError {
    case rpcError(ACPRPCError)
    case requestTimedOut(method: String, seconds: TimeInterval)
    case connectionClosed(String)
    case tooManyMalformedLines(count: Int, lastPreview: String)
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .rpcError(let err):
            return err.message
        case .requestTimedOut(let method, let seconds):
            return "ACP request \(method) timed out after \(Int(seconds))s."
        case .connectionClosed(let reason):
            return reason
        case .tooManyMalformedLines(let count, let preview):
            return "ACP transport failed after \(count) consecutive malformed lines (last: \(preview))."
        case .encodingFailed(let detail):
            return "Failed to encode ACP payload: \(detail)"
        case .decodingFailed(let detail):
            return "Failed to decode ACP payload: \(detail)"
        }
    }
}

/// Newline-delimited JSON-RPC 2.0 transport over any byte stream pair.
public actor ACPTransport {
    /// 64 MiB maximum line length (`vitruvian-code-acp.md`, Interfaces).
    public static let defaultMaxLineBytes = 64 * 1024 * 1024
    /// Three malformed lines in a row fail the transport (`vitruvian-code-acp.md`, Interfaces).
    public static let defaultMaxConsecutiveMalformedLines = 3
    /// Matches T3 Code's `defaultSessionLoadTimeout = Duration.seconds(90)` (`AcpSessionRuntime.ts:81`).
    public static let defaultSessionSetupTimeout: TimeInterval = 90.0

    public typealias RequestHandler = @Sendable (String, ACPJSONValue?) async throws -> ACPJSONValue
    public typealias NotificationHandler = @Sendable (String, ACPJSONValue?) async -> Void
    public typealias FailureHandler = @Sendable (ACPTransportError) async -> Void
    public typealias LogHandler = @Sendable (String) -> Void

    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<ACPJSONValue, Error>
        let timeoutTask: Task<Void, Never>?
    }

    private let incoming: AsyncStream<Data>
    private let outgoing: @Sendable (Data) throws -> Void
    private let closeOutgoing: @Sendable () -> Void
    private let maxLineBytes: Int
    private let maxConsecutiveMalformedLines: Int

    private var requestHandler: RequestHandler?
    private var notificationHandler: NotificationHandler?
    private var failureHandler: FailureHandler?
    private var logHandler: LogHandler?

    private var readerTask: Task<Void, Never>?
    private var nextRequestID = 1
    private var pendingRequests: [ACPRPCID: PendingRequest] = [:]
    private var consecutiveMalformedLines = 0
    private var terminalError: ACPTransportError?
    private var isStarted = false

    public init(
        incoming: AsyncStream<Data>,
        outgoing: @escaping @Sendable (Data) throws -> Void,
        closeOutgoing: @escaping @Sendable () -> Void = {},
        maxLineBytes: Int = ACPTransport.defaultMaxLineBytes,
        maxConsecutiveMalformedLines: Int = ACPTransport.defaultMaxConsecutiveMalformedLines,
        onRequest: RequestHandler? = nil,
        onNotification: NotificationHandler? = nil,
        onFailure: FailureHandler? = nil,
        onLog: LogHandler? = nil
    ) {
        self.incoming = incoming
        self.outgoing = outgoing
        self.closeOutgoing = closeOutgoing
        self.maxLineBytes = maxLineBytes
        self.maxConsecutiveMalformedLines = maxConsecutiveMalformedLines
        self.requestHandler = onRequest
        self.notificationHandler = onNotification
        self.failureHandler = onFailure
        self.logHandler = onLog
    }

    /// Creates a transport reading from `input` off the main actor and writing to `output`.
    public static func overFileHandles(
        input: FileHandle,
        output: FileHandle,
        maxLineBytes: Int = ACPTransport.defaultMaxLineBytes,
        maxConsecutiveMalformedLines: Int = ACPTransport.defaultMaxConsecutiveMalformedLines,
        onRequest: RequestHandler? = nil,
        onNotification: NotificationHandler? = nil,
        onFailure: FailureHandler? = nil,
        onLog: LogHandler? = nil
    ) -> ACPTransport {
        let writer = AgentInput(output)
        let inputFD = input.fileDescriptor
        let stream = AsyncStream<Data> { continuation in
            Thread.detachNewThread {
                // Keep `input` alive until the reader finishes.
                withExtendedLifetime(input) {
                    var scratch = [UInt8](repeating: 0, count: 65_536)
                    while true {
                        let count = scratch.withUnsafeMutableBytes { rawBuffer -> Int in
                            guard let base = rawBuffer.baseAddress else { return 0 }
                            return Darwin.read(inputFD, base, rawBuffer.count)
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
                    try? input.close()
                }
                continuation.finish()
            }
        }
        return ACPTransport(
            incoming: stream,
            outgoing: { data in try writer.writeThrowing(data) },
            closeOutgoing: { writer.close() },
            maxLineBytes: maxLineBytes,
            maxConsecutiveMalformedLines: maxConsecutiveMalformedLines,
            onRequest: onRequest,
            onNotification: onNotification,
            onFailure: onFailure,
            onLog: onLog
        )
    }

    /// Configures handlers before `start()` begins draining incoming messages.
    public func setHandlers(
        onRequest: RequestHandler? = nil,
        onNotification: NotificationHandler? = nil,
        onFailure: FailureHandler? = nil,
        onLog: LogHandler? = nil
    ) {
        if let onRequest { self.requestHandler = onRequest }
        if let onNotification { self.notificationHandler = onNotification }
        if let onFailure { self.failureHandler = onFailure }
        if let onLog { self.logHandler = onLog }
    }

    /// Starts reading lines from the incoming byte stream.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let stream = self.incoming
        readerTask = Task {
            await self.consumeIncoming(stream)
        }
    }

    /// Closes the transport and fails every pending outgoing request with `.connectionClosed`.
    public func close(reason: String = "ACP connection closed") {
        let error = ACPTransportError.connectionClosed(reason)
        if terminalError == nil {
            terminalError = error
        }
        closeOutgoing()
        readerTask?.cancel()
        readerTask = nil
        failAllPending(with: terminalError ?? error)
    }

    /// Sends a raw JSON-RPC request and awaits its result or error.
    public func sendRequest(
        method: String,
        params: ACPJSONValue? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ACPJSONValue {
        if !isStarted {
            start()
        }
        if let terminalError {
            throw terminalError
        }

        let id = ACPRPCID.int(nextRequestID)
        nextRequestID += 1

        var envelope: [String: ACPJSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "method": .string(method),
        ]
        if let params {
            envelope["params"] = params
        }

        let lineData = try Self.encodeLine(.object(envelope))
        do {
            try outgoing(lineData)
        } catch {
            let closed = ACPTransportError.connectionClosed("ACP connection closed while sending \(method)")
            if terminalError == nil {
                terminalError = closed
            }
            failAllPending(with: closed)
            throw closed
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ACPJSONValue, Error>) in
                if let terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }
                let timeoutTask: Task<Void, Never>?
                if let timeout, timeout > 0 {
                    let nanos = UInt64(max(1.0, timeout * 1_000_000_000))
                    timeoutTask = Task {
                        try? await Task.sleep(nanoseconds: nanos)
                        guard !Task.isCancelled else { return }
                        self.expireRequest(id: id, method: method, seconds: timeout)
                    }
                } else {
                    timeoutTask = nil
                }
                pendingRequests[id] = PendingRequest(
                    method: method,
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaitingRequest(id: id)
            }
        }
    }

    /// Sends a typed Codable JSON-RPC request and decodes the result.
    public func request<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        method: String,
        params: Params,
        timeout: TimeInterval? = nil,
        as resultType: Result.Type = Result.self
    ) async throws -> Result {
        let encodedParams = try ACPJSONValue.fromEncodable(params)
        let rawResult = try await sendRequest(method: method, params: encodedParams, timeout: timeout)
        do {
            return try rawResult.decode(Result.self)
        } catch {
            throw ACPTransportError.decodingFailed("\(method): \(error.localizedDescription)")
        }
    }

    /// Sends a JSON-RPC notification (no `id`, no reply).
    public func sendNotification(method: String, params: ACPJSONValue? = nil) throws {
        if let terminalError {
            throw terminalError
        }
        var envelope: [String: ACPJSONValue] = [
            "jsonrpc": .string("2.0"),
            "method": .string(method),
        ]
        if let params {
            envelope["params"] = params
        }
        let lineData = try Self.encodeLine(.object(envelope))
        do {
            try outgoing(lineData)
        } catch {
            throw ACPTransportError.connectionClosed("ACP connection closed while notifying \(method)")
        }
    }

    /// Sends a typed Codable JSON-RPC notification.
    public func notify<Params: Encodable & Sendable>(method: String, params: Params) throws {
        let encodedParams = try ACPJSONValue.fromEncodable(params)
        try sendNotification(method: method, params: encodedParams)
    }

    // MARK: - Framing & Dispatch

    private func consumeIncoming(_ stream: AsyncStream<Data>) async {
        var buffer = Data()
        var droppingOversizedLine = false
        var droppedByteCount = 0

        for await chunk in stream {
            if Task.isCancelled || terminalError != nil {
                break
            }
            var cursor = chunk.startIndex
            while cursor < chunk.endIndex {
                if droppingOversizedLine {
                    if let newline = chunk[cursor...].firstIndex(of: 0x0A) {
                        droppedByteCount += chunk.distance(from: cursor, to: newline)
                        let totalBytes = droppedByteCount
                        droppingOversizedLine = false
                        droppedByteCount = 0
                        cursor = chunk.index(after: newline)
                        let stop = await recordMalformedLine(
                            reason: "line exceeded \(maxLineBytes) byte limit (\(totalBytes) bytes)"
                        )
                        if stop { return }
                    } else {
                        droppedByteCount += chunk.distance(from: cursor, to: chunk.endIndex)
                        break
                    }
                    continue
                }

                if let newline = chunk[cursor...].firstIndex(of: 0x0A) {
                    let segmentCount = chunk.distance(from: cursor, to: newline)
                    let totalCount = buffer.count + segmentCount
                    if totalCount > maxLineBytes {
                        buffer.removeAll(keepingCapacity: false)
                        cursor = chunk.index(after: newline)
                        let stop = await recordMalformedLine(
                            reason: "line exceeded \(maxLineBytes) byte limit (\(totalCount) bytes)"
                        )
                        if stop { return }
                        continue
                    }

                    var lineData: Data
                    if buffer.isEmpty {
                        lineData = Data(chunk[cursor..<newline])
                    } else {
                        lineData = buffer
                        buffer.removeAll(keepingCapacity: true)
                        lineData.append(contentsOf: chunk[cursor..<newline])
                    }
                    if lineData.last == 0x0D {
                        lineData.removeLast()
                    }
                    cursor = chunk.index(after: newline)
                    let stop = await processLine(lineData)
                    if stop { return }
                } else {
                    let remainingCount = chunk.distance(from: cursor, to: chunk.endIndex)
                    if buffer.count + remainingCount > maxLineBytes {
                        droppedByteCount = buffer.count + remainingCount
                        buffer.removeAll(keepingCapacity: false)
                        droppingOversizedLine = true
                    } else {
                        buffer.append(contentsOf: chunk[cursor...])
                    }
                    break
                }
            }
        }

        if terminalError == nil {
            if droppingOversizedLine {
                _ = await recordMalformedLine(
                    reason: "line exceeded \(maxLineBytes) byte limit (\(droppedByteCount) bytes before EOF)"
                )
            } else if !buffer.isEmpty {
                if buffer.last == 0x0D {
                    buffer.removeLast()
                }
                _ = await processLine(buffer)
            }
        }

        if terminalError == nil {
            let closed = ACPTransportError.connectionClosed("ACP connection closed")
            terminalError = closed
            failAllPending(with: closed)
        }
    }

    /// Processes a single newline-stripped line. Returns `true` when the transport has terminally failed.
    private func processLine(_ lineData: Data) async -> Bool {
        let isAllWhitespace = lineData.allSatisfy { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0D || byte == 0x0A
        }
        if isAllWhitespace {
            return false
        }

        let decoded: ACPJSONValue
        do {
            decoded = try JSONDecoder().decode(ACPJSONValue.self, from: lineData)
        } catch {
            let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
            return await recordMalformedLine(reason: "invalid JSON: \(preview)")
        }

        guard case .object(let obj) = decoded,
              obj["jsonrpc"]?.stringValue == "2.0" else {
            let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
            return await recordMalformedLine(reason: "not a JSON-RPC 2.0 object: \(preview)")
        }

        let hasMethod = obj["method"] != nil
        let methodString = obj["method"]?.stringValue

        if hasMethod {
            guard let method = methodString, !method.isEmpty else {
                let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
                return await recordMalformedLine(reason: "invalid JSON-RPC method: \(preview)")
            }

            if let rawID = obj["id"], rawID != .null {
                guard let id = ACPRPCID(jsonValue: rawID) else {
                    let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
                    return await recordMalformedLine(reason: "invalid JSON-RPC request id: \(preview)")
                }
                consecutiveMalformedLines = 0
                let params = obj["params"]
                Task {
                    await self.handleIncomingRequest(id: id, method: method, params: params)
                }
                return false
            } else {
                consecutiveMalformedLines = 0
                if let notificationHandler {
                    await notificationHandler(method, obj["params"])
                }
                return false
            }
        }

        // Response envelope: requires a valid id and exclusively result or error.
        guard let rawID = obj["id"], let id = ACPRPCID(jsonValue: rawID) else {
            let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
            return await recordMalformedLine(reason: "missing or invalid JSON-RPC response id: \(preview)")
        }

        let hasResult = obj["result"] != nil
        let hasError = obj["error"] != nil
        guard hasResult != hasError else {
            let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
            return await recordMalformedLine(reason: "JSON-RPC response must have result or error: \(preview)")
        }

        if let rawError = obj["error"] {
            guard let rpcError = try? rawError.decode(ACPRPCError.self) else {
                let preview = String(decoding: lineData.prefix(120), as: UTF8.self)
                return await recordMalformedLine(reason: "malformed JSON-RPC error object: \(preview)")
            }
            consecutiveMalformedLines = 0
            if let pending = pendingRequests.removeValue(forKey: id) {
                pending.timeoutTask?.cancel()
                pending.continuation.resume(throwing: ACPTransportError.rpcError(rpcError))
            }
            return false
        }

        consecutiveMalformedLines = 0
        let resultValue = obj["result"] ?? .null
        if let pending = pendingRequests.removeValue(forKey: id) {
            pending.timeoutTask?.cancel()
            pending.continuation.resume(returning: resultValue)
        }
        return false
    }

    private func recordMalformedLine(reason: String) async -> Bool {
        consecutiveMalformedLines += 1
        logHandler?("ACP malformed line (\(consecutiveMalformedLines)/\(maxConsecutiveMalformedLines)): \(reason)")
        guard consecutiveMalformedLines >= maxConsecutiveMalformedLines else {
            return false
        }
        let failure = ACPTransportError.tooManyMalformedLines(
            count: consecutiveMalformedLines,
            lastPreview: reason
        )
        terminalError = failure
        closeOutgoing()
        failAllPending(with: failure)
        if let failureHandler {
            await failureHandler(failure)
        }
        return true
    }

    private func handleIncomingRequest(id: ACPRPCID, method: String, params: ACPJSONValue?) async {
        guard terminalError == nil else { return }
        guard let requestHandler else {
            sendIncomingError(
                id: id,
                error: ACPRPCError(
                    code: ACPRPCError.methodNotFound,
                    message: "Method not found: \(method)"
                )
            )
            return
        }

        do {
            let result = try await requestHandler(method, params)
            sendIncomingResult(id: id, result: result)
        } catch let rpcError as ACPRPCError {
            sendIncomingError(id: id, error: rpcError)
        } catch {
            sendIncomingError(
                id: id,
                error: ACPRPCError(
                    code: ACPRPCError.internalError,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func sendIncomingResult(id: ACPRPCID, result: ACPJSONValue) {
        guard terminalError == nil else { return }
        let envelope: ACPJSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "result": result,
        ])
        if let data = try? Self.encodeLine(envelope) {
            try? outgoing(data)
        }
    }

    private func sendIncomingError(id: ACPRPCID, error: ACPRPCError) {
        guard terminalError == nil else { return }
        var errorObj: [String: ACPJSONValue] = [
            "code": .int(error.code),
            "message": .string(error.message),
        ]
        if let data = error.data {
            errorObj["data"] = data
        }
        let envelope: ACPJSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": id.jsonValue,
            "error": .object(errorObj),
        ])
        if let line = try? Self.encodeLine(envelope) {
            try? outgoing(line)
        }
    }

    private func expireRequest(id: ACPRPCID, method: String, seconds: TimeInterval) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.continuation.resume(
            throwing: ACPTransportError.requestTimedOut(method: method, seconds: seconds)
        )
    }

    private func cancelWaitingRequest(id: ACPRPCID) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        pending.timeoutTask?.cancel()
        pending.continuation.resume(throwing: CancellationError())
    }

    private func failAllPending(with error: ACPTransportError) {
        let all = pendingRequests
        pendingRequests.removeAll()
        for (_, pending) in all {
            pending.timeoutTask?.cancel()
            pending.continuation.resume(throwing: error)
        }
    }

    private static func encodeLine(_ value: ACPJSONValue) throws -> Data {
        do {
            let encoder = JSONEncoder()
            var data = try encoder.encode(value)
            data.append(0x0A)
            return data
        } catch {
            throw ACPTransportError.encodingFailed(error.localizedDescription)
        }
    }
}
