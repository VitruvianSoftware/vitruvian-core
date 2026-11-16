// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Which links this Mac fetches a preview for itself (`LocalLinkPreviewPolicy`), and the store that keeps what it
/// fetched. All data here is made up.
@MainActor
final class LocalLinkPreviewTests: XCTestCase {
    private let me = Timeline.meUserID

    private func message(body: String, msgtype: String = "m.text", previews: [LinkPreviewItem]? = nil,
                         html: String? = nil, mine: Bool = false) -> TimelineMessage {
        let formatted = html.map { #","format":"org.matrix.custom.html","formatted_body":\#(quoted($0))"# } ?? ""
        let content = try! JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"msgtype":"\#(msgtype)","body":\#(quoted(body))\#(formatted)}"#.utf8)
        )
        let event = Event(eventID: "$1", roomID: "!room", sender: mine ? me : "@ann:example.test", senderName: "Ann",
                          mine: mine, type: "m.room.message", content: content, ts: 1_760_000_000_000, seq: 0,
                          status: .sent, linkPreviews: previews)
        let items = Timeline.build(events: [event], me: me, now: Date(timeIntervalSince1970: 1_760_000_100))
        for case let .message(m) in items { return m }
        fatalError("no message built")
    }

    private func quoted(_ text: String) -> String {
        String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
    }

    private let docs = "https://antigravity.google/docs/dynamic-workflows/"

    // MARK: - Policy

