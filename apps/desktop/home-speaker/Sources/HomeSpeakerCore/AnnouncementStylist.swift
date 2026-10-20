// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

// Rewording a coding agent's reply before it is spoken
// (`announcement_style`): "As written" reads the reply cleaned for speech,
// as HomeSpeaker always has; the other styles have a language model say it
// again in a sentence or two. The model is the user's choice
// (`style_model`): Gemini with the saved key, else Apple's on-device model,
// else the reply as written. Whatever comes back is cleaned for speech
// again, because models still say file paths and markdown when told not to.

/// Words an announcement in the configured style. Never throws and never
/// returns nothing for text that cleans to something.
public protocol AnnouncementStyling: Sendable {
    func style(_ text: String, config: SpeakerConfig) async -> String
}

/// One model that rewrites text by an instruction.
public protocol StyleRewriting: Sendable {
    /// `apiKey` is the Gemini key for a model that needs one; nil otherwise.
    func rewrite(_ text: String, instructions: String, apiKey: String?) async throws -> String
}

public enum StyleRewriteError: LocalizedError, Equatable {
    case timedOut
    case unavailable(String)
    case badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "The model did not answer in time."
        case .unavailable(let why): return why
        case .badResponse(let why): return why
        }
    }
}

public struct AnnouncementStylist: AnnouncementStyling {
    public static let logger = Logger(subsystem: "com.vitruviansoftware.homespeaker", category: "style")

    /// Each model gets this long before the next one is tried.
    public static let modelTimeout: Double = 4

    /// The most a rewrite can add to an announcement: both models timing out.
    public static let worstCaseSeconds: Double = modelTimeout * 2

    /// What a model sees of the reply, at most. Apple's on-device model has
    /// a small context; the start of a reply carries its point.
    static let inputLimit = 3000

    let gemini: StyleRewriting
    let apple: StyleRewriting
    let geminiKey: @Sendable () -> String?
    let timeout: Double
    let log: @Sendable (String) -> Void

    public init(
        gemini: StyleRewriting = GeminiStyleRewriter(),
        apple: StyleRewriting = AppleStyleRewriter(),
        geminiKey: @escaping @Sendable () -> String? = { SecretStore.shared.load().geminiApiKey },
        timeout: Double = AnnouncementStylist.modelTimeout,
        log: @escaping @Sendable (String) -> Void = { AnnouncementStylist.logger.notice("\($0, privacy: .public)") }
    ) {
        self.gemini = gemini
        self.apple = apple
        self.geminiKey = geminiKey
        self.timeout = timeout
        self.log = log
    }

    /// True when `config` asks for a rewrite: any style but "As written",
    /// and a custom style only once it has an instruction.
    public static func rewrites(_ config: SpeakerConfig) -> Bool {
        switch config.effectiveAnnouncementStyle {
        case .verbatim: return false
        case .custom: return !config.effectiveCustomStylePrompt.isEmpty
        default: return true
        }
    }

