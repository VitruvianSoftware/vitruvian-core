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

// Guards for the shared-foundation fixes: the config file is never clobbered
// and keeps other writers' keys, hooks point at the app, the "spoken twice"
// warning belongs to Claude Code, an external edit reaches the chat monitor,
// and the app-identity CLI flags parse and run as documented.

/// The disk, in memory: records every write and can be told to fail a read.
final class MemoryFiles: ConfigFileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private(set) var writes = 0
    var readError: Error?

    subscript(url: URL) -> Data? {
        get { lock.withLock { files[url.path] } }
        set { lock.withLock { files[url.path] = newValue } }
    }

    func text(_ url: URL) -> String? { self[url].map { String(decoding: $0, as: UTF8.self) } }
    func object(_ url: URL) -> [String: Any] {
        (self[url].flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
    }

    func read(_ url: URL) throws -> Data? {
        if let readError { throw readError }
        return self[url]
    }

    func write(_ data: Data, to url: URL) throws {
        lock.withLock { writes += 1 }
        self[url] = data
    }
}

private let configURL = URL(fileURLWithPath: "/fake/.gemini/speaker_broadcast.json")

private func put(_ files: MemoryFiles, _ text: String) { files[configURL] = Data(text.utf8) }

/// A file as the Android remote's macagent might leave it: keys this app
/// does not know at the top, inside chat_monitor, and on a speaker.
private let foreignFile = """
{
  "enabled": true,
  "default_target": "kitchen",
  "structure_id": "s1",
  "targets": {
    "kitchen": {"id": "d1", "type": "SPEAKER", "name": "Kitchen", "phone_icon": "speaker"},
    "office": {"id": "d2", "type": "SPEAKER", "name": "Office"}
  },
  "chat_monitor": {"slack_enabled": false, "phone_only_setting": 7},
  "macagent_version": "2.1",
  "remote": {"paired": true, "devices": ["pixel"]},
  "speech_length": "full"
}
"""

@Suite struct SpeakerConfigFileTests {
    @Test func unknownKeysSurviveASaveAtEveryLevel() throws {
        let files = MemoryFiles()
        put(files, foreignFile)
        let file = SpeakerConfigFile(url: configURL, fileSystem: files)
        guard case .loaded(var config) = file.read() else { Issue.record("fixture must load"); return }
        config.defaultTarget = "office"
        config.effectiveChatMonitor.slackEnabled = true
        config.speechLength = nil
        try file.write(config)

        let disk = files.object(configURL)
        #expect(disk["macagent_version"] as? String == "2.1", "a top-level key this app does not know survives")
        #expect((disk["remote"] as? [String: Any])?["paired"] as? Bool == true, "nested foreign objects survive whole")
        let monitor = disk["chat_monitor"] as? [String: Any]
        #expect(monitor?["phone_only_setting"] as? Int == 7, "a foreign key inside chat_monitor survives")
        #expect(monitor?["slack_enabled"] as? Bool == true, "and ours inside it changed")
        let kitchen = (disk["targets"] as? [String: Any])?["kitchen"] as? [String: Any]
        #expect(kitchen?["phone_icon"] as? String == "speaker", "a foreign field on a speaker survives")
        #expect(disk["default_target"] as? String == "office")
        #expect(disk["speech_length"] == nil, "a key of ours set to nil is removed, as a whole-file write did")
        // And the result still reads as a config.
        guard case .loaded(let back) = file.read() else { Issue.record("must read back"); return }
        #expect(back == config)
    }

    @Test func aSpeakerThisAppDroppedStaysDropped() throws {
        let files = MemoryFiles()
        put(files, foreignFile)
        let file = SpeakerConfigFile(url: configURL, fileSystem: files)
        guard case .loaded(var config) = file.read() else { Issue.record("fixture must load"); return }
        config.targets.removeValue(forKey: "office")
        try file.write(config)
        let targets = files.object(configURL)["targets"] as? [String: Any]
        #expect(targets?["office"] == nil, "targets is a map, not a record: a removed alias must not come back")
        #expect(targets?["kitchen"] != nil)
    }