    func testALinkWithNoNetworkPreviewGetsOneWhenExternalContentIsAllowed() {
        let m = message(body: "have a look \(docs) it is good")
        XCTAssertEqual(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true), URL(string: docs))
    }

    func testAPreviewTheNetworkSentWinsOverFetchingOne() {
        let supplied = LinkPreviewItem(matchedURL: docs, url: docs, title: "Dynamic workflows")
        let m = message(body: docs, previews: [supplied])
        XCTAssertEqual(m.linkPreviews.count, 1, "the fixture carries the network's preview")
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true))
    }

    func testNothingIsFetchedWhileTheSettingIsOff() {
        let m = message(body: docs)
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: false))
        XCTAssertNotNil(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true),
                        "the same message does get one with it on, so the nil above is the setting")
    }

    func testTheSettingIsOffByDefaultSoNothingNewAppearsUntilThePersonTurnsItOn() {
        let store = TestDefaults()
        defer { store.remove() }
        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertFalse(preferences.loadExternalEmbedsAutomatically)
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(
            for: message(body: docs), loadExternalContent: preferences.loadExternalEmbedsAutomatically
        ))
    }

    func testAnEmbeddableLinkKeepsItsEmbedCardAndGetsNoSecondOne() {
        let m = message(body: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        let isEmbeddable: (URL) -> Bool = { $0.host?.contains("youtube.com") == true }
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true, isEmbeddable: isEmbeddable))
        XCTAssertNotNil(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true))
    }

    func testOnlyTextMessagesAreEligible() {
        XCTAssertNotNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: docs, msgtype: "m.notice"),
                                                          loadExternalContent: true))
        XCTAssertNotNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: docs, msgtype: "m.emote"),
                                                          loadExternalContent: true))
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: docs, msgtype: "m.file"),
                                                       loadExternalContent: true))
    }

    func testALinkRangeInFormattedTextIsFoundToo() {
        let m = message(body: "read the docs", html: #"read the <a href="https://example.org/docs">docs</a>"#)
        XCTAssertEqual(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true),
                       URL(string: "https://example.org/docs"))
    }

    func testTheFirstWebLinkIsUsedAndAMailAddressIsNot() {
        let m = message(body: "write to ann@example.org or see https://a.example.org/x then https://b.example.org/y")
        XCTAssertEqual(LocalLinkPreviewPolicy.urlToFetch(for: m, loadExternalContent: true),
                       URL(string: "https://a.example.org/x"))
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: "write to ann@example.org"),
                                                       loadExternalContent: true))
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: "no link here"), loadExternalContent: true))
    }

    func testOnlyHTTPSLinksAreFetched() {
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: "http://example.org/plain"),
                                                       loadExternalContent: true))
        XCTAssertEqual(LocalLinkPreviewPolicy.urlToFetch(for: message(body: "http://a.example.org/ https://b.example.org/"),
                                                         loadExternalContent: true),
                       URL(string: "https://b.example.org/"))
    }

    func testAddressesOnThisMacOrTheLocalNetworkAreNeverFetched() {
        for address in [
            "http://localhost:8080/admin", "http://printer/status", "http://nas.local/", "http://router.lan/",
            "http://127.0.0.1/", "http://10.0.0.5/", "http://192.168.1.20/", "http://172.16.4.4/",
            "http://169.254.1.1/", "http://100.64.0.9/", "http://[::1]/", "http://[fd00::1]/",
            "https://user:secret@example.org/", "ftp://example.org/file",
        ] {
            let url = URL(string: address)!
            XCTAssertFalse(LocalLinkPreviewPolicy.isPublicWebURL(url), address)
        }
        for address in ["https://example.org/", "http://www.example.co.uk/a?b=1", "https://8.8.8.8/", "https://172.32.0.1/"] {
            XCTAssertTrue(LocalLinkPreviewPolicy.isPublicWebURL(URL(string: address)!), address)
        }
        XCTAssertNil(LocalLinkPreviewPolicy.urlToFetch(for: message(body: "http://192.168.1.20/router"),
                                                       loadExternalContent: true))
    }

    // MARK: - Store

    private final class CountingFetcher: LinkMetadataFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [URL: Int] = [:]
        var result: @Sendable (URL) -> LocalLinkPreview?
        var delay: Duration = .zero

        init(result: @escaping @Sendable (URL) -> LocalLinkPreview?) { self.result = result }

        func count(_ url: URL) -> Int { lock.withLock { counts[url, default: 0] } }
        var total: Int { lock.withLock { counts.values.reduce(0, +) } }

        func fetch(_ url: URL) async -> LocalLinkPreview? {
            lock.withLock { counts[url, default: 0] += 1 }
            if delay > .zero { try? await Task.sleep(for: delay) }
            return result(url)
        }
    }

    private func found(_ url: URL) -> LocalLinkPreview {
        LocalLinkPreview(url: url, title: "Dynamic workflows", siteName: "antigravity.google")
    }

    func testTheStoreFetchesALinkOnceHoweverOftenAndHoweverManyAsk() async throws {
        let url = try XCTUnwrap(URL(string: docs))
        let fetcher = CountingFetcher { LocalLinkPreview(url: $0, title: "Dynamic workflows") }
        fetcher.delay = .milliseconds(50)
        let store = LocalLinkPreviewStore(fetcher: fetcher)
        XCTAssertNil(store.cached(url))
        async let first = store.preview(for: url)
        async let second = store.preview(for: url)
        let (a, b) = await (first, second)
        XCTAssertEqual(a?.title, "Dynamic workflows")
        XCTAssertEqual(a, b)
        _ = await store.preview(for: url)
        XCTAssertEqual(fetcher.count(url), 1, "two asking at once and one later share a single fetch")
        XCTAssertEqual(store.cached(url)?.title, "Dynamic workflows")
    }

    func testAFailedFetchIsNotRepeatedAtOnceButIsTriedAgainLater() async throws {
        let url = try XCTUnwrap(URL(string: docs))
        let fetcher = CountingFetcher { _ in nil }
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = LocalLinkPreviewStore(fetcher: fetcher, failureRetry: 600, now: { clock })
        let first = await store.preview(for: url)
        XCTAssertNil(first)
        let second = await store.preview(for: url)
        XCTAssertNil(second)
        XCTAssertEqual(fetcher.count(url), 1)
        clock = clock.addingTimeInterval(601)
        fetcher.result = { LocalLinkPreview(url: $0, title: "Back up") }
        let third = await store.preview(for: url)
        XCTAssertEqual(third?.title, "Back up")
        XCTAssertEqual(fetcher.count(url), 2)
    }

    func testAPageWithNeitherTitleNorPictureShowsNothing() async throws {
        let url = try XCTUnwrap(URL(string: docs))
        let store = LocalLinkPreviewStore(fetcher: CountingFetcher { LocalLinkPreview(url: $0, title: "  ", siteName: "x") })
        let preview = await store.preview(for: url)
        XCTAssertNil(preview)
        XCTAssertNil(store.cached(url))
    }

    func testTheStoreIsBoundedByTheBytesOfItsPicturesToo() async throws {
        let urls = try (1 ... 5).map { try XCTUnwrap(URL(string: "https://example.org/\($0)")) }
        let fetcher = CountingFetcher {
            LocalLinkPreview(url: $0, title: "T", imageData: Data(count: 400_000))
        }
        let store = LocalLinkPreviewStore(fetcher: fetcher, capacity: 100, maxBytes: 1_000_000)
        for url in urls {
            _ = await store.preview(for: url)
            XCTAssertLessThanOrEqual(store.keptBytes, 1_000_000)
        }
        XCTAssertNil(store.cached(urls[0]), "the oldest went to make room")
        XCTAssertNotNil(store.cached(urls[4]))
        XCTAssertNotNil(store.cached(urls[3]))
        XCTAssertGreaterThan(store.keptBytes, 0)
    }

    func testTheStoreForgetsTheOldestWhenFull() async throws {
        let urls = try (1 ... 3).map { try XCTUnwrap(URL(string: "https://example.org/\($0)")) }
        let fetcher = CountingFetcher { LocalLinkPreview(url: $0, title: $0.lastPathComponent) }
        let store = LocalLinkPreviewStore(fetcher: fetcher, capacity: 2)
        for url in urls { _ = await store.preview(for: url) }
        XCTAssertNil(store.cached(urls[0]))
        XCTAssertNotNil(store.cached(urls[1]))
        XCTAssertNotNil(store.cached(urls[2]))
    }
}
