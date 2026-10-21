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

public enum PhoneSpeakResult: Equatable, Sendable {
    case spoken
    case skipped(String)
}

public enum PhoneSpeechError: LocalizedError, Equatable, Sendable {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let reason): return reason
        }
    }
}

public protocol PhoneSpeaking: Sendable {
    func speak(
        _ text: String,
        wav: Data?,
        pauseMedia: Bool,
        headphonesOnly: Bool
    ) async throws -> PhoneSpeakResult
}

/// Speaks an announcement on the paired Android phone via the local
/// `vitruvian-remote-agent` daemon (`POST /v1/homespeaker/phone-say`).
public struct PhoneSpeaker: PhoneSpeaking {
    public static let shared = PhoneSpeaker()

    public static let logger = Logger(subsystem: "com.vitruviansoftware.homespeaker", category: "phone-speech")

    public static let fallbackEndpoint = URL(string: "http://127.0.0.1:7411/v1/homespeaker/phone-say")!

    public static var defaultEndpoint: URL {
        let raw = ProcessInfo.processInfo.environment["HOMESPEAKER_REMOTE_AGENT_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty, let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return fallbackEndpoint
    }

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public let endpoint: URL
    let send: Send

    public init(
        endpoint: URL = PhoneSpeaker.defaultEndpoint,
        send: @escaping Send = { try await URLSession.shared.data(for: $0) }
    ) {
        self.endpoint = endpoint
        self.send = send
    }

    public func speak(
        _ text: String,
        wav: Data?,
        pauseMedia: Bool,
        headphonesOnly: Bool
    ) async throws -> PhoneSpeakResult {
        var payload: [String: Any] = [
            "text": text,
            "pause_media": pauseMedia,
            "headphones_only": headphonesOnly,
        ]
        if let wav {
            payload["wav_base64"] = wav.base64EncodedString()
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = max(75, LocalSpeaker.estimatedSeconds(for: text) + 30)
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await send(request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw PhoneSpeechError.failed("Timed out waiting for phone to finish speaking")
        } catch is URLError {
            throw PhoneSpeechError.failed("Vitruvian Remote Agent is not reachable on this Mac")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let skippedStr = (json?["skipped"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !skippedStr.isEmpty {
            let reason = (json?["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .skipped((reason?.isEmpty == false ? reason : nil) ?? skippedStr)
        }
        if (json?["skipped"] as? Bool) == true {
            let reason = (json?["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .skipped((reason?.isEmpty == false ? reason : nil) ?? "skipped on phone")
        }
        if status == 200, (json?["ok"] as? Bool) == true, (json?["spoken"] as? Bool) == true {
            return .spoken
        }
        let reason = (json?["reason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorMsg = (json?["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (reason?.isEmpty == false ? reason : nil)
            ?? (errorMsg?.isEmpty == false ? errorMsg : nil)
            ?? "Phone agent returned HTTP \(status)"
        throw PhoneSpeechError.failed(detail)
    }
}
