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
import VitruvianToolKit
import VitruvianToolProtocol

// The extension's own program, on its own engine (plan Task 12): what it
// does in each role the choice file gives it, when its chat monitor may
// run, the mark on the closed island, and that every part it is built from
// is the extension's own.
//
// Engines are on extension profiles in scratch folders, under message
// prefixes of their own (`test.<uuid>.homespeaker`). The app, its program,
// Google, the speakers and this Mac's speech and media are stand-ins:
// nothing here reaches this Mac's HomeSpeaker, its files or its home.

// MARK: - Scratch

private func scratchDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("homespeaker-door-role-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A message prefix no real app or extension on this Mac listens on.
private func testPrefix() -> String { "test.\(UUID().uuidString).homespeaker" }

// MARK: - Stand-ins

/// Everything one stand-in was asked, in order, from any thread.
private final class Calls<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.withLock { items.append(item) } }
    var all: [T] { lock.withLock { items } }
}

/// The app, as far as the extension asks: whether it is running. Anything
/// that would act on it fails the test.
private final class StandInApp: OtherAppControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    var isRunning: Bool {
        get { lock.withLock { running } }
        set { lock.withLock { running = newValue } }
    }
    var version: String? { "1.19.0" }
    func quit(timeout: Double) async -> Bool {
        XCTFail("asked the app to quit")
        return false
    }
    func turnOffLoginItem() async -> Result<Void, OtherAppProblem> {
        XCTFail("turned the app's login item off")
        return .failure(OtherAppProblem("no"))
    }
    func moveToTrash() throws -> URL {
        XCTFail("moved the app to the Trash")
        throw OtherAppError.notAnApp
    }
    func turnOnLoginItem() async -> Result<Void, OtherAppProblem> {
        XCTFail("turned the app's login item on")
        return .failure(OtherAppProblem("no"))
    }
    func open() async -> Bool {
        XCTFail("opened the app")
        return false
    }
}

/// A chat monitor that only records what it is asked.
private final class RecordingMonitor: ChatMonitorControlling {
    var isRunning = false
    var calls: [String] = []
    func start() {
        calls.append("start")
        isRunning = true
    }
    func stop() {
        calls.append("stop")
        isRunning = false
    }
}

/// A home speaker that records and answers sent.
private struct StandInHome: HomeBroadcasting {
    let calls: Calls<String>
    func broadcast(
        text: String, target: SpeakerDevice, structureId: String,
        config: SpeakerConfig?, force: Bool, at date: Date
    ) async throws -> Bool {
        calls.add(text)
        return true
    }
}

/// This Mac's speech, silent.
private struct SilentLocal: LocalSpeaking {
    func speak(_ text: String, voiceID: String) async throws {}
}

/// Media that is never paused: no message leaves the test.
private struct NoMediaPause: MediaPausing {
    func pause(seconds: Double) async {}
    func extend(seconds: Double) async {}
    func resumeNow() async {}
}

/// A speaker's volume and mute, remembered.
private final class StandInVolume: VolumeAndMuteControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var reading = SpeakerVolume(percent: 40, muted: false, online: true)
    func volume(of target: SpeakerDevice, structureId: String) async throws -> SpeakerVolume {
        lock.withLock { reading }
    }
    func setVolume(_ percent: Int, on target: SpeakerDevice, structureId: String) async throws {
        lock.withLock { reading.percent = percent }
    }
    func setMuted(_ muted: Bool, on target: SpeakerDevice, structureId: String) async throws {
        lock.withLock { reading.muted = muted }
    }
}

/// One home, one speaker.
private struct OneHome: HomeDiscovering {
    func listHomes() async throws -> [HomeStructure] { [HomeStructure(id: "h1", name: "Lake House")] }
    func discoverBroadcastTargets(structureId: String) async throws -> [String: SpeakerDevice] {
        ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen", room: "Kitchen")]
    }
}

private struct StandInFailure: LocalizedError {
    let words: String
    init(_ words: String) { self.words = words }
    var errorDescription: String? { words }
}

