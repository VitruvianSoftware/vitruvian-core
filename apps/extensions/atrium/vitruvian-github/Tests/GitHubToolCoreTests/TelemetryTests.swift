// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import XCTest
@testable import GitHubToolCore
#if canImport(SentryLite)
import SentryLite
#endif

final class TelemetryTests: XCTestCase {
    func testTelemetryFailOpenWhenSentryUnreachable() {
        let start = Date()
        // Point to an unreachable local port; must return immediately without throwing or blocking.
        GitHubToolTelemetry.start(dsn: "https://public@127.0.0.1:1/19", release: "test")
        GitHubToolTelemetry.capture(
            error: NSError(domain: "GitHubToolTelemetryTests", code: 503, userInfo: [
                NSLocalizedDescriptionKey: "simulated error"
            ]),
            tags: ["test": "fail_open"],
            extra: ["note": "unreachable"]
        )
        #if canImport(SentryLite)
        SentryLite.capture(message: "fail-open unreachable check", level: .warning)
        #endif
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "Sentry telemetry must be non-blocking when unreachable")
    }

    func testTelemetryIgnoresMalformedDSN() {
        GitHubToolTelemetry.start(dsn: "not-a-valid-dsn", release: "test")
        GitHubToolTelemetry.capture(
            error: NSError(domain: "GitHubToolTelemetryTests", code: 1)
        )
    }
}
