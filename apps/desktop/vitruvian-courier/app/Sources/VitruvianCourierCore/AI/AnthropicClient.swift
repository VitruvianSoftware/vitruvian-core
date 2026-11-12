// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct AnthropicClient: ChatModelClient, Sendable {
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    public static let anthropicVersion = "2023-06-01"
    public static let defaultMaxTokens = 1024

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
}
