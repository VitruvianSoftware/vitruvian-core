// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
#if canImport(Speech)
import Speech
#endif
import XCTest

@testable import VitruvianCourierCore

@MainActor
final class SpeechTranscriptionTests: XCTestCase {
    private var suites: [String] = []
    private var tempURLs: [URL] = []

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
        for url in tempURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempURLs = []
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        suites = []
    }

    private func makeDefaults() -> UserDefaults {
        let name = "test.courier.speech.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeTempAudioFile(named filename: String = "voice-note.ogg", contents: Data = Data("OggS-fake-audio-bytes".utf8)) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-speech-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURLs.append(dir)
        let fileURL = dir.appendingPathComponent(filename)
        try contents.write(to: fileURL)
        return fileURL
    }

    private func waitUntil(
        description: String = "condition",
        maxIterations: Int = 2_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        for _ in 0 ..< maxIterations {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }

    // MARK: - Language Mapping

    func testSpeechLanguageMapsAutoDetectAndNamedLanguages() {
        let customCurrent = Locale(identifier: "fr-CA")
        XCTAssertTrue(SpeechLanguage.isAutoDetect("Auto-Detect"))
        XCTAssertTrue(SpeechLanguage.isAutoDetect("  auto-detect "))
        XCTAssertTrue(SpeechLanguage.isAutoDetect(""))
        XCTAssertFalse(SpeechLanguage.isAutoDetect("Spanish"))

        // Auto-Detect -> current Mac locale for Apple, nil for Whisper (omits language field).
        XCTAssertEqual(
            SpeechLanguage.appleLocale(for: "Auto-Detect", currentLocale: customCurrent).identifier,
            customCurrent.identifier
        )
        XCTAssertNil(SpeechLanguage.whisperCode(for: "Auto-Detect"))

        // Named languages -> expected Apple locale and ISO-639-1 Whisper code.
        XCTAssertEqual(SpeechLanguage.appleLocale(for: "English", currentLocale: customCurrent).identifier, "en-US")
        XCTAssertEqual(SpeechLanguage.whisperCode(for: "English"), "en")

        XCTAssertEqual(SpeechLanguage.appleLocale(for: "Spanish", currentLocale: customCurrent).identifier, "es-ES")
        XCTAssertEqual(SpeechLanguage.whisperCode(for: "Spanish"), "es")

        XCTAssertEqual(SpeechLanguage.appleLocale(for: "Japanese", currentLocale: customCurrent).identifier, "ja-JP")
        XCTAssertEqual(SpeechLanguage.whisperCode(for: "Japanese"), "ja")

        XCTAssertEqual(SpeechLanguage.appleLocale(for: "Chinese (Simplified)", currentLocale: customCurrent).identifier, "zh-CN")
        XCTAssertEqual(SpeechLanguage.whisperCode(for: "Chinese (Simplified)"), "zh")

        XCTAssertEqual(SpeechLanguage.appleLocale(for: "Chinese (Traditional)", currentLocale: customCurrent).identifier, "zh-TW")
        XCTAssertEqual(SpeechLanguage.whisperCode(for: "Chinese (Traditional)"), "zh")

        // Every supported language in AIPreferences maps to a two-letter Whisper ISO-639-1 code.
        for language in AIPreferences.supportedTranslationLanguages {
            let code = SpeechLanguage.whisperCode(for: language)
            XCTAssertNotNil(code, "Expected Whisper ISO-639-1 code for \(language)")
            XCTAssertEqual(code?.count, 2, "Expected 2-letter ISO-639-1 code for \(language), got \(String(describing: code))")
        }
    }

    // MARK: - SpeechEngineFactory & AIProviderStore

    func testSpeechEngineFactoryResolvesAppleAndWhisperIndependentlyOfChatAI() async {
        let prefs = AIPreferences(defaults: makeDefaults())
        XCTAssertFalse(prefs.enableContextualAI, "Chat AI starts Off by default")
        XCTAssertFalse(prefs.useWhisperForTalkToType)

        let transport = SpeechFakeHTTPTransport()
        let credStore = SpeechInMemoryCredentialStore()
        let keyStore = AIKeyStore(store: credStore)
        let fakeApple = FakeSpeechEngine(provenance: .onThisMac)

        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: keyStore,
            transport: transport,
            appleEngineFactory: { fakeApple },
            appleAvailability: { lang in
                lang == "Japanese" ? .modelWillDownload : .ready
            }
        )

        // 1. Whisper off + Chat AI off -> Apple speech engine works and makes zero HTTP calls.
        switch factory.resolveEngine() {
        case let .available(engine):
            XCTAssertEqual(engine.provenance, .onThisMac)
        case let .notAllowed(reason):
            XCTFail("Expected Apple speech engine when Whisper is off, got notAllowed(\(reason))")
        }
        XCTAssertFalse(factory.canEnableWhisper)
        let readyLine = await factory.settingsStatusLine()
        XCTAssertEqual(readyLine, "On this Mac · Ready")

        prefs.transcriptionLanguage = "Japanese"
        let downloadLine = await factory.settingsStatusLine()
        XCTAssertEqual(downloadLine, "On this Mac · Speech model will download on first use")

        // 2. Whisper on without OpenAI key -> notAllowed, no fallback, zero HTTP calls.
        prefs.useWhisperForTalkToType = true
        switch factory.resolveEngine() {
        case .available:
            XCTFail("Expected .notAllowed when Whisper is enabled without an OpenAI key")
        case let .notAllowed(reason):
            XCTAssertEqual(reason, "Add an OpenAI key in the Cloud section to use Whisper.")
        }

        // 3. Save OpenAI key -> Whisper allowed even while Chat AI remains Off.
        XCTAssertNoThrow(try keyStore.saveKey("sk-openai-speech-key", for: .openAI).get())
        XCTAssertTrue(factory.canEnableWhisper)
        XCTAssertFalse(prefs.enableContextualAI, "Chat AI is still Off")
        switch factory.resolveEngine() {
        case let .available(engine):
            XCTAssertEqual(engine.provenance, .openAIWhisper)
            XCTAssertTrue(engine is WhisperClient)
        case let .notAllowed(reason):
            XCTFail("Expected WhisperClient once OpenAI key is saved, got notAllowed(\(reason))")
        }
        let whisperLine = await factory.settingsStatusLine()
        XCTAssertEqual(whisperLine, "OpenAI Whisper · audio is sent to OpenAI")
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAIProviderStoreRemovingOpenAIKeyResetsWhisperToggleAndUpdatesSpeechStatus() async {
        let prefs = AIPreferences(defaults: makeDefaults())
        let credStore = SpeechInMemoryCredentialStore(["openAI": "sk-test-key"])
        let keyStore = AIKeyStore(store: credStore)
        prefs.useWhisperForTalkToType = true

        let store = AIProviderStore(
            preferences: prefs,
            keyStore: keyStore,
            transport: SpeechFakeHTTPTransport(),
            appleSpeechAvailability: { lang in .notAvailable(language: lang) }
        )
        prefs.transcriptionLanguage = "Arabic"
        await store.refreshSpeechStatus()
        XCTAssertEqual(store.speechStatusLine, "OpenAI Whisper · audio is sent to OpenAI")

        // Removing the OpenAI key turns Whisper off and restores the on-device status line.
        _ = store.removeKey(for: .openAI)
        XCTAssertFalse(prefs.useWhisperForTalkToType)
        await store.refreshSpeechStatus()
        XCTAssertEqual(store.speechStatusLine, "On this Mac · Not available for Arabic")
    }

    // MARK: - WhisperClient

    func testWhisperClientBuildsExactMultipartRequestAndNeverLeaksKey() async throws {
        let secretKey = "sk-whisper-super-secret-998877"
        let audioBytes = Data("OggS\u{00}\u{02}opus-payload-bytes".utf8)
        let audioFile = try makeTempAudioFile(named: "clip.ogg", contents: audioBytes)
        let transport = SpeechFakeHTTPTransport()
        let client = WhisperClient(apiKey: secretKey, transport: transport)

        // Key must never appear in string descriptions.
        XCTAssertFalse(String(describing: client).contains(secretKey))
        XCTAssertFalse(String(reflecting: client).contains(secretKey))

        // 1. Auto-Detect omits `language` field.
        transport.enqueue(status: 200, json: #"{"text":"  See you at the trailhead. \n"}"#)
        let autoResult = try await client.transcribe(file: audioFile, language: "Auto-Detect")
        XCTAssertEqual(autoResult, "See you at the trailhead.")
        XCTAssertEqual(transport.requests.count, 1)

        let autoReq = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(autoReq.httpMethod, "POST")
        XCTAssertEqual(autoReq.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertFalse(autoReq.url?.absoluteString.contains(secretKey) ?? true, "API key must never appear in URL")
        XCTAssertEqual(autoReq.value(forHTTPHeaderField: "Authorization"), "Bearer \(secretKey)")

        let contentType = try XCTUnwrap(autoReq.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertFalse(boundary.isEmpty)

        let autoBody = try XCTUnwrap(StubHTTPTransport.bodyData(of: autoReq))
        let autoBodyLatin1 = try XCTUnwrap(String(data: autoBody, encoding: .isoLatin1))
        XCTAssertTrue(autoBodyLatin1.contains("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"))
        XCTAssertFalse(autoBodyLatin1.contains("name=\"language\""), "Auto-Detect must omit the language field")
        XCTAssertTrue(autoBodyLatin1.contains("Content-Disposition: form-data; name=\"file\"; filename=\"clip.ogg\"\r\nContent-Type: audio/ogg\r\n\r\n"))
        XCTAssertTrue(autoBody.range(of: audioBytes) != nil, "Multipart body must contain the exact audio bytes")
        XCTAssertFalse(autoBodyLatin1.contains(secretKey), "Multipart body must not contain the API key")

        // 2. Named language includes ISO-639-1 `language` field (`Spanish` -> `es`).
        transport.enqueue(status: 200, json: #"{"text":"Nos vemos a las seis."}"#)
        let spanishResult = try await client.transcribe(file: audioFile, language: "Spanish")
        XCTAssertEqual(spanishResult, "Nos vemos a las seis.")
        XCTAssertEqual(transport.requests.count, 2)

        let esReq = try XCTUnwrap(transport.requests.last)
        let esBody = try XCTUnwrap(StubHTTPTransport.bodyData(of: esReq))
        let esBodyLatin1 = try XCTUnwrap(String(data: esBody, encoding: .isoLatin1))
        XCTAssertTrue(esBodyLatin1.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\nes\r\n"))
    }

    func testWhisperClientMapsHTTPErrorsToPlainMessagesWithoutRawJSONOrKey() async throws {
        let secretKey = "sk-whisper-err-secret"
        let audioFile = try makeTempAudioFile()
        let transport = SpeechFakeHTTPTransport()
        let client = WhisperClient(apiKey: secretKey, transport: transport)

        // 401 -> plain badKey message
        transport.enqueue(status: 401, json: #"{"error":{"message":"Incorrect API key provided: sk-whisper-err-secret"}}"#)
        do {
            _ = try await client.transcribe(file: audioFile, language: "Auto-Detect")
            XCTFail("Expected 401 to throw SpeechError.badKey")
        } catch let error as SpeechError {
            XCTAssertEqual(error, .badKey)
            XCTAssertEqual(error.message, "OpenAI rejected the API key. Check it in Settings ▸ AI.")
            XCTAssertFalse(error.message.contains(secretKey))
            XCTAssertFalse(error.message.contains("{"))
        }

        // 429 -> plain rateLimited message
        transport.enqueue(status: 429, json: #"{"error":{"message":"Rate limit exceeded"}}"#)
        do {
            _ = try await client.transcribe(file: audioFile, language: "Auto-Detect")
            XCTFail("Expected 429 to throw SpeechError.rateLimited")
        } catch let error as SpeechError {
            XCTAssertEqual(error, .rateLimited)
            XCTAssertEqual(error.message, "OpenAI rate limit reached. Try again in a moment.")
        }

        // 502 -> plain HTTP status message
        transport.enqueue(status: 502, json: #"<html>Bad Gateway</html>"#)
        do {
            _ = try await client.transcribe(file: audioFile, language: "Auto-Detect")
            XCTFail("Expected 502 to throw SpeechError.failed")
        } catch let error as SpeechError {
            XCTAssertEqual(error.message, "OpenAI transcription failed (HTTP 502).")
            XCTAssertFalse(error.message.contains("<html>"))
        }

        // Network failure -> plain unreachable message
        transport.enqueue(error: URLError(.notConnectedToInternet))
        do {
            _ = try await client.transcribe(file: audioFile, language: "Auto-Detect")
            XCTFail("Expected URLError to throw SpeechError.unreachable")
        } catch let error as SpeechError {
            XCTAssertEqual(error, .unreachable)
            XCTAssertEqual(error.message, "Couldn’t reach OpenAI. Check your internet connection.")
        }
    }

    func testWhisperClientLiveTalkToTypeRecordsUploadsAndDeletesTempFile() async throws {
        let recordedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-live-\(UUID().uuidString).m4a")
        try Data("ftypM4A -recorded-voice".utf8).write(to: recordedURL)
        tempURLs.append(recordedURL)

        let recorder = FakeVoiceRecordingBackend(recordingURL: recordedURL, meterLevels: [0.45, 0.7])
        let transport = SpeechFakeHTTPTransport()
        transport.enqueue(status: 200, json: #"{"text":"Dictated through Whisper"}"#)

        let client = WhisperClient(
            apiKey: "sk-live-whisper",
            transport: transport,
            meterPollInterval: .milliseconds(10),
            preferredDeviceUID: { "usb-mic-1" },
            recorderFactory: { recorder }
        )

        let stream = client.startLive(language: "French")
        var updates: [SpeechUpdate] = []
        let consumer = Task { () -> [SpeechUpdate] in
            var collected: [SpeechUpdate] = []
            for try await update in stream {
                collected.append(update)
            }
            return collected
        }

        await waitUntil(description: "Whisper recorder started") { recorder.startCount == 1 }
        XCTAssertEqual(recorder.lastDeviceUID, "usb-mic-1")

        await client.stop()
        updates = try await consumer.value

        XCTAssertTrue(updates.contains(where: { $0.statusMessage == "Transcribing…" }))
        XCTAssertEqual(updates.last?.text, "Dictated through Whisper")
        XCTAssertEqual(updates.last?.isFinal, true)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: recordedURL.path),
            "Temporary recording file must be deleted after upload"
        )
    }

    // MARK: - TalkToTypeModel & ComposerModel

    private func makeTalkToTypeComposer(
        engine: FakeSpeechEngine,
        permissions: FakeSpeechPermissions = FakeSpeechPermissions(),
        maxDuration: Duration = TalkToTypeModel.defaultMaxDuration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) -> (composer: ComposerModel, sender: FakeSender) {
        let prefs = AIPreferences(defaults: makeDefaults())
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let talkToType = TalkToTypeModel(
            engineFactory: factory,
            permissions: permissions,
            maxDuration: maxDuration,
            sleep: sleep
        )
        let sender = FakeSender()
        let composer = ComposerModel(
            sender: sender,
            draftDelay: 0,
            sleep: { _ in },
            talkToType: talkToType
        )
        composer.aiPreferences = prefs
        composer.open("!room-a")
        return (composer, sender)
    }

    func testTalkToTypeTransitionsListeningFinishingAndInsertsAtCursorWithSpace() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.holdStopUntilReleased = true
        engine.finalTextOnStop = "see you at six"

        let (composer, sender) = makeTalkToTypeComposer(engine: engine)
        // Draft has "Hello world" with bold on "world" (offset 6, length 5); place cursor at index 5 (right after "Hello").
        composer.text = "Hello world"
        composer.entities = [TextEntity(kind: .bold, offset: 6, length: 5)]
        composer.selectionChanged(to: NSRange(location: 5, length: 0))

        XCTAssertEqual(composer.talkToType.state, .idle)

        // Start via triggerTalkToType (⌘⇧D).
        composer.triggerTalkToType()
        await waitUntil(description: "engine live stream started") { engine.liveStartCount == 1 }
        XCTAssertEqual(
            composer.talkToType.state,
            .listening(partialText: "", level: 0, provenance: .onThisMac, statusMessage: nil)
        )

        // Emit partial update and verify live strip state updates without touching composer.text.
        engine.emitLive(SpeechUpdate(text: "see you", isFinal: false, level: 0.6))
        await waitUntil(description: "partial update reflected") {
            if case let .listening(partial, _, _, _) = composer.talkToType.state {
                return partial == "see you"
            }
            return false
        }
        XCTAssertEqual(composer.text, "Hello world", "Draft must remain untouched while listening")

        // Second triggerTalkToType stops listening and enters .finishing until engine.stop() finishes.
        composer.triggerTalkToType()
        if case let .finishing(partial, provenance, _) = composer.talkToType.state {
            XCTAssertEqual(partial, "see you")
            XCTAssertEqual(provenance, .onThisMac)
        } else {
            XCTFail("Expected .finishing right after stopping, got \(composer.talkToType.state)")
        }

        engine.releaseStop()
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(composer.text, "Hello see you at six world")
        // Bold entity on "world" shifted cleanly by +" see you at six" (15 UTF-16 units) -> offset 21, length 5.
        XCTAssertEqual(composer.entities, [TextEntity(kind: .bold, offset: 21, length: 5)])
        XCTAssertTrue(sender.calls.isEmpty, "Talk to Type must never auto-send")
    }

    func testTalkToTypeInsertsWithoutLeadingSpaceAtStartOrAfterWhitespace() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.finalTextOnStop = "first words"
        let (composer, _) = makeTalkToTypeComposer(engine: engine)
        composer.text = ""
        composer.selectionChanged(to: NSRange(location: 0, length: 0))

        composer.triggerTalkToType()
        await waitUntil(description: "live started") { engine.liveStartCount == 1 }
        composer.triggerTalkToType()
        await composer.talkToType.waitForIdle()
        XCTAssertEqual(composer.text, "first words")

        // Trailing space already present -> no double space.
        composer.text = "Already spaced "
        composer.selectionChanged(to: NSRange(location: composer.text.utf16.count, length: 0))
        engine.finalTextOnStop = "next phrase"
        composer.triggerTalkToType()
        await waitUntil(description: "second live started") { engine.liveStartCount == 2 }
        composer.triggerTalkToType()
        await composer.talkToType.waitForIdle()
        XCTAssertEqual(composer.text, "Already spaced next phrase")
    }

    func testTalkToTypeEscapeCancelsImmediatelyAndInsertsNothing() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let (composer, sender) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Keep my draft"

        composer.triggerTalkToType()
        await waitUntil(description: "live started") { engine.liveStartCount == 1 }
        engine.emitLive(SpeechUpdate(text: "throw this away", isFinal: false, level: 0.5))
        await waitUntil(description: "partial received") {
            if case let .listening(partial, _, _, _) = composer.talkToType.state {
                return partial == "throw this away"
            }
            return false
        }

        _ = composer.escape()
        XCTAssertEqual(composer.talkToType.state, .idle)
        await waitUntil(description: "engine cancelled") { engine.cancelCount == 1 }
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.text, "Keep my draft")
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testTalkToTypeChatSwitchCancelsAndInsertsNothingInEitherChat() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let (composer, _) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Draft in room A"

        composer.triggerTalkToType()
        await waitUntil(description: "live started") { engine.liveStartCount == 1 }
        engine.emitLive(SpeechUpdate(text: "spoken while switching", isFinal: false, level: 0.4))
        await waitUntil(description: "partial received") {
            if case let .listening(partial, _, _, _) = composer.talkToType.state {
                return partial == "spoken while switching"
            }
            return false
        }

        // Switch to room B while listening.
        composer.open("!room-b")
        XCTAssertEqual(composer.talkToType.state, .idle)
        await waitUntil(description: "engine cancelled on chat switch") { engine.cancelCount == 1 }
        await composer.talkToType.waitForIdle()
        XCTAssertEqual(composer.text, "")

        // Switch back to room A: original draft is intact without partial dictation.
        composer.open("!room-a")
        XCTAssertEqual(composer.text, "Draft in room A")
    }

    func testTalkToTypeDeniedPermissionShowsNoticeAndLeavesDraftUnchanged() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let permissions = FakeSpeechPermissions(micStatus: .notDetermined, micGrantResult: false)
        let (composer, sender) = makeTalkToTypeComposer(engine: engine, permissions: permissions)
        composer.text = "Important unsent message"

        composer.triggerTalkToType()
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(engine.liveStartCount, 0)
        XCTAssertEqual(composer.text, "Important unsent message")
        XCTAssertEqual(
            composer.talkToType.permissionNotice,
            TalkToTypePermissionNotice(
                kind: .microphone,
                message: "Vitruvian Courier needs microphone access for Talk to Type."
            )
        )
        XCTAssertEqual(
            composer.talkToType.permissionNotice?.systemSettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testTalkToTypeEngineErrorShowsPlainNoticeAndLeavesDraftUnchanged() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let (composer, sender) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Do not touch this draft"

        composer.triggerTalkToType()
        await waitUntil(description: "live started") { engine.liveStartCount == 1 }

        engine.failLive(with: SpeechError.languageUnavailable(language: "Polish"))
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(composer.text, "Do not touch this draft")
        XCTAssertEqual(composer.notice?.displayText, "Speech recognition for Polish isn’t available on this Mac.")
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testTalkToTypeFiveMinuteCapStopsListeningAndInsertsRecognizedText() async {
        XCTAssertEqual(TalkToTypeModel.defaultMaxDuration, .seconds(300))

        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.finalTextOnStop = nil // Keep partial text recognized so far
        let sleepGate = CapSleepGate()

        let (composer, _) = makeTalkToTypeComposer(
            engine: engine,
            maxDuration: TalkToTypeModel.defaultMaxDuration,
            sleep: { duration in
                try await sleepGate.sleep(for: duration)
            }
        )
        composer.text = "Notes:"

        composer.triggerTalkToType()
        await waitUntil(description: "live started and 5-minute timer armed") {
            engine.liveStartCount == 1 && sleepGate.requestedDuration == .seconds(300)
        }

        engine.emitLive(SpeechUpdate(text: "captured before the five minute cap", isFinal: false, level: 0.5))
        await waitUntil(description: "partial captured") {
            if case let .listening(partial, _, _, _) = composer.talkToType.state {
                return partial == "captured before the five minute cap"
            }
            return false
        }

        // Fire the 5-minute cap.
        sleepGate.fire()
        await waitUntil(description: "engine stopped by cap") { engine.stopCount == 1 }
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(composer.text, "Notes: captured before the five minute cap")
    }

    func testTalkToTypeWithWhisperShowsSentToOpenAIProvenanceAndTranscribingStatus() async throws {
        let recordedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-talk-\(UUID().uuidString).m4a")
        try Data("ftypM4A -spoken".utf8).write(to: recordedURL)
        tempURLs.append(recordedURL)

        let recorder = FakeVoiceRecordingBackend(recordingURL: recordedURL, meterLevels: [0.5])
        let transport = SpeechFakeHTTPTransport()
        transport.enqueue(status: 200, json: #"{"text":"sent via whisper"}"#)
        let credStore = SpeechInMemoryCredentialStore(["openAI": "sk-whisper-strip-test"])
        let prefs = AIPreferences(defaults: makeDefaults())
        prefs.useWhisperForTalkToType = true

        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: credStore),
            transport: transport,
            recorderFactory: { recorder }
        )
        let talkToType = TalkToTypeModel(
            engineFactory: factory,
            permissions: FakeSpeechPermissions()
        )
        let sender = FakeSender()
        let composer = ComposerModel(
            sender: sender,
            draftDelay: 0,
            sleep: { _ in },
            talkToType: talkToType
        )
        composer.aiPreferences = prefs
        composer.open("!room-whisper")

        composer.triggerTalkToType()
        await waitUntil(description: "whisper live listening") {
            if case let .listening(_, _, provenance, _) = composer.talkToType.state {
                return provenance == .openAIWhisper && recorder.startCount == 1
            }
            return false
        }
        if case let .listening(_, _, provenance, _) = composer.talkToType.state {
            XCTAssertEqual(provenance.liveStripLabel, "Sent to OpenAI")
        } else {
            XCTFail("Expected .listening with .openAIWhisper")
        }
        XCTAssertEqual(SpeechProvenance.onThisMac.liveStripLabel, "On this Mac")

        composer.triggerTalkToType()
        await composer.talkToType.waitForIdle()
        XCTAssertEqual(composer.text, "sent via whisper")
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testCommandSetAndHotkeyTriggerTalkToTypeWhenChatIsOpen() async throws {
        let h = try await startConversation(
            ["!room-cmd": [textEvent(id: "$m1", room: "!room-cmd", at: 1, body: "Hi")]],
            rows: ["!room-cmd": chatRow("!room-cmd", name: "Alice", network: "whatsapp")]
        )
        try await h.open("!room-cmd")

        let conversation = h.conversation
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.finalTextOnStop = "from shortcut"

        let suiteDefaults = makeDefaults()
        let prefs = AIPreferences(defaults: suiteDefaults)
        conversation.composer.talkToType.permissions = FakeSpeechPermissions()
        conversation.composer.talkToType.engineFactory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        conversation.composer.aiPreferences = prefs

        let commands = CommandSet.all(conversation: conversation, composer: conversation.composer)
        let talkCommand = commands.first(where: { $0.id == "ai.talkToType" })
        XCTAssertNotNil(talkCommand)
        XCTAssertEqual(talkCommand?.shortcut, "⌘⇧D")

        // Trigger via command bar item -> starts listening.
        talkCommand?.run()
        await waitUntil(description: "command started live") { engine.liveStartCount == 1 }

        // Trigger again via HotkeyDispatcher (⌘⇧D) -> stops listening and inserts text.
        let inbox = InboxModel(appModel: h.app, preferences: InboxPreferences(defaults: suiteDefaults))
        let spaces = SpacesModel(appModel: h.app, inbox: inbox)
        let composerPrefs = ComposerPreferences(defaults: suiteDefaults)
        final class NoopSpeechPasteboard: TextPasteboard {
            func setString(_: String) {}
        }
        let messageActions = MessageActionsModel(
            conversation: conversation,
            appModel: h.app,
            preferences: composerPrefs,
            pasteboard: NoopSpeechPasteboard()
        )
        let lifecycle = SystemLifecycleModel(defaults: suiteDefaults)
        let coordinator = AppMenuCoordinator(inbox: inbox, lifecycle: lifecycle)
        let registry = HotkeyRegistry(defaults: suiteDefaults, isAppLocked: { lifecycle.isLocked })
        let search = SearchModel(
            appModel: h.app,
            recents: RecentSearches(defaults: suiteDefaults),
            open: { _ in }
        )
        let dispatcher = HotkeyDispatcher(
            inbox: inbox,
            spaces: spaces,
            conversation: conversation,
            messageActions: messageActions,
            search: search,
            lifecycle: lifecycle,
            menuCoordinator: coordinator,
            hotkeys: registry
        )
        XCTAssertTrue(dispatcher.perform(HotkeyID.talkToType))
        await conversation.composer.talkToType.waitForIdle()
        XCTAssertEqual(conversation.composer.text, "from shortcut")
    }

    // MARK: - VoiceNoteTranscriptStore & MessageMenu

    func testVoiceNoteTranscriptStoreCachesByEventIDAndSupportsCollapseToggle() async throws {
        let audioFile = try makeTempAudioFile()
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.transcribeResult = .success("Meet by the ferry building at noon.")

        let prefs = AIPreferences(defaults: makeDefaults())
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let store = VoiceNoteTranscriptStore(engineFactory: factory)

        await store.transcribe(eventID: "$vn-cache-1", mediaPath: audioFile.path)
        XCTAssertEqual(
            store.entry(for: "$vn-cache-1"),
            .transcribed(text: "Meet by the ferry building at noon.", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(engine.transcribeCallCount, 1)

        // Second call for same eventID hits session cache without invoking engine again.
        await store.transcribe(eventID: "$vn-cache-1", mediaPath: audioFile.path)
        XCTAssertEqual(engine.transcribeCallCount, 1)

        // Collapsing and expanding preserves cached transcript and provenance.
        store.toggleCollapsed(eventID: "$vn-cache-1")
        XCTAssertEqual(
            store.entry(for: "$vn-cache-1"),
            .transcribed(text: "Meet by the ferry building at noon.", provenance: .onThisMac, isCollapsed: true)
        )
        store.toggleCollapsed(eventID: "$vn-cache-1")
        XCTAssertEqual(
            store.entry(for: "$vn-cache-1"),
            .transcribed(text: "Meet by the ferry building at noon.", provenance: .onThisMac, isCollapsed: false)
        )
    }

    func testVoiceNoteTranscriptStoreDedupesConcurrentInFlightRequests() async throws {
        let audioFile = try makeTempAudioFile()
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.holdTranscribeUntilReleased = true
        engine.transcribeResult = .success("Transcribed once for both callers")

        let prefs = AIPreferences(defaults: makeDefaults())
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let store = VoiceNoteTranscriptStore(engineFactory: factory)

        let firstTask = Task { await store.transcribe(eventID: "$vn-dedupe", mediaPath: audioFile.path) }
        await waitUntil(description: "first transcribe in flight") {
            store.entry(for: "$vn-dedupe") == .transcribing && engine.transcribeCallCount == 1
        }

        let secondTask = Task { await store.transcribe(eventID: "$vn-dedupe", mediaPath: audioFile.path) }
        await Task.yield()
        XCTAssertEqual(engine.transcribeCallCount, 1, "In-flight request for same eventID must not start a second engine call")

        engine.releaseTranscribe()
        await firstTask.value
        await secondTask.value

        XCTAssertEqual(engine.transcribeCallCount, 1)
        XCTAssertEqual(
            store.entry(for: "$vn-dedupe"),
            .transcribed(text: "Transcribed once for both callers", provenance: .onThisMac, isCollapsed: false)
        )
    }

    func testVoiceNoteTranscriptStoreMissingLocalFileFailsCalmlyWithZeroEngineCalls() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let transport = SpeechFakeHTTPTransport()
        let prefs = AIPreferences(defaults: makeDefaults())
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: transport,
            appleEngineFactory: { engine }
        )
        let store = VoiceNoteTranscriptStore(engineFactory: factory)

        await store.transcribe(eventID: "$vn-mxc", mediaPath: "mxc://courier.local/media123")
        XCTAssertEqual(store.entry(for: "$vn-mxc"), .failed(message: "Download the voice note first."))

        await store.transcribe(eventID: "$vn-missing", mediaPath: "/tmp/nonexistent-\(UUID().uuidString).ogg")
        XCTAssertEqual(store.entry(for: "$vn-missing"), .failed(message: "Download the voice note first."))

        XCTAssertEqual(engine.transcribeCallCount, 0, "Missing local file must never invoke SpeechEngine")
        XCTAssertTrue(transport.requests.isEmpty, "Missing local file must never make network calls")
    }

    func testVoiceNoteAutoTranscribeSkipsOwnNotesAndRunsIncomingSequentially() async throws {
        let file1 = try makeTempAudioFile(named: "in-1.ogg")
        let file2 = try makeTempAudioFile(named: "in-2.ogg")
        let fileMine = try makeTempAudioFile(named: "mine.ogg")

        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.transcribeDelay = .milliseconds(15)
        engine.perFileTranscript = [
            file1.lastPathComponent: "Incoming first",
            file2.lastPathComponent: "Incoming second",
            fileMine.lastPathComponent: "Should never transcribe own note",
        ]

        let prefs = AIPreferences(defaults: makeDefaults())
        prefs.autoTranscribeVoiceNotes = true
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let store = VoiceNoteTranscriptStore(engineFactory: factory)

        // Own voice note is skipped.
        store.noteAppeared(eventID: "$mine", mediaPath: fileMine.path, isMine: true)
        // Two incoming voice notes run one at a time in order.
        store.noteAppeared(eventID: "$in-1", mediaPath: file1.path, isMine: false)
        store.noteAppeared(eventID: "$in-2", mediaPath: file2.path, isMine: false)

        await store.waitForIdle()

        XCTAssertNil(store.entry(for: "$mine"), "Auto-transcribe must skip outgoing (isMine == true) voice notes")
        XCTAssertEqual(
            store.entry(for: "$in-1"),
            .transcribed(text: "Incoming first", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(
            store.entry(for: "$in-2"),
            .transcribed(text: "Incoming second", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(engine.transcribedFilenames, ["in-1.ogg", "in-2.ogg"])
        XCTAssertEqual(engine.maxObservedTranscribeConcurrency, 1, "Auto-transcribe must run strictly one at a time")
    }

    func testMessageMenuOffersTranscribeForVoiceNoteEvenWhenChatAIIsOff() {
        let voiceMsg = TimelineMessage(
            id: "$voice-1",
            roomID: "!room:courier.local",
            sender: "@alice:courier.local",
            senderName: "Alice",
            senderAvatarPath: "",
            mine: false,
            ts: 1_760_600_000_000,
            kind: .voiceNote,
            body: "Voice message",
            rich: RichText(text: ""),
            isEdited: false,
            editCount: 0,
            editFailed: nil,
            failedEditID: nil,
            fileName: "voice.ogg",
            mimeType: "audio/ogg",
            byteSize: 12_345,
            width: nil,
            height: nil,
            mediaPath: "/tmp/voice.ogg",
            durationMS: 8_000,
            waveform: [20, 50, 80],
            played: false,
            statusLine: nil,
            countsAsUnread: true,
            poll: nil,
            thread: nil,
            bookmarked: false,
            expiresAt: nil,
            timerChange: nil,
            call: nil,
            reply: nil,
            reactions: [],
            startsGroup: true
        )

        let sections = MessageMenu.sections(
            for: voiceMsg,
            available: (actions: [.reply, .markAsPlayed], unavailable: []),
            features: ChatFeatures(source: .stored),
            disappearsIn: nil,
            time: { _ in "12:00 PM" },
            includeDiagnostics: true,
            isAIAvailable: false
        )
        let items = sections.flatMap { $0 }
        let transcribeItem = items.first { $0.command == .transcribeVoiceNote }
        XCTAssertNotNil(transcribeItem)
        XCTAssertEqual(transcribeItem?.title, "Transcribe")
        XCTAssertEqual(transcribeItem?.isEnabled, true)
    }

    func testTalkToTypeDeniedSpeechRecognitionPermissionShowsSettingsNoticeAndPreservesDraft() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let permissions = FakeSpeechPermissions(
            micStatus: .authorized,
            requiresSpeechPerm: true,
            speechStatus: .notDetermined,
            speechGrantResult: false
        )
        let (composer, sender) = makeTalkToTypeComposer(engine: engine, permissions: permissions)
        composer.text = "Draft preserved on speech permission denial"

        composer.triggerTalkToType()
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(engine.liveStartCount, 0)
        XCTAssertEqual(composer.text, "Draft preserved on speech permission denial")
        XCTAssertEqual(
            composer.talkToType.permissionNotice,
            TalkToTypePermissionNotice(
                kind: .speechRecognition,
                message: "Vitruvian Courier needs speech recognition access for Talk to Type."
            )
        )
        XCTAssertEqual(
            composer.talkToType.permissionNotice?.systemSettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
        )
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testTalkToTypeStopPressedTwiceIsIdempotentAndInsertsOnce() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.holdStopUntilReleased = true
        engine.finalTextOnStop = "dictated once"

        let (composer, sender) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Start"
        composer.selectionChanged(to: NSRange(location: composer.text.utf16.count, length: 0))

        composer.triggerTalkToType()
        await waitUntil(description: "live started") { engine.liveStartCount == 1 }

        // First stop transitions to .finishing; subsequent stop() and toggle() calls must be no-ops.
        composer.talkToType.stop()
        composer.talkToType.stop()
        composer.triggerTalkToType()
        await waitUntil(description: "engine stop invoked once") { engine.stopCount == 1 }
        XCTAssertEqual(engine.stopCount, 1)

        engine.releaseStop()
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(composer.text, "Start dictated once")
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testTalkToTypeCancelDuringFinishingDiscardsLateFinalResultOnChatSwitchAndEscape() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.holdStopUntilReleased = true
        engine.finalTextOnStop = "final after stop"

        let (composer, sender) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Draft A"
        composer.selectionChanged(to: NSRange(location: composer.text.utf16.count, length: 0))

        // 1. Switch chats while .finishing and emit a late final update before async engine.cancel() completes.
        composer.triggerTalkToType()
        await waitUntil(description: "first live started") { engine.liveStartCount == 1 }
        composer.triggerTalkToType()
        await waitUntil(description: "first stop in flight") { engine.stopCount == 1 }

        composer.open("!room-b")
        engine.emitLive(SpeechUpdate(text: "late final after cancel", isFinal: true, level: 0))
        XCTAssertEqual(composer.talkToType.state, .idle)
        await waitUntil(description: "first cancel reached engine") { engine.cancelCount == 1 }
        await composer.talkToType.waitForIdle()
        XCTAssertEqual(composer.text, "")

        composer.open("!room-a")
        XCTAssertEqual(composer.text, "Draft A")

        // 2. Press Escape while .finishing -> consumes Escape and discards final text.
        composer.triggerTalkToType()
        await waitUntil(description: "second live started") { engine.liveStartCount == 2 }
        composer.triggerTalkToType()
        await waitUntil(description: "second stop in flight") { engine.stopCount == 2 }

        XCTAssertTrue(composer.escape())
        engine.emitLive(SpeechUpdate(text: "late final after escape", isFinal: true, level: 0))
        XCTAssertEqual(composer.talkToType.state, .idle)
        await waitUntil(description: "second cancel reached engine") { engine.cancelCount == 2 }
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.text, "Draft A")
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testTalkToTypeWithNonEmptySelectionPreservesSelectedDraftText() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.finalTextOnStop = "there"

        let (composer, _) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Hello world"
        // Select "Hello" (range 0..<5); dictation must insert after selection rather than overwriting "Hello".
        composer.selectionChanged(to: NSRange(location: 0, length: 5))

        composer.triggerTalkToType()
        await waitUntil(description: "live started") { engine.liveStartCount == 1 }
        composer.triggerTalkToType()
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.text, "Hello there world")
    }

    // MARK: - Round 1 QA Regression Coverage

    func testAppleSpeechEngineCancelBeforeStartupFinishesInsertsNothingAndTearsDownEngine() async {
        // 1. Cancel while suspended inside async startup Task (e.g. model/format setup): startup Task is cancelled,
        //    engine setup tears down, and nothing is inserted into the composer.
        let probe1 = AppleStartupProbe()
        let appleEngine1 = AppleSpeechEngine(
            customLiveRunner: { _, _, _, _, registerHandlers, continuation in
                probe1.markSetupStarted()
                do {
                    try await probe1.waitCancellablyDuringStartup()
                } catch {
                    probe1.markEngineTornDown()
                    continuation.finish()
                    return
                }
                let cancelClosure: @Sendable () async -> Void = {
                    probe1.markEngineTornDown()
                    continuation.finish()
                }
                guard registerHandlers({}, cancelClosure) else {
                    await cancelClosure()
                    return
                }
                continuation.yield(SpeechUpdate(text: "should never insert", isFinal: true, level: 0))
                continuation.finish()
            }
        )

        let prefs1 = AIPreferences(defaults: makeDefaults())
        let factory1 = SpeechEngineFactory(
            preferences: prefs1,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { appleEngine1 }
        )
        let talk1 = TalkToTypeModel(engineFactory: factory1, permissions: FakeSpeechPermissions())
        let sender1 = FakeSender()
        let composer1 = ComposerModel(sender: sender1, draftDelay: 0, sleep: { _ in }, talkToType: talk1)
        composer1.aiPreferences = prefs1
        composer1.open("!room-startup-cancel")
        composer1.text = "Draft untouched"

        composer1.triggerTalkToType()
        await waitUntil(description: "Apple engine entered async startup") { probe1.setupStarted }

        XCTAssertTrue(composer1.escape())
        await composer1.talkToType.waitForIdle()

        XCTAssertTrue(probe1.startupTaskCancelled, "Cancelling during startup must cancel the in-progress startup Task")
        XCTAssertTrue(probe1.engineTornDown, "In-progress engine setup must be torn down on startup cancel")
        XCTAssertEqual(composer1.talkToType.state, .idle)
        XCTAssertEqual(composer1.text, "Draft untouched")
        XCTAssertTrue(sender1.calls.isEmpty)

        // 2. Race where non-throwing setup finishes right after cancel() ran before registerHandlers:
        //    registerHandlers returns false and immediately runs cancelClosure to tear down the engine.
        let probe2 = AppleStartupProbe()
        let appleEngine2 = AppleSpeechEngine(
            customLiveRunner: { _, _, _, _, registerHandlers, continuation in
                probe2.markSetupStarted()
                await probe2.waitUninterruptiblyUntilReleased()
                let cancelClosure: @Sendable () async -> Void = {
                    probe2.markEngineTornDown()
                    continuation.finish()
                }
                guard registerHandlers({}, cancelClosure) else {
                    await cancelClosure()
                    return
                }
                continuation.yield(SpeechUpdate(text: "raced text", isFinal: true, level: 0))
                continuation.finish()
            }
        )
        let stream = appleEngine2.startLive(language: "English")
        let drain = Task { () -> [SpeechUpdate] in
            var items: [SpeechUpdate] = []
            for try await item in stream {
                items.append(item)
            }
            return items
        }
        await waitUntil(description: "second Apple startup entered") { probe2.setupStarted }
        let cancelCall = Task {
            await appleEngine2.cancel()
        }
        await waitUntil(description: "startup Task marked cancelled") { probe2.startupTaskCancelled }
        probe2.releaseUninterruptibleWait()
        await cancelCall.value
        let collected = (try? await drain.value) ?? []
        XCTAssertTrue(collected.isEmpty)
        XCTAssertTrue(probe2.engineTornDown)
    }

    func testWhisperClientStartThenImmediateStopWaitsForStartupAndUploads() async throws {
        let recordedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper-immediate-stop-\(UUID().uuidString).m4a")
        try Data("ftypM4A -quick-tap".utf8).write(to: recordedURL)
        tempURLs.append(recordedURL)

        let recorder = FakeVoiceRecordingBackend(recordingURL: recordedURL, meterLevels: [0.4])
        recorder.holdStartUntilReleased = true

        let transport = SpeechFakeHTTPTransport()
        transport.enqueue(status: 200, json: #"{"text":"immediate whisper stop"}"#)
        let credStore = SpeechInMemoryCredentialStore(["openAI": "sk-whisper-immediate"])
        let prefs = AIPreferences(defaults: makeDefaults())
        prefs.useWhisperForTalkToType = true

        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: credStore),
            transport: transport,
            recorderFactory: { recorder }
        )
        let talkToType = TalkToTypeModel(engineFactory: factory, permissions: FakeSpeechPermissions())
        let sender = FakeSender()
        let composer = ComposerModel(sender: sender, draftDelay: 0, sleep: { _ in }, talkToType: talkToType)
        composer.aiPreferences = prefs
        composer.open("!room-whisper-fast")
        composer.text = "Prefix"
        composer.selectionChanged(to: NSRange(location: composer.text.utf16.count, length: 0))

        // Start Talk to Type; recorder.startRecording is still suspended in startup.
        composer.triggerTalkToType()
        await waitUntil(description: "recorder entered startRecording while still starting") {
            if case .listening = composer.talkToType.state {
                return recorder.startEntered && !recorder.isRecordingActive
            }
            return false
        }

        // Stop immediately BEFORE startRecording finishes.
        composer.triggerTalkToType()
        if case .finishing = composer.talkToType.state {
            // Expected
        } else {
            XCTFail("Expected .finishing after immediate stop, got \(composer.talkToType.state)")
        }

        recorder.releaseStart()
        await composer.talkToType.waitForIdle()

        XCTAssertNil(composer.notice, "Immediate stop must wait for startup rather than failing with a recording error")
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(composer.text, "Prefix immediate whisper stop")
        XCTAssertTrue(sender.calls.isEmpty)
    }

    func testVoiceNoteAutoTranscribeDequeueOnDisappearSkipsOffscreenAndMarksDoneOnlyAfterProcessed() async throws {
        let file1 = try makeTempAudioFile(named: "auto-1.ogg")
        let file2 = try makeTempAudioFile(named: "auto-2.ogg")
        let file3 = try makeTempAudioFile(named: "auto-3.ogg")

        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.holdTranscribeUntilReleased = true
        engine.perFileTranscript = [
            file1.lastPathComponent: "First note",
            file2.lastPathComponent: "Second note",
            file3.lastPathComponent: "Third note",
        ]

        let prefs = AIPreferences(defaults: makeDefaults())
        prefs.autoTranscribeVoiceNotes = true
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let store = VoiceNoteTranscriptStore(engineFactory: factory)

        store.noteAppeared(eventID: "$in-1", mediaPath: file1.path, isMine: false)
        store.noteAppeared(eventID: "$in-2", mediaPath: file2.path, isMine: false)
        store.noteAppeared(eventID: "$in-3", mediaPath: file3.path, isMine: false)

        await waitUntil(description: "first note in flight") {
            engine.transcribeCallCount == 1 && store.entry(for: "$in-1") == .transcribing
        }

        // $in-2 scrolls off screen before the worker reaches it.
        store.noteDisappeared(eventID: "$in-2")

        engine.releaseTranscribe()
        await store.waitForIdle()

        XCTAssertEqual(engine.transcribedFilenames, ["auto-1.ogg", "auto-3.ogg"])
        XCTAssertNil(store.entry(for: "$in-2"), "Dequeued off-screen note must not be transcribed")
        XCTAssertEqual(
            store.entry(for: "$in-1"),
            .transcribed(text: "First note", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(
            store.entry(for: "$in-3"),
            .transcribed(text: "Third note", provenance: .onThisMac, isCollapsed: false)
        )

        // Scrolling $in-2 back into view later still auto-transcribes it because it was never marked done early.
        store.noteAppeared(eventID: "$in-2", mediaPath: file2.path, isMine: false)
        await store.waitForIdle()
        XCTAssertEqual(
            store.entry(for: "$in-2"),
            .transcribed(text: "Second note", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(engine.transcribedFilenames, ["auto-1.ogg", "auto-3.ogg", "auto-2.ogg"])

        // Already-processed notes are marked done and never re-run on subsequent appearances.
        store.noteAppeared(eventID: "$in-1", mediaPath: file1.path, isMine: false)
        store.noteAppeared(eventID: "$in-2", mediaPath: file2.path, isMine: false)
        await store.waitForIdle()
        XCTAssertEqual(engine.transcribeCallCount, 3)
    }

    func testVoiceNoteMissingLocalFileClearsAndTranscribesOnceFileAppears() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-courier-delayed-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURLs.append(dir)
        let delayedManualURL = dir.appendingPathComponent("delayed-manual.ogg")
        let delayedAutoURL = dir.appendingPathComponent("delayed-auto.ogg")

        let engine = FakeSpeechEngine(provenance: .onThisMac)
        engine.perFileTranscript = [
            delayedManualURL.lastPathComponent: "Manual note after download",
            delayedAutoURL.lastPathComponent: "Auto note after download",
        ]

        let prefs = AIPreferences(defaults: makeDefaults())
        prefs.autoTranscribeVoiceNotes = true
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let store = VoiceNoteTranscriptStore(engineFactory: factory)

        // 1. Before download: reports missing local file with zero engine calls.
        await store.transcribe(eventID: "$vn-delayed-manual", mediaPath: delayedManualURL.path)
        XCTAssertEqual(store.entry(for: "$vn-delayed-manual"), .failed(message: "Download the voice note first."))
        XCTAssertEqual(engine.transcribeCallCount, 0)

        // Once the file appears on disk, the missing-file notice is no longer cached and a subsequent call transcribes.
        try Data("OggS-downloaded-manual".utf8).write(to: delayedManualURL)
        XCTAssertNil(store.entry(for: "$vn-delayed-manual"))

        await store.transcribe(eventID: "$vn-delayed-manual", mediaPath: delayedManualURL.path)
        XCTAssertEqual(
            store.entry(for: "$vn-delayed-manual"),
            .transcribed(text: "Manual note after download", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(engine.transcribeCallCount, 1)

        // 2. Auto-transcribe path after an earlier missing-file attempt also transcribes once downloaded.
        await store.transcribe(eventID: "$vn-delayed-auto", mediaPath: delayedAutoURL.path)
        XCTAssertEqual(store.entry(for: "$vn-delayed-auto"), .failed(message: "Download the voice note first."))
        try Data("OggS-downloaded-auto".utf8).write(to: delayedAutoURL)

        store.noteAppeared(eventID: "$vn-delayed-auto", mediaPath: delayedAutoURL.path, isMine: false)
        await store.waitForIdle()
        XCTAssertEqual(
            store.entry(for: "$vn-delayed-auto"),
            .transcribed(text: "Auto note after download", provenance: .onThisMac, isCollapsed: false)
        )
        XCTAssertEqual(engine.transcribeCallCount, 2)
    }

    func testStartingVoiceRecordingWhileTalkToTypeRunsCancelsTalkToType() async throws {
        let recordedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-note-cancel-ttt-\(UUID().uuidString).m4a")
        try Data("ftypM4A -voice".utf8).write(to: recordedURL)
        tempURLs.append(recordedURL)

        let voiceBackend = FakeVoiceRecordingBackend(recordingURL: recordedURL)
        let voiceRecorder = VoiceRecorderModel(backend: voiceBackend)
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let prefs = AIPreferences(defaults: makeDefaults())
        let factory = SpeechEngineFactory(
            preferences: prefs,
            keyStore: AIKeyStore(store: SpeechInMemoryCredentialStore()),
            transport: SpeechFakeHTTPTransport(),
            appleEngineFactory: { engine }
        )
        let talkToType = TalkToTypeModel(engineFactory: factory, permissions: FakeSpeechPermissions())
        let sender = FakeSender()
        let composer = ComposerModel(
            sender: sender,
            draftDelay: 0,
            sleep: { _ in },
            voiceRecorder: voiceRecorder,
            talkToType: talkToType
        )
        composer.aiPreferences = prefs
        composer.open("!room-voice-cancel")
        composer.text = "Keep my draft"

        composer.triggerTalkToType()
        await waitUntil(description: "Talk to Type listening") { engine.liveStartCount == 1 }
        engine.emitLive(SpeechUpdate(text: "partial before voice note", isFinal: false, level: 0.5))
        await waitUntil(description: "partial reflected") {
            if case let .listening(partial, _, _, _) = composer.talkToType.state {
                return partial == "partial before voice note"
            }
            return false
        }

        await composer.startVoiceRecording()
        engine.emitLive(SpeechUpdate(text: "late speech after voice start", isFinal: true, level: 0))
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertTrue(composer.voiceRecorder.isRecordingOrReviewing)
        XCTAssertEqual(voiceBackend.startCount, 1)
        XCTAssertEqual(composer.text, "Keep my draft")

        await composer.voiceRecorder.cancel()
    }

    func testSendingWhileTalkToTypeRunsCancelsTalkToTypeAndNeverInsertsLateSpeech() async {
        let engine = FakeSpeechEngine(provenance: .onThisMac)
        let (composer, sender) = makeTalkToTypeComposer(engine: engine)
        composer.text = "Ready to send now"

        composer.triggerTalkToType()
        await waitUntil(description: "Talk to Type listening") { engine.liveStartCount == 1 }
        engine.emitLive(SpeechUpdate(text: "spoken before pressing send", isFinal: false, level: 0.6))
        await waitUntil(description: "partial reflected") {
            if case let .listening(partial, _, _, _) = composer.talkToType.state {
                return partial == "spoken before pressing send"
            }
            return false
        }

        await composer.send()
        engine.emitLive(SpeechUpdate(text: "late final after send", isFinal: true, level: 0))
        await composer.talkToType.waitForIdle()

        XCTAssertEqual(composer.talkToType.state, .idle)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(composer.text, "", "Cancelled Talk to Type must not insert speech into the cleared composer")
        XCTAssertEqual(sender.calls.count, 1)
    }

    #if canImport(Speech)
    func testAppleSpeechEngineRequiresOnDeviceRecognitionAndNeverStartsServerRequest() async throws {
        let audioFile = try makeTempAudioFile(named: "ondevice-check.m4a", contents: Data("ftypM4A -local".utf8))

        // 1. Request builders always enforce requiresOnDeviceRecognition == true.
        let fileRequest = AppleSpeechEngine.makeLegacyFileRecognitionRequest(url: audioFile)
        XCTAssertTrue(fileRequest.requiresOnDeviceRecognition)
        XCTAssertFalse(fileRequest.shouldReportPartialResults)

        let liveRequest = AppleSpeechEngine.makeLegacyLiveRecognitionRequest()
        XCTAssertTrue(liveRequest.requiresOnDeviceRecognition)
        XCTAssertTrue(liveRequest.shouldReportPartialResults)

        // Verify transcribe() passes a request with requiresOnDeviceRecognition == true and starts zero server tasks.
        let onDeviceRecognizer = FakeLegacySpeechRecognizer(
            isAvailable: true,
            supportsOnDeviceRecognition: true
        )
        let supportedEngine = AppleSpeechEngine(
            forceLegacyBackend: true,
            legacyRecognizerProvider: { _ in onDeviceRecognizer }
        )
        do {
            _ = try await supportedEngine.transcribe(file: audioFile, language: "English")
            XCTFail("FakeLegacySpeechRecognizer finishes with simulated completion error after inspecting request")
        } catch {
            // Expected synthetic completion from fake recognizer (SFSpeechRecognitionResult has no public init).
        }
        XCTAssertEqual(onDeviceRecognizer.totalTasksStarted, 1)
        XCTAssertEqual(onDeviceRecognizer.capturedRequests.first?.requiresOnDeviceRecognition, true)
        XCTAssertEqual(onDeviceRecognizer.serverRequestsStarted, 0, "No server speech request may ever be started")

        // 2 & 3. When server recognition is available (isAvailable == true) but on-device recognition is NOT supported
        //        (supportsOnDeviceRecognition == false), both transcribe() and startLive() refuse with the exact plain
        //        message and never start any recognition task.
        let serverOnlyRecognizer = FakeLegacySpeechRecognizer(
            isAvailable: true,
            supportsOnDeviceRecognition: false
        )
        let unsupportedEngine = AppleSpeechEngine(
            forceLegacyBackend: true,
            legacyRecognizerProvider: { _ in serverOnlyRecognizer }
        )

        do {
            _ = try await unsupportedEngine.transcribe(file: audioFile, language: "Polish")
            XCTFail("Expected unsupported on-device language to throw SpeechError.languageUnavailable")
        } catch let error as SpeechError {
            XCTAssertEqual(error, .languageUnavailable(language: "Polish"))
            XCTAssertEqual(error.message, "Speech recognition for Polish isn’t available on this Mac.")
        }

        let liveStream = unsupportedEngine.startLive(language: "Polish")
        do {
            for try await _ in liveStream {
                XCTFail("Unsupported on-device language must not emit live updates")
            }
            XCTFail("Expected live stream to throw SpeechError.languageUnavailable")
        } catch let error as SpeechError {
            XCTAssertEqual(error, .languageUnavailable(language: "Polish"))
            XCTAssertEqual(error.message, "Speech recognition for Polish isn’t available on this Mac.")
        }

        XCTAssertEqual(serverOnlyRecognizer.totalTasksStarted, 0, "Unsupported on-device recognition must never fall back to a server task")
        XCTAssertEqual(serverOnlyRecognizer.serverRequestsStarted, 0)
    }
    #endif
}

// MARK: - Test Doubles

private final class SpeechInMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String]

    init(_ initial: [String: String] = [:]) {
        self.storage = initial
    }

    func read(account: String) throws -> String? {
        lock.withLock { storage[account] }
    }

    func write(_ value: String, account: String) throws {
        lock.withLock { storage[account] = value }
    }

    func delete(account: String) throws {
        _ = lock.withLock { storage.removeValue(forKey: account) }
    }
}

private typealias SpeechFakeHTTPTransport = StubHTTPTransport

private struct FakeSpeechPermissions: SpeechPermissionChecking {
    var micStatus: MicrophoneAuthStatus = .authorized
    var micGrantResult: Bool = true
    var requiresSpeechPerm: Bool = false
    var speechStatus: MicrophoneAuthStatus = .authorized
    var speechGrantResult: Bool = true

    func microphoneStatus() -> MicrophoneAuthStatus { micStatus }
    func requestMicrophoneAccess() async -> Bool { micGrantResult }
    func requiresSpeechRecognitionPermission(for _: SpeechProvenance) -> Bool { requiresSpeechPerm }
    func speechRecognitionStatus() -> MicrophoneAuthStatus { speechStatus }
    func requestSpeechRecognitionAccess() async -> Bool { speechGrantResult }
}

private final class FakeVoiceRecordingBackend: VoiceRecordingBackend, @unchecked Sendable {
    private struct NotStartedYetError: Error {}

    private let lock = NSLock()
    private let recordingURL: URL
    private let meterLevels: [Float]
    private var meterIndex = 0
    private var startGateContinuation: CheckedContinuation<Void, Never>?
    private var startReleased = false
    private var activeRecording = false
    var holdStartUntilReleased = false
    private(set) var startEntered = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0
    private(set) var lastDeviceUID: String?

    var isRecordingActive: Bool {
        lock.withLock { activeRecording }
    }

    init(recordingURL: URL, meterLevels: [Float] = [0.5]) {
        self.recordingURL = recordingURL
        self.meterLevels = meterLevels
    }

    func availableDevices() -> [AudioInputDevice] { [] }
    func authorizationStatus() -> MicrophoneAuthStatus { .authorized }
    func requestAccess() async -> Bool { true }

    func startRecording(deviceUID: String?) async throws -> URL {
        let shouldHold = markStartEntered(deviceUID: deviceUID)
        if shouldHold {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                storeStartWaiter(cont)
            }
        }
        markRecordingActive()
        return recordingURL
    }

    func releaseStart() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            startReleased = true
            let c = startGateContinuation
            startGateContinuation = nil
            return c
        }
        cont?.resume()
    }

    func currentMeterLevel() -> Float {
        lock.withLock {
            guard !meterLevels.isEmpty else { return 0 }
            let value = meterLevels[min(meterIndex, meterLevels.count - 1)]
            meterIndex += 1
            return value
        }
    }

    func stopRecording() async throws -> RecordedVoiceNote {
        guard finishActiveRecording() else {
            throw NotStartedYetError()
        }
        return RecordedVoiceNote(url: recordingURL, durationMS: 1_500, waveform: [30, 60])
    }

    func cancelRecording() async {
        recordCancel()
    }

    private func markStartEntered(deviceUID: String?) -> Bool {
        lock.withLock {
            startEntered = true
            lastDeviceUID = deviceUID
            return holdStartUntilReleased && !startReleased
        }
    }

    private func storeStartWaiter(_ cont: CheckedContinuation<Void, Never>) {
        let alreadyReleased = lock.withLock { () -> Bool in
            if startReleased { return true }
            startGateContinuation = cont
            return false
        }
        if alreadyReleased {
            cont.resume()
        }
    }

    private func markRecordingActive() {
        lock.withLock {
            startCount += 1
            activeRecording = true
        }
    }

    private func finishActiveRecording() -> Bool {
        lock.withLock {
            guard activeRecording else { return false }
            activeRecording = false
            stopCount += 1
            return true
        }
    }

    private func recordCancel() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            cancelCount += 1
            activeRecording = false
            startReleased = true
            let c = startGateContinuation
            startGateContinuation = nil
            return c
        }
        cont?.resume()
    }
}

private final class AppleStartupProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellableCont: CheckedContinuation<Void, Error>?
    private var uninterruptibleCont: CheckedContinuation<Void, Never>?
    private var uninterruptibleReleased = false
    private var _setupStarted = false
    private var _startupTaskCancelled = false
    private var _engineTornDown = false

    var setupStarted: Bool { lock.withLock { _setupStarted } }
    var startupTaskCancelled: Bool { lock.withLock { _startupTaskCancelled } }
    var engineTornDown: Bool { lock.withLock { _engineTornDown } }

    func markSetupStarted() {
        lock.withLock { _setupStarted = true }
    }

    func markEngineTornDown() {
        lock.withLock { _engineTornDown = true }
    }

    func markStartupTaskCancelled() {
        lock.withLock { _startupTaskCancelled = true }
    }

    func waitCancellablyDuringStartup() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                storeCancellable(cont)
            }
        } onCancel: {
            cancelCancellable()
        }
    }

    func waitUninterruptiblyUntilReleased() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                storeUninterruptible(cont)
            }
        } onCancel: {
            markStartupTaskCancelled()
        }
    }

    func releaseUninterruptibleWait() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            uninterruptibleReleased = true
            let c = uninterruptibleCont
            uninterruptibleCont = nil
            return c
        }
        cont?.resume()
    }

    private func storeCancellable(_ cont: CheckedContinuation<Void, Error>) {
        let alreadyCancelled = lock.withLock { () -> Bool in
            if _startupTaskCancelled { return true }
            cancellableCont = cont
            return false
        }
        if alreadyCancelled {
            cont.resume(throwing: CancellationError())
        }
    }

    private func cancelCancellable() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            _startupTaskCancelled = true
            let c = cancellableCont
            cancellableCont = nil
            return c
        }
        cont?.resume(throwing: CancellationError())
    }

    private func storeUninterruptible(_ cont: CheckedContinuation<Void, Never>) {
        let alreadyReleased = lock.withLock { () -> Bool in
            if uninterruptibleReleased { return true }
            uninterruptibleCont = cont
            return false
        }
        if alreadyReleased {
            cont.resume()
        }
    }
}

