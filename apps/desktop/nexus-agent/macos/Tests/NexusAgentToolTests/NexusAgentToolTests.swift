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

import NexusAgentCore
import NexusAgentToolCore
import VitruvianToolKit
import VitruvianToolProtocol

@MainActor
final class NexusAgentToolTests: XCTestCase {
    /// The app, recording.
    final class Link: ToolLink {
        var badges: [(count: Int?, dot: Bool)] = []
        var rendered: [(panel: String, tree: UITree)] = []
        var messages: [String] = []
        var logged: [String] = []
        var written: [(key: String, value: JSONValue)] = []
        var runnable: [[String]] = []

        func badge(count: Int?, dot: Bool) { badges.append((count, dot)) }
        func render(panel: String, _ tree: UITree) { rendered.append((panel, tree)) }
        func showMessage(_ message: String, icon: String) { messages.append(message) }
        func log(_ message: String) { logged.append(message) }
        func setValue(_ value: JSONValue, for key: String) { written.append((key, value)) }
        func setRunnable(_ commands: [String]) { runnable.append(commands) }
    }

    /// The window, recording.
    final class Window: QuickPromptWindow {
        var isVisible = false
        var shows = 0
        func show() { isVisible = true; shows += 1 }
        func hide() { isVisible = false }
        func toggle() { isVisible.toggle(); if isVisible { shows += 1 } }
    }

    /// A Mac in memory, as the app's tests have it: files, the bot's
    /// process, and the delayed work, run by hand.
    @MainActor
    final class Rig {
        var files: [String: String] = [:]
        var executables: Set<String> = []
        var aliveNode: Set<Int32> = []
        var launches: [String] = []
        var exitHandlers: [Int32: @MainActor @Sendable (Int32) -> Void] = [:]
        var nextPID: Int32 = 500
        var pending: [@MainActor () -> Void] = []
        var opened: [String] = []
        var sessionList: [NexusAgentSessionSummary] = []
        let home = "/Users/rig"
        let state = "/Users/rig/Library/Application Support/NexusAgent"
        var bot: String { home + "/.config/nexus-agent" }

        func installBot(token: String = "1:real") {
            files[bot] = ""
            files[bot + "/src/bot.js"] = "// bot"
            files[bot + "/.env"] = "TELEGRAM_BOT_TOKEN=\(token)\nAGY_TIMEOUT_MS=1\n"
            executables.insert("/opt/homebrew/bin/node")
        }

        func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }

