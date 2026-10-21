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
import Testing
@testable import HomeSpeakerCore

// Rewording agents' replies (`announcement_style`) and the Gemini voice on
// this Mac (`local_engine: gemini`). Nothing here reaches the network or
// makes a sound: every model, request and player is a fake.

// MARK: - Fakes

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-style-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A model that answers, fails or stalls, and records what it was asked.
private final class FakeModel: StyleRewriting, @unchecked Sendable {
    enum Behaviour { case answer(String), fail, stall }
    private let lock = NSLock()
    private let behaviour: Behaviour
    private var _calls: [(text: String, instructions: String, key: String?)] = []
    var calls: [(text: String, instructions: String, key: String?)] { lock.withLock { _calls } }

    init(_ behaviour: Behaviour) { self.behaviour = behaviour }

    func rewrite(_ text: String, instructions: String, apiKey: String?) async throws -> String {
        lock.withLock { _calls.append((text, instructions, apiKey)) }
        switch behaviour {
        case .answer(let out): return out
        case .fail: throw StyleRewriteError.unavailable("no model")
        case .stall:
            try await Task.sleep(for: .seconds(30))
            return "too late"
        }
    }
}

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.withLock { items.append(s) } }
    var all: [String] { lock.withLock { items } }
}

private func styled(_ style: AnnouncementStyle, model: StyleModel = .apple, custom: String? = nil,
                    length: SpeechLength = .summary) -> SpeakerConfig {
    var c = SpeakerConfig()
    c.announcementStyle = style
    c.styleModel = model
    c.customStylePrompt = custom
    c.speechLength = length
    return c
}

private let reply = """
    ## Done
    I fixed the **flaky test** in `Sources/App/Foo.swift`. See https://example.test/pr/1.
    ```swift
    let x = 1
    ```
    Next: run the suite again.
    """

// MARK: - The settings

@Suite struct StyleSettingsTests {
    @Test func anOldConfigReadsAsWrittenInTheMacVoice() throws {
        let c = try JSONDecoder().decode(SpeakerConfig.self, from: Data(#"{"enabled":true,"default_target":"","structure_id":"","targets":{}}"#.utf8))
        #expect(c.announcementStyle == nil && c.styleModel == nil && c.localEngine == nil && c.geminiVoice == nil)
        #expect(c.effectiveAnnouncementStyle == .verbatim)
        #expect(c.effectiveStyleModel == .apple)
        #expect(c.effectiveLocalEngine == .apple)
        #expect(c.effectiveGeminiVoice == "Kore")
        #expect(c.effectiveCustomStylePrompt == "")
    }

    @Test func theNewKeysRoundTripInSnakeCase() throws {
        var c = SpeakerConfig()
        c.effectiveAnnouncementStyle = .briefing
        c.customStylePrompt = "  like a pirate  "
        c.effectiveStyleModel = .gemini
        c.effectiveLocalEngine = .gemini
        c.effectiveGeminiVoice = "Puck"
        let data = try JSONEncoder().encode(c)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["announcement_style"] as? String == "briefing")
        #expect(json["custom_style_prompt"] as? String == "  like a pirate  ")
        #expect(json["style_model"] as? String == "gemini")
        #expect(json["local_engine"] as? String == "gemini")
        #expect(json["gemini_voice"] as? String == "Puck")
        let back = try JSONDecoder().decode(SpeakerConfig.self, from: data)
        #expect(back == c)
        #expect(back.effectiveCustomStylePrompt == "like a pirate")
    }

    /// A newer HomeSpeaker's choice must not stop this one reading the file.
    @Test func unknownChoicesReadAsTheDefaults() throws {
        let json = #"{"enabled":true,"default_target":"","structure_id":"","targets":{},"announcement_style":"haiku","style_model":"claude","local_engine":"elevenlabs","speech_length":"summary"}"#
        let c = try JSONDecoder().decode(SpeakerConfig.self, from: Data(json.utf8))
        #expect(c.effectiveAnnouncementStyle == .verbatim)
        #expect(c.effectiveStyleModel == .apple)
        #expect(c.effectiveLocalEngine == .apple)
    }

    @Test func anEmptyGeminiVoiceMeansKore() {
        var c = SpeakerConfig()
        c.geminiVoice = "  "
        #expect(c.effectiveGeminiVoice == "Kore")
        c.geminiVoice = "Sulafat"
        #expect(c.effectiveGeminiVoice == "Sulafat", "a voice set by hand is kept")
    }

    @Test func theLabelsAreTheOnesSettingsShows() {
        #expect(AnnouncementStyle.allCases.map(\.label) == ["As written", "Plain summary", "Status update", "Conversational", "Custom…"])
        #expect(StyleModel.allCases.map(\.label) == ["Apple (On-device)", "Gemini"])
        #expect(LocalVoiceEngine.allCases.map(\.label) == ["Apple (System)", "Gemini TTS"])
        #expect(GeminiVoice.allCases.map(\.rawValue) == ["Kore", "Puck", "Aoede", "Charon", "Zephyr", "Fenrir", "Leda", "Orus"])
        #expect(GeminiVoice.kore.label == "Kore · Warm & clear")
    }

    @Test func theChatPrivacyLineNamesGeminiOnlyWhenItSpeaks() {
        var c = SpeakerConfig()
        #expect(c.chatMessagesSentTo == "Nothing is sent anywhere except to Google Home.")
        c.effectiveLocalEngine = .gemini
        #expect(!c.chatMessagesSentTo.contains("Gemini"), "Gemini chosen but This Mac off: nothing goes to it")
        c.effectiveSpeakLocal = true
        #expect(c.chatMessagesSentTo.contains("Gemini"))
    }

    @Test func theGeminiKeyIsKeptInTheSecretsFile() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SecretStore(fileURL: dir.appendingPathComponent("secrets.json"))
        try store.update { $0.slackToken = "xoxp-kept" }
        try store.update { $0.geminiApiKey = "gemini-key" }
        #expect(store.load().geminiApiKey == "gemini-key")
        #expect(store.load().slackToken == "xoxp-kept")
        let attrs = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(raw.contains("\"geminiApiKey\""))
        try store.update { $0.geminiApiKey = nil }
        #expect(store.load().geminiApiKey == nil)
    }
}

