// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// `LinkPreviewImages`: the page picture of a link card whose network preview came without one is asked of the engine
/// only while "Show link previews" is on, and once per link. All data here is made up.
@MainActor
final class LinkPreviewImagesTests: XCTestCase {
    private let page = URL(string: "https://www.example.com/news/story")!

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
        for bad in ["file:///etc/passwd", "ftp://example.com/a", "mailto:a@example.com", "javascript:alert(1)"] {
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

    func testAQuestionThatCouldNotBeAskedIsAskedAgainLater() async {
        let calls = Calls()
        calls.fails = true
        let images = source(calls)
        let failed = await images.image(for: page, showLinkPreviews: true)
        XCTAssertNil(failed)
        calls.fails = false
        let later = await images.image(for: page, showLinkPreviews: true)
        XCTAssertNotNil(later, "the engine was not up the first time: that is not remembered as 'no picture'")
        XCTAssertEqual(calls.urls.count, 2)
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
