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
import Foundation
import os

// Speaking on this Mac (docs/local-speech.md): the same announcement the
// Google Home speakers get, read by a system voice through this Mac's own
// output at its current volume.

/// One installed voice, reduced to what the picker and the fallback need.
public struct LocalVoice: Equatable, Hashable, Identifiable, Sendable {
    /// Apple's three voice tiers. Ordered so the best compares greatest.
    public enum Quality: Int, Comparable, Sendable {
        case standard = 1, enhanced, premium

        public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .standard: return "Default"
            case .enhanced: return "Enhanced"
            case .premium: return "Premium"
            }
        }
    }

    /// The `AVSpeechSynthesisVoice` identifier, as stored in `local_voice`.
    public let id: String
    public let name: String
    /// BCP-47 language, "en-US".
    public let language: String
    public let quality: Quality

    public init(id: String, name: String, language: String, quality: Quality) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }

    /// "Ava (en-US) · Premium", for the Settings picker.
    public var pickerLabel: String { "\(name) (\(language)) · \(quality.label)" }

    var isEnglish: Bool { language.lowercased().hasPrefix("en") }
    var isUSEnglish: Bool { language.replacingOccurrences(of: "_", with: "-").lowercased() == "en-us" }
}

/// The speech engine, behind a protocol so tests never make a sound.
public protocol SpeechSynthesizing: Sendable {
    func installedVoices() -> [LocalVoice]
    /// Speaks `text` and returns once the speech has finished (or was
    /// cancelled). `voiceID` nil means the system's default voice.
    func speak(_ text: String, voiceID: String?) async throws
}

public enum LocalSpeechError: LocalizedError, Equatable {
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "This Mac did not finish speaking in time."
        }
    }
}

/// Speaks on this Mac, choosing the voice by the contract's fallback rule.
public final class LocalSpeaker: Sendable {
    public static let shared = LocalSpeaker()

    public static let logger = Logger(subsystem: "com.vitruviansoftware.homespeaker", category: "local-speech")

    private let synthesizer: SpeechSynthesizing
    private let log: @Sendable (String) -> Void

    public init(
        synthesizer: SpeechSynthesizing = SystemSpeechSynthesizer(),
        log: @escaping @Sendable (String) -> Void = { LocalSpeaker.logger.notice("\($0, privacy: .public)") }
    ) {
        self.synthesizer = synthesizer
        self.log = log
    }

    /// Installed English voices for the picker: best quality first, then by name.
    public func englishVoices() -> [LocalVoice] {
        Self.ranked(synthesizer.installedVoices().filter(\.isEnglish))
    }

    /// Speaks `text` in `voiceID`, or the best installed US English voice
    /// when that one is not installed. Returns when the Mac has finished.
    public func speak(_ text: String, voiceID: String) async throws {
        let choice = Self.chooseVoice(requested: voiceID, from: synthesizer.installedVoices())
        log(choice.note)
        let synthesizer = self.synthesizer
        let limit = Self.timeLimit(for: text)
        // A backstop, not a timer on normal speech: an audio device that never
        // reports "finished" must not wedge the chat monitor or the CLI.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await synthesizer.speak(text, voiceID: choice.voice?.id) }
            group.addTask {
                try await Task.sleep(for: .seconds(limit))
                throw LocalSpeechError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    // MARK: Pure rules (tested)

    /// Rule 8: the requested voice if installed; otherwise the best installed
    /// en-US voice by quality (premium > enhanced > default); otherwise the
    /// best English voice; otherwise the system default. Never silence.
    public static func chooseVoice(requested: String, from voices: [LocalVoice]) -> (voice: LocalVoice?, note: String) {
        if let exact = voices.first(where: { $0.id == requested }) {
            return (exact, "Speaking on this Mac as \(exact.name) (\(exact.quality.label)).")
        }
        if let best = ranked(voices.filter(\.isUSEnglish)).first ?? ranked(voices.filter(\.isEnglish)).first {
            return (best, "Voice \(requested) is not installed; using \(best.name) (\(best.language), \(best.quality.label)).")
        }
        return (nil, "Voice \(requested) is not installed and no English voice is; using the system voice.")
    }

    static func ranked(_ voices: [LocalVoice]) -> [LocalVoice] {
        voices.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Roughly how long the Mac takes to say `text`: system voices read at
    /// about 2.5 to 3 words a second. Used to hold paused media.
    public static func estimatedSeconds(for text: String) -> Double {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        return max(1, Double(words) / 2.5)
    }

    /// The longest speech is allowed to take before it is given up on.
    public static func timeLimit(for text: String) -> Double {
        min(estimatedSeconds(for: text) * 3 + 15, 280)
    }
}

// MARK: - The real engine

/// `AVSpeechSynthesizer`, one per utterance, waited on through its delegate.
public struct SystemSpeechSynthesizer: SpeechSynthesizing {
    public init() {}

    public func installedVoices() -> [LocalVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { v in
            let quality: LocalVoice.Quality
            switch v.quality {
            case .premium: quality = .premium
            case .enhanced: quality = .enhanced
            default: quality = .standard
            }
            return LocalVoice(id: v.identifier, name: v.name, language: v.language, quality: quality)
        }
    }

    public func speak(_ text: String, voiceID: String?) async throws {
        let waiter = UtteranceWaiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                waiter.start(text: text, voiceID: voiceID, continuation: cont)
            }
        } onCancel: {
            waiter.cancel()
        }
        // The synthesizer holds its delegate weakly; keep it until done.
        withExtendedLifetime(waiter) {}
    }
}

/// Resumes its continuation exactly once: on finish, on cancel by the
/// synthesizer, or when the waiting task is cancelled.
private final class UtteranceWaiter: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Error>?
    private var done = false

    func start(text: String, voiceID: String?, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if done {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
        let utterance = AVSpeechUtterance(string: text)
        if let voiceID, let voice = AVSpeechSynthesisVoice(identifier: voiceID) { utterance.voice = voice }
        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    func cancel() {
        finish(CancellationError())
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        done = true
        lock.unlock()
        if let error { cont?.resume(throwing: error) } else { cont?.resume() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(nil)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(nil)
    }
}
