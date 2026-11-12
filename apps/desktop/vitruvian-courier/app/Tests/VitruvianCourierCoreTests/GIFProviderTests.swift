// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest

@testable import CourierCore

final class GIFProviderTests: XCTestCase {
    private final class NetworkTrapURLProtocol: URLProtocol {
        nonisolated(unsafe) static var interceptedRequests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool {
            interceptedRequests.append(request)
            return true
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }

        override func stopLoading() {}
    }

    func testStubGIFProviderIsOfflineAndNeverTouchesNetwork() async throws {
        NetworkTrapURLProtocol.interceptedRequests = []
        URLProtocol.registerClass(NetworkTrapURLProtocol.self)
        defer { URLProtocol.unregisterClass(NetworkTrapURLProtocol.self) }

        let provider: any GIFProvider = StubGIFProvider()
        XCTAssertFalse(provider.isAvailable)
        XCTAssertFalse(provider.unavailableReason.isEmpty)
        XCTAssertTrue(provider.unavailableReason.contains("Courier"))
        XCTAssertFalse(provider.unavailableReason.localizedCaseInsensitiveContains("Beeper"))

        let trending = try await provider.trending()
        XCTAssertEqual(trending, [])

        let searched = try await provider.search("cats")
        XCTAssertEqual(searched, [])

        XCTAssertTrue(
            NetworkTrapURLProtocol.interceptedRequests.isEmpty,
            "StubGIFProvider must never make any network request"
        )

        let candidate = GIFCandidate(
            id: "gif-1",
            title: "Excited Cat",
            mediaURL: "courier://media/cat.gif",
            mimeType: "image/gif",
            width: 320,
            height: 240
        )
        XCTAssertEqual(candidate.id, "gif-1")
        XCTAssertEqual(candidate.title, "Excited Cat")
        XCTAssertEqual(candidate.mediaURL, "courier://media/cat.gif")
        XCTAssertEqual(candidate.mimeType, "image/gif")
        XCTAssertEqual(candidate.width, 320)
        XCTAssertEqual(candidate.height, 240)
    }
}