    @Test func oldAndForeignKeysStayReadable() {
        let files = MemoryFiles()
        // A config from before most optional keys existed, plus a key from an older tool.
        put(files, #"{"enabled":false,"default_target":"","structure_id":"","targets":{},"legacy_room":"Kitchen"}"#)
        guard case .loaded(let config) = SpeakerConfigFile(url: configURL, fileSystem: files).read() else {
            Issue.record("an old config must still load"); return
        }
        #expect(config.enabled == false)
        #expect(config.effectiveSpeakHome, "absent keys read through their defaults")
    }

    @Test func aMissingFileIsWritten() throws {
        let files = MemoryFiles()
        let file = SpeakerConfigFile(url: configURL, fileSystem: files)
        #expect(file.read() == .missing)
        try file.write(SpeakerConfig(defaultTarget: "kitchen"))
        #expect(files.text(configURL)?.contains("\"default_target\" : \"kitchen\"") == true, "pretty, as the app writes it")
    }

    @Test(arguments: [
        "not json at all",
        "[1, 2, 3]",
        #"{"enabled": "yes", "default_target": "", "structure_id": "", "targets": {}}"#,
        #"{"enabled": true}"#,
    ])
    func aFileThatDoesNotReadIsNeverWrittenOver(_ text: String) {
        let files = MemoryFiles()
        put(files, text)
        let file = SpeakerConfigFile(url: configURL, fileSystem: files)
        guard case .unreadable = file.read() else { Issue.record("\(text) must not read as a config"); return }
        #expect(throws: ConfigFileError.self) { try file.write(SpeakerConfig()) }
        #expect(files.writes == 0)
        #expect(files.text(configURL) == text, "the file is exactly as it was")
    }

    @Test func aFileThatCannotBeOpenedIsNeverWrittenOver() {
        let files = MemoryFiles()
        put(files, foreignFile)
        files.readError = CocoaError(.fileReadNoPermission)
        let file = SpeakerConfigFile(url: configURL, fileSystem: files)
        guard case .unreadable = file.read() else { Issue.record("must be unreadable"); return }
        #expect(throws: ConfigFileError.self) { try file.write(SpeakerConfig()) }
        #expect(files.writes == 0)
    }

    @Test func twoWritersBothLand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("speaker_broadcast.json")
        let file = SpeakerConfigFile(url: url)
        try file.write(SpeakerConfig(defaultTarget: "initial"))

        #expect(file.lockURL.lastPathComponent == "speaker_broadcast.json.lock")
        #expect(FileManager.default.fileExists(atPath: file.lockURL.path))

        let writers = 32
        let start = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let failures = Failures()
        for i in 0..<writers {
            group.enter()
            Thread {
                defer { group.leave() }
                start.wait()
                do {
                    try SpeakerConfigFile(url: url).modify { cfg in
                        usleep(1_000)
                        cfg.targets["target_\(i)"] = SpeakerDevice(id: "id_\(i)", type: "SPEAKER", name: "Speaker \(i)")
                    }
                } catch {
                    failures.add("\(i): \(error)")
                }
            }.start()
        }
        for _ in 0..<writers { start.signal() }
        group.wait()

        #expect(failures.all.isEmpty)
        guard case .loaded(let finalConfig) = file.read() else {
            Issue.record("Config must load")
            return
        }
        #expect(finalConfig.defaultTarget == "initial")
        let landed = (0..<writers).filter { finalConfig.targets["target_\($0)"] != nil }
        #expect(landed.count == writers, "every writer's target landed; \(writers - landed.count) were lost")
    }

    @Test func applyDiscoveryWithEmptyTargetsPreservesSavedTargetsAndDefault() {
        var config = SpeakerConfig()
        let device = SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen")
        config.targets = ["kitchen": device]
        config.defaultTarget = "kitchen"
        config.structureId = "home1"
        config.structureName = "Main Home"

        let changed = config.applyDiscovery(structureId: "home1", structureName: "Main Home", targets: [:])
        #expect(!changed)
        #expect(config.targets == ["kitchen": device])
        #expect(config.defaultTarget == "kitchen")
        #expect(config.structureId == "home1")
        #expect(config.structureName == "Main Home")

        let changedOther = config.applyDiscovery(structureId: "other_home", structureName: "Other", targets: [:])
        #expect(!changedOther)
        #expect(config.targets == ["kitchen": device])
        #expect(config.defaultTarget == "kitchen")
        #expect(config.structureId == "home1")
        #expect(config.structureName == "Main Home")
    }
}

/// Failures collected from several threads.
private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.lock(); items.append(item); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

/// Records what the config manager asked of the chat monitor.
@MainActor
final class FakeChatMonitor: ChatMonitorControlling {
    var isRunning: Bool
    var calls: [String] = []
    init(running: Bool) { isRunning = running }
    func start() { calls.append("start"); isRunning = true }
    func stop() { calls.append("stop"); isRunning = false }
}

@MainActor
private func manager(_ files: MemoryFiles) -> ConfigManager {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-foundation-\(UUID().uuidString)")
    return ConfigManager(
        configPath: configURL,
        historyPath: scratch.appendingPathComponent("history.json"),
        secrets: SecretStore(fileURL: scratch.appendingPathComponent("secrets.json")),
        fileSystem: files)
}

@MainActor
@Suite struct ConfigManagerSafetyTests {
    @Test func aFailedLoadNeverWritesTheDefaults() {
        let files = MemoryFiles()
        put(files, "{ this is not json")
        let m = manager(files)
        #expect(m.configProblem != nil, "the failure is surfaced, not just printed")
        #expect(m.config == SpeakerConfig(), "the defaults stay in memory")
        m.toggleEnabled()
        m.setTarget("kitchen")
        #expect(!m.saveConfig())
        #expect(throws: ConfigFileError.self) { try m.trySaveConfig() }
        #expect(files.writes == 0, "nothing was written over the file")
        #expect(files.text(configURL) == "{ this is not json")
    }