#if canImport(Speech)
private final class FakeLegacySpeechTask: LegacySpeechTasking {
    private(set) var didFinish = false
    private(set) var didCancel = false
    func finish() { didFinish = true }
    func cancel() { didCancel = true }
}

private final class FakeLegacySpeechRecognizer: LegacySpeechRecognizing, @unchecked Sendable {
    private struct SyntheticCompletionError: Error {}

    let isAvailable: Bool
    let supportsOnDeviceRecognition: Bool
    private let lock = NSLock()
    private(set) var capturedRequests: [SFSpeechRecognitionRequest] = []
    private(set) var totalTasksStarted = 0
    private(set) var serverRequestsStarted = 0

    init(isAvailable: Bool, supportsOnDeviceRecognition: Bool) {
        self.isAvailable = isAvailable
        self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
    }

    func startRecognitionTask(
        with request: SFSpeechRecognitionRequest,
        resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void
    ) -> any LegacySpeechTasking {
        lock.withLock {
            totalTasksStarted += 1
            capturedRequests.append(request)
            if !request.requiresOnDeviceRecognition {
                serverRequestsStarted += 1
            }
        }
        let task = FakeLegacySpeechTask()
        resultHandler(nil, SyntheticCompletionError())
        return task
    }
}
#endif

private final class CapSleepGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var fired = false
    private(set) var requestedDuration: Duration?

    func sleep(for duration: Duration) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                let finishImmediately = lock.withLock { () -> Bool in
                    requestedDuration = duration
                    if fired {
                        return true
                    }
                    continuation = cont
                    return false
                }
                if finishImmediately {
                    cont.resume()
                }
            }
        } onCancel: {
            let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                let c = continuation
                continuation = nil
                return c
            }
            cont?.resume(throwing: CancellationError())
        }
    }

    func fire() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            fired = true
            let c = continuation
            continuation = nil
            return c
        }
        cont?.resume()
    }
}

