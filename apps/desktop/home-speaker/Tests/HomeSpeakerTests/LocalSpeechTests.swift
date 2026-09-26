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

// Speaking on this Mac (docs/local-speech.md). Nothing here makes a sound:
// the home speakers, this Mac's voice and the media pause are all fakes.

// MARK: - Fakes

/// Records what happened, in order, across all the fakes of one test.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [String] = []
    var events: [String] { lock.withLock { _events } }
    func add(_ e: String) { lock.withLock { _events.append(e) } }
    func has(_ e: String) -> Bool { events.contains(e) }
}

final class FakeHome: HomeBroadcasting, @unchecked Sendable {
    let log: EventLog
    var error: Error?
    /// When set, the broadcast waits (up to 2 s) until this Mac has started
    /// speaking -- which only happens if both were started together.
    var waitForLocal = false
    private let lock = NSLock()
    private var _configs: [SpeakerConfig?] = []
    var configs: [SpeakerConfig?] { lock.withLock { _configs } }
    private(set) var sawLocalStart = false

    init(log: EventLog) { self.log = log }

    func broadcast(
        text: String, target: SpeakerDevice, structureId: String,
        config: SpeakerConfig?, force: Bool, at date: Date
    ) async throws -> Bool {
        lock.withLock { _configs.append(config) }
        log.add("home:start")
        if waitForLocal {
            for _ in 0..<200 where !log.has("local:start") { try? await Task.sleep(for: .milliseconds(10)) }
            sawLocalStart = log.has("local:start")
        }
        if let error { log.add("home:failed"); throw error }
        log.add("home:done")
        return true
    }
}

final class FakeLocal: LocalSpeaking, @unchecked Sendable {
    let log: EventLog
    var error: Error?
    private(set) var voices: [String] = []
    private(set) var texts: [String] = []

    init(log: EventLog) { self.log = log }

    func speak(_ text: String, voiceID: String) async throws {
        voices.append(voiceID)
        texts.append(text)
        log.add("local:start")
        try? await Task.sleep(for: .milliseconds(30))
        if let error { log.add("local:failed"); throw error }
        log.add("local:done")
    }
}

struct FakeMedia: MediaPausing {
    let log: EventLog
    func pause(seconds: Double) async { log.add("pause") }
    func extend(seconds: Double) async { log.add("extend(\(seconds))") }
    func resumeNow() async { log.add("resume") }
}

struct Boom: LocalizedError { var errorDescription: String? { "boom" } }

private let lake = SpeakerDevice(id: "device@lake", type: "GoogleDisplayDevice", name: "Lake Office", room: "Lake Office")

private func config(home: Bool? = nil, local: Bool? = nil, pause: Bool = false) -> SpeakerConfig {
    var c = SpeakerConfig(enabled: true, defaultTarget: "lake", structureId: "structure@s", targets: ["lake": lake])
    c.speakHome = home
    c.speakLocal = local
    c.pauseMedia = pause
    return c
}

private struct Rig {
    let log = EventLog()
    let home: FakeHome
    let local: FakeLocal
    let announcer: Announcer

    init() {
        home = FakeHome(log: log)
        local = FakeLocal(log: log)
        announcer = Announcer(home: home, local: local, media: FakeMedia(log: log))
    }
}

// MARK: - Config: defaults and backward compatibility

@Suite struct LocalSpeechConfigTests {
    @Test func anOldConfigDecodesToHomeOnly() throws {
        // Written before these keys existed: must behave exactly as before.
        let json = #"{"enabled":true,"default_target":"lake","structure_id":"s","targets":{}}"#
        let c = try JSONDecoder().decode(SpeakerConfig.self, from: Data(json.utf8))
        #expect(c.speakHome == nil && c.speakLocal == nil && c.localVoice == nil)
        #expect(c.effectiveSpeakHome == true)
        #expect(c.effectiveSpeakLocal == false)
        #expect(c.effectiveLocalVoice == "com.apple.ttsbundle.siri_Aaron_en-US_premium")
    }