    @Test func aMissingFileIsCreatedWithTheDefaults() {
        let files = MemoryFiles()
        let m = manager(files)
        #expect(m.configProblem == nil)
        #expect(files.writes == 1)
    }

    @Test func aSaveKeepsKeysOtherWritersOwn() {
        let files = MemoryFiles()
        put(files, foreignFile)
        let m = manager(files)
        m.setTarget("office")
        let disk = files.object(configURL)
        #expect(disk["macagent_version"] as? String == "2.1")
        #expect(disk["default_target"] as? String == "office")
    }

    @Test func aFileBrokenAfterLaunchIsNotWrittenOverAndAFixedOneIsFollowed() {
        let files = MemoryFiles()
        put(files, foreignFile)
        let m = manager(files)
        let writes = files.writes
        put(files, "broken by hand")
        m.reloadIfChangedExternally()
        #expect(m.configProblem != nil)
        #expect(m.config.defaultTarget == "kitchen", "the last good settings stay in memory")
        m.setTarget("office")
        #expect(files.writes == writes)
        #expect(files.text(configURL) == "broken by hand")

        put(files, foreignFile.replacingOccurrences(of: "\"default_target\": \"kitchen\"", with: "\"default_target\": \"office\""))
        m.reloadIfChangedExternally()
        #expect(m.configProblem == nil, "the problem clears once the file reads")
        #expect(m.config.defaultTarget == "office")
        #expect(m.saveConfig())
    }

    @Test func aFileBrokenBetweenWatcherEventsStillRefusesTheSave() {
        let files = MemoryFiles()
        put(files, foreignFile)
        let m = manager(files)
        put(files, "broken before the watcher fired")
        // No reload: the write itself checks what is on disk.
        #expect(!m.saveConfig())
        #expect(m.configProblem != nil)
        #expect(files.text(configURL) == "broken before the watcher fired")
    }
}

@MainActor
@Suite struct ExternalReloadChatMonitorTests {
    private func edit(_ files: MemoryFiles, slack: Bool, chat: Bool, interval: Int = 15, target: String = "kitchen") {
        put(files, """
        {"enabled":true,"default_target":"\(target)","structure_id":"s1","targets":{},
         "chat_monitor":{"slack_enabled":\(slack),"google_chat_enabled":\(chat),"poll_interval_seconds":\(interval)}}
        """)
    }

    private func setUp(slack: Bool, running: Bool) -> (MemoryFiles, ConfigManager, FakeChatMonitor) {
        let files = MemoryFiles()
        edit(files, slack: slack, chat: false)
        let m = manager(files)
        let monitor = FakeChatMonitor(running: running)
        m.chatMonitor = monitor
        return (files, m, monitor)
    }

    @Test func turningASourceOnFromThePhoneStartsTheMonitor() {
        let (files, m, monitor) = setUp(slack: false, running: false)
        edit(files, slack: true, chat: false)
        m.reloadIfChangedExternally()
        #expect(monitor.calls == ["start"])
    }

    @Test func turningEverySourceOffStopsIt() {
        let (files, m, monitor) = setUp(slack: true, running: true)
        edit(files, slack: false, chat: false)
        m.reloadIfChangedExternally()
        #expect(monitor.calls == ["stop"])
    }

    @Test func changingARunningMonitorsSettingsRestartsIt() {
        let (files, m, monitor) = setUp(slack: true, running: true)
        edit(files, slack: true, chat: true, interval: 30)
        m.reloadIfChangedExternally()
        #expect(monitor.calls == ["stop", "start"])
    }

    @Test func anUnrelatedEditLeavesTheMonitorAlone() {
        let (files, m, monitor) = setUp(slack: true, running: false)
        edit(files, slack: true, chat: false, target: "office")
        m.reloadIfChangedExternally()
        #expect(m.config.defaultTarget == "office")
        #expect(monitor.calls.isEmpty, "a monitor stopped by signing out must not come back because the speaker changed")
    }

    @Test func decisionMatrix() {
        let off = ChatMonitorConfig()
        let slack = ChatMonitorConfig(slackEnabled: true)
        let slackFast = ChatMonitorConfig(slackEnabled: true, pollIntervalSeconds: 5)
        #expect(ChatMonitorReconciliation.decide(old: slack, new: slack, isRunning: true) == .none)
        #expect(ChatMonitorReconciliation.decide(old: slack, new: slack, isRunning: false) == .none)
        #expect(ChatMonitorReconciliation.decide(old: off, new: slack, isRunning: false) == .start)
        #expect(ChatMonitorReconciliation.decide(old: slack, new: slackFast, isRunning: true) == .restart)
        #expect(ChatMonitorReconciliation.decide(old: slack, new: slackFast, isRunning: false) == .start)
        #expect(ChatMonitorReconciliation.decide(old: slack, new: off, isRunning: true) == .stop)
        #expect(ChatMonitorReconciliation.decide(old: slack, new: off, isRunning: false) == .none)
    }
}