/// Google Chat, in this process: one space with no messages. Anything else
/// is answered 500, so a request that should not be made shows.
private final class StandInChat: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen: [URL] = []
    static var requests: [URL] { lock.withLock { seen } }

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StandInChat.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self.seen.append(url) }
        let isChat = url.host == "chat.googleapis.com"
        let body: String
        if isChat, url.path.hasSuffix("/messages") {
            body = #"{"messages":[]}"#
        } else if isChat, url.path == "/v1/spaces" {
            body = #"{"spaces":[{"name":"spaces/AAAA","displayName":"Team"}]}"#
        } else {
            body = "{}"
        }
        let response = HTTPURLResponse(
            url: url, statusCode: isChat ? 200 : 500, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - The tool in each role

@MainActor
final class DoorRoleTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Account = HomeSpeakerToolTests.Account

    private var root: URL!
    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var account: Account!
    private var app: StandInApp!
    private var door: DoorFile!
    private var role: DoorRole = .active
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var asked: [ChatMonitorAction] = []
    private var mayRun: [Bool] = []
    private var marks: [MarkChoice] = []

    override func setUpWithError() throws {
        root = try scratchDir()
        let root = self.root!
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        link = Link()
        store = Store()
        driver = Driver()
        account = Account()
        app = StandInApp()
        door = DoorFile(url: root.appendingPathComponent("home/.gemini").appendingPathComponent(DoorFile.fileName))
        role = .active
        asked = []
        mayRun = []
        marks = []
        var config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                                   targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
        config.effectiveChatMonitor.slackEnabled = true
        store.config = config
    }

    private func tool() -> HomeSpeakerTool {
        HomeSpeakerTool(parts: .init(
            link: link, store: store, driver: driver, later: { $0() }, now: { [unowned self] in now },
            account: account, historyURL: HomeSpeakerToolTests.noHistory,
            monitorStatusURL: root.appendingPathComponent("data/speaker_monitor_status.json"),
            controlChatMonitor: { [unowned self] in asked.append($0) },
            role: { [unowned self] in role }, other: app, door: door,
            sendStatus: { [unowned self] in marks.append($0) },
            monitorMayRun: { [unowned self] in mayRun.append($0) }))
    }

    private func choose(_ chosen: HomeSpeakerProfile.Door, at date: Date) throws {
        try door.update {
            $0.chosen = chosen
            $0.chosenAt = date
        }
    }

    private func texts(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en")
            default: return nil
            }
        }
    }

    static let quietWords = "The HomeSpeaker app is in use, so this one stays quiet"

    // MARK: Speaking by hand

    func testQuietRefusesSpeech() throws {
        role = .quiet(other: .app)
        let tool = tool()
        tool.start()
        _ = tool.islandPage()
        _ = tool.settingsPage()
        XCTAssertEqual(driver.jobs, [], "a quiet extension reads, speaks and signs in nothing by itself")

        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        XCTAssertEqual(tool.notice, Self.quietWords)
        link.clipboard = "read me"
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.sayClipboard)) {
            XCTAssertEqual(($0 as? CommandRefused)?.message, Self.quietWords)
        }
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.mute)) {
            XCTAssertEqual(($0 as? CommandRefused)?.message, Self.quietWords)
        }
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.signIn, kind: .tap))
        XCTAssertEqual(tool.setupNotice, Self.quietWords)
        XCTAssertEqual(driver.jobs, [], "nothing was run")
    }

    func testWaitingAllowsSpeechByHand() throws {
        role = .waitingAsking
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30)))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        XCTAssertEqual(driver.jobs.last, .say("dinner"), "a person's own request is not a duplicate")
        driver.answer(.spoke("sent to Kitchen"))
        try tool.run(command: HomeSpeakerTool.Command.mute)
        XCTAssertEqual(driver.jobs.last, .mute)
    }

    func testSayRefusesWhenNotSetUp() throws {
        store.config = SpeakerConfig(enabled: true)
        let tool = tool()
        link.clipboard = "read me"
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.sayClipboard)) {
            XCTAssertEqual(($0 as? CommandRefused)?.message, HomeSpeakerTool.notSetUp)
        }
        _ = tool.islandPage()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        XCTAssertEqual(tool.notice, HomeSpeakerTool.notSetUp.capitalizingFirstForTests)
        XCTAssertEqual(driver.jobs, [], "nothing asked of a HomeSpeaker with nowhere to speak")

        store.config?.effectiveSpeakLocal = true
        try tool.run(command: HomeSpeakerTool.Command.sayClipboard)
        XCTAssertEqual(driver.jobs.last, .say("read me"), "this Mac alone is somewhere to speak")
    }

    // MARK: The chat monitor

    func testTheMonitorStartsOnlyWhenActive() throws {
        role = .waitingAsking
        let tool = tool()
        tool.start()
        tool.refreshRole()
        role = .quiet(other: .app)
        tool.refreshRole()
        XCTAssertEqual(asked, [], "neither waiting nor quiet starts the monitor")
        XCTAssertEqual(mayRun, [])
        role = .active
        tool.refreshRole()
        XCTAssertEqual(asked, [.start])
        XCTAssertEqual(mayRun, [true])
        tool.refreshRole()
        XCTAssertEqual(asked, [.start], "asked once")
    }

    func testAnActiveSideWithEverySourceOffStartsNothing() throws {
        store.config?.effectiveChatMonitor.slackEnabled = false
        let tool = tool()
        tool.start()
        XCTAssertEqual(mayRun, [true], "it may run")
        XCTAssertEqual(asked, [], "but there is nothing to read")
    }

    func testTheMonitorWaitsForTheOtherToStop() throws {
        try choose(.extension, at: now)
        app.isRunning = true
        let tool = tool()
        tool.start()
        XCTAssertEqual(asked, [], "the app is still running its own")
        now += 2
        tool.refreshRole()
        XCTAssertEqual(asked, [])
        app.isRunning = false
        tool.refreshRole()
        XCTAssertEqual(asked, [.start], "it starts once the app has quit")

        // An app that never quits: after five seconds it starts anyway.
        asked = []
        try choose(.extension, at: now)
        app.isRunning = true
        let stubborn = self.tool()
        stubborn.start()
        now += 4
        stubborn.refreshRole()
        XCTAssertEqual(asked, [])
        now += 1
        stubborn.refreshRole()
        XCTAssertEqual(asked, [.start], "five seconds after the choice it starts anyway")
    }

    func testTheMonitorStopsWhenTheAppIsChosen() throws {
        let tool = tool()
        tool.start()
        XCTAssertEqual(asked, [.start])
        role = .quiet(other: .app)
        tool.refreshRole()
        XCTAssertEqual(asked, [.start, .stop])
        XCTAssertEqual(mayRun, [true, false])
    }

    func testStartIsRefusedWhileQuietOrWaiting() throws {
        role = .quiet(other: .app)
        let tool = tool()
        _ = tool.settingsPage()
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string(Pages.Section.monitor.rawValue)))
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.startChatMonitor, kind: .tap))
        XCTAssertEqual(tool.setupNotice, "The HomeSpeaker app is in use, so its monitor is the one that runs")
        role = .waitingAsking
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.startChatMonitor, kind: .tap))
        XCTAssertEqual(tool.setupNotice, HomeSpeakerTool.pickFirst)
        XCTAssertEqual(asked, [])
    }

    // MARK: The mark

    func testTheMarkFollowsTheRole() throws {
        link.features = [.status]
        let tool = tool()
        tool.start()
        XCTAssertEqual(marks.last, MarkChoice(state: .ok, icon: "dot.radiowaves.left.and.right", text: "Broadcasting to Kitchen"))
        role = .waitingAsking
        tool.refreshRole()
        XCTAssertEqual(marks.last, MarkChoice(state: .attention, icon: "exclamationmark.circle", text: "Pick which HomeSpeaker to use"))
        role = .quiet(other: .app)
        tool.refreshRole()
        XCTAssertEqual(marks.last, MarkChoice(state: .none))
        let sent = marks.count
        tool.refreshRole()
        XCTAssertEqual(marks.count, sent, "an unchanged mark is not sent again")
        role = .active
        tool.refreshRole()
        XCTAssertEqual(marks.last?.text, "Broadcasting to Kitchen")
    }

    func testNoStatusForAnAppWithoutTheFeature() throws {
        link.features = []
        let tool = tool()
        tool.start()
        role = .waitingAsking
        tool.refreshRole()
        _ = tool.islandPage()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.broadcasting, kind: .toggle, value: .bool(false)))
        XCTAssertEqual(marks, [], "an app before 3.48 is sent no ui/status")
    }

    func testTheMarksSetUpIsASignInASpeakerOrThisMac() throws {
        store.config = SpeakerConfig(enabled: true)
        let tool = tool()
        _ = tool.islandPage()
        XCTAssertFalse(tool.statusInputs().setUp, "no sign-in, no speaker, this Mac off")
        account.isSignedIn = true
        XCTAssertTrue(tool.statusInputs().setUp, "a sign-in")
        account.isSignedIn = false
        store.config?.effectiveSpeakLocal = true
        _ = tool.islandPage()
        XCTAssertTrue(tool.statusInputs().setUp, "this Mac on")
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
        _ = tool.islandPage()
        XCTAssertTrue(tool.statusInputs().setUp, "a speaker")
    }
}

