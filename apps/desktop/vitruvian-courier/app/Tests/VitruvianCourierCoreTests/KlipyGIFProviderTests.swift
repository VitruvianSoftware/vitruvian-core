// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// A stand-in for the network: answers each request from `answer` and writes down what was asked.
final class FakeGIFTransport: GIFHTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [URLRequest] = []
    var answer: @Sendable (URLRequest) throws -> (body: Data, status: Int)

    init(answer: @escaping @Sendable (URLRequest) throws -> (body: Data, status: Int) = { _ in (Data(), 200) }) {
        self.answer = answer
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return asked
    }

    func send(_ request: URLRequest) async throws -> (body: Data, status: Int) {
        lock.lock()
        asked.append(request)
        lock.unlock()
        return try answer(request)
    }
}

/// KLIPY's GIF API: the requests built, the replies read (from the shape in docs.klipy.com), the key's source, and
/// that nothing is ever fetched from anywhere else. Every reply here is a fixture; no test reaches the network.
final class KlipyGIFProviderTests: XCTestCase {
    static let key = "test-app-key_1"

    /// Two real-shaped items (an MP4 and a GIF for each size) and one with no file at all, which is left out. The
    /// first id is a number and the second a string, as an id may be either.
    static let page = Data("""
    {"result": true, "data": {"data": [
      {"id": 8041071659142944, "slug": "hello-hi-662", "title": "Hello Hi", "type": "gif", "tags": [],
       "blur_preview": "data:image/jpeg;base64,AAAA",
       "file": {
         "md": {"gif": {"url": "https://static.klipy.com/ii/a/md.gif", "width": 498, "height": 498, "size": 3721260},
                "mp4": {"url": "https://static.klipy.com/ii/a/md.mp4", "width": 498, "height": 498, "size": 119294}},
         "sm": {"gif": {"url": "https://static.klipy.com/ii/a/sm.gif", "width": 220, "height": 220, "size": 314884},
                "mp4": {"url": "https://static.klipy.com/ii/a/sm.mp4", "width": 320, "height": 320, "size": 49565}},
         "xs": {"gif": {"url": "https://static.klipy.com/ii/a/xs.gif", "width": 90, "height": 90, "size": 71468}}}},
      {"id": "abc123", "slug": "only-gif", "title": "  ", "type": "gif",
       "file": {"hd": {"gif": {"url": "https://static1.klipy.com/ii/b/hd.gif", "width": 400, "height": 200, "size": 100}}}},
      {"id": 3, "slug": "no-file", "title": "Empty", "type": "gif", "file": {}},
      {"id": 4, "slug": "broken", "title": 5, "type": "gif", "file": "nope"}
    ], "current_page": 1, "per_page": 24, "has_next": true}}
    """.utf8)

    private var cache: URL!

