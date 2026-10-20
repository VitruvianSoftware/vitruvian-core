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

// Guards for HomeSpeaker's command line, which now lives in Core and runs
// on any engine. What it prints and how it exits is a contract: scripts,
// the Vitruvian tool and `macagent` (which parses `--volume`'s JSON) read
// it. So each golden below is today's text, word for word.
//
// The goldens were copied from the literals in Sources/HomeSpeaker/Entry.swift
// at 3409c1b50, before the command line moved: the app's program cannot be
// linked by a test, so its lines are written out here, not recorded by
// running it. `--help` and `--version` were also checked against the built
// program's own output. Only the version is interpolated, so a release
// never breaks them.
//
// Nothing here reaches this Mac's HomeSpeaker, Google, home, speakers or
// settings: every speaker, sign-in and home is a stand-in, every file is in
// a scratch folder, and every message name is under a prefix of its own
// (`test.<uuid>.homespeaker`), recorded, never posted.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-cli-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A message prefix no real app or extension on this Mac listens on.
private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

private func scratchProfile(in root: URL) -> HomeSpeakerProfile {
    .extension(dataFolder: root.appendingPathComponent("data"), toolFolder: nil, messagePrefix: testPrefix())
}

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

/// Settings: broadcasting on, the Office speaker picked, quiet hours
/// 22:00 to 07:00 when `quiet`, and media never paused.
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

/// 23:30 today: inside quiet hours.
private let lateEvening: Date = {
    Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
}()

/// One run's stand-ins and scratch files.
private struct Rig {
    let root: URL
    let profile: HomeSpeakerProfile
    let home = StandInHome()
    let local = StandInLocal()
    let history: BroadcastHistory
    var announcer: Announcer { Announcer(home: home, local: local, media: NoMediaPause()) }

    init() throws {
        root = try scratchDir()
        profile = scratchProfile(in: root)
        history = BroadcastHistory(fileURL: root.appendingPathComponent("history.json"))
    }
}

/// Answers Google's revoke address with 200, so a sign-out never leaves
/// the process.
private final class RevokeStandIn: URLProtocol {
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RevokeStandIn.self]
        return URLSession(configuration: configuration)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// `--sign-out` as the program runs it (`action`), on an engine over the
/// scratch profile, signed in for Home and Chat, with no other side. The
/// signed-out notice is recorded, never posted.
@MainActor
private func signOutThroughTheCommandLine(_ arguments: [String], posts: String) async throws -> CLIOutput {
    let rig = try Rig()
    let engine = HomeSpeakerEngine(profile: rig.profile, session: RevokeStandIn.session, local: StandInLocal())
    func login(_ refresh: String) -> GoogleCredentials {
        GoogleCredentials(clientId: "client.apps.googleusercontent.test", clientSecret: "made-up", // gitleaks:allow (made-up test token)
                          accessToken: "made-up", refreshToken: refresh) // gitleaks:allow (made-up test token)
    }
    try engine.secrets.save(Secrets(google: login("made-up-home"), googleChat: login("made-up-chat")))
    let posted = Calls<String>()
    let parts = HomeSpeakerCommandLine.Parts.app(postSignedOut: { chatOnly, name in
        posted.add("\(name.rawValue) chatOnly=\(chatOnly)")
    })
    guard case .headless(_, _, let body) = HomeSpeakerCommandLine.action(for: arguments, engine: engine, parts: parts) else {
        Issue.record("\(arguments) does not run headless")
        return CLIOutput()
    }
    let out = await body()
    #expect(posted.all == ["\(rig.profile.messagePrefix).signed-out \(posts)"])
    return out
}

// MARK: - The goldens

/// What a run printed and how it ended, as recorded from today's code.
private struct Golden {
    let name: String
    let expected: CLIOutput
    let run: @MainActor () async throws -> CLIOutput
}

private let noSpeaker = "no default speaker; open HomeSpeaker and pick one"
private let badLevel = #"{"available":false,"reason":"--set-volume needs a whole number from 0 to 100"}"#

/// `HomeSpeaker --help`, from Entry.swift's literal and `AppCommandParser.usageLines`.
private let helpText = """
HomeSpeaker \(HomeSpeakerVersion.current) — speaks your coding agent's replies on a Google speaker.

usage: HomeSpeaker [flag]
  (no flag)            run the menu bar app
  --say <text>         announce text on the default speaker and/or this Mac
  --source <name> --say <text>
                       the same, for claude-code, antigravity or opencode:
                       spoken only while that agent's switch is on (default:
                       the agent whose shell runs it, else a person)
  --volume             the default speaker's volume, as JSON
  --set-volume <0-100> set it; --mute / --unmute likewise
  --sign-in [--chat]   sign in for Home (or Google Chat)
  --sign-out [--chat]  sign out of every Google login (or only Google Chat)
  --discover [--save] [--home <id>]
                       list homes and broadcast targets; --save keeps them
                       as the speaker list (the home given, else the
                       current one, else the first)
  --login-item [status|enable|disable]
                       show or change Open at Login
  --test-media-pause   pause what this Mac plays for 3 s, then resume
  --chat-monitor start|stop
                       start or stop the chat monitor in the running app
  --claude-stop-hook   Claude Code Stop hook; reads hook JSON on stdin
  --antigravity-hook   Antigravity Stop hook; reads hook JSON on stdin
  --opencode-hook      OpenCode session.idle plugin; reads messages JSON on stdin
  --version            print the version
  --help               print this
"""