// MARK: - Hooks

private func scratchHome() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-home-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct HookPathTests {
    let app = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"
    let tool = "/Users/me/Library/Application Support/Vitruvian/tools/homespeaker/bin/tool"

    @Test func aHookIsNeverPointedAtTheTool() throws {
        let home = scratchHome()
        let fromTool = AgentIntegration(home: home, executablePath: tool)
        #expect(throws: AgentIntegration.IntegrationError.notHomeSpeaker(tool)) { try fromTool.installHook(for: .claudeCode) }
        #expect(!FileManager.default.fileExists(atPath: CodingAgent.claudeCode.settingsURL(home: home).path), "nothing written")
    }

    @Test func repairFromAnotherProgramLeavesTheAppsHookAlone() throws {
        let home = scratchHome()
        try AgentIntegration(home: home, executablePath: app).installHook(for: .claudeCode)
        AgentIntegration(home: home, executablePath: tool).repairHookIfMoved(choice: nil)
        #expect(AgentIntegration(home: home, executablePath: app).hookStatus() == .installed, "still the app's hook")
    }

    @Test func theRunningProgramIsAnAbsolutePath() {
        #expect(AgentIntegration.runningExecutable(bundleExecutable: app, argv0: "x", currentDirectory: "/") == app)
        #expect(AgentIntegration.runningExecutable(bundleExecutable: nil, argv0: ".build/debug/HomeSpeaker", currentDirectory: "/src/hs")
                == "/src/hs/.build/debug/HomeSpeaker")
        #expect(AgentIntegration.runningExecutable(bundleExecutable: nil, argv0: "/opt/HomeSpeaker", currentDirectory: "/tmp") == "/opt/HomeSpeaker")
        #expect(AgentIntegration.isHomeSpeakerProgram(app))
        #expect(!AgentIntegration.isHomeSpeakerProgram(tool))
    }
}

@Suite struct SpeaksTwiceTests {
    let rival = URL(fileURLWithPath: "/Users/me/.claude/skills/google-home/hooks/hooks.json")

    private func status(_ agent: CodingAgent, hook: AgentIntegration.HookStatus, rival: URL?) -> AgentIntegration.AgentStatus {
        .init(agent: agent, isInstalled: true, hook: hook, configuredByInstruction: false, rivalHook: rival)
    }

    @Test func claudeCodeWithBothHooksSpeaksTwiceAndSaysWhichFile() {
        let st = status(.claudeCode, hook: .installed, rival: rival)
        #expect(st.speaksTwice)
        #expect(st.section == .hook, "the warning is shown in the hook section Claude Code gets")
        #expect(st.speaksTwiceWarning == "Every reply is spoken twice: hooks.json in hooks also announces it.")
    }

    @Test(arguments: [
        (CodingAgent.claudeCode, AgentIntegration.HookStatus.notInstalled, true),
        (CodingAgent.claudeCode, AgentIntegration.HookStatus.stale("\"/old/HomeSpeaker\" --claude-stop-hook"), true),
        (CodingAgent.claudeCode, AgentIntegration.HookStatus.installed, false),
        (CodingAgent.antigravity, AgentIntegration.HookStatus.notInstalled, true),
        (CodingAgent.antigravity, AgentIntegration.HookStatus.installed, false),
        (CodingAgent.opencode, AgentIntegration.HookStatus.notInstalled, true),
        (CodingAgent.opencode, AgentIntegration.HookStatus.installed, false),
    ])
    func everyOtherCombinationIsOneVoice(agent: CodingAgent, hook: AgentIntegration.HookStatus, hasRival: Bool) {
        let st = status(agent, hook: hook, rival: hasRival ? rival : nil)
        #expect(!st.speaksTwice)
        #expect(st.speaksTwiceWarning == nil)
    }

    @Test func eachAgentGetsTheSectionItsIntegrationNeeds() {
        #expect(status(.claudeCode, hook: .notInstalled, rival: nil).section == .hook)
        #expect(status(.antigravity, hook: .notInstalled, rival: nil).section == .hook)
        #expect(status(.opencode, hook: .notInstalled, rival: nil).section == .hook)
        let absent = AgentIntegration.AgentStatus(agent: .claudeCode, isInstalled: false, hook: .notInstalled,
                                                  configuredByInstruction: false, rivalHook: rival)
        #expect(absent.section == .notInstalled)
    }
}

// MARK: - CLI flags

@Suite struct AppCommandParserTests {
    private func parse(_ args: String...) -> Result<AppCommand, UsageError>? { AppCommandParser.parse(args) }
    private func usage(_ args: String...) -> String? {
        if case .failure(let e)? = AppCommandParser.parse(args) { return e.message }
        return nil
    }

    @Test func otherFlagsAreLeftToTheirOwnCode() {
        #expect(AppCommandParser.parse([]) == nil)
        #expect(parse("--volume") == nil)
        #expect(parse("--sign-in", "--chat") == nil)
        #expect(parse("--say", "--discover") == nil, "--say's text is free-form")
        #expect(parse("--announce", "--sign-out") == nil)
    }