    override func setUpWithError() throws {
        cache = FileManager.default.temporaryDirectory.appendingPathComponent("klipy-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cache)
    }

    private func provider(_ transport: FakeGIFTransport, key: String? = KlipyGIFProviderTests.key) -> KlipyGIFProvider {
        KlipyGIFProvider(apiKey: key, transport: transport, cacheDirectory: cache)
    }

    // MARK: The key

    private func plist(_ entries: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
    }

    func testKeyComesFromKlipyAppPlistAndMustBeSafeInAnAddress() throws {
        XCTAssertEqual(KlipyConfiguration.resourceName, "KlipyApp")
        XCTAssertEqual(KlipyConfiguration.plistKey, "api_key")
        XCTAssertEqual(KlipyConfiguration.apiKey(plist: try plist(["api_key": " abc-DEF_123.x~y \n"])), "abc-DEF_123.x~y")
        XCTAssertNil(KlipyConfiguration.apiKey(plist: nil))
        XCTAssertNil(KlipyConfiguration.apiKey(plist: Data("not a plist".utf8)))
        XCTAssertNil(KlipyConfiguration.apiKey(plist: try plist([:])))
        XCTAssertNil(KlipyConfiguration.apiKey(plist: try plist(["api_key": 12])))
        XCTAssertNil(KlipyConfiguration.apiKey(plist: try plist(["other": "abc"])))
        for bad in ["", "   ", "a/b", "a?b=c", "a b", "../x", "ключ", String(repeating: "a", count: 201), "a#b", "$(KLIPY_KEY)"] {
            XCTAssertNil(KlipyConfiguration.validKey(bad), "\(bad.debugDescription) must not be a key")
        }
    }

    /// A made-up app folder with an Info.plist, and `KlipyApp.plist` in Resources when `key` is given. (A bundle keeps
    /// what it found, so each case gets a folder of its own.)
    private func fakeApp(key: String?) throws -> Bundle {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("klipy-bundle-\(UUID().uuidString).app")
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        try plist(["CFBundleIdentifier": "test.klipy"]).write(to: app.appendingPathComponent("Contents/Info.plist"))
        if let key { try plist(["api_key": key]).write(to: resources.appendingPathComponent("KlipyApp.plist")) }
        return try XCTUnwrap(Bundle(url: app))
    }

    func testTheKeyIsReadFromAnAppBundlesResources() throws {
        let without = try fakeApp(key: nil)
        XCTAssertNil(KlipyConfiguration.apiKey(in: without), "no file, no key")
        XCTAssertFalse(KlipyGIFProvider.fromBundle(without).isAvailable)
        let with = try fakeApp(key: "from-the-file")
        XCTAssertEqual(KlipyConfiguration.apiKey(in: with), "from-the-file")
        XCTAssertTrue(KlipyGIFProvider.fromBundle(with).isAvailable)
        let bad = try fakeApp(key: "bad/key")
        XCTAssertNil(KlipyConfiguration.apiKey(in: bad))
    }

    func testWithNoKeyTheProviderIsUnavailableAndAsksNothing() async {
        let transport = FakeGIFTransport()
        for key in [nil, "", "bad/key"] as [String?] {
            let none = provider(transport, key: key)
            XCTAssertFalse(none.isAvailable)
            XCTAssertFalse(none.unavailableReason.isEmpty)
            do {
                _ = try await none.trending()
                XCTFail("no key, no request")
            } catch {
                XCTAssertEqual(error as? GIFProviderError, .unavailable)
            }
            do {
                _ = try await none.search("cats")
                XCTFail("no key, no request")
            } catch {
                XCTAssertEqual(error as? GIFProviderError, .unavailable)
            }
        }
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertTrue(provider(transport).isAvailable)
    }

    // MARK: Requests

    func testTrendingRequestIsAGetOnKlipysHostWithTheKeyInThePath() throws {
        let request = try XCTUnwrap(KlipyAPI.trendingRequest(apiKey: Self.key))
        XCTAssertEqual(request.httpMethod, "GET")
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.klipy.com")
        XCTAssertEqual(url.path, "/api/v1/test-app-key_1/gifs/trending")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "page" }?.value, "1")
        XCTAssertEqual(items.first { $0.name == "per_page" }?.value, "24")
        XCTAssertEqual(items.first { $0.name == "content_filter" }?.value, "medium")
        XCTAssertEqual(items.first { $0.name == "format_filter" }?.value, "gif,mp4")
        XCTAssertFalse(items.contains { $0.name == "customer_id" || $0.name == "locale" }, "no more than a search needs")
        XCTAssertEqual(request.timeoutInterval, 10)
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testSearchRequestCarriesWhatWasTypedEncoded() throws {
        let request = try XCTUnwrap(KlipyAPI.searchRequest(apiKey: Self.key, query: "cats & dogs/é"))
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/api/v1/test-app-key_1/gifs/search")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "cats & dogs/é")
        XCTAssertEqual(url.host, "api.klipy.com", "what is typed cannot move the request to another host")
        XCTAssertNil(KlipyAPI.searchRequest(apiKey: "bad/key", query: "x"))
        XCTAssertNil(KlipyAPI.trendingRequest(apiKey: ""))
    }

