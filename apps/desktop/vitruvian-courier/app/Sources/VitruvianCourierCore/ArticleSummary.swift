// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation
import os

// "Summarize" on a link card (E1): Courier reads the article itself (the engine's `article.read`, with the link
// preview's limits), sends only its text to the person's AI service, and shows 3 to 5 bullets in a panel under the
// card. A paywalled or unreadable article is looked for elsewhere through the service's own web search, and a page
// found is used only if the service says it is the same story. Nothing is ever posted to the chat.

// MARK: - What the panel shows

/// Why the linked page itself wasn't summarized.
public enum ArticleSummaryWhy: String, Codable, Hashable, Sendable {
    /// The site keeps the article behind a subscription or sign-in.
    case paywalled
    /// Nothing readable came back: the page needs a browser, failed to load, or isn't a web page.
    case unreadable
}

/// Which page a summary is of.
public enum ArticleSummaryOrigin: Codable, Hashable, Sendable {
    /// The linked article itself.
    case page
    /// The same story from another site, because the linked page couldn't be used.
    case elsewhere(ArticleSummaryWhy)
}

/// A finished summary. Codable: it is what the cache keeps.
public struct ArticleSummary: Codable, Hashable, Sendable {
    /// 3 to 5 points, without bullet marks.
    public var bullets: [String]
    /// The AI service that wrote it ("Anthropic"): the panel's "Summary by …".
    public var provider: String
    /// The page the summary is of: what "Open article" opens.
    public var sourceURL: URL
    /// That page's site, as a domain ("apnews.com").
    public var sourceDomain: String
    /// The linked page's site ("usatoday.com").
    public var linkDomain: String
    public var origin: ArticleSummaryOrigin
    /// The footer line, as the other AI features write it (`AIProvider.provenanceFooter`): "via <model> · sent to
    /// Anthropic" or "via <model> · on this Mac". nil in a summary kept by an earlier version.
    public var provenance: String?
    /// Google's search suggestions (HTML and CSS) when the page was found by Google AI Studio's search: Google's terms
    /// require them under anything that search grounded. Kept with the summary, so they come back with it.
    public var searchSuggestionsHTML: String?
    /// The searches Google ran: shown as "Search Google for: …" links when its suggestions can't be shown.
    public var searchQueries: [String]?

    public init(bullets: [String], provider: String, sourceURL: URL, sourceDomain: String, linkDomain: String,
                origin: ArticleSummaryOrigin, provenance: String? = nil, searchSuggestionsHTML: String? = nil,
                searchQueries: [String]? = nil) {
        self.searchQueries = searchQueries
        self.provenance = provenance
        self.searchSuggestionsHTML = searchSuggestionsHTML
        self.bullets = bullets
        self.provider = provider
        self.sourceURL = sourceURL
        self.sourceDomain = sourceDomain
        self.linkDomain = linkDomain
        self.origin = origin
    }

    /// What Copy puts on the pasteboard: the bullets, and where they come from when it isn't the linked page.
    public var copyText: String {
        var lines = bullets.map { "• \($0)" }
        if origin != .page {
            lines.append("")
            lines.append(String(localized: "Source: \(sourceURL.absoluteString)"))
        }
        return lines.joined(separator: "\n")
    }
}

/// What a summary is doing now.
public enum ArticleSummaryPhase: Hashable, Sendable {
    case reading
    case summarizing
    /// Looking for the same story on a free site.
    case searching
    /// Checking that a page found is the same story.
    case checking
}

/// Why there is no summary.
public enum ArticleSummaryFailure: Hashable, Sendable {
    /// The linked page couldn't be used and the same story wasn't found elsewhere. `detail` says why the search
    /// failed, when it failed (no key, a limit, an error) rather than found nothing.
    case notFoundElsewhere(why: ArticleSummaryWhy, domain: String, detail: String?)
    /// The AI service refused or failed. `reason` is in plain words.
    case aiError(reason: String)
}

