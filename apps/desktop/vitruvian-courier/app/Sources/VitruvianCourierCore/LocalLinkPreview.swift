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
public enum LocalLinkPreviewPolicy {
    /// The link to fetch a preview for, or nil for none.
    ///
    /// - `loadExternalContent`: the person's "Load external embeds automatically". Off, nothing is fetched.
    /// - `isEmbeddable`: a link the timeline already draws as a click-to-load embed (YouTube and the like); it
    ///   gets that card, not a second one.
    ///
    /// Only a plain text message with no preview from its network, and a public `http`/`https` address (not this
    /// Mac's own or a local network's), is eligible. The first such link is used.
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
        return links.first(where: isPublicWebURL)
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

    /// A web address on the public internet: not a name or number that only means something on this Mac or its
    /// network (`localhost`, `.local`, a private or loopback number), so a message can't make this Mac knock on
    /// something inside the person's own network.
    public static func isPublicWebURL(_ url: URL) -> Bool {
        guard isWeb(url), url.user == nil, url.password == nil,
              let rawHost = url.host?.lowercased(), !rawHost.isEmpty
        else { return false }
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        if let parts = ipv4Parts(host) {
            return !isPrivateIPv4(parts)
        }
        if host.contains(":") { // an IPv6 number
            return !isPrivateIPv6(host)
        }
        guard host.contains(".") else { return false } // "printer", "localhost"
        let localSuffixes = [".local", ".localhost", ".internal", ".lan", ".home", ".home.arpa", ".corp", ".intranet"]
        return !localSuffixes.contains { host.hasSuffix($0) }
    }

    private static func ipv4Parts(_ host: String) -> [Int]? {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 4 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard let value = Int(piece), (0 ... 255).contains(value) else { return nil }
            parts.append(value)
        }
        return parts
    }

    private static func isPrivateIPv4(_ p: [Int]) -> Bool {
        switch (p[0], p[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): true
        case (172, 16 ... 31): true
        case (100, 64 ... 127): true // carrier-grade NAT, and tailnet addresses
        case (224 ... 255, _): true
        default: false
        }
    }

    private static func isPrivateIPv6(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if h == "::" || h == "::1" { return true }
        if h.hasPrefix("fe8") || h.hasPrefix("fe9") || h.hasPrefix("fea") || h.hasPrefix("feb") { return true } // link-local
        if h.hasPrefix("fc") || h.hasPrefix("fd") { return true } // unique local
        if h.hasPrefix("::ffff:") { // an IPv4 address in IPv6 clothes
            if let parts = ipv4Parts(String(h.dropFirst("::ffff:".count))) { return isPrivateIPv4(parts) }
            return true
        }
        return false
    }
}

/// Keeps what was fetched for each link, so a message scrolling in and out of view fetches once, and a link several
/// messages share is fetched once.
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
    private let failureRetry: TimeInterval
    private let now: () -> Date
    private var entries: [URL: Entry] = [:]
    /// Oldest first, for dropping when full.
    private var order: [URL] = []
    private var inFlight: [URL: Task<LocalLinkPreview?, Never>] = [:]

    public init(fetcher: LinkMetadataFetching, capacity: Int = 200, failureRetry: TimeInterval = 600,
                now: @escaping () -> Date = Date.init) {
        self.fetcher = fetcher
        self.capacity = max(1, capacity)
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

    private func remember(_ url: URL, _ entry: Entry) {
        if entries[url] == nil { order.append(url) }
        entries[url] = entry
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }
}
