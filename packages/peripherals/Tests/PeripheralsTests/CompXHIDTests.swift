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

import XCTest

import CompXHID
import CompXProtocol

final class CompXHIDTests: XCTestCase {
    private func mouse(_ transport: MockTransport) -> GravaStarMouse {
        GravaStarMouse(transport: transport, timing: .zero, nonce: { [0xDE, 0xAD, 0xBE, 0xEF] })
    }

    func testHandshakeReadWriteOrderAndExactBytes() throws {
        let transport = MockTransport(replies: [
            Fixtures.handshakeWithID, Fixtures.readCyanWithID, Fixtures.ack(includesReportID: true),
        ])
        let device = mouse(transport)
        try device.handshake()
        let config = try device.readLighting()
        let red = LightingConfig(mode: .breathe, color: RGB(r: 255, g: 0, b: 0), speed: .seven, brightness: .nine)
        try device.writeLighting(red)

        XCTAssertEqual(config, Fixtures.cyan)
        XCTAssertEqual(transport.events, ["write cmd=1", "read", "write cmd=8", "read", "write cmd=7", "read"])
        XCTAssertTrue(transport.writes.allSatisfy { $0.reportID == 8 })
        XCTAssertEqual(transport.writes[0].payload, [1, 0, 0, 0, 8, 222, 173, 190, 239, 0, 0, 0, 0, 0, 0, 12])
        XCTAssertEqual(transport.writes[1].payload, [8, 0, 0, 160, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 155])
        XCTAssertEqual(transport.writes[2].payload, [7, 0, 0, 160, 7, 2, 255, 0, 0, 7, 9, 68, 0, 0, 0, 74])
    }

    func testReadWorksWithATransportThatOmitsTheReportID() throws {
        let transport = MockTransport(
            replies: [Fixtures.readCyanWithoutID, Fixtures.ack(includesReportID: false)], includesReportID: false)
        let device = mouse(transport)
        XCTAssertEqual(try device.readLighting(), Fixtures.cyan)
        XCTAssertNoThrow(try device.writeLighting(Fixtures.cyan))
    }

    func testWrongAckEchoIsNotAcknowledged() {
        let transport = MockTransport(replies: [Fixtures.readCyanWithID])
        XCTAssertThrowsError(try mouse(transport).writeLighting(Fixtures.cyan)) {
            XCTAssertEqual($0 as? CompXError, .notAcknowledged)
        }
    }

    func testNoAckAtAllIsNotAcknowledged() {
        XCTAssertThrowsError(try mouse(MockTransport()).writeLighting(Fixtures.cyan)) {
            XCTAssertEqual($0 as? CompXError, .notAcknowledged)
        }
    }

    func testShortReadIsMalformed() {
        let transport = MockTransport(replies: [[8, 8, 0, 0, 160, 10, 3]])
        XCTAssertThrowsError(try mouse(transport).readLighting()) {
            guard case .malformedResponse = $0 as? CompXError else { return XCTFail("got \($0)") }
        }
    }

    func testMissingReadReplyTimesOut() {
        XCTAssertThrowsError(try mouse(MockTransport()).readLighting()) {
            XCTAssertEqual($0 as? CompXError, .timeout)
        }
    }

    func testTracingTransportLogsHexAndPassesThrough() throws {
        let inner = MockTransport(replies: [Fixtures.readCyanWithID])
        var lines: [String] = []
        let traced = TracingTransport(wrapping: inner, log: { lines.append($0) })
        let device = GravaStarMouse(transport: traced, timing: .zero)
        XCTAssertEqual(try device.readLighting(), Fixtures.cyan)
        XCTAssertEqual(lines.first, "-> id=8 08 00 00 a0 0a 00 00 00 00 00 00 00 00 00 00 9b")
        XCTAssertEqual(lines.last, "<- (with id) 08 08 00 00 a0 0a 03 00 ff ff 05 07 48 01 54 08 e9")
    }

    func testPrototypeTimings() {
        XCTAssertEqual(Timing.prototype.afterHandshake, .milliseconds(20))
        XCTAssertEqual(Timing.prototype.afterRead, .milliseconds(30))
        XCTAssertEqual(Timing.prototype.afterWrite, .milliseconds(40))
    }
}
