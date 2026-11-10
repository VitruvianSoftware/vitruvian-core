// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public protocol ChatModelClient: Sendable {
    func listModels() async throws -> [String]
    func complete(_ turns: [AIChatTurn], model: String) async throws -> String
}

public enum AIClientError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case badKey
    case rateLimited
    case unreachable
    case server(status: Int, message: String)
    case badResponse

    public var message: String {
        switch self {
        case .notConfigured:
            String(localized: "Turn on AI and set up a provider in Settings ▸ AI.")
        case .badKey:
            String(localized: "The API key was rejected. Check your key in Settings ▸ AI.")
        case .rateLimited:
            String(localized: "Rate limit reached. Wait a moment and try again.")
        case .unreachable:
            String(localized: "Could not reach the AI provider. Check your connection or make sure the local server is running.")
        case let .server(status, detail):
            detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "The AI provider returned an error (HTTP \(status)).")
                : detail
        case .badResponse:
            String(localized: "The AI provider returned an unexpected response.")
        }
    }

    public var errorDescription: String? { message }
}

public enum AIClientHTTP {
    public static let listModelsTimeout: TimeInterval = 2.0
    public static let detectionProbeTimeout: TimeInterval = 0.4
    public static let cloudCompletionTimeout: TimeInterval = 60.0
    public static let localCompletionTimeout: TimeInterval = 180.0

    public static func send(
        _ request: URLRequest,
        using transport: any HTTPTransport
    ) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch let clientError as AIClientError {
            throw clientError
        } catch {
            throw AIClientError.unreachable
        }

        switch response.statusCode {
        case 200 ..< 300:
            return (data, response)
        case 401, 403:
            throw AIClientError.badKey
        case 429:
            throw AIClientError.rateLimited
        default:
            let message = extractErrorMessage(from: data)
            throw AIClientError.server(status: response.statusCode, message: message)
        }
    }

    public static func extractErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errorDict = json["error"] as? [String: Any],
               let message = errorDict["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let errorString = json["error"] as? String,
               !errorString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return errorString.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let message = json["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let detail = json["detail"] as? String,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return detail.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !text.hasPrefix("<") {
            return String(text.prefix(300))
        }
        return ""
    }

    public static func endpoint(baseURL: URL, path: String) -> URL {
        var baseString = baseURL.absoluteString
        while baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        if baseString.hasSuffix("/v1"), normalizedPath.hasPrefix("/v1/") {
            let strippedPath = String(normalizedPath.dropFirst("/v1".count))
            return URL(string: baseString + strippedPath) ?? baseURL.appendingPathComponent(strippedPath)
        }
        if baseString.hasSuffix("/v1beta"), normalizedPath.hasPrefix("/v1beta/") {
            let strippedPath = String(normalizedPath.dropFirst("/v1beta".count))
            return URL(string: baseString + strippedPath) ?? baseURL.appendingPathComponent(strippedPath)
        }
        return URL(string: baseString + normalizedPath) ?? baseURL.appendingPathComponent(path)
    }
}