extension String {
    /// The page's capitalization of a refusal, for comparing.
    var capitalizingFirstForTests: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - The extension's own parts

@MainActor
final class ExtensionPartsTests: XCTestCase {
    /// The extension's engine and the parts built on it, all in `root`.
    private struct Rig {
        let root: URL
        let home: URL
        let profile: HomeSpeakerProfile
        let engine: HomeSpeakerEngine
        let monitor: RecordingMonitor
        let gate: GatedMonitor
        let parts: HomeSpeakerTool.Parts
        let program: URL
        let ran: Calls<[String]>
        let broadcasts: Calls<String>
    }

    static let program = "Tools/dev.vitruvian.homespeaker/bin/tool"
    /// Where the app would be. Nothing is there, and nothing may run it.
    static let appProgram = URL(fileURLWithPath: "/nonexistent/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")

    private func rig(
        appInstalled: Bool = false, holdsLiveLock: Bool = true, session: URLSession = StandInChat.session
    ) throws -> Rig {
        let root = try scratchDir()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini"), withIntermediateDirectories: true)
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("ToolData/dev.vitruvian.homespeaker"),
            toolFolder: root.appendingPathComponent("Tools/dev.vitruvian.homespeaker"), messagePrefix: testPrefix())
        for url in [profile.settingsURL, profile.historyURL, profile.secretsURL, profile.monitorStatusURL] {
            guard url.path.hasPrefix(root.path + "/") else { throw StandInFailure("\(url.path) is outside the scratch folder") }
        }
        let engine = HomeSpeakerEngine(profile: profile, session: session, local: SilentLocal())
        var config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "h1",
                                   targets: ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen")])
        config.pauseMedia = false
        engine.config.config = config
        try engine.config.trySaveConfig()

