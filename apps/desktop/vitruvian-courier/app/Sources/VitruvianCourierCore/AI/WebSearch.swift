// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A page an AI service's own web search turned up.
public struct WebSource: Equatable, Hashable, Sendable {
    public let url: URL
    /// What the search called the page. For Google AI Studio it is the site's name, not the article's title.
    public let title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

/// What `AIProvider.findUnpaywalledSource` found.
public enum AISourceSearchDisposition: Equatable, Sendable {
    /// This service has no web search of its own (Apple Intelligence, Ollama, LM Studio, Unsloth, a custom server).
    /// Nothing was sent.
    case unsupported
    /// The service couldn't search: no key, rate limit, an error. `reason` is in plain words.
    case unavailable(reason: String)
    /// The pages the search turned up, best first, never from the paywalled site. May be empty.
    case sources([WebSource])
}

/// A chat client whose service can search the web itself while it answers (Google AI Studio's `google_search` tool,
/// OpenAI's `web_search`, Anthropic's `web_search`). The service runs the search; Courier sends only the prompt.
///
/// Each client maps its own request and answer; see `AnthropicClient.searchWeb`, `GeminiClient.searchWeb` and
/// `OpenAICompatibleClient.searchWeb`. Services that can't search don't conform.
public protocol WebSearchingClient: ChatModelClient {
    /// Whether the service this client talks to can search. `OpenAICompatibleClient` says yes only for OpenAI itself:
    /// Ollama, LM Studio and custom servers have no such tool.
    var supportsWebSearch: Bool { get }

    /// Asks the service to search the web for `prompt` and returns the pages it found, best first. Pages on
    /// `excludingDomain` (a host such as `usatoday.com`, with or without `www.`) are not returned, and the service is
    /// asked not to search it where its API allows.
    func searchWeb(prompt: String, excludingDomain: String?, model: String) async throws -> [WebSource]
}

enum WebSourceFilter {
    /// Keeps https pages, drops the excluded site (and its subdomains) and repeats, and stops at `limit`.
    static func clean(_ sources: [WebSource], excludingDomain: String?, limit: Int = 5) -> [WebSource] {
        let excluded = excludingDomain.map(normalizedHost)?.nilIfEmpty
        var seen = Set<String>()
        var out: [WebSource] = []
        for source in sources {
            guard source.url.scheme?.lowercased() == "https", let host = source.url.host?.lowercased(), !host.isEmpty else { continue }
            if let excluded, hostMatches(host, excluded) || hostMatches(normalizedHost(source.title), excluded) { continue }
            guard seen.insert(source.url.absoluteString).inserted else { continue }
            out.append(source)
            if out.count == limit { break }
        }
        return out
    }

    static func normalizedHost(_ raw: String) -> String {
        var host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func hostMatches(_ host: String, _ excluded: String) -> Bool {
        let h = normalizedHost(host)
        return h == excluded || h.hasSuffix("." + excluded)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