public enum ArticleSummaryState: Hashable, Sendable {
    case working(ArticleSummaryPhase)
    case summary(ArticleSummary)
    case failed(ArticleSummaryFailure)
}

/// The panel's words.
public enum ArticleSummaryCopy {
    public static func paywalled(_ domain: String) -> String {
        String(localized: "\(domain) has this behind a paywall.")
    }

    public static var unreadable: String { String(localized: "Couldn’t read this article.") }

    public static func summaryFrom(_ domain: String) -> String {
        String(localized: "Summary from \(domain):")
    }

    public static var notFoundOutsidePaywall: String { String(localized: "Couldn’t find this story outside the paywall.") }
    public static var notFoundElsewhere: String { String(localized: "Couldn’t find the same story elsewhere.") }

    public static func working(_ phase: ArticleSummaryPhase) -> String {
        switch phase {
        case .reading: String(localized: "Reading the article…")
        case .summarizing: String(localized: "Summarizing…")
        case .searching: String(localized: "Looking for this story on a free site…")
        case .checking: String(localized: "Checking it’s the same story…")
        }
    }

    public static func why(_ why: ArticleSummaryWhy, domain: String) -> String {
        switch why {
        case .paywalled: paywalled(domain)
        case .unreadable: unreadable
        }
    }

    /// The line above the bullets or in place of them; nil when the summary is of the linked page itself.
    public static func header(for state: ArticleSummaryState) -> String? {
        switch state {
        case .working:
            return nil
        case let .summary(summary):
            guard case let .elsewhere(reason) = summary.origin else { return nil }
            return why(reason, domain: summary.linkDomain) + " " + summaryFrom(summary.sourceDomain)
        case let .failed(failure):
            switch failure {
            case let .notFoundElsewhere(reason, domain, _):
                return why(reason, domain: domain) + " " + (reason == .paywalled ? notFoundOutsidePaywall : notFoundElsewhere)
            case let .aiError(reason):
                return reason
            }
        }
    }

    /// The line under a summary: the provenance footer the other AI features show ("via <model> · sent to
    /// Anthropic"), or "Summary by Anthropic" for a summary kept without one.
    public static func footer(for summary: ArticleSummary) -> String {
        if let provenance = summary.provenance, !provenance.isEmpty { return provenance }
        return footer(provider: summary.provider)
    }

    /// "Summary by Anthropic".
    public static func footer(provider: String) -> String {
        provider.isEmpty ? String(localized: "AI summary") : String(localized: "Summary by \(provider)")
    }
}

// MARK: - Reading the article

/// Reads an article's text: in the app, the engine's `article.read`. Tests use a fake.
public protocol ArticleReading: Sendable {
    func readArticle(at url: URL) async throws -> ArticleResult
}

/// `article.read` over the engine's connection.
public struct EngineArticleReader: ArticleReading {
    /// A page is read in the engine within 3 s; this leaves room for the engine's own queue.
    public static let timeout: TimeInterval = 15
    private let client: @Sendable @MainActor () -> EngineClient?

    public init(client: @escaping @Sendable @MainActor () -> EngineClient?) {
        self.client = client
    }

    public func readArticle(at url: URL) async throws -> ArticleResult {
        guard let client = await client() else { throw EngineError.notConnected }
        return try await client.call("article.read", ArticleParams(url: url.absoluteString), timeout: Self.timeout)
    }
}

// MARK: - The link to summarize

/// A link to summarize, with what the card already knows about it.
public struct ArticleSummaryRequest: Equatable, Sendable {
    public var url: URL
    /// The card's title; "" when the link has no card. The page's own title is used then.
    public var headline: String
    /// The card's description.
    public var description: String

    public init(url: URL, headline: String = "", description: String = "") {
        self.url = url
        self.headline = headline
        self.description = description
    }