// MARK: - The stylist

@Suite struct AnnouncementStylistTests {
    private func stylist(gemini: FakeModel, apple: FakeModel, key: String? = "k", timeout: Double = 1,
                         log: Lines = Lines()) -> AnnouncementStylist {
        AnnouncementStylist(gemini: gemini, apple: apple, geminiKey: { key }, timeout: timeout, log: { log.add($0) })
    }

    @Test func asWrittenAsksNoModelAndCleansAsBefore() async {
        let gemini = FakeModel(.answer("x")), apple = FakeModel(.answer("x"))
        let out = await stylist(gemini: gemini, apple: apple).style(reply, config: styled(.verbatim, model: .gemini))
        #expect(out == GoogleHomeClient.cleanForSpeech(reply, length: .summary))
        #expect(gemini.calls.isEmpty && apple.calls.isEmpty)
    }

    @Test func customWithNoInstructionIsAsWritten() async {
        let apple = FakeModel(.answer("x"))
        let out = await stylist(gemini: FakeModel(.fail), apple: apple).style(reply, config: styled(.custom, custom: "   "))
        #expect(out == GoogleHomeClient.cleanForSpeech(reply, length: .summary))
        #expect(apple.calls.isEmpty)
        #expect(!AnnouncementStylist.rewrites(styled(.custom, custom: " ")))
        #expect(AnnouncementStylist.rewrites(styled(.custom, custom: "like a pirate")))
    }

    @Test func aStyleRewordsAndTheResultIsCleanedAgain() async throws {
        let apple = FakeModel(.answer("**Fixed** the flaky test in `Foo.swift`. Next, run the suite. https://x.test/1"))
        let out = await stylist(gemini: FakeModel(.fail), apple: apple).style(reply, config: styled(.briefing))
        #expect(out == "Fixed the flaky test in Foo.swift. Next, run the suite.")
        let call = try #require(apple.calls.first)
        #expect(call.key == nil, "Apple's model is never given the Gemini key")
        #expect(call.instructions.contains("status update"))
        #expect(!call.text.contains("let x = 1"), "code blocks never reach the model")
    }

