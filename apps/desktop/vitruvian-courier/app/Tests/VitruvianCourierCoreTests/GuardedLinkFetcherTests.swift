// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import ImageIO
import XCTest

@testable import VitruvianCourierCore

/// Answers every request from a closure, and keeps the addresses asked for, so a test sees what was and was not
/// requested. No network is used.
final class StubURLProtocol: URLProtocol {
    enum Answer {
        case page(status: Int = 200, type: String = "text/html", body: Data)
        case redirect(String)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: ((URL) -> Answer)?
    nonisolated(unsafe) private static var log: [String] = []

    static func install(_ answer: @escaping (URL) -> Answer) {
        lock.withLock {
            answers = answer
            log = []
        }
    }

    static var requested: [String] { lock.withLock { log } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let answer = Self.lock.withLock { () -> Answer? in
            Self.log.append(url.absoluteString)
            return Self.answers?(url)
        }
        switch answer {
        case let .redirect(target)?:
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: target)!), redirectResponse: response)
        case let .page(status, type, body)?:
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": type])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case nil:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        }
    }

    override func stopLoading() {}
}

struct FakeResolver: HostResolving {
    var table: [String: [[UInt8]]] = [:]
    func addresses(for host: String) async -> [[UInt8]] {
        table[host] ?? [[93, 184, 216, 34]]
    }
}

/// The guarded fetch of a link's page and picture: what it refuses (private addresses, redirects to them, too much
/// data, too long), and what it reads from a page. All data here is made up.
final class GuardedLinkFetcherTests: XCTestCase {
    private func fetcher(_ resolver: FakeResolver = FakeResolver()) -> GuardedLinkFetcher {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return GuardedLinkFetcher(session: URLSession(configuration: configuration), resolver: resolver)
    }

    private func html(_ head: String) -> Data {
        Data("<!doctype html><html><head>\(head)</head><body>hi</body></html>".utf8)
    }