private final class FakeSpeechEngine: SpeechEngine, @unchecked Sendable {
    let provenance: SpeechProvenance
    private let lock = NSLock()

    private var liveContinuation: AsyncThrowingStream<SpeechUpdate, Error>.Continuation?
    private var stopGateContinuation: CheckedContinuation<Void, Never>?
    private var stopReleased = false
    private var transcribeGateContinuation: CheckedContinuation<Void, Never>?
    private var transcribeReleased = false

    private var currentTranscribeConcurrency = 0
    private(set) var maxObservedTranscribeConcurrency = 0
    private(set) var transcribeCallCount = 0
    private(set) var transcribedFilenames: [String] = []
    private(set) var liveStartCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    var holdStopUntilReleased = false
    var finalTextOnStop: String?
    var holdTranscribeUntilReleased = false
    var transcribeDelay: Duration?
    var transcribeResult: Result<String, Error> = .success("Transcript")
    var perFileTranscript: [String: String] = [:]

    init(provenance: SpeechProvenance) {
        self.provenance = provenance
    }

    func transcribe(file: URL, language _: String) async throws -> String {
        let shouldHold = lock.withLock { () -> Bool in
            transcribeCallCount += 1
            transcribedFilenames.append(file.lastPathComponent)
            currentTranscribeConcurrency += 1
            if currentTranscribeConcurrency > maxObservedTranscribeConcurrency {
                maxObservedTranscribeConcurrency = currentTranscribeConcurrency
            }
            return holdTranscribeUntilReleased && !transcribeReleased
        }
        defer {
            lock.withLock {
                currentTranscribeConcurrency -= 1
            }
        }

        if shouldHold {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let alreadyReleased = lock.withLock { () -> Bool in
                    if transcribeReleased { return true }
                    transcribeGateContinuation = cont
                    return false
                }
                if alreadyReleased {
                    cont.resume()
                }
            }
        }