    @Test func eachStyleHasItsOwnInstruction() throws {
        let plain = try #require(AnnouncementStylist.instructions(for: styled(.plain)))
        let casual = try #require(AnnouncementStylist.instructions(for: styled(.casual)))
        let custom = try #require(AnnouncementStylist.instructions(for: styled(.custom, custom: "like a ship captain")))
        #expect(plain != casual)
        #expect(custom.hasSuffix("Style: like a ship captain"))
        for text in [plain, casual, custom] { #expect(text.contains("No markdown")) }
        #expect(AnnouncementStylist.instructions(for: styled(.verbatim)) == nil)
    }

    @Test func geminiIsUsedWhenChosenWithAKey() async throws {
        let gemini = FakeModel(.answer("All fixed.")), apple = FakeModel(.answer("Apple"))
        let out = await stylist(gemini: gemini, apple: apple, key: " key-1 ").style(reply, config: styled(.plain, model: .gemini))
        #expect(out == "All fixed.")
        #expect(gemini.calls.first?.key == "key-1")
        #expect(apple.calls.isEmpty)
    }

    @Test func geminiWithNoKeyGoesStraightToApple() async {
        let gemini = FakeModel(.answer("Gemini")), apple = FakeModel(.answer("Apple says it."))
        let log = Lines()
        let out = await stylist(gemini: gemini, apple: apple, key: nil, log: log).style(reply, config: styled(.plain, model: .gemini))
        #expect(out == "Apple says it.")
        #expect(gemini.calls.isEmpty)
        #expect(log.all.contains { $0.contains("no Gemini API key") })
    }

    @Test func geminiFailingFallsBackToApple() async {
        let apple = FakeModel(.answer("Apple says it."))
        let out = await stylist(gemini: FakeModel(.fail), apple: apple).style(reply, config: styled(.plain, model: .gemini))
        #expect(out == "Apple says it.")
    }

    @Test func bothFailingReadsTheReplyAsWritten() async {
        let log = Lines()
        let out = await stylist(gemini: FakeModel(.fail), apple: FakeModel(.fail), log: log)
            .style(reply, config: styled(.casual, model: .gemini, length: .headline))
        #expect(out == GoogleHomeClient.cleanForSpeech(reply, length: .headline))
        #expect(log.all.count == 2, "each failure is logged")
    }

    @Test func aModelThatStallsIsGivenUpOn() async {
        let start = Date()
        let out = await stylist(gemini: FakeModel(.stall), apple: FakeModel(.stall), timeout: 0.2)
            .style(reply, config: styled(.plain, model: .gemini))
        #expect(out == GoogleHomeClient.cleanForSpeech(reply, length: .summary))
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test func anAnswerThatCleansToNothingFallsThrough() async {
        let apple = FakeModel(.answer("Apple says it."))
        let out = await stylist(gemini: FakeModel(.answer("```\ncode only\n```")), apple: apple)
            .style(reply, config: styled(.plain, model: .gemini))
        #expect(out == "Apple says it.")
    }

    @Test func theRewordedTextKeepsToTheSpeechLength() async {
        let long = Array(repeating: "This sentence is here to be long enough to matter.", count: 10).joined(separator: " ")
        let out = await stylist(gemini: FakeModel(.fail), apple: FakeModel(.answer(long)))
            .style(reply, config: styled(.plain, length: .headline))
        #expect(out.count <= SpeechLength.headline.maxCharacters)
    }

    @Test func theModelSeesAtMostTheInputLimit() {
        let huge = String(repeating: "word ", count: 2000)
        #expect(AnnouncementStylist.modelInput(huge).count <= AnnouncementStylist.inputLimit)
    }
}

// MARK: - Gemini's text request

@Suite struct GeminiStyleRewriterTests {
    @Test func theKeyGoesInAHeaderNeverTheURL() throws {
        let request = try GeminiStyleRewriter.request("hello", instructions: "be brief", apiKey: "secret-key")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "secret-key")
        #expect(!(request.url?.absoluteString.contains("secret-key") ?? true))
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let system = (body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: Any]]
        #expect(system?.first?["text"] as? String == "be brief")
        let config = body["generationConfig"] as? [String: Any]
        #expect((config?["thinkingConfig"] as? [String: Any])?["thinkingBudget"] as? Int == 0)
    }

