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
@testable import VitruvianSpeakerCore

// The phone's link to Vitruvian Remote is down: announcements are dropped
// for the phone, the outage is recorded once (PhoneLinkStatusFile), every
// surface says so, and a probe clears it when the phone is back.

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("vitruvian-speaker-phone-link-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private var utc: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    return cal
}

private let fixedDate = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18T...Z

private func relayAnswer(_ body: String, status: Int = 200) -> PhoneSpeaker.Send {
    { request in
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private func phoneOnly(_ on: Bool = true) -> SpeakerConfig {
    var c = SpeakerConfig(enabled: true, defaultTarget: "", structureId: "", targets: [:])
    c.speakHome = false
    c.speakLocal = false
    c.speakPhone = on
    return c
}

/// A phone whose answer can change between announcements.
private final class SwitchablePhone: PhoneSpeaking, @unchecked Sendable {
    private let lock = NSLock()
    private var _connected = false
    var connected: Bool {
        get { lock.withLock { _connected } }
        set { lock.withLock { _connected = newValue } }
    }

    func speak(_ text: String, wav: Data?, pauseMedia: Bool, headphonesOnly: Bool) async throws -> PhoneSpeakResult {
        guard connected else { throw PhoneSpeechError.notConnected }
        return .spoken
    }
}

private struct FakeProbe: PhoneLinkProbing {
    let answer: Bool?
    func isConnected() async -> Bool? { answer }
}

@Suite struct PhoneSpeakerNotConnectedTests {
    @Test(arguments: [
        #"{"ok":false,"spoken":false,"skipped":false,"reason":"no phone connected"}"#,
        #"{"ok":false,"spoken":false,"skipped":false,"reason":"phone not connected"}"#,
        #"{"ok":false,"spoken":false,"skipped":false,"reason":"  No Phone Connected \n"}"#,
    ])
    func relayReasonsMapToNotConnected(body: String) async {
        let speaker = PhoneSpeaker(endpoint: URL(string: "http://127.0.0.1:7411/v1/speaker/phone-say")!,
                                   send: relayAnswer(body))
        await #expect(throws: PhoneSpeechError.notConnected) {
            _ = try await speaker.speak("hi", wav: nil, pauseMedia: false, headphonesOnly: false)
        }
        #expect(PhoneSpeechError.notConnected.errorDescription == "not connected")
    }

    @Test func anotherReasonStaysAGenericFailure() async {
        let speaker = PhoneSpeaker(endpoint: URL(string: "http://127.0.0.1:7411/v1/speaker/phone-say")!,
                                   send: relayAnswer(#"{"ok":false,"spoken":false,"reason":"tts engine busy"}"#))
        await #expect(throws: PhoneSpeechError.failed("tts engine busy")) {
            _ = try await speaker.speak("hi", wav: nil, pauseMedia: false, headphonesOnly: false)
        }
    }
}

@Suite struct PhoneLinkStatusFileTests {
    @Test func transitionsAreReportedOnceAndConnectedWritesOnlyAfterAnOutage() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))

        // A normal announcement with no outage writes nothing.
        file.recordConnected(at: fixedDate)
        #expect(file.read() == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))

        // No file → not connected: a transition.
        #expect(file.recordNotConnected(at: fixedDate))
        #expect(file.read() == PhoneLinkStatus(connected: false, since: fixedDate))
        // Already down: not a transition, and `since` keeps the start.
        #expect(!file.recordNotConnected(at: fixedDate.addingTimeInterval(60)))
        #expect(file.read()?.since == fixedDate)

        // Back.
        file.recordConnected(at: fixedDate.addingTimeInterval(120))
        #expect(file.read() == PhoneLinkStatus(connected: true, since: fixedDate.addingTimeInterval(120)))
        // Already up: nothing changes.
        file.recordConnected(at: fixedDate.addingTimeInterval(180))
        #expect(file.read()?.since == fixedDate.addingTimeInterval(120))

        // connected → not connected is a transition again.
        #expect(file.recordNotConnected(at: fixedDate.addingTimeInterval(240)))
    }

    @Test func theFileIsSnakeCaseISO8601UTC() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent("phone_link.json"))
        let since = try #require(ISO8601DateFormatter().date(from: "2026-11-18T09:30:00Z"))
        file.recordNotConnected(at: since)
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        #expect(json["connected"] as? Bool == false)
        #expect(json["since"] as? String == "2026-11-18T09:30:00Z")
    }

    @Test func eachProfileHasItsOwnFile() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        #expect(VitruvianSpeakerProfile.app(home: home).phoneLinkStatusURL.path == "/Users/test/.gemini/speaker_phone_link.json")
        let data = URL(fileURLWithPath: "/tmp/data", isDirectory: true)
        #expect(VitruvianSpeakerProfile.extension(dataFolder: data, toolFolder: nil).phoneLinkStatusURL.path
            == "/tmp/data/phone_link.json")
    }

    @Test func anOutageShowsOnlyWhilePhoneOutputIsOn() {
        let down = PhoneLinkStatus(connected: false, since: fixedDate)
        #expect(PhoneLinkStatusFile.outageSince(down, config: phoneOnly(true)) == fixedDate)
        #expect(PhoneLinkStatusFile.outageSince(down, config: phoneOnly(false)) == nil)
        #expect(PhoneLinkStatusFile.outageSince(PhoneLinkStatus(connected: true, since: fixedDate), config: phoneOnly()) == nil)
        #expect(PhoneLinkStatusFile.outageSince(nil, config: phoneOnly()) == nil)
    }
}