    @Test func signOut() {
        #expect(parse("--sign-out") == .success(.signOut(chatOnly: false)))
        #expect(parse("--sign-out", "--chat") == .success(.signOut(chatOnly: true)))
        #expect(usage("--sign-out", "--home") == "unexpected argument \"--home\" for --sign-out")
        #expect(usage("--sign-out", "--chat", "--chat") != nil)
    }

    @Test func discover() {
        #expect(parse("--discover") == .success(.discover(save: false, home: nil)))
        #expect(parse("--discover", "--save") == .success(.discover(save: true, home: nil)))
        #expect(parse("--discover", "--home", "h1") == .success(.discover(save: false, home: "h1")))
        #expect(parse("--discover", "--home", "h1", "--save") == .success(.discover(save: true, home: "h1")))
        #expect(usage("--discover", "--home")?.contains("--home needs a home id") == true)
        #expect(usage("--discover", "--home", "--save")?.contains("--home needs a home id") == true)
        #expect(usage("--discover", "--home", "  ") != nil)
        #expect(usage("--discover", "--home", "a", "--home", "b") != nil)
        #expect(usage("--discover", "--save", "--save") != nil)
        #expect(usage("--discover", "kitchen") == "unexpected argument \"kitchen\" for --discover")
    }

    @Test func loginItem() {
        #expect(parse("--login-item") == .success(.loginItem(.status)))
        #expect(parse("--login-item", "status") == .success(.loginItem(.status)))
        #expect(parse("--login-item", "enable") == .success(.loginItem(.enable)))
        #expect(parse("--login-item", "disable") == .success(.loginItem(.disable)))
        #expect(usage("--login-item", "on") == "--login-item takes one of status, enable, disable, not \"on\"")
        #expect(usage("--login-item", "enable", "now") != nil)
    }

    @Test func testMediaPause() {
        #expect(parse("--test-media-pause") == .success(.testMediaPause))
        #expect(usage("--test-media-pause", "3") != nil)
    }

    @Test func commandsDoNotCombineAndMustComeFirst() {
        #expect(usage("--sign-out", "--discover") == "--sign-out and --discover cannot be combined; run one at a time")
        #expect(usage("--save", "--discover") == "--discover must be the first argument")
        #expect(AppCommandParser.usageExitCode == 2)
        #expect(AppCommandParser.failureExitCode == 1)
    }

    @Test func helpListsEveryCommand() {
        for flag in AppCommandParser.commandFlags { #expect(AppCommandParser.usageLines.contains(flag)) }
    }
}

final class FakeAuth: GoogleSigningOut, @unchecked Sendable {
    var signedIn: Set<GoogleAuth.Purpose> = [.home, .chat]
    var broken = false
    var asked: [GoogleAuth.Purpose?] = []
    func signOut(purpose: GoogleAuth.Purpose?, revoke: Bool) async {
        asked.append(purpose)
        guard !broken else { return }
        if let purpose { signedIn.remove(purpose) } else { signedIn.removeAll() }
    }
}

struct FakeHomes: HomeDiscovering {
    var homes: [HomeStructure] = [HomeStructure(id: "h1", name: "Lake House"), HomeStructure(id: "h2", name: "City Flat")]
    var targets: [String: [String: SpeakerDevice]] = [
        "h1": ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen")],
        "h2": ["office": SpeakerDevice(id: "d2", type: "SPEAKER", name: "Office")],
    ]
    var failure: String?
    func listHomes() async throws -> [HomeStructure] {
        if let failure { throw BroadcastError.mcp(failure) }
        return homes
    }
    func discoverBroadcastTargets(structureId: String) async throws -> [String: SpeakerDevice] { targets[structureId] ?? [:] }
}

final class FakeLoginItem: LoginItemControlling {
    var state: LoginItemState
    var after: LoginItemState?
    var refuses = false
    var calls: [String] = []
    init(_ state: LoginItemState, after: LoginItemState? = nil) { self.state = state; self.after = after }
    func register() throws {
        calls.append("register")
        if refuses { throw CocoaError(.featureUnsupported) }
        state = after ?? .enabled
    }
    func unregister() throws {
        calls.append("unregister")
        if refuses { throw CocoaError(.featureUnsupported) }
        state = after ?? .notRegistered
    }
}

/// Collects what `--discover --save` would have saved.
final class Saved: @unchecked Sendable {
    var home: HomeStructure?
    var targets: [String: SpeakerDevice] = [:]
}

@Suite struct AppCommandRunnerTests {
    @Test func signOutEverythingOrOnlyChat() async {
        let auth = FakeAuth()
        let chat = await AppCommandRunner.signOut(chatOnly: true, auth: auth, signedIn: { auth.signedIn })
        #expect(chat == CLIOutput(stdout: ["signed out of Google Chat"]))
        #expect(auth.asked == [.chat])
        #expect(auth.signedIn == [.home], "Home stays signed in")
        let all = await AppCommandRunner.signOut(chatOnly: false, auth: auth, signedIn: { auth.signedIn })
        #expect(all.exitCode == 0)
        #expect(auth.asked.last == .some(nil))
        #expect(auth.signedIn.isEmpty)
    }