        let broadcasts = Calls<String>()
        var driverParts = EngineDriver.Parts(engine: engine, otherSecrets: { nil })
        driverParts.announcer = Announcer(home: StandInHome(calls: broadcasts), local: SilentLocal(), media: NoMediaPause())
        driverParts.speaker = StandInVolume()
        driverParts.homes = OneHome()
        driverParts.signIn = { _, _ in throw StandInFailure("no sign-in in this test") }
        driverParts.browser = { _ in XCTFail("opened this Mac's browser") }
        driverParts.signedIn = {}
        driverParts.signedOut = { _ in }

        let monitor = RecordingMonitor()
        let gate = GatedMonitor(monitor)
        let check = DoorCheck(
            file: DoorFile(url: DoorFile.defaultURL(home: home)), appInstalled: { appInstalled },
            fileExists: { _ in false })
        let ran = Calls<[String]>()
        let program = root.appendingPathComponent(Self.program)
        let parts = HomeSpeakerTool.Parts.extension(
            // A job's end waits for the main queue, so it never lands
            // while a test is reading the tool.
            engine: engine, program: program, link: HomeSpeakerToolTests.Link(),
            later: { work in DispatchQueue.main.async(execute: work) },
            driverParts: driverParts, monitor: gate, holdsLiveLock: holdsLiveLock, check: check,
            appProgram: { Self.appProgram },
            appProfile: HomeSpeakerProfile(
                door: .app, settingsURL: home.appendingPathComponent(".gemini/speaker_broadcast.json"),
                historyURL: home.appendingPathComponent(".gemini/speaker_history.json"),
                secretsURL: root.appendingPathComponent("app-secrets.json"), messagePrefix: testPrefix(),
                liveLockURL: nil, toolFolder: nil),
            runningApps: { [] },
            runProgram: { program, arguments in
                ran.add([program.path] + arguments)
                return ProgramRun(status: 1, output: "", error: "error: the test's stand-in never runs the app")
            },
            openApp: { _ in
                XCTFail("opened the app")
                return false
            },
            home: home, onMain: { work in MainActor.assumeIsolated { work() } })
        return Rig(root: root, home: home, profile: profile, engine: engine, monitor: monitor, gate: gate,
                   parts: parts, program: program, ran: ran, broadcasts: broadcasts)
    }

    private func answer(_ driver: SpeakerDriver, _ job: Job) async -> JobResult? {
        let answers = Calls<JobResult>()
        let answered = expectation(description: "\(job) answered")
        answered.assertForOverFulfill = false
        driver.run(job) {
            answers.add($0)
            answered.fulfill()
        }
        await fulfillment(of: [answered], timeout: 10)
        return answers.all.first
    }