    @Test func anOldConfigRoundTripsWithoutGainingKeys() throws {
        let json = #"{"enabled":true,"default_target":"lake","structure_id":"s","targets":{}}"#
        let c = try JSONDecoder().decode(SpeakerConfig.self, from: Data(json.utf8))
        let out = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
        #expect(!out.contains("speak_home") && !out.contains("speak_local") && !out.contains("local_voice"),
                "saving an old config must not switch anything on by writing defaults")
    }

    @Test func theNewKeysRoundTripInSnakeCase() throws {
        var c = config(home: false, local: true)
        c.localVoice = "com.apple.voice.premium.en-US.Zoe"
        let data = try JSONEncoder().encode(c)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["speak_home"] as? Bool == false)
        #expect(obj["speak_local"] as? Bool == true)
        #expect(obj["local_voice"] as? String == "com.apple.voice.premium.en-US.Zoe")
        #expect(try JSONDecoder().decode(SpeakerConfig.self, from: data) == c)
    }

    @Test func anEmptyVoiceMeansTheDefault() {
        var c = config()
        c.localVoice = "  "
        #expect(c.effectiveLocalVoice == SpeakerConfig.defaultLocalVoice)
    }

    @Test func theMenuBarNamesTheActiveOutputs() {
        #expect(config().activeOutputsLabel == "Lake Office")
        #expect(config(local: true).activeOutputsLabel == "Lake Office + This Mac")
        #expect(config(home: false, local: true).activeOutputsLabel == "This Mac")
        #expect(config(home: false, local: false).activeOutputsLabel == "")
    }
}

// MARK: - The rules, in order

@Suite struct AnnouncerRuleTests {
    @Test func switchedOffSpeaksNowhere() async {
        let rig = Rig()
        var c = config(local: true)
        c.enabled = false
        #expect(await rig.announcer.announce("hello", config: c, force: true) == .disabled)
        #expect(rig.log.events.isEmpty)
    }

    @Test func quietHoursHoldBothOutputs() async {
        let rig = Rig()
        var c = config(local: true, pause: true)
        c.quietHoursEnabled = true
        c.quietHoursStart = "00:00"
        c.quietHoursEnd = "23:59"
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        #expect(await rig.announcer.announce("hello", config: c, force: false, at: noon) == .quietHours(until: "23:59"))
        #expect(rig.log.events.isEmpty, "neither output, and no media paused")
        // A deliberate announcement still overrides quiet hours, as before.
        #expect(await rig.announcer.announce("hello", config: c, force: true, at: noon).anySpoke)
    }

    @Test func neitherOutputSpeaksNowhere() async {
        let rig = Rig()
        #expect(await rig.announcer.announce("hello", config: config(home: false, local: false), force: true) == .noOutputs)
        #expect(rig.log.events.isEmpty)
        #expect(AnnounceOutcome.noOutputsMessage == "No outputs selected (home speakers and this Mac are both off)")
    }

    @Test func homeOnlyIsTheOldPathUntouched() async {
        let rig = Rig()
        let c = config(pause: true)
        #expect(await rig.announcer.announce("hello", config: c, force: false) == .announced(home: .spoken, local: .off))
        #expect(rig.local.texts.isEmpty)
        #expect(!rig.log.has("pause"), "home only: GoogleHomeClient pauses media itself, as it always did")
        #expect(rig.home.configs.first??.pauseMedia == true, "the config reaches broadcast unchanged")
    }

    @Test func localOnlyNeverTouchesGoogle() async {
        let rig = Rig()
        var c = config(home: false, local: true)
        c.targets = [:]   // no Google setup at all
        #expect(await rig.announcer.announce("hello", config: c, force: false) == .announced(home: .off, local: .spoken))
        #expect(rig.home.configs.isEmpty)
        #expect(rig.local.voices == [SpeakerConfig.defaultLocalVoice])
    }

    @Test func bothSpeakStartedTogether() async {
        let rig = Rig()
        rig.home.waitForLocal = true
        let outcome = await rig.announcer.announce("hello", config: config(local: true), force: false)
        #expect(outcome == .announced(home: .spoken, local: .spoken))
        #expect(rig.home.sawLocalStart, "the Mac started while the home broadcast was still in flight")
        #expect(outcome.spokenLabel(homeName: "Lake Office") == "Lake Office + This Mac")
    }

