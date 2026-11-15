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

final class ACPTransportTests: XCTestCase {
    private final class Recorder: Sendable {
        private struct State {
            var sentLines: [ACPJSONValue] = []
            var notifications: [(String, ACPJSONValue?)] = []
            var failures: [ACPTransportError] = []
            var logs: [String] = []
            var sentWaiters: [UUID: (Int, CheckedContinuation<ACPJSONValue?, Never>)] = [:]
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        func recordOutgoing(_ data: Data) {
            let text = String(decoding: data, as: UTF8.self)
            let decodedLines: [ACPJSONValue] = text.split(separator: "\n").compactMap { line in
                try? JSONDecoder().decode(ACPJSONValue.self, from: Data(line.utf8))
            }
            guard !decodedLines.isEmpty else { return }

            let toResume: [(CheckedContinuation<ACPJSONValue?, Never>, ACPJSONValue)] = state.withLock { s in
                var ready: [(CheckedContinuation<ACPJSONValue?, Never>, ACPJSONValue)] = []
                for decoded in decodedLines {
                    let idx = s.sentLines.count
                    s.sentLines.append(decoded)
                    for (waiterID, entry) in s.sentWaiters where entry.0 == idx {
                        s.sentWaiters.removeValue(forKey: waiterID)
                        ready.append((entry.1, decoded))
                    }
                }
                return ready
            }
            for (cont, value) in toResume {
                cont.resume(returning: value)
            }
        }

        private func cancelWaiter(_ id: UUID) {
            let removed = state.withLock { s in
                s.sentWaiters.removeValue(forKey: id)?.1
            }
            removed?.resume(returning: nil)
        }

        func waitOutgoing(at index: Int) async -> ACPJSONValue {
            if let existing = state.withLock({ index < $0.sentLines.count ? $0.sentLines[index] : nil }) {
                return existing
            }
            let waiterID = UUID()
            let result = await withTaskCancellationHandler {
                await withCheckedContinuation { (cont: CheckedContinuation<ACPJSONValue?, Never>) in
                    let immediate: ( Bool, ACPJSONValue? ) = state.withLock { s in
                        if index < s.sentLines.count {
                            return (true, s.sentLines[index])
                        }
                        if Task.isCancelled {
                            return (true, nil)
                        }
                        s.sentWaiters[waiterID] = (index, cont)
                        return (false, nil)
                    }
                    if immediate.0 {
                        cont.resume(returning: immediate.1)
                    }
                }
            } onCancel: {
                self.cancelWaiter(waiterID)
            }
            return result ?? .null
        }

        func recordNotification(_ method: String, _ params: ACPJSONValue?) {
            state.withLock { $0.notifications.append((method, params)) }
        }

        func recordFailure(_ error: ACPTransportError) {
            state.withLock { $0.failures.append(error) }
        }

        func recordLog(_ line: String) {
            state.withLock { $0.logs.append(line) }
        }

        func snapshot() -> (
            notifications: [(String, ACPJSONValue?)],
            failures: [ACPTransportError],
            logs: [String]
        ) {
            state.withLock { ($0.notifications, $0.failures, $0.logs) }
        }
    }

    func testDefaultConstantsMatchDesignAndT3Code() {
        XCTAssertEqual(ACPTransport.defaultMaxLineBytes, 64 * 1024 * 1024)
        XCTAssertEqual(ACPTransport.defaultMaxConsecutiveMalformedLines, 3)
        XCTAssertEqual(ACPTransport.defaultSessionSetupTimeout, 90.0)
    }

