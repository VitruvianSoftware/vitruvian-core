// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct GeminiClient: ChatModelClient, Sendable {
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com")!

    public let baseURL: URL
    private let apiKey: String
    private let transport: any HTTPTransport

    public init(
        apiKey: String,
        baseURL: URL = GeminiClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.transport = transport
    }

    public init(
        key: String,
        baseURL: URL = GeminiClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.init(apiKey: key, baseURL: baseURL, transport: transport)
    }

    public func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIClientError.notConfigured }
        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1beta/models")
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.listModelsTimeout)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else {
            throw AIClientError.badResponse
        }

        return models.compactMap { entry -> String? in
            guard let name = entry["name"] as? String else { return nil }
            let methods = (entry["supportedGenerationMethods"] as? [String]) ?? []
            guard methods.contains("generateContent") else { return nil }
            let stripped = Self.stripModelsPrefix(name)
            return stripped.isEmpty ? nil : stripped
        }
    }

    public func complete(_ turns: [AIChatTurn], model: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIClientError.notConfigured }
        let cleanModel = Self.stripModelsPrefix(model)
        guard !cleanModel.isEmpty else { throw AIClientError.notConfigured }

        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1beta/models/\(cleanModel):generateContent")
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.cloudCompletionTimeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemText = turns
            .filter { $0.role == .system }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let contents: [[String: Any]] = turns
            .filter { $0.role != .system }
            .map { turn in
                [
                    "role": turn.role == .assistant ? "model" : "user",
                    "parts": [["text": turn.text]],
                ]
            }

        var body: [String: Any] = [
            "contents": contents,
        ]
        if !systemText.isEmpty {
            body["systemInstruction"] = [
                "parts": [["text": systemText]],
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw AIClientError.badResponse
        }

        let texts = parts.compactMap { $0["text"] as? String }
        let combined = texts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !combined.isEmpty else {
            throw AIClientError.badResponse
        }
        return combined
    }

    public static func stripModelsPrefix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("models/") {
            return String(trimmed.dropFirst("models/".count))
        }
        return trimmed
    }
}
