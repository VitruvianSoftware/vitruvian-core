// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// OpenAI Whisper speech-to-text engine (`POST https://api.openai.com/v1/audio/transcriptions`, `whisper-1`).
///
/// Sends audio as `multipart/form-data` with the API key strictly in the `Authorization: Bearer` header —
/// never in a URL, query parameter, log, or string description.
public final class WhisperClient: SpeechEngine, CustomStringConvertible, CustomDebugStringConvertible, @unchecked Sendable {
    public static let transcriptionsURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public static let modelID = "whisper-1"

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private struct LiveSession {
        let id: UUID
        let language: String
        let backend: any VoiceRecordingBackend
        let continuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation
        var startupTask: Task<Bool, Never>?
        var meterTask: Task<Void, Never>?
        var recordingURL: URL?
        var isStopping = false
        var isCancelled = false
    }

    private enum StartupDisposition {
        case listening
        case stopping
        case cancelled
    }

    public let provenance: SpeechProvenance = .openAIWhisper
    public let timeout: TimeInterval
    public let meterPollInterval: Duration

    private let apiKey: String
    private let transport: any HTTPTransport
    private let recorderFactory: @Sendable () -> any VoiceRecordingBackend
    private let preferredDeviceUID: @Sendable () -> String?
    private let lock = NSLock()
    private var liveSession: LiveSession?

    public init(
        apiKey: String,
        transport: any HTTPTransport = URLSessionHTTPTransport.shared,
        timeout: TimeInterval = 60,
        meterPollInterval: Duration = .milliseconds(80),
        preferredDeviceUID: @escaping @Sendable () -> String? = { nil },
        recorderFactory: @escaping @Sendable () -> any VoiceRecordingBackend = { AVAudioVoiceRecordingBackend() }
    ) {
        self.apiKey = apiKey
        self.transport = transport
        self.timeout = timeout
        self.meterPollInterval = meterPollInterval
        self.preferredDeviceUID = preferredDeviceUID
        self.recorderFactory = recorderFactory
    }

    public var description: String {
        "WhisperClient(model: \(Self.modelID), key: <redacted>)"
    }

    public var debugDescription: String {
        description
    }

    // MARK: - File Transcription

