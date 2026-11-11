// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation
#if canImport(Speech)
import Speech
#endif

/// On-device Apple speech model availability for Settings ▸ AI.
public enum AppleSpeechAvailability: Equatable, Sendable {
    case ready
    case modelWillDownload
    case notAvailable(language: String)

    public var settingsStatusLine: String {
        switch self {
        case .ready:
            String(localized: "On this Mac · Ready")
        case .modelWillDownload:
            String(localized: "On this Mac · Speech model will download on first use")
        case let .notAvailable(language):
            String(localized: "On this Mac · Not available for \(language)")
        }
    }
}

/// On-device Apple speech engine.
///
/// - macOS 26+: uses `SpeechAnalyzer` + `SpeechTranscriber` and installs missing language assets via `AssetInventory`
///   (yielding `"Downloading speech model…"` while downloading).
/// - macOS 14–25: uses `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`.
/// - Never falls back to Apple's servers: if on-device recognition is unavailable for the requested language, throws
///   `SpeechError.languageUnavailable(language:)`.
public final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    public typealias AvailabilityCheck = @Sendable (_ language: String) async -> AppleSpeechAvailability

    typealias LiveHandlerRegistrar = @Sendable (
        _ stopHandler: @escaping @Sendable () async -> Void,
        _ cancelHandler: @escaping @Sendable () async -> Void
    ) -> Bool

    typealias CustomLiveRunner = @Sendable (
        _ sessionID: UUID,
        _ locale: Locale,
        _ displayLanguage: String,
        _ deviceUID: String?,
        _ registerHandlers: LiveHandlerRegistrar,
        _ continuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation
    ) async -> Void

    #if canImport(Speech)
    typealias LegacyRecognizerProvider = @Sendable (Locale) -> (any LegacySpeechRecognizing)?
    #else
    typealias LegacyRecognizerProvider = @Sendable (Locale) -> AnyObject?
    #endif

    private struct ActiveLiveController {
        let id: UUID
        let continuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation
        var startupTask: Task<Void, Never>?
        var stopHandler: (@Sendable () async -> Void)?
        var cancelHandler: (@Sendable () async -> Void)?
        var stopWaiters: [CheckedContinuation<(@Sendable () async -> Void)?, Never>] = []
        var isCancelled = false
    }

    public let provenance: SpeechProvenance = .onThisMac
    private let preferredDeviceUID: @Sendable () -> String?
    private let currentLocale: @Sendable () -> Locale
    private let forceLegacyBackend: Bool
    private let legacyRecognizerProvider: LegacyRecognizerProvider?
    private let customLiveRunner: CustomLiveRunner?
    private let lock = NSLock()
    private var activeLive: ActiveLiveController?

    public convenience init(
        preferredDeviceUID: @escaping @Sendable () -> String? = { nil },
        currentLocale: @escaping @Sendable () -> Locale = { .current }
    ) {
        self.init(
            preferredDeviceUID: preferredDeviceUID,
            currentLocale: currentLocale,
            forceLegacyBackend: false,
            legacyRecognizerProvider: nil,
            customLiveRunner: nil
        )
    }

    init(
        preferredDeviceUID: @escaping @Sendable () -> String? = { nil },
        currentLocale: @escaping @Sendable () -> Locale = { .current },
        forceLegacyBackend: Bool = false,
        legacyRecognizerProvider: LegacyRecognizerProvider? = nil,
        customLiveRunner: CustomLiveRunner? = nil
    ) {
        self.preferredDeviceUID = preferredDeviceUID
        self.currentLocale = currentLocale
        self.forceLegacyBackend = forceLegacyBackend
        self.legacyRecognizerProvider = legacyRecognizerProvider
        self.customLiveRunner = customLiveRunner
    }

    // MARK: - Availability

    @Sendable
    public static func systemAvailability(for language: String) async -> AppleSpeechAvailability {
        await systemAvailability(for: language, currentLocale: .current)
    }

    public static func systemAvailability(for language: String, currentLocale: Locale) async -> AppleSpeechAvailability {
        let locale = SpeechLanguage.appleLocale(for: language, currentLocale: currentLocale)
        let displayLanguage = SpeechLanguage.displayName(for: language, currentLocale: currentLocale)

        #if canImport(Speech)
        if #available(macOS 26, *) {
            guard SpeechTranscriber.isAvailable,
                  let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            else {
                return .notAvailable(language: displayLanguage)
            }
            let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
            let status = await AssetInventory.status(forModules: [transcriber])
            switch status {
            case .installed:
                return .ready
            case .supported, .downloading:
                return .modelWillDownload
            case .unsupported:
                return .notAvailable(language: displayLanguage)
            @unknown default:
                return .notAvailable(language: displayLanguage)
            }
        } else {
            guard let recognizer = resolveLegacyRecognizer(for: locale),
                  recognizer.supportsOnDeviceRecognition
            else {
                return .notAvailable(language: displayLanguage)
            }
            return .ready
        }
        #else
        return .notAvailable(language: displayLanguage)
        #endif
    }

    // MARK: - File Transcription

    public func transcribe(file: URL, language: String) async throws -> String {
        let localeSnapshot = currentLocale()
        let locale = SpeechLanguage.appleLocale(for: language, currentLocale: localeSnapshot)
        let displayLanguage = SpeechLanguage.displayName(for: language, currentLocale: localeSnapshot)

        #if canImport(Speech)
        if !forceLegacyBackend, #available(macOS 26, *) {
            return try await transcribeFileModern(file: file, locale: locale, displayLanguage: displayLanguage)
        } else {
            return try await transcribeFileLegacy(file: file, locale: locale, displayLanguage: displayLanguage)
        }
        #else
        throw SpeechError.languageUnavailable(language: displayLanguage)
        #endif
    }

    // MARK: - Live Transcription

    public func startLive(language: String) -> AsyncThrowingStream<SpeechUpdate, Error> {
        let sessionID = UUID()
        let localeSnapshot = currentLocale()
        let locale = SpeechLanguage.appleLocale(for: language, currentLocale: localeSnapshot)
        let displayLanguage = SpeechLanguage.displayName(for: language, currentLocale: localeSnapshot)
        let deviceUID = preferredDeviceUID()

        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination {
                    Task { await self?.cancelLive(id: sessionID) }
                }
            }

            let previous = self.beginLiveSession(id: sessionID, continuation: continuation)

            let startupTask = Task { [weak self] in
                if let previous {
                    previous.startupTask?.cancel()
                    if let prevCancel = previous.cancelHandler {
                        await prevCancel()
                    } else {
                        previous.continuation.finish()
                        await previous.startupTask?.value
                    }
                }

                guard let self,
                      !Task.isCancelled,
                      self.isLiveSessionActive(id: sessionID)
                else {
                    continuation.finish()
                    return
                }

                let registerHandlers: LiveHandlerRegistrar = { [weak self] stopHandler, cancelHandler in
                    self?.registerLiveHandlers(id: sessionID, stop: stopHandler, cancel: cancelHandler) ?? false
                }

                if let customLiveRunner = self.customLiveRunner {
                    await customLiveRunner(
                        sessionID,
                        locale,
                        displayLanguage,
                        deviceUID,
                        registerHandlers,
                        continuation
                    )
                    return
                }

                #if canImport(Speech)
                if !self.forceLegacyBackend, #available(macOS 26, *) {
                    await self.runLiveModern(
                        sessionID: sessionID,
                        locale: locale,
                        displayLanguage: displayLanguage,
                        deviceUID: deviceUID,
                        registerHandlers: registerHandlers,
                        continuation: continuation
                    )
                } else {
                    await self.runLiveLegacy(
                        sessionID: sessionID,
                        locale: locale,
                        displayLanguage: displayLanguage,
                        deviceUID: deviceUID,
                        registerHandlers: registerHandlers,
                        continuation: continuation
                    )
                }
                #else
                self.clearLive(id: sessionID)
                continuation.finish(throwing: SpeechError.languageUnavailable(language: displayLanguage))
                #endif
            }

            if !self.attachStartupTask(startupTask, for: sessionID) {
                startupTask.cancel()
            }
        }
    }

    public func stop() async {
        let stopHandler = await waitForStopHandler()
        await stopHandler?()
    }

    public func cancel() async {
        await performCancel(matching: nil)
    }

    private func cancelLive(id: UUID) async {
        await performCancel(matching: id)
    }

    private func performCancel(matching id: UUID?) async {
        guard let cancelled = takeActiveLiveForCancel(matching: id) else { return }
        cancelled.startupTask?.cancel()
        if let cancelHandler = cancelled.cancelHandler {
            await cancelHandler()
        } else {
            cancelled.continuation.finish()
            await cancelled.startupTask?.value
        }
    }

    // MARK: - Synchronous Session State Locking

    private func beginLiveSession(
        id: UUID,
        continuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation
    ) -> ActiveLiveController? {
        let (previous, waiters) = lock.withLock {
            () -> (ActiveLiveController?, [CheckedContinuation<(@Sendable () async -> Void)?, Never>]) in
            var old = activeLive
            let oldWaiters = old?.stopWaiters ?? []
            old?.stopWaiters = []
            old?.isCancelled = true
            activeLive = ActiveLiveController(id: id, continuation: continuation)
            return (old, oldWaiters)
        }
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
        return previous
    }

    private func attachStartupTask(_ task: Task<Void, Never>, for id: UUID) -> Bool {
        lock.withLock {
            guard var current = activeLive, current.id == id, !current.isCancelled else {
                return false
            }
            current.startupTask = task
            activeLive = current
            return true
        }
    }

    private func isLiveSessionActive(id: UUID) -> Bool {
        lock.withLock {
            guard let current = activeLive else { return false }
            return current.id == id && !current.isCancelled
        }
    }

    private func registerLiveHandlers(
        id: UUID,
        stop: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () async -> Void
    ) -> Bool {
        let waiters = lock.withLock { () -> [CheckedContinuation<(@Sendable () async -> Void)?, Never>]? in
            guard var current = activeLive, current.id == id, !current.isCancelled else {
                return nil
            }
            current.stopHandler = stop
            current.cancelHandler = cancel
            let pending = current.stopWaiters
            current.stopWaiters = []
            activeLive = current
            return pending
        }
        guard let waiters else { return false }
        for waiter in waiters {
            waiter.resume(returning: stop)
        }
        return true
    }

    private enum StopPreparation {
        case none
        case ready(@Sendable () async -> Void)
        case waitStartup
    }

    private func waitForStopHandler() async -> (@Sendable () async -> Void)? {
        switch currentStopPreparation() {
        case .none:
            return nil
        case let .ready(handler):
            return handler
        case .waitStartup:
            return await withCheckedContinuation { continuation in
                enqueueStopWaiter(continuation)
            }
        }
    }

    private func currentStopPreparation() -> StopPreparation {
        lock.withLock {
            guard let current = activeLive, !current.isCancelled else { return .none }
            if let handler = current.stopHandler {
                return .ready(handler)
            }
            return .waitStartup
        }
    }

    private func enqueueStopWaiter(_ continuation: CheckedContinuation<(@Sendable () async -> Void)?, Never>) {
        let immediateResult = lock.withLock { () -> (@Sendable () async -> Void)?? in
            guard var current = activeLive, !current.isCancelled else {
                return .some(nil)
            }
            if let handler = current.stopHandler {
                return .some(handler)
            }
            current.stopWaiters.append(continuation)
            activeLive = current
            return nil
        }
        if let immediateResult {
            continuation.resume(returning: immediateResult)
        }
    }

    private func takeActiveLiveForCancel(matching id: UUID?) -> ActiveLiveController? {
        let (removed, waiters) = lock.withLock {
            () -> (ActiveLiveController?, [CheckedContinuation<(@Sendable () async -> Void)?, Never>]) in
            guard var current = activeLive else { return (nil, []) }
            if let id, current.id != id { return (nil, []) }
            current.isCancelled = true
            let pending = current.stopWaiters
            current.stopWaiters = []
            activeLive = nil
            return (current, pending)
        }
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
        return removed
    }

    private func clearLive(id: UUID) {
        let waiters = lock.withLock { () -> [CheckedContinuation<(@Sendable () async -> Void)?, Never>] in
            guard let current = activeLive, current.id == id else { return [] }
            activeLive = nil
            return current.stopWaiters
        }
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
    }

    // MARK: - macOS 26+ SpeechAnalyzer + SpeechTranscriber

    #if canImport(Speech)
    @available(macOS 26, *)
    private func transcribeFileModern(
        file: URL,
        locale: Locale,
        displayLanguage: String
    ) async throws -> String {
        guard SpeechTranscriber.isAvailable,
              let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        else {
            throw SpeechError.languageUnavailable(language: displayLanguage)
        }

        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .transcription)
        let status = await AssetInventory.status(forModules: [transcriber])
        switch status {
        case .unsupported:
            throw SpeechError.languageUnavailable(language: displayLanguage)
        case .supported, .downloading:
            _ = try? await AssetInventory.reserve(locale: supportedLocale)
            if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installRequest.downloadAndInstall()
            }
        case .installed:
            break
        @unknown default:
            throw SpeechError.languageUnavailable(language: displayLanguage)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: file)
        } catch {
            throw SpeechError.audioUnreadable
        }

        let collector = ModernTranscriptCollector()
        let resultsTask = Task {
            for try await result in transcriber.results {
                let piece = String(result.text.characters)
                await collector.ingest(text: piece, isFinal: result.isFinal)
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            _ = try await resultsTask.value
            return await collector.combinedText()
        } catch is CancellationError {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw CancellationError()
        } catch let speechError as SpeechError {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw speechError
        } catch {
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw SpeechError.failed(String(localized: "Speech recognition failed on this Mac."))
        }
    }

    @available(macOS 26, *)
    private func runLiveModern(
        sessionID: UUID,
        locale: Locale,
        displayLanguage: String,
        deviceUID: String?,
        registerHandlers: LiveHandlerRegistrar,
        continuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation
    ) async {
        guard SpeechTranscriber.isAvailable,
              let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        else {
            clearLive(id: sessionID)
            continuation.finish(throwing: SpeechError.languageUnavailable(language: displayLanguage))
            return
        }
        guard !Task.isCancelled, isLiveSessionActive(id: sessionID) else {
            continuation.finish()
            return
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        guard !Task.isCancelled, isLiveSessionActive(id: sessionID) else {
            continuation.finish()
            return
        }
        switch status {
        case .unsupported:
            clearLive(id: sessionID)
            continuation.finish(throwing: SpeechError.languageUnavailable(language: displayLanguage))
            return
        case .supported, .downloading:
            continuation.yield(
                SpeechUpdate(
                    text: "",
                    isFinal: false,
                    level: 0,
                    statusMessage: String(localized: "Downloading speech model…")
                )
            )
            do {
                _ = try? await AssetInventory.reserve(locale: supportedLocale)
                if let installRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await installRequest.downloadAndInstall()
                }
            } catch is CancellationError {
                clearLive(id: sessionID)
                continuation.finish()
                return
            } catch {
                clearLive(id: sessionID)
                continuation.finish(
                    throwing: SpeechError.failed(String(localized: "Couldn’t download the speech model on this Mac."))
                )
                return
            }
        case .installed:
            break
        @unknown default:
            clearLive(id: sessionID)
            continuation.finish(throwing: SpeechError.languageUnavailable(language: displayLanguage))
            return
        }
        guard !Task.isCancelled, isLiveSessionActive(id: sessionID) else {
            continuation.finish()
            return
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioEngine = AVAudioEngine()
        Self.configurePreferredInputDevice(uid: deviceUID, on: audioEngine)
        let inputNode = audioEngine.inputNode
        let naturalFormat = inputNode.outputFormat(forBus: 0)
        guard naturalFormat.channelCount > 0, naturalFormat.sampleRate > 0 else {
            clearLive(id: sessionID)
            continuation.finish(
                throwing: SpeechError.failed(String(localized: "Couldn’t access an audio input format on this Mac."))
            )
            return
        }

        let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: naturalFormat
        ) ?? naturalFormat
        let converter: AVAudioConverter? = (targetFormat == naturalFormat)
            ? nil
            : AVAudioConverter(from: naturalFormat, to: targetFormat)

        var inputContinuationBox: AsyncStream<AnalyzerInput>.Continuation?
        let inputStream = AsyncStream<AnalyzerInput> { streamCont in
            inputContinuationBox = streamCont
        }
        guard let inputContinuation = inputContinuationBox else {
            clearLive(id: sessionID)
            continuation.finish()
            return
        }

        let collector = ModernTranscriptCollector()
        let meterBox = MeterLevelBox()

        let resultsTask = Task {
            for try await result in transcriber.results {
                let piece = String(result.text.characters)
                let combined = await collector.ingest(text: piece, isFinal: result.isFinal)
                continuation.yield(
                    SpeechUpdate(
                        text: combined,
                        isFinal: false,
                        level: meterBox.current(),
                        statusMessage: nil
                    )
                )
            }
        }

        let stateGuard = LiveExecutionGuard()

        let stopClosure: @Sendable () async -> Void = { [weak self] in
            guard stateGuard.beginStop() else { return }
            Self.tearDownAudioEngine(audioEngine)
            inputContinuation.finish()
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                _ = try await resultsTask.value
                if !stateGuard.isCancelled {
                    let finalTranscript = await collector.combinedText()
                    continuation.yield(SpeechUpdate(text: finalTranscript, isFinal: true, level: 0))
                    continuation.finish()
                }
            } catch is CancellationError {
                continuation.finish()
            } catch {
                if !stateGuard.isCancelled {
                    continuation.finish(
                        throwing: SpeechError.failed(String(localized: "Speech recognition failed on this Mac."))
                    )
                }
            }
            self?.clearLive(id: sessionID)
        }

        let cancelClosure: @Sendable () async -> Void = { [weak self] in
            guard stateGuard.beginCancel() else { return }
            Self.tearDownAudioEngine(audioEngine)
            inputContinuation.finish()
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            continuation.finish()
            self?.clearLive(id: sessionID)
        }

        guard registerHandlers(stopClosure, cancelClosure) else {
            await cancelClosure()
            return
        }

        do {
            try await analyzer.prepareToAnalyze(in: targetFormat)
            guard !Task.isCancelled, isLiveSessionActive(id: sessionID) else {
                await cancelClosure()
                return
            }
            try Self.installInputTap(on: inputNode, bufferSize: 2048, format: naturalFormat) { buffer, isOwnedCopy in
                let level = Self.rmsMeterLevel(from: buffer)
                meterBox.update(level)
                continuation.yield(SpeechUpdate(text: collector.cachedLatest(), isFinal: false, level: level))

                if let converter {
                    if let converted = Self.convertBuffer(buffer, using: converter, to: targetFormat) {
                        inputContinuation.yield(AnalyzerInput(buffer: converted))
                    }
                } else if isOwnedCopy {
                    inputContinuation.yield(AnalyzerInput(buffer: buffer))
                } else if let copy = Self.copyBuffer(buffer) {
                    inputContinuation.yield(AnalyzerInput(buffer: copy))
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            continuation.yield(SpeechUpdate(text: "", isFinal: false, level: 0, statusMessage: nil))
            try await analyzer.start(inputSequence: inputStream)
        } catch is CancellationError {
            await cancelClosure()
        } catch {
            Self.tearDownAudioEngine(audioEngine)
            inputContinuation.finish()
            resultsTask.cancel()
            await analyzer.cancelAndFinishNow()
            clearLive(id: sessionID)
            continuation.finish(
                throwing: SpeechError.failed(String(localized: "Couldn’t start speech recognition on this Mac."))
            )
        }
    }

    // MARK: - macOS 14–25 SFSpeechRecognizer (On-Device Only)

    static func makeLegacyFileRecognitionRequest(url: URL) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: url)
        configureLegacyRecognitionRequest(request, reportPartialResults: false)
        return request
    }

    static func makeLegacyLiveRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        configureLegacyRecognitionRequest(request, reportPartialResults: true)
        return request
    }

    static func configureLegacyRecognitionRequest(
        _ request: SFSpeechRecognitionRequest,
        reportPartialResults: Bool
    ) {
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = reportPartialResults
    }

    private func resolveLegacyRecognizerInstance(for locale: Locale) -> (any LegacySpeechRecognizing)? {
        if let legacyRecognizerProvider {
            return legacyRecognizerProvider(locale)
        }
        return Self.resolveLegacyRecognizer(for: locale)
    }

    private static func resolveLegacyRecognizer(for locale: Locale) -> SFSpeechRecognizer? {
        if let exact = SFSpeechRecognizer(locale: locale) {
            return exact
        }
        let targetLanguage = locale.language.languageCode?.identifier.lowercased()
        let targetScript = locale.language.script?.identifier.lowercased()
        guard let targetLanguage else { return nil }
        let supported = SFSpeechRecognizer.supportedLocales()
        if let targetScript,
           let scriptMatch = supported.first(where: {
               $0.language.languageCode?.identifier.lowercased() == targetLanguage
                   && $0.language.script?.identifier.lowercased() == targetScript
           }),
           let recognizer = SFSpeechRecognizer(locale: scriptMatch)
        {
            return recognizer
        }
        if let languageMatch = supported.first(where: {
            $0.language.languageCode?.identifier.lowercased() == targetLanguage
        }) {
            return SFSpeechRecognizer(locale: languageMatch)
        }
        return nil
    }

    private func transcribeFileLegacy(
        file: URL,
        locale: Locale,
        displayLanguage: String
    ) async throws -> String {
        guard let recognizer = resolveLegacyRecognizerInstance(for: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else {
            throw SpeechError.languageUnavailable(language: displayLanguage)
        }

        let request = Self.makeLegacyFileRecognitionRequest(url: file)

        let taskBox = LegacyTaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = OnceGate()
                let task = recognizer.startRecognitionTask(with: request) { result, error in
                    if let error {
                        guard gate.tryEnter() else { return }
                        continuation.resume(
                            throwing: SpeechError.failed(
                                Self.plainLegacyErrorMessage(error, displayLanguage: displayLanguage)
                            )
                        )
                        return
                    }
                    if let result, result.isFinal {
                        guard gate.tryEnter() else { return }
                        let text = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: text)
                    }
                }
                taskBox.store(task)
            }
        } onCancel: {
            taskBox.cancel()
        }
    }

    private func runLiveLegacy(
        sessionID: UUID,
        locale: Locale,
        displayLanguage: String,
        deviceUID: String?,
        registerHandlers: LiveHandlerRegistrar,
        continuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation
    ) async {
        guard let recognizer = resolveLegacyRecognizerInstance(for: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else {
            clearLive(id: sessionID)
            continuation.finish(throwing: SpeechError.languageUnavailable(language: displayLanguage))
            return
        }
        guard !Task.isCancelled, isLiveSessionActive(id: sessionID) else {
            continuation.finish()
            return
        }

        let audioEngine = AVAudioEngine()
        Self.configurePreferredInputDevice(uid: deviceUID, on: audioEngine)
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            clearLive(id: sessionID)
            continuation.finish(
                throwing: SpeechError.failed(String(localized: "Couldn’t access an audio input format on this Mac."))
            )
            return
        }

        let request = Self.makeLegacyLiveRecognitionRequest()

        let stateGuard = LiveExecutionGuard()
        let latestBox = LatestTextBox()
        let meterBox = MeterLevelBox()
        let taskBox = LegacyTaskBox()

        let task = recognizer.startRecognitionTask(with: request) { [weak self] result, error in
            guard !stateGuard.isCancelled else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                latestBox.update(text)
                if result.isFinal {
                    if stateGuard.markFinished() {
                        Self.tearDownAudioEngine(audioEngine)
                        self?.clearLive(id: sessionID)
                        continuation.yield(
                            SpeechUpdate(
                                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                isFinal: true,
                                level: 0
                            )
                        )
                        continuation.finish()
                    }
                } else {
                    continuation.yield(SpeechUpdate(text: text, isFinal: false, level: meterBox.current()))
                }
            }
            if let error {
                if stateGuard.isStopping, !latestBox.current().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if stateGuard.markFinished() {
                        Self.tearDownAudioEngine(audioEngine)
                        self?.clearLive(id: sessionID)
                        continuation.yield(
                            SpeechUpdate(
                                text: latestBox.current().trimmingCharacters(in: .whitespacesAndNewlines),
                                isFinal: true,
                                level: 0
                            )
                        )
                        continuation.finish()
                    }
                } else if stateGuard.markFinished() {
                    Self.tearDownAudioEngine(audioEngine)
                    self?.clearLive(id: sessionID)
                    continuation.finish(
                        throwing: SpeechError.failed(
                            Self.plainLegacyErrorMessage(error, displayLanguage: displayLanguage)
                        )
                    )
                }
            }
        }
        taskBox.store(task)

        let stopClosure: @Sendable () async -> Void = { [weak self] in
            guard stateGuard.beginStop() else { return }
            Self.tearDownAudioEngine(audioEngine)
            request.endAudio()
            try? await Task.sleep(for: .milliseconds(600))
            if stateGuard.markFinished() {
                taskBox.finish()
                self?.clearLive(id: sessionID)
                let text = latestBox.current().trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.yield(SpeechUpdate(text: text, isFinal: true, level: 0))
                continuation.finish()
            }
        }

        let cancelClosure: @Sendable () async -> Void = { [weak self] in
            guard stateGuard.beginCancel() else { return }
            Self.tearDownAudioEngine(audioEngine)
            request.endAudio()
            taskBox.cancel()
            self?.clearLive(id: sessionID)
            continuation.finish()
        }

        guard registerHandlers(stopClosure, cancelClosure) else {
            await cancelClosure()
            return
        }

        do {
            try Self.installInputTap(on: inputNode, bufferSize: 2048, format: format) { buffer, _ in
                let level = Self.rmsMeterLevel(from: buffer)
                meterBox.update(level)
                request.append(buffer)
                continuation.yield(SpeechUpdate(text: latestBox.current(), isFinal: false, level: level))
            }
            audioEngine.prepare()
            try audioEngine.start()
            continuation.yield(SpeechUpdate(text: "", isFinal: false, level: 0))
        } catch {
            Self.tearDownAudioEngine(audioEngine)
            taskBox.cancel()
            clearLive(id: sessionID)
            continuation.finish(
                throwing: SpeechError.failed(String(localized: "Couldn’t start microphone capture on this Mac."))
            )
        }
    }

    private static func plainLegacyErrorMessage(_ error: Error, displayLanguage: String) -> String {
        let nsError = error as NSError
        if nsError.localizedDescription.localizedCaseInsensitiveContains("on-device")
            || nsError.localizedDescription.localizedCaseInsensitiveContains("offline")
        {
            return SpeechError.languageUnavailable(language: displayLanguage).message
        }
        return String(localized: "Speech recognition failed on this Mac.")
    }
    #endif

    // MARK: - Audio Helpers

    private static func installInputTap(
        on inputNode: AVAudioInputNode,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat,
        handler: @escaping @Sendable (_ buffer: AVAudioPCMBuffer, _ isOwnedCopy: Bool) -> Void
    ) throws {
        if #available(macOS 27.0, *) {
            try inputNode.installAudioTap(onBus: 0, bufferSize: bufferSize, format: format) { readOnlyBuffer, _ in
                guard let pcmBuffer = copyReadOnlyBuffer(readOnlyBuffer) else { return }
                handler(pcmBuffer, true)
            }
        } else {
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
                handler(buffer, false)
            }
        }
    }

    @available(macOS 27.0, *)
    private static func copyReadOnlyBuffer(_ buffer: AVReadOnlyAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frameLength = AVAudioFrameCount(buffer.frameLength)
        guard frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frameLength)
        else {
            return nil
        }
        copy.frameLength = frameLength
        buffer.withUnsafeAudioBufferList { srcPtr in
            let srcList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: srcPtr))
            let dstList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (src, dst) in zip(srcList, dstList) {
                guard let srcData = src.mData, let dstData = dst.mData else { continue }
                memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
            }
        }
        return copy
    }

    private static func configurePreferredInputDevice(uid: String?, on engine: AVAudioEngine) {
        let resolved = AVAudioVoiceRecordingBackend.resolveAudioDeviceID(
            forUID: uid,
            in: AVAudioVoiceRecordingBackend.systemInputDevices()
        )
        guard let deviceID = resolved.deviceID else {
            return
        }
        if #available(macOS 27.0, *) {
            engine.inputNode.withAudioUnit { audioUnit in
                guard let audioUnit else { return }
                var mutableDeviceID = deviceID
                _ = AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &mutableDeviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
            }
        } else {
            guard let audioUnit = engine.inputNode.audioUnit else { return }
            var mutableDeviceID = deviceID
            _ = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
    }

    private static func tearDownAudioEngine(_ engine: AVAudioEngine) {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }

    private static func rmsMeterLevel(from buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else {
            return 0
        }
        let samples = channelData[0]
        var sumSquares: Float = 0
        for index in 0 ..< frameCount {
            let sample = samples[index]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        let minDb: Float = -55
        if decibels <= minDb { return 0 }
        if decibels >= 0 { return 1 }
        return (decibels - minDb) / -minDb
    }

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength
        let srcList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let dstList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(srcList, dstList) {
            guard let srcData = src.mData, let dstData = dst.mData else { continue }
            memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return copy
    }

    private static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }
        let consumed = OnceGate()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed.tryEnter() {
                outStatus.pointee = .haveData
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        guard conversionError == nil, status != .error, output.frameLength > 0 else {
            return nil
        }
        return output
    }
}

