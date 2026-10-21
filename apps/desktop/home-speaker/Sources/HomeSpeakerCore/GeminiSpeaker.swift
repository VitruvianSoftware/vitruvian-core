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

import AVFoundation
import CryptoKit
import Foundation
import os

// Speaking on this Mac in a Gemini voice (`local_engine: gemini`): the
// announcement goes to Gemini's speech model, which answers with audio, and
// the audio plays from memory. The announcer falls back to the Mac voice
// whenever this throws, so a missing key, no network or a refusal never
// leaves the Mac silent.

/// Says text in a Gemini voice and returns once it has finished playing.
public protocol GeminiSpeaking: Sendable {
    /// `started` is told the audio's length in seconds just before it plays,
    /// so a media pause can be held for exactly that long.
    func speak(
        _ text: String, voice: String, apiKey: String, started: @escaping @Sendable (Double) async -> Void
    ) async throws

    /// Synthesizes `text` as a playable WAV without playing it locally, so
    /// the phone output can stream the WAV to Android.
    func synthesizeWAV(_ text: String, voice: String, apiKey: String) async throws -> Data?
}

extension GeminiSpeaking {
    public func synthesizeWAV(_ text: String, voice: String, apiKey: String) async throws -> Data? { nil }
}

/// Plays a WAV held in memory and returns when it ends.
public protocol AudioPlaying: Sendable {
    func play(_ wav: Data) async throws
}

public enum GeminiSpeechError: LocalizedError, Equatable {
    case timedOut
    case noAudio
    case unplayable

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "Gemini did not answer in time."
        case .noAudio: return "Gemini's answer had no audio."
        case .unplayable: return "Gemini's audio could not be played."
        }
    }
}

public struct GeminiAudioCache: Sendable {
    public static let shared = GeminiAudioCache()