/// Runs `--say` or `--announce` `arguments` through the command line's
/// parser, then the outcome for what it parsed, on `rig`'s stand-ins.
@MainActor
private func announcement(_ arguments: [String], _ config: SpeakerConfig, _ rig: Rig, at date: Date = Date()) async throws -> CLIOutput {
    let command = try #require(HomeSpeakerCommandLine.parse(arguments))
    switch command {
    case .say(let text):
        return await HomeSpeakerCommandLine.say(
            text, config: config, announcer: rig.announcer, history: rig.history,
            standsAside: false, door: rig.profile.door, at: date)
    case .announce(let text, let agent):
        return await HomeSpeakerCommandLine.announce(
            text, for: agent, config: config, announcer: rig.announcer, history: rig.history, standsAside: false, at: date)
    default:
        Issue.record("\(arguments) parsed as \(command)")
        return CLIOutput()
    }
}

@MainActor
private func volume(_ arguments: [String], _ config: SpeakerConfig, _ speaker: StandInVolume) async throws -> CLIOutput {
    guard case .volume(let request) = try #require(HomeSpeakerCommandLine.parse(arguments)) else {
        Issue.record("\(arguments) is not a volume command")
        return CLIOutput()
    }
    return await HomeSpeakerCommandLine.volume(request, config: config, speaker: speaker)
}