    @Test func aHomeFailureDoesNotStopTheMac() async {
        let rig = Rig()
        rig.home.error = BroadcastError.http(500)
        let outcome = await rig.announcer.announce("hello", config: config(local: true), force: false)
        #expect(outcome == .announced(home: .failed("Google Home returned HTTP 500."), local: .spoken))
        #expect(outcome.anySpoke)
        #expect(outcome.failureMessages == ["Home speakers: Google Home returned HTTP 500."])
    }

    @Test func aMacFailureDoesNotStopTheHome() async {
        let rig = Rig()
        rig.local.error = Boom()
        let outcome = await rig.announcer.announce("hello", config: config(local: true), force: false)
        #expect(outcome == .announced(home: .spoken, local: .failed("boom")))
        #expect(outcome.failureMessages == ["This Mac: boom"])
    }

    @Test func noSpeakerPickedStillLetsTheMacSpeak() async {
        let rig = Rig()
        var c = config(local: true)
        c.defaultTarget = ""
        let outcome = await rig.announcer.announce("hello", config: c, force: false)
        #expect(outcome == .announced(home: .failed("No speaker selected."), local: .spoken))
    }

    @Test func bothOutputsGetTheSameCleanedText() async {
        let rig = Rig()
        var c = config(local: true)
        c.speechLength = .headline
        _ = await rig.announcer.announce("**Done.** See `x`. Third. Fourth.", config: c, force: false)
        #expect(rig.local.texts == [GoogleHomeClient.cleanForSpeech("**Done.** See `x`. Third. Fourth.", length: .headline)])
    }

    @Test func textThatCleansToNothingSpeaksNowhere() async {
        let rig = Rig()
        #expect(await rig.announcer.announce("```\ncode\n```", config: config(local: true), force: false) == .nothingToSay)
        #expect(rig.log.events.isEmpty)
    }
}

// MARK: - Pause media once

@Suite struct AnnouncerMediaPauseTests {
    @Test func bothOutputsPauseOnceAndHoldPastTheMac() async {
        let rig = Rig()
        _ = await rig.announcer.announce("hello there", config: config(local: true, pause: true), force: false)
        let pauses = rig.log.events.filter { $0 == "pause" }
        #expect(pauses.count == 1, "one pause for both outputs")
        #expect(rig.log.events.first == "pause", "paused before either output starts")
        #expect(rig.home.configs.allSatisfy { $0?.pauseMedia == false }, "the home broadcast must not pause again")
        #expect(rig.log.events.last == "extend(1.0)", "held until the Mac has finished, plus the extra second")
        #expect(!rig.log.has("resume"))
    }

    @Test func everythingFailingResumesAtOnce() async {
        let rig = Rig()
        rig.home.error = Boom()
        rig.local.error = Boom()
        _ = await rig.announcer.announce("hello", config: config(local: true, pause: true), force: false)
        #expect(rig.log.events.filter { $0 == "pause" }.count == 1)
        #expect(rig.log.events.last == "resume")
    }

    @Test func pauseOffTouchesNoMedia() async {
        let rig = Rig()
        _ = await rig.announcer.announce("hello", config: config(local: true, pause: false), force: false)
        #expect(!rig.log.events.contains { $0 == "pause" || $0 == "resume" || $0.hasPrefix("extend") })
    }
}

// MARK: - Voice choice

