// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// `LinkPreviewImages`: the page picture of a link card whose network preview came without one is asked of the engine
/// only while "Show link previews" is on, and once per link. All data here is made up.
@MainActor
final class LinkPreviewImagesTests: XCTestCase {
    private let page = URL(string: "https://www.example.com/news/story")!

    private final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private final class Allowed: @unchecked Sendable { var on = true }

    private final class Calls: @unchecked Sendable {
        var urls: [URL] = []
        var answer: LinkPreviewImage? = LinkPreviewImage(path: "/media/ab/abcd", width: 1200, height: 630)
        var fails = false
        var delay: Duration = .zero
    }

    private func source(_ calls: Calls) -> LinkPreviewImages {
        LinkPreviewImages { url in
            calls.urls.append(url)
            if calls.delay > .zero { try await Task.sleep(for: calls.delay) }
            if calls.fails { throw EngineError.notConnected }
            return calls.answer
        }
    }

    func testNothingIsAskedWhileShowLinkPreviewsIsOff() async {
        let calls = Calls()
        let images = source(calls)
        let off = await images.image(for: page, showLinkPreviews: false)
        XCTAssertNil(off)
        XCTAssertTrue(calls.urls.isEmpty, "Show link previews off: no request")
        XCTAssertEqual(images.requestCount, 0)
        XCTAssertNil(images.cached(for: page))
    }

    func testOnlyHTTPAddressesAreAsked() async {
        let calls = Calls()
        let images = source(calls)
        // The engine fetches https pages only, so http is not even asked about.
        for bad in ["http://www.example.com/story", "file:///etc/passwd", "ftp://example.com/a", "mailto:a@example.com",
                    "javascript:alert(1)"] {
            let result = await images.image(for: URL(string: bad)!, showLinkPreviews: true)
            XCTAssertNil(result, bad)
        }
        XCTAssertTrue(calls.urls.isEmpty)
    }

    func testALinkIsAskedOnceNoMatterHowOftenItsCardIsDrawn() async {
        let calls = Calls()
        let images = source(calls)
        let first = await images.image(for: page, showLinkPreviews: true)
        XCTAssertEqual(first?.path, "/media/ab/abcd")
        for again in [page, URL(string: page.absoluteString + "#comments")!] {
            let result = await images.image(for: again, showLinkPreviews: true)
            XCTAssertEqual(result, first)
        }
        XCTAssertEqual(calls.urls.count, 1, "scrolling past it again asks nothing")
        XCTAssertEqual(images.cached(for: page), first, "a card drawn again knows it at once, with no wait")
    }

    func testCardsDrawnTogetherShareOneRequest() async {
        let calls = Calls()
        calls.delay = .milliseconds(50)
        let images = source(calls)
        async let a = images.image(for: page, showLinkPreviews: true)
        async let b = images.image(for: page, showLinkPreviews: true)
        async let c = images.image(for: page, showLinkPreviews: true)
        let results = await [a, b, c]
        XCTAssertEqual(calls.urls.count, 1)
        XCTAssertTrue(results.allSatisfy { $0 != nil })
    }

    func testAPageWithNoPictureIsNotAskedAgain() async {
        let calls = Calls()
        calls.answer = nil
        let images = source(calls)
        let first = await images.image(for: page, showLinkPreviews: true)
        let second = await images.image(for: page, showLinkPreviews: true)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(calls.urls.count, 1)
    }

    /// A question that could not be asked yet (the engine is not up) is asked again, but only after a wait that grows.
    func testATransientFailureIsRetriedWithBackoff() async {
        let calls = Calls()
        calls.fails = true
        let clock = Clock()
        let images = LinkPreviewImages(now: { clock.now }) { url in
            calls.urls.append(url)
            if calls.fails { throw EngineError.notConnected }
            return calls.answer
        }
        let failed = await images.image(for: page, showLinkPreviews: true)
        XCTAssertNil(failed)
        // Drawn again at once, and again: no storm of requests.
        for _ in 0 ..< 5 { _ = await images.image(for: page, showLinkPreviews: true) }
        XCTAssertEqual(calls.urls.count, 1, "not asked again during the wait")
        clock.now.addTimeInterval(6) // past the first 5 s
        _ = await images.image(for: page, showLinkPreviews: true)
        XCTAssertEqual(calls.urls.count, 2)
        clock.now.addTimeInterval(10) // the second wait is 15 s
        _ = await images.image(for: page, showLinkPreviews: true)
        XCTAssertEqual(calls.urls.count, 2, "the wait grew")
        clock.now.addTimeInterval(6)
        calls.fails = false
        let later = await images.image(for: page, showLinkPreviews: true)
        XCTAssertNotNil(later, "the engine was not up before: that is not remembered as 'no picture'")
        XCTAssertEqual(calls.urls.count, 3)
        XCTAssertEqual([1, 2, 3, 4, 5, 6].map { LinkPreviewImages.retryDelay(afterFailures: $0) }, [5, 15, 45, 135, 300, 300])
    }