private let goldens: [Golden] = [
    // --say
    Golden(name: "--say with broadcasting off",
           expected: CLIOutput(stderr: ["broadcasting is switched off"], exitCode: 1)) {
        try await announcement(["--say", "dinner is ready"], settings(enabled: false), Rig())
    },
    Golden(name: "--say in quiet hours speaks: it is deliberate",
           expected: CLIOutput(stdout: ["sent to Office"])) {
        try await announcement(["--say", "dinner is ready"], settings(quiet: true), Rig(), at: lateEvening)
    },
    Golden(name: "--announce in quiet hours (the hook's own) says nothing",
           expected: CLIOutput(stderr: ["Quiet hours active until 07:00. Nothing spoken."])) {
        try await announcement(["--announce", "the build is green"], settings(quiet: true), Rig(), at: lateEvening)
    },
    Golden(name: "--say with no speaker",
           expected: CLIOutput(stderr: [noSpeaker], exitCode: 1)) {
        try await announcement(["--say", "dinner is ready"], settings(speaker: false), Rig())
    },
    Golden(name: "--say with nothing to say",
           expected: CLIOutput(stderr: ["nothing to say after cleaning up the text"])) {
        try await announcement(["--say"], settings(), Rig())
    },
    Golden(name: "--say with no outputs",
           expected: CLIOutput(stdout: ["No outputs selected (home speakers and this Mac are both off)"])) {
        try await announcement(["--say", "dinner is ready"], settings(home: false, local: false), Rig())
    },
    Golden(name: "--say spoken on the home speaker",
           expected: CLIOutput(stdout: ["sent to Office"])) {
        let rig = try Rig()
        let out = try await announcement(["--say", "dinner", "is", "ready"], settings(), rig)
        #expect(rig.home.calls.all == ["dinner is ready"])
        let saved = rig.history.load()
        #expect(saved.map(\.targetName) == ["Office"])
        #expect(saved.map(\.source) == ["Say"])
        return out
    },
    Golden(name: "--say spoken on this Mac",
           expected: CLIOutput(stdout: ["spoke on this Mac"])) {
        let rig = try Rig()
        let out = try await announcement(["--say", "dinner is ready"], settings(home: false, local: true), rig)
        #expect(rig.local.calls.all.count == 1)
        #expect(rig.history.load().map(\.targetName) == ["This Mac"])
        return out
    },
    Golden(name: "--say on both, the home speaker failing",
           expected: CLIOutput(stdout: ["Spoke on this Mac (Home speaker failed: No speaker selected.)"],
                               stderr: ["error: Home speakers: No speaker selected."])) {
        let rig = try Rig()
        rig.home.failure = BroadcastError.noSpeaker
        return try await announcement(["--say", "dinner is ready"], settings(home: true, local: true), rig)
    },

    // --volume and friends: one JSON object, keys sorted, for macagent.
    Golden(name: "--volume with no speaker",
           expected: CLIOutput(stdout: [#"{"available":false,"reason":"\#(noSpeaker)"}"#], exitCode: 1)) {
        try await volume(["--volume"], settings(speaker: false), StandInVolume())
    },
    Golden(name: "--volume available",
           expected: CLIOutput(stdout: [#"{"available":true,"muted":false,"online":true,"percent":40,"speaker":"Office"}"#])) {
        try await volume(["--volume"], settings(), StandInVolume())
    },
    Golden(name: "--volume with an error",
           expected: CLIOutput(stdout: [#"{"available":false,"reason":"Office does not offer volume control through Google Home.","speaker":"Office"}"#], exitCode: 1)) {
        let speaker = StandInVolume()
        speaker.failure = VolumeError.unsupported("Office")
        return try await volume(["--volume"], settings(), speaker)
    },
    Golden(name: "--set-volume 101", expected: CLIOutput(stdout: [badLevel], exitCode: 1)) {
        try await volume(["--set-volume", "101"], settings(), StandInVolume())
    },
    Golden(name: "--set-volume x", expected: CLIOutput(stdout: [badLevel], exitCode: 1)) {
        try await volume(["--set-volume", "x"], settings(), StandInVolume())
    },
    Golden(name: "--set-volume 55",
           expected: CLIOutput(stdout: [#"{"available":true,"muted":false,"online":true,"percent":55,"speaker":"Office"}"#])) {
        try await volume(["--set-volume", "55"], settings(), StandInVolume())
    },

    // The app-identity commands.
    Golden(name: "--sign-out --chat", expected: CLIOutput(stdout: ["signed out of Google Chat"])) {
        try await signOutThroughTheCommandLine(["--sign-out", "--chat"], posts: "chatOnly=true")
    },
    Golden(name: "--sign-out", expected: CLIOutput(stdout: ["signed out of Google (Home and Chat)"])) {
        try await signOutThroughTheCommandLine(["--sign-out"], posts: "chatOnly=false")
    },
    Golden(name: "--discover with two homes",
           expected: CLIOutput(stdout: [
               "home: Lake House (h1)",
               "  kitchen\tSPEAKER\tKitchen\td1",
               "home: City Flat (h2)",
               "  office\tDISPLAY\tNest Hub · Office\td2",
           ])) {
        guard case .app(.success(.discover(let save, let home))) = try #require(HomeSpeakerCommandLine.parse(["--discover"])) else {
            Issue.record("--discover did not parse")
            return CLIOutput()
        }
        return await AppCommandRunner.discover(
            save: save, home: home, client: TwoHomes(), currentStructureId: "", apply: { _, _ in })
    },
    Golden(name: "a misplaced command flag",
           expected: CLIOutput(stderr: ["error: --discover must be the first argument", "run HomeSpeaker --help for usage"],
                               exitCode: 2)) {
        guard case .app(.failure(let usage)) = try #require(HomeSpeakerCommandLine.parse(["--chat", "--discover"])) else {
            Issue.record("a misplaced --discover was not a usage error")
            return CLIOutput()
        }
        return HomeSpeakerCommandLine.usageError(usage)
    },

    // --chat-monitor: the line, and the message under the profile's name.
    Golden(name: "--chat-monitor start",
           expected: CLIOutput(stdout: ["asked a running HomeSpeaker to start the chat monitor"])) {
        try chatMonitor("start")
    },
    Golden(name: "--chat-monitor stop",
           expected: CLIOutput(stdout: ["asked a running HomeSpeaker to stop the chat monitor"])) {
        try chatMonitor("stop")
    },
    Golden(name: "--chat-monitor pause",
           expected: CLIOutput(stderr: [#"error: --chat-monitor takes one of start or stop, not "pause""#,
                                        "run HomeSpeaker --help for usage"], exitCode: 2)) {
        guard case .chatMonitor(.failure(let usage)) = try #require(HomeSpeakerCommandLine.parse(["--chat-monitor", "pause"])) else {
            Issue.record("--chat-monitor pause was not a usage error")
            return CLIOutput()
        }
        return HomeSpeakerCommandLine.usageError(usage)
    },

    // --sign-in: the line printed while it waits, then who signed in.
    Golden(name: "--sign-in --chat",
           expected: CLIOutput(stdout: ["signed in as someone@example.com; scopes: chat.one chat.two"])) {
        guard case .signIn(let purpose) = try #require(HomeSpeakerCommandLine.parse(["--sign-in", "--chat"])) else {
            Issue.record("--sign-in --chat did not parse")
            return CLIOutput()
        }
        let progress = Calls<String>()
        let opened = Calls<String>()
        let notified = Calls<String>()
        let out = await HomeSpeakerCommandLine.signIn(
            purpose: purpose,
            signIn: { purpose, open in
                #expect(purpose == .chat)
                open(URL(string: "https://accounts.google.com/o/oauth2/v2/auth?client_id=x")!)
                return GoogleCredentials(
                    clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r",
                    scopes: ["chat.one", "chat.two"], email: "someone@example.com")
            },
            openBrowser: { opened.add($0.host ?? "") }, progress: { progress.add($0) },
            notify: { notified.add("credentials changed") })
        #expect(progress.all == ["opening browser: accounts.google.com"])
        #expect(opened.all == ["accounts.google.com"])
        #expect(notified.all == ["credentials changed"])
        return out
    },
    Golden(name: "--sign-in failing", expected: CLIOutput(stderr: ["error: the browser was closed"], exitCode: 1)) {
        await HomeSpeakerCommandLine.signIn(
            purpose: .home, signIn: { _, _ in throw StandInFailure("the browser was closed") },
            openBrowser: { _ in }, progress: { _ in }, notify: { Issue.record("told a running HomeSpeaker after a failure") })
    },

    Golden(name: "--help", expected: CLIOutput(stdout: [helpText])) {
        #expect(HomeSpeakerCommandLine.parse(["-h"]) == .help)
        return try outcome(of: ["--help"])
    },
    Golden(name: "--version", expected: CLIOutput(stdout: ["HomeSpeaker \(HomeSpeakerVersion.current)"])) {
        try outcome(of: ["--version"])
    },
]

/// `--chat-monitor <word>`, posted to a recorder: the line it printed,
/// after checking the message went under the profile's name.
@MainActor
private func chatMonitor(_ word: String) throws -> CLIOutput {
    let root = try scratchDir()
    let profile = scratchProfile(in: root)
    guard case .chatMonitor(.success(let action)) = try #require(HomeSpeakerCommandLine.parse(["--chat-monitor", word])) else {
        Issue.record("--chat-monitor \(word) did not parse")
        return CLIOutput()
    }
    let posted = Calls<String>()
    let out = HomeSpeakerCommandLine.chatMonitor(action, profile: profile) { action, name in
        posted.add("\(name.rawValue) \(action.rawValue)")
    }
    #expect(posted.all == ["\(profile.messagePrefix).chat-monitor-control \(word)"])
    return out
}

/// The words-only flags.
@MainActor
private func outcome(of arguments: [String]) throws -> CLIOutput {
    switch try #require(HomeSpeakerCommandLine.parse(arguments)) {
    case .help: return HomeSpeakerCommandLine.help()
    case .version: return HomeSpeakerCommandLine.version()
    case let other:
        Issue.record("\(arguments) parsed as \(other)")
        return CLIOutput()
    }
}

// MARK: - Tests

@Suite struct CommandLineTests {
    @Test @MainActor func everyGoldenStillMatches() async throws {
        for golden in goldens {
            let actual = try await golden.run()
            #expect(actual == golden.expected, "\(golden.name)")
        }
    }

    /// Exactly the arguments Entry used to act on, in Entry's order of
    /// precedence; anything else starts the menu bar app.
    @Test func itRecognizesWhatEntryDid() {
        typealias C = HomeSpeakerCommandLine.Command
        let cases: [([String], C?)] = [
            ([], nil),
            (["--chat"], nil),
            (["-psn_0_12345"], nil),
            (["--announce", "hi"], .announce("hi", .claudeCode)),
            (["--announce", "hi", "there"], nil),
            (["--announce", "--claude-stop-hook"], .announce("--claude-stop-hook", .claudeCode)),
            (["--announce", "hi", "--source", "antigravity"], .announce("hi", .antigravity)),
            (["--announce", "hi", "--source", "opencode"], .announce("hi", .opencode)),
            (["--announce", "hi", "--source", "user"], nil),
            (["--claude-stop-hook"], .stopHook(.claudeCode)),
            (["--antigravity-hook"], .stopHook(.antigravity)),
            (["--opencode-hook"], .stopHook(.opencode)),
            (["--sign-out"], .app(.success(.signOut(chatOnly: false)))),
            (["--login-item", "enable"], .app(.success(.loginItem(.enable)))),
            (["--test-media-pause"], .app(.success(.testMediaPause))),
            (["--chat-monitor", "start"], .chatMonitor(.success(.start))),
            (["--say", "--volume", "now"], .say("--volume now")),
            (["--say"], .say("")),
            (["--volume", "--mute"], .volume(.read)),
            (["--set-volume", "7"], .volume(.set(7))),
            (["--set-volume"], .volume(.invalidLevel)),
            (["--set-volume", "-1"], .volume(.invalidLevel)),
            (["--mute"], .volume(.mute)),
            (["--unmute"], .volume(.unmute)),
            (["--sign-in"], .signIn(.home)),
            (["--sign-in", "--chat"], .signIn(.chat)),
            (["--version", "--help"], .help),
            (["--version"], .version),
            (["--where"], .location),
            (["--say", "--where"], .say("--where")),
            (["--chat", "--where"], nil),
        ]
        for (arguments, expected) in cases {
            #expect(HomeSpeakerCommandLine.parse(arguments) == expected, "\(arguments)")
            #expect(HomeSpeakerCommandLine.recognizes(arguments) == (expected != nil), "\(arguments)")
        }
    }

    /// `--where`, for the conformance test: the profile's data folder, one
    /// line. Hidden: `--help` does not list it.
    @Test func whereSaysTheDataFolder() throws {
        let root = try scratchDir()
        let profile = scratchProfile(in: root)
        #expect(HomeSpeakerCommandLine.dataFolder(of: profile)
                == CLIOutput(stdout: [root.appendingPathComponent("data").path]))
        #expect(!helpText.contains("--where"))
        #expect(HomeSpeakerCommandLine.help() == CLIOutput(stdout: [helpText]))
    }

    /// The Stop hook, when the other HomeSpeaker is the one chosen and
    /// installed: `{}` and exit 0, and nothing is spoken or launched.
    @Test @MainActor func aHookStandsAsideForTheChosenOther() async throws {
        let root = try scratchDir()
        // Unique, so a de-duplication lock never silences a run.
        let reply = "The build is green and the change is ready \(UUID().uuidString)."
        let transcript = [
            #"{"message":{"role":"user","content":"is it done?"}}"#,
            #"{"message":{"role":"assistant","content":[{"type":"text","text":"\#(reply)"}]}}"#,
        ].joined(separator: "\n")
        let transcriptURL = root.appendingPathComponent("t.jsonl")
        try transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        let input = try JSONSerialization.data(withJSONObject: ["transcript_path": transcriptURL.path])
        let profile = scratchProfile(in: root)
        let manager = ConfigManager(
            configPath: profile.settingsURL, historyPath: profile.historyURL,
            secrets: SecretStore(fileURL: profile.secretsURL))
        manager.config = settings()
        let history = BroadcastHistory(fileURL: profile.historyURL)
        let locks = root.appendingPathComponent("locks")
        try FileManager.default.createDirectory(at: locks, withIntermediateDirectories: true)

        let broadcasts = Calls<String>()
        let launches = Calls<String>()
        func hook(standsAside: Bool) async -> CLIOutput {
            await HomeSpeakerCommandLine.claudeStopHook(
                input: input, config: { manager }, history: history, standsAside: standsAside,
                lockDirectory: locks, launchDetached: { launches.add($0) },
                broadcaster: { text, _, _, _ in broadcasts.add(text); return true })
        }

        #expect(await hook(standsAside: true) == CLIOutput(stdout: ["{}"]))
        #expect(broadcasts.all.isEmpty, "the hook spoke for the side that was not chosen")
        #expect(launches.all.isEmpty)
        #expect(history.load().isEmpty)

        // This Mac speaking goes through a detached --announce: also held.
        manager.config.effectiveSpeakLocal = true
        #expect(await hook(standsAside: true) == CLIOutput(stdout: ["{}"]))
        #expect(launches.all.isEmpty, "the hook launched an announcement for the side that was not chosen")

        // The detached --announce itself prints nothing and says nothing.
        let rig = try Rig()
        let announced = await HomeSpeakerCommandLine.announce(
            reply, config: settings(), announcer: rig.announcer, history: rig.history, standsAside: true)
        #expect(announced == CLIOutput())
        #expect(rig.home.calls.all.isEmpty)

        // Control: the same run, standing in for no one, does speak.
        manager.config.effectiveSpeakLocal = false
        #expect(await hook(standsAside: false) == CLIOutput(stdout: ["{}"]))
        #expect(broadcasts.all.count == 1)
    }

    /// `--say` is someone asking, so it speaks whichever side is chosen,
    /// and says which one is in use.
    @Test @MainActor func aDeliberateSayDoesNotStandAside() async throws {
        for door in [HomeSpeakerProfile.Door.app, .extension] {
            let rig = try Rig()
            let out = await HomeSpeakerCommandLine.say(
                "dinner is ready", config: settings(), announcer: rig.announcer, history: rig.history,
                standsAside: true, door: door)
            let other = door == .app ? "extension" : "app"
            #expect(out == CLIOutput(stdout: ["sent to Office"],
                                     stderr: ["note: the HomeSpeaker \(other) is the one in use"]), "\(door)")
            #expect(rig.home.calls.all == ["dinner is ready"], "a script's --say was silenced")
        }
    }

    @Test func theExtensionHasNoLoginItem() {
        let refusal = "the extension runs while Vitruvian runs; it has no login item of its own"
        for action in LoginItemAction.allCases {
            #expect(HomeSpeakerCommandLine.loginItem(action, item: HomeSpeakerCommandLine.Parts.extension().loginItem)
                    == CLIOutput(stderr: ["error: \(refusal)"], exitCode: 1), "\(action)")
        }
        guard case .control(let control) = HomeSpeakerCommandLine.Parts.app().loginItem else {
            Issue.record("the app's parts have no login item")
            return
        }
        #expect(control is SystemLoginItem)
    }

    /// Nothing is chosen yet, so today's users never see a hook stand aside.
    @Test func nothingStandsAsideUntilAChoiceIsMade() {
        #expect(HomeSpeakerCommandLine.Parts.app().standsAside() == false)
        #expect(HomeSpeakerCommandLine.Parts.extension().standsAside() == false)
    }

    /// The Stop hook's detached announcement runs this program again: the
    /// app's, or for the extension, `bin/tool`, its own program. Nothing is
    /// started: the spawn is a recorder.
    @Test func theDetachedAnnouncementRunsThisProgram() throws {
        let program = try #require(Bundle.main.executablePath)
        let started = Calls<[String]>()
        #expect(DetachedAnnouncement.launch(text: "never spoken") { executable, arguments in
            started.add([executable] + arguments)
            return true
        })
        #expect(started.all == [[program, program, "--announce", "never spoken"]])
        #expect(DetachedAnnouncement.launch(text: "never spoken", executable: nil) { _, _ in
            Issue.record("started a program with none to start")
            return true
        } == false)
    }
}

