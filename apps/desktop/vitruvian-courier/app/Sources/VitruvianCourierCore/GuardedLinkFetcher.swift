// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import ImageIO

/// Looks a host name up: the addresses it points at, as bytes (4 for IPv4, 16 for IPv6). Empty when it can't be found.
public protocol HostResolving: Sendable {
    func addresses(for host: String) async -> [[UInt8]]
}

/// Asks the system (`getaddrinfo`), off the calling thread.
public struct SystemHostResolver: HostResolving {
    public init() {}

    public func addresses(for host: String) async -> [[UInt8]] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: Self.lookup(host)) }
        }
    }

    static func lookup(_ host: String) -> [[UInt8]] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var found: [[UInt8]] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            if let address = info.pointee.ai_addr {
                if info.pointee.ai_family == AF_INET {
                    address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                        found.append(withUnsafeBytes(of: pointer.pointee.sin_addr) { Array($0) })
                    }
                } else if info.pointee.ai_family == AF_INET6 {
                    address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                        found.append(withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) })
                    }
                }
            }
            cursor = info.pointee.ai_next
        }
        return found
    }
}

/// Fetches a link's title, site name and picture on this Mac, with every step guarded, for a link its network sent
/// no preview for (`LocalLinkPreviewPolicy` decides which, and only with "Load external embeds automatically" on).
///
/// - Before any request, and before following each redirect, the host is looked up and **every** address it
///   points at must be public (`LocalLinkPreviewPolicy.isPublicAddress`); `https` only, so a redirect can't step
///   down to `http`; at most 3 redirects. A hop to `localhost`, a `.local` name, a private or link-local number, or a
///   name that resolves to one, is refused and nothing is requested.
/// - It reads at most 512 KB of the page and 2 MB of the picture, and gives up after 5 seconds in all.
/// - It reads only `og:title`, `og:site_name`, `og:image` and `<title>`, and sends no cookies or credentials.
/// - The picture is fetched the same guarded way, then shrunk to the card's size before it is kept.
///
/// Limit: the system looks the name up again when it connects, so a server that answers differently the second
/// time could still be reached. Where the system reports the address it actually connected to, that is checked
/// too, and the page is dropped if it was private.
public struct GuardedLinkFetcher: LinkMetadataFetching {
    public static let maxHTMLBytes = 512 * 1024
    public static let maxImageBytes = 2 * 1024 * 1024
    public static let timeout: TimeInterval = 5
    public static let maxRedirects = 3
    /// The longest side the picture is kept at: the card draws it at most 320 x 148 points, 2x.
    public static let imageMaxPixelSize = 640

    private let session: URLSession
    private let resolver: HostResolving

    public init(session: URLSession = GuardedLinkFetcher.makeSession(), resolver: HostResolving = SystemHostResolver()) {
        self.session = session
        self.resolver = resolver
    }

