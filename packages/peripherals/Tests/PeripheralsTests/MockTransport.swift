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

import CompXHID
import CompXProtocol

/// A scripted transport: hands back queued replies in order and records every
/// write, so tests assert the exact bytes and call order.
final class MockTransport: HIDTransport {
    var reportsIncludeReportID: Bool
    var replies: [[UInt8]]
    private(set) var writes: [(reportID: UInt8, payload: [UInt8])] = []
    private(set) var events: [String] = []
    private(set) var closeCount = 0

    init(replies: [[UInt8]] = [], includesReportID: Bool = true) {
        self.replies = replies
        reportsIncludeReportID = includesReportID
    }

    func write(reportID: UInt8, payload: [UInt8]) throws {
        writes.append((reportID, payload))
        events.append("write cmd=\(payload.first ?? 0)")
    }

    func read(timeout: Duration) throws -> [UInt8] {
        events.append("read")
        guard !replies.isEmpty else { throw CompXError.timeout }
        return replies.removeFirst()
    }

    func close() { closeCount += 1 }

    /// The commands written so far, in order.
    var commands: [UInt8] { writes.map { $0.payload[0] } }
}

/// Replies the real device sends, in both shapes.
enum Fixtures {
    /// Captured from the mouse on 2026-10-07 via hidapi (report ID first):
    /// read-lighting reply, fixed cyan, speed 5, brightness 7.
    static let readCyanWithID: [UInt8] = [8, 8, 0, 0, 160, 10, 3, 0, 255, 255, 5, 7, 72, 1, 84, 8, 233]
    static var readCyanWithoutID: [UInt8] { Array(readCyanWithID.dropFirst()) }
    /// Captured handshake reply (its content is ignored).
    static let handshakeWithID: [UInt8] = [8, 1, 0, 0, 0, 8, 21, 8, 13, 17, 18, 1, 2, 0, 0, 0, 244]

    static func ack(includesReportID: Bool) -> [UInt8] {
        let payload: [UInt8] = [7, 0, 0, 160, 7] + [UInt8](repeating: 0, count: 11)
        return includesReportID ? [8] + payload : payload
    }

    /// A well-formed read reply for any config, in either shape.
    static func readReply(_ config: LightingConfig, includesReportID: Bool = true) -> [UInt8] {
        var payload: [UInt8] = [8, 0, 0, 160, 10] + config.encodeRecord() + [0, 0, 0]
        payload.append(Checksum.outer(reportID: 8, payloadPrefix: payload))
        return includesReportID ? [8] + payload : payload
    }

    static let cyan = LightingConfig(mode: .fixed, color: RGB(r: 0, g: 255, b: 255), speed: .five, brightness: .seven)
}