    func testMessageSplitAcrossReadsReassemblesIncludingMultiByteUTF8() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            }
        )

        let requestTask = Task {
            try await transport.sendRequest(
                method: "initialize",
                params: .object(["protocolVersion": .int(1)]),
                timeout: 2.0
            )
        }

        let sent = try await withACPTestTimeout(seconds: 2.0) {
            await recorder.waitOutgoing(at: 0)
        }
        let id = sent.objectValue?["id"]?.intValue ?? -1
        XCTAssertEqual(id, 1)

        let fullLine = Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{\"greeting\":\"héllo 🚀\"}}\n".utf8)
        // Split right inside multi-byte UTF-8 sequences and JSON tokens.
        let cuts = [0, 7, 19, 38, 46, 51, fullLine.count]
        for idx in 0..<(cuts.count - 1) {
            try incoming.write(Data(fullLine[cuts[idx]..<cuts[idx + 1]]))
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        let result = try await withACPTestTimeout(seconds: 2.0) {
            try await requestTask.value
        }
        XCTAssertEqual(result.objectValue?["greeting"]?.stringValue, "héllo 🚀")
        await transport.close()
    }

    func testSeveralMessagesInSingleReadDispatchResponsesAndNotificationsInOrder() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            },
            onNotification: { method, params in
                recorder.recordNotification(method, params)
            }
        )

        let req1 = Task { try await transport.sendRequest(method: "m1", timeout: 2.0) }
        let out0 = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }
        XCTAssertEqual(out0.objectValue?["method"]?.stringValue, "m1")

        let req2 = Task { try await transport.sendRequest(method: "m2", timeout: 2.0) }
        let out1 = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 1) }
        XCTAssertEqual(out1.objectValue?["method"]?.stringValue, "m2")

        let combined = [
            #"{"jsonrpc":"2.0","method":"session/update","params":{"seq":1}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{"ok":"one"}}"#,
            #"{"jsonrpc":"2.0","method":"session/update","params":{"seq":2}}"# + "\r",
            #"{"jsonrpc":"2.0","id":2,"result":{"ok":"two"}}"#,
        ].joined(separator: "\n") + "\n"

        try incoming.write(Data(combined.utf8))

        let res1 = try await withACPTestTimeout(seconds: 2.0) { try await req1.value }
        let res2 = try await withACPTestTimeout(seconds: 2.0) { try await req2.value }
        XCTAssertEqual(res1.objectValue?["ok"]?.stringValue, "one")
        XCTAssertEqual(res2.objectValue?["ok"]?.stringValue, "two")

        let snap = recorder.snapshot()
        XCTAssertEqual(snap.notifications.count, 2)
        XCTAssertEqual(snap.notifications[0].1?.objectValue?["seq"]?.intValue, 1)
        XCTAssertEqual(snap.notifications[1].1?.objectValue?["seq"]?.intValue, 2)
        await transport.close()
    }

    func testLineOverByteLimitIsDroppedCountsAsMalformedAndNextLineStillWorks() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            },
            maxLineBytes: 128,
            onFailure: { err in
                recorder.recordFailure(err)
            },
            onLog: { line in
                recorder.recordLog(line)
            }
        )

        let req = Task { try await transport.sendRequest(method: "ping", timeout: 2.0) }
        _ = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }

        // Stream an oversized line across multiple chunks without a newline, then finish it, then send a valid reply.
        let chunkA = String(repeating: "x", count: 90)
        let chunkB = String(repeating: "y", count: 90) + "\n"
        try incoming.write(Data(chunkA.utf8))
        try incoming.write(Data(chunkB.utf8))
        try incoming.writeLine(#"{"jsonrpc":"2.0","id":1,"result":{"pong":true}}"#)

        let res = try await withACPTestTimeout(seconds: 2.0) { try await req.value }
        XCTAssertEqual(res.objectValue?["pong"]?.boolValue, true)

        let snap = recorder.snapshot()
        XCTAssertTrue(snap.failures.isEmpty, "One oversized line must not fail the transport")
        XCTAssertTrue(snap.logs.contains { $0.contains("1/3") && $0.contains("exceeded 128 byte limit") })
        await transport.close()
    }

    func testTwoMalformedLinesAreSkippedValidLineResetsCountAndThirdInARowFailsTransport() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            },
            onNotification: { method, params in
                recorder.recordNotification(method, params)
            },
            onFailure: { err in
                recorder.recordFailure(err)
            },
            onLog: { line in
                recorder.recordLog(line)
            }
        )
        await transport.start()

        // Two malformed lines followed by a valid notification resets the consecutive streak.
        try incoming.writeLine("not-json-at-all")
        try incoming.writeLine(#"{"hello":"missing-jsonrpc"}"#)
        try incoming.writeLine(#"{"jsonrpc":"2.0","method":"session/update","params":{"ok":true}}"#)

        let pending = Task {
            try await transport.sendRequest(method: "session/prompt", params: .object([:]), timeout: nil)
        }
        _ = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }

        // Now send three consecutive malformed lines: the third fails the transport and the pending request.
        try incoming.writeLine("{broken-1")
        try incoming.writeLine("{broken-2")
        try incoming.writeLine("{broken-3")

        do {
            _ = try await withACPTestTimeout(seconds: 2.0) { try await pending.value }
            XCTFail("Expected pending request to fail after 3 consecutive malformed lines")
        } catch let error as ACPTransportError {
            guard case .tooManyMalformedLines(let count, _) = error else {
                XCTFail("Unexpected transport error: \(error)")
                return
            }
            XCTAssertEqual(count, 3)
        }

        let snap = recorder.snapshot()
        XCTAssertEqual(snap.notifications.count, 1)
        XCTAssertEqual(snap.failures.count, 1)
    }

    func testJSONRPCErrorObjectMapsToTypedSwiftErrorKeepingCodeMessageAndData() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            }
        )

        let req = Task {
            try await transport.sendRequest(method: "session/load", params: .object(["sessionId": .string("s1")]), timeout: 2.0)
        }
        _ = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }

        try incoming.writeLine(
            #"{"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"Session not found","data":{"sessionId":"s1","retryable":false}}}"#
        )

        do {
            _ = try await withACPTestTimeout(seconds: 2.0) { try await req.value }
            XCTFail("Expected JSON-RPC error to throw")
        } catch let ACPTransportError.rpcError(rpcError) {
            XCTAssertEqual(rpcError.code, -32042)
            XCTAssertEqual(rpcError.message, "Session not found")
            XCTAssertEqual(
                rpcError.data,
                .object(["sessionId": .string("s1"), "retryable": .bool(false)])
            )
        }
        await transport.close()
    }

    func testPerRequestTimeoutExpiresWhileUntimedPromptWaitsForCompletion() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            }
        )

        // Start the untimed prompt first and record its actual request id so it is guaranteed
        // to be pending in the transport while the timed `session/load` request expires.
        let untimedPromptTask = Task {
            try await transport.sendRequest(method: "session/prompt", timeout: nil)
        }
        let promptSent = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }
        XCTAssertEqual(promptSent.objectValue?["method"]?.stringValue, "session/prompt")
        let promptID = try XCTUnwrap(promptSent.objectValue?["id"]?.intValue)

        let timedTask = Task {
            try await transport.sendRequest(method: "session/load", timeout: 0.08)
        }
        let loadSent = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 1) }
        XCTAssertEqual(loadSent.objectValue?["method"]?.stringValue, "session/load")
        let loadID = try XCTUnwrap(loadSent.objectValue?["id"]?.intValue)
        XCTAssertNotEqual(promptID, loadID)

        do {
            _ = try await withACPTestTimeout(seconds: 2.0) { try await timedTask.value }
            XCTFail("Expected timed request to time out")
        } catch let ACPTransportError.requestTimedOut(method, seconds) {
            XCTAssertEqual(method, "session/load")
            XCTAssertEqual(seconds, 0.08, accuracy: 0.001)
        }

        // Late reply for the expired `session/load` request is ignored without affecting `session/prompt`.
        try incoming.writeLine(#"{"jsonrpc":"2.0","id":\#(loadID),"result":{}}"#)

        // Wait longer than the timed request's timeout, then answer the untimed prompt request by its recorded id.
        try await Task.sleep(nanoseconds: 120_000_000)
        try incoming.writeLine(#"{"jsonrpc":"2.0","id":\#(promptID),"result":{"stopReason":"end_turn"}}"#)

        let promptReply = try await withACPTestTimeout(seconds: 2.0) { try await untimedPromptTask.value }
        XCTAssertEqual(promptReply.objectValue?["stopReason"]?.stringValue, "end_turn")
        await transport.close()
    }

    func testPendingRequestsFailWithConnectionClosedWhenStreamEnds() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            }
        )

        let req1 = Task { try await transport.sendRequest(method: "initialize", timeout: 5.0) }
        _ = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }
        let req2 = Task { try await transport.sendRequest(method: "session/prompt", timeout: nil) }
        _ = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 1) }

        // Simulate agent process exiting and closing its stdout pipe.
        incoming.finish()

        for task in [req1, req2] {
            do {
                _ = try await withACPTestTimeout(seconds: 2.0) { try await task.value }
                XCTFail("Expected pending request to fail with connectionClosed")
            } catch let ACPTransportError.connectionClosed(reason) {
                XCTAssertTrue(reason.localizedCaseInsensitiveContains("closed"))
            }
        }
    }

    func testIncomingAgentRequestsReturnHandlerResultOrTypedRPCError() async throws {
        let incoming = InMemoryBytePipe()
        let recorder = Recorder()
        let transport = ACPTransport(
            incoming: incoming.stream,
            outgoing: { data in
                recorder.recordOutgoing(data)
            },
            onRequest: { method, params in
                if method == "fs/read_text_file" {
                    let path = params?.objectValue?["path"]?.stringValue ?? ""
                    return .object(["content": .string("read:\(path)")])
                }
                throw ACPRPCError(code: ACPRPCError.methodNotFound, message: "Method not found: \(method)")
            }
        )
        await transport.start()

        try incoming.writeLine(#"{"jsonrpc":"2.0","id":"agent-1","method":"fs/read_text_file","params":{"path":"a.txt"}}"#)
        let firstReply = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 0) }
        XCTAssertEqual(firstReply.objectValue?["id"]?.stringValue, "agent-1")
        XCTAssertEqual(firstReply.objectValue?["result"]?.objectValue?["content"]?.stringValue, "read:a.txt")

        try incoming.writeLine(#"{"jsonrpc":"2.0","id":99,"method":"fs/write_text_file","params":{}}"#)
        let secondReply = try await withACPTestTimeout(seconds: 2.0) { await recorder.waitOutgoing(at: 1) }
        XCTAssertEqual(secondReply.objectValue?["id"]?.intValue, 99)
        XCTAssertEqual(secondReply.objectValue?["error"]?.objectValue?["code"]?.intValue, ACPRPCError.methodNotFound)
        await transport.close()
    }
}