    public let directory: URL
    public let limit: Int

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.vitruviansoftware.homespeaker/gemini-tts", isDirectory: true)
    }

    public init(directory: URL = GeminiAudioCache.defaultDirectory(), limit: Int = BroadcastHistory.limit) {
        self.directory = directory
        self.limit = max(1, limit)
    }

    public static func fileName(text: String, voice: String, model: String = GeminiSpeaker.model) -> String {
        let digest = SHA256.hash(data: Data("\(model)\0\(voice)\0\(text)".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(hex).wav"
    }

    public func read(text: String, voice: String) -> Data? {
        let url = directory.appendingPathComponent(Self.fileName(text: text, voice: voice))
        guard let data = try? Data(contentsOf: url),
              GeminiSpeaker.duration(ofWAV: data) != nil else {
            return nil
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public func write(_ wav: Data, text: String, voice: String) {
        guard GeminiSpeaker.duration(ofWAV: wav) != nil else { return }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(Self.fileName(text: text, voice: voice))
            try wav.write(to: url, options: .atomic)
            prune()
        } catch {
            GeminiSpeaker.logger.error("Could not cache Gemini audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prune() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let wavs = urls.filter { $0.pathExtension.lowercased() == "wav" }
        guard wavs.count > limit else { return }
        let sorted = wavs.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if dateA != dateB { return dateA > dateB }
            return a.lastPathComponent < b.lastPathComponent
        }
        for stale in sorted.dropFirst(limit) {
            try? fm.removeItem(at: stale)
        }
    }
}

public struct GeminiSpeaker: GeminiSpeaking {
    public static let logger = Logger(subsystem: "com.vitruviansoftware.homespeaker", category: "gemini-speech")

    /// The current speech model, through the Interactions API. A unary
    /// request answers with a WAV (24 kHz, 16-bit, mono).
    public static let model = "gemini-3.8-flash-tts"
    /// Lighter Interactions API speech model with an independent daily quota
    /// bucket, used when `model` is rate-limited (HTTP 429).
    public static let fallbackModel = "gemini-3.8-flash-lite-tts"
    public static let interactionsEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!
    /// The earlier speech model, through `generateContent`, for a key or
    /// region the Interactions API answers 404 for (or when both 3.8 models
    /// are rate-limited). It answers headerless
    /// PCM (`audio/L16;codec=pcm;rate=24000`). Google retires it on
    /// 2026-11-17; after that the 404 simply falls through to the Mac voice.
    public static let legacyModel = "gemini-2.5-flash-preview-tts"
    public static var legacyEndpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(legacyModel):generateContent")!
    }

    /// How long synthesis may take before the Mac voice takes over.
    public static let synthesisTimeout: Double = 12

    public typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let send: Send
    let player: AudioPlaying
    let timeout: Double
    public let cache: GeminiAudioCache?

    public init(
        send: @escaping Send = { try await URLSession.shared.data(for: $0) },
        player: AudioPlaying = InMemoryAudioPlayer(),
        timeout: Double = GeminiSpeaker.synthesisTimeout,
        cache: GeminiAudioCache? = nil
    ) {
        self.send = send
        self.player = player
        self.timeout = timeout
        self.cache = cache
    }

    public func speak(
        _ text: String, voice: String, apiKey: String, started: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let wav = try await synthesize(text, voice: voice, apiKey: apiKey)
        let seconds = Self.duration(ofWAV: wav) ?? LocalSpeaker.estimatedSeconds(for: text)
        await started(seconds)
        // A backstop, as for the Mac voice: an output that never reports
        // the end must not wedge the caller.
        let player = self.player
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await player.play(wav) }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds + 10))
                throw LocalSpeechError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    /// The announcement as a playable WAV, within `timeout`.
    public func synthesize(_ text: String, voice: String, apiKey: String) async throws -> Data {
        if let cached = cache?.read(text: text, voice: voice) {
            return cached
        }
        let send = self.send
        let wav = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                do {
                    let (data, response) = try await send(Self.interactionsRequest(text, voice: voice, apiKey: apiKey))
                    try GeminiAPI.check(response, data)
                    return try Self.audio(fromResponse: data)
                } catch let error as GeminiAPIError where error.status == 429 {
                    do {
                        let (data, response) = try await send(Self.interactionsRequest(text, voice: voice, apiKey: apiKey, model: Self.fallbackModel))
                        try GeminiAPI.check(response, data)
                        return try Self.audio(fromResponse: data)
                    } catch let fallbackError as GeminiAPIError where fallbackError.status == 404 || fallbackError.status == 429 {
                        let (data, response) = try await send(Self.legacyRequest(text, voice: voice, apiKey: apiKey))
                        try GeminiAPI.check(response, data)
                        return try Self.audio(fromResponse: data)
                    }
                } catch let error as GeminiAPIError where error.status == 404 {
                    let (data, response) = try await send(Self.legacyRequest(text, voice: voice, apiKey: apiKey))
                    try GeminiAPI.check(response, data)
                    return try Self.audio(fromResponse: data)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw GeminiSpeechError.timedOut
            }
            defer { group.cancelAll() }
            guard let wav = try await group.next() else { throw GeminiSpeechError.timedOut }
            return wav
        }
        cache?.write(wav, text: text, voice: voice)
        return wav
    }

    public func synthesizeWAV(_ text: String, voice: String, apiKey: String) async throws -> Data? {
        try await synthesize(text, voice: voice, apiKey: apiKey)
    }

    // MARK: Requests

    static func interactionsRequest(_ text: String, voice: String, apiKey: String, model: String = GeminiSpeaker.model) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "input": [["type": "user_input", "content": [["type": "text", "text": text]]]],
            "response_format": ["type": "audio"],
            "generation_config": ["speech_config": [["voice": voice]]],
        ]
        return try post(interactionsEndpoint, body, apiKey: apiKey)
    }

    static func legacyRequest(_ text: String, voice: String, apiKey: String) throws -> URLRequest {
        let body: [String: Any] = [
            "contents": [["parts": [["text": text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": ["voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]],
            ],
        ]
        return try post(legacyEndpoint, body, apiKey: apiKey)
    }

    /// The key goes in a header, never the URL.
    private static func post(_ url: URL, _ body: [String: Any], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Pure rules (tested)

    /// The audio in either API's answer, as a WAV: the Interactions API's
    /// `steps[].content[]` audio block (the last one), or `generateContent`'s
    /// `inlineData`. Raw PCM gets a WAV header.
    public static func audio(fromResponse data: Data) throws -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiSpeechError.noAudio
        }
        var found: (data: String, mime: String?)?
        if let steps = json["steps"] as? [[String: Any]] {
            for step in steps where (step["type"] as? String) == "model_output" {
                for block in step["content"] as? [[String: Any]] ?? [] where (block["type"] as? String) == "audio" {
                    if let b64 = block["data"] as? String {
                        found = (b64, (block["mime_type"] as? String) ?? (block["mimeType"] as? String))
                    }
                }
            }
        }
        if found == nil, let candidates = json["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            for part in parts {
                if let inline = (part["inlineData"] ?? part["inline_data"]) as? [String: Any],
                   let b64 = inline["data"] as? String {
                    found = (b64, (inline["mimeType"] as? String) ?? (inline["mime_type"] as? String))
                }
            }
        }
        guard let found, let bytes = Data(base64Encoded: found.data), !bytes.isEmpty else {
            throw GeminiSpeechError.noAudio
        }
        return wav(from: bytes, mimeType: found.mime)
    }

    /// `bytes` as they are when they already are a WAV ("RIFF"); otherwise
    /// 16-bit mono PCM at the MIME type's `rate=` (24 kHz if none), under a
    /// 44-byte WAV header.
    public static func wav(from bytes: Data, mimeType: String?) -> Data {
        if bytes.starts(with: Array("RIFF".utf8)) { return bytes }
        var rate = 24000
        if let mimeType, let range = mimeType.range(of: "rate=(\\d+)", options: .regularExpression) {
            rate = Int(mimeType[range].dropFirst("rate=".count)) ?? rate
        }
        return wavHeader(pcmBytes: bytes.count, sampleRate: rate) + bytes
    }

    static func wavHeader(pcmBytes: Int, sampleRate: Int, channels: Int = 1, bitsPerSample: Int = 16) -> Data {
        func le32(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(v).littleEndian, Array.init) }
        func le16(_ v: Int) -> [UInt8] { withUnsafeBytes(of: UInt16(v).littleEndian, Array.init) }
        let blockAlign = channels * bitsPerSample / 8
        var h: [UInt8] = []
        h += Array("RIFF".utf8) + le32(36 + pcmBytes) + Array("WAVE".utf8)
        h += Array("fmt ".utf8) + le32(16) + le16(1) + le16(channels) + le32(sampleRate)
        h += le32(sampleRate * blockAlign) + le16(blockAlign) + le16(bitsPerSample)
        h += Array("data".utf8) + le32(pcmBytes)
        return Data(h)
    }

    /// Seconds of audio in a PCM WAV, from its `fmt ` byte rate and its
    /// `data` chunk; nil when it does not read as one.
    public static func duration(ofWAV wav: Data) -> Double? {
        let b = [UInt8](wav)
        guard b.count >= 12, b.starts(with: Array("RIFF".utf8)) else { return nil }
        func u32(_ i: Int) -> Int {
            Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        var i = 12
        var byteRate: Int?
        while i + 8 <= b.count {
            let id = String(bytes: b[i..<i + 4], encoding: .ascii)
            let size = u32(i + 4)
            if id == "fmt ", i + 16 <= b.count { byteRate = u32(i + 16) }
            if id == "data", let byteRate, byteRate > 0 {
                // A streamed WAV may say 0xFFFFFFFF; what is there counts.
                let available = min(size, b.count - (i + 8))
                return Double(available) / Double(byteRate)
            }
            i += 8 + size + (size & 1)
        }
        return nil
    }
}

// MARK: - Playing from memory

/// `AVAudioPlayer(data:)`, waited on through its delegate.
public struct InMemoryAudioPlayer: AudioPlaying {
    public init() {}

    public func play(_ wav: Data) async throws {
        let waiter = try PlaybackWaiter(wav: wav)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                waiter.start(continuation: cont)
            }
        } onCancel: {
            waiter.stop()
        }
        withExtendedLifetime(waiter) {}
    }
}

/// Resumes its continuation exactly once: when playing ends, fails, or the
/// waiting task is cancelled (which stops the audio).
private final class PlaybackWaiter: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let player: AVAudioPlayer
    private var continuation: CheckedContinuation<Void, Error>?
    private var done = false

    init(wav: Data) throws {
        player = try AVAudioPlayer(data: wav)
        super.init()
        player.delegate = self
    }

    func start(continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if done {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
        player.prepareToPlay()
        if !player.play() { finish(GeminiSpeechError.unplayable) }
    }

    func stop() {
        finish(CancellationError())
        player.stop()
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        done = true
        lock.unlock()
        if let error { cont?.resume(throwing: error) } else { cont?.resume() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(flag ? nil : GeminiSpeechError.unplayable)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(error ?? GeminiSpeechError.unplayable)
    }
}
