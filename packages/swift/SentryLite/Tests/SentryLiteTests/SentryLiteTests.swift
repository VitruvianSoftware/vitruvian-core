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
@testable import SentryLite
import XCTest

final class SentryLiteTests: XCTestCase {
    func testDSNParsing() throws {
        let dsnString = "https://2fc1a74b9689b056842028164e4baaca@sentry-ingest.ipv1337.dev/13" // gitleaks:allow
        let dsn = try XCTUnwrap(SentryDSN(string: dsnString))

        XCTAssertEqual(dsn.publicKey, "2fc1a74b9689b056842028164e4baaca") // gitleaks:allow
        XCTAssertEqual(dsn.projectId, "13")
        XCTAssertEqual(dsn.storeEndpointURL.absoluteString, "https://sentry-ingest.ipv1337.dev/api/13/store/")
        XCTAssertTrue(dsn.authHeader.contains("sentry_key=2fc1a74b9689b056842028164e4baaca")) // gitleaks:allow
    }

    func testEventEncoding() throws {
        let event = SentryEvent(
            level: .error,
            message: "Test message",
            error: NSError(domain: "test.domain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Sample failure"]),
            release: "1.0.0",
            environment: "test",
            tags: ["component": "unit-test"]
        )

        let data = try JSONEncoder().encode(event)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["level"] as? String, "error")
        XCTAssertEqual(json["platform"] as? String, "cocoa")
        XCTAssertEqual(json["release"] as? String, "1.0.0")
        let msgObj = json["message"] as? [String: Any]
        XCTAssertEqual(msgObj?["formatted"] as? String, "Test message")
        let tagsObj = json["tags"] as? [String: Any]
        XCTAssertEqual(tagsObj?["component"] as? String, "unit-test")
    }

    func testSentryLiteStartAndCapture() {
        SentryLite.start(
            dsn: "https://2fc1a74b9689b056842028164e4baaca@sentry-ingest.ipv1337.dev/13", // gitleaks:allow
            release: "test-release",
            environment: "test-env"
        )
        SentryLite.capture(message: "Testing info capture", level: .info)
        SentryLite.capture(error: NSError(domain: "test", code: 1))
        SentryLite.flush(timeout: 0.1)
    }
}