@Suite struct AnnouncerPhoneOutageTests {
    @Test func theOutageIsSaidOncePerOutageAndTheAnnouncementIsDropped() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))
        let logged = EventLog()
        let phone = SwitchablePhone()
        let announcer = Announcer(
            phone: phone, media: FakeMedia(log: EventLog()), geminiKey: { nil },
            snoozeQueue: SnoozeQueue(fileURL: dir.appendingPathComponent("queue.json")),
            phoneLink: file, log: { logged.add($0) })
        let notice = PhoneLinkStatusFile.droppedNotice

        // Two announcements while the phone is away: one notice.
        for _ in 0..<2 {
            let outcome = await announcer.announce("Build finished", config: phoneOnly(), force: false, at: fixedDate)
            #expect(outcome == .announced(home: .off, local: .off, phone: .failed("not connected")))
        }
        #expect(logged.events.filter { $0 == notice }.count == 1)
        #expect(file.read()?.connected == false)
        // Dropped, not queued.
        #expect(SnoozeQueue(fileURL: dir.appendingPathComponent("queue.json")).count() == 0)

        // The phone is back: the outage clears.
        phone.connected = true
        let spoken = await announcer.announce("Tests passed", config: phoneOnly(), force: false, at: fixedDate)
        #expect(spoken == .announced(home: .off, local: .off, phone: .spoken))
        #expect(file.read()?.connected == true)

        // The next outage is said again.
        phone.connected = false
        _ = await announcer.announce("Deploy failed", config: phoneOnly(), force: false, at: fixedDate)
        #expect(logged.events.filter { $0 == notice }.count == 2)
        #expect(notice.contains(PhoneLinkStatusFile.hint))
    }

    @Test func aSkipAlsoCountsAsThePhoneBeingBack() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))
        file.recordNotConnected(at: fixedDate)
        let phone = FakePhone(log: EventLog())
        phone.result = .skipped("no headphones")
        let announcer = Announcer(phone: phone, media: FakeMedia(log: EventLog()), geminiKey: { nil }, phoneLink: file)
        _ = await announcer.announce("hi", config: phoneOnly(), force: false, at: fixedDate)
        #expect(file.read()?.connected == true)
    }
}