    @Test func aSignOutThatDidNotTakeFails() async {
        let auth = FakeAuth()
        auth.broken = true
        let out = await AppCommandRunner.signOut(chatOnly: false, auth: auth, signedIn: { auth.signedIn })
        #expect(out.exitCode == 1)
        #expect(out.stderr.first?.contains("still signed in for chat and home") == true)
    }

    private func discover(save: Bool = false, home: String? = nil, client: FakeHomes = FakeHomes(), current: String = "",
                          refuse: Bool = false) async -> (CLIOutput, Saved) {
        let saved = Saved()
        let out = await AppCommandRunner.discover(save: save, home: home, client: client, currentStructureId: current) { h, t in
            if refuse { throw ConfigFileError.unreadable(path: "/x", reason: "bad") }
            saved.home = h
            saved.targets = t
        }
        return (out, saved)
    }

    @Test func discoverListsEveryHomeAndSavesNothing() async {
        let (out, saved) = await discover()
        #expect(out.exitCode == 0)
        #expect(out.stdout == ["home: Lake House (h1)", "  kitchen\tSPEAKER\tKitchen\td1", "home: City Flat (h2)", "  office\tSPEAKER\tOffice\td2"])
        #expect(saved.home == nil)
    }

    @Test func discoverOneHome() async {
        let (out, _) = await discover(home: "h2")
        #expect(out.stdout.first == "home: City Flat (h2)")
        #expect(out.stdout.count == 2)
        let (missing, _) = await discover(home: "nope")
        #expect(missing.exitCode == 1)
        #expect(missing.stderr.first?.contains("no home with id nope") == true)
    }

    @Test func discoverSaveUsesTheGivenHomeThenTheCurrentThenTheFirst() async {
        var (out, saved) = await discover(save: true, home: "h2", current: "h1")
        #expect(saved.home?.id == "h2")
        #expect(out.stdout.last == "saved 1 target(s) from City Flat")
        (out, saved) = await discover(save: true, current: "h2")
        #expect(saved.home?.id == "h2")
        (out, saved) = await discover(save: true, current: "gone")
        #expect(saved.home?.id == "h1")
        #expect(saved.targets.keys.sorted() == ["kitchen"])
    }

    @Test func discoverFailuresExitOne() async {
        var client = FakeHomes()
        client.failure = "not signed in"
        var (out, _) = await discover(client: client)
        #expect(out.exitCode == 1)
        #expect(out.stderr == ["error: Google Home error: not signed in"])

        (out, _) = await discover(client: FakeHomes(homes: []))
        #expect(out.exitCode == 1)

        var empty = FakeHomes()
        empty.targets = [:]
        let (none, saved) = await discover(save: true, client: empty)
        #expect(none.exitCode == 1, "an empty result never wipes the speaker list")
        #expect(saved.home == nil)

        let (refused, _) = await discover(save: true, refuse: true)
        #expect(refused.exitCode == 1, "a refused save is reported, not claimed")
        #expect(refused.stderr.first?.contains("could not be read") == true)
    }

    @Test func loginItemStatusEnableDisable() {
        #expect(AppCommandRunner.loginItem(.status, control: FakeLoginItem(.enabled)) == CLIOutput(stdout: ["login item: enabled"]))
        let off = FakeLoginItem(.notRegistered)
        #expect(AppCommandRunner.loginItem(.enable, control: off) == CLIOutput(stdout: ["login item: enabled"]))
        #expect(AppCommandRunner.loginItem(.disable, control: off) == CLIOutput(stdout: ["login item: disabled"]))
        #expect(off.calls == ["register", "unregister"])
        let already = FakeLoginItem(.enabled)
        _ = AppCommandRunner.loginItem(.enable, control: already)
        #expect(already.calls.isEmpty, "enabling twice is a no-op")
    }

    @Test func loginItemThatNeedsApprovalOrFails() {
        let pending = AppCommandRunner.loginItem(.enable, control: FakeLoginItem(.notRegistered, after: .requiresApproval))
        #expect(pending.exitCode == 0)
        #expect(pending.stdout.last?.contains("System Settings") == true)
        let bare = AppCommandRunner.loginItem(.enable, control: FakeLoginItem(.notFound, after: .notFound))
        #expect(bare.exitCode == 1)
        #expect(bare.stderr.first?.contains(".app bundle") == true)
        let refusing = FakeLoginItem(.notRegistered)
        refusing.refuses = true
        #expect(AppCommandRunner.loginItem(.enable, control: refusing).exitCode == 1)
    }
}

@MainActor
@Suite(.serialized) struct TestMediaPauseCommandTests {
    private func coordinator(_ runner: FakeRunner, audio: Set<String>) -> MediaPauseCoordinator {
        MediaPauseCoordinator(controller: MediaController(runner: runner), audio: { audio }, safariRunning: { false })
    }