    @Test func itReadsTheCandidatesText() async throws {
        let answer = #"{"candidates":[{"content":{"parts":[{"text":"All "},{"text":"done."}]}}]}"#
        let rewriter = GeminiStyleRewriter { request in
            (Data(answer.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(try await rewriter.rewrite("x", instructions: "y", apiKey: "k") == "All  done.")
    }

    @Test func anErrorSaysGooglesMessageNotTheKey() async {
        let answer = #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key."}}"#
        let rewriter = GeminiStyleRewriter { request in
            (Data(answer.utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await rewriter.rewrite("x", instructions: "y", apiKey: "my-secret")
            Issue.record("a 400 must throw")
        } catch {
            #expect(error.localizedDescription == "Gemini answered 400: API key not valid. Please pass a valid API key.")
            #expect(!error.localizedDescription.contains("my-secret"))
        }
    }
}

// MARK: - Gemini's voice

private final class FakePlayer: AudioPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var _played: [Data] = []
    var played: [Data] { lock.withLock { _played } }
    var fails = false
    func play(_ wav: Data) async throws {
        lock.withLock { _played.append(wav) }
        if fails { throw GeminiSpeechError.unplayable }
    }
}

private func ok(_ request: URLRequest, _ body: String) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
}

/// One second of 24 kHz 16-bit mono silence.
private let oneSecondPCM = Data(count: 48_000)

@Suite struct GeminiSpeakerTests {
    @Test func aWAVIsPlayedAsItCame() {
        let wav = GeminiSpeaker.wavHeader(pcmBytes: 4, sampleRate: 24000) + Data([1, 2, 3, 4])
        #expect(GeminiSpeaker.wav(from: wav, mimeType: "audio/wav") == wav)
    }

    @Test func rawPCMGetsA44ByteHeaderAtItsRate() throws {
        let wav = GeminiSpeaker.wav(from: oneSecondPCM, mimeType: "audio/L16;codec=pcm;rate=16000")
        #expect(wav.count == 44 + oneSecondPCM.count)
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(wav[8..<12] == Data("WAVE".utf8))
        let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
        #expect(rate == 16000)
        #expect(GeminiSpeaker.duration(ofWAV: wav) == 1.5, "48 000 bytes at 32 000 bytes a second")
        #expect(GeminiSpeaker.duration(ofWAV: GeminiSpeaker.wav(from: oneSecondPCM, mimeType: nil)) == 1, "24 kHz when unsaid")
    }

    @Test func itReadsTheInteractionsAnswer() throws {
        let wav = GeminiSpeaker.wavHeader(pcmBytes: 2, sampleRate: 24000) + Data([0, 0])
        let body = """
            {"steps":[{"type":"user_input"},{"type":"model_output","content":[{"type":"text","text":"hi"},\
            {"type":"audio","mime_type":"audio/wav","data":"\(wav.base64EncodedString())"}]}]}
            """
        #expect(try GeminiSpeaker.audio(fromResponse: Data(body.utf8)) == wav)
    }

    @Test func itReadsTheLegacyAnswerAndWrapsItsPCM() throws {
        let body = """
            {"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"audio/L16;codec=pcm;rate=24000",\
            "data":"\(oneSecondPCM.base64EncodedString())"}}]}}]}
            """
        let wav = try GeminiSpeaker.audio(fromResponse: Data(body.utf8))
        #expect(wav.prefix(4) == Data("RIFF".utf8))
        #expect(GeminiSpeaker.duration(ofWAV: wav) == 1)
    }

    @Test func anAnswerWithNoAudioThrows() {
        #expect(throws: GeminiSpeechError.noAudio) { try GeminiSpeaker.audio(fromResponse: Data(#"{"steps":[]}"#.utf8)) }
    }

    @Test func theRequestAsksForTheVoiceWithTheKeyInAHeader() throws {
        let request = try GeminiSpeaker.interactionsRequest("Hello", voice: "Puck", apiKey: "secret-key")
        #expect(request.url == GeminiSpeaker.interactionsEndpoint)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "secret-key")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "gemini-3.8-flash-tts")
        let speech = (body["generation_config"] as? [String: Any])?["speech_config"] as? [[String: Any]]
        #expect(speech?.first?["voice"] as? String == "Puck")
    }

    @Test func itSpeaksTellingTheLengthFirst() async throws {
        let wav = GeminiSpeaker.wav(from: oneSecondPCM, mimeType: nil)
        let player = FakePlayer()
        let speaker = GeminiSpeaker(send: { ok($0, #"{"steps":[{"type":"model_output","content":[{"type":"audio","data":"\#(wav.base64EncodedString())"}]}]}"#) },
                                    player: player)
        let told = Lines()
        try await speaker.speak("Hello", voice: "Kore", apiKey: "k") { told.add("\($0)") }
        #expect(told.all == ["1.0"])
        #expect(player.played == [wav])
    }

    @Test func a404TriesTheEarlierModel() async throws {
        let asked = Lines()
        let speaker = GeminiSpeaker(send: { request in
            asked.add(request.url?.lastPathComponent ?? "")
            if request.url == GeminiSpeaker.interactionsEndpoint {
                return (Data(#"{"error":{"message":"not found"}}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            return ok(request, #"{"candidates":[{"content":{"parts":[{"inlineData":{"data":"\#(oneSecondPCM.base64EncodedString())"}}]}}]}"#)
        }, player: FakePlayer())
        let wav = try await speaker.synthesize("Hello", voice: "Kore", apiKey: "k")
        #expect(asked.all == ["interactions", "gemini-2.5-flash-preview-tts:generateContent"])
        #expect(GeminiSpeaker.duration(ofWAV: wav) == 1)
    }

    @Test func a429TriesLiteModelThenLegacyModel() async throws {
        let models = Lines()
        let speaker = GeminiSpeaker(send: { request in
            if request.url == GeminiSpeaker.interactionsEndpoint,
               let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let m = json["model"] as? String {
                models.add(m)
                if m == GeminiSpeaker.model {
                    return (Data(#"{"error":{"message":"rate limit exceeded"}}"#.utf8),
                            HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!)
                }
            }
            return ok(request, #"{"steps":[{"type":"model_output","content":[{"type":"audio","data":"\#(GeminiSpeaker.wav(from: oneSecondPCM, mimeType: nil).base64EncodedString())"}]}]}"#)
        }, player: FakePlayer())
        let wav = try await speaker.synthesize("Hello", voice: "Kore", apiKey: "k")
        #expect(models.all == [GeminiSpeaker.model, GeminiSpeaker.fallbackModel])
        #expect(GeminiSpeaker.duration(ofWAV: wav) == 1)
    }

    /// The Interactions API wraps its error in a list (as it answered a
    /// bad key, live): Google's words still come through.
    @Test func anInteractionsErrorSaysGooglesMessage() async {
        let body = #"[{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}]"#
        let speaker = GeminiSpeaker(send: { request in
            (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        }, player: FakePlayer())
        do {
            _ = try await speaker.synthesize("Hello", voice: "Kore", apiKey: "k")
            Issue.record("a 400 must throw")
        } catch {
            #expect(error.localizedDescription == "Gemini answered 400: API key not valid. Please pass a valid API key.")
        }
    }

    @Test func aSlowAnswerTimesOut() async {
        let speaker = GeminiSpeaker(send: { request in
            try await Task.sleep(for: .seconds(30))
            return ok(request, "{}")
        }, player: FakePlayer(), timeout: 0.2)
        await #expect(throws: GeminiSpeechError.timedOut) {
            try await speaker.speak("Hello", voice: "Kore", apiKey: "k") { _ in }
        }
    }

    @Test func replayingTheSameTextAndVoicePlaysCachedAudioWithoutCallingGeminiAgain() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = GeminiAudioCache(directory: dir)
        let wav = GeminiSpeaker.wav(from: oneSecondPCM, mimeType: nil)
        let calls = Lines()
        let player = FakePlayer()
        let speaker = GeminiSpeaker(
            send: { request in
                calls.add(request.url?.lastPathComponent ?? "")
                return ok(request, #"{"steps":[{"type":"model_output","content":[{"type":"audio","data":"\#(wav.base64EncodedString())"}]}]}"#)
            },
            player: player,
            cache: cache
        )
        try await speaker.speak("Hello world", voice: "Kore", apiKey: "k") { _ in }
        #expect(calls.all.count == 1)
        #expect(player.played == [wav])

        try await speaker.speak("Hello world", voice: "Kore", apiKey: "k") { _ in }
        #expect(calls.all.count == 1, "replay hits on-disk cache with 0 extra network requests")
        #expect(player.played == [wav, wav])
    }

    @Test func differentVoicesDoNotShareCachedAudio() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = GeminiAudioCache(directory: dir)
        let wavKore = GeminiSpeaker.wavHeader(pcmBytes: 2, sampleRate: 24000) + Data([1, 2])
        let wavPuck = GeminiSpeaker.wavHeader(pcmBytes: 2, sampleRate: 24000) + Data([3, 4])
        let calls = Lines()
        let player = FakePlayer()
        let speaker = GeminiSpeaker(
            send: { request in
                calls.add("call")
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                let chosen = body.contains("Puck") ? wavPuck : wavKore
                return ok(request, #"{"steps":[{"type":"model_output","content":[{"type":"audio","data":"\#(chosen.base64EncodedString())"}]}]}"#)
            },
            player: player,
            cache: cache
        )
        try await speaker.speak("Hello world", voice: "Kore", apiKey: "k") { _ in }
        try await speaker.speak("Hello world", voice: "Puck", apiKey: "k") { _ in }
        #expect(calls.all.count == 2)
        #expect(player.played == [wavKore, wavPuck])
    }

    @Test func audioCachePrunesLeastRecentlyUsedFilesBeyondLimit() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = GeminiAudioCache(directory: dir, limit: 3)
        let wav = GeminiSpeaker.wav(from: oneSecondPCM, mimeType: nil)

        cache.write(wav, text: "first", voice: "Kore")
        try await Task.sleep(for: .milliseconds(15))
        cache.write(wav, text: "second", voice: "Kore")
        try await Task.sleep(for: .milliseconds(15))
        cache.write(wav, text: "third", voice: "Kore")
        try await Task.sleep(for: .milliseconds(15))

        // Reading "first" refreshes its modification date so "second" becomes oldest.
        #expect(cache.read(text: "first", voice: "Kore") == wav)
        try await Task.sleep(for: .milliseconds(15))

        cache.write(wav, text: "fourth", voice: "Kore")

        #expect(cache.read(text: "second", voice: "Kore") == nil, "oldest untouched entry is evicted")
        #expect(cache.read(text: "first", voice: "Kore") == wav)
        #expect(cache.read(text: "third", voice: "Kore") == wav)
        #expect(cache.read(text: "fourth", voice: "Kore") == wav)
    }
}

// MARK: - The announcer with both

private final class FakeGemini: GeminiSpeaking, @unchecked Sendable {
    let log: EventLog
    var error: Error?
    var seconds: Double = 2
    private(set) var asked: [(text: String, voice: String, key: String)] = []
    init(log: EventLog) { self.log = log }
    func speak(_ text: String, voice: String, apiKey: String, started: @escaping @Sendable (Double) async -> Void) async throws {
        asked.append((text, voice, apiKey))
        log.add("gemini:start")
        if let error { log.add("gemini:failed"); throw error }
        await started(seconds)
        log.add("gemini:done")
    }
}

/// Records each extend's length, so the hold can be checked.
private struct HoldMedia: MediaPausing {
    let log: EventLog
    func pause(seconds: Double) async { log.add("pause(\(seconds))") }
    func extend(seconds: Double) async { log.add("extend(\(seconds))") }
    func resumeNow() async { log.add("resume") }
}

private struct FixedStylist: AnnouncementStyling {
    let log: EventLog
    func style(_ text: String, config: SpeakerConfig) async -> String {
        log.add("styled")
        return "Reworded."
    }
}

private let lake = SpeakerDevice(id: "device@lake", type: "GoogleDisplayDevice", name: "Lake Office", room: "Lake Office")

private func macConfig(engine: LocalVoiceEngine = .gemini, home: Bool = false, pause: Bool = false) -> SpeakerConfig {
    var c = SpeakerConfig(enabled: true, defaultTarget: "lake", structureId: "structure@s", targets: ["lake": lake])
    c.speakHome = home
    c.speakLocal = true
    c.pauseMedia = pause
    c.localEngine = engine
    c.geminiVoice = "Charon"
    return c
}

@Suite struct GeminiAnnouncerTests {
    private struct Rig {
        let log = EventLog()
        let home: FakeHome
        let local: FakeLocal
        let gemini: FakeGemini
        let announcer: Announcer
        let notes = Lines()

        init(key: String? = "gem-key") {
            home = FakeHome(log: log)
            local = FakeLocal(log: log)
            gemini = FakeGemini(log: log)
            let notes = self.notes
            announcer = Announcer(home: home, local: local, media: HoldMedia(log: log), gemini: gemini,
                                  stylist: FixedStylist(log: log), geminiKey: { key }, log: { notes.add($0) })
        }
    }

    @Test func geminiSpeaksWhenChosenWithAKey() async {
        let rig = Rig()
        let outcome = await rig.announcer.announce("Hello there.", config: macConfig(), force: true)
        #expect(outcome == .announced(home: .off, local: .spoken))
        #expect(rig.gemini.asked.first?.voice == "Charon")
        #expect(rig.gemini.asked.first?.key == "gem-key")
        #expect(rig.local.texts.isEmpty, "the Mac voice is not used")
    }

    @Test func noKeyMeansTheMacVoice() async {
        let rig = Rig(key: "  ")
        let outcome = await rig.announcer.announce("Hello there.", config: macConfig(), force: true)
        #expect(outcome == .announced(home: .off, local: .spoken))
        #expect(rig.gemini.asked.isEmpty)
        #expect(rig.local.texts == ["Hello there."])
        #expect(rig.notes.all.contains { $0.contains("no Gemini API key") })
    }

    @Test func geminiFailingFallsBackToTheMacVoice() async throws {
        let rig = Rig()
        rig.gemini.error = Boom()
        let outcome = await rig.announcer.announce("Hello there.", config: macConfig(), force: true)
        #expect(outcome == .announced(home: .off, local: .spoken))
        let failed = try #require(rig.log.events.firstIndex(of: "gemini:failed"))
        let local = try #require(rig.log.events.firstIndex(of: "local:start"))
        #expect(failed < local)
        #expect(rig.local.voices == [SpeakerConfig.defaultLocalVoice])
        #expect(rig.notes.all.contains { $0.contains("Gemini voice failed (boom)") })
    }

    @Test func theMacVoiceEngineNeverAsksGemini() async {
        let rig = Rig()
        _ = await rig.announcer.announce("Hello there.", config: macConfig(engine: .apple), force: true)
        #expect(rig.gemini.asked.isEmpty)
        #expect(rig.local.texts == ["Hello there."])
    }

    /// The hold covers the audio Gemini sent, from when it starts playing.
    @Test func thePauseIsHeldForGeminisAudio() async {
        let rig = Rig()
        rig.gemini.seconds = 7
        var c = macConfig(pause: true)
        c.effectivePauseMediaExtraSeconds = 2
        _ = await rig.announcer.announce("Hello there.", config: c, force: true)
        #expect(rig.log.has("extend(9.0)"), "the audio's 7 s plus 2 s: \(rig.log.events)")
        #expect(rig.log.events.last == "extend(2.0)", "and the extra once it has finished")
    }

    @Test func onlyAnAgentsReplyIsReworded() async {
        let rig = Rig()
        var c = macConfig(engine: .apple, home: true)
        c.effectiveAnnouncementStyle = .plain
        _ = await rig.announcer.announce("A chat message.", config: c, force: false)
        #expect(!rig.log.has("styled"))
        #expect(rig.local.texts == ["A chat message."])

        let (outcome, spoken) = await rig.announcer.announceReporting("A long reply.", config: c, force: false, restyle: true)
        #expect(outcome.anySpoke)
        #expect(spoken == "Reworded.")
        #expect(rig.local.texts.last == "Reworded.")
    }

    @Test func asWrittenIsNotRewordedEvenForAnAgent() async {
        let rig = Rig()
        let (_, spoken) = await rig.announcer.announceReporting("Plain words.", config: macConfig(engine: .apple), force: true, restyle: true)
        #expect(!rig.log.has("styled"))
        #expect(spoken == "Plain words.")
    }

    @Test func theTimeLimitCoversTheRewordingAndGemini() {
        var c = macConfig(engine: .apple)
        let base = HomeSpeakerCommandLine.announceTimeout("Hello there.", config: c, restyle: true)
        c.effectiveAnnouncementStyle = .plain
        #expect(HomeSpeakerCommandLine.announceTimeout("Hello there.", config: c, restyle: true) == base + AnnouncementStylist.worstCaseSeconds)
        #expect(HomeSpeakerCommandLine.announceTimeout("Hello there.", config: c) == base, "--say is never reworded")
        c.effectiveLocalEngine = .gemini
        #expect(HomeSpeakerCommandLine.announceTimeout("Hello there.", config: c) > base + GeminiSpeaker.synthesisTimeout)
    }
}

// MARK: - The Stop hook

@Suite struct StyledStopHookTests {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    @MainActor
    private func hook(style: AnnouncementStyle, local: Bool) async throws -> (detached: [String], home: [String], reply: String) {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reply = "## Done\\nThe build is green \(UUID().uuidString). Next, ship it. More words follow here."
        let transcript = [
            #"{"message":{"role":"user","content":"is it done?"}}"#,
            #"{"message":{"role":"assistant","content":[{"type":"text","text":"\#(reply)"}]}}"#,
        ].joined(separator: "\n")
        let url = dir.appendingPathComponent("t.jsonl")
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        let input = try JSONSerialization.data(withJSONObject: ["transcript_path": url.path])
        let manager = ConfigManager(configPath: dir.appendingPathComponent("c.json"),
                                    historyPath: dir.appendingPathComponent("h.json"),
                                    secrets: SecretStore(fileURL: dir.appendingPathComponent("s.json")))
        manager.config.enabled = true
        manager.config.effectiveSpeakHome = true
        manager.config.effectiveSpeakLocal = local
        manager.config.structureId = "s1"
        manager.config.targets = ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen speaker")]
        manager.config.defaultTarget = "kitchen"
        manager.config.effectiveAnnouncementStyle = style
        let detached = Calls(), home = Calls()
        await ClaudeStopHook.run(input: input, configManager: manager,
                                 history: BroadcastHistory(fileURL: dir.appendingPathComponent("hist.json")),
                                 lockDirectory: dir, launchDetached: { detached.add($0) }) { text, _, _, _ in
            home.add(text)
            return true
        }
        return (detached.all, home.all, reply.replacingOccurrences(of: "\\n", with: "\n"))
    }

    /// Rewording can outlast the hook: it goes to `--announce`, as the
    /// whole reply, even with only the home speakers on.
    @Test func aStyledReplyGoesDetachedAndWhole() async throws {
        let r = try await hook(style: .plain, local: false)
        #expect(r.home.isEmpty)
        #expect(r.detached == [r.reply])
    }

    @Test func asWrittenHomeOnlyStillBroadcastsFromTheHook() async throws {
        let r = try await hook(style: .verbatim, local: false)
        #expect(r.detached.isEmpty)
        #expect(r.home == [GoogleHomeClient.cleanForSpeech(r.reply, length: .summary)])
    }

    @Test func asWrittenWithThisMacHandsOverTheCleanedText() async throws {
        let r = try await hook(style: .verbatim, local: true)
        #expect(r.detached == [GoogleHomeClient.cleanForSpeech(r.reply, length: .summary)])
    }
}
