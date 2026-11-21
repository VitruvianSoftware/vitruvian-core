// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct AnthropicClient: WebSearchingClient, Sendable {
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    public static let anthropicVersion = "2023-06-01"
    public static let defaultMaxTokens = 1024
    /// The basic web search tool: available on every model that has web search, with no code-execution step.
    /// Docs: platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool
    public static let webSearchToolType = "web_search_20250305"
    public static let webSearchMaxUses = 3

    public let baseURL: URL
    private let apiKey: String
    private let transport: any HTTPTransport

    public init(
        apiKey: String,
        baseURL: URL = AnthropicClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.transport = transport
    }

    public init(
        key: String,
        baseURL: URL = AnthropicClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.init(apiKey: key, baseURL: baseURL, transport: transport)
    }

    public func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIClientError.notConfigured }
        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1/models")
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.listModelsTimeout)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]]
        else {
            throw AIClientError.badResponse
        }
        return items.compactMap { item -> String? in
            guard let id = item["id"] as? String else { return nil }
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    public func complete(_ turns: [AIChatTurn], model: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIClientError.notConfigured }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIClientError.notConfigured }

        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1/messages")
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.cloudCompletionTimeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemText = turns
            .filter { $0.role == .system }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let messageTurns: [[String: String]] = turns
            .filter { $0.role != .system }
            .map { turn in
                [
                    "role": turn.role == .assistant ? "assistant" : "user",
                    "content": turn.text,
                ]
            }

        var body: [String: Any] = [
            "model": trimmedModel,
            "max_tokens": Self.defaultMaxTokens,
            "messages": messageTurns,
        ]
        if !systemText.isEmpty {
            body["system"] = systemText
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else {
            throw AIClientError.badResponse
        }
        let texts = content.compactMap { block -> String? in
            if let type = block["type"] as? String, type != "text" {
                return nil
            }
            return block["text"] as? String
        }
        let combined = texts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw AIClientError.badResponse
        }
        return combined
    }

    // MARK: - Web search

    public var supportsWebSearch: Bool { true }

    /// Messages API with the `web_search` server tool. The sources are what Claude cited, then every result the search
    /// returned. A search that fails inside a 200 answer (`web_search_tool_result_error`) gives no sources.
    public func searchWeb(prompt: String, excludingDomain: String?, model: String) async throws -> WebSearchFindings {
        guard !apiKey.isEmpty else { throw AIClientError.notConfigured }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIClientError.notConfigured }

        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1/messages")
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.cloudCompletionTimeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var tool: [String: Any] = [
            "type": Self.webSearchToolType,
            "name": "web_search",
            "max_uses": Self.webSearchMaxUses,
        ]
        if let domain = excludingDomain.map(WebSourceFilter.normalizedHost), !domain.isEmpty {
            tool["blocked_domains"] = [domain]
        }
        let body: [String: Any] = [
            "model": trimmedModel,
            "max_tokens": Self.defaultMaxTokens,
            "messages": [["role": "user", "content": prompt]],
            "tools": [tool],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        return WebSearchFindings(sources: WebSourceFilter.clean(try Self.parseWebSources(from: data), excludingDomain: excludingDomain))
    }

    /// Reads the pages out of a Messages answer that used the web search tool: the `web_search_result_location`
    /// citations on its text blocks first (what Claude relied on), then the `web_search_result` entries.
    public static func parseWebSources(from data: Data) throws -> [WebSource] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else {
            throw AIClientError.badResponse
        }
        var cited: [WebSource] = []
        var found: [WebSource] = []
        for block in content {
            switch block["type"] as? String {
            case "text":
                for citation in (block["citations"] as? [[String: Any]]) ?? [] {
                    if let source = webSource(citation) { cited.append(source) }
                }
            case "web_search_tool_result":
                // On an error `content` is one object, not a list: nothing to read.
                for result in (block["content"] as? [[String: Any]]) ?? [] where (result["type"] as? String) == "web_search_result" {
                    if let source = webSource(result) { found.append(source) }
                }
            default:
                break
            }
        }
        return cited + found
    }

    private static func webSource(_ entry: [String: Any]) -> WebSource? {
        guard let raw = entry["url"] as? String, let url = URL(string: raw) else { return nil }
        return WebSource(url: url, title: (entry["title"] as? String) ?? "")
    }
}