// MARK: - The whole dispatch, on a real engine in a scratch folder

/// An engine on an extension profile in a scratch folder, with this Mac's
/// speech silent. Its settings file holds `settings`, or is absent.
@MainActor
private func scratchEngine(settings: String?) throws -> HomeSpeakerEngine {
    let profile = scratchProfile(in: try scratchDir())
    let folder = profile.settingsURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    if let settings { try settings.write(to: profile.settingsURL, atomically: true, encoding: .utf8) }
    return HomeSpeakerEngine(profile: profile, local: StandInLocal())
}

/// The extension's parts, with no browser.
private let scratchParts = HomeSpeakerCommandLine.Parts(
    openBrowser: { _ in Issue.record("opened a browser") },
    loginItem: .none(reason: HomeSpeakerCommandLine.Parts.extensionHasNoLoginItem),
    standsAside: { false })

/// A settings file that does not read: reading it prints a problem.
private let unreadableSettings = "{ not json"

@Suite struct CommandLineDispatchTests {
    /// What the settings file is after a run: its text, or nil when absent.
    private func settingsText(_ engine: HomeSpeakerEngine) async -> String? {
        let url = await MainActor.run { engine.profile.settingsURL }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The commands that never read the settings still do not: with a
    /// settings file that does not read, nothing but their own lines is
    /// printed (reading it would print "Error loading speaker config" on
    /// stdout first); with none, none is written.
    @Test @MainActor func aCommandThatNeverReadTheSettingsStillDoesNot() async throws {
        let commands: [([String], (CLIOutput) -> Bool)] = [
            (["--version"], { $0 == CLIOutput(stdout: ["HomeSpeaker \(HomeSpeakerVersion.current)"]) }),
            (["--help"], { $0 == HomeSpeakerCommandLine.help() }),
            (["-h"], { $0 == HomeSpeakerCommandLine.help() }),
            (["--where"], { $0.stdout.count == 1 && $0.stderr.isEmpty }),
            (["--chat-monitor", "start"], { $0 == CLIOutput(stdout: ["asked a running HomeSpeaker to start the chat monitor"]) }),
            (["--chat-monitor", "pause"], { $0.exitCode == 2 }),
            (["--login-item", "status"], { $0.stderr == ["error: \(HomeSpeakerCommandLine.Parts.extensionHasNoLoginItem)"] }),
            (["--chat", "--discover"], { $0.exitCode == 2 }),
            (["--set-volume", "x"], { $0 == CLIOutput(stdout: [badLevel], exitCode: 1) }),
        ]
        for settings in [unreadableSettings, nil] {
            for (arguments, expected) in commands {
                let engine = try scratchEngine(settings: settings)
                guard case .now(let out) = HomeSpeakerCommandLine.action(for: arguments, engine: engine, parts: scratchParts) else {
                    Issue.record("\(arguments) did not print at once")
                    continue
                }
                #expect(expected(out), "\(arguments): \(out)")
                #expect(!engine.configLoaded, "\(arguments) read the settings")
                #expect(await settingsText(engine) == settings, "\(arguments) changed the settings file")
            }
        }
    }

    /// The same for the commands that run off the main actor: building
    /// them reads nothing, and neither does running them.
    @Test @MainActor func aLongerCommandThatNeverReadTheSettingsStillDoesNot() async throws {
        for settings in [unreadableSettings, nil] {
            for arguments in [["--sign-in"], ["--sign-out"], ["--test-media-pause"], ["--claude-stop-hook"]] {
                let engine = try scratchEngine(settings: settings)
                let action = HomeSpeakerCommandLine.action(
                    for: arguments, engine: engine, parts: scratchParts, standardInput: { Data("not json".utf8) })
                guard case .headless(_, _, let body) = action else {
                    Issue.record("\(arguments) did not run off the main actor")
                    continue
                }
                #expect(!engine.configLoaded, "\(arguments) read the settings")
                // Running them: no sign-in client, no stored login and no
                // transcript, so none reaches Google. --test-media-pause
                // would pause this Mac's music, so it is not run.
                if arguments != ["--test-media-pause"] {
                    let out = await body()
                    #expect(out.exitCode == (arguments == ["--sign-in"] ? 1 : 0), "\(arguments): \(out)")
                    #expect(!engine.configLoaded, "\(arguments) read the settings while running")
                }
                #expect(await settingsText(engine) == settings, "\(arguments) changed the settings file")
            }
        }
    }

    /// The commands that always read the settings read them where they
    /// always did: --say and --announce at once, for their time limit; the
    /// volume flags only while running.
    @Test @MainActor func theSettingsAreReadWhereTheyAlwaysWere() async throws {
        for arguments in [["--say", "hi"], ["--announce", "hi"]] {
            let engine = try scratchEngine(settings: nil)
            _ = HomeSpeakerCommandLine.action(for: arguments, engine: engine, parts: scratchParts)
            #expect(engine.configLoaded, "\(arguments)")
        }
        for arguments in [["--volume"], ["--discover"]] {
            let engine = try scratchEngine(settings: nil)
            _ = HomeSpeakerCommandLine.action(for: arguments, engine: engine, parts: scratchParts)
            #expect(!engine.configLoaded, "\(arguments) read the settings before running")
        }
        // Running --volume with no speaker picked reaches no speaker.
        let engine = try scratchEngine(settings: nil)
        guard case .headless(_, _, let body) = HomeSpeakerCommandLine.action(
            for: ["--volume"], engine: engine, parts: scratchParts) else {
            Issue.record("--volume did not run off the main actor")
            return
        }
        #expect(await body() == CLIOutput(stdout: [#"{"available":false,"reason":"\#(noSpeaker)"}"#], exitCode: 1))
        #expect(engine.configLoaded)
    }

    /// Each command's time limit and what it prints when it runs out.
    @Test @MainActor func everyCommandKeepsItsTimeLimit() throws {
        let timedOut = CLIOutput(stderr: ["error: timed out"], exitCode: 1)
        let volumeTimedOut = CLIOutput(stdout: [#"{"available":false,"reason":"timed out"}"#], exitCode: 1)
        let limits: [([String], TimeInterval, CLIOutput)] = [
            (["--say", "hi"], 20, timedOut),
            (["--announce", "hi"], 20, timedOut),
            (["--claude-stop-hook"], 8, CLIOutput(stdout: ["{}"])),
            (["--antigravity-hook"], 8, CLIOutput(stdout: ["{}"])),
            (["--opencode-hook"], 8, CLIOutput(stdout: ["{}"])),
            (["--volume"], 40, volumeTimedOut),
            (["--set-volume", "5"], 40, volumeTimedOut),
            (["--mute"], 40, volumeTimedOut),
            (["--sign-in"], 300, timedOut),
            (["--sign-out"], 30, timedOut),
            (["--discover"], 60, timedOut),
            (["--test-media-pause"], 30, timedOut),
        ]
        for (arguments, limit, output) in limits {
            let engine = try scratchEngine(settings: nil)
            guard case .headless(let timeout, let onTimeout, _) = HomeSpeakerCommandLine.action(
                for: arguments, engine: engine, parts: scratchParts, standardInput: { Data() }) else {
                Issue.record("\(arguments) did not run off the main actor")
                continue
            }
            #expect(timeout == limit, "\(arguments)")
            #expect(onTimeout == output, "\(arguments)")
        }
    }
}

// MARK: - Who asked: BroadcastSource and each agent's switch

@Suite struct BroadcastSourceTests {
    @Test func aGivenSourceWinsOverTheShell() {
        let claudeShell = ["CLAUDECODE": "1", "AI_AGENT": "claude-code"]
        #expect(BroadcastSource.resolve(arguments: ["--source", "antigravity", "--say", "hi"], environment: claudeShell)
                == .success(.antigravity))
        #expect(BroadcastSource.resolve(arguments: ["--source", "opencode", "--say", "hi"], environment: claudeShell)
                == .success(.opencode))
        #expect(BroadcastSource.resolve(arguments: ["--source", "user", "--say", "hi"], environment: claudeShell)
                == .success(.user), "a person can say it is them from an agent's shell")
        #expect(BroadcastSource.resolve(arguments: ["--source", "Claude", "--say", "hi"], environment: [:]) == .success(.claudeCode))
        #expect(BroadcastSource.resolve(arguments: ["--source", "agy", "--say", "hi"], environment: [:]) == .success(.antigravity))
        #expect(BroadcastSource.resolve(arguments: ["--source", "open-code", "--say", "hi"], environment: [:]) == .success(.opencode))
        #expect(BroadcastSource.resolve(arguments: ["--source", "open_code", "--say", "hi"], environment: [:]) == .success(.opencode))
    }