        var environment: NexusAgentEngine.Environment {
            NexusAgentEngine.Environment(
                defaults: UserDefaults(suiteName: "com.vitruviansoftware.nexus-agent.tool-tests")!,
                home: home,
                processEnvironment: ["PATH": "/usr/bin"],
                stateDirectory: state,
                isExecutable: { [unowned self] in executables.contains($0) },
                fileExists: { [unowned self] in files[$0] != nil },
                readFile: { [unowned self] in files[$0] },
                readTail: { [unowned self] path, _ in files[path] },
                writePrivateFile: { [unowned self] path, content in
                    guard files[(path as NSString).deletingLastPathComponent] != nil || path.hasPrefix(state) else { return false }
                    files[path] = content
                    return true
                },
                removeFile: { [unowned self] in files[$0] = nil },
                isBotProcess: { [unowned self] in aliveNode.contains($0) },
                signal: { [unowned self] pid, signal in if signal == SIGKILL { aliveNode.remove(pid) } },
                launchBot: { [unowned self] node, directory, _, _, onExit in
                    nextPID += 1
                    launches.append(directory)
                    aliveNode.insert(nextPID)
                    exitHandlers[nextPID] = onExit
                    return nextPID
                },
                schedule: { [unowned self] _, work in pending.append(work) },
                openFile: { [unowned self] in opened.append($0) },
                launchAgent: { _, _, _, _, _, _ in NexusAgentRunningAgent(terminate: {}) },
                listSessions: { [unowned self] _, _, _ in sessionList })
        }
    }

    private var folder: URL!
    private var rig: Rig!
    private var link: Link!
    private var window: Window!
    private var settings: ToolSettings!
    private var engine: ToolEngine!
    private var chosenFolder: String?

    override func setUp() {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-agent-tool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        rig = Rig()
        link = Link()
        window = Window()
        settings = ToolSettings(folder: folder)
        engine = ToolEngine(environment: rig.environment, host: settings)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func tool() -> NexusAgentTool {
        NexusAgentTool(parts: .init(link: link, settings: settings, engine: engine, window: window,
                                    chooseFolder: { [unowned self] in chosenFolder }))
    }

    /// Lets the engine's publishers reach the tool on the main queue.
    private func settle() {
        let until = Date().addingTimeInterval(0.05)
        while Date() < until { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
    }

    func testStartTakesTheHandedSettingsClearsThemAndStartsTheBotWhenAsked() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "fr", handed: ["autoStart": .bool(true), "promptHistory": .string(#"["hi"]"#),
                                            "chosenProvider": .string("not a uuid")])
        XCTAssertEqual(link.written.map(\.key), ["chosenProvider", "promptHistory"], "the untitled copies are cleared, in order")
        XCTAssertEqual(link.written.map(\.value), [.string(""), .string("")])
        XCTAssertEqual(settings.promptHistory, ["hi"])
        XCTAssertEqual(rig.launches, [rig.bot], "auto-start starts the bot")
        XCTAssertTrue(engine.isRunning)
        XCTAssertEqual(link.runnable.last, ["quickPrompt", "newChat", "stopBot"])
        XCTAssertEqual(link.badges.last?.dot, false)
        XCTAssertTrue(link.logged.contains { $0.contains("chosenProvider, promptHistory") })
        XCTAssertEqual(tool.language, "fr")
        // A second hello in the same run does not start anything twice.
        tool.start(language: "fr", handed: [:])
        XCTAssertEqual(rig.launches.count, 1)
    }

    func testCommandsOpenTheWindowAndDriveTheBot() throws {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        XCTAssertFalse(engine.isRunning, "not asked to start at launch")
        XCTAssertEqual(link.runnable.last, ["quickPrompt", "newChat", "startBot"])
        try tool.run(command: "quickPrompt")
        XCTAssertTrue(window.isVisible)
        try tool.run(command: "quickPrompt")
        XCTAssertFalse(window.isVisible, "the command toggles")
        try tool.run(command: "newChat")
        XCTAssertTrue(window.isVisible)
        XCTAssertThrowsError(try tool.run(command: "stopBot")) { XCTAssertTrue($0 is CommandRefused) }
        try tool.run(command: "startBot")
        XCTAssertTrue(engine.isRunning)
        settle()
        XCTAssertEqual(link.runnable.last, ["quickPrompt", "newChat", "stopBot"])
        XCTAssertThrowsError(try tool.run(command: "startBot"))
        XCTAssertThrowsError(try tool.run(command: "nothing"))
    }

    func testTheIslandPageOpensTheWindowResumesASessionAndFollowsTheBot() {
        rig.installBot()
        rig.sessionList = [NexusAgentSessionSummary(id: "s1", title: "Fix", preview: "", steps: 1, modified: nil, isArchived: false)]
        let tool = tool()
        tool.start(language: "en", handed: [:])
        let page = tool.islandPage()
        XCTAssertEqual(tool.openPanels, ["agent"])
        XCTAssertEqual(page.blocks.compactMap(\.id), ["open", "startBot", "sessions"])
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "open", kind: .tap)), .keep)
        XCTAssertEqual(window.shows, 1)
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "sessions", kind: .tap, value: .string("s1"))), .keep)
        XCTAssertEqual(window.shows, 2)
        XCTAssertEqual(engine.session.conversationID, "s1", "the row's session is resumed")
        guard case .page(let after) = tool.islandEvent(PanelEvent(block: "startBot", kind: .tap)) else { return XCTFail("no page") }
        XCTAssertEqual(after.blocks.compactMap(\.id), ["open", "stopBot", "sessions"])
        XCTAssertTrue(engine.isRunning)
        settle()
        XCTAssertEqual(link.rendered.last?.panel, "agent", "the bot's change is drawn again while the page is open")
        tool.panelClosed("agent")
        XCTAssertEqual(tool.openPanels, [])
        link.rendered.removeAll()
        engine.stop()
        settle()
        XCTAssertTrue(link.rendered.isEmpty, "nothing is drawn for a closed page")
    }

    func testTheSettingsPanelEditsTheEnvAndSavesIt() throws {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        _ = tool.settingsPage()
        XCTAssertEqual(tool.draft.botToken, "1:real")
        _ = tool.settingsEvent(PanelEvent(block: "token", kind: .submit, value: .string("1:new")))
        _ = tool.settingsEvent(PanelEvent(block: "approval", kind: .tap, value: .string("plan")))
        _ = tool.settingsEvent(PanelEvent(block: "effort", kind: .tap, value: .string("high")))
        chosenFolder = "/Users/rig/work"
        _ = tool.settingsEvent(PanelEvent(block: "chooseFolder", kind: .tap))
        XCTAssertEqual(tool.draft.workingDirectory, "/Users/rig/work")
        XCTAssertEqual(tool.draft.approvalMode, .plan)
        XCTAssertEqual(tool.draft.effort, .high)
        guard case .page(let page) = tool.settingsEvent(PanelEvent(block: "save", kind: .tap)) else { return XCTFail("no page") }
        let env = try XCTUnwrap(rig.files[rig.bot + "/.env"])
        XCTAssertTrue(env.contains("TELEGRAM_BOT_TOKEN=1:new") && env.contains("plan") && env.contains("high"), env)
        XCTAssertEqual(tool.draft, engine.configuration, "the draft is the saved file again")
        guard case .button(let save)? = page.blocks.first(where: { $0.id == "save" })?.content else { return XCTFail("no Save") }
        XCTAssertEqual(save.enabled, false)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "save", kind: .tap)), .keep, "nothing to save")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "openLog", kind: .tap)), .keep)
        XCTAssertEqual(rig.opened, [], "no log yet, nothing to open")
        rig.files[engine.logPath] = "started"
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "openLog", kind: .tap)), .keep)
        XCTAssertEqual(rig.opened, [engine.logPath])
    }

    func testAChangedBotFolderIsReadAgainAndPlanModeReachesTheChat() {
        rig.installBot()
        rig.files["/Users/rig/other"] = ""
        rig.files["/Users/rig/other/src/bot.js"] = "// bot"
        rig.files["/Users/rig/other/.env"] = "TELEGRAM_BOT_TOKEN=2:other\n"
        let tool = tool()
        tool.start(language: "en", handed: [:])
        _ = tool.settingsPage()
        tool.preferencesChanged(["botDirectory": .string("/Users/rig/other"), "planMode": .bool(true)])
        XCTAssertEqual(tool.draft.botToken, "2:other")
        XCTAssertTrue(engine.session.planMode)
        XCTAssertEqual(link.rendered.last?.panel, "settings")
        // The chat turns plan mode off: the app's copy follows.
        engine.session.planMode = false
        XCTAssertEqual(link.written.last?.key, "planMode")
        XCTAssertEqual(link.written.last?.value, .bool(false))
    }

    func testTurnsAreToldWithTheBadgeAndAMessage() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "de", handed: [:])
        link.messages.removeAll()
        settings.turnNeedsApproval(NexusAgentTurnNotice(providerName: "agy", text: "rm -rf", failed: false, endedCleanly: false))
        XCTAssertTrue(tool.awaitingApproval)
        XCTAssertEqual(link.badges.last?.count, 1)
        XCTAssertEqual(link.messages, ["agy — Approval Required"])
        XCTAssertTrue(tool.status().awaitingApproval)
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "done", failed: false, endedCleanly: true), isChatVisible: true)
        XCTAssertFalse(tool.awaitingApproval)
        XCTAssertEqual(link.badges.last?.count, nil)
        XCTAssertEqual(link.messages.count, 1, "a reply the person saw is not announced")
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "done", failed: false, endedCleanly: true), isChatVisible: false)
        XCTAssertEqual(link.messages.last, "agy — Done")
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "", failed: true, endedCleanly: false), isChatVisible: true)
        XCTAssertEqual(link.messages.last, "agy — Failed", "a failure is always said")
    }

    func testLanguageAndStopReachTheEngine() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        _ = tool.islandPage()
        link.rendered.removeAll()
        tool.languageChanged("ja")
        XCTAssertEqual(settings.language, "ja")
        XCTAssertEqual(link.rendered.count, 1)
        window.show()
        tool.stop()
        XCTAssertFalse(window.isVisible)
    }
}