    /// A session that keeps nothing: no cookies, no cache, no credentials.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    public func fetch(_ url: URL) async -> LocalLinkPreview? {
        await Self.withDeadline(Self.timeout) { await self.fetchWithoutDeadline(url) }
    }

    private func fetchWithoutDeadline(_ url: URL) async -> LocalLinkPreview? {
        guard let page = await get(url, maxBytes: Self.maxHTMLBytes, accept: "text/html,application/xhtml+xml"),
              page.isHTML
        else { return nil }
        let html = String(decoding: page.data, as: UTF8.self)
        let meta = PageMetadata.parse(html: html)
        var imageData: Data?
        if let address = meta.imageAddress,
           let imageURL = URL(string: address, relativeTo: page.finalURL)?.absoluteURL,
           let image = await get(imageURL, maxBytes: Self.maxImageBytes, accept: "image/*"),
           !image.truncated, image.mimeType.isEmpty || image.mimeType.hasPrefix("image/") {
            imageData = Self.shrunk(image.data)
        }
        let host = (page.finalURL.host ?? url.host ?? "").lowercased()
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return LocalLinkPreview(
            url: url,
            title: meta.title,
            siteName: meta.siteName ?? (site.isEmpty ? nil : site),
            imageData: imageData
        )
    }

    struct Page {
        var data: Data
        var finalURL: URL
        var mimeType: String
        /// The body was longer than the cap and was cut.
        var truncated: Bool

        var isHTML: Bool { mimeType.isEmpty || mimeType == "text/html" || mimeType == "application/xhtml+xml" }
    }

    /// The first `maxBytes` of `url`'s body, or nil: refused by the guard (at the start or at a redirect), not a
    /// 2xx answer, too slow, or a failed request.
    func get(_ url: URL, maxBytes: Int, accept: String) async -> Page? {
        let rail = LinkGuard(resolver: resolver)
        guard await rail.allows(url) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: Self.timeout)
        request.httpShouldHandleCookies = false
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh) VitruvianCourier-LinkPreview", forHTTPHeaderField: "User-Agent")
        let delegate = GuardedFetchDelegate(rail: rail, maxRedirects: Self.maxRedirects)
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode),
                  let finalURL = http.url, !delegate.refused
            else { return nil }
            guard await rail.allows(finalURL) else { return nil }
            var data = Data()
            var truncated = false
            for try await byte in bytes {
                if data.count >= maxBytes {
                    truncated = true
                    break
                }
                data.append(byte)
            }
            guard !delegate.refused else { return nil }
            let mime = (http.mimeType ?? "").lowercased()
            return Page(data: data, finalURL: finalURL, mimeType: mime, truncated: truncated)
        } catch {
            return nil
        }
    }

    /// The picture at the card's size, as JPEG (PNG when it has transparency); nil when it isn't a picture.
    static func shrunk(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: imageMaxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, (opaque ? "public.jpeg" : "public.png") as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Runs `work`, and gives up (nil) when it takes longer than `seconds`, whatever it is waiting on.
    static func withDeadline<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// Decides whether a URL may be requested: `https`, a public-looking host, and a host whose every address is public.
struct LinkGuard: Sendable {
    let resolver: HostResolving

    func allows(_ url: URL) async -> Bool {
        guard LocalLinkPreviewPolicy.isFetchable(url), let host = url.host else { return false }
        let addresses = await resolver.addresses(for: host)
        return !addresses.isEmpty && addresses.allSatisfy(LocalLinkPreviewPolicy.isPublicAddress)
    }
}

/// Checks each redirect before it is followed, and the address the connection really went to.
final class GuardedFetchDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let rail: LinkGuard
    private let maxRedirects: Int
    private let lock = NSLock()
    private var hops = 0
    private var wasRefused = false

    init(rail: LinkGuard, maxRedirects: Int) {
        self.rail = rail
        self.maxRedirects = maxRedirects
    }

    /// A redirect was refused, or the connection went to a private address.
    var refused: Bool { lock.withLock { wasRefused } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        let hop = lock.withLock { () -> Int in
            hops += 1
            return hops
        }
        guard hop <= maxRedirects, let url = request.url, await rail.allows(url) else {
            lock.withLock { wasRefused = true }
            return nil
        }
        return request
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for transaction in metrics.transactionMetrics where !transaction.isProxyConnection {
            guard let address = transaction.remoteAddress,
                  let bytes = LocalLinkPreviewPolicy.literalAddress(address), !bytes.isEmpty,
                  !LocalLinkPreviewPolicy.isPublicAddress(bytes)
            else { continue }
            lock.withLock { wasRefused = true }
        }
    }
}

/// The few things a page says about itself that the card uses.
struct PageMetadata: Equatable {
    var title: String?
    var siteName: String?
    var imageAddress: String?

    private static let metaTag = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: [.caseInsensitive])
    private static let property = try! NSRegularExpression(
        pattern: "\\b(?:property|name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]
    )
    private static let content = try! NSRegularExpression(
        pattern: "\\bcontent\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')", options: [.caseInsensitive]
    )
    private static let titleTag = try! NSRegularExpression(
        pattern: "<title\\b[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    /// Reads `og:title`, `og:site_name`, `og:image` and `<title>` from the head of `html` (the title is `<title>` when
    /// there is no `og:title`).
    static func parse(html: String) -> PageMetadata {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html
        let range = NSRange(head.startIndex..., in: head)
        var found = PageMetadata()
        for match in metaTag.matches(in: head, range: range) {
            guard let tagRange = Range(match.range, in: head) else { continue }
            let tag = String(head[tagRange])
            guard let key = attribute(property, in: tag)?.lowercased(),
                  let value = attribute(content, in: tag).map(decodeEntities)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { continue }
            switch key {
            case "og:title" where found.title == nil: found.title = String(value.prefix(300))
            case "og:site_name" where found.siteName == nil: found.siteName = String(value.prefix(100))
            case "og:image" where found.imageAddress == nil: found.imageAddress = value
            default: break
            }
        }
        if found.title == nil,
           let match = titleTag.firstMatch(in: head, range: range), let r = Range(match.range(at: 1), in: head) {
            let text = decodeEntities(String(head[r])).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            if !text.isEmpty { found.title = String(text.prefix(300)) }
        }
        return found
    }

    private static func attribute(_ expression: NSRegularExpression, in tag: String) -> String? {
        let range = NSRange(tag.startIndex..., in: tag)
        guard let match = expression.firstMatch(in: tag, range: range) else { return nil }
        for group in 1 ... 2 {
            if let r = Range(match.range(at: group), in: tag) { return String(tag[r]) }
        }
        return nil
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let end = text[index...].prefix(12).firstIndex(of: ";") {
                let body = String(text[text.index(after: index) ..< end])
                var replacement: String?
                if body.hasPrefix("#x") || body.hasPrefix("#X") {
                    replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
                } else if body.hasPrefix("#") {
                    replacement = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map(String.init)
                } else {
                    replacement = namedEntities[body.lowercased()]
                }
                if let replacement {
                    output += replacement
                    index = text.index(after: end)
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }
}
