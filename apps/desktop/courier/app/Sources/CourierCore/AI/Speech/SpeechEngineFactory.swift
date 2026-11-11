// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Outcome of resolving the active speech engine from `AIPreferences` and `AIKeyStore`.
public enum SpeechEngineResolution: Sendable {
    case available(any SpeechEngine)
    case notAllowed(reason: String)
}

/// Chooses the speech engine from `AIPreferences` + `AIKeyStore`, independent of the chat AI provider.
///
/// - `useWhisperForTalkToType == false` -> Apple on-device engine (`AppleSpeechEngine`), even when chat AI is Off.
/// - `useWhisperForTalkToType == true` without a saved OpenAI key -> `.notAllowed`.
/// - `useWhisperForTalkToType == true` with a saved OpenAI key -> `WhisperClient`.
@MainActor
public final class SpeechEngineFactory {
    public static let whisperStatusLine = String(localized: "OpenAI Whisper · audio is sent to OpenAI")
    public static let whisperMissingKeyMessage = SpeechError.whisperKeyMissing.message

    public let preferences: AIPreferences
    public let keyStore: AIKeyStore
    public let transport: any HTTPTransport
    public var preferredDeviceUID: @Sendable () -> String?
    public var recorderFactory: @Sendable () -> any VoiceRecordingBackend
    public var appleEngineFactory: (@Sendable () -> any SpeechEngine)?
    public var appleAvailability: AppleSpeechEngine.AvailabilityCheck

    public init(
        preferences: AIPreferences,
        keyStore: AIKeyStore = AIKeyStore(),
        transport: any HTTPTransport = URLSessionHTTPTransport.shared,
        preferredDeviceUID: @escaping @Sendable () -> String? = { nil },
        preferredMicrophoneUIDFallback: (@Sendable () -> String?)? = nil,
        recorderFactory: @escaping @Sendable () -> any VoiceRecordingBackend = { AVAudioVoiceRecordingBackend() },
        appleEngineFactory: (@Sendable () -> any SpeechEngine)? = nil,
        appleAvailability: @escaping AppleSpeechEngine.AvailabilityCheck = AppleSpeechEngine.systemAvailability
    ) {
        self.preferences = preferences
        self.keyStore = keyStore
        self.transport = transport
        self.preferredDeviceUID = preferredMicrophoneUIDFallback ?? preferredDeviceUID
        self.recorderFactory = recorderFactory
        self.appleEngineFactory = appleEngineFactory
        self.appleAvailability = appleAvailability
    }

    /// True when an OpenAI API key is saved in `AIKeyStore`, enabling the Whisper toggle in Settings ▸ AI.
    public var canEnableWhisper: Bool {
        keyStore.hasKey(for: .openAI)
    }

    /// Resolves the speech engine for Talk to Type or voice-note transcription.
    /// Chat AI (`preferences.enableContextualAI`) being Off never blocks Apple speech or Whisper.
    public func resolveEngine() -> SpeechEngineResolution {
        if preferences.useWhisperForTalkToType {
            guard let key = keyStore.key(for: .openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty
            else {
                return .notAllowed(reason: Self.whisperMissingKeyMessage)
            }
            let client = WhisperClient(
                apiKey: key,
                transport: transport,
                preferredDeviceUID: preferredDeviceUID,
                recorderFactory: recorderFactory
            )
            return .available(client)
        }

        if let appleEngineFactory {
            return .available(appleEngineFactory())
        }
        return .available(AppleSpeechEngine(preferredDeviceUID: preferredDeviceUID))
    }

    /// Computes the live status line shown in Settings ▸ AI ▸ Talk to Type & Voice Transcription.
    public func settingsStatusLine() async -> String {
        if preferences.useWhisperForTalkToType, canEnableWhisper {
            return Self.whisperStatusLine
        }
        let availability = await appleAvailability(preferences.transcriptionLanguage)
        return availability.settingsStatusLine
    }
}