    func testPageSizeIsKeptInKlipysRange() throws {
        let big = try XCTUnwrap(KlipyAPI.trendingRequest(apiKey: Self.key, perPage: 5_000))
        let small = try XCTUnwrap(KlipyAPI.trendingRequest(apiKey: Self.key, page: 0, perPage: 0))
        func value(_ request: URLRequest, _ name: String) -> String? {
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
        XCTAssertEqual(value(big, "per_page"), "50")
        XCTAssertEqual(value(small, "per_page"), "1")
        XCTAssertEqual(value(small, "page"), "1")
    }

    // MARK: Replies

    func testTheReplyBecomesCandidatesWithAGIFAnMP4AndASmallPreview() throws {
        let found = try KlipyAPI.candidates(from: Self.page)
        XCTAssertEqual(found.map(\.id), ["8041071659142944", "abc123"], "an item with no file, or one that does not decode, is left out")
        let first = found[0]
        XCTAssertEqual(first.title, "Hello Hi")
        XCTAssertEqual(first.mediaURL, "https://static.klipy.com/ii/a/md.gif", "the GIF is what is sent, medium size")
        XCTAssertEqual(first.mimeType, "image/gif")
        XCTAssertEqual(first.mp4URL, "https://static.klipy.com/ii/a/md.mp4", "and its MP4 loop, for a chat that takes one")
        XCTAssertEqual(first.width, 498)
        XCTAssertEqual(first.previewURL, "https://static.klipy.com/ii/a/sm.gif")
        let second = found[1]
        XCTAssertEqual(second.title, "only-gif", "a blank title falls back to the slug")
        XCTAssertEqual(second.mediaURL, "https://static1.klipy.com/ii/b/hd.gif")
        XCTAssertEqual(second.mimeType, "image/gif")
        XCTAssertEqual(second.height, 200)
        XCTAssertNil(second.previewURL, "no small GIF to show")
        XCTAssertNil(second.mp4URL)
    }

    /// KLIPY can mix adverts into a page (the reply's meta carries `ad_max_resize_percent`): an item whose `type` is
    /// not a GIF is never offered (adverts, and clips, which are videos with sound), even when it carries files that would play.
    func testAnAdvertInAPageIsNeverOffered() throws {
        let body = Data("""
        {"result": true, "data": {"data": [
          {"id": 1, "slug": "real", "title": "Real", "type": "gif",
           "file": {"md": {"gif": {"url": "https://static.klipy.com/ii/r/md.gif", "width": 10, "height": 10}}}},
          {"id": 2, "slug": "sponsored", "title": "Sponsored", "type": "ad", "content": "<script>x</script>",
           "file": {"md": {"gif": {"url": "https://static.klipy.com/ii/ad/md.gif", "width": 10, "height": 10}}}},
          {"id": 3, "slug": "clip", "title": "Clip", "type": "clip",
           "file": {"md": {"mp4": {"url": "https://static.klipy.com/ii/c/md.mp4", "width": 10, "height": 10}}}}
        ], "current_page": 1, "per_page": 24, "has_next": false}, "meta": {"ad_max_resize_percent": 50}}
        """.utf8)
        XCTAssertEqual(try KlipyAPI.candidates(from: body).map(\.id), ["1"])
    }

    func testAnItemWithNoTypeOrAnUnknownOneIsSkippedToo() throws {
        let body = Data("""
        {"result": true, "data": {"data": [
          {"id": 1, "slug": "typed", "title": "T", "type": "gif",
           "file": {"md": {"gif": {"url": "https://static.klipy.com/ii/r/md.gif", "width": 10, "height": 10}}}},
          {"id": 2, "slug": "untyped", "title": "U",
           "file": {"md": {"gif": {"url": "https://static.klipy.com/ii/u/md.gif", "width": 10, "height": 10}}}},
          {"id": 3, "slug": "odd", "title": "O", "type": "native_ad",
           "file": {"md": {"gif": {"url": "https://static.klipy.com/ii/o/md.gif", "width": 10, "height": 10}}}}
        ]}}
        """.utf8)
        XCTAssertEqual(try KlipyAPI.candidates(from: body).map(\.id), ["1"])
    }

    func testAnEmptyPageIsNotAnError() throws {
        let empty = Data(#"{"result": true, "data": {"data": [], "has_next": false}}"#.utf8)
        XCTAssertEqual(try KlipyAPI.candidates(from: empty), [])
    }

    func testAReplyThatIsNotKlipysShapeIsAnError() {
        for body in ["", "not json", "[]", #"{"result": false, "data": {"data": []}}"#, #"{"result": true}"#, #"{"data": {"data": 5}}"#] {
            XCTAssertThrowsError(try KlipyAPI.candidates(from: Data(body.utf8)), body) { error in
                XCTAssertEqual(error as? GIFProviderError, .badResponse)
            }
        }
    }

    // MARK: The provider over a fake network

    func testTrendingAndSearchAskKlipyOnceEachAndReadTheAnswer() async throws {
        let transport = FakeGIFTransport { _ in (KlipyGIFProviderTests.page, 200) }
        let klipy = provider(transport)
        let trending = try await klipy.trending()
        XCTAssertEqual(trending.count, 2)
        let searched = try await klipy.search("  hello  ")
        XCTAssertEqual(searched.count, 2)
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/api/v1/test-app-key_1/gifs/trending", "/api/v1/test-app-key_1/gifs/search",
        ])
        let query = URLComponents(url: transport.requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }
        XCTAssertEqual(query?.value, "hello", "the query is trimmed")
    }

