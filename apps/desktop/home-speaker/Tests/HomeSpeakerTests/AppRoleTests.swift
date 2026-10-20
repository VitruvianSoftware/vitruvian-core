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

// The menu bar app learns the choice (design 7.3 to 7.7, plan Task 15): what
// it starts at launch and on a change, what it shows, its hook, its monitor's
// gate, its sign-out, and the switch run from the app.
//
// The app's target cannot be linked by a test, so the app applies what
// `AppStartup`, `AppDoor` and `AppSwitch` decide, and these drive them with
// stand-ins. Every file is in a new temporary folder: the choice file, the
// agents' settings, both sides' settings and sign-ins, and the "installed"
// programs. No test quits, opens, moves to the Trash or switches the login
// item of anything: those are recorded. No message is posted, and no request
// leaves the process.

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-app-role-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

/// Answers every request with 200 and remembers each revoke's token, so a
/// sign-out never reaches Google.
private final class AppRoleGoogle: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String] = []

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AppRoleGoogle.self]
        return URLSession(configuration: configuration)
    }

    static func revoked(_ token: String) -> Bool {
        lock.withLock { bodies.contains { $0.contains(token.formEncoded) } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                guard n > 0 else { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        Self.lock.withLock { Self.bodies.append(String(decoding: body, as: UTF8.self)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private struct SilentMac: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

/// This Mac's media, as these tests see it: never paused, and never asked
/// under the app's message names (the default pauser's in a test process).
/// No test here speaks, so being asked at all fails the test.
private struct NoMediaPause: MediaPausing {
    func pause(seconds: Double) async { Issue.record("asked to pause this Mac's media") }
    func extend(seconds: Double) async { Issue.record("asked to hold this Mac's media paused") }
    func resumeNow() async { Issue.record("asked to resume this Mac's media") }
}

/// One Mac, in a temporary folder: the choice file, the agents' home, the
/// app's files and program, and the extension's program and data folder.
@MainActor
private final class AppRig {
    let root: URL
    let door: DoorFile
    /// Where the coding agents keep their files.
    let home: URL
    /// The app's program, as a hook names it.
    let appProgram: URL
    /// HomeSpeaker.app, as the running app finds its own bundle.
    var bundlePath: String
    let extensionProgram: URL
    let extensionData: URL
    let appProfile: HomeSpeakerProfile
    /// Everything the app was asked to do, in order.
    var calls: [String] = []
    let monitor = FakeChatMonitor(running: false)
    /// The extension's chat monitor, as the app sees it: running or not.
    var extensionReading = false
    /// Re-checks the app asked for while it waits; run by hand.
    var scheduled: [@MainActor () -> Void] = []

    init() throws {
        root = try scratchDir()
        door = DoorFile(url: root.appendingPathComponent("gemini").appendingPathComponent(DoorFile.fileName))
        home = root.appendingPathComponent("home")
        let bundle = root.appendingPathComponent("Applications/HomeSpeaker.app")
        bundlePath = bundle.path
        appProgram = bundle.appendingPathComponent("Contents/MacOS/HomeSpeaker")
        try FileManager.default.createDirectory(at: appProgram.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: appProgram)
        let vitruvian = root.appendingPathComponent("Vitruvian")
        extensionProgram = vitruvian.appendingPathComponent("Tools/dev.vitruvian.homespeaker/bin/tool")
        extensionData = vitruvian.appendingPathComponent("ToolData/dev.vitruvian.homespeaker")
        appProfile = HomeSpeakerProfile(
            door: .app,
            settingsURL: root.appendingPathComponent("gemini/speaker_broadcast.json"),
            historyURL: root.appendingPathComponent("gemini/speaker_history.json"),
            secretsURL: root.appendingPathComponent("AppSupport/HomeSpeaker/secrets.json"),
            messagePrefix: testPrefix(), liveLockURL: nil, toolFolder: nil)
        for url in [appProfile.settingsURL, appProfile.historyURL, appProfile.secretsURL, door.url] {
            try #require(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        }
    }

    /// The extension as a 1.19+ one leaves it: its program, its data folder,
    /// and its block in the choice file. `mark` nil is an older extension.
    func installExtension(mark: Int? = DoorRecord.ExtensionEntry.runsAlone, chosen: HomeSpeakerProfile.Door? = nil) throws {
        try FileManager.default.createDirectory(at: extensionProgram.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extensionData, withIntermediateDirectories: true)
        try Data().write(to: extensionProgram)
        try door.update {
            $0.installedExtension = DoorRecord.ExtensionEntry(
                program: self.extensionProgram.path, dataFolder: self.extensionData.path, version: "1.19.0", door: mark)
            $0.chosen = chosen
            $0.chosenAt = chosen == nil ? nil : Date(timeIntervalSince1970: 1_800_000_000)
        }
    }

    func choose(_ chosen: HomeSpeakerProfile.Door) throws {
        try door.update {
            $0.chosen = chosen
            $0.chosenAt = Date()
        }
    }

    var check: DoorCheck { DoorCheck(file: door, appInstalled: { false }) }

    /// The agents' integration as the app's program sees it, on this home.
    var integration: AgentIntegration {
        AgentIntegration(home: home, executablePath: appProgram.path, bootout: { _ in })
    }

    func makeDoor() -> AppDoor {
        AppDoor(
            check: check,
            bundlePath: { [unowned self] in self.bundlePath },
            monitor: monitor,
            effects: AppDoor.Effects(
                repairHooks: { [unowned self] choice in
                    self.calls.append("repairHooks(\(choice?.rawValue ?? "nil"))")
                    self.integration.repairHookIfMoved(choice: choice)
                },
                startMonitorIfConfigured: { [unowned self] in self.calls.append("startMonitor") },
                stopMonitor: { [unowned self] in self.calls.append("stopMonitor") },
                startListening: { [unowned self] in self.calls.append("startListening") },
                stopListening: { [unowned self] in self.calls.append("stopListening") }),
            extensionReadsChat: { [unowned self] _ in self.extensionReading },
            later: { [unowned self] in self.scheduled.append($0) })
    }

    /// Runs the re-checks asked for so far.
    func runScheduled() {
        let due = scheduled
        scheduled = []
        for work in due { work() }
    }

    var copied: [HomeSpeakerProfile.Door] = []
    var copyFails: DoorCopyPartial?

    func makeSwitch(_ appDoor: AppDoor) -> AppSwitch {
        AppSwitch(door: appDoor, parts: AppSwitch.Parts(
            appProfile: appProfile,
            home: home,
            now: { Date(timeIntervalSince1970: 1_900_000_000) },
            copy: { [unowned self] from, to in
                self.calls.append("copy(\(from.door.rawValue)->\(to.door.rawValue))")
                if let partial = self.copyFails { throw partial }
                return try DoorCopy.copy(from: from, to: to)
            },
            credentialsChangedIn: { [unowned self] in self.calls.append("credentialsChanged(\($0.door.rawValue))") },
            turnOffLoginItem: { [unowned self] in self.calls.append("loginItemOff") },
            moveToTrash: { [unowned self] in self.calls.append("trash") },
            quit: { [unowned self] in self.calls.append("quit") },
            openVitruvian: { [unowned self] in self.calls.append("openVitruvian"); return true }))
    }

    var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }

    /// Writes a Claude Code Stop hook that runs `program`, beside one of the
    /// person's own.
    func installHook(running program: String) throws {
        var settings = AgentIntegration.mergeHook(
            into: [:], command: AgentIntegration.hookCommand(executable: program), agent: .claudeCode)
        var hooks = settings["hooks"] as! [String: Any]
        var stop = hooks["Stop"] as! [[String: Any]]
        stop.insert(["hooks": [["type": "command", "command": "say done"]]], at: 0)
        hooks["Stop"] = stop
        settings["hooks"] = hooks
        try FileManager.default.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: claudeSettings)
    }

    /// The program the Claude Code hook runs now.
    var hookProgram: String? { integration.status(of: .claudeCode).hookProgram }

    /// The person's own hook is still there.
    var ownHookKept: Bool { ((try? String(contentsOf: claudeSettings, encoding: .utf8)) ?? "").contains("say done") }
}

// MARK: - What starts, by role

@MainActor
@Suite struct AppRoleTests {
    @Test func aloneStartsAsToday() throws {
        let rig = try AppRig()
        // Today: the hook repaired, the chat monitor started when switched
        // on, then the media and volume listeners (App.swift before 1.19).
        #expect(AppStartup.today == [.hookRepair, .chatMonitor, .listeners])
        let plan = AppStartup.plan(check: rig.check, bundlePath: rig.bundlePath)
        #expect(plan.role == .active)
        #expect(plan.starts == AppStartup.today)
        #expect(!plan.asks)
        #expect(!plan.showsQuiet)

        let door = rig.makeDoor()
        door.refresh()
        #expect(rig.calls == ["repairHooks(nil)", "startMonitor", "startListening"])
        #expect(door.monitor.permission.value, "the monitor may start, as it always could")
        // Nothing changed: nothing is started twice.
        door.refresh()
        #expect(rig.calls.count == 3)
    }

    @Test func askingStartsAsTodayAndAsks() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        let plan = AppStartup.plan(check: rig.check, bundlePath: rig.bundlePath)
        #expect(plan.role == .activeAsking)
        #expect(plan.starts == AppStartup.today, "until a pick, the app runs exactly as today")
        #expect(plan.asks)
        #expect(!plan.showsQuiet)

        let door = rig.makeDoor()
        door.refresh()
        #expect(rig.calls == ["repairHooks(nil)", "startMonitor", "startListening"])
        #expect(door.monitor.permission.value)
        door.monitor.start()
        #expect(rig.monitor.calls == ["start"], "a monitor switched on runs while nobody has picked")
    }

    @Test func quietStartsNothing() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        let plan = AppStartup.plan(check: rig.check, bundlePath: rig.bundlePath)
        #expect(plan.role == .quiet(other: .extension))
        #expect(plan.starts.isEmpty)
        #expect(plan.showsQuiet)
        #expect(!plan.asks)

        let door = rig.makeDoor()
        door.refresh()
        #expect(rig.calls.isEmpty, "a quiet app started \(rig.calls)")
        #expect(!door.monitor.permission.value)
        door.monitor.start()
        #expect(rig.monitor.calls.isEmpty, "a quiet app read chat")
    }

    @Test func goingQuietStopsTheMonitor() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        let door = rig.makeDoor()
        door.refresh()
        rig.calls = []

        // Picking the app while it runs: the hook follows the choice, and
        // nothing is started twice.
        try rig.choose(.app)
        door.refresh()
        #expect(rig.calls == ["repairHooks(app)"])
        rig.calls = []

        try rig.choose(.extension)
        door.refresh()
        #expect(rig.calls == ["stopMonitor", "stopListening"])
        #expect(door.plan.role == .quiet(other: .extension))
        door.monitor.start()
        #expect(rig.monitor.calls.isEmpty)

        // Chosen again: it starts as at launch, the hook following the choice.
        rig.calls = []
        try rig.choose(.app)
        door.refresh()
        #expect(rig.calls == ["repairHooks(app)", "startMonitor", "startListening"])
        #expect(door.plan.role == .active)
    }

    @Test func theAppsMonitorWaitsForTheExtensionToStop() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        rig.extensionReading = true
        let door = rig.makeDoor()
        door.refresh()
        let side = rig.makeSwitch(door)

        // Picked in the app: the extension reads chat until its next look.
        side.choose(.app)
        side.finish(copy: false)
        #expect(rig.calls == ["repairHooks(app)", "startListening"], "the monitor started beside the extension's: \(rig.calls)")
        #expect(!door.monitor.permission.value)
        ChatMonitorControlNotice.apply(.start, monitor: door.monitor)
        #expect(rig.monitor.calls.isEmpty, "a start went past the wait")
        #expect(!rig.scheduled.isEmpty, "nothing will look again")

        // Still reading: still waiting.
        rig.runScheduled()
        #expect(!rig.calls.contains("startMonitor"))
        #expect(!rig.scheduled.isEmpty)

        // Seen quiet: now it starts, once.
        rig.extensionReading = false
        rig.runScheduled()
        #expect(rig.calls.filter { $0 == "startMonitor" }.count == 1)
        #expect(door.monitor.permission.value)
        rig.runScheduled()
        door.refresh()
        #expect(rig.calls.filter { $0 == "startMonitor" }.count == 1, "started twice")

        // At launch, the same: an extension still reading holds it back.
        rig.calls = []
        rig.extensionReading = true
        let launched = rig.makeDoor()
        launched.refresh()
        #expect(!rig.calls.contains("startMonitor"))
        rig.extensionReading = false
        launched.refresh()
        #expect(rig.calls.contains("startMonitor"))
    }

    @Test func theExtensionReadsChatOnlyWhileItsLockIsHeldAndItSaysSo() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .app)
        let profile = try #require(AppStartup.extensionProfile(record: rig.door.read()))
        let lockURL = try #require(profile.liveLockURL)
        try #require(lockURL.path.hasPrefix(rig.root.path + "/"))
        let status = ChatMonitorStatusFile(url: profile.monitorStatusURL)

        #expect(!AppStartup.extensionReadsChat(profile), "no process, no status")
        try status.write(ChatMonitorStatus(isRunning: true))
        #expect(!AppStartup.extensionReadsChat(profile), "a crashed extension left 'running' behind: nobody holds its lock")
        let lock = try LiveLock.hold(at: lockURL)
        #expect(AppStartup.extensionReadsChat(profile))
        try status.write(ChatMonitorStatus(isRunning: false))
        #expect(!AppStartup.extensionReadsChat(profile), "running, but its monitor stopped")
        lock.release()
    }

    @Test func quietNeverRepairsTheHook() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        // The hook runs a copy of the app that has moved away.
        let moved = rig.root.appendingPathComponent("Downloads/HomeSpeaker.app/Contents/MacOS/HomeSpeaker").path
        try rig.installHook(running: moved)
        let before = try Data(contentsOf: rig.claudeSettings)

        rig.makeDoor().refresh()
        #expect(try Data(contentsOf: rig.claudeSettings) == before, "a quiet app re-pointed the hook")

        // Control: chosen, the same app repairs it.
        try rig.choose(.app)
        rig.makeDoor().refresh()
        #expect(rig.hookProgram == rig.appProgram.path)
        #expect(rig.ownHookKept)
    }

    @Test func anOldExtensionIsNotAsked() throws {
        let rig = try AppRig()
        // An extension before 1.19 never writes the mark: it drives the app.
        try rig.installExtension(mark: nil, chosen: nil)
        var plan = AppStartup.plan(check: rig.check, bundlePath: rig.bundlePath)
        #expect(plan.role == .active)
        #expect(!plan.asks)
        // Nor one whose program is gone or in the Trash.
        try rig.installExtension(chosen: nil)
        try FileManager.default.removeItem(at: rig.extensionProgram)
        plan = AppStartup.plan(check: rig.check, bundlePath: rig.bundlePath)
        #expect(!plan.asks)
        #expect(!rig.makeSwitch(rig.makeDoor()).canChooseExtension, "Use the extension offered for one that is gone")
    }

    // MARK: - The monitor's gate

    @Test func aQuietSideIgnoresSettingsAndNotices() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        let secrets = SecretStore(fileURL: rig.appProfile.secretsURL)
        try secrets.save(Secrets(slackToken: "xoxp-made-up-\(UUID().uuidString)")) // gitleaks:allow (made-up test token)
        let config = ConfigManager(configPath: rig.appProfile.settingsURL, historyPath: rig.appProfile.historyURL, secrets: secrets)
        let door = rig.makeDoor()
        door.refresh()
        config.chatMonitor = door.monitor

        // The phone switches Slack on: the settings watcher.
        var on = config.config
        on.chatMonitor = ChatMonitorConfig(slackEnabled: true)
        try SpeakerConfigFile(url: rig.appProfile.settingsURL).write(on)
        config.reloadIfChangedExternally()
        // A token saved elsewhere: the credentials-changed notice.
        CredentialsChangedNotice.apply(config: config, monitor: door.monitor)
        // A Chat-only sign-out elsewhere restarts a running monitor.
        SignOutNotice.apply(chatOnly: true, config: config, monitor: door.monitor)
        // `--chat-monitor start` and the Vitruvian tool: the control message.
        ChatMonitorControlNotice.apply(.start, monitor: door.monitor)
        #expect(!rig.monitor.calls.contains("start"), "a quiet app started its monitor: \(rig.monitor.calls)")
        #expect(!rig.monitor.isRunning)

        // Chosen: the same message starts it.
        try rig.choose(.app)
        door.refresh()
        ChatMonitorControlNotice.apply(.start, monitor: door.monitor)
        #expect(rig.monitor.calls.contains("start"))
    }

    // MARK: - The hook

    @Test func theAppsHookStandsAside() async throws {
        let rig = try AppRig()
        let bundlePath = rig.bundlePath
        var parts = AppStartup.commandLineParts(check: rig.check, bundlePath: { bundlePath })
        #expect(!parts.standsAside(), "nothing installed: the app's hook speaks")

        try rig.installExtension(chosen: nil)
        #expect(!parts.standsAside(), "nobody has picked: the app's hook still speaks")
        try rig.choose(.app)
        #expect(!parts.standsAside())

        try rig.choose(.extension)
        #expect(parts.standsAside(), "the extension is chosen and installed: a stale app hook must say nothing")

        // The real wiring: the Stop hook on an engine of the app's shape
        // answers "{}" and speaks nothing, before reading a transcript.
        let engine = HomeSpeakerEngine(profile: rig.appProfile, session: AppRoleGoogle.session, local: SilentMac())
        let transcript = rig.root.appendingPathComponent("t.jsonl")
        try #"{"message":{"role":"assistant","content":[{"type":"text","text":"Done."}]}}"#
            .write(to: transcript, atomically: true, encoding: .utf8)
        let input = try JSONSerialization.data(withJSONObject: ["transcript_path": transcript.path])
        guard case .headless(_, _, let body) = HomeSpeakerCommandLine.action(
            for: [ClaudeStopHook.argument], engine: engine, parts: parts, standardInput: { input }) else {
            Issue.record("the Stop hook does not run headless")
            return
        }
        #expect(await body() == CLIOutput(stdout: ["{}"]))
        #expect(BroadcastHistory(fileURL: rig.appProfile.historyURL).load().isEmpty, "the stale hook spoke")

        // An app in the Trash stands aside too, whatever the file says.
        try FileManager.default.removeItem(at: rig.door.url)
        let trashed = rig.root.appendingPathComponent(".Trash/HomeSpeaker.app").path
        parts = AppStartup.commandLineParts(check: rig.check, bundlePath: { trashed })
        #expect(parts.standsAside())
    }

    @Test func theSwitchRepointsTheHook() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        try rig.installHook(running: rig.extensionProgram.path)
        let door = rig.makeDoor()
        door.refresh()
        let side = rig.makeSwitch(door)

        side.choose(.app)
        side.finish(copy: false)
        #expect(rig.hookProgram == rig.appProgram.path, "the app was chosen, but the hook still runs the extension")
        #expect(rig.ownHookKept)

        side.done()
        side.choose(.extension)
        side.finish(copy: false)
        #expect(rig.hookProgram == rig.extensionProgram.path, "the extension was chosen, but the hook still runs the app")
        #expect(rig.ownHookKept)
        #expect(!FileManager.default.fileExists(
            atPath: CodingAgent.antigravity.settingsURL(home: rig.home).path), "a hook was added where there was none")
    }

    // MARK: - Signing out

    @Test func theQuietAppSignsOutLocally() async throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        let id = UUID().uuidString
        let refresh = "1//made-up-refresh-\(id)" // gitleaks:allow (made-up test token)
        let login = GoogleCredentials(
            clientId: "shipped.apps.googleusercontent.test", clientSecret: "made-up-\(id)", // gitleaks:allow (made-up test token)
            accessToken: "ya29.made-up-\(id)", refreshToken: refresh, // gitleaks:allow (made-up test token)
            scopes: [GoogleAuth.homeScope], userId: "1234", email: "person@example.test")
        // The copy left the same login on both sides.
        let extensionProfile = try #require(AppStartup.extensionProfile(record: rig.door.read()))
        try SecretStore(fileURL: extensionProfile.secretsURL).save(Secrets(google: login))
        let theirs = try Data(contentsOf: extensionProfile.secretsURL)
        let engine = HomeSpeakerEngine(profile: rig.appProfile, session: AppRoleGoogle.session, local: SilentMac())
        try engine.secrets.save(Secrets(google: login))

        let door = rig.makeDoor()
        door.refresh()
        let out = await door.signOut(engine: engine, chatOnly: false)
        #expect(out.exitCode == 0)
        #expect(engine.secrets.load().google == nil, "still signed in here")
        #expect(!AppRoleGoogle.revoked(refresh), "the quiet app revoked the extension's login at Google")
        #expect(try Data(contentsOf: extensionProfile.secretsURL) == theirs, "the extension's sign-ins changed")

        // Control: with no extension, the same Sign Out revokes, as always.
        try FileManager.default.removeItem(at: rig.door.url)
        var alone = login
        alone.refreshToken = "1//made-up-alone-\(id)" // gitleaks:allow (made-up test token)
        try engine.secrets.save(Secrets(google: alone))
        door.refresh()
        _ = await door.signOut(engine: engine, chatOnly: false)
        #expect(AppRoleGoogle.revoked(alone.refreshToken), "the stand-in never saw a revoke, so the check above proves nothing")
    }

    @Test func theCommandLineSignOutNeverRevokesASharedLogin() async throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        let id = UUID().uuidString
        let shared = GoogleCredentials(
            clientId: "shipped.apps.googleusercontent.test", clientSecret: "made-up-\(id)", // gitleaks:allow (made-up test token)
            accessToken: "ya29.made-up-cli-\(id)", refreshToken: "1//made-up-cli-\(id)", // gitleaks:allow (made-up test token)
            scopes: [GoogleAuth.homeScope], userId: "1234", email: "person@example.test")
        let extensionProfile = try #require(AppStartup.extensionProfile(record: rig.door.read()))
        try SecretStore(fileURL: extensionProfile.secretsURL).save(Secrets(google: shared))
        let theirs = try Data(contentsOf: extensionProfile.secretsURL)
        let engine = HomeSpeakerEngine(profile: rig.appProfile, session: AppRoleGoogle.session, local: SilentMac())
        try engine.secrets.save(Secrets(google: shared))
        var posted: [String] = []
        let lock = NSLock()
        let bundlePath = rig.bundlePath
        let parts = AppStartup.commandLineParts(
            check: rig.check, bundlePath: { bundlePath },
            postSignedOut: { chatOnly, name in lock.withLock { posted.append("\(name.rawValue) \(chatOnly)") } })

        func signOut() async -> CLIOutput {
            guard case .headless(_, _, let body) = HomeSpeakerCommandLine.action(
                for: ["--sign-out"], engine: engine, parts: parts) else {
                Issue.record("--sign-out does not run headless")
                return CLIOutput()
            }
            return await body()
        }

        // The app is quiet, the login is the extension's too: removed here only.
        #expect(await signOut() == CLIOutput(stdout: ["signed out of Google (Home and Chat)"]))
        #expect(engine.secrets.load().google == nil, "still signed in here")
        #expect(!AppRoleGoogle.revoked(shared.refreshToken), "the app's --sign-out revoked the extension's login at Google")
        #expect(try Data(contentsOf: extensionProfile.secretsURL) == theirs)
        #expect(lock.withLock { posted } == ["\(rig.appProfile.messagePrefix).signed-out false"])

        // Control: with no extension, the same lines, and the login revoked.
        try FileManager.default.removeItem(at: rig.door.url)
        var alone = shared
        alone.refreshToken = "1//made-up-cli-alone-\(id)" // gitleaks:allow (made-up test token)
        try engine.secrets.save(Secrets(google: alone))
        #expect(await signOut() == CLIOutput(stdout: ["signed out of Google (Home and Chat)"]))
        #expect(AppRoleGoogle.revoked(alone.refreshToken))
    }

    // MARK: - In the Trash

    @Test func sayInTheTrashSaysWhyItStandsAside() async throws {
        let rig = try AppRig()
        let trashed = rig.root.appendingPathComponent(".Trash/HomeSpeaker.app").path
        let parts = AppStartup.commandLineParts(check: rig.check, bundlePath: { trashed })
        let rigHistory = BroadcastHistory(fileURL: rig.appProfile.historyURL)
        let announcer = Announcer(home: GoogleHomeClient(
            auth: GoogleAuth(store: SecretStore(fileURL: rig.appProfile.secretsURL), session: AppRoleGoogle.session),
            session: AppRoleGoogle.session), local: SilentMac(), media: NoMediaPause())
        var off = SpeakerConfig()
        off.enabled = false
        func say() async -> [String] {
            await HomeSpeakerCommandLine.say(
                "hello", config: off, announcer: announcer, history: rigHistory,
                standsAside: parts.standsAside(), door: .app, note: parts.asideNote()).stderr
        }

        // In the Trash, no extension: not "the extension is in use".
        #expect(parts.standsAside())
        #expect(await say().first == "note: this copy of the HomeSpeaker app is in the Trash, so it stays quiet")
        // An extension installed but not chosen: still only the Trash.
        try rig.installExtension(chosen: nil)
        #expect(await say().first == AppStartup.inTheTrashNote)
        // The extension chosen and installed: that is why.
        try rig.choose(.extension)
        #expect(await say().first == "note: the HomeSpeaker extension is the one in use")
        // Not in the Trash: the same.
        let home = rig.bundlePath
        let usual = AppStartup.commandLineParts(check: rig.check, bundlePath: { home })
        #expect(usual.asideNote() == nil)
    }

    @Test func anAppInTheTrashStaysQuietAndWritesNothing() throws {
        let rig = try AppRig()
        try rig.installHook(running: rig.root.appendingPathComponent("gone/HomeSpeaker").path)
        let hookBefore = try Data(contentsOf: rig.claudeSettings)
        rig.bundlePath = rig.root.appendingPathComponent(".Trash/HomeSpeaker.app").path

        let plan = AppStartup.plan(check: rig.check, bundlePath: rig.bundlePath)
        #expect(plan.inTrash)
        #expect(plan.role.isQuiet)
        #expect(plan.starts.isEmpty)
        #expect(!plan.asks && !plan.showsQuiet)
        let door = rig.makeDoor()
        door.refresh()
        #expect(rig.calls.isEmpty)
        #expect(!door.monitor.permission.value)

        let side = rig.makeSwitch(door)
        side.choose(.app)
        side.finish(copy: true)
        #expect(!FileManager.default.fileExists(atPath: rig.door.url.path), "an app in the Trash wrote the choice")
        #expect(try Data(contentsOf: rig.claudeSettings) == hookBefore)

        // Dragged there while it runs: the next look stops it.
        rig.bundlePath = rig.root.appendingPathComponent("Applications/HomeSpeaker.app").path
        let running = rig.makeDoor()
        running.refresh()
        rig.calls = []
        rig.bundlePath = rig.root.appendingPathComponent(".Trash/HomeSpeaker.app").path
        running.refresh()
        #expect(rig.calls == ["stopMonitor", "stopListening"])
    }

    // MARK: - The switch, from the app

    @Test func choosingTheExtensionCopiesGoesQuietAndOffers() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        try SpeakerConfigFile(url: rig.appProfile.settingsURL).write(SpeakerConfig(structureName: "Lake House"))
        let door = rig.makeDoor()
        door.refresh()
        rig.calls = []
        let side = rig.makeSwitch(door)
        #expect(side.canChooseExtension)

        side.choose(.extension)
        guard case .compare(let compare)? = side.step else { Issue.record("no step 2"); return }
        #expect(compare.from == .app && compare.into == .extension)
        side.finish(copy: true)

        #expect(Array(rig.calls.prefix(2)) == ["copy(app->extension)", "credentialsChanged(extension)"],
                "the copy, then the destination told: \(rig.calls)")
        #expect(rig.calls.contains("stopMonitor"), "choosing the extension leaves the app reading chat")
        #expect(rig.door.read()?.chosen == .extension)
        #expect(rig.door.read()?.chosenBy == "HomeSpeaker app \(HomeSpeakerVersion.current)")
        #expect(door.plan.role == .quiet(other: .extension))
        #expect(side.report.contains("Settings: copied from the app."))
        guard case .extensionChosen(let offers)? = side.step else { Issue.record("no offers"); return }
        #expect(offers.loginItem, "Open at Login is turned off unless unticked")
        #expect(!offers.trash, "the Trash needs its own tick")

        rig.calls = []
        side.setTrash(true)
        side.done()
        #expect(rig.calls == ["loginItemOff", "trash", "quit"])
    }

    @Test func choosingTheAppSaysHowToRemoveTheExtension() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        let door = rig.makeDoor()
        door.refresh()
        let side = rig.makeSwitch(door)
        side.choose(.app)
        guard case .compare(let compare)? = side.step else { Issue.record("no step 2"); return }
        #expect(compare.from == .extension && compare.into == .app)
        side.finish(copy: false)

        #expect(rig.door.read()?.chosen == .app)
        #expect(door.plan.role == .active)
        #expect(rig.calls.contains("startMonitor"))
        #expect(side.step == .appChosen)
        #expect(DoorWords.appChosen ==
                "The extension is quiet now. To remove it: Vitruvian > Settings > Extensions > HomeSpeaker > Remove.")
        side.openVitruvian()
        #expect(rig.calls.last == "openVitruvian")
        #expect(!rig.calls.contains("quit"))
    }

    @Test func aPartialCopyTellsTheDestinationAndSaysWhatCopied() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        let door = rig.makeDoor()
        door.refresh()
        let side = rig.makeSwitch(door)
        rig.copyFails = DoorCopyPartial(
            copied: ["Settings: copied from the extension."], notCopied: ["History: not copied (disk full)."],
            signInsWritten: true)
        side.choose(.app)
        side.finish(copy: true)
        #expect(rig.calls.contains("credentialsChanged(app)"))
        #expect(side.report == ["Settings: copied from the extension.", "History: not copied (disk full)."])
        #expect(rig.door.read()?.chosen == nil, "a copy that stopped part-way still chose")
        guard case .compare? = side.step else { Issue.record("step 2 left"); return }
    }

    @Test func copyingFromASideWithNoSignInsWarnsFirst() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        try SecretStore(fileURL: rig.appProfile.secretsURL).save(Secrets(slackToken: "xoxp-made-up-\(UUID().uuidString)")) // gitleaks:allow (made-up test token)
        let side = rig.makeSwitch(rig.makeDoor())
        side.choose(.app)
        guard case .compare(let compare)? = side.step else { Issue.record("no step 2"); return }
        #expect(compare.signsOut)
        #expect(DoorWords.signsOut(from: compare.from, into: compare.into)
                == "The extension has no sign-ins, so copying from it signs the app out.")
    }

    @Test func backLeavesEverythingAsItWas() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        let before = try Data(contentsOf: rig.door.url)
        let side = rig.makeSwitch(rig.makeDoor())
        side.choose(.extension)
        side.back()
        #expect(side.step == nil)
        #expect(try Data(contentsOf: rig.door.url) == before)
        #expect(!rig.calls.contains { $0.hasPrefix("copy") })
    }

    @Test func aChoiceMadeInTheExtensionIsNeverOverridden() throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: nil)
        let door = rig.makeDoor()
        door.refresh()
        let side = rig.makeSwitch(door)
        side.choose(.app)
        // Meanwhile, the person picks the extension in Vitruvian.
        try rig.choose(.extension)
        side.finish(copy: true)
        #expect(rig.door.read()?.chosen == .extension)
        #expect(side.step == nil)
        #expect(side.report == [DoorWords.choiceChanged])
        #expect(!rig.calls.contains { $0.hasPrefix("copy") })
        #expect(door.plan.role == .quiet(other: .extension))
    }

    @Test func useTheExtensionNeedsADoorMarkedExtension() throws {
        let rig = try AppRig()
        try rig.installExtension(mark: nil, chosen: nil)
        let side = rig.makeSwitch(rig.makeDoor())
        #expect(!side.canChooseExtension)
        side.choose(.extension)
        #expect(side.step == nil)
    }

    // MARK: - Odds and ends

    @Test func aChangeInTheFolderReachesTheRole() throws {
        let rig = try AppRig()
        let config = ConfigManager(
            configPath: rig.appProfile.settingsURL, historyPath: rig.appProfile.historyURL,
            secrets: SecretStore(fileURL: rig.appProfile.secretsURL))
        var heard = 0
        config.onFolderChange = { heard += 1 }
        config.folderChanged()
        #expect(heard == 1)
    }

    @Test func theAppSaysWhereToApproveItsLoginItem() {
        #expect(AppCommandRunner.approveLoginItem.hasSuffix("System Settings > General > Login Items & Extensions"))
        #expect(DoorWords.approveLoginItem == "Approve HomeSpeaker under System Settings > General > Login Items & Extensions.")
    }

    @Test func passiveAppSayDelegatesToActiveExtensionsSettingsEngineAndTimeLimit() async throws {
        let rig = try AppRig()
        try rig.installExtension(chosen: .extension)
        let extensionProfile = try #require(AppStartup.extensionProfile(record: rig.door.read()))

        // The app has local speech off (20s limit); the active extension has
        // local speech on (90s limit).
        var appConfig = SpeakerConfig(enabled: true)
        appConfig.effectiveSpeakHome = false
        appConfig.effectiveSpeakLocal = false
        try SpeakerConfigFile(url: rig.appProfile.settingsURL).write(appConfig)

        var extConfig = SpeakerConfig(enabled: true)
        extConfig.effectiveSpeakHome = false
        extConfig.effectiveSpeakLocal = true
        try SpeakerConfigFile(url: extensionProfile.settingsURL).write(extConfig)

        let appEngine = HomeSpeakerEngine(profile: rig.appProfile, session: AppRoleGoogle.session, local: SilentMac())
        let bundlePath = rig.bundlePath
        let parts = AppStartup.commandLineParts(
            check: rig.check, bundlePath: { bundlePath },
            makeInUseEngine: { HomeSpeakerEngine(profile: $0, session: AppRoleGoogle.session, local: SilentMac()) })

        guard case .headless(let timeout, _, let body) = HomeSpeakerCommandLine.action(
            for: ["--say", "hello from passive app"], engine: appEngine, parts: parts) else {
            Issue.record("--say must run headless")
            return
        }
        #expect(timeout > 20, "passive door must use active door's expanded timeLimit when local speech is enabled there")
        let out = await body()
        #expect(out.exitCode == 0)
        #expect(out.stdout == ["spoke on this Mac"])
        #expect(out.stderr.first == "note: the HomeSpeaker extension is the one in use")
        #expect(BroadcastHistory(fileURL: extensionProfile.historyURL).load().map(\.text) == ["hello from passive app"],
                "must record into the active extension's history")
        #expect(BroadcastHistory(fileURL: rig.appProfile.historyURL).load().isEmpty,
                "must not record into the passive app's history")
    }
}