    func testEveryPartUsesTheProfile() async throws {
        let rig = try rig()
        let parts = rig.parts
        let profile = rig.profile
        XCTAssertEqual(parts.settingsURL, profile.settingsURL)
        XCTAssertEqual(parts.secretsURL, profile.secretsURL)
        XCTAssertEqual(parts.historyURL, profile.historyURL)
        XCTAssertEqual(parts.monitorStatusURL, profile.monitorStatusURL)
        XCTAssertEqual(parts.home, rig.home, "the agents' files are the home's")
        let gemini = rig.home.appendingPathComponent(".gemini").path + "/"
        for url in [parts.settingsURL, parts.secretsURL, parts.historyURL, parts.monitorStatusURL] {
            XCTAssertFalse(url.path.hasPrefix(gemini), "\(url.path) is the app's folder")
            XCTAssertTrue(url.path.hasPrefix(rig.root.path + "/"), "\(url.path) is not the extension's")
        }
        XCTAssertEqual((parts.store as? FileConfigStore)?.url, profile.settingsURL, "the settings are the extension's")
        let account = try XCTUnwrap(parts.account as? SecretStoreAccount)
        XCTAssertTrue(account.store === rig.engine.secrets, "the sign-in is the engine's, not .shared")
        XCTAssertEqual(account.profile, profile, "the shipped client is the extension's")
        let chat = try XCTUnwrap(parts.chat as? SecretStoreChatCredentials)
        XCTAssertTrue(chat.store === rig.engine.secrets, "Slack and Chat are the engine's, not .shared")
        let driver = try XCTUnwrap(parts.driver as? EngineDriver)
        XCTAssertEqual(driver.program, rig.program, "hooks run the extension's own program")
        XCTAssertEqual(parts.door?.url, DoorFile.defaultURL(home: rig.home))
        XCTAssertFalse(parts.ownerRunning(), "nothing holds this side's lock yet")
        let lock = try LiveLock.hold(at: try XCTUnwrap(profile.liveLockURL))
        XCTAssertTrue(parts.ownerRunning(), "this side's own lock")
        lock.release()

        // Credentials changed: told under the extension's own name.
        let heard = expectation(description: "credentials-changed under the profile's name")
        let token = CredentialsChangedNotice.listen(name: profile.messageName(.credentialsChanged)) { heard.fulfill() }
        defer { DistributedNotificationCenter.default().removeObserver(token) }
        parts.credentialsChanged()
        await fulfillment(of: [heard], timeout: 5)
    }

    func testNoJobStartsTheAppsProgram() async throws {
        let rig = try rig(appInstalled: true)
        let jobs: [Job] = [
            .say("dinner is ready"), .volume, .setVolume(30), .mute, .unmute,
            .app(.discover(save: false, home: nil)), .app(.discover(save: true, home: "h1")),
            .app(.loginItem(.status)), .app(.loginItem(.disable)),
            .signIn(chatOnly: false), .app(.signOut(chatOnly: true)),
        ]
        for job in jobs {
            let result = await answer(rig.parts.driver, job)
            XCTAssertNotNil(result, "\(job) answered")
        }
        XCTAssertEqual(rig.ran.all, [], "a job started the app's program")
        XCTAssertEqual(rig.broadcasts.all, ["dinner is ready"], "spoken in this process")
    }

