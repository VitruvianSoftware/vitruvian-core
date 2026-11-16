// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What this Mac found out about a link by fetching it itself: a title, the site's name and a picture. A network
/// that sends its own preview (a bridge's `com.beeper.linkpreviews`) never comes here.
public struct LocalLinkPreview: Equatable, Sendable {
    public var url: URL
    public var title: String?
    public var siteName: String?
    /// The page's picture as image data (any format ImageIO reads), if it had one.
    public var imageData: Data?

    public init(url: URL, title: String? = nil, siteName: String? = nil, imageData: Data? = nil) {
        self.url = url
        self.title = title
        self.siteName = siteName
        self.imageData = imageData
    }

    /// Nothing worth a card: no title and no picture.
    public var isEmpty: Bool {
        (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && imageData == nil
    }
}

/// Fetches a page's preview. The app's version asks macOS (`LPMetadataProvider`); tests use a stand-in.
public protocol LinkMetadataFetching: Sendable {
    func fetch(_ url: URL) async -> LocalLinkPreview?
}

/// Decides which links this Mac may fetch a preview for itself.
///
/// Fetching a link tells the site this Mac's address, which is why a network's own preview (the sender's side did
/// the fetching) is always preferred, and why nothing is fetched unless the person has turned on
/// **Load external embeds automatically**, the one setting that says external content may be loaded without asking.
///
/// What this decides is the link as typed. It is not enough on its own: a public-looking name can point at a
/// private address, and a page can redirect to one. `GuardedLinkFetcher` therefore looks the name up and checks
/// every address, and checks every redirect, with `isPublicAddress` and `isPublicWebURL` below.
public enum LocalLinkPreviewPolicy {
    /// The link to fetch a preview for, or nil for none.
    ///
    /// - `loadExternalContent`: the person's "Load external embeds automatically". Off, nothing is fetched.
    /// - `isEmbeddable`: a link the timeline already draws as a click-to-load embed (YouTube and the like); it
    ///   gets that card, not a second one.
    ///
    /// Only a plain text message with no preview from its network, and a public `https` address (not this Mac's
    /// own or a local network's), is eligible. The first such link is used.
    public static func urlToFetch(
        for message: TimelineMessage,
        loadExternalContent: Bool,
        isEmbeddable: (URL) -> Bool = { _ in false }
    ) -> URL? {
        guard loadExternalContent else { return nil }
        switch message.kind {
        case .text, .notice, .emote: break
        default: return nil
        }
        guard message.linkPreviews.isEmpty else { return nil }
        let links = webLinks(in: message.rich)
        guard !links.contains(where: isEmbeddable) else { return nil }
        return links.first(where: isFetchable)
    }

    /// The `http`/`https` links in a message's text, in reading order: its link ranges' addresses and the bare
    /// addresses macOS finds in the text.
    static func webLinks(in rich: RichText) -> [URL] {
        var found: [(offset: Int, url: URL)] = []
        for entity in rich.entities where entity.kind == .link {
            if let address = entity.url, let url = URL(string: address), isWeb(url) {
                found.append((entity.offset, url))
            }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(location: 0, length: (rich.text as NSString).length)
            for match in detector.matches(in: rich.text, options: [], range: range) {
                if let url = match.url, isWeb(url) { found.append((match.range.location, url)) }
            }
        }
        var seen = Set<URL>()
        return found.sorted { $0.offset < $1.offset }.map(\.url).filter { seen.insert($0).inserted }
    }

    private static func isWeb(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// What may be fetched: `https` (never `http`, so a redirect can't step down to it either) and public.
    public static func isFetchable(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && isPublicWebURL(url)
    }

    /// A web address whose host, as written, is on the public internet: not a name or number that only means
    /// something on this Mac or its network (`localhost`, `.local`, a private, loopback or link-local number, in
    /// any way of writing it), and with no user name or password in it.
    ///
    /// A name passes here and may still point somewhere private; `GuardedLinkFetcher` looks it up before fetching.
    public static func isPublicWebURL(_ url: URL) -> Bool {
        guard isWeb(url), url.user == nil, url.password == nil,
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty
        else { return false }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        if let bytes = literalAddress(host) { return isPublicAddress(bytes) }
        guard host.contains(".") else { return false } // "printer", "localhost"
        let localSuffixes = [".local", ".localhost", ".internal", ".lan", ".home", ".home.arpa", ".corp", ".intranet"]
        return !localSuffixes.contains { host.hasSuffix($0) }
    }

    /// The bytes of a host written as an address: IPv6 (`::1`), IPv4 in any form `inet_aton` reads (`127.1`,
    /// `0x7f.0.0.1`, `2130706433`); nil for a name.
    static func literalAddress(_ host: String) -> [UInt8]? {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare.contains(":") {
            var v6 = in6_addr()
            guard inet_pton(AF_INET6, bare, &v6) == 1 else { return [] } // not an address, never public
            return withUnsafeBytes(of: v6) { Array($0) }
        }
        var v4 = in_addr()
        guard inet_aton(bare, &v4) != 0 else { return nil }
        return withUnsafeBytes(of: v4.s_addr) { Array($0) }
    }

    /// An address (4 bytes for IPv4, 16 for IPv6) on the public internet. Not: this host, private networks
    /// (10/8, 172.16/12, 192.168/16, fc00::/7), loopback, link-local (169.254/16, fe80::/10), carrier-grade NAT
    /// and tailnet (100.64/10), multicast, reserved and documentation ranges; and an IPv4 address carried inside
    /// an IPv6 one (`::ffff:10.0.0.1`, 6to4, NAT64) is judged as that IPv4 address.
    public static func isPublicAddress(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4: return isPublicIPv4(bytes)
        case 16: return isPublicIPv6(bytes)
        default: return false
        }
    }