    /// An older engine without the method, or one that refuses the address, will never answer: "no picture" for the session.
    func testAnEngineThatCannotAnswerIsNotAskedAgain() async {
        for code in [RPCErrorCode.methodNotFound, .invalidParams] {
            let calls = Calls()
            let images = LinkPreviewImages { url in
                calls.urls.append(url)
                throw EngineError.rpc(code, message: "no", reason: nil)
            }
            for _ in 0 ..< 4 { _ = await images.image(for: page, showLinkPreviews: true) }
            XCTAssertEqual(calls.urls.count, 1, "\(code): asked once, however often the card is drawn")
            XCTAssertNil(images.cached(for: page))
        }
    }

    /// Show link previews going off drops the requests waiting their turn, and a picture already got stops showing.
    func testTurningShowLinkPreviewsOffDropsWaitingRequestsAndHidesPictures() async {
        let calls = Calls()
        let allowed = Allowed()
        var release: CheckedContinuation<Void, Never>?
        let images = LinkPreviewImages(allows: { allowed.on }, maxConcurrent: 1) { url in
            calls.urls.append(url)
            if url.path == "/first" { await withCheckedContinuation { release = $0 } }
            return calls.answer
        }
        let first = URL(string: "https://www.example.com/first")!
        let second = URL(string: "https://www.example.com/second")!
        async let firstAnswer = images.image(for: first, showLinkPreviews: true)
        try? await Task.sleep(for: .milliseconds(30))
        async let secondAnswer = images.image(for: second, showLinkPreviews: true) // waits: one request at a time
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.urls.map(\.path), ["/first"], "the second waits for the first")

        allowed.on = false // Show link previews goes off while the second waits
        release?.resume()
        let results = await [firstAnswer, secondAnswer]
        XCTAssertEqual(calls.urls.map(\.path), ["/first"], "the waiting request was dropped, not asked")
        XCTAssertNil(results[1])
        XCTAssertNil(images.cached(for: first), "a picture got earlier is not handed out while it is off")

        allowed.on = true
        XCTAssertNotNil(images.cached(for: first), "and is there again when it is back on")
        let again = await images.image(for: second, showLinkPreviews: true)
        XCTAssertNotNil(again, "a dropped request was not remembered as 'no picture'")
        XCTAssertEqual(calls.urls.map(\.path), ["/first", "/second"])
    }

    func testThePageAddressOfAPreview() {
        XCTAssertEqual(LinkPreviewItem(matchedURL: "https://a.example/x", url: "https://b.example/y").pageURL?.host, "b.example")
        XCTAssertEqual(LinkPreviewItem(matchedURL: " https://a.example/x ").pageURL?.host, "a.example")
        XCTAssertNil(LinkPreviewItem(matchedURL: "ftp://a.example/x").pageURL)
    }

    // MARK: The engine's side of the wire

    /// The conversation's own source asks `linkPreview.image` with only the address, reads the answer and asks once.
    func testTheConversationAsksTheEngineForTheLinkPicture() async throws {
        let h = try await startConversation(["!a": []])
        defer { Task { await h.stop() } }
        h.script.overrides["linkPreview.image"] = .result([
            "image_path": "/Users/test/media/3f/3fa1", "image_width": 1200, "image_height": 630,
        ])
        let first = await h.conversation.linkPreviewImages.image(for: page, showLinkPreviews: true)
        XCTAssertEqual(first, LinkPreviewImage(path: "/Users/test/media/3f/3fa1", width: 1200, height: 630))
        _ = await h.conversation.linkPreviewImages.image(for: page, showLinkPreviews: true)
        XCTAssertEqual(h.count("linkPreview.image"), 1)
        XCTAssertEqual(Set(try XCTUnwrap(h.server.receivedParams("linkPreview.image").last).keys), ["url"])

        // A page with no picture answers an empty result: nothing to draw, and not asked again.
        let other = URL(string: "https://www.example.com/plain")!
        h.script.overrides["linkPreview.image"] = .result([:])
        let none = await h.conversation.linkPreviewImages.image(for: other, showLinkPreviews: true)
        XCTAssertNil(none)

        // With Show link previews off the engine hears nothing.
        let third = URL(string: "https://www.example.com/third")!
        _ = await h.conversation.linkPreviewImages.image(for: third, showLinkPreviews: false)
        XCTAssertEqual(h.count("linkPreview.image"), 2)
    }
}