    public func style(_ text: String, config: SpeakerConfig) async -> String {
        let length = config.effectiveSpeechLength
        guard Self.rewrites(config), let instructions = Self.instructions(for: config) else {
            return GoogleHomeClient.cleanForSpeech(text, length: length)
        }
        let input = Self.modelInput(text)
        guard !input.isEmpty else { return GoogleHomeClient.cleanForSpeech(text, length: length) }

        if config.effectiveStyleModel == .gemini {
            let key = geminiKey()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                log("Style with Gemini: no Gemini API key saved; using Apple's on-device model.")
            } else if let out = await attempt(gemini, input, instructions, key: key, name: "Gemini", length: length) {
                return out
            }
        }
        if let out = await attempt(apple, input, instructions, key: nil, name: "Apple's on-device model", length: length) {
            return out
        }
        return GoogleHomeClient.cleanForSpeech(text, length: length)
    }

    /// One model, under the time limit; nil when it failed or said nothing
    /// that survives cleaning.
    private func attempt(
        _ model: StyleRewriting, _ input: String, _ instructions: String, key: String?, name: String,
        length: SpeechLength
    ) async -> String? {
        do {
            let raw = try await Self.withTimeLimit(timeout) {
                try await model.rewrite(input, instructions: instructions, apiKey: key)
            }
            let spoken = GoogleHomeClient.cleanForSpeech(raw, length: length)
            if spoken.isEmpty {
                log("\(name) returned nothing to say; trying the next way.")
                return nil
            }
            return spoken
        } catch {
            log("\(name) could not restyle the announcement (\(error.localizedDescription)); trying the next way.")
            return nil
        }
    }

    // MARK: Pure rules (tested)

    /// What every style shares: speakable, short, and true to the reply.
    static let baseInstructions = """
        You rewrite a message from a coding assistant into what a smart speaker will say aloud to the person \
        who asked for the work. Reply with only the words to speak: one or two short sentences of plain \
        spoken English. No markdown, lists, code, file paths, URLs, commands or emoji. Keep the facts and \
        never add any. If something failed or needs the person's attention, say so.
        """

    /// The instruction for `config`'s style; nil for "As written" and for a
    /// custom style without one.
    public static func instructions(for config: SpeakerConfig) -> String? {
        let style: String
        switch config.effectiveAnnouncementStyle {
        case .verbatim: return nil
        case .plain: style = "Summarise what happened plainly and simply."
        case .briefing: style = "Say it as a short status update: what was done, then what is next or needs attention."
        case .casual: style = "Say it warmly and casually, the way a helpful colleague would in passing."
        case .custom:
            let custom = config.effectiveCustomStylePrompt
            guard !custom.isEmpty else { return nil }
            style = "Style: \(custom)"
        }
        return baseInstructions + "\n" + style
    }

    /// The reply as a model should see it: no code blocks, one line, capped.
    static func modelInput(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > inputLimit ? String(s.prefix(inputLimit)) : s
    }

    /// Runs `body`, throwing `StyleRewriteError.timedOut` after `seconds`.
    static func withTimeLimit<T: Sendable>(
        _ seconds: Double, _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw StyleRewriteError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw StyleRewriteError.timedOut }
            return first
        }
    }
}

// MARK: - Gemini

/// Gemini's text model through the REST API, with the key in a header
/// (never the URL, which ends up in logs).
public struct GeminiStyleRewriter: StyleRewriting {
    /// Fast and stable; thinking is switched off below so it answers well
    /// inside `AnnouncementStylist.modelTimeout`.
    public static let model = "gemini-3.5-flash"
    public static var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let send: Send

    public init(send: @escaping Send = { try await URLSession.shared.data(for: $0) }) {
        self.send = send
    }

    public func rewrite(_ text: String, instructions: String, apiKey: String?) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw StyleRewriteError.unavailable("No Gemini API key.") }
        let (data, response) = try await send(Self.request(text, instructions: instructions, apiKey: apiKey))
        try GeminiAPI.check(response, data)
        return try Self.parse(data)
    }

    static func request(_ text: String, instructions: String, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instructions]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": [
                "temperature": 0.4,
                "maxOutputTokens": 200,
                "thinkingConfig": ["thinkingBudget": 0],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The text of the first candidate's parts, joined.
    static func parse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw StyleRewriteError.badResponse("Gemini's answer had no text.")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StyleRewriteError.badResponse("Gemini's answer had no text.") }
        return text
    }
}

/// What the Gemini API's callers share.
enum GeminiAPI {
    /// Throws for anything but a 2xx, with Google's own message when there
    /// is one ("API key not valid…"), never the key.
    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiAPIError(status: http.statusCode, message: message(in: data))
        }
    }

    /// `{"error": {"message": …}}`, or that inside a list, as the
    /// Interactions API answers (seen live, 2026-10-19).
    static func message(in data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data)
        let object = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
        guard let error = object?["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}

public struct GeminiAPIError: LocalizedError, Equatable {
    public let status: Int
    public let message: String?

    public var errorDescription: String? {
        "Gemini answered \(status)" + (message.map { ": \($0)" } ?? "")
    }
}

// MARK: - Apple on-device

/// Apple's on-device model (FoundationModels), on macOS 26 and later with
/// Apple Intelligence on. Unavailable is an error, so the stylist falls
/// back to the reply as written.
public struct AppleStyleRewriter: StyleRewriting {
    public init() {}

    public func rewrite(_ text: String, instructions: String, apiKey: String?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                throw StyleRewriteError.unavailable("Apple's on-device model is not available on this Mac.")
            }
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: text)
            return response.content
        }
        #endif
        throw StyleRewriteError.unavailable("Apple's on-device model needs macOS 26 or later.")
    }
}
