// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest

@testable import VitruvianCourierCore

final class EmbedThumbnailTests: XCTestCase {
    func testAValidVideoIDMakesYouTubesPictureAddress() {
        XCTAssertEqual(EmbedThumbnail.youTubeURL(videoID: "dQw4w9WgXcQ")?.absoluteString,
                       "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg")
        XCTAssertEqual(EmbedThumbnail.youTubeOEmbedURL(videoID: "dQw4w9WgXcQ")?.absoluteString,
                       "https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&format=json")
        XCTAssertNotNil(EmbedThumbnail.youTubeURL(videoID: "a-_B1234567"))
        XCTAssertNotNil(EmbedThumbnail.youTubeOEmbedURL(videoID: "a-_B1234567"))
    }

    func testAnIDThatIsNotExactlyElevenSafeCharactersIsRefused() {
        for bad in ["", "short", "dQw4w9WgXcQx", "dQw4w9WgXc!", "dQw4w9Wg/cQ", "dQw4w9Wg?cQ", "dQw4w9WgXc ", "dQw4w9WgXcé",
                    "../../etc/p", "dQw4w9WgXc\n"] {
            XCTAssertNil(EmbedThumbnail.youTubeURL(videoID: bad), "\(bad.debugDescription) must be refused")
            XCTAssertNil(EmbedThumbnail.youTubeOEmbedURL(videoID: bad), "\(bad.debugDescription) must be refused for oEmbed")
        }
    }

    private func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testOnlyYouTubesPictureAddressIsEverAskedFor() async {
        CountingURLProtocol.reset(body: pngData())
        let session = CountingURLProtocol.session()
        EmbedThumbnail.clearCache()
        // Bad IDs, including ones shaped like addresses, ask for nothing at all.
        for bad in ["", "evil.com/x", "dQw4w9WgXcQ/../x", "dQw4w9WgXc?", "a b c d e f g"] {
            let image = await EmbedThumbnail.fetch(videoID: bad, session: session)
            XCTAssertNil(image)
        }
        XCTAssertEqual(CountingURLProtocol.requests, [], "no request for a bad ID")
        let image = await EmbedThumbnail.fetch(videoID: "dQw4w9WgXcQ", session: session)
        XCTAssertNotNil(image)
        XCTAssertEqual(CountingURLProtocol.requests, ["https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"])
        XCTAssertNotNil(EmbedThumbnail.cachedThumbnail(videoID: "dQw4w9WgXcQ"))
        _ = await EmbedThumbnail.fetch(videoID: "dQw4w9WgXcQ", session: session)
        XCTAssertEqual(CountingURLProtocol.requests.count, 1, "the second time comes from memory")
    }

    func testFetchMetadataParsesTitleAndChannelAndCaches() async {
        let json = Data(#"{"title":"  Build With Bazel  ","author_name":"  Courier Channel  "}"#.utf8)
        CountingURLProtocol.reset(body: json)
        let session = CountingURLProtocol.session()
        EmbedThumbnail.clearCache()

        let badIDMeta = await EmbedThumbnail.fetchMetadata(videoID: "bad-id", session: session)
        XCTAssertNil(badIDMeta)
        XCTAssertEqual(CountingURLProtocol.requests, [], "no oEmbed request for a bad ID")

        let meta = await EmbedThumbnail.fetchMetadata(videoID: "dQw4w9WgXcQ", session: session)
        XCTAssertEqual(meta, YouTubeMetadata(title: "Build With Bazel", authorName: "Courier Channel"))
        XCTAssertEqual(
            CountingURLProtocol.requests,
            ["https://www.youtube.com/oembed?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ&format=json"]
        )
        XCTAssertEqual(EmbedThumbnail.cachedMetadata(videoID: "dQw4w9WgXcQ"), meta)

        _ = await EmbedThumbnail.fetchMetadata(videoID: "dQw4w9WgXcQ", session: session)
        XCTAssertEqual(CountingURLProtocol.requests.count, 1, "the second oEmbed lookup comes from memory")

        EmbedThumbnail.clearCache()
        XCTAssertNil(EmbedThumbnail.cachedMetadata(videoID: "dQw4w9WgXcQ"))
        CountingURLProtocol.reset(body: Data(#"{"title":"   ","author_name":"Ch"}"#.utf8))
        let emptyTitleMeta = await EmbedThumbnail.fetchMetadata(videoID: "dQw4w9WgXcQ", session: session)
        XCTAssertNil(emptyTitleMeta, "empty title is rejected")
    }
}

/// Answers every request with a small picture and remembers what was asked for.
final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [String] = []
    nonisolated(unsafe) static var body = Data()
    private static let lock = NSLock()

    static func reset(body: Data) {
        lock.lock(); defer { lock.unlock() }
        requests = []
        self.body = body
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CountingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request.url?.absoluteString ?? "")
        let body = Self.body
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