@Suite struct LocalVoiceChoiceTests {
    static let voices = [
        LocalVoice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .standard),
        LocalVoice(id: "com.apple.voice.enhanced.en-US.Evan", name: "Evan", language: "en-US", quality: .enhanced),
        LocalVoice(id: "com.apple.voice.premium.en-GB.Jamie", name: "Jamie", language: "en-GB", quality: .premium),
        LocalVoice(id: "com.apple.voice.premium.en-US.Zoe", name: "Zoe", language: "en-US", quality: .premium),
        LocalVoice(id: "com.apple.voice.premium.en-US.Ava", name: "Ava", language: "en-US", quality: .premium),
        LocalVoice(id: "com.apple.voice.compact.fr-FR.Thomas", name: "Thomas", language: "fr-FR", quality: .standard),
    ]

    @Test func anInstalledVoiceIsUsedAsAsked() {
        let choice = LocalSpeaker.chooseVoice(requested: "com.apple.voice.enhanced.en-US.Evan", from: Self.voices)
        #expect(choice.voice?.name == "Evan")
    }

    @Test func aMissingVoiceFallsBackToTheBestUSEnglishVoice() {
        let choice = LocalSpeaker.chooseVoice(requested: SpeakerConfig.defaultLocalVoice, from: Self.voices)
        // Premium beats enhanced; en-GB Jamie is premium but not en-US; ties by name.
        #expect(choice.voice?.name == "Ava")
        #expect(choice.note.contains("not installed") && choice.note.contains("Ava"), "the choice is logged")
    }

    @Test func noUSVoiceFallsBackToAnyEnglishThenTheSystemVoice() {
        let gb = Self.voices.filter { $0.language != "en-US" }
        #expect(LocalSpeaker.chooseVoice(requested: "x", from: gb).voice?.name == "Jamie")
        let none = LocalSpeaker.chooseVoice(requested: "x", from: Self.voices.filter { $0.language == "fr-FR" })
        #expect(none.voice == nil, "nil means the system voice -- never silence")
    }

    @Test func thePickerListsEnglishVoicesBestFirst() {
        let speaker = LocalSpeaker(synthesizer: FakeSynth(voices: Self.voices), log: { _ in })
        #expect(speaker.englishVoices().map(\.name) == ["Ava", "Jamie", "Zoe", "Evan", "Samantha"])
        #expect(speaker.englishVoices().first?.pickerLabel == "Ava (en-US) · Premium")
    }

    @Test func speakUsesTheChosenVoiceAndLogsIt() async throws {
        let synth = FakeSynth(voices: Self.voices)
        let notes = EventLog()
        let speaker = LocalSpeaker(synthesizer: synth, log: { notes.add($0) })
        try await speaker.speak("hi", voiceID: "com.apple.siri.natural.Aaron")
        #expect(synth.spokeWith == ["com.apple.voice.premium.en-US.Ava"])
        #expect(notes.events.count == 1)
    }
}

final class FakeSynth: SpeechSynthesizing, @unchecked Sendable {
    let voices: [LocalVoice]
    private(set) var spokeWith: [String?] = []
    init(voices: [LocalVoice]) { self.voices = voices }
    func installedVoices() -> [LocalVoice] { voices }
    func speak(_ text: String, voiceID: String?) async throws { spokeWith.append(voiceID) }
}

// MARK: - Extending a pause

@MainActor
@Suite(.serialized) struct MediaPauseExtendTests {
    @Test func extendNeverPausesAnythingNew() async {
        let runner = FakeRunner()
        runner.spotify = .success("1")
        let coordinator = MediaPauseCoordinator(
            controller: MediaController(runner: runner), audio: { ["com.spotify.client"] }, safariRunning: { false })
        coordinator.extend(for: 5)
        #expect(!coordinator.isHolding)
        #expect(runner.ran.isEmpty, "nothing was paused, so nothing is touched")
    }

    // Found on the Mac: every remaining voice was "Default" quality, so the
    // alphabetical tie-break chose Albert, a novelty voice. Never again.
    @Test func fallbackNeverPicksANoveltyVoice() {
        let voices = [
            LocalVoice(id: "com.apple.speech.synthesis.voice.Albert", name: "Albert", language: "en-US", quality: .standard),
            LocalVoice(id: "com.apple.eloquence.en-US.Eddy", name: "Eddy", language: "en-US", quality: .standard),
            LocalVoice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .standard),
        ]
        let choice = LocalSpeaker.chooseVoice(requested: "com.apple.siri.natural.Aaron", from: voices)
        #expect(choice.voice?.name == "Samantha")
    }
}