// MARK: - Concurrency Helpers

private actor ModernTranscriptCollector {
    private var finalizedSegments: [String] = []
    private var currentVolatile: String = ""
    private nonisolated(unsafe) var latestCombinedSnapshot: String = ""
    private let snapshotLock = NSLock()

    @discardableResult
    func ingest(text: String, isFinal: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            if !trimmed.isEmpty {
                finalizedSegments.append(trimmed)
            }
            currentVolatile = ""
        } else {
            currentVolatile = trimmed
        }
        let combined = buildCombined()
        storeLatestSnapshot(combined)
        return combined
    }

    func combinedText() -> String {
        buildCombined()
    }

    nonisolated func cachedLatest() -> String {
        snapshotLock.withLock { latestCombinedSnapshot }
    }

    nonisolated private func storeLatestSnapshot(_ combined: String) {
        snapshotLock.withLock {
            latestCombinedSnapshot = combined
        }
    }

    private func buildCombined() -> String {
        var parts = finalizedSegments
        if !currentVolatile.isEmpty {
            parts.append(currentVolatile)
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false

    func tryEnter() -> Bool {
        lock.withLock {
            guard !entered else { return false }
            entered = true
            return true
        }
    }
}

private final class MeterLevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func update(_ next: Float) {
        lock.withLock { value = min(max(next, 0), 1) }
    }

    func current() -> Float {
        lock.withLock { value }
    }
}

