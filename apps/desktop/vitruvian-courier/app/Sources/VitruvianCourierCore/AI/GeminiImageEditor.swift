// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The Google AI Studio image model that edits photos ("Nano Banana").
public enum GeminiImageModel {
    /// Nano Banana 2.1, the newest of the Nano Banana models in Google's Gemini API docs (checked 2026-11-21 at
    /// ai.google.dev/gemini-api/docs/image-generation and /docs/models/gemini-nano-banana-2.1). The docs call
    /// `gemini-2.5-flash-image` the legacy one and `gemini-3.1-flash-image` the previous generation.
    public static let `default` = "gemini-nano-banana-2.1"
}

/// Edits a photo with Google AI Studio's "Nano Banana" image model, through `generateContent`: the instruction and the
/// photo go in as parts of one message, and the edited picture comes back as an inline-data part. The key goes in the
/// `x-goog-api-key` header only. Google's docs list image models as paid-tier only, so a free key is answered with a
/// quota error, which maps to `.needsPaidAccess`.
public struct GeminiImageEditor: AIImageEditor, CustomStringConvertible, CustomDebugStringConvertible {
    public static let timeout: TimeInterval = 120

    public let provider: AIProviderKind = .googleAIStudio
    public let baseURL: URL
    public let model: String
    private let apiKey: String
    private let transport: any HTTPTransport
    private let maxUploadBytes: Int

    public init(
        apiKey: String,
        model: String = GeminiImageModel.default,
        baseURL: URL = GeminiClient.defaultBaseURL,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared,
        maxUploadBytes: Int = PhotoEditPreparer.maxUploadBytes
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = GeminiClient.stripModelsPrefix(model)
        self.baseURL = baseURL
        self.transport = transport
        self.maxUploadBytes = maxUploadBytes
    }

    public var description: String { "GeminiImageEditor(model: \(model), key: <redacted>)" }
    public var debugDescription: String { description }

    public func edit(image: Data, mimeType _: String, instruction: String) async -> ImageEditResult {
        guard !apiKey.isEmpty, !model.isEmpty else { return .failure(.noKey) }
        let prepared: PreparedPhoto
        do {
            prepared = try PhotoEditPreparer.prepare(image, maxBytes: maxUploadBytes)
        } catch PhotoEditPreparer.Failure.tooLarge {
            return .failure(.tooLarge)
        } catch {
            return .failure(.unreadablePhoto)
        }

        let request: URLRequest
        do {
            request = try makeRequest(photo: prepared, instruction: instruction)
        } catch {
            return .failure(.unreadablePhoto)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let urlError as URLError where urlError.code == .cancelled {
            return .failure(.cancelled)
        } catch {
            return .failure(.network)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            return .failure(Self.failure(status: response.statusCode, body: data, key: apiKey))
        }
        return Self.parse(data, key: apiKey)
    }

    /// The request that would be sent: exposed so tests can read it without a network.
    func makeRequest(photo: PreparedPhoto, instruction: String) throws -> URLRequest {
        let url = AIClientHTTP.endpoint(baseURL: baseURL, path: "/v1beta/models/\(model):generateContent")
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [[
                "role": "user",
                "parts": [
                    ["text": PhotoEditPrompt.wrap(instruction)],
                    ["inlineData": ["mimeType": photo.mimeType, "data": photo.data.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["responseModalities": ["TEXT", "IMAGE"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    private static let blockedFinishReasons: Set<String> = [
        "SAFETY", "IMAGE_SAFETY", "PROHIBITED_CONTENT", "IMAGE_PROHIBITED_CONTENT", "BLOCKLIST", "SPII",
        "RECITATION", "IMAGE_RECITATION",
    ]

    static func parse(_ data: Data, key: String) -> ImageEditResult {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.noImageReturned(note: nil))
        }
        if let feedback = json["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String, !reason.isEmpty
        {
            return .failure(.refused)
        }
        let candidates = (json["candidates"] as? [[String: Any]]) ?? []
        guard let candidate = candidates.first else { return .failure(.noImageReturned(note: nil)) }
        let parts = ((candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        for part in parts {
            let inline = (part["inlineData"] as? [String: Any]) ?? (part["inline_data"] as? [String: Any])
            guard let inline, let encoded = inline["data"] as? String,
                  let bytes = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), !bytes.isEmpty
            else { continue }
            // The type the service claims is ignored: the bytes must really be a picture of a safe size.
            guard let edited = EditedImage.validated(bytes) else { continue }
            return .success(edited)
        }
        if let reason = candidate["finishReason"] as? String, blockedFinishReasons.contains(reason) {
            return .failure(.refused)
        }
        let said = ImageEditText.scrub(parts.compactMap { $0["text"] as? String }.joined(separator: " "), key: key)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(.noImageReturned(note: said.isEmpty ? nil : String(said.prefix(300))))
    }

    static func failure(status: Int, body: Data, key: String) -> ImageEditFailure {
        let detail = ImageEditText.errorDetail(from: body, key: key)
        let lowered = detail.lowercased()
        switch status {
        case 413:
            return .tooLarge
        case 401:
            return .keyRejected
        case 403:
            return lowered.contains("billing") || lowered.contains("paid") || lowered.contains("free tier")
                ? .needsPaidAccess : .keyRejected
        case 429:
            // A free key has a limit of 0 for image models.
            return lowered.contains("limit: 0") || lowered.contains("free_tier") || lowered.contains("free tier")
                || lowered.contains("billing") ? .needsPaidAccess : .rateLimited
        case 400:
            if lowered.contains("api key") || lowered.contains("api_key") { return .keyRejected }
            if lowered.contains("too large") || lowered.contains("exceeds") || lowered.contains("size limit") {
                return .tooLarge
            }
            return .server(status: status, detail: detail)
        default:
            return .server(status: status, detail: detail)
        }
    }
}