@Suite struct PhoneLinkProbeTests {
    @Test func theProbeAsksTheRelaysPhoneEndpoint() async {
        #expect(PhoneLinkProbe.endpoint(relativeTo: URL(string: "http://127.0.0.1:7411/v1/speaker/phone-say")!)
            == URL(string: "http://127.0.0.1:7411/v1/phone")!)
        let seen = EventLog()
        let probe = PhoneLinkProbe(endpoint: URL(string: "http://127.0.0.1:7411/v1/phone")!) { request in
            seen.add("\(request.httpMethod ?? "") \(request.url!.path) \(request.timeoutInterval)")
            return (Data(#"{"connected":true,"name":"Pixel"}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(await probe.isConnected() == true)
        #expect(seen.events == ["GET /v1/phone 2.0"])

        let down = PhoneLinkProbe(endpoint: URL(string: "http://127.0.0.1:7411/v1/phone")!,
                                  send: relayAnswer(#"{"connected":false}"#))
        #expect(await down.isConnected() == false)
        let unreachable = PhoneLinkProbe(endpoint: URL(string: "http://127.0.0.1:7411/v1/phone")!) { _ in
            throw URLError(.cannotConnectToHost)
        }
        #expect(await unreachable.isConnected() == nil)
    }

    @MainActor
    @Test func theWatcherClearsAnOutageOnlyWhenThePhoneIsSeenBack() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))
        var config = phoneOnly()
        file.recordNotConnected(at: fixedDate)

        // Relay unreachable or phone still away: left as it is.
        for answer in [Bool?.none, .some(false)] {
            let watcher = PhoneLinkWatcher(statusFile: file, probe: FakeProbe(answer: answer), config: { config })
            #expect(await !watcher.check())
            #expect(file.read()?.connected == false)
        }
        // Phone output off: not asked, not cleared.
        config.speakPhone = false
        let back = PhoneLinkWatcher(statusFile: file, probe: FakeProbe(answer: true), config: { config },
                                    now: { fixedDate.addingTimeInterval(60) })
        #expect(await !back.check())
        #expect(file.read()?.connected == false)
        // On, and the phone is back: cleared.
        config.speakPhone = true
        #expect(await back.check())
        #expect(file.read() == PhoneLinkStatus(connected: true, since: fixedDate.addingTimeInterval(60)))
        // Nothing recorded down: nothing to do.
        #expect(await !back.check())
    }

    @MainActor
    @Test func theWatcherLoopRunsOnItsInterval() async throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))
        file.recordNotConnected(at: fixedDate)
        let watcher = PhoneLinkWatcher(statusFile: file, probe: FakeProbe(answer: true), config: { phoneOnly() },
                                       interval: .milliseconds(20))
        watcher.start()
        defer { watcher.stop() }
        for _ in 0..<200 where file.read()?.connected == false { try await Task.sleep(for: .milliseconds(10)) }
        #expect(file.read()?.connected == true)
    }

    @MainActor
    @Test func theEngineRecordsAndWatchesItsOwnProfilesFile() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let profile = VitruvianSpeakerProfile.extension(
            dataFolder: dir, toolFolder: nil, messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker")
        let engine = VitruvianSpeakerEngine(profile: profile)
        #expect(engine.phoneLink.url == profile.phoneLinkStatusURL)
        #expect(engine.announcer.phoneLink?.url == profile.phoneLinkStatusURL)
        #expect(VitruvianSpeakerEngine.app.phoneLink.url == VitruvianSpeakerProfile.app().phoneLinkStatusURL)
        #expect(Announcer.shared.phoneLink?.url == VitruvianSpeakerProfile.app().phoneLinkStatusURL)
    }
}

@Suite struct PhoneLinkSurfaceTests {
    @Test func statusSaysTheOutageOnlyWhilePhoneOutputIsOn() {
        let down = PhoneLinkStatus(connected: false, since: try! #require(ISO8601DateFormatter().date(from: "2026-11-18T14:05:00Z")))
        let on = BroadcastCommand.formatStatus(config: phoneOnly(true), phoneLink: down, calendar: utc)
        #expect(on.contains("Your phone: not connected (since 14:05)"))
        #expect(on.contains(PhoneLinkStatusFile.hint))

        let off = BroadcastCommand.formatStatus(config: phoneOnly(false), phoneLink: down, calendar: utc)
        #expect(!off.contains { $0.hasPrefix(PhoneLinkStatusFile.headline) })
        #expect(!off.contains(PhoneLinkStatusFile.hint))

        let up = BroadcastCommand.formatStatus(
            config: phoneOnly(true), phoneLink: PhoneLinkStatus(connected: true, since: down.since), calendar: utc)
        #expect(!up.contains(PhoneLinkStatusFile.hint))
    }

    @MainActor
    @Test func statusReadsTheEnginesFile() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let profile = VitruvianSpeakerProfile.extension(
            dataFolder: dir.appendingPathComponent("data"), toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker")
        try SpeakerConfigFile(url: profile.settingsURL).write(phoneOnly())
        let engine = VitruvianSpeakerEngine(profile: profile)
        engine.phoneLink.recordNotConnected(at: fixedDate)
        guard case .now(let out) = BroadcastCommand.action(
            for: ["--status"], engine: engine, parts: VitruvianSpeakerCommandLine.Parts.app(),
            systemVoices: { [] }, phoneLinkProbe: FakeProbe(answer: false), calendar: utc) else {
            Issue.record("expected .now output for --status")
            return
        }
        #expect(out.stdout.contains(PhoneLinkStatusFile.headline(since: fixedDate, calendar: utc)))
        #expect(out.stdout.contains(PhoneLinkStatusFile.hint))
    }

    @Test func stateSaysPhoneConnectedTrueFalseOrNull() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let configFile = SpeakerConfigFile(url: dir.appendingPathComponent("speaker_broadcast.json"))
        let seam = VitruvianSpeakerStateContract.Seam(
            program: .app, configFile: configFile,
            secrets: SecretStore(fileURL: dir.appendingPathComponent("secrets.json")),
            history: BroadcastHistory(fileURL: dir.appendingPathComponent("speaker_history.json")),
            monitorStatusFile: ChatMonitorStatusFile(url: dir.appendingPathComponent("speaker_monitor_status.json")),
            phoneLinkProbe: FakeProbe(answer: nil),
            doorFile: DoorFile(url: dir.appendingPathComponent("speaker_door.json")),
            otherInstalled: { _ in false }, appRunning: { true }, extensionRunning: { _ in false },
            gwsInstalled: { false },
            agentHome: dir.appendingPathComponent("home"), hookExecutablePath: "/Applications/Vitruvian Speaker.app/x")
        #expect(seam.phoneLinkStatusFile.url == dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))
        func phoneConnected() -> Any? { VitruvianSpeakerStateContract.stateObject(seam: seam)["phone_connected"] }

        try configFile.write(phoneOnly(true))
        #expect(phoneConnected() is NSNull, "nothing recorded")
        seam.phoneLinkStatusFile.recordNotConnected(at: fixedDate)
        #expect(phoneConnected() as? Bool == false)
        seam.phoneLinkStatusFile.recordConnected(at: fixedDate)
        #expect(phoneConnected() as? Bool == true)
        seam.phoneLinkStatusFile.recordNotConnected(at: fixedDate)
        try configFile.write(phoneOnly(false))
        #expect(phoneConnected() is NSNull, "phone output off")
    }

