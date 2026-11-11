// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Calm notice shown above the composer when microphone or speech-recognition permission is denied,
/// offering an `Open System Settings` action without altering the draft.
public struct TalkToTypePermissionNotice: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case microphone
        case speechRecognition
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var systemSettingsURL: URL? {
        switch kind {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechRecognition:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        }
    }
}

/// Talk to Type state machine owned by `ComposerModel`:
///
/// ```
/// idle ──⌘⇧D──▶ askingPermission ──granted──▶ listening ──⌘⇧D / Stop──▶ finishing ──▶ idle (text inserted)
///                     │ denied                    │ Esc                     │ error
///                     ▼                           ▼                         ▼
///              notice + Open Settings       idle (nothing inserted)   notice, draft unchanged
/// ```
@MainActor
public final class TalkToTypeModel: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle
        case askingPermission
        case listening(
            partialText: String,
            level: Float,
            provenance: SpeechProvenance,
            statusMessage: String?
        )
        case finishing(
            partialText: String,
            provenance: SpeechProvenance,
            statusMessage: String?
        )
    }

    nonisolated public static let defaultMaxDuration: Duration = .seconds(300)

    @Published public private(set) var state: State = .idle
    @Published public private(set) var permissionNotice: TalkToTypePermissionNotice?

    public var engineFactory: SpeechEngineFactory
    public var permissions: any SpeechPermissionChecking
    public var maxDuration: Duration
    public var sleep: @Sendable (Duration) async throws -> Void
    public var onInsertText: (@MainActor (String) -> Void)?
    public var onErrorNotice: (@MainActor (String) -> Void)?

    private var sessionToken: UInt64 = 0
    private var activeEngine: (any SpeechEngine)?
    private var sessionTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var cancelTask: Task<Void, Never>?
    private var capTask: Task<Void, Never>?

    public init(
        engineFactory: SpeechEngineFactory? = nil,
        permissions: any SpeechPermissionChecking = SystemSpeechPermissionChecker(),
        maxDuration: Duration = TalkToTypeModel.defaultMaxDuration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.engineFactory = engineFactory ?? SpeechEngineFactory(preferences: AIPreferences())
        self.permissions = permissions
        self.maxDuration = maxDuration
        self.sleep = sleep
    }

    public var isActive: Bool {
        state != .idle
    }

    /// Toggles Talk to Type on `⌘⇧D`: starts from `.idle`, stops and finishes when `.listening`.
    public func toggle() {
        switch state {
        case .idle:
            start()
        case .listening:
            stop()
        case .askingPermission, .finishing:
            break
        }
    }

    /// Starts a Talk to Type session from `.idle`.
    public func start() {
        guard state == .idle else { return }
        permissionNotice = nil

        let engine: any SpeechEngine
        switch engineFactory.resolveEngine() {
        case let .available(resolved):
            engine = resolved
        case let .notAllowed(reason):
            onErrorNotice?(reason)
            return
        }

        sessionToken &+= 1
        let token = sessionToken
        let language = engineFactory.preferences.transcriptionLanguage
        activeEngine = engine
        state = .askingPermission

        sessionTask = Task { @MainActor [weak self] in
            guard let self, self.sessionToken == token else { return }

            // 1. Microphone permission (always required).
            let micAuthorized: Bool
            switch self.permissions.microphoneStatus() {
            case .authorized:
                micAuthorized = true
            case .notDetermined:
                micAuthorized = await self.permissions.requestMicrophoneAccess()
            case .denied, .restricted:
                micAuthorized = false
            }
            guard !Task.isCancelled, self.sessionToken == token else { return }
            guard micAuthorized else {
                self.tearDownSessionState()
                self.permissionNotice = TalkToTypePermissionNotice(
                    kind: .microphone,
                    message: SpeechError.microphoneAccessDenied.message
                )
                return
            }

            // 2. Speech recognition permission (Apple legacy recognizer where macOS asks for it).
            if self.permissions.requiresSpeechRecognitionPermission(for: engine.provenance) {
                let speechAuthorized: Bool
                switch self.permissions.speechRecognitionStatus() {
                case .authorized:
                    speechAuthorized = true
                case .notDetermined:
                    speechAuthorized = await self.permissions.requestSpeechRecognitionAccess()
                case .denied, .restricted:
                    speechAuthorized = false
                }
                guard !Task.isCancelled, self.sessionToken == token else { return }
                guard speechAuthorized else {
                    self.tearDownSessionState()
                    self.permissionNotice = TalkToTypePermissionNotice(
                        kind: .speechRecognition,
                        message: SpeechError.speechRecognitionAccessDenied.message
                    )
                    return
                }
            }

            // 3. Enter listening state and arm the 5-minute recording cap.
            let provenance = engine.provenance
            self.state = .listening(
                partialText: "",
                level: 0,
                provenance: provenance,
                statusMessage: nil
            )

            let capDuration = self.maxDuration
            let sleepFn = self.sleep
            self.capTask = Task { @MainActor [weak self] in
                do {
                    try await sleepFn(capDuration)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled, self.sessionToken == token else { return }
                if case .listening = self.state {
                    self.stop()
                }
            }

            // 4. Consume live stream updates until finished, stopped, cancelled, or failed.
            var latestText = ""
            var currentLevel: Float = 0
            do {
                let stream = engine.startLive(language: language)
                for try await update in stream {
                    guard !Task.isCancelled, self.sessionToken == token else { return }
                    if !update.text.isEmpty || update.isFinal {
                        latestText = update.text
                    }
                    if let level = update.level {
                        currentLevel = min(max(level, 0), 1)
                    }
                    switch self.state {
                    case .listening:
                        self.state = .listening(
                            partialText: latestText,
                            level: currentLevel,
                            provenance: provenance,
                            statusMessage: update.statusMessage
                        )
                    case let .finishing(_, _, existingStatus):
                        self.state = .finishing(
                            partialText: latestText,
                            provenance: provenance,
                            statusMessage: update.statusMessage ?? existingStatus
                        )
                    case .idle, .askingPermission:
                        break
                    }
                }

                guard !Task.isCancelled, self.sessionToken == token else { return }
                self.tearDownSessionState()
                let trimmed = latestText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self.onInsertText?(trimmed)
                }
            } catch is CancellationError {
                guard self.sessionToken == token else { return }
                self.tearDownSessionState()
            } catch {
                guard self.sessionToken == token else { return }
                self.tearDownSessionState()
                let reason = (error as? SpeechError)?.message
                    ?? String(localized: "Speech recognition failed. Try again.")
                self.onErrorNotice?(reason)
            }
        }
    }

    /// Stops listening (`⌘⇧D` / Stop button, or the 5-minute cap) and finalizes/uploads the spoken audio.
    public func stop() {
        guard case let .listening(partialText, _, provenance, _) = state,
              let engine = activeEngine
        else {
            return
        }
        let token = sessionToken
        capTask?.cancel()
        capTask = nil
        state = .finishing(
            partialText: partialText,
            provenance: provenance,
            statusMessage: provenance == .openAIWhisper ? String(localized: "Transcribing…") : nil
        )
        stopTask = Task { @MainActor [weak self] in
            await engine.stop()
            guard let self, self.sessionToken == token else { return }
            self.stopTask = nil
        }
    }

    /// Cancels immediately (`Esc`, switching chats, or app lock) and inserts nothing.
    /// Returns `true` when Talk to Type was active and consumed the cancellation.
    @discardableResult
    public func cancel() -> Bool {
        guard state != .idle else { return false }
        sessionToken &+= 1
        capTask?.cancel()
        capTask = nil
        stopTask?.cancel()
        stopTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        let engine = activeEngine
        activeEngine = nil
        state = .idle
        if let engine {
            cancelTask = Task { @MainActor [weak self] in
                await engine.cancel()
                self?.cancelTask = nil
            }
        }
        return true
    }

    public func dismissPermissionNotice() {
        permissionNotice = nil
    }

    /// Deterministic test helper: awaits any in-flight session/stop/cancel tasks.
    public func waitForIdle() async {
        await cancelTask?.value
        await stopTask?.value
        await sessionTask?.value
    }

    /// Preview/snapshot helper for deterministic view rendering tests.
    public func setStateForTesting(
        _ newState: State,
        permissionNotice: TalkToTypePermissionNotice? = nil
    ) {
        self.state = newState
        self.permissionNotice = permissionNotice
    }

    private func tearDownSessionState() {
        capTask?.cancel()
        capTask = nil
        stopTask = nil
        sessionTask = nil
        activeEngine = nil
        state = .idle
    }
}
