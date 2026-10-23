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
        var features: Set<ProtocolFeature> = []
        var statuses: [(icon: String?, text: String?, activity: String?)] = []
        var notices: [(title: String, detail: String?, icon: String)] = []
        var dockRequests = 0

        func badge(count: Int?, dot: Bool) { badges.append((count, dot)) }
        func render(panel: String, _ tree: UITree) { rendered.append((panel, tree)) }
        func showMessage(_ message: String, icon: String) { messages.append(message) }
        func log(_ message: String) { logged.append(message) }
        func setValue(_ value: JSONValue, for key: String) { written.append((key, value)) }
        func setRunnable(_ commands: [String]) { runnable.append(commands) }
        func supports(_ feature: ProtocolFeature) -> Bool { features.contains(feature) }
        func setStatus(icon: String?, text: String?, activity: String?) { statuses.append((icon, text, activity)) }
        func showNotice(title: String, detail: String?, icon: String) { notices.append((title, detail, icon)) }
        func dockToSlot() { dockRequests += 1 }
    }

    /// A link that leaves `supports`, `setStatus`, `showNotice` and
    /// `dockToSlot` to the protocol's defaults.
    final class PlainLink: ToolLink {
        var messages: [String] = []
        func badge(count: Int?, dot: Bool) {}
        func render(panel: String, _ tree: UITree) {}
        func showMessage(_ message: String, icon: String) { messages.append(message) }
        func log(_ message: String) {}
        func setValue(_ value: JSONValue, for key: String) {}
        func setRunnable(_ commands: [String]) {}
    }

    /// The window, recording.
    final class Window: QuickPromptWindow {
        var isVisible = false
        var shows = 0
        var slot: CGRect?
        var docks: [CGRect] = []
        var undocks: [Bool] = []
        var isDockedInSlot: Bool { slot != nil }
        func show() { isVisible = true; shows += 1 }
        func hide() { isVisible = false }
        func toggle() { isVisible.toggle(); if isVisible { shows += 1 } }
        func dockIntoSlot(frame: CGRect) { slot = frame; docks.append(frame); isVisible = true }
        func undockFromSlot(popOut: Bool) {
            slot = nil
            undocks.append(popOut)
            if popOut { show() } else { hide() }
        }
    }

    /// A window that leaves docking to the protocol's defaults.
    final class PlainWindow: QuickPromptWindow {
        var isVisible = false
        func show() { isVisible = true }
        func hide() { isVisible = false }
        func toggle() { isVisible.toggle() }
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

    // `async`, so the override runs on the main actor the class is held to.
    // Swift 6.1.2, the CI Mac's (Xcode 16.4), refuses a plain `setUp()` that
    // touches the class's own properties; Swift 6.4 lets it by.
    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-agent-tool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        rig = Rig()
        link = Link()
        window = Window()
        settings = ToolSettings(folder: folder)
        engine = ToolEngine(environment: rig.environment, host: settings)
    }

    override func tearDown() async throws {
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
        XCTAssertEqual(page.blocks.compactMap(\.id), ["open", "newChat", "startBot", "sessions"])
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "open", kind: .tap)), .keep)
        XCTAssertEqual(window.shows, 1)
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "sessions", kind: .tap, value: .string("s1"))), .keep)
        XCTAssertEqual(window.shows, 2)
        XCTAssertEqual(engine.session.conversationID, "s1", "the row's session is resumed")
        guard case .page(let after) = tool.islandEvent(PanelEvent(block: "startBot", kind: .tap)) else { return XCTFail("no page") }
        XCTAssertEqual(after.blocks.compactMap(\.id), ["open", "newChat", "stopBot", "sessions"])
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
        XCTAssertEqual(link.messages, ["agy — Approval Required — rm -rf"], "what it wants to run is said")
        XCTAssertTrue(tool.status().awaitingApproval)
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "done", failed: false, endedCleanly: true), isChatVisible: true)
        XCTAssertFalse(tool.awaitingApproval)
        XCTAssertEqual(link.badges.last?.count, nil)
        XCTAssertEqual(link.messages.count, 1, "a reply the person saw is not announced")
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "done", failed: false, endedCleanly: true), isChatVisible: false)
        XCTAssertEqual(link.messages.last, "agy — Done — done")
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "", failed: true, endedCleanly: false), isChatVisible: true)
        XCTAssertEqual(link.messages.last, "agy — Failed", "a failure is always said, bare when it has no detail")
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

    func testTheIslandsNewChatButtonStartsAChatAndShowsTheWindow() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        _ = tool.islandPage()
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "newChat", kind: .tap)), .keep)
        XCTAssertEqual(window.shows, 1)
        XCTAssertTrue(window.isVisible)
        XCTAssertNil(engine.session.conversationID, "a new chat has no conversation yet")
    }

    func testTheTokenIsNeverSentBackAndAnEmptyAnswerLeavesIt() throws {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        let page = tool.settingsPage()
        guard case .field(let token)? = page.blocks.first(where: { $0.id == "token" })?.content else { return XCTFail("no token") }
        XCTAssertEqual(token.value, "", "the page does not carry the secret")
        XCTAssertEqual(token.placeholder?.text(for: "en"), "••••••••")
        XCTAssertFalse(try String(decoding: JSONEncoder().encode(page), as: UTF8.self).contains("1:real"))
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "token", kind: .submit, value: .string(""))), .keep)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: "token", kind: .change, value: .string(""))), .keep)
        XCTAssertEqual(tool.draft.botToken, "1:real", "an empty field is no change")
        _ = tool.settingsEvent(PanelEvent(block: "token", kind: .change, value: .string("9:typed")))
        XCTAssertEqual(tool.draft.botToken, "9:typed")
    }

    func testAnAppWithChoiceAndSectionsGetsMenusAndHelpAndPickingWorks() {
        rig.installBot()
        link.features = [.choice, .sections]
        let tool = tool()
        tool.start(language: "en", handed: [:])
        let page = tool.settingsPage()
        guard case .choice(let approval)? = page.blocks.first(where: { $0.id == "approval" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(approval.options.map(\.value), ["yolo", "accept-edits", "plan", "default"])
        guard case .choice(let effort)? = page.blocks.first(where: { $0.id == "effort" })?.content else { return XCTFail("no menu") }
        XCTAssertEqual(effort.value, "automatic")
        XCTAssertTrue(page.blocks.contains { if case .heading(let heading) = $0.content { return heading.section == true }; return false })
        _ = tool.settingsEvent(PanelEvent(block: "approval", kind: .change, value: .string("plan")))
        _ = tool.settingsEvent(PanelEvent(block: "effort", kind: .change, value: .string("high")))
        XCTAssertEqual(tool.draft.approvalMode, .plan)
        XCTAssertEqual(tool.draft.effort, .high)
        // A tap, as a list sends, is still read.
        _ = tool.settingsEvent(PanelEvent(block: "approval", kind: .tap, value: .string("yolo")))
        XCTAssertEqual(tool.draft.approvalMode, .yolo)
    }

    func testAnAppWithoutTheFeaturesGetsListsAndTheDefaultsAnswerForAPlainLink() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        let page = tool.settingsPage()
        guard case .list? = page.blocks.first(where: { $0.id == "approval" })?.content else { return XCTFail("no list") }
        let plain = PlainLink()
        XCTAssertFalse(plain.supports(.choice))
        plain.setStatus(icon: "x", text: "y", activity: nil)
    }

    func testTheClosedIslandsStatusFollowsApprovalAndTheReply() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        XCTAssertTrue(link.statuses.isEmpty, "nothing to show, nothing sent")
        settings.turnNeedsApproval(NexusAgentTurnNotice(providerName: "agy", text: "rm", failed: false, endedCleanly: false))
        XCTAssertEqual(link.statuses.last?.icon, "hand.raised.fill")
        XCTAssertEqual(link.statuses.last?.text, Words.text("awaitingApproval", "en"))
        XCTAssertNil(link.statuses.last?.activity, "waiting for the person is no activity")
        settings.turnNeedsApproval(NexusAgentTurnNotice(providerName: "agy", text: "rm", failed: false, endedCleanly: false))
        XCTAssertEqual(link.statuses.count, 1, "the same mark is not sent twice")
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "ok", failed: false, endedCleanly: true), isChatVisible: true)
        XCTAssertNil(link.statuses.last?.icon, "the mark goes when the turn ends")
        XCTAssertNil(link.statuses.last?.text)
        XCTAssertEqual(link.statuses.count, 2)
    }

    func testAFailureAndAReplyAreSaidWithTheirDetailCut() {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        settings.turnFinished(NexusAgentTurnNotice(providerName: "claude", text: "", failed: true, endedCleanly: false,
                                                   failureDetail: "The agent stopped with an error.\n  command not found: claude  \n"),
                              isChatVisible: false)
        XCTAssertEqual(link.messages.last, "claude — Failed — The agent stopped with an error. command not found: claude")
        let long = String(repeating: "word ", count: 40)
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: long, failed: false, endedCleanly: true),
                              isChatVisible: false)
        let said = link.messages.last ?? ""
        XCTAssertTrue(said.hasPrefix("agy — Done — word word"), said)
        XCTAssertEqual(said.dropFirst("agy — Done — ".count).count, NexusAgentTool.messageDetailLength)
        XCTAssertTrue(said.hasSuffix("…"))
        XCTAssertEqual(NexusAgentTool.message("t", detail: "  \n "), "t", "blank detail is none")
    }

    func testTheQuickPromptCommandPopsADockedChatOutAndStopUndocksIt() throws {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        let slot = CGRect(x: 600, y: 860, width: 420, height: 300)
        window.dockIntoSlot(frame: slot)
        XCTAssertTrue(window.isDockedInSlot)
        try tool.run(command: "quickPrompt")
        XCTAssertEqual(window.undocks, [true], "the command takes it out of the slot, floating")
        XCTAssertFalse(window.isDockedInSlot)
        XCTAssertTrue(window.isVisible)
        try tool.run(command: "quickPrompt")
        XCTAssertFalse(window.isVisible, "floating, the command toggles again")
        window.dockIntoSlot(frame: slot)
        tool.stop()
        XCTAssertEqual(window.undocks, [true, false], "goodbye undocks without showing")
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(window.docks, [slot, slot])
    }

    func testTheAppsSlotDocksTheChatMovesItAndLetsItGo() {
        let tool = tool()
        let first = CGRect(x: 600, y: 860, width: 420, height: 300)
        tool.slotChanged(UISlotParams(visible: true, x: 600, y: 860, width: 420, height: 300))
        XCTAssertEqual(window.docks, [first], "a shown slot docks the chat into its rectangle")
        XCTAssertTrue(window.isDockedInSlot)
        tool.slotChanged(UISlotParams(visible: true, x: 10, y: 20, width: 400, height: 280))
        XCTAssertEqual(window.docks.last, CGRect(x: 10, y: 20, width: 400, height: 280), "a moved slot moves it")
        tool.slotChanged(UISlotParams(visible: true, x: 10, y: 20))
        XCTAssertEqual(window.docks.count, 2, "a shown slot without a whole rectangle is ignored")
        tool.slotChanged(UISlotParams(visible: false, popOut: true))
        XCTAssertEqual(window.undocks, [true], "asked for in a window of its own, the chat floats")
        XCTAssertTrue(window.isVisible)
        tool.slotChanged(UISlotParams(visible: true, x: 600, y: 860, width: 420, height: 300))
        tool.slotChanged(UISlotParams(visible: false))
        XCTAssertEqual(window.undocks, [true, false], "a slot that went, with no pop-out, hides it")
        XCTAssertFalse(window.isVisible)
    }

    func testAnAppWithNoticesGetsTitleAndDetailApartAndOneWithoutGetsOneMessage() {
        rig.installBot()
        link.features = [.notice]
        let tool = tool()
        tool.start(language: "en", handed: [:])
        link.messages.removeAll()
        settings.turnNeedsApproval(NexusAgentTurnNotice(providerName: "agy", text: "rm -rf", failed: false, endedCleanly: false))
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "all\n done", failed: false, endedCleanly: true),
                              isChatVisible: false)
        settings.turnFinished(NexusAgentTurnNotice(providerName: "claude", text: "", failed: true, endedCleanly: false),
                              isChatVisible: true)
        settings.turnFinished(NexusAgentTurnNotice(providerName: "agy", text: "seen", failed: false, endedCleanly: true),
                              isChatVisible: true)
        XCTAssertEqual(link.notices.map(\.title), ["agy — Approval Required", "agy — Done", "claude — Failed"],
                       "a reply the person saw is still not told")
        XCTAssertEqual(link.notices.map(\.detail), ["rm -rf", "all done", nil], "the detail on one line, none when blank")
        XCTAssertEqual(link.notices.map(\.icon), ["hand.raised.fill", "sparkles", "exclamationmark.triangle.fill"])
        XCTAssertEqual(link.messages, [], "a notice replaces the message")

        let plain = PlainLink()
        plain.showNotice(title: "agy — Done", detail: "done", icon: "sparkles")
        XCTAssertEqual(plain.messages, ["agy — Done — done"], "without notices, the default says both in one message")
        plain.dockToSlot()
    }

    func testAWindowWithoutASlotIsNeverDocked() {
        let plain = PlainWindow()
        plain.dockIntoSlot(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertFalse(plain.isDockedInSlot)
        plain.undockFromSlot(popOut: true)
        XCTAssertFalse(plain.isVisible, "the default does nothing")
    }

    func testTheChatsArchiveAndModelChoicesReachTheSettings() throws {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])
        link.written.removeAll()
        settings.hiddenClaudeSessionIDs = ["s1"]
        XCTAssertEqual(link.written.map(\.key), ["hiddenClaudeSessions"], "the app's copy follows the archive")
        XCTAssertEqual(link.written.last?.value, .string(#"["s1"]"#))
        let provider = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        settings.chosenModels = [provider: "sonnet"]
        XCTAssertEqual(ToolSettings(folder: folder).chosenModels, [provider: "sonnet"])
    }

    func testTheAssistiveKeyboardHoldsTheClicksOnItsKeys() {
        func window(_ owner: pid_t, name: String = "App", x: CGFloat = 0, alpha: CGFloat = 1) -> [String: Any] {
            [kCGWindowBounds as String: ["X": x, "Y": 0, "Width": 100, "Height": 100] as [String: CGFloat],
             kCGWindowOwnerPID as String: owner, kCGWindowOwnerName as String: name, kCGWindowAlpha as String: alpha]
        }
        let point = CGPoint(x: 50, y: 50)
        XCTAssertTrue(AssistiveKeyboard.ownsPoint(point, windows: [window(7)], keyboardPID: 7, ownPID: 1))
        XCTAssertTrue(AssistiveKeyboard.ownsPoint(point, windows: [window(9, name: "Panel")], keyboardPID: nil, ownPID: 1))
        XCTAssertFalse(AssistiveKeyboard.ownsPoint(point, windows: [window(8), window(7)], keyboardPID: 7, ownPID: 1),
                       "a window over the keyboard took the click")
        XCTAssertTrue(AssistiveKeyboard.ownsPoint(point, windows: [window(8, alpha: 0), window(1), window(7)],
                                                  keyboardPID: 7, ownPID: 1),
                      "a clear window and the tool's own are clicked through")
        XCTAssertFalse(AssistiveKeyboard.ownsPoint(point, windows: [window(7, x: 200)], keyboardPID: 7, ownPID: 1))
        XCTAssertTrue(AssistiveKeyboard.ownsCocoaPoint(CGPoint(x: 50, y: 950), primaryHeight: 1000,
                                                       windows: [window(7)], keyboardPID: 7), "Cocoa's y is flipped")
    }

    func testOrcaADEPanelsAndQuickJumpWorkInTheVitruvianExtension() throws {
        rig.installBot()
        let tool = tool()
        tool.start(language: "en", handed: [:])

        let expectations: [(String, NexusAgentADEPanel)] = [
            (NexusAgentTool.Command.quickJump, .jumpPalette),
            (NexusAgentTool.Command.raceMode, .raceMode),
            (NexusAgentTool.Command.diffReview, .diffReview),
            (NexusAgentTool.Command.designMode, .designMode),
            (NexusAgentTool.Command.agentInbox, .inbox),
            (NexusAgentTool.Command.tasksDrawer, .tasks),
            (NexusAgentTool.Command.agentCatalog, .accountsAndCatalog),
            (NexusAgentTool.Command.checkpoints, .checkpoints),
            (NexusAgentTool.Command.notes, .notes),
            (NexusAgentTool.Command.automations, .automationsAndOrchestration),
            (NexusAgentTool.Command.orchestration, .automationsAndOrchestration),
        ]

        for (command, expectedPanel) in expectations {
            window.hide()
            try tool.run(command: command)
            XCTAssertTrue(window.isVisible, "running \(command) shows the floating Quick Prompt when undocked")
            XCTAssertEqual(engine.session.mode, .chat)
            XCTAssertEqual(engine.session.activeADEPanel, expectedPanel)
        }

        // Pressing Escape while an ADE panel is open closes the ADE panel first without dismissing the window.
        XCTAssertEqual(engine.session.pressEscape(stoppingReply: false), .closeInlineEditor)
        XCTAssertNil(engine.session.activeADEPanel)

        // Toggling Quick Jump (⌘K) opens and closes .jumpPalette.
        engine.session.toggleQuickJump(configuration: engine.configuration)
        XCTAssertEqual(engine.session.activeADEPanel, .jumpPalette)
        engine.session.toggleQuickJump(configuration: engine.configuration)
        XCTAssertNil(engine.session.activeADEPanel)

        // When docked in the Vitruvian notch/Agents slot, opening an ADE panel keeps it docked in the slot.
        let slot = CGRect(x: 600, y: 860, width: 420, height: 300)
        window.dockIntoSlot(frame: slot)
        let showsBefore = window.shows
        try tool.run(command: NexusAgentTool.Command.raceMode)
        XCTAssertEqual(window.shows, showsBefore, "docked in the Vitruvian slot, opening Race Mode stays in the slot")
        XCTAssertEqual(engine.session.activeADEPanel, .raceMode)

        // Enabling one of the 27 CLI presets persists in the extension's settings.json.
        let preset = try XCTUnwrap(NexusAgentCatalog.allPresets.first(where: { $0.id == "codex" }))
        settings.savedProviders = [NexusAgentCatalog.toCLIProvider(preset)]
        XCTAssertEqual(ToolSettings(folder: folder).savedProviders.map(\.name), [preset.name])
    }
}
