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

import XCTest

import HomeSpeakerCore
import HomeSpeakerToolCore

// The extension's jobs on its own engine, in the tool's own process
// (`EngineDriver`). Each job must answer the `JobResult` that
// `ProcessDriver.result` gives for what HomeSpeaker's program printed for
// the same flag, so the tool's state machine needs no change.
//
// Every engine here is on an extension profile in a scratch folder, under a
// message prefix of its own (`test.<uuid>.homespeaker`). Google's sign-out
// is answered by a stand-in in this process; the home speaker, this Mac's
// speech, media, the volume and the homes are stand-ins too. Nothing here
// reaches this Mac's HomeSpeaker, its files, Google, a speaker or a browser.

// MARK: - Scratch files

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-engine-driver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A message prefix no real app or extension on this Mac listens on.
private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

/// The extension's files, all inside `root`; stops the test before anything
/// is read or written when one is not.
private func extensionProfile(in root: URL) throws -> HomeSpeakerProfile {
    let profile = HomeSpeakerProfile.extension(
        dataFolder: root.appendingPathComponent("data"), toolFolder: nil, messagePrefix: testPrefix())
    for url in [profile.settingsURL, profile.historyURL, profile.secretsURL] {
        XCTAssertTrue(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        guard url.path.hasPrefix(root.path + "/") else { throw StandInFailure("outside the scratch folder") }
    }
    try FileManager.default.createDirectory(
        at: profile.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    return profile
}

private func bytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

// MARK: - Stand-ins

/// Everything one stand-in was asked, in order.
private final class Calls<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.withLock { items.append(item) } }
    var all: [T] { lock.withLock { items } }
}

/// The home speaker: records each broadcast and answers `sent`, or throws.
private final class StandInHome: HomeBroadcasting, @unchecked Sendable {
    let calls = Calls<String>()
    var failure: Error?
    func broadcast(
        text: String, target: SpeakerDevice, structureId: String,
        config: SpeakerConfig?, force: Bool, at date: Date
    ) async throws -> Bool {
        calls.add(text)
        if let failure { throw failure }
        return true
    }
}

/// This Mac's speech, silent, recorded.
private final class StandInLocal: LocalSpeaking, @unchecked Sendable {
    let calls = Calls<String>()
    func speak(_ text: String, voiceID: String) async throws { calls.add(text) }
}

/// Media that is never paused: no message leaves the test.
private struct NoMediaPause: MediaPausing {
    func pause(seconds: Double) async {}
    func extend(seconds: Double) async {}
    func resumeNow() async {}
}

/// A speaker's volume, or a failure reading it.
private final class StandInVolume: VolumeAndMuteControlling, @unchecked Sendable {
    var reading = SpeakerVolume(percent: 40, muted: false, online: true)
    var failure: Error?
    func volume(of target: SpeakerDevice, structureId: String) async throws -> SpeakerVolume {
        if let failure { throw failure }
        return reading
    }
    func setVolume(_ percent: Int, on target: SpeakerDevice, structureId: String) async throws {
        reading.percent = percent
    }
    func setMuted(_ muted: Bool, on target: SpeakerDevice, structureId: String) async throws {
        reading.muted = muted
    }
}

/// Two homes, one speaker each.
private struct TwoHomes: HomeDiscovering {
    func listHomes() async throws -> [HomeStructure] {
        [HomeStructure(id: "h1", name: "Lake House"), HomeStructure(id: "h2", name: "City Flat")]
    }
    func discoverBroadcastTargets(structureId: String) async throws -> [String: SpeakerDevice] {
        structureId == "h1"
            ? ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen", room: "Kitchen")]
            : ["office": SpeakerDevice(id: "d2", type: "DISPLAY", name: "Nest Hub", room: "Office")]
    }
}

/// A failure with the words given.
private struct StandInFailure: LocalizedError {
    let words: String
    init(_ words: String) { self.words = words }
    var errorDescription: String? { words }
}

/// Google, in this process: answers every request 200 and counts them, so
/// a sign-out's revoke never leaves the test.
private final class StandInGoogle: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [URL] = []
    static var requests: [URL] { lock.withLock { seen } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInGoogle.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url) }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Settings and logins