private final class LatestTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String = ""

    func update(_ next: String) {
        lock.withLock { value = next }
    }

    func current() -> String {
        lock.withLock { value }
    }
}

private final class LiveExecutionGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var stopping = false
    private var cancelled = false
    private var finished = false

    var isStopping: Bool {
        lock.withLock { stopping }
    }

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func beginStop() -> Bool {
        lock.withLock {
            guard !stopping, !cancelled, !finished else { return false }
            stopping = true
            return true
        }
    }

    func beginCancel() -> Bool {
        lock.withLock {
            guard !cancelled else { return false }
            cancelled = true
            finished = true
            return true
        }
    }

    func markFinished() -> Bool {
        lock.withLock {
            guard !finished, !cancelled else { return false }
            finished = true
            return true
        }
    }
}

#if canImport(Speech)
protocol LegacySpeechTasking: AnyObject {
    func finish()
    func cancel()
}

extension SFSpeechRecognitionTask: LegacySpeechTasking {}

protocol LegacySpeechRecognizing: AnyObject {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }
    func startRecognitionTask(
        with request: SFSpeechRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> any LegacySpeechTasking
}

extension SFSpeechRecognizer: LegacySpeechRecognizing {
    func startRecognitionTask(
        with request: SFSpeechRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> any LegacySpeechTasking {
        recognitionTask(with: request, resultHandler: resultHandler)
    }
}

private final class LegacyTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: (any LegacySpeechTasking)?
    private var cancelled = false

    func store(_ newTask: any LegacySpeechTasking) {
        let shouldCancel = lock.withLock { () -> Bool in
            if cancelled { return true }
            task = newTask
            return false
        }
        if shouldCancel {
            newTask.cancel()
        }
    }

    func finish() {
        lock.withLock { task }?.finish()
    }

    func cancel() {
        let existing = lock.withLock { () -> (any LegacySpeechTasking)? in
            cancelled = true
            let current = task
            task = nil
            return current
        }
        existing?.cancel()
    }
}
#endif