    func testStartAndStopRunInThisProcess() throws {
        let rig = try rig()
        rig.engine.config.config.effectiveChatMonitor.slackEnabled = true
        try rig.engine.config.trySaveConfig()
        let tool = HomeSpeakerTool(parts: rig.parts)
        tool.start()
        XCTAssertEqual(rig.monitor.calls, ["start"], "active, with a source on: started here")
        _ = tool.settingsPage()
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string(Pages.Section.monitor.rawValue)))
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.stopChatMonitor, kind: .tap))
        XCTAssertEqual(rig.monitor.calls, ["start", "stop"], "Stop stops this process's monitor")
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.startChatMonitor, kind: .tap))
        XCTAssertEqual(rig.monitor.calls, ["start", "stop", "start"], "Start starts it")
    }

    func testAProcessWithoutTheLockNeverReadsChat() async throws {
        let rig = try rig(holdsLiveLock: false)
        rig.engine.config.config.effectiveChatMonitor.slackEnabled = true
        try rig.engine.config.trySaveConfig()
        let tokens = ExtensionSide.watch(engine: rig.engine, monitor: rig.gate)
        defer {
            rig.engine.config.stopWatchingConfigFile()
            tokens.forEach(DistributedNotificationCenter.default().removeObserver)
        }
        let tool = HomeSpeakerTool(parts: rig.parts)
        tool.start()
        XCTAssertEqual(tool.role, .active, "the role alone would let it run")
        XCTAssertFalse(rig.gate.permission.value, "a second process, without the lock, may not read chat")
        _ = tool.settingsPage()
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string(Pages.Section.monitor.rawValue)))
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.startChatMonitor, kind: .tap))
        ChatMonitorControlNotice.post(.start, name: rig.profile.messageName(.chatMonitorControl))
        tool.refreshRole()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(rig.monitor.calls, [], "the process without the lock started its monitor")

        // Control: the same, holding the lock, starts it.
        let holder = try self.rig(holdsLiveLock: true)
        holder.engine.config.config.effectiveChatMonitor.slackEnabled = true
        try holder.engine.config.trySaveConfig()
        HomeSpeakerTool(parts: holder.parts).start()
        XCTAssertEqual(holder.monitor.calls, ["start"])
    }

    func testAQuietSideIgnoresSettingsAndNotices() async throws {
        let rig = try rig()
        let profile = rig.profile
        let tokens = ExtensionSide.watch(engine: rig.engine, monitor: rig.gate)
        defer {
            rig.engine.config.stopWatchingConfigFile()
            tokens.forEach(DistributedNotificationCenter.default().removeObserver)
        }
        XCTAssertTrue(rig.engine.config.chatMonitor === rig.gate, "the settings watcher reaches the gate")
        XCTAssertFalse(rig.gate.permission.value, "nothing may start until the role says so")

        // The settings, changed on disk by someone else: a source switched on.
        func switchSlack(_ on: Bool) throws {
            let file = FileConfigStore(url: profile.settingsURL)
            var changed = try XCTUnwrap(file.load())
            changed.effectiveChatMonitor.slackEnabled = on
            try file.save(changed)
            rig.engine.config.reloadIfChangedExternally()
        }
        try switchSlack(true)
        CredentialsChangedNotice.post(name: profile.messageName(.credentialsChanged))
        ChatMonitorControlNotice.post(.start, name: profile.messageName(.chatMonitorControl))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(rig.monitor.calls, [], "a side that may not run starts nothing")

        // The same paths, once it may.
        rig.gate.permission.set(true)
        ChatMonitorControlNotice.post(.start, name: profile.messageName(.chatMonitorControl))
        for _ in 0..<100 where rig.monitor.calls.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(rig.monitor.calls, ["start"], "the control message starts it once it may")
        try switchSlack(false)
        XCTAssertEqual(rig.monitor.calls, ["start", "stop"], "stopping is never held back")
    }

    func testTheStatusFileIsTheExtensions() async throws {
        let rig = try rig()
        let engine = rig.engine
        try engine.secrets.save(Secrets(googleChat: GoogleCredentials(
            clientId: "test-client", clientSecret: "test-secret",
            accessToken: "test-token-\(UUID().uuidString)", refreshToken: "test-refresh",
            expiry: Date().addingTimeInterval(86_400),
            scopes: GoogleAuth.identityScopes + GoogleAuth.chatScopes,
            userId: "1234567890", email: "extension@example.test")))
        engine.config.config.effectiveChatMonitor = ChatMonitorConfig(
            slackEnabled: false, googleChatEnabled: true, googleChatSource: .api)
        let monitor = ExtensionSide.chatMonitor(engine: engine, chatSession: StandInChat.session)
        monitor.start()
        defer { monitor.stop() }
        let statusURL = rig.profile.monitorStatusURL
        for _ in 0..<200 where ChatMonitorStatusFile(url: statusURL).read()?.lastPollDate == nil {
            try await Task.sleep(for: .milliseconds(25))
        }
        let status = try XCTUnwrap(ChatMonitorStatusFile(url: statusURL).read(), "the extension's status file was not written")
        XCTAssertTrue(status.isRunning)
        XCTAssertNotNil(status.lastPollDate, "it polled")
        XCTAssertEqual(statusURL.deletingLastPathComponent(), rig.profile.settingsURL.deletingLastPathComponent())
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: rig.home.appendingPathComponent(".gemini/speaker_monitor_status.json").path),
            "nothing written to the home's .gemini")
    }

    func testTheDoorEntryIsTheExtensionsAndLeavesTheChoiceAlone() throws {
        let rig = try rig()
        let door = DoorFile(url: DoorFile.defaultURL(home: rig.home))
        try door.update {
            $0.chosen = .app
            $0.chosenBy = "HomeSpeaker 1.19.0"
        }
        try ExtensionSide.recordInDoor(door, program: rig.program, profile: rig.profile)
        let record = try XCTUnwrap(door.read())
        XCTAssertEqual(record.chosen, .app, "the app's choice is not the extension's to change")
        XCTAssertEqual(record.chosenBy, "HomeSpeaker 1.19.0")
        XCTAssertEqual(record.installedExtension, DoorRecord.ExtensionEntry(
            program: rig.program.path, dataFolder: rig.profile.settingsURL.deletingLastPathComponent().path,
            version: ToolVersion.current, door: DoorRecord.ExtensionEntry.runsAlone))
    }
}