    public func transcribe(file: URL, language: String) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw SpeechError.whisperKeyMissing
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: file)
        } catch {
            throw SpeechError.audioUnreadable
        }

        let boundary = "CourierWhisper-\(UUID().uuidString)"
        let (filename, mimeType) = Self.uploadFileMetadata(for: file, data: audioData)
        let whisperLanguage = SpeechLanguage.whisperCode(for: language)
        let body = Self.makeMultipartBody(
            boundary: boundary,
            model: Self.modelID,
            language: whisperLanguage,
            filename: filename,
            mimeType: mimeType,
            fileData: audioData
        )

        var request = URLRequest(url: Self.transcriptionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let responseData: Data
        let httpResponse: HTTPURLResponse
        do {
            (responseData, httpResponse) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechError.unreachable
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: responseData) else {
                throw SpeechError.failed(String(localized: "OpenAI returned an unreadable transcription response."))
            }
            return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case 401, 403:
            throw SpeechError.badKey
        case 429:
            throw SpeechError.rateLimited
        default:
            throw SpeechError.failed(
                String(localized: "OpenAI transcription failed (HTTP \(httpResponse.statusCode)).")
            )
        }
    }

    // MARK: - Live Talk to Type (Record -> Upload on Stop)

    public func startLive(language: String) -> AsyncThrowingStream<SpeechUpdate, Error> {
        let sessionID = UUID()
        let backend = recorderFactory()
        let deviceUID = preferredDeviceUID()
        let pollInterval = meterPollInterval

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination {
                    Task { await self?.cancelSession(id: sessionID) }
                }
            }

            let session = LiveSession(
                id: sessionID,
                language: language,
                backend: backend,
                continuation: continuation
            )

            let previous = self.beginSession(session)

            let startupTask = Task { [weak self] () -> Bool in
                if let previous {
                    previous.startupTask?.cancel()
                    previous.meterTask?.cancel()
                    _ = await previous.startupTask?.value
                    await previous.backend.cancelRecording()
                    if let oldURL = previous.recordingURL {
                        try? FileManager.default.removeItem(at: oldURL)
                    }
                    previous.continuation.finish()
                }
                guard let self, !Task.isCancelled, !self.isSessionCancelled(id: sessionID) else {
                    return false
                }

                do {
                    let recordedURL = try await backend.startRecording(deviceUID: deviceUID)
                    switch self.recordStartedURL(recordedURL, for: sessionID) {
                    case .cancelled:
                        await backend.cancelRecording()
                        try? FileManager.default.removeItem(at: recordedURL)
                        return false
                    case .stopping:
                        return true
                    case .listening:
                        continuation.yield(SpeechUpdate(text: "", isFinal: false, level: backend.currentMeterLevel()))

                        let meterTask = Task { [weak self] in
                            while !Task.isCancelled {
                                do {
                                    try await Task.sleep(for: pollInterval)
                                } catch {
                                    break
                                }
                                guard let self, self.shouldEmitMeter(for: sessionID) else { break }
                                continuation.yield(
                                    SpeechUpdate(text: "", isFinal: false, level: backend.currentMeterLevel())
                                )
                            }
                        }

                        self.storeMeterTask(meterTask, for: sessionID)
                        return true
                    }
                } catch is CancellationError {
                    self.clearSession(id: sessionID)
                    continuation.finish()
                    return false
                } catch {
                    self.clearSession(id: sessionID)
                    continuation.finish(
                        throwing: SpeechError.failed(String(localized: "Couldn’t start microphone recording."))
                    )
                    return false
                }
            }

            if !self.attachStartupTask(startupTask, for: sessionID) {
                startupTask.cancel()
            }
        }
    }

    public func stop() async {
        guard let current = beginStopping() else { return }

        current.meterTask?.cancel()
        let started = await current.startupTask?.value ?? false
        guard started, !isSessionCancelled(id: current.id) else {
            return
        }

        current.continuation.yield(
            SpeechUpdate(
                text: "",
                isFinal: false,
                level: 0,
                statusMessage: String(localized: "Transcribing…")
            )
        )

        do {
            let recorded = try await current.backend.stopRecording()
            defer {
                try? FileManager.default.removeItem(at: recorded.url)
            }
            guard !isSessionCancelled(id: current.id) else {
                clearSession(id: current.id)
                current.continuation.finish()
                return
            }

            let transcript = try await transcribe(file: recorded.url, language: current.language)
            let cancelledDuringUpload = completeUploadAndCheckCancelled(id: current.id)
            guard !cancelledDuringUpload else {
                current.continuation.finish()
                return
            }

            current.continuation.yield(SpeechUpdate(text: transcript, isFinal: true, level: 0))
            current.continuation.finish()
        } catch is CancellationError {
            clearSession(id: current.id)
            current.continuation.finish()
        } catch let speechError as SpeechError {
            if let url = takeRecordingURLAndClear(id: current.id) {
                try? FileManager.default.removeItem(at: url)
            }
            current.continuation.finish(throwing: speechError)
        } catch {
            if let url = takeRecordingURLAndClear(id: current.id) {
                try? FileManager.default.removeItem(at: url)
            }
            current.continuation.finish(
                throwing: SpeechError.failed(String(localized: "Couldn’t finish microphone recording."))
            )
        }
    }

    public func cancel() async {
        if let sessionID = activeSessionID() {
            await cancelSession(id: sessionID)
        }
    }

    private func cancelSession(id: UUID) async {
        guard let removed = takeCancelledSession(id: id) else { return }
        removed.startupTask?.cancel()
        removed.meterTask?.cancel()
        _ = await removed.startupTask?.value
        await removed.backend.cancelRecording()
        if let url = removed.recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        removed.continuation.finish()
    }

    // MARK: - Synchronous Session State Locking

    private func beginSession(_ session: LiveSession) -> LiveSession? {
        lock.withLock {
            var old = liveSession
            old?.isCancelled = true
            liveSession = session
            return old
        }
    }

    private func attachStartupTask(_ task: Task<Bool, Never>, for id: UUID) -> Bool {
        lock.withLock {
            guard var current = liveSession, current.id == id, !current.isCancelled else {
                return false
            }
            current.startupTask = task
            liveSession = current
            return true
        }
    }

    private func isSessionCancelled(id: UUID) -> Bool {
        lock.withLock {
            guard let current = liveSession, current.id == id else { return true }
            return current.isCancelled
        }
    }

    private func recordStartedURL(_ url: URL, for id: UUID) -> StartupDisposition {
        lock.withLock {
            guard var current = liveSession, current.id == id, !current.isCancelled else {
                return .cancelled
            }
            current.recordingURL = url
            liveSession = current
            return current.isStopping ? .stopping : .listening
        }
    }

    private func shouldEmitMeter(for id: UUID) -> Bool {
        lock.withLock {
            guard let current = liveSession,
                  current.id == id,
                  !current.isStopping,
                  !current.isCancelled
            else {
                return false
            }
            return true
        }
    }

    private func storeMeterTask(_ task: Task<Void, Never>, for id: UUID) {
        let shouldCancel = lock.withLock { () -> Bool in
            guard var current = liveSession,
                  current.id == id,
                  !current.isStopping,
                  !current.isCancelled
            else {
                return true
            }
            current.meterTask = task
            liveSession = current
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    private func beginStopping() -> LiveSession? {
        lock.withLock {
            guard var session = liveSession, !session.isStopping, !session.isCancelled else {
                return nil
            }
            session.isStopping = true
            liveSession = session
            return session
        }
    }

    private func completeUploadAndCheckCancelled(id: UUID) -> Bool {
        lock.withLock {
            let cancelled = liveSession?.id != id || (liveSession?.isCancelled ?? true)
            if liveSession?.id == id {
                liveSession = nil
            }
            return cancelled
        }
    }

    private func takeRecordingURLAndClear(id: UUID) -> URL? {
        lock.withLock {
            guard let current = liveSession, current.id == id else { return nil }
            liveSession = nil
            return current.recordingURL
        }
    }

    private func activeSessionID() -> UUID? {
        lock.withLock { liveSession?.id }
    }

    private func takeCancelledSession(id: UUID) -> LiveSession? {
        lock.withLock {
            guard var current = liveSession, current.id == id else { return nil }
            current.isCancelled = true
            liveSession = nil
            return current
        }
    }

    private func clearSession(id: UUID) {
        lock.withLock {
            if liveSession?.id == id {
                liveSession = nil
            }
        }
    }

    // MARK: - Multipart Encoding

    private static func makeMultipartBody(
        boundary: String,
        model: String,
        language: String?,
        filename: String,
        mimeType: String,
        fileData: Data
    ) -> Data {
        var body = Data()
        func appendText(_ string: String) {
            body.append(Data(string.utf8))
        }
        func appendField(name: String, value: String) {
            appendText("--\(boundary)\r\n")
            appendText("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            appendText("\(value)\r\n")
        }

        appendField(name: "model", value: model)
        if let language, !language.isEmpty {
            appendField(name: "language", value: language)
        }

        let safeFilename = filename
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        appendText("--\(boundary)\r\n")
        appendText("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
        appendText("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        appendText("\r\n")
        appendText("--\(boundary)--\r\n")
        return body
    }

    private static func uploadFileMetadata(for url: URL, data: Data) -> (filename: String, mimeType: String) {
        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent.isEmpty
            ? "audio"
            : url.deletingPathExtension().lastPathComponent

        switch ext {
        case "m4a":
            return (url.lastPathComponent, "audio/mp4")
        case "mp4":
            return (url.lastPathComponent, "video/mp4")
        case "mp3", "mpeg", "mpga":
            return (url.lastPathComponent, "audio/mpeg")
        case "ogg", "opus":
            return (url.lastPathComponent, "audio/ogg")
        case "oga":
            return ("\(baseName).ogg", "audio/ogg")
        case "wav":
            return (url.lastPathComponent, "audio/wav")
        case "webm":
            return (url.lastPathComponent, "audio/webm")
        case "flac":
            return (url.lastPathComponent, "audio/flac")
        default:
            if data.starts(with: Data("OggS".utf8)) {
                return ("\(baseName).ogg", "audio/ogg")
            }
            if data.count >= 8, Data(data[4 ..< 8]) == Data("ftyp".utf8) {
                return ("\(baseName).m4a", "audio/mp4")
            }
            if data.starts(with: Data("RIFF".utf8)) {
                return ("\(baseName).wav", "audio/wav")
            }
            if data.starts(with: Data("fLaC".utf8)) {
                return ("\(baseName).flac", "audio/flac")
            }
            if data.starts(with: Data("ID3".utf8)) {
                return ("\(baseName).mp3", "audio/mpeg")
            }
            let fallbackName = url.lastPathComponent.isEmpty ? "audio.m4a" : url.lastPathComponent
            return (fallbackName, "audio/mp4")
        }
    }
}
