// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import CourierCore

final class BlurHashDecoderTests: XCTestCase {
    func testDecodesValidBlurHashAndRejectsInvalid() throws {
        let validHash = "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
        let decoded = try XCTUnwrap(
            BlurHashDecoder.decode(validHash, width: 32, height: 32),
            "Expected valid 4x3 BlurHash to decode into a 32x32 CGImage"
        )
        XCTAssertEqual(decoded.width, 32)
        XCTAssertEqual(decoded.height, 32)

        let customSize = try XCTUnwrap(
            BlurHashDecoder.decode(validHash, width: 48, height: 24),
            "Expected valid BlurHash to decode at custom dimensions"
        )
        XCTAssertEqual(customSize.width, 48)
        XCTAssertEqual(customSize.height, 24)

        // Invalid strings must return nil without crashing.
        XCTAssertNil(BlurHashDecoder.decode(""))
        XCTAssertNil(BlurHashDecoder.decode("short"))
        XCTAssertNil(BlurHashDecoder.decode("!"))
        XCTAssertNil(BlurHashDecoder.decode("LEHV6nWB2yk8"))
        XCTAssertNil(BlurHashDecoder.decode("LEHV6nWB2yk8pyo0adR*.7kCMdn!"))
        XCTAssertNil(BlurHashDecoder.decode(validHash, width: 0, height: 32))
        XCTAssertNil(BlurHashDecoder.decode(validHash, width: 32, height: -1))
    }
}