/// Settings: broadcasting on, the Office speaker picked in home `s1`, and
/// media never paused. Task 4's goldens use the same.
private func settings(
    enabled: Bool = true, home: Bool = true, local: Bool = false, speaker: Bool = true, quiet: Bool = false
) -> SpeakerConfig {
    var config = SpeakerConfig(
        enabled: enabled,
        defaultTarget: speaker ? "office" : "",
        structureId: speaker ? "s1" : "",
        targets: speaker ? ["office": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Office")] : [:],
        quietHoursEnabled: quiet, quietHoursStart: "22:00", quietHoursEnd: "07:00")
    config.effectiveSpeakHome = home
    config.effectiveSpeakLocal = local
    config.pauseMedia = false
    return config
}

/// Logins for both Google slots and a Slack token, unique to each call.
private func logins(account: String) -> Secrets {
    let id = UUID().uuidString
    func login(_ slot: String) -> GoogleCredentials {
        GoogleCredentials(
            clientId: "shipped-client.apps.googleusercontent.test", clientSecret: "GOCSPX-\(id)",
            accessToken: "ya29.\(slot)-\(id)", refreshToken: "1//\(slot)-\(id)",
            expiry: Date(timeIntervalSince1970: 2_000_000_000), scopes: [GoogleAuth.homeScope],
            userId: account, email: "\(account)@example.test")
    }
    return Secrets(google: login("home"), googleChat: login("chat"), slackToken: "xoxp-\(id)")
}

// MARK: - What the program printed

/// What HomeSpeaker's program printed for a flag, as Task 4's goldens hold
/// it, read the way `ProcessDriver` reads the program's end.
private func asTheProgramAnswered(_ job: Job, _ printed: CLIOutput) -> JobResult {
    ProcessDriver.result(
        of: job, status: printed.exitCode,
        output: printed.stdout.map { $0 + "\n" }.joined(), error: printed.stderr.map { $0 + "\n" }.joined())
}

private let noSpeaker = "no default speaker; open HomeSpeaker and pick one"

// MARK: - The tests

@MainActor
final class EngineDriverTests: XCTestCase {
    /// One engine on a scratch extension profile, and the stand-ins its
    /// driver runs on.
    @MainActor
    private struct Rig {
        let root: URL
        let engine: HomeSpeakerEngine
        let home = StandInHome()
        let local = StandInLocal()
        let speaker = StandInVolume()
        let signedOut = Calls<Bool>()
        let signedIn = Calls<String>()
        var parts: EngineDriver.Parts
        var driver: EngineDriver { EngineDriver(engine: engine, program: Rig.program, parts: parts) }

        static let program = URL(fileURLWithPath: "/Tools/dev.vitruvian.homespeaker/bin/tool")
    }

    /// A rig whose settings are `config`, saved to the extension's file;
    /// none when nil.
    private func rig(_ config: SpeakerConfig? = settings()) throws -> Rig {
        let root = try scratchDir()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let profile = try extensionProfile(in: root)
        let engine = HomeSpeakerEngine(profile: profile, session: StandInGoogle.session, local: StandInLocal())
        var parts = EngineDriver.Parts(engine: engine, otherSecrets: { nil })
        parts.browser = { _ in XCTFail("opened this Mac's browser") }
        parts.signIn = { _, _ in throw StandInFailure("no sign-in in this test") }
        var rig = Rig(root: root, engine: engine, parts: parts)
        rig.parts.announcer = Announcer(home: rig.home, local: rig.local, media: NoMediaPause())
        rig.parts.speaker = rig.speaker
        rig.parts.homes = TwoHomes()
        let signedOut = rig.signedOut
        let signedIn = rig.signedIn
        rig.parts.signedOut = { signedOut.add($0) }
        rig.parts.signedIn = { signedIn.add("credentials changed") }
        if let config {
            engine.config.config = config
            try engine.config.trySaveConfig()
        }
        return rig
    }

    private func run(_ driver: EngineDriver, _ job: Job) async -> JobResult {
        await withCheckedContinuation { done in driver.run(job) { done.resume(returning: $0) } }
    }

    func testItIsAlwaysInstalledAndNamesTheToolsOwnProgram() throws {
        let driver = try rig().driver
        XCTAssertTrue(driver.isInstalled)
        XCTAssertEqual(driver.program, Rig.program, "the hook points at the tool's own program")
    }

    // MARK: --say

    func testSayAnswersAsTheProgramDid() async throws {
        // Task 4's --say goldens: the settings, the text, and what the
        // program printed for them, word for word.
        let failing = BroadcastError.noSpeaker
        let cases: [(name: String, config: SpeakerConfig, text: String, homeFails: Bool, printed: CLIOutput)] = [
            ("broadcasting off", settings(enabled: false), "dinner is ready", false,
             CLIOutput(stderr: ["broadcasting is switched off"], exitCode: 1)),
            ("quiet hours: it is deliberate", settings(quiet: true), "dinner is ready", false,
             CLIOutput(stdout: ["sent to Office"])),
            ("no speaker", settings(speaker: false), "dinner is ready", false,
             CLIOutput(stderr: [noSpeaker], exitCode: 1)),
            ("nothing to say", settings(), "", false,
             CLIOutput(stderr: ["nothing to say after cleaning up the text"])),
            ("no outputs", settings(home: false, local: false), "dinner is ready", false,
             CLIOutput(stdout: ["No outputs selected (home speakers and this Mac are both off)"])),
            ("spoken on the home speaker", settings(), "dinner is ready", false,
             CLIOutput(stdout: ["sent to Office"])),
            ("spoken on this Mac", settings(home: false, local: true), "dinner is ready", false,
             CLIOutput(stdout: ["spoke on this Mac"])),
            ("both, the home speaker failing", settings(home: true, local: true), "dinner is ready", true,
             CLIOutput(stdout: ["Spoke on this Mac (Home speaker failed: No speaker selected.)"],
                       stderr: ["error: Home speakers: No speaker selected."])),
        ]
        for example in cases {
            let rig = try rig(example.config)
            if example.homeFails { rig.home.failure = failing }
            let job = Job.say(example.text)
            let answer = await run(rig.driver, job)
            XCTAssertEqual(answer, asTheProgramAnswered(job, example.printed), example.name)
        }
        // The words the tool shows, for two of them.
        let spoken = try rig()
        let answer = await run(spoken.driver, .say("dinner is ready"))
        XCTAssertEqual(answer, .spoke("sent to Office"))
        XCTAssertEqual(spoken.home.calls.all, ["dinner is ready"])
        let off = try rig(settings(enabled: false))
        let refused = await run(off.driver, .say("dinner is ready"))
        XCTAssertEqual(refused, .notSpoken("broadcasting is switched off"))
    }

    func testASayIsRecordedInTheExtensionsHistory() async throws {
        let rig = try rig()
        let answer = await run(rig.driver, .say("dinner is ready"))
        XCTAssertEqual(answer, .spoke("sent to Office"))

        let saved = rig.engine.history.load()
        XCTAssertEqual(saved.map(\.text), ["dinner is ready"])
        XCTAssertEqual(saved.map(\.source), ["Say"], "recorded as --say records it")
        XCTAssertEqual(saved.map(\.targetName), ["Office"])
        let onDisk = try JSONDecoder().decode([BroadcastLogItem].self, from: try Data(contentsOf: rig.engine.profile.historyURL))
        XCTAssertEqual(onDisk.map(\.text), ["dinner is ready"], "in the extension's own history file")
    }

    // MARK: The volume

    func testVolumeAnswersAsTheProgramDid() async throws {
        let json = { (percent: Int, muted: Bool) in
            CLIOutput(stdout: [#"{"available":true,"muted":\#(muted),"online":true,"percent":\#(percent),"speaker":"Office"}"#])
        }
        let cases: [(job: Job, printed: CLIOutput, answer: Volume)] = [
            (.volume, json(40, false), Volume(speaker: "Office", percent: 40, muted: false, online: true)),
            (.setVolume(55), json(55, false), Volume(speaker: "Office", percent: 55, muted: false, online: true)),
            // The program's flag is held to 0 to 100 (`ProcessDriver.arguments`).
            (.setVolume(140), json(100, false), Volume(speaker: "Office", percent: 100, muted: false, online: true)),
            (.mute, json(40, true), Volume(speaker: "Office", percent: 40, muted: true, online: true)),
            (.unmute, json(40, false), Volume(speaker: "Office", percent: 40, muted: false, online: true)),
        ]
        for example in cases {
            let rig = try rig()
            if example.job == .unmute { rig.speaker.reading.muted = true }
            let answer = await run(rig.driver, example.job)
            XCTAssertEqual(answer, asTheProgramAnswered(example.job, example.printed), "\(example.job)")
            XCTAssertEqual(answer, .volume(example.answer), "\(example.job)")
        }

        // Task 4's goldens for a speaker that cannot answer, and for none.
        let failing = try rig()
        failing.speaker.failure = VolumeError.unsupported("Office")
        let unsupported = await run(failing.driver, .volume)
        XCTAssertEqual(unsupported, asTheProgramAnswered(.volume, CLIOutput(
            stdout: [#"{"available":false,"reason":"Office does not offer volume control through Google Home.","speaker":"Office"}"#],
            exitCode: 1)))
        XCTAssertEqual(unsupported, .unavailable("Office does not offer volume control through Google Home."))
        let none = try rig(settings(speaker: false))
        let noneAnswer = await run(none.driver, .mute)
        XCTAssertEqual(noneAnswer, asTheProgramAnswered(.mute, CLIOutput(
            stdout: [#"{"available":false,"reason":"\#(noSpeaker)"}"#], exitCode: 1)))
    }

    // MARK: Discovery

    func testDiscoverWithoutSaveListsHomes() async throws {
        let rig = try rig()
        let before = bytes(rig.engine.profile.settingsURL)
        XCTAssertNotNil(before)
        let job = Job.app(.discover(save: false, home: nil))

        let answer = await run(rig.driver, job)

        // Task 4's golden for --discover with two homes.
        XCTAssertEqual(answer, asTheProgramAnswered(job, CLIOutput(stdout: [
            "home: Lake House (h1)",
            "  kitchen\tSPEAKER\tKitchen\td1",
            "home: City Flat (h2)",
            "  office\tDISPLAY\tNest Hub · Office\td2",
        ])))
        XCTAssertEqual(answer, .homes([HomeStructure(id: "h1", name: "Lake House"), HomeStructure(id: "h2", name: "City Flat")]))
        XCTAssertEqual(bytes(rig.engine.profile.settingsURL), before, "listing the homes saved the settings")
    }

    func testDiscoverWithSaveSavesToTheExtensionsSettings() async throws {
        var current = settings()
        current.structureId = "h2"
        let rig = try rig(current)

        let answer = await run(rig.driver, .app(.discover(save: true, home: nil)))

        XCTAssertEqual(answer, .done(["home: City Flat (h2)", "  office\tDISPLAY\tNest Hub · Office\td2",
                                      "saved 1 target(s) from City Flat"]))
        // Saved into the extension's own settings, on its engine and in its
        // file: not into the app's (`ConfigManager.shared`).
        XCTAssertEqual(rig.engine.config.config.structureName, "City Flat")
        XCTAssertEqual(Set(rig.engine.config.config.targets.keys), ["office"])
        let onDisk = try JSONDecoder().decode(SpeakerConfig.self, from: try Data(contentsOf: rig.engine.profile.settingsURL))
        XCTAssertEqual(onDisk.structureId, "h2")
        XCTAssertEqual(onDisk.structureName, "City Flat")
        XCTAssertEqual(onDisk.targets["office"]?.id, "d2", "the extension's settings file holds the home's speakers")
    }

    // MARK: Signing in and out, and the login item

    func testSignOutClearsTheExtensionsSecretsOnly() async throws {
        var rig = try rig()
        let mine = logins(account: "1111")
        try rig.engine.secrets.save(mine)
        // The app's sign-ins, in the scratch folder: read, never written.
        let appSecrets = rig.root.appendingPathComponent("app/secrets.json")
        try FileManager.default.createDirectory(at: appSecrets.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SecretStore(fileURL: appSecrets).save(logins(account: "2222"))
        let appBefore = bytes(appSecrets)
        rig.parts.otherSecrets = { SecretStore(fileURL: appSecrets).load() }

        let answer = await run(rig.driver, .app(.signOut(chatOnly: false)))

        XCTAssertEqual(answer, asTheProgramAnswered(.app(.signOut(chatOnly: false)),
                                                    CLIOutput(stdout: ["signed out of Google (Home and Chat)"])))
        let left = rig.engine.secrets.load()
        XCTAssertNil(left.google, "still signed in to Home here")
        XCTAssertNil(left.googleChat, "still signed in to Chat here")
        XCTAssertEqual(left.slackToken, mine.slackToken, "signing out of Google kept Slack")
        XCTAssertEqual(bytes(appSecrets), appBefore, "the app's sign-ins changed")
        XCTAssertEqual(rig.signedOut.all, [false], "the extension's own sign-out notice")
    }

    func testTheLoginItemIsRefusedInTheExtensionsOwnWords() async throws {
        let rig = try rig()
        for action in [LoginItemAction.status, .enable, .disable] {
            let answer = await run(rig.driver, .app(.loginItem(action)))
            XCTAssertEqual(answer, .failed(HomeSpeakerCommandLine.Parts.extensionHasNoLoginItem), "\(action)")
        }
    }

    func testASignInOpensTheLinkWhenThereIsOneElseThisMacsBrowser() async throws {
        for hasLink in [true, false] {
            var rig = try rig()
            let viaLink = Calls<String>()
            let viaBrowser = Calls<String>()
            if hasLink {
                rig.parts.link = { viaLink.add($0.host ?? "") }
            } else {
                rig.parts.link = nil
            }
            rig.parts.browser = { viaBrowser.add($0.host ?? "") }
            rig.parts.signIn = { purpose, open in
                XCTAssertEqual(purpose, .chat)
                open(URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=x")!)
                return GoogleCredentials(
                    clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r",
                    scopes: ["chat.one", "chat.two"], email: "someone@example.com")
            }

            let answer = await run(rig.driver, .signIn(chatOnly: true))

            // The program printed the line it waits on, then who signed in.
            XCTAssertEqual(answer, asTheProgramAnswered(.signIn(chatOnly: true), CLIOutput(stdout: [
                "opening browser: accounts.google.com", "signed in as someone@example.com; scopes: chat.one chat.two",
            ])))
            XCTAssertEqual(viaLink.all, hasLink ? ["accounts.google.com"] : [])
            XCTAssertEqual(viaBrowser.all, hasLink ? [] : ["accounts.google.com"])
            XCTAssertEqual(rig.signedIn.all, ["credentials changed"])
        }
    }
}