    /// A probe that counts how often it was asked.
    private final class CountingProbe: PhoneLinkProbing, @unchecked Sendable {
        let answer: Bool?
        private let lock = NSLock()
        private var _asked = 0
        var asked: Int { lock.withLock { _asked } }
        init(_ answer: Bool?) { self.answer = answer }
        func isConnected() async -> Bool? {
            lock.withLock { _asked += 1 }
            return answer
        }
    }

    @Test func aShortLivedReaderLooksOnceAndClearsAnOutageThePhoneIsBackFrom() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = PhoneLinkStatusFile(url: dir.appendingPathComponent(PhoneLinkStatusFile.appFileName))

        let idle = CountingProbe(true)
        #expect(file.refreshedRead(config: phoneOnly(), probe: idle) == nil)
        file.recordConnected(at: fixedDate)
        #expect(idle.asked == 0, "no outage recorded: nothing is asked")

        file.recordNotConnected(at: fixedDate)
        let off = CountingProbe(true)
        #expect(file.refreshedRead(config: phoneOnly(false), probe: off)?.connected == false)
        #expect(off.asked == 0, "phone output off: nothing is asked")

        let stillDown = CountingProbe(false)
        #expect(file.refreshedRead(config: phoneOnly(), probe: stillDown)?.connected == false)
        let unreachable = CountingProbe(nil)
        #expect(file.refreshedRead(config: phoneOnly(), probe: unreachable)?.connected == false)
        #expect(stillDown.asked == 1 && unreachable.asked == 1)

        let back = CountingProbe(true)
        #expect(file.refreshedRead(config: phoneOnly(), probe: back)?.connected == true)
        #expect(file.read()?.connected == true, "the outage is cleared in the file too")
    }

    @MainActor
    @Test func statusDoesNotSayDownWhenThePhoneIsBack() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let profile = VitruvianSpeakerProfile.extension(
            dataFolder: dir.appendingPathComponent("data"), toolFolder: nil,
            messagePrefix: "test.\(UUID().uuidString).vitruvian-speaker")
        try SpeakerConfigFile(url: profile.settingsURL).write(phoneOnly())
        let engine = VitruvianSpeakerEngine(profile: profile)
        engine.phoneLink.recordNotConnected(at: fixedDate)
        guard case .now(let out) = BroadcastCommand.action(
            for: ["--status"], engine: engine, parts: VitruvianSpeakerCommandLine.Parts.app(),
            systemVoices: { [] }, phoneLinkProbe: FakeProbe(answer: true), calendar: utc) else {
            Issue.record("expected .now output for --status")
            return
        }
        #expect(!out.stdout.contains { $0.hasPrefix(PhoneLinkStatusFile.headline) })
        #expect(!out.stdout.contains(PhoneLinkStatusFile.hint))
        #expect(engine.phoneLink.read()?.connected == true)
    }
}