    /// The request for a card: the address it opens, its title and description.
    public init?(preview: LinkPreviewItem) {
        let raw = (preview.url?.isEmpty == false ? preview.url : preview.matchedURL) ?? ""
        guard let url = Self.articleURL(raw) else { return nil }
        self.init(url: url, headline: preview.title ?? "", description: preview.description ?? "")
    }

    /// The first link of a message that can be summarized: a card's, else the first link in the text. `isEmbed` says
    /// a link has its own player card (YouTube and the like), which isn't an article.
    public static func first(in message: TimelineMessage, isEmbed: (URL) -> Bool = { _ in false }) -> ArticleSummaryRequest? {
        for preview in message.linkPreviews {
            if let request = ArticleSummaryRequest(preview: preview), !isEmbed(request.url) { return request }
        }
        if let url = MessageActions.firstLink(in: message.rich), url.scheme?.lowercased() == "https",
           let article = articleURL(url.absoluteString), !isEmbed(article) {
            return ArticleSummaryRequest(url: article)
        }
        return nil
    }

    /// An https address with a host: the only kind the engine reads.
    static func articleURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

enum ArticleSummaryText {
    /// The bullets in a model's answer: lines starting "-", "*", "•" or "1.", with the marks and bold marks taken
    /// off; a line before the first bullet ("Here is a summary:") is dropped; a line after one continues it. An
    /// answer with no bullet marks becomes one bullet per line. At most 5.
    static func bullets(from raw: String) -> [String] {
        let cleaned = AIOutputFormatter.cleanMarkdown(raw)
        var bullets: [String] = []
        var loose: [String] = []
        for rawLine in cleaned.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let text = stripMarker(line) {
                bullets.append(text)
            } else if bullets.isEmpty {
                loose.append(line)
            } else {
                bullets[bullets.count - 1] += " " + line
            }
        }
        let chosen = bullets.isEmpty ? loose : bullets
        return Array(chosen.map(stripEmphasis).filter { !$0.isEmpty }.prefix(5))
    }

    private static func stripMarker(_ line: String) -> String? {
        for marker in ["• ", "- ", "* ", "– ", "— "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func stripEmphasis(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ArticleSummaryKey {
    private static let trackingParameters: Set<String> = ["fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref", "ref_src", "s_cid"]

    /// One key per article: the address without its fragment, its tracking parameters (utm_*, fbclid…) and a
    /// trailing slash, with the scheme and host in lower case.
    static func key(for url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.fragment = nil
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        let kept = (parts.queryItems ?? []).filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }
        parts.queryItems = kept.isEmpty ? nil : kept
        if parts.path.count > 1, parts.path.hasSuffix("/") { parts.path.removeLast() }
        return parts.string ?? url.absoluteString
    }

    /// A site's domain as people write it: the host without "www.".
    static func domain(of url: URL) -> String {
        var host = (url.host ?? "").lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}

/// A check made here, without the AI, before a page found by the search is even shown to the model as "the same
/// story": the page's own title or opening has to share the distinctive words of the headline. A page can't talk its
/// way past this the way it can past a yes/no question to a model: a different story, or a page that is nothing but
/// "answer YES", has none of the headline's words. It only ever says no: a page that passes still has to get a clear
/// YES from the model.
enum StoryOverlap {
    /// The share of the headline's distinctive words the page must have.
    static let minimumShare = 0.4
    /// How much of the page's text counts: its start says what it is about.
    static let textCharacters = 2500

    static func plausiblySameStory(headline: String, candidateTitle: String, candidateText: String) -> Bool {
        let wanted = words(headline)
        // A headline too short to judge (or in a language written without spaces) is left to the model.
        guard wanted.count >= 3, !hasUnspacedScript(headline) else { return true }
        let have = words(candidateTitle + " " + String(candidateText.prefix(textCharacters)))
        let hits = wanted.intersection(have).count
        return hits >= 2 && Double(hits) / Double(wanted.count) >= minimumShare
    }

    private static let filler: Set<String> = [
        "that", "this", "with", "from", "have", "will", "were", "been", "after", "before", "about", "their", "they",
        "says", "said", "over", "into", "what", "when", "your", "more", "than", "also", "amid", "news", "live",
    ]

    /// The lower-case, accent-free words of `text` that carry its meaning: four letters or more (or any with a digit),
    /// without the commonest filler.
    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var out = Set<String>()
        for word in folded.components(separatedBy: CharacterSet.alphanumerics.inverted) where !word.isEmpty {
            if (word.count >= 4 || word.contains { $0.isNumber }) && !filler.contains(word) { out.insert(word) }
        }
        return out
    }

    private static func hasUnspacedScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0E00 ... 0x0E7F, 0x3040 ... 0x30FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF: true
            default: false
            }
        }
    }
}