        if let delay = transcribeDelay {
            try await Task.sleep(for: delay)
        }

        let mapped = lock.withLock { perFileTranscript[file.lastPathComponent] }
        if let mapped {
            return mapped
        }
        return try lock.withLock { transcribeResult }.get()
    }

    func releaseTranscribe() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            transcribeReleased = true
            let c = transcribeGateContinuation
            transcribeGateContinuation = nil
            return c
        }
        cont?.resume()
    }

    func startLive(language _: String) -> AsyncThrowingStream<SpeechUpdate, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock {
                liveStartCount += 1
                stopReleased = false
                liveContinuation = continuation
            }
        }
    }

    func emitLive(_ update: SpeechUpdate) {
        let cont = lock.withLock { liveContinuation }
        cont?.yield(update)
    }

    func failLive(with error: Error) {
        let cont = lock.withLock { () -> AsyncThrowingStream<SpeechUpdate, Error>.Continuation? in
            let c = liveContinuation
            liveContinuation = nil
            return c
        }
        cont?.finish(throwing: error)
    }

    func stop() async {
        let shouldHold = lock.withLock { () -> Bool in
            stopCount += 1
            return holdStopUntilReleased && !stopReleased
        }
        if shouldHold {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let alreadyReleased = lock.withLock { () -> Bool in
                    if stopReleased { return true }
                    stopGateContinuation = cont
                    return false
                }
                if alreadyReleased {
                    cont.resume()
                }
            }
        }
        let (cont, finalText) = lock.withLock { () -> (AsyncThrowingStream<SpeechUpdate, Error>.Continuation?, String?) in
            let c = liveContinuation
            liveContinuation = nil
            return (c, finalTextOnStop)
        }
        if let finalText {
            cont?.yield(SpeechUpdate(text: finalText, isFinal: true, level: 0))
        }
        cont?.finish()
    }

    func releaseStop() {
        let cont = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            stopReleased = true
            let c = stopGateContinuation
            stopGateContinuation = nil
            return c
        }
        cont?.resume()
    }

    func cancel() async {
        let (liveCont, stopCont) = lock.withLock {
            () -> (AsyncThrowingStream<SpeechUpdate, Error>.Continuation?, CheckedContinuation<Void, Never>?) in
            cancelCount += 1
            let lc = liveContinuation
            liveContinuation = nil
            let sc = stopGateContinuation
            stopGateContinuation = nil
            return (lc, sc)
        }
        stopCont?.resume()
        liveCont?.finish()
    }
}