    @Test func aSourceInTheTextIsText() {
        // Everything after --say is what is spoken, flags and all.
        #expect(BroadcastSource.resolve(arguments: ["--say", "use", "--source", "antigravity"], environment: [:]) == .success(.user))
        #expect(HomeSpeakerCommandLine.parse(["--source", "antigravity", "--say", "use", "--source", "x"])
                == .say("use --source x"))
    }

    @Test func aBadSourceIsTheCallersMistake() {
        guard case .failure(let missing) = BroadcastSource.resolve(arguments: ["--source"], environment: [:]),
              case .failure(let unknown) = BroadcastSource.resolve(arguments: ["--source", "cursor", "--say", "x"], environment: [:])
        else {
            Issue.record("a bad --source resolved")
            return
        }
        #expect(missing.message.contains("needs a name"))
        #expect(unknown.message.contains("unknown --source cursor"))
        #expect(unknown.message.contains("user, claude-code, antigravity, opencode"))
    }

    @Test func theShellSaysWhichAgentRunsIt() {
        #expect(BroadcastSource.inferred(from: [:]) == .user)
        #expect(BroadcastSource.inferred(from: ["CLAUDECODE": "1"]) == .claudeCode)
        #expect(BroadcastSource.inferred(from: ["ANTIGRAVITY_AGENT": "1"]) == .antigravity)
        #expect(BroadcastSource.inferred(from: ["OPENCODE": "1"]) == .opencode)
        #expect(BroadcastSource.inferred(from: ["CLAUDECODE": "0"]) == .user, "only 1 counts")
        #expect(BroadcastSource.inferred(from: ["OPENCODE": "0"]) == .user, "only 1 counts")
        // Multiple inherited: AI_AGENT picks among the flagged ones.
        let both = ["CLAUDECODE": "1", "ANTIGRAVITY_AGENT": "1"]
        #expect(BroadcastSource.inferred(from: both.merging(["AI_AGENT": "antigravity"]) { $1 }) == .antigravity)
        #expect(BroadcastSource.inferred(from: both.merging(["AI_AGENT": "claude-code_2"]) { $1 }) == .claudeCode)
        #expect(BroadcastSource.inferred(from: both.merging(["AI_AGENT": "opencode"]) { $1 }) == .claudeCode,
                "AI_AGENT only chooses among the agents whose flag is 1")
        #expect(BroadcastSource.inferred(from: both) == .claudeCode, "no AI_AGENT: Claude Code, which sets CLAUDECODE")
        let agyAndOpenCode = ["ANTIGRAVITY_AGENT": "1", "OPENCODE": "1", "AI_AGENT": "opencode"]
        #expect(BroadcastSource.inferred(from: agyAndOpenCode) == .opencode,
                "OpenCode inside Antigravity sets AI_AGENT=opencode because Antigravity does not set AI_AGENT")
        let claudeAndOpenCode = ["CLAUDECODE": "1", "OPENCODE": "1", "AI_AGENT": "claude-code_2"]
        #expect(BroadcastSource.inferred(from: claudeAndOpenCode) == .claudeCode,
                "OpenCode uses AI_AGENT ||= opencode, so an outer Claude Code's AI_AGENT stays")
    }

    @Test func theHistoryNamesWhoAsked() {
        #expect(BroadcastSource.user.historyLabel == "Say")
        #expect(BroadcastSource.claudeCode.historyLabel == "Claude Code")
        #expect(BroadcastSource.antigravity.historyLabel == "Antigravity")
        #expect(BroadcastSource.opencode.historyLabel == "OpenCode")
        #expect(BroadcastSource.user.agent == nil)
    }

    @Test func aConfigWithoutTheKeysSpeaksForAllAgents() throws {
        let old = try JSONDecoder().decode(SpeakerConfig.self, from: Data(#"{"enabled": true, "default_target": "", "structure_id": "", "targets": {}}"#.utf8))
        #expect(old.announces(.claudeCode) && old.announces(.antigravity) && old.announces(.opencode), "as before the switches existed")
        var config = old
        config.setAnnounces(.antigravity, false)
        config.setAnnounces(.opencode, false)
        let json = try #require(String(data: JSONEncoder().encode(config), encoding: .utf8))
        #expect(json.contains(#""announce_antigravity":false"#))
        #expect(json.contains(#""announce_opencode":false"#))
        #expect(!json.contains("announce_claude_code"), "a switch never turned is not written")
        let read = try JSONDecoder().decode(SpeakerConfig.self, from: Data(json.utf8))
        #expect(read.announces(.claudeCode))
        #expect(!read.announces(.antigravity))
        #expect(!read.announces(.opencode))
        let explicit = try JSONDecoder().decode(
            SpeakerConfig.self, from: Data(#"{"enabled": true, "default_target": "", "structure_id": "", "targets": {}, "announce_claude_code": false}"#.utf8))
        #expect(!explicit.announces(.claudeCode))
        #expect(explicit.announces(.antigravity))
        #expect(explicit.announces(.opencode))
    }

    private func speaking() -> SpeakerConfig {
        var config = SpeakerConfig(enabled: true, defaultTarget: "", structureId: "")
        config.effectiveSpeakHome = false
        config.effectiveSpeakLocal = true
        return config
    }

    @Test @MainActor func anAgentsSayNeedsItsSwitch() async throws {
        let rig = try Rig()
        var config = speaking()
        config.setAnnounces(.antigravity, false)
        let off = await HomeSpeakerCommandLine.say(
            "done", config: config, announcer: rig.announcer, history: rig.history,
            standsAside: false, door: rig.profile.door, source: .antigravity)
        #expect(off == CLIOutput(stderr: [HomeSpeakerCommandLine.agentSwitchedOff(.antigravity)]),
                "the person's choice: exit 0, so the agent is not told it failed")
        #expect(off.stderr == ["Antigravity announcements are switched off in HomeSpeaker. Nothing spoken."])
        #expect(rig.local.calls.all.isEmpty)
        #expect(rig.history.load().isEmpty)

        // The other agent, and a person, still speak.
        let claude = await HomeSpeakerCommandLine.say(
            "built", config: config, announcer: rig.announcer, history: rig.history,
            standsAside: false, door: rig.profile.door, source: .claudeCode)
        #expect(claude.exitCode == 0)
        let person = await HomeSpeakerCommandLine.say(
            "dinner", config: config, announcer: rig.announcer, history: rig.history,
            standsAside: false, door: rig.profile.door)
        #expect(person.exitCode == 0)
        #expect(rig.local.calls.all == ["built", "dinner"])
        #expect(rig.history.load().map(\.source) == ["Say", "Claude Code"], "newest first, each under who asked")
    }

    @Test @MainActor func theSideInUseHoldsTheSwitches() async throws {
        let rig = try Rig()
        let mine = settings()
        var inUse = speaking()
        let routed = await HomeSpeakerCommandLine.say(
            "on this Mac", config: mine, announcer: rig.announcer, history: rig.history,
            standsAside: true, door: rig.profile.door, source: .opencode, inUse: inUse)
        #expect(routed.exitCode == 0)
        #expect(rig.local.calls.all == ["on this Mac"], "speaks on the outputs chosen in the active HomeSpeaker")
        #expect(rig.home.calls.all.isEmpty, "does not fall back to the passive side's home speaker toggle")

        inUse.setAnnounces(.claudeCode, false)
        let refused = await HomeSpeakerCommandLine.say(
            "x", config: mine, announcer: rig.announcer, history: rig.history,
            standsAside: true, door: rig.profile.door, source: .claudeCode, inUse: inUse)
        #expect(refused.stderr == [HomeSpeakerCommandLine.agentSwitchedOff(.claudeCode)])
        #expect(rig.local.calls.all == ["on this Mac"])
        inUse.enabled = false
        let masterOff = await HomeSpeakerCommandLine.say(
            "x", config: mine, announcer: rig.announcer, history: rig.history,
            standsAside: true, door: rig.profile.door, source: .antigravity, inUse: inUse)
        #expect(masterOff == CLIOutput(stderr: ["broadcasting is switched off"], exitCode: 1))
    }

    @Test @MainActor func aReplaySpeaksWithoutListingItAgain() async throws {
        let rig = try Rig()
        let out = await HomeSpeakerCommandLine.say(
            "again", config: speaking(), announcer: rig.announcer, history: rig.history,
            standsAside: false, door: rig.profile.door, records: false)
        #expect(out.exitCode == 0)
        #expect(rig.local.calls.all == ["again"])
        #expect(rig.history.load().isEmpty)
    }

    @Test @MainActor func theStopHooksAnnouncementFollowsClaudeCodesSwitch() async throws {
        let rig = try Rig()
        var config = speaking()
        config.setAnnounces(.claudeCode, false)
        let off = await HomeSpeakerCommandLine.announce(
            "reply", config: config, announcer: rig.announcer, history: rig.history, standsAside: false)
        #expect(off.stderr == [HomeSpeakerCommandLine.agentSwitchedOff(.claudeCode)])
        #expect(off.exitCode == 0)
        #expect(rig.local.calls.all.isEmpty)
        config.setAnnounces(.claudeCode, true)
        config.setAnnounces(.antigravity, false)
        let on = await HomeSpeakerCommandLine.announce(
            "reply", config: config, announcer: rig.announcer, history: rig.history, standsAside: false)
        #expect(on.exitCode == 0)
        #expect(rig.local.calls.all == ["reply"], "Antigravity's switch is not Claude Code's")
    }

    @Test func sourceIsNotAnAppCommand() {
        // `--source` first is a --say line, never "must be the first argument".
        #expect(AppCommandParser.parse(["--source", "claude-code", "--say", "hi"]) == nil)
        #expect(HomeSpeakerCommandLine.recognizes(["--source", "claude-code", "--say", "hi"]))
    }
}