    func testAnEmptySearchIsTheTrendingList() async throws {
        let transport = FakeGIFTransport { _ in (KlipyGIFProviderTests.page, 200) }
        _ = try await provider(transport).search("   ")
        XCTAssertEqual(transport.requests.map { $0.url?.path }, ["/api/v1/test-app-key_1/gifs/trending"])
    }

    func testAnErrorStatusIsAnError() async {
        for status in [401, 429, 500] {
            let transport = FakeGIFTransport { _ in (Data(), status) }
            do {
                _ = try await provider(transport).trending()
                XCTFail("status \(status)")
            } catch {
                XCTAssertEqual(error as? GIFProviderError, .status(status))
            }
        }
    }

    // MARK: Downloads

    func testAPickedGIFIsDownloadedOnceAndKeptInTheCache() async throws {
        let transport = FakeGIFTransport { _ in (Data("mp4-bytes".utf8), 200) }
        let klipy = provider(transport)
        let candidate = try XCTUnwrap(KlipyAPI.candidates(from: Self.page).first)
        let file = try await klipy.fetchFile(for: candidate)
        XCTAssertEqual(file.pathExtension, "gif", "the GIF unless the chat takes MP4")
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL, cache.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: file), Data("mp4-bytes".utf8))
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://static.klipy.com/ii/a/md.gif")
        let again = try await klipy.fetchFile(for: candidate)
        XCTAssertEqual(again, file)
        XCTAssertEqual(transport.requests.count, 1, "the second time comes from the cache")

        let loop = try await klipy.fetchFile(for: candidate, asMP4: true)
        XCTAssertEqual(loop.pathExtension, "mp4")
        XCTAssertEqual(transport.requests.last?.url?.absoluteString, "https://static.klipy.com/ii/a/md.mp4")
        let noLoop = GIFCandidate(id: "g", title: "g", mediaURL: "https://static.klipy.com/g.gif", mimeType: "image/gif")
        let gifOnly = try await klipy.fetchFile(for: noLoop, asMP4: true)
        XCTAssertEqual(gifOnly.pathExtension, "gif", "no MP4 to send: the GIF")
        let preview = try await klipy.fetchPreview(for: candidate)
        XCTAssertEqual(preview?.pathExtension, "gif")
        XCTAssertNotEqual(preview, file)
        let none = try await klipy.fetchPreview(for: GIFCandidate(id: "x", title: "x", mediaURL: "https://static.klipy.com/x.gif", mimeType: "image/gif"))
        XCTAssertNil(none)
    }

    func testOnlyKlipysOwnHostsAreEverDownloadedFrom() async throws {
        let transport = FakeGIFTransport { _ in (Data("x".utf8), 200) }
        let klipy = provider(transport)
        for address in [
            "https://evil.example/a.gif", "http://static.klipy.com/a.gif", "https://klipy.com.evil.example/a.gif",
            "https://notklipy.com/a.gif", "file:///etc/passwd", "ftp://static.klipy.com/a.gif", "not a url",
        ] {
            let candidate = GIFCandidate(id: "a", title: "a", mediaURL: address, mimeType: "image/gif")
            do {
                _ = try await klipy.fetchFile(for: candidate)
                XCTFail("\(address) must be refused")
            } catch {
                XCTAssertEqual(error as? GIFProviderError, .refusedFile, address)
            }
        }
        XCTAssertEqual(transport.requests.count, 0, "a refused address is never asked for")
        XCTAssertTrue(KlipyAPI.isMediaHost(URL(string: "https://static2.klipy.com/a.gif")!))
        XCTAssertTrue(KlipyAPI.isMediaHost(URL(string: "https://klipy.com/a.gif")!))
    }

    func testAnIdCannotReachOutsideTheCacheFolder() async throws {
        let transport = FakeGIFTransport { _ in (Data("x".utf8), 200) }
        let candidate = GIFCandidate(id: "../../../etc/passwd", title: "t", mediaURL: "https://static.klipy.com/a.mp4", mimeType: "video/mp4")
        let file = try await provider(transport).fetchFile(for: candidate)
        XCTAssertEqual(file.deletingLastPathComponent().standardizedFileURL, cache.standardizedFileURL)
        XCTAssertFalse(file.lastPathComponent.contains("/"))
    }

    func testEmptyOrOversizeOrFailedDownloadsAreRefused() async throws {
        let candidate = GIFCandidate(id: "a", title: "a", mediaURL: "https://static.klipy.com/a.mp4", mimeType: "video/mp4")
        let empty = FakeGIFTransport { _ in (Data(), 200) }
        do {
            _ = try await provider(empty).fetchFile(for: candidate)
            XCTFail("empty file")
        } catch {
            XCTAssertEqual(error as? GIFProviderError, .refusedFile)
        }
        let huge = FakeGIFTransport { _ in (Data(count: KlipyGIFProvider.maximumFileBytes + 1), 200) }
        do {
            _ = try await provider(huge).fetchFile(for: candidate)
            XCTFail("oversize file")
        } catch {
            XCTAssertEqual(error as? GIFProviderError, .refusedFile)
        }
        let failing = FakeGIFTransport { _ in (Data("x".utf8), 404) }
        do {
            _ = try await provider(failing).fetchFile(for: candidate)
            XCTFail("404")
        } catch {
            XCTAssertEqual(error as? GIFProviderError, .status(404))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path), "nothing is written for a refused download")
    }

    // MARK: The policy

    func testPolicyAsksOnlyWithTheSettingOnAndAKeyPresent() {
        XCTAssertTrue(GIFSearchPolicy.mayRequest(searchGIFsOnline: true, providerAvailable: true))
        XCTAssertFalse(GIFSearchPolicy.mayRequest(searchGIFsOnline: false, providerAvailable: true))
        XCTAssertFalse(GIFSearchPolicy.mayRequest(searchGIFsOnline: true, providerAvailable: false))
        XCTAssertFalse(GIFSearchPolicy.mayRequest(searchGIFsOnline: false, providerAvailable: false))
        XCTAssertEqual(GIFSearchPolicy.settingExplanation, "What you type in GIF search, and your network address, go to KLIPY.")
    }

    func testTheSettingIsOnByDefaultAndKept() {
        let store = TestDefaults()
        addTeardownBlock { store.remove() }
        let preferences = ComposerPreferences(defaults: store.defaults)
        XCTAssertTrue(preferences.searchGIFsOnline, "on by default")
        preferences.searchGIFsOnline = false
        XCTAssertEqual(store.defaults.object(forKey: ComposerPreferences.searchGIFsOnlineKey) as? Bool, false)
        XCTAssertFalse(ComposerPreferences(defaults: store.defaults).searchGIFsOnline)
    }

    func testTheStubStillSaysNoAndKeepsItsOldWords() async throws {
        let stub = StubGIFProvider()
        XCTAssertFalse(stub.isAvailable)
        do {
            _ = try await stub.fetchFile(for: GIFCandidate(id: "a", title: "a", mediaURL: "x", mimeType: "image/gif"))
            XCTFail("the stub has no files")
        } catch {
            XCTAssertEqual(error as? GIFProviderError, .unavailable)
        }
        let none = try await stub.fetchPreview(for: GIFCandidate(id: "a", title: "a", mediaURL: "x", mimeType: "image/gif"))
        XCTAssertNil(none)
    }
}
