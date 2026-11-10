// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct OpenAICompatibleClient: ChatModelClient, Sendable {
    public let baseURL: URL
    public let isLocal: Bool
    private let apiKey: String?
    private let transport: any HTTPTransport

    public init(
        baseURL: URL,
        key: String? = nil,
        isLocal: Bool? = nil,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.baseURL = baseURL
        let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = (trimmedKey?.isEmpty == false) ? trimmedKey : nil
        if let isLocal {
            self.isLocal = isLocal
        } else {
            let host = baseURL.host?.lowercased() ?? ""
            self.isLocal = (host == "127.0.0.1" || host == "localhost" || host == "::1")
        }
        self.transport = transport
    }

    public init(
        baseURL: URL,
        apiKey: String?,
        isLocal: Bool? = nil,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.init(baseURL: baseURL, key: apiKey, isLocal: isLocal, transport: transport)
    }

    public init(
        _ baseURL: URL,
        _ key: String? = nil,
        isLocal: Bool? = nil,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared
    ) {
        self.init(baseURL: baseURL, key: key, isLocal: isLocal, transport: transport)
    }

    public func listModels() async throws -> [String] {
        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/models")
        var request = URLRequest(url: url, timeoutInterval: AIClientHTTP.listModelsTimeout)
        request.httpMethod = "GET"
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        return try Self.parseModels(from: data)
    }

    public func complete(_ turns: [AIChatTurn], model: String) async throws -> String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw AIClientError.notConfigured }

        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/chat/completions")
        let timeout = isLocal ? AIClientHTTP.localCompletionTimeout : AIClientHTTP.cloudCompletionTimeout
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let messages: [[String: String]] = turns.map { turn in
            [
                "role": turn.role.rawValue,
                "content": turn.text,
            ]
        }

        let body: [String: Any] = [
            "model": trimmedModel,
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, _) = try await AIClientHTTP.send(request, using: transport)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw AIClientError.badResponse
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIClientError.badResponse
        }
        return trimmed
    }

    public static func parseModels(from data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIClientError.badResponse
        }
        if let dataItems = json["data"] as? [[String: Any]] {
            return dataItems.compactMap { item -> String? in
                guard let id = item["id"] as? String else { return nil }
                let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        if let modelItems = json["models"] as? [[String: Any]] {
            return modelItems.compactMap { item -> String? in
                let raw = (item["id"] as? String) ?? (item["name"] as? String)
                guard let raw else { return nil }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        throw AIClientError.badResponse
    }
}