// MARK: - Cache

private let articleSummaryLog = Logger(subsystem: "dev.vitruvian.courier", category: "ArticleSummaries")

/// Summaries kept per link, so opening a chat again, or the same link in another chat, doesn't send the article
/// to the AI service again. Kept in memory; `enablePersistence(at:)` also keeps them in a file in the app's data
/// folder (the app does that once at start-up; tests never do). A summary is kept 30 days and at most 300 are kept.
/// Only finished summaries are kept: a failure is tried again on the next press.
@MainActor
public final class ArticleSummaryCache {
    public struct Entry: Codable, Equatable, Sendable {
        public var summary: ArticleSummary
        public var savedAt: Date
    }

    public static let fileName = "article-summaries.json"
    public static let maxEntries = 300
    /// A file bigger than this isn't read (300 summaries are far smaller): it is left alone and the cache stays in memory.
    public static let maxFileBytes = 4 << 20
    public static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    /// The app's cache. In memory until the app calls `enablePersistence(at:)`.
    public static let shared = ArticleSummaryCache()

    public private(set) var entries: [String: Entry] = [:]
    private var fileURL: URL?
    private let now: () -> Date
    private let io = DispatchQueue(label: "dev.vitruvian.courier.article-summaries")

    public init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.now = now
        if let fileURL { enablePersistence(at: fileURL) }
    }

    /// Keeps the cache in `url` from now on, reading what is there. A file that can't be read is left alone.
    public func enablePersistence(at url: URL) {
        fileURL = url
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > Self.maxFileBytes {
            articleSummaryLog.error("article-summaries.json is too big to read; it is left alone and kept in memory only")
            fileURL = nil
            return
        }
        guard let data = try? Data(contentsOf: url) else { return }
        guard let stored = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            articleSummaryLog.error("article-summaries.json couldn't be read; it is left alone and kept in memory only")
            fileURL = nil
            return
        }
        // Only a summary whose source is an https page comes back: "Open article" opens it.
        for (key, entry) in stored where entries[key] == nil && entry.summary.sourceURL.scheme?.lowercased() == "https" {
            entries[key] = entry
        }
        prune()
    }

    /// The summary kept for `key`, unless it has expired.
    public func summary(for key: String) -> ArticleSummary? {
        guard let entry = entries[key] else { return nil }
        if now().timeIntervalSince(entry.savedAt) > Self.maxAge {
            entries[key] = nil
            return nil
        }
        return entry.summary
    }

    public func store(_ summary: ArticleSummary, for key: String) {
        entries[key] = Entry(summary: summary, savedAt: now())
        prune()
        write()
    }

    public func removeAll() {
        entries = [:]
        write()
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-Self.maxAge)
        entries = entries.filter { $0.value.savedAt >= cutoff }
        if entries.count > Self.maxEntries {
            let keep = entries.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(Self.maxEntries)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }

    private func write() {
        guard let fileURL, let data = try? JSONEncoder().encode(entries) else { return }
        io.async {
            do {
                // Like the engine's own files: the folder is the person's alone (0700), and so is the file (0600).
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try data.write(to: fileURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            } catch {
                articleSummaryLog.error("article-summaries.json couldn't be written")
            }
        }
    }

    /// Waits for writes to finish (for tests).
    public func waitForWrites() {
        io.sync {}
    }
}