    private func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func pixelWidth(_ data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyPixelWidth] as? Int
    }

    private let page = URL(string: "https://example.org/post")!

    // MARK: - What it reads

    func testReadsTheTitleSiteAndPictureAndShrinksThePicture() async throws {
        let big = png(width: 2000, height: 1000)
        StubURLProtocol.install { url in
            if url.path == "/cover.png" { return .page(type: "image/png", body: big) }
            return .page(body: self.html("""
            <title>ignored when og:title is there</title>
            <meta property="og:title" content="Dynamic &amp; &#39;fast&#39; workflows">
            <meta content="Example Docs" property="og:site_name">
            <meta property="og:image" content="/cover.png">
            """))
        }
        let preview = await fetcher().fetch(page)
        XCTAssertEqual(preview?.title, "Dynamic & 'fast' workflows")
        XCTAssertEqual(preview?.siteName, "Example Docs")
        let image = try XCTUnwrap(preview?.imageData)
        XCTAssertLessThanOrEqual(try XCTUnwrap(pixelWidth(image)), GuardedLinkFetcher.imageMaxPixelSize)
        XCTAssertLessThan(image.count, big.count + 1, "kept at the card's size, not as fetched")
        XCTAssertEqual(StubURLProtocol.requested, ["https://example.org/post", "https://example.org/cover.png"])
    }

    func testFallsBackToTheTitleTagAndTheHostName() async {
        StubURLProtocol.install { _ in .page(body: self.html("<title>\n  Release\n notes </title>")) }
        let preview = await fetcher().fetch(URL(string: "https://www.example.org/x")!)
        XCTAssertEqual(preview?.title, "Release notes")
        XCTAssertEqual(preview?.siteName, "example.org")
        XCTAssertNil(preview?.imageData)
    }

    func testAnythingButAnHTMLPageGivesNothing() async {
        StubURLProtocol.install { _ in .page(type: "application/json", body: Data("{}".utf8)) }
        let json = await fetcher().fetch(page)
        XCTAssertNil(json)
        StubURLProtocol.install { _ in .page(status: 404, body: self.html("<title>Gone</title>")) }
        let missing = await fetcher().fetch(page)
        XCTAssertNil(missing)
    }

    // MARK: - What it refuses

    func testAHostThatPointsAtAPrivateAddressIsNeverRequested() async {
        StubURLProtocol.install { _ in .page(body: self.html("<title>secret</title>")) }
        for addresses in [[[10, 0, 0, 5]], [[93, 184, 216, 34], [192, 168, 1, 9]], [[127, 0, 0, 1]],
                          [[0xFD] + [UInt8](repeating: 0, count: 14) + [1]], []] as [[[UInt8]]] {
            let preview = await fetcher(FakeResolver(table: ["example.org": addresses])).fetch(page)
            XCTAssertNil(preview, "\(addresses)")
        }
        XCTAssertEqual(StubURLProtocol.requested, [], "refused before any request, whatever the name looked like")
        let literal = await fetcher().fetch(URL(string: "https://192.168.1.1/admin")!)
        XCTAssertNil(literal)
        let plain = await fetcher().fetch(URL(string: "http://example.org/post")!)
        XCTAssertNil(plain, "http is not fetched")
        XCTAssertEqual(StubURLProtocol.requested, [])
    }

    func testARedirectToAPrivateOrLocalHostIsRefusedAndNotFollowed() async {
        let targets = [
            "https://192.168.1.1/admin", "https://10.0.0.7/", "https://169.254.169.254/latest/meta-data",
            "https://localhost/", "https://printer.local/", "https://[::1]/", "https://[fd00::5]/", "https://[fe80::1]/",
            "https://2130706433/", "http://example.org/downgraded",
        ]
        for target in targets {
            StubURLProtocol.install { url in
                url == self.page ? .redirect(target) : .page(body: self.html("<title>secret</title>"))
            }
            let preview = await fetcher().fetch(page)
            XCTAssertNil(preview, target)
            XCTAssertEqual(StubURLProtocol.requested, ["https://example.org/post"], "\(target) was requested")
        }
    }

    func testARedirectToANameThatResolvesPrivatelyIsRefused() async {
        StubURLProtocol.install { url in
            url == self.page ? .redirect("https://evil.example/in") : .page(body: self.html("<title>secret</title>"))
        }
        let resolver = FakeResolver(table: ["evil.example": [[10, 1, 2, 3]]])
        let preview = await fetcher(resolver).fetch(page)
        XCTAssertNil(preview)
        XCTAssertEqual(StubURLProtocol.requested, ["https://example.org/post"])
    }

    func testARedirectToAPublicHostIsFollowedButOnlyAFewTimes() async {
        StubURLProtocol.install { url in
            url.host == "example.org"
                ? .redirect("https://www.example.net/landing")
                : .page(body: self.html("<title>Landed</title>"))
        }
        let preview = await fetcher().fetch(page)
        XCTAssertEqual(preview?.title, "Landed")
        XCTAssertEqual(preview?.siteName, "example.net", "the site is the one it ended on")

        StubURLProtocol.install { url in
            let hop = Int(url.lastPathComponent) ?? 0
            return .redirect("https://example.org/\(hop + 1)")
        }
        let endless = await fetcher().fetch(URL(string: "https://example.org/0")!)
        XCTAssertNil(endless)
        XCTAssertLessThanOrEqual(StubURLProtocol.requested.count, GuardedLinkFetcher.maxRedirects + 1)
    }

    func testAPictureOnAPrivateHostIsLeftOutButThePageStays() async {
        StubURLProtocol.install { _ in
            .page(body: self.html(#"<title>Page</title><meta property="og:image" content="https://192.168.1.5/a.png">"#))
        }
        let preview = await fetcher().fetch(page)
        XCTAssertEqual(preview?.title, "Page")
        XCTAssertNil(preview?.imageData)
        XCTAssertEqual(StubURLProtocol.requested, ["https://example.org/post"])
    }

    // MARK: - Limits

    func testOnlyTheFirst512KBOfThePageIsRead() async {
        let filler = String(repeating: "x", count: GuardedLinkFetcher.maxHTMLBytes + 1000)
        StubURLProtocol.install { _ in
            .page(body: Data("<html><head><!--\(filler)--><title>too late</title></head></html>".utf8))
        }
        let late = await fetcher().fetch(page)
        XCTAssertNil(late?.title, "a title past the cap is never seen")
        StubURLProtocol.install { _ in
            .page(body: Data("<html><head><title>early</title><!--\(filler)--></head></html>".utf8))
        }
        let early = await fetcher().fetch(page)
        XCTAssertEqual(early?.title, "early")
    }

    func testAPictureOver2MBIsLeftOut() async {
        let huge = Data(count: GuardedLinkFetcher.maxImageBytes + 10)
        StubURLProtocol.install { url in
            url.path == "/big.png"
                ? .page(type: "image/png", body: huge)
                : .page(body: self.html(#"<title>Page</title><meta property="og:image" content="/big.png">"#))
        }
        let preview = await fetcher().fetch(page)
        XCTAssertEqual(preview?.title, "Page")
        XCTAssertNil(preview?.imageData)
    }

    func testGivesUpAfterTheDeadline() async {
        let started = Date()
        let result: Int? = await GuardedLinkFetcher.withDeadline(0.2) {
            try? await Task.sleep(for: .seconds(30))
            return 1
        }
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        let quick: Int? = await GuardedLinkFetcher.withDeadline(5) { 7 }
        XCTAssertEqual(quick, 7)
        XCTAssertEqual(GuardedLinkFetcher.timeout, 5)
        XCTAssertEqual(GuardedLinkFetcher.maxHTMLBytes, 512 * 1024)
        XCTAssertEqual(GuardedLinkFetcher.maxImageBytes, 2 * 1024 * 1024)
    }

    // MARK: - What it reads from a page

    func testPageMetadataReadsOnlyWhatTheCardUses() {
        let meta = PageMetadata.parse(html: """
        <html><head>
        <META NAME='og:title' CONTENT='Single &quot;quoted&quot;'>
        <meta property="og:description" content="never read">
        <meta property="og:site_name" content="Site">
        <meta property="og:image" content="https://cdn.example.org/a.jpg">
        <meta property="og:image" content="https://cdn.example.org/second.jpg">
        </head><body><meta property="og:title" content="in the body"></body></html>
        """)
        XCTAssertEqual(meta, PageMetadata(title: "Single \"quoted\"", siteName: "Site",
                                          imageAddress: "https://cdn.example.org/a.jpg"))
        XCTAssertEqual(PageMetadata.parse(html: "<p>nothing</p>"), PageMetadata())
        XCTAssertEqual(PageMetadata.decodeEntities("a &amp; b &#x41; &#66; &unknown; &"), "a & b A B &unknown; &")
    }

    // MARK: - Addresses

    func testWhichAddressesArePublic() {
        let blocked: [[UInt8]] = [
            [0, 0, 0, 0], [10, 1, 2, 3], [127, 0, 0, 1], [169, 254, 1, 1], [172, 16, 0, 1], [172, 31, 255, 255],
            [192, 168, 0, 1], [100, 64, 0, 1], [100, 127, 0, 1], [224, 0, 0, 1], [255, 255, 255, 255],
            [192, 0, 2, 1], [198, 18, 0, 1],
        ]
        for bytes in blocked { XCTAssertFalse(LocalLinkPreviewPolicy.isPublicAddress(bytes), "\(bytes)") }
        let open: [[UInt8]] = [[8, 8, 8, 8], [93, 184, 216, 34], [172, 32, 0, 1], [172, 15, 0, 1], [100, 63, 0, 1], [100, 128, 0, 1]]
        for bytes in open { XCTAssertTrue(LocalLinkPreviewPolicy.isPublicAddress(bytes), "\(bytes)") }
        func v6(_ prefix: [UInt8], tail: [UInt8] = []) -> [UInt8] {
            prefix + [UInt8](repeating: 0, count: 16 - prefix.count - tail.count) + tail
        }
        for bytes in [
            v6([], tail: []), v6([], tail: [1]), v6([0xFC]), v6([0xFD, 0x12]), v6([0xFE, 0x80]), v6([0xFE, 0xBF]),
            v6([0xFE, 0xC0]), v6([0xFF, 0x02]), v6([0x20, 0x01, 0x0D, 0xB8]), v6([0x20, 0x01, 0, 0]),
            v6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF], tail: [10, 0, 0, 1]),
            v6([0, 0x64, 0xFF, 0x9B], tail: [192, 168, 0, 1]),
            v6([0x20, 0x02, 127, 0, 0, 1]),
            v6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], tail: [8, 8, 8, 8]),
        ] { XCTAssertFalse(LocalLinkPreviewPolicy.isPublicAddress(bytes), "\(bytes)") }
        for bytes in [
            v6([0x26, 0x06, 0x47, 0x00], tail: [0x11, 0x11]),
            v6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF], tail: [8, 8, 8, 8]),
            v6([0x20, 0x02, 8, 8, 8, 8]),
        ] { XCTAssertTrue(LocalLinkPreviewPolicy.isPublicAddress(bytes), "\(bytes)") }
        XCTAssertFalse(LocalLinkPreviewPolicy.isPublicAddress([1, 2, 3]))
    }

    func testAddressesAreReadInEveryWayOfWritingThem() {
        for host in ["127.1", "0x7f.0.0.1", "2130706433", "017700000001", "10.1", "[::1]", "[::ffff:10.0.0.1]", "[::ffff:a00:1]"] {
            let url = URL(string: "https://\(host)/")
            XCTAssertFalse(url.map(LocalLinkPreviewPolicy.isPublicWebURL) ?? false, host)
        }
        XCTAssertNotNil(LocalLinkPreviewPolicy.literalAddress("0x7f.1"))
        XCTAssertNil(LocalLinkPreviewPolicy.literalAddress("example.org"))
    }

    func testThisMacsOwnNameLooksUpToNothingPublic() {
        let addresses = SystemHostResolver.lookup("localhost")
        XCTAssertFalse(addresses.isEmpty)
        XCTAssertTrue(addresses.allSatisfy { !LocalLinkPreviewPolicy.isPublicAddress($0) })
    }
}