    @Test func pausesThenResumes() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("7:42:www.youtube.com,")
        let c = coordinator(runner, audio: ["com.google.Chrome.helper"])
        let out = await AppCommandRunner.testMediaPause(coordinator: c, hold: 0.1, wait: { _ in })
        #expect(out == CLIOutput(stdout: ["Paused Google Chrome (www.youtube.com).", "resumed"]))
        #expect(!c.isHolding)
        #expect(runner.ran.last?.contains("tab id 42 of window id 7") == true, "the paused tab was resumed")
    }

    @Test func nothingPlaying() async {
        let out = await AppCommandRunner.testMediaPause(coordinator: coordinator(FakeRunner(), audio: []), wait: { _ in })
        #expect(out == CLIOutput(stdout: ["nothing was playing that HomeSpeaker can pause"]))
    }

    @Test func aRefusingPlayerExitsOne() async {
        let runner = FakeRunner()
        runner.activeTabs = .success("ERR:Executing JavaScript through AppleScript is turned off.")
        runner.allTabs = .success("ERR:Executing JavaScript through AppleScript is turned off.")
        let out = await AppCommandRunner.testMediaPause(coordinator: coordinator(runner, audio: ["com.google.Chrome.helper"]), wait: { _ in })
        #expect(out.exitCode == 1)
        #expect(out.stdout.first?.contains("Allow JavaScript from Apple Events") == true)
        let unknown = await AppCommandRunner.testMediaPause(coordinator: coordinator(FakeRunner(), audio: ["us.zoom.xos"]), wait: { _ in })
        #expect(unknown.exitCode == 1, "a player HomeSpeaker cannot drive is a failed test, not a pass")
    }
}

/// `HomeSpeaker --sign-out` runs as a second process; the running menu bar
/// app has to hear about it, re-read the login and stop polling Chat.
@MainActor
@Suite(.serialized) struct SignOutNoticeTests {
    /// A store with a Home login, and a manager that has read it.
    private func signedIn() throws -> (ConfigManager, SecretStore) {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-signout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let secrets = SecretStore(fileURL: scratch.appendingPathComponent("secrets.json"))
        try secrets.save(Secrets(google: GoogleCredentials(
            clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r", email: "someone@example.com")))
        let manager = ConfigManager(
            configPath: configURL, historyPath: scratch.appendingPathComponent("history.json"),
            secrets: secrets, fileSystem: MemoryFiles())
        #expect(manager.isConnectedToGoogle)
        return (manager, secrets)
    }

    @Test func aFullSignOutRereadsTheLoginAndStopsTheMonitor() throws {
        let (manager, secrets) = try signedIn()
        let monitor = FakeChatMonitor(running: true)
        try secrets.clear()
        SignOutNotice.apply(chatOnly: false, config: manager, monitor: monitor)
        #expect(!manager.isConnectedToGoogle, "the menu bar must stop showing Connected")
        #expect(manager.googleEmail == nil)
        #expect(monitor.calls == ["stop"])
        #expect(!monitor.isRunning)
    }

    @Test func aChatOnlySignOutRestartsARunningMonitorAndLeavesAStoppedOneAlone() throws {
        let (manager, _) = try signedIn()
        let running = FakeChatMonitor(running: true)
        SignOutNotice.apply(chatOnly: true, config: manager, monitor: running)
        #expect(running.calls == ["stop", "start"], "Slack keeps going; Google Chat drops on the restart")
        #expect(manager.isConnectedToGoogle, "Home stays signed in")
        let stopped = FakeChatMonitor(running: false)
        SignOutNotice.apply(chatOnly: true, config: manager, monitor: stopped)
        #expect(stopped.calls.isEmpty)
    }

    @Test func theCLIPostsOnlyWhenTheSignOutTook() async {
        let posted = Posted()
        let auth = FakeAuth()
        _ = await AppCommandRunner.signOut(chatOnly: true, auth: auth, signedIn: { auth.signedIn }, notify: { posted.add($0) })
        #expect(posted.values == [true])
        auth.broken = true
        auth.signedIn = [.home, .chat]
        _ = await AppCommandRunner.signOut(chatOnly: false, auth: auth, signedIn: { auth.signedIn }, notify: { posted.add($0) })
        #expect(posted.values == [true], "a sign-out that did not take tells the app nothing")
    }

    /// The real distributed notification, under a name of its own so a
    /// HomeSpeaker running on this Mac never sees it.
    @Test func aPostedNoticeReachesTheListener() async throws {
        let name = Notification.Name("com.vitruviansoftware.homespeaker.test.signed-out.\(UUID().uuidString)")
        var heard: [Bool] = []
        let token = SignOutNotice.listen(name: name) { heard.append($0) }
        defer { DistributedNotificationCenter.default().removeObserver(token) }
        SignOutNotice.post(chatOnly: true, name: name)
        SignOutNotice.post(chatOnly: false, name: name)
        for _ in 0..<100 where heard.count < 2 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(heard == [true, false])
    }
}

final class Posted: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Bool] = []
    func add(_ value: Bool) { lock.withLock { stored.append(value) } }
    var values: [Bool] { lock.withLock { stored } }
}

// MARK: - Custom Voice Parity Tests

@Suite struct CustomVoiceTests {
    @Test func customVoiceLenientDecoding() throws {
        let json = """
        {
            "id": "voice_123",
            "name": "Morgan Freeman Clone",
            "audio_path": "/path/to/sample.wav",
            "transcript": "Hello world",
            "created_at": "2026-10-21T12:00:00Z"
        }
        """.data(using: .utf8)!

        let voice = try JSONDecoder().decode(CustomVoice.self, from: json)
        #expect(voice.id == "voice_123")
        #expect(voice.name == "Morgan Freeman Clone")
        #expect(voice.audioPath == "/path/to/sample.wav")
        #expect(voice.transcript == "Hello world")
        #expect(voice.createdAt == "2026-10-21T12:00:00Z")

        // Lenient decoding when optional fields and name are absent
        let minimalJson = #"{"id": "voice_min"}"#.data(using: .utf8)!
        let minimal = try JSONDecoder().decode(CustomVoice.self, from: minimalJson)
        #expect(minimal.id == "voice_min")
        #expect(minimal.name == "voice_min")
        #expect(minimal.audioPath == nil)
    }

