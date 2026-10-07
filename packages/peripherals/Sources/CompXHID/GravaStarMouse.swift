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

import CompXProtocol
import Foundation

/// The pauses the proven Python prototype makes after each request. Tests
/// use `.zero`; real hardware uses `.prototype`.
public struct Timing: Equatable, Sendable {
    public var afterHandshake: Duration
    public var afterRead: Duration
    public var afterWrite: Duration
    /// How long to wait for a reply before giving up.
    public var replyTimeout: Duration

    public init(afterHandshake: Duration, afterRead: Duration, afterWrite: Duration, replyTimeout: Duration) {
        self.afterHandshake = afterHandshake
        self.afterRead = afterRead
        self.afterWrite = afterWrite
        self.replyTimeout = replyTimeout
    }

    public static let prototype = Timing(
        afterHandshake: .milliseconds(20), afterRead: .milliseconds(30),
        afterWrite: .milliseconds(40), replyTimeout: .seconds(1)
    )
    public static let zero = Timing(afterHandshake: .zero, afterRead: .zero, afterWrite: .zero, replyTimeout: .zero)
}

/// A GravaStar mouse: handshake, read and write its lighting.
public final class GravaStarMouse {
    public let transport: HIDTransport
    public let timing: Timing
    private let makeNonce: () -> [UInt8]

    public init(transport: HIDTransport, timing: Timing = .prototype,
                nonce: @escaping () -> [UInt8] = { (0..<4).map { _ in UInt8.random(in: 0...255) } }) {
        self.transport = transport
        self.timing = timing
        makeNonce = nonce
    }

    /// Opens the attached mouse over IOKit and performs the handshake.
    /// Throws `CompXError.deviceNotFound` when none is attached.
    public static func open(timing: Timing = .prototype, trace: ((String) -> Void)? = nil) throws -> GravaStarMouse {
        var transport: HIDTransport = try IOKitHIDTransport()
        if let trace { transport = TracingTransport(wrapping: transport, log: trace) }
        let mouse = GravaStarMouse(transport: transport, timing: timing)
        do {
            try mouse.handshake()
        } catch {
            mouse.close()
            throw error
        }
        return mouse
    }

    /// Whether a mouse is attached, without opening it.
    public static func isConnected() -> Bool { IOKitHIDTransport.isPresent() }

    /// Sends the nonce the device wants first, then reads and discards its reply.
    public func handshake() throws {
        try send(Requests.handshake(nonce: makeNonce()))
        pause(timing.afterHandshake)
        _ = try transport.read(timeout: timing.replyTimeout)
    }

    public func readLighting() throws -> LightingConfig {
        try send(Requests.readLighting())
        pause(timing.afterRead)
        let reply = try transport.read(timeout: timing.replyTimeout)
        return try Responses.parseReadLighting(reply, includesReportID: transport.reportsIncludeReportID)
    }

    /// Writes the record. Throws `notAcknowledged` unless the reply echoes command 7.
    public func writeLighting(_ config: LightingConfig) throws {
        try send(Requests.writeLighting(config))
        pause(timing.afterWrite)
        let reply: [UInt8]
        do {
            reply = try transport.read(timeout: timing.replyTimeout)
        } catch CompXError.timeout {
            throw CompXError.notAcknowledged
        }
        guard Responses.isWriteAck(reply, includesReportID: transport.reportsIncludeReportID) else {
            throw CompXError.notAcknowledged
        }
    }

    public func close() { transport.close() }

    private func send(_ frame: Frame) throws {
        try transport.write(reportID: CompXDevice.reportID, payload: frame.payload)
    }

    private func pause(_ duration: Duration) {
        guard duration > .zero else { return }
        Thread.sleep(forTimeInterval: duration.timeInterval)
    }
}