// MARK: - The model

/// One summary per link, as the card's panel shows it. See the file's header for the flow. Everything here is
/// keyed by the link (`ArticleSummaryKey`), so the same link in two chats shows one panel's state and one summary.
@MainActor
public final class ArticleSummaryModel: ObservableObject {
    /// The summaries in progress, finished or failed, by link. A dismissed one is gone (its finished summary stays in
    /// the cache).
    @Published public private(set) var states: [String: ArticleSummaryState] = [:]
    /// How tall Google's search suggestions are under each link's summary, in points, once the view has measured them.
    /// Part of what the timeline's rows are measured by.
    @Published public private(set) var suggestionHeights: [String: Int] = [:]

    /// The AI service in use. `bindAIProviderStore` keeps it current.
    public var aiProvider: any AIProvider = UnavailableAIProvider()
    /// The name of the AI service ("Anthropic").
    public var providerName: @MainActor () -> String = { "" }
    /// The footer under a summary (`AIProvider.provenanceFooter`).
    public var provenance: @MainActor () -> String = { "" }
    /// Whether the app is locked: nothing is read or sent while it is, and work in flight stops.
    public var isLocked: @MainActor () -> Bool = { false }
    public var reader: (any ArticleReading)?
    public let cache: ArticleSummaryCache
    /// How many pages found by the search are tried, at most.
    public var maxCandidates = 3

    private var tasks: [String: Task<Void, Never>] = [:]
    private var requests: [String: ArticleSummaryRequest] = [:]
    private var aiStoreCancellable: AnyCancellable?

    public init(cache: ArticleSummaryCache? = nil, reader: (any ArticleReading)? = nil) {
        self.cache = cache ?? .shared
        self.reader = reader
    }

    /// Keeps `aiProvider` and the service's name current from the app's `AIProviderStore`.
    public func bindAIProviderStore(_ store: AIProviderStore) {
        aiProvider = store.provider
        providerName = { [weak store] in store.map { $0.provider.providerName(preferences: $0.preferences) } ?? "" }
        provenance = { [weak store] in store.map { $0.provider.provenanceFooter(preferences: $0.preferences) } ?? "" }
        aiStoreCancellable = store.$provider.sink { [weak self] next in self?.aiProvider = next }
    }

    public static func key(for url: URL) -> String { ArticleSummaryKey.key(for: url) }

    public func state(for url: URL) -> ArticleSummaryState? { states[Self.key(for: url)] }

    /// Whether Summarize is offered for `url`: an https link, "Show link previews" on (it is the same kind of
    /// request), and an AI service ready.
    public func canSummarize(_ url: URL, showLinkPreviews: Bool) -> Bool {
        url.scheme?.lowercased() == "https"
            && LinkPreviewPolicy.mayRequest(url, showLinkPreviews: showLinkPreviews)
            && aiProvider.isAvailable
    }

    /// Starts a summary, or shows the one kept for the link, without sending anything. A summary already running
    /// for the link isn't started twice.
    public func summarize(_ request: ArticleSummaryRequest) {
        let key = Self.key(for: request.url)
        if let state = states[key] {
            switch state {
            case .working, .summary: return
            case .failed: break
            }
        }
        if let cached = cache.summary(for: key) {
            states[key] = .summary(cached)
            return
        }
        guard aiProvider.isAvailable else {
            states[key] = .failed(.aiError(reason: aiProvider.unavailableReason))
            return
        }
        requests[key] = request
        states[key] = .working(.reading)
        let provider = aiProvider
        let name = providerName()
        let footer = provenance()
        tasks[key]?.cancel()
        tasks[key] = Task { [weak self] in
            guard let self else { return }
            let outcome: Outcome
            do {
                outcome = try await self.run(request, key: key, provider: provider, providerName: name, provenance: footer)
            } catch {
                // Closed, or the app locked: the panel goes, and nothing more is sent.
                if !Task.isCancelled { self.tasks[key] = nil; self.states[key] = nil }
                return
            }
            guard !Task.isCancelled else { return }
            self.tasks[key] = nil
            switch outcome {
            case let .summary(summary):
                self.cache.store(summary, for: key)
                self.states[key] = .summary(summary)
            case let .failed(failure):
                self.states[key] = .failed(failure)
            }
        }
    }

