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

import CompXProtocol

/// Golden bytes come from running the Python prototype's own functions
/// (~/.dotfile/bin/gravastar-mouse) and from a reply captured on hardware.
final class CompXProtocolTests: XCTestCase {
    func testReadLightingFrameMatchesPrototype() {
        XCTAssertEqual(
            Requests.readLighting().encode(),
            [8, 8, 0, 0, 0xA0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 155])
    }

    func testWriteFixedCyanFrameMatchesPrototype() {
        let cyan = LightingConfig(mode: .fixed, color: RGB(r: 0, g: 255, b: 255), speed: .five, brightness: .seven)
        XCTAssertEqual(
            Requests.writeLighting(cyan).encode(),
            [8, 7, 0, 0, 160, 7, 3, 0, 255, 255, 5, 7, 72, 0, 0, 0, 74])
    }

    func testWriteRedBreatheAndOffFramesMatchPrototype() {
        let red = LightingConfig(mode: .breathe, color: RGB(r: 255, g: 0, b: 0), speed: .seven, brightness: .nine)
        XCTAssertEqual(Requests.writeLighting(red).encode(), [8, 7, 0, 0, 160, 7, 2, 255, 0, 0, 7, 9, 68, 0, 0, 0, 74])
        let off = LightingConfig(mode: .off, color: .black, speed: .zero, brightness: .zero)
        XCTAssertEqual(Requests.writeLighting(off).encode(), [8, 7, 0, 0, 160, 7, 0, 0, 0, 0, 0, 0, 85, 0, 0, 0, 74])
    }

