// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import Foundation
#if canImport(Speech)
import Speech
#endif

/// Where speech was turned into text, for the Talk to Type strip and voice-note provenance footer.
public enum SpeechProvenance: String, Equatable, Sendable {
    case onThisMac
    case openAIWhisper

    /// Right-hand badge in the Talk to Type listening strip.
    public var liveStripLabel: String {
        switch self {
        case .onThisMac:
            String(localized: "On this Mac")
        case .openAIWhisper:
            String(localized: "Sent to OpenAI")
        }
    }

    /// Provenance line under a transcribed voice note.
    public var transcriptFooter: String {
        switch self {
        case .onThisMac:
            String(localized: "Transcribed on this Mac")
        case .openAIWhisper:
            String(localized: "Transcribed by OpenAI")
        }
    }
}

/// Incremental update streamed during a live Talk to Type session.
public struct SpeechUpdate: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public let level: Float?
    public let statusMessage: String?

    public init(
        text: String,
        isFinal: Bool = false,
        level: Float? = nil,
        statusMessage: String? = nil
    ) {
        self.text = text
        self.isFinal = isFinal
        self.level = level
        self.statusMessage = statusMessage
    }
}

/// Plain-English speech errors shown in Courier without exposing SDK names, URLs, or API keys.
public enum SpeechError: Error, Equatable, Sendable, LocalizedError {
    case languageUnavailable(language: String)
    case microphoneAccessDenied
    case speechRecognitionAccessDenied
    case whisperKeyMissing
    case missingLocalFile
    case badKey
    case rateLimited
    case unreachable
    case audioUnreadable
    case failed(String)

    public var message: String {
        switch self {
        case let .languageUnavailable(language):
            String(localized: "Speech recognition for \(language) isn’t available on this Mac.")
        case .microphoneAccessDenied:
            String(localized: "Courier needs microphone access for Talk to Type.")
        case .speechRecognitionAccessDenied:
            String(localized: "Courier needs speech recognition access for Talk to Type.")
        case .whisperKeyMissing:
            String(localized: "Add an OpenAI key in the Cloud section to use Whisper.")
        case .missingLocalFile:
            String(localized: "Download the voice note first.")
        case .badKey:
            String(localized: "OpenAI rejected the API key. Check it in Settings ▸ AI.")
        case .rateLimited:
            String(localized: "OpenAI rate limit reached. Try again in a moment.")
        case .unreachable:
            String(localized: "Couldn’t reach OpenAI. Check your internet connection.")
        case .audioUnreadable:
            String(localized: "Couldn’t read the audio recording.")
        case let .failed(detail):
            detail
        }
    }

    public var errorDescription: String? { message }
}

/// Speech-to-text engine seam (`AppleSpeechEngine` on this Mac or `WhisperClient` via OpenAI).
/// Separate from `AIProvider` so speech works even when the chat AI provider is Off.
public protocol SpeechEngine: Sendable {
    var provenance: SpeechProvenance { get }
    func transcribe(file: URL, language: String) async throws -> String
    func startLive(language: String) -> AsyncThrowingStream<SpeechUpdate, Error>
    func stop() async
    func cancel() async
}

/// Injectable permission seam for Talk to Type so unit tests never trigger macOS TCC prompts.
public protocol SpeechPermissionChecking: Sendable {
    func microphoneStatus() -> MicrophoneAuthStatus
    func requestMicrophoneAccess() async -> Bool
    func requiresSpeechRecognitionPermission(for provenance: SpeechProvenance) -> Bool
    func speechRecognitionStatus() -> MicrophoneAuthStatus
    func requestSpeechRecognitionAccess() async -> Bool
}

/// Production permission checker backed by `AVCaptureDevice` (always) and `SFSpeechRecognizer` (macOS 14–25 Apple engine).
public struct SystemSpeechPermissionChecker: SpeechPermissionChecking {
    public init() {}

    public func microphoneStatus() -> MicrophoneAuthStatus {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return .denied
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    public func requestMicrophoneAccess() async -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return false
        }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func requiresSpeechRecognitionPermission(for provenance: SpeechProvenance) -> Bool {
        guard provenance == .onThisMac else { return false }
        if #available(macOS 26, *) {
            // SpeechAnalyzer + SpeechTranscriber run locally via AssetInventory without SFSpeechRecognizer TCC.
            return false
        }
        return true
    }

    public func speechRecognitionStatus() -> MicrophoneAuthStatus {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            return .denied
        }
        #if canImport(Speech)
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
        #else
        return .denied
        #endif
    }

    public func requestSpeechRecognitionAccess() async -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil else {
            return false
        }
        #if canImport(Speech)
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        #else
        return false
        #endif
    }
}