// MARK: - The extension's command line

/// Google, in this process: answers every request 200 and keeps each body,
/// so a sign-out's revoke is seen and never leaves this Mac.
private final class RevokeRecorder: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String] = []

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RevokeRecorder.self]
        return URLSession(configuration: configuration)
    }

    /// `token` holds no character a form encodes, so it is found as is.
    static func revoked(_ token: String) -> Bool {
        lock.withLock { bodies.contains { $0.contains(token) } }
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

/// `bin/tool --sign-out`, wired as `main.swift` wires it
/// (`ExtensionSide.commandLineParts`): the mirror of the app's
/// `theCommandLineSignOutNeverRevokesASharedLogin`.
@MainActor
final class ExtensionCommandLineTests: XCTestCase {
    func testTheCommandLineSignOutNeverRevokesALoginTheAppShares() async throws {
        let root = try scratchDir()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let profile = HomeSpeakerProfile.extension(
            dataFolder: root.appendingPathComponent("ToolData/dev.vitruvian.homespeaker"),
            toolFolder: root.appendingPathComponent("Tools/dev.vitruvian.homespeaker"), messagePrefix: testPrefix())
        // The app's sign-ins, beside the extension's, in the scratch folder.
        let appSecretsURL = root.appendingPathComponent("home/.gemini/speaker_secrets.json")
        try FileManager.default.createDirectory(
            at: appSecretsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let appInstalled = Calls<Bool>()
        appInstalled.add(true)
        let check = DoorCheck(
            file: DoorFile(url: root.appendingPathComponent("home/.gemini").appendingPathComponent(DoorFile.fileName)),
            appInstalled: { appInstalled.all.last ?? false }, fileExists: { _ in false })

        let id = UUID().uuidString
        let shared = GoogleCredentials(
            clientId: "shipped.apps.googleusercontent.test", clientSecret: "made-up-\(id)", // gitleaks:allow (made-up test token)
            accessToken: "made-up-ext-access-\(id)", refreshToken: "made-up-ext-refresh-\(id)", // gitleaks:allow (made-up test token)
            scopes: [GoogleAuth.homeScope], userId: "1234", email: "person@example.test")
        // The copy left the same login on both sides.
        try SecretStore(fileURL: appSecretsURL).save(Secrets(google: shared))
        let theirs = try Data(contentsOf: appSecretsURL)
        let engine = HomeSpeakerEngine(profile: profile, session: RevokeRecorder.session, local: SilentLocal())
        try engine.secrets.save(Secrets(google: shared))
        let posted = Calls<String>()
        let parts = ExtensionSide.commandLineParts(
            check: check, appSecretsURL: appSecretsURL,
            postSignedOut: { chatOnly, name in posted.add("\(name.rawValue) \(chatOnly)") })

        func signOut() async -> CLIOutput {
            guard case .headless(_, _, let body) = HomeSpeakerCommandLine.action(
                for: ["--sign-out"], engine: engine, parts: parts) else {
                XCTFail("--sign-out does not run headless")
                return CLIOutput()
            }
            return await body()
        }

        // The app is installed and holds the same login: removed here only.
        let quiet = await signOut()
        XCTAssertEqual(quiet, CLIOutput(stdout: ["signed out of Google (Home and Chat)"]))
        XCTAssertNil(engine.secrets.load().google, "still signed in here")
        XCTAssertFalse(RevokeRecorder.revoked(shared.refreshToken),
                       "the extension's --sign-out revoked the app's login at Google")
        XCTAssertEqual(try Data(contentsOf: appSecretsURL), theirs, "the app's sign-ins changed")
        XCTAssertEqual(posted.all, ["\(profile.messagePrefix).signed-out false"], "told under the extension's names")

        // Control: no app, the same lines, and the login revoked.
        appInstalled.add(false)
        var alone = shared
        alone.refreshToken = "made-up-ext-alone-\(id)" // gitleaks:allow (made-up test token)
        try engine.secrets.save(Secrets(google: alone))
        let lone = await signOut()
        XCTAssertEqual(lone, CLIOutput(stdout: ["signed out of Google (Home and Chat)"]))
        XCTAssertTrue(RevokeRecorder.revoked(alone.refreshToken),
                      "the stand-in never saw a revoke, so the check above proves nothing")
    }
}

// MARK: - Where the extension's files are

final class ExtensionLocationTests: XCTestCase {
    private let installed = URL(fileURLWithPath: "/Users/someone/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker/bin/tool")
    private let built = URL(fileURLWithPath: "/private/var/scratch/homespeaker/bin/tool")

    func testTheVariableComesFirst() throws {
        let located = try XCTUnwrap(ExtensionLocation.locate(
            environment: [ExtensionLocation.dataFolderVariable: "/tmp/hs-data"], program: installed,
            workingDirectory: URL(fileURLWithPath: "/elsewhere")))
        XCTAssertEqual(located.profile.settingsURL.path, "/tmp/hs-data/settings.json")
        XCTAssertEqual(located.source, .variable)
        XCTAssertEqual(located.profile.door, .extension)
        XCTAssertEqual(located.profile.messagePrefix, HomeSpeakerProfile.extensionMessagePrefix)
    }

    func testThenTheProgramsOwnPath() throws {
        let located = try XCTUnwrap(ExtensionLocation.locate(environment: [:], program: installed, workingDirectory: nil))
        XCTAssertEqual(located.profile.settingsURL.path,
                       "/Users/someone/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.homespeaker/settings.json")
        XCTAssertEqual(located.profile.toolFolder?.path,
                       "/Users/someone/Library/Application Support/Vitruvian/Tools/dev.vitruvian.homespeaker")
        XCTAssertEqual(located.source, .programPath)
    }

    func testThenTheFolderVitruvianStartedItIn() throws {
        XCTAssertNil(ExtensionLocation.locate(environment: [:], program: built, workingDirectory: nil),
                     "the command line has no hello: it refuses")
        let located = try XCTUnwrap(ExtensionLocation.locate(
            environment: [:], program: built, workingDirectory: URL(fileURLWithPath: "/tmp/given")))
        XCTAssertEqual(located.profile.settingsURL.path, "/tmp/given/settings.json")
        XCTAssertEqual(located.profile.toolFolder?.path, "/private/var/scratch/homespeaker", "the program's grandparent")
        XCTAssertEqual(located.source, .workingDirectory)
    }

    func testATestsMessagePrefixIsKept() throws {
        let located = try XCTUnwrap(ExtensionLocation.locate(
            environment: [ExtensionLocation.dataFolderVariable: "/tmp/hs-data",
                          ExtensionLocation.messagePrefixVariable: "test.abc.homespeaker"],
            program: built, workingDirectory: nil))
        XCTAssertEqual(located.profile.messagePrefix, "test.abc.homespeaker")
    }

    func testAFolderThatIsNotTheHellosIsRefused() throws {
        let fromPath = try XCTUnwrap(ExtensionLocation.locate(environment: [:], program: installed, workingDirectory: nil))
        XCTAssertNil(fromPath.refusal(helloFolder: URL(fileURLWithPath:
            "/Users/someone/Library/Application Support/Vitruvian/ToolData/dev.vitruvian.homespeaker", isDirectory: true)))
        let refusal = try XCTUnwrap(fromPath.refusal(helloFolder: URL(fileURLWithPath: "/Users/someone/Other")))
        XCTAssertTrue(refusal.contains("/Users/someone/Other"), refusal)
        let fromVariable = try XCTUnwrap(ExtensionLocation.locate(
            environment: [ExtensionLocation.dataFolderVariable: "/tmp/hs-data"], program: installed, workingDirectory: nil))
        XCTAssertNil(fromVariable.refusal(helloFolder: URL(fileURLWithPath: "/Users/someone/Other")),
                     "a folder named on purpose is the one used")
    }
}