    func testHandshakeFrameWithFixedNonce() {
        let frame = Requests.handshake(nonce: [0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(frame.encode(), [8, 1, 0, 0, 0, 8, 222, 173, 190, 239, 0, 0, 0, 0, 0, 0, 12])
    }

    func testPayloadIsSixteenBytesWithoutReportID() {
        let payload = Requests.readLighting().payload
        XCTAssertEqual(payload.count, 16)
        XCTAssertEqual(payload[0], 8, "payload starts with the command, not the report ID")
    }

    func testInnerRecordCRC() {
        let cyan = LightingConfig(mode: .fixed, color: RGB(r: 0, g: 255, b: 255), speed: .five, brightness: .seven)
        XCTAssertEqual(cyan.encodeRecord(), [3, 0, 255, 255, 5, 7, 72])
        XCTAssertEqual(Checksum.inner([3, 0, 255, 255, 5, 7] as [UInt8]), 72)
    }

    func testOuterCRCInvariantHoldsForEveryRequest() {
        var frames = [Requests.readLighting(), Requests.handshake(nonce: [1, 2, 3, 4])]
        for mode in LightingMode.allCases {
            frames.append(Requests.writeLighting(
                LightingConfig(mode: mode, color: RGB(r: 12, g: 200, b: 99), speed: .nine, brightness: .zero)))
        }
        for frame in frames {
            let sum = frame.encode().reduce(UInt8(0), &+)
            XCTAssertEqual(sum, 0x55, "report ID + 16 payload bytes must sum to 0x55 for \(frame)")
        }
    }

    func testParseCapturedReplyWithReportID() throws {
        let config = try Responses.parseReadLighting(
            [8, 8, 0, 0, 0xA0, 10, 3, 0, 255, 255, 5, 7, 72, 1, 84, 8, 233], includesReportID: true)
        XCTAssertEqual(config.mode, .fixed)
        XCTAssertEqual(config.color, RGB(r: 0, g: 255, b: 255))
        XCTAssertEqual(config.speed, .five)
        XCTAssertEqual(config.brightness, .seven)
    }

    func testParseCapturedReplyWithoutReportID() throws {
        let config = try Responses.parseReadLighting(
            [8, 0, 0, 0xA0, 10, 3, 0, 255, 255, 5, 7, 72, 1, 84, 8, 233], includesReportID: false)
        XCTAssertEqual(config, LightingConfig(mode: .fixed, color: RGB(r: 0, g: 255, b: 255), speed: .five, brightness: .seven))
    }

    func testParseWithWrongShapeFlagFails() {
        // The off-by-one this flag exists to prevent: reading an ID-less buffer
        // as if it had the ID must fail loudly, not decode garbage.
        let withoutID: [UInt8] = [8, 0, 0, 0xA0, 10, 3, 0, 255, 255, 5, 7, 72, 1, 84, 8, 233]
        XCTAssertThrowsError(try Responses.parseReadLighting(withoutID, includesReportID: true))
        let withID: [UInt8] = [8, 8, 0, 0, 0xA0, 10, 3, 0, 255, 255, 5, 7, 72, 1, 84, 8, 233]
        XCTAssertThrowsError(try Responses.parseReadLighting(withID, includesReportID: false))
    }

    func testParseRejectsCorruptedChecksums() {
        var outer: [UInt8] = [8, 8, 0, 0, 0xA0, 10, 3, 0, 255, 255, 5, 7, 72, 1, 84, 8, 233]
        outer[16] = 0
        XCTAssertThrowsError(try Responses.parseReadLighting(outer, includesReportID: true)) {
            XCTAssertEqual($0 as? CompXError, .badCRC)
        }
        XCTAssertThrowsError(try LightingConfig.decode(record: [3, 0, 255, 255, 5, 7, 0] as [UInt8])) {
            XCTAssertEqual($0 as? CompXError, .badCRC)
        }
    }

    func testParseRejectsShortReplyAndWrongCommand() {
        XCTAssertThrowsError(try Responses.parseReadLighting([8, 8, 0, 0, 0xA0], includesReportID: true)) {
            guard case .malformedResponse = $0 as? CompXError else { return XCTFail("got \($0)") }
        }
        var wrongCommand = Fixtures.readCyanWithID
        wrongCommand[1] = 7
        XCTAssertThrowsError(try Responses.parseReadLighting(wrongCommand, includesReportID: true))
    }

    func testWriteAckInBothShapes() {
        XCTAssertTrue(Responses.isWriteAck([8, 7, 0, 0, 160], includesReportID: true))
        XCTAssertTrue(Responses.isWriteAck([7, 0, 0, 160], includesReportID: false))
        XCTAssertFalse(Responses.isWriteAck([8, 8, 0], includesReportID: true))
        XCTAssertFalse(Responses.isWriteAck([7, 0], includesReportID: true), "7 at [0] is a report ID slot, not the command")
        XCTAssertFalse(Responses.isWriteAck([], includesReportID: false))
    }

    func testLevelRange() {
        XCTAssertNotNil(Level(0))
        XCTAssertNotNil(Level(9))
        XCTAssertNil(Level(10))
        XCTAssertNil(Level(-1))
    }

    func testRGBParsing() {
        XCTAssertEqual(RGB(hex: "#00ffcc"), RGB(r: 0, g: 255, b: 204))
        XCTAssertEqual(RGB(hex: "00FFCC"), RGB(r: 0, g: 255, b: 204))
        XCTAssertNil(RGB(hex: "#xyz"))
        XCTAssertNil(RGB(hex: "#00ffc"))
        XCTAssertNil(RGB(hex: "#00ffccdd"))
        XCTAssertEqual(RGB(name: "Cyan"), RGB(r: 0, g: 255, b: 255))
        XCTAssertEqual(RGB.named.count, 10)
        XCTAssertEqual(RGB(r: 255, g: 128, b: 0).hexString, "#ff8000")
    }

    func testModeNamesAndAliases() {
        XCTAssertEqual(LightingMode(name: "single-breath"), .breathe)
        XCTAssertEqual(LightingMode(name: "static"), .fixed)
        XCTAssertEqual(LightingMode(name: "rainbow-breath"), .rainbowBreathe)
        XCTAssertNil(LightingMode(name: "disco"))
        for mode in LightingMode.allCases {
            XCTAssertEqual(LightingMode(name: mode.name), mode, "name round-trips for \(mode)")
        }
        XCTAssertEqual(LightingMode.fixed.description, "Fixed Color")
    }

    func testRecordRoundTripAndJSON() throws {
        let config = LightingConfig(mode: .neon, color: RGB(r: 1, g: 2, b: 3), speed: .nine, brightness: .zero)
        XCTAssertEqual(try LightingConfig.decode(record: config.encodeRecord()), config)
        let json = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(LightingConfig.self, from: json), config)
    }

    func testDecodeRejectsUnknownModeAndOutOfRangeLevel() {
        XCTAssertThrowsError(try LightingConfig.decode(record: [9, 0, 0, 0, 5, 5] as [UInt8]))
        XCTAssertThrowsError(try LightingConfig.decode(record: [3, 0, 0, 0, 10, 5] as [UInt8]))
    }
}