    private static func isPublicIPv4(_ b: [UInt8]) -> Bool {
        switch (b[0], b[1], b[2]) {
        case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _): false
        case (172, 16 ... 31, _): false
        case (100, 64 ... 127, _): false // carrier-grade NAT, and tailnet addresses
        case (192, 0, 0), (192, 0, 2), (198, 51, 100), (203, 0, 113): false // protocol and documentation ranges
        case (198, 18 ... 19, _): false // benchmarking
        case (224 ... 255, _, _): false // multicast, reserved, broadcast
        default: true
        }
    }

    private static func isPublicIPv6(_ b: [UInt8]) -> Bool {
        if b.allSatisfy({ $0 == 0 }) { return false } // ::
        if b[0 ..< 15].allSatisfy({ $0 == 0 }), b[15] == 1 { return false } // ::1
        if b[0] & 0xFE == 0xFC { return false } // fc00::/7, unique local
        if b[0] == 0xFE, b[1] & 0xC0 == 0x80 || b[1] & 0xC0 == 0xC0 { return false } // fe80::/10, fec0::/10
        if b[0] == 0xFF { return false } // multicast
        if b[0 ..< 12].allSatisfy({ $0 == 0 }) { return false } // ::a.b.c.d, the old IPv4-compatible form
        if b[0 ..< 10].allSatisfy({ $0 == 0 }), b[10] == 0xFF, b[11] == 0xFF { // ::ffff:a.b.c.d
            return isPublicIPv4(Array(b[12 ..< 16]))
        }
        if b[0] == 0x00, b[1] == 0x64, b[2] == 0xFF, b[3] == 0x9B, b[4 ..< 12].allSatisfy({ $0 == 0 }) { // 64:ff9b::/96
            return isPublicIPv4(Array(b[12 ..< 16]))
        }
        if b[0] == 0x20, b[1] == 0x02 { return isPublicIPv4(Array(b[2 ..< 6])) } // 2002::/16, 6to4
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0x0D, b[3] == 0xB8 { return false } // 2001:db8::/32, documentation
        if b[0] == 0x20, b[1] == 0x01, b[2] == 0x00, b[3] == 0x00 { return false } // 2001::/32, Teredo
        return true
    }
}

/// Keeps what was fetched for each link, so a message scrolling in and out of view fetches once, and a link several
/// messages share is fetched once. What is kept is bounded by a count and by the bytes the pictures take (the
/// oldest go first), so a chat full of links can't grow it without limit.
///
/// Only the conversation on screen asks, from the row being drawn, so a chat the person has not opened is never
/// fetched for. A failed fetch is remembered for `failureRetry` seconds before another try.
@MainActor
public final class LocalLinkPreviewStore {
    private enum Entry {
        case found(LocalLinkPreview)
        case failed(Date)
    }

    private let fetcher: LinkMetadataFetching
    private let capacity: Int
    private let maxBytes: Int
    private let failureRetry: TimeInterval
    private let now: () -> Date
    private var entries: [URL: Entry] = [:]
    /// Oldest first, for dropping when full.
    private var order: [URL] = []
    private var totalBytes = 0
    private var inFlight: [URL: Task<LocalLinkPreview?, Never>] = [:]

    public init(fetcher: LinkMetadataFetching, capacity: Int = 200, maxBytes: Int = 20 * 1024 * 1024,
                failureRetry: TimeInterval = 600, now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.capacity = max(1, capacity)
        self.maxBytes = max(1, maxBytes)
        self.failureRetry = failureRetry
        self.now = now
    }

    /// What is already known for `url`, without fetching.
    public func cached(_ url: URL) -> LocalLinkPreview? {
        if case let .found(preview)? = entries[url] { return preview }
        return nil
    }

    /// The preview for `url`: what is kept, or what the fetcher finds. Nil when there is none to show.
    public func preview(for url: URL) async -> LocalLinkPreview? {
        switch entries[url] {
        case let .found(preview)?:
            return preview
        case let .failed(at)? where now().timeIntervalSince(at) < failureRetry:
            return nil
        default:
            break
        }
        if let running = inFlight[url] { return await running.value }
        let fetcher = fetcher
        let task = Task { await fetcher.fetch(url) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result, !result.isEmpty {
            remember(url, .found(result))
            return result
        }
        remember(url, .failed(now()))
        return nil
    }

    /// The bytes kept for what is remembered, for a test to read.
    public var keptBytes: Int { totalBytes }

    private static func cost(_ entry: Entry) -> Int {
        guard case let .found(preview) = entry else { return 0 }
        return 512 + (preview.imageData?.count ?? 0) + (preview.title?.utf8.count ?? 0)
    }

    private func remember(_ url: URL, _ entry: Entry) {
        if let old = entries[url] {
            totalBytes -= Self.cost(old)
        } else {
            order.append(url)
        }
        entries[url] = entry
        totalBytes += Self.cost(entry)
        while order.count > capacity || totalBytes > maxBytes, !order.isEmpty {
            let oldest = order.removeFirst()
            if let dropped = entries.removeValue(forKey: oldest) { totalBytes -= Self.cost(dropped) }
        }
    }
}