    @Test func effectiveCustomVoicesDeduplicatesById() {
        var config = SpeakerConfig()
        config.customVoices = [
            CustomVoice(id: "v1", name: "Voice One"),
            CustomVoice(id: "v2", name: "Voice Two"),
            CustomVoice(id: "v1", name: "Duplicate Voice One")
        ]
        let effective = config.effectiveCustomVoices
        #expect(effective.count == 2)
        #expect(effective[0].id == "v1")
        #expect(effective[0].name == "Voice One")
        #expect(effective[1].id == "v2")
    }

    @Test func geminiVoiceDisplayNameResolvesPrebuiltAndCustom() {
        var config = SpeakerConfig()
        config.customVoices = [CustomVoice(id: "voice_clone", name: "Custom Voice")]
        config.geminiVoice = "Kore"

        #expect(config.geminiVoiceDisplayName() == "Kore · Warm & clear")
        #expect(config.geminiVoiceDisplayName("Puck") == "Puck · Upbeat")
        #expect(config.geminiVoiceDisplayName("voice_clone") == "Custom Voice (cloned)")
        #expect(config.geminiVoiceDisplayName("unknown_raw") == "unknown_raw")
    }

    @Test func geminiVoiceOptionsProvidesPrebuiltAndCustomAndActive() {
        var config = SpeakerConfig()
        config.customVoices = [CustomVoice(id: "clone_1", name: "Clone 1")]
        config.geminiVoice = "custom_unknown"

        let options = config.geminiVoiceOptions()
        #expect(options.first?.value == "custom_unknown")
        #expect(options.contains(where: { $0.value == "Kore" && $0.label == "Kore · Warm & clear" }))
        #expect(options.contains(where: { $0.value == "clone_1" && $0.label == "Clone 1 (cloned)" }))
    }

    @Test func speakerConfigFilePreservesCustomVoicesWhenNilInNewConfig() throws {
        let existingJson: [String: Any] = [
            "enabled": true,
            "default_target": "living_room",
            "custom_voices": [
                ["id": "cv1", "name": "Cloned Voice", "audio_path": "/audio.wav"]
            ]
        ]
        let newConfig = SpeakerConfig(enabled: false, defaultTarget: "office")
        // newConfig has customVoices == nil
        let mergedData = try SpeakerConfigFile.encode(newConfig, preserving: existingJson)
        let mergedObj = try JSONSerialization.jsonObject(with: mergedData) as? [String: Any]
        #expect(mergedObj?["enabled"] as? Bool == false)
        #expect(mergedObj?["default_target"] as? String == "office")
        let voices = mergedObj?["custom_voices"] as? [[String: Any]]
        #expect(voices?.count == 1)
        #expect(voices?[0]["id"] as? String == "cv1")
    }
}

// MARK: - Canonical Outputs Footer Tests

@Suite struct OutputsFooterTests {
    @Test func allOutputsOffReturnsExplanation() {
        var config = SpeakerConfig()
        config.speakHome = false
        config.speakLocal = false
        config.speakPhone = false
        #expect(config.outputsFooter == "All outputs are off, so nothing is spoken anywhere.")
    }

    @Test func geminiPrivacyAndSimultaneousPlaybackIncluded() {
        var config = SpeakerConfig()
        config.speakHome = true
        config.speakLocal = true
        config.localEngine = .gemini

        let footer = config.outputsFooter
        #expect(footer.contains("Gemini TTS sends what this Mac says to Google"))
        #expect(footer.contains("This Mac speaks at its own volume."))
        #expect(footer.contains("Both speak at the same time. Quiet hours and pausing media cover both."))
    }
}