    /// Tries the same link again after a failure.
    public func retry(_ url: URL) {
        let key = Self.key(for: url)
        guard case .failed? = states[key], let request = requests[key] else { return }
        states[key] = nil
        summarize(request)
    }

    public func suggestionsHeight(for url: URL) -> Int? { suggestionHeights[Self.key(for: url)] }

    public func setSuggestionsHeight(_ points: CGFloat, for url: URL) {
        let height = Int(points.rounded(.up))
        let key = Self.key(for: url)
        guard height > 0, height < 400, suggestionHeights[key] != height else { return }
        suggestionHeights[key] = height
    }

    /// Closes the panel. A summary in progress is stopped; a finished one stays in the cache.
    public func dismiss(_ url: URL) {
        let key = Self.key(for: url)
        tasks[key]?.cancel()
        tasks[key] = nil
        states[key] = nil
    }

    /// Stops everything in progress and closes every panel (the app locked).
    public func dismissAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]
        states = [:]
    }

    /// Waits for the summary of `url` to finish (for tests).
    public func waitForSummary(of url: URL) async {
        await tasks[Self.key(for: url)]?.value
    }

    // MARK: Flow

    private enum Outcome {
        case summary(ArticleSummary)
        case failed(ArticleSummaryFailure)
    }

    private func setPhase(_ phase: ArticleSummaryPhase, key: String) {
        guard !Task.isCancelled, case .working? = states[key] else { return }
        states[key] = .working(phase)
    }

    /// The work stopped: its panel was closed, or the app locked.
    private struct Halted: Error {}

    private func checkNotHalted() throws {
        if Task.isCancelled || isLocked() { throw Halted() }
    }

    private func run(_ request: ArticleSummaryRequest, key: String, provider: any AIProvider,
                     providerName: String, provenance: String) async throws -> Outcome {
        let linkDomain = ArticleSummaryKey.domain(of: request.url)
        try checkNotHalted()
        let page = try await read(request.url)
        // A closed panel, or a lock, stops the work: nothing more is read or sent, and a read that failed because the
        // app was locked is not "couldn't read it" (which would go on to a web search).
        try checkNotHalted()

        // The linked page itself, when it can be read.
        if let page, !page.paywalled, !page.needsBrowser, !page.text.isEmpty {
            setPhase(.summarizing, key: key)
            return await summarize(
                page, provider: provider, providerName: providerName, provenance: provenance,
                sourceURL: pageURL(page, fallback: request.url), linkDomain: linkDomain, origin: .page
            )
        }

        // Paywalled, or unreadable: the same story from a free site, if there is one.
        let why: ArticleSummaryWhy = page?.paywalled == true ? .paywalled : .unreadable
        let headline = firstNonEmpty(request.headline, page?.title)
        let description = firstNonEmpty(request.description, page?.description)
        func nothing(_ detail: String? = nil) -> Outcome {
            .failed(.notFoundElsewhere(why: why, domain: linkDomain, detail: detail))
        }
        guard !headline.isEmpty else { return nothing() }

        setPhase(.searching, key: key)
        let findings: WebSearchFindings
        let searched = await provider.findUnpaywalledSource(headline: headline, site: linkDomain, description: description)
        try checkNotHalted()
        switch searched {
        case .unsupported:
            return nothing()
        case let .unavailable(reason):
            return nothing(reason)
        case let .sources(found):
            findings = found
        }

        for source in findings.sources.prefix(maxCandidates) {
            try checkNotHalted()
            setPhase(.checking, key: key)
            let found = try await read(source.url)
            try checkNotHalted()
            guard let candidate = found, !candidate.paywalled, !candidate.needsBrowser, !candidate.text.isEmpty else { continue }
            let landed = pageURL(candidate, fallback: source.url)
            // The search can lead back to the paywalled site (a redirect, a mirror): that isn't a way round it.
            let candidateDomain = ArticleSummaryKey.domain(of: landed)
            guard candidateDomain != linkDomain, !candidateDomain.hasSuffix("." + linkDomain) else { continue }
            // A page with none of the headline's words isn't the story: it never reaches the model.
            guard StoryOverlap.plausiblySameStory(headline: headline, candidateTitle: candidate.title, candidateText: candidate.text) else { continue }
            let verdict = await provider.isSameStory(
                headline: headline, description: description,
                candidateTitle: candidate.title, candidateText: candidate.text
            )
            try checkNotHalted()
            switch verdict {
            case .same:
                setPhase(.summarizing, key: key)
                return await summarize(
                    candidate, provider: provider, providerName: providerName, provenance: provenance, sourceURL: landed,
                    linkDomain: linkDomain, origin: .elsewhere(why), searchSuggestionsHTML: findings.suggestionsHTML,
                    searchQueries: findings.searchQueries
                )
            case .different:
                continue
            case let .unavailable(reason):
                return nothing(reason)
            }
        }
        return nothing()
    }

    /// The page, or nil when it couldn't be read. A read refused because the app is locked, or cancelled, halts the
    /// work instead: it must not go on to a web search.
    private func read(_ url: URL) async throws -> ArticleResult? {
        guard let reader else { return nil }
        do {
            return try await reader.readArticle(at: url)
        } catch is CancellationError {
            throw Halted()
        } catch {
            if let engine = error as? EngineError, engine == EngineError.appLocked { throw Halted() }
            return nil
        }
    }

    private func pageURL(_ page: ArticleResult, fallback: URL) -> URL {
        URL(string: page.url).flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil } ?? fallback
    }

    private func summarize(_ page: ArticleResult, provider: any AIProvider, providerName: String, provenance: String,
                           sourceURL: URL, linkDomain: String, origin: ArticleSummaryOrigin,
                           searchSuggestionsHTML: String? = nil, searchQueries: [String] = []) async -> Outcome {
        let disposition = await provider.summarizeArticle(title: page.title, site: page.site, text: page.text)
        switch disposition {
        case let .unavailable(reason):
            return .failed(.aiError(reason: reason))
        case let .text(raw):
            let bullets = ArticleSummaryText.bullets(from: raw)
            guard !bullets.isEmpty else { return .failed(.aiError(reason: AIClientError.badResponse.message)) }
            return .summary(ArticleSummary(
                bullets: bullets, provider: providerName, sourceURL: sourceURL,
                sourceDomain: ArticleSummaryKey.domain(of: sourceURL), linkDomain: linkDomain, origin: origin,
                provenance: provenance.isEmpty ? nil : provenance, searchSuggestionsHTML: searchSuggestionsHTML,
                searchQueries: searchQueries.isEmpty ? nil : searchQueries
            ))
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty { return trimmed }
        }
        return ""
    }
}

extension AIProvider {
    /// The service's name for "Summarize with …" ("Claude", "OpenAI", "Google AI Studio").
    @MainActor
    public func summarizerName(preferences: AIPreferences) -> String {
        if let configured = self as? ConfiguredAIProvider { return configured.kind.summarizerName }
        return preferences.selectedEngine.summarizerName
    }

    /// The name of the AI service for "Summary by …".
    @MainActor
    public func providerName(preferences: AIPreferences) -> String {
        if let configured = self as? ConfiguredAIProvider { return configured.kind.label }
        return preferences.selectedEngine.label
    }
}
