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

import AppKit
import XCTest

import HomeSpeakerCore
import HomeSpeakerToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// The settings panel's Chats section, driven as the app drives it,
/// with credentials that record and a running app the test decides on.
final class ChatSlackTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Account = HomeSpeakerToolTests.Account

    /// Credentials that say what they are told and record what is saved.
    final class Chat: ChatCredentials {
        var token: String?
        var hasChatAccess = false
        var refuses = false
        var saved: [String] = []
        var cleared = 0
        var hasSlackToken: Bool { token != nil }
        func saveSlackToken(_ token: String) throws {
            if refuses { throw CocoaError(.fileWriteNoPermission) }
            saved.append(token)
            self.token = token
        }
        func clearSlackToken() throws {
            if refuses { throw CocoaError(.fileWriteNoPermission) }
            cleared += 1
            token = nil
        }
        var beeperToken: String?
        var beeperSaved: [String] = []
        var beeperCleared = 0
        var hasBeeperToken: Bool { beeperToken != nil }
        func saveBeeperToken(_ token: String) throws {
            if refuses { throw CocoaError(.fileWriteNoPermission) }
            beeperSaved.append(token)
            beeperToken = token
        }
        func clearBeeperToken() throws {
            if refuses { throw CocoaError(.fileWriteNoPermission) }
            beeperCleared += 1
            beeperToken = nil
        }
        var geminiKey: String?
        var geminiSaved: [String] = []
        var geminiCleared = 0
        var hasGeminiKey: Bool { geminiKey != nil }
        func saveGeminiKey(_ key: String) throws {
            if refuses { throw CocoaError(.fileWriteNoPermission) }
            geminiSaved.append(key)
            geminiKey = key
        }
        func clearGeminiKey() throws {
            if refuses { throw CocoaError(.fileWriteNoPermission) }
            geminiCleared += 1
            geminiKey = nil
        }
    }

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var account: Account!
    private var chat: Chat!
    private var gwsPath: String?
    private var appRunning = false
    private var posted = 0
    private var gwsAsked = 0
    private var runningAsked = 0

    override func setUp() {
        link = Link()
        store = Store()
        driver = Driver()
        account = Account()
        chat = Chat()
        gwsPath = nil
        appRunning = false
        posted = 0
        gwsAsked = 0
        runningAsked = 0
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
    }

    private func tool() -> HomeSpeakerTool {
        HomeSpeakerTool(parts: .init(
            link: link, store: store, driver: driver, later: { $0() }, account: account, chat: chat,
            gwsLocation: { [unowned self] in gwsAsked += 1; return gwsPath },
            ownerRunning: { [unowned self] in runningAsked += 1; return appRunning },
            credentialsChanged: { [unowned self] in posted += 1 }, historyURL: HomeSpeakerToolTests.noHistory))
    }

    /// Settings opened on Chats, the login item answered.
    private func opened(choice: Bool = false) -> HomeSpeakerTool {
        link.features = choice ? [.choice] : []
        let tool = tool()
        _ = tool.settingsPage()
        _ = event(tool, Pages.Block.section, .tap, .string(Pages.Section.monitor.rawValue))
        XCTAssertEqual(tool.section, .monitor)
        return tool
    }

    private func page(_ answer: PanelAnswer, file: StaticString = #filePath, line: UInt = #line) -> UITree {
        guard case .page(let tree) = answer else {
            XCTFail("no page: \(answer)", file: file, line: line)
            return UITree(blocks: [])
        }
        return tree
    }

    @discardableResult
    private func event(_ tool: HomeSpeakerTool, _ block: String, _ kind: UIEventKind, _ value: JSONValue? = nil) -> UITree {
        page(tool.settingsEvent(PanelEvent(block: block, kind: kind, value: value)))
    }

    private func ids(_ tree: UITree) -> [String] { tree.blocks.compactMap(\.id) }
    private func content(_ tree: UITree, _ id: String) -> UIBlock.Content? { tree.blocks.first { $0.id == id }?.content }

    private func texts(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .heading(let heading): return heading.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en") + " · " + (row.subtitle?.text(for: "en") ?? "")
            case .button(let button): return button.title.text(for: "en")
            default: return nil
            }
        }
    }

    private func icons(_ tree: UITree) -> [String: String] {
        var icons: [String: String] = [:]
        for block in tree.blocks {
            if case .row(let row) = block.content, let icon = row.icon { icons[row.title.text(for: "en")] = icon }
        }
        return icons
    }

    private func field(_ tree: UITree, _ id: String) -> FieldBlock? {
        if case .field(let f)? = content(tree, id) { return f }
        return nil
    }

    private func toggle(_ tree: UITree, _ id: String) -> ToggleBlock? {
        if case .toggle(let t)? = content(tree, id) { return t }
        return nil
    }

    private func button(_ tree: UITree, _ id: String) -> ButtonBlock? {
        if case .button(let b)? = content(tree, id) { return b }
        return nil
    }

    private var monitor: ChatMonitorConfig { store.config?.effectiveChatMonitor ?? ChatMonitorConfig() }

    private func setMonitor(_ change: (inout ChatMonitorConfig) -> Void) {
        var config = store.config ?? SpeakerConfig()
        change(&config.effectiveChatMonitor)
        store.config = config
    }

    // MARK: - The section

    func testTheSectionHasMonitoringSlackGoogleChatBeeperAndOptions() {
        let tool = opened()
        let tree = tool.settingsPage()
        XCTAssertEqual(texts(tree).filter { ["Background Monitoring", "Slack", "Google Chat", "Beeper", "Options"].contains($0) },
                       ["Background Monitoring", "Slack", "Google Chat", "Beeper", "Options"])
        // Defaults: every source off, Automatic, no tokens, no Chat access,
        // no gws.
        XCTAssertEqual(ids(tree), ["section", "slackEnabled", "slackToken", "saveSlackToken", "googleChatEnabled", "chatSource", "grantChat",
                                   "beeperEnabled", "beeperAnnounce", "beeperToken", "saveBeeperToken", "muteOwnMessages", "pollInterval"])
        XCTAssertEqual(toggle(tree, Pages.Block.slackEnabled)?.title.text(for: "en"), "Announce Slack messages")
        XCTAssertEqual(toggle(tree, Pages.Block.slackEnabled)?.value, false)
        XCTAssertEqual(toggle(tree, Pages.Block.googleChatEnabled)?.title.text(for: "en"), "Announce Google Chat messages")
        XCTAssertEqual(toggle(tree, Pages.Block.muteOwnMessages)?.title.text(for: "en"), "Skip messages I sent")
        XCTAssertEqual(toggle(tree, Pages.Block.muteOwnMessages)?.value, true)
        XCTAssertEqual(field(tree, Pages.Block.slackToken)?.title?.text(for: "en"), "User token (xoxp-…)")
        XCTAssertEqual(field(tree, Pages.Block.slackToken)?.kind, .secret)
        XCTAssertEqual(field(tree, Pages.Block.pollInterval)?.kind, .number)
        XCTAssertEqual(field(tree, Pages.Block.pollInterval)?.value, "15")
        XCTAssertTrue(texts(tree).contains("No Slack token saved · "))
        XCTAssertTrue(texts(tree).contains { $0.contains("gws is not installed") })
    }

    func testTheSectionStaysAcrossRedrawsAndTheSwitcherReturns() {
        let tool = opened()
        XCTAssertNotNil(content(tool.settingsPage(), Pages.Block.slackEnabled))
        let general = event(tool, Pages.Block.section, .tap, .string("general"))
        XCTAssertNil(content(general, Pages.Block.slackEnabled))
        XCTAssertNotNil(content(general, Pages.Block.broadcasting))
    }

    // MARK: - Background monitoring

    func testItSaysWhetherHomeSpeakerIsRunning() {
        appRunning = true
        let tool = opened()
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("HomeSpeaker is running · "))
        XCTAssertEqual(icons(tree)["HomeSpeaker is running"], "bolt.fill")
        XCTAssertTrue(texts(tree).contains { $0.hasPrefix("HomeSpeaker reads new messages in the background while Slack, Google Chat or Beeper is on") })
        appRunning = false
        tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("HomeSpeaker is not running · "))
        XCTAssertFalse(texts(tree).contains { $0.contains("Open HomeSpeaker to start") }, "nothing is on, so nothing waits for it")
        setMonitor { $0.slackEnabled = true }
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.contains("Open HomeSpeaker to start") })
    }

    func testProblemsShowOnlyWhileASourceIsOn() {
        let tool = opened()
        XCTAssertFalse(texts(tool.settingsPage()).contains { $0.contains(ChatMonitorError.slackTokenMissing.localizedDescription) })
        setMonitor { $0.slackEnabled = true }
        var tree = tool.settingsPage()
        let missing = ChatMonitorError.slackTokenMissing.localizedDescription
        XCTAssertTrue(texts(tree).contains("\(missing) · "))
        XCTAssertEqual(icons(tree)[missing], "exclamationmark.triangle.fill")
        chat.token = "xoxp-1"
        XCTAssertFalse(texts(tool.settingsPage()).contains { $0.contains(missing) })

        setMonitor { $0.googleChatEnabled = true; $0.googleChatSource = .gws }
        tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("\(ChatMonitorError.gwsNotInstalled.localizedDescription) · "))
        gwsPath = "/opt/homebrew/bin/gws"
        XCTAssertFalse(texts(tool.settingsPage()).contains { $0.contains(ChatMonitorError.gwsNotInstalled.localizedDescription) })
        setMonitor { $0.googleChatSource = .auto }
        gwsPath = nil
        XCTAssertTrue(texts(tool.settingsPage()).contains("\(ChatMonitorError.noGoogleChatSource.localizedDescription) · "))
        chat.hasChatAccess = true
        XCTAssertFalse(texts(tool.settingsPage()).contains { $0.contains("Google Chat is on but") })
    }

    /// What the page warns of is exactly what the monitor would refuse.
    func testTheWarningsAreTheMonitorsOwnRules() {
        for source in ChatMonitorConfig.GoogleChatSource.allCases {
            for (token, access, gws) in [(false, false, false), (true, false, true), (false, true, false), (true, true, true)] {
                var status = Pages.Status()
                status.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true, googleChatSource: source)
                status.chat = Pages.Chat(hasSlackToken: token, hasChatAccess: access, gwsPath: gws ? "/usr/local/bin/gws" : nil)
                XCTAssertEqual(Pages.monitorProblems(status),
                               ChatMonitorService.setupProblems(config: status.config.effectiveChatMonitor, hasSlackToken: token,
                                                                hasChatScopes: access, gwsInstalled: gws, hasBeeperToken: false))
            }
        }
        XCTAssertEqual(Pages.monitorProblems(Pages.Status()), [])
    }

    func testTheEnvironmentIsAskedOnlyOnChatAndSlack() {
        let tool = tool()
        _ = tool.settingsPage()
        _ = tool.settingsPage()
        _ = tool.islandPage()
        XCTAssertEqual(gwsAsked, 0, "General never looks for gws")
        XCTAssertEqual(runningAsked, 0)
        _ = event(tool, Pages.Block.section, .tap, .string("monitor"))
        XCTAssertGreaterThan(gwsAsked, 0)
        XCTAssertGreaterThan(runningAsked, 0)
    }

    // MARK: - Slack

    func testTheSlackToggleIsSavedToTheFile() {
        let tool = opened()
        let tree = event(tool, Pages.Block.slackEnabled, .toggle, .bool(true))
        XCTAssertTrue(monitor.slackEnabled)
        XCTAssertEqual(toggle(tree, Pages.Block.slackEnabled)?.value, true)
        XCTAssertEqual(store.saves, 1)
        XCTAssertEqual(posted, 0, "a settings change reaches the app through the file, not the notice")
        event(tool, Pages.Block.slackEnabled, .toggle, .bool(false))
        XCTAssertFalse(monitor.slackEnabled)
    }

    func testATokenIsSavedTrimmedAndTheAppIsTold() {
        let tool = opened()
        let tree = event(tool, Pages.Block.slackToken, .submit, .string("  xoxp-secret-123 \n"))
        XCTAssertEqual(chat.saved, ["xoxp-secret-123"])
        XCTAssertEqual(posted, 1)
        XCTAssertEqual(tool.setupNotice, "Slack token saved")
        XCTAssertTrue(texts(tree).contains("Slack token saved · "))
        XCTAssertEqual(icons(tree)["Slack token saved"], "checkmark.circle.fill")
        XCTAssertEqual(button(tree, Pages.Block.clearSlackToken)?.title.text(for: "en"), "Clear Slack Token")
        XCTAssertEqual(store.saves, 0, "the token never goes in the settings file")
    }

    func testTheTokenNeverEntersThePageOrItsState() throws {
        let secret = "xoxp-very-secret-token"
        chat.token = secret
        let tool = opened()
        var tree = event(tool, Pages.Block.slackToken, .submit, .string(secret))
        XCTAssertEqual(field(tree, Pages.Block.slackToken)?.value, "", "the field is always empty")
        let json = String(decoding: try JSONEncoder().encode(tree), as: UTF8.self)
        XCTAssertFalse(json.contains(secret))
        XCTAssertFalse(String(describing: tool.status()).contains(secret))
        XCTAssertFalse(tool.setupNotice?.contains(secret) ?? false)
        XCTAssertFalse(link.logged.contains { $0.contains(secret) })
        XCTAssertFalse(link.messages.contains { $0.contains(secret) })
        tree = tool.settingsPage()
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(tree), as: UTF8.self).contains(secret))
        XCTAssertFalse(link.rendered.contains { String(decoding: (try? JSONEncoder().encode($0.tree)) ?? Data(), as: UTF8.self).contains(secret) })
    }

    func testAnEmptyTokenClearsIt() {
        chat.token = "xoxp-old"
        let tool = opened()
        let tree = event(tool, Pages.Block.slackToken, .submit, .string("   \n "))
        XCTAssertEqual(chat.cleared, 1)
        XCTAssertEqual(chat.saved, [])
        XCTAssertFalse(chat.hasSlackToken)
        XCTAssertEqual(posted, 1)
        XCTAssertEqual(tool.setupNotice, "Slack token cleared")
        XCTAssertTrue(texts(tree).contains("No Slack token saved · "))
        XCTAssertNil(content(tree, Pages.Block.clearSlackToken))
    }

    func testClearSlackTokenClearsItAndTellsTheApp() {
        chat.token = "xoxp-old"
        let tool = opened()
        XCTAssertNotNil(button(tool.settingsPage(), Pages.Block.clearSlackToken))
        let tree = event(tool, Pages.Block.clearSlackToken, .tap)
        XCTAssertEqual(chat.cleared, 1)
        XCTAssertEqual(posted, 1)
        XCTAssertNil(content(tree, Pages.Block.clearSlackToken))
    }

    func testOnlyReturnSavesATokenNotLeavingTheField() {
        let tool = opened()
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.slackToken, kind: .change, value: .string("xoxp-half"))), .keep)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.slackToken, kind: .submit)), .keep)
        XCTAssertEqual(chat.saved, [])
        XCTAssertEqual(chat.cleared, 0)
        XCTAssertEqual(posted, 0)
    }

    /// As HomeSpeaker's own Settings has: paste, then Save Token. The
    /// paste is held (no redraw, which would wipe the field) until then.
    func testSaveTokenSavesWhatWasPasted() throws {
        let tool = opened()
        var tree = tool.settingsPage()
        XCTAssertEqual(button(tree, Pages.Block.saveSlackToken)?.title.text(for: "en"), "Save Token")
        XCTAssertEqual(button(tree, Pages.Block.saveBeeperToken)?.title.text(for: "en"), "Save Token")
        let slackAt = try XCTUnwrap(ids(tree).firstIndex(of: Pages.Block.slackToken))
        XCTAssertEqual(ids(tree)[slackAt + 1], Pages.Block.saveSlackToken, "right under its field")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.slackToken, kind: .change, value: .string(" xoxp-pasted "))), .keep)
        XCTAssertEqual(chat.saved, [])
        tree = event(tool, Pages.Block.saveSlackToken, .tap)
        XCTAssertEqual(chat.saved, ["xoxp-pasted"])
        XCTAssertEqual(posted, 1)
        XCTAssertEqual(tool.setupNotice, "Slack token saved")
        XCTAssertEqual(tool.draftSlackToken, "")
        XCTAssertTrue(texts(tree).contains("Slack token saved · "))

        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.beeperToken, kind: .change, value: .string("beeper-pasted"))), .keep)
        tree = event(tool, Pages.Block.saveBeeperToken, .tap)
        XCTAssertEqual(chat.beeperSaved, ["beeper-pasted"])
        XCTAssertEqual(tool.setupNotice, "Beeper token saved")
        XCTAssertTrue(texts(tree).contains("Beeper token saved · "))
    }

    /// Vitruvian 3.61 and earlier send a field's text only when the field
    /// is left, and clicking Save Token does not leave it: the paste never
    /// arrives. Save Token then takes the token from the clipboard, where
    /// the paste came from.
    func testSaveTokenInSettingsTakesAPasteThatNeverArrivedFromTheClipboard() {
        let tool = opened()
        link.clipboard = "  xoxp-from-clipboard \n"
        event(tool, Pages.Block.saveSlackToken, .tap)
        XCTAssertEqual(chat.saved, ["xoxp-from-clipboard"])
        XCTAssertEqual(tool.setupNotice, "Slack token saved")

        link.clipboard = "beeper-from-clipboard"
        event(tool, Pages.Block.saveBeeperToken, .tap)
        XCTAssertEqual(chat.beeperSaved, ["beeper-from-clipboard"])
        XCTAssertEqual(tool.setupNotice, "Beeper token saved")
        XCTAssertEqual(posted, 2)
    }

    func testSaveTokenOnTheIslandTakesAPasteThatNeverArrivedFromTheClipboard() throws {
        setMonitor {
            $0.slackEnabled = true
            $0.beeperEnabled = true
        }
        let tool = tool()
        _ = tool.islandPage()
        link.clipboard = "beeper-from-clipboard"
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.saveBeeperToken, kind: .tap))
        XCTAssertEqual(chat.beeperSaved, ["beeper-from-clipboard"])
        XCTAssertEqual(tool.notice, "Beeper token saved")
        link.clipboard = "xoxb-from-clipboard"
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.saveSlackToken, kind: .tap))
        XCTAssertEqual(chat.saved, ["xoxb-from-clipboard"])
        XCTAssertEqual(tool.notice, "Slack token saved")
    }

    /// What was typed wins over the clipboard, and a clipboard that is no
    /// token is never saved.
    func testSaveTokenPrefersTheFieldAndTakesOnlyATokenFromTheClipboard() {
        let tool = opened()
        link.clipboard = "xoxp-on-clipboard"
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.slackToken, kind: .change, value: .string("xoxp-typed")))
        event(tool, Pages.Block.saveSlackToken, .tap)
        XCTAssertEqual(chat.saved, ["xoxp-typed"], "the field's text, not the clipboard's")

        for clip in ["not a token", "https://example.com/x", ""] {
            link.clipboard = clip
            event(tool, Pages.Block.saveSlackToken, .tap)
            XCTAssertEqual(tool.setupNotice, "Paste the Slack token first", "\(clip) is no Slack token")
        }
        link.clipboard = "two words"
        event(tool, Pages.Block.saveBeeperToken, .tap)
        XCTAssertEqual(tool.setupNotice, "Paste the Beeper token first")
        XCTAssertEqual(chat.saved, ["xoxp-typed"])
        XCTAssertEqual(chat.beeperSaved, [])
        XCTAssertEqual(chat.cleared, 0)
        XCTAssertEqual(chat.beeperCleared, 0)
    }

    func testAnEmptySaveTokenNeverClears() {
        chat.token = "xoxp-old"
        chat.beeperToken = "old"
        let tool = opened()
        event(tool, Pages.Block.saveSlackToken, .tap)
        XCTAssertEqual(tool.setupNotice, "Paste the Slack token first")
        event(tool, Pages.Block.saveBeeperToken, .tap)
        XCTAssertEqual(tool.setupNotice, "Paste the Beeper token first")
        XCTAssertEqual(chat.cleared, 0)
        XCTAssertEqual(chat.beeperCleared, 0)
        XCTAssertEqual(posted, 0)
    }

    func testADraftDoesNotOutliveClosingSettings() {
        let tool = opened()
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.slackToken, kind: .change, value: .string("xoxp-half")))
        tool.panelClosed(HomeSpeakerTool.settingsPanel)
        _ = tool.settingsPage()
        XCTAssertEqual(tool.draftSlackToken, "")
    }

    func testSavingInSettingsRedrawsAnOpenIsland() {
        setMonitor { $0.slackEnabled = true }
        let tool = opened()
        _ = tool.islandPage()
        link.rendered = []
        event(tool, Pages.Block.slackToken, .submit, .string("xoxp-1"))
        XCTAssertEqual(link.rendered.map(\.panel), [HomeSpeakerTool.islandPanel])
        XCTAssertFalse(link.rendered.last?.tree.blocks.contains { $0.id == Pages.Block.slackToken } ?? true,
                       "the island's token field goes")
    }

    func testAFailedSaveIsSaidAndTheAppIsNotTold() {
        chat.refuses = true
        let tool = opened()
        _ = event(tool, Pages.Block.slackToken, .submit, .string("xoxp-1"))
        XCTAssertEqual(posted, 0)
        XCTAssertNotNil(tool.setupNotice)
        XCTAssertNotEqual(tool.setupNotice, "Slack token saved")
    }

    // MARK: - Beeper

    func testTheBeeperControlsAreDrawnAndSaved() {
        let tool = opened(choice: true)
        var tree = tool.settingsPage()
        XCTAssertEqual(toggle(tree, Pages.Block.beeperEnabled)?.title.text(for: "en"), "Announce Beeper messages")
        XCTAssertEqual(toggle(tree, Pages.Block.beeperEnabled)?.value, false)
        XCTAssertEqual(field(tree, Pages.Block.beeperToken)?.title?.text(for: "en"), "Access token")
        XCTAssertEqual(field(tree, Pages.Block.beeperToken)?.kind, .secret)
        XCTAssertTrue(texts(tree).contains("No Beeper token saved · "))
        XCTAssertTrue(texts(tree).contains(Pages.beeperHelp))
        guard case .choice(let announce)? = content(tree, Pages.Block.beeperAnnounce) else { return XCTFail("no choice") }
        XCTAssertEqual(announce.title?.text(for: "en"), "Announce")
        XCTAssertEqual(announce.value, "direct_and_mentions")
        XCTAssertEqual(announce.options.map(\.value), ["direct_and_mentions", "all"])
        XCTAssertEqual(announce.options.map { $0.title.text(for: "en") }, ["Direct messages and mentions", "Every message"])

        tree = event(tool, Pages.Block.beeperEnabled, .toggle, .bool(true))
        XCTAssertTrue(monitor.beeperEnabled)
        XCTAssertEqual(toggle(tree, Pages.Block.beeperEnabled)?.value, true)
        event(tool, Pages.Block.beeperAnnounce, .change, .string("all"))
        XCTAssertEqual(monitor.beeperAnnounce, .all)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.beeperAnnounce, kind: .change, value: .string("vips"))), .keep)
        XCTAssertEqual(monitor.beeperAnnounce, .all)
        XCTAssertEqual(store.saves, 2)
        XCTAssertEqual(posted, 0, "a settings change reaches HomeSpeaker through the file, not the notice")
        // On with no token: the monitor's own setup problem.
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.hasPrefix(ChatMonitorError.beeperTokenMissing.localizedDescription) })
    }

    func testABeeperTokenIsSavedTrimmedNeverShownAndTheMonitorIsTold() throws {
        let secret = "fake-beeper-token-for-the-tool-test" // gitleaks:allow (made-up test token)
        let tool = opened()
        var tree = event(tool, Pages.Block.beeperToken, .submit, .string("  \(secret) \n"))
        XCTAssertEqual(chat.beeperSaved, [secret])
        XCTAssertEqual(posted, 1)
        XCTAssertEqual(tool.setupNotice, "Beeper token saved")
        XCTAssertTrue(texts(tree).contains("Beeper token saved · "))
        XCTAssertEqual(button(tree, Pages.Block.clearBeeperToken)?.title.text(for: "en"), "Clear Beeper Token")
        XCTAssertEqual(field(tree, Pages.Block.beeperToken)?.value, "", "the field is always empty")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(tree), as: UTF8.self).contains(secret))
        XCTAssertFalse(link.logged.contains { $0.contains(secret) })
        XCTAssertEqual(store.saves, 0, "the token never goes in the settings file")

        tree = event(tool, Pages.Block.clearBeeperToken, .tap)
        XCTAssertEqual(chat.beeperCleared, 1)
        XCTAssertEqual(posted, 2)
        XCTAssertNil(content(tree, Pages.Block.clearBeeperToken))
        // Empty clears; leaving the field half-typed saves nothing.
        chat.beeperToken = "old"
        event(tool, Pages.Block.beeperToken, .submit, .string("  "))
        XCTAssertEqual(chat.beeperCleared, 2)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.beeperToken, kind: .change, value: .string("half"))), .keep)
        XCTAssertEqual(chat.beeperSaved, [secret])
    }

    func testStartIsOfferedWithOnlyBeeperOn() {
        appRunning = true
        setMonitor { $0.beeperEnabled = true }
        XCTAssertTrue(ids(opened().settingsPage()).contains(Pages.Block.startChatMonitor))
    }

    // MARK: - Google Chat

    func testTheGoogleChatToggleAndSourceAreSaved() {
        let tool = opened(choice: true)
        event(tool, Pages.Block.googleChatEnabled, .toggle, .bool(true))
        XCTAssertTrue(monitor.googleChatEnabled)
        guard case .choice(let via)? = content(tool.settingsPage(), Pages.Block.chatSource) else { return XCTFail("no choice") }
        XCTAssertEqual(via.title?.text(for: "en"), "Read Google Chat via")
        XCTAssertEqual(via.value, "auto")
        XCTAssertEqual(via.options.map(\.value), ["auto", "api", "gws"])
        XCTAssertEqual(via.options.map { $0.title.text(for: "en") },
                       ["Automatic", "Google API (this app's login)", "gws command-line tool"])
        event(tool, Pages.Block.chatSource, .change, .string("gws"))
        XCTAssertEqual(monitor.googleChatSource, .gws)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.chatSource, kind: .change, value: .string("carrier-pigeon"))),
                       .keep)
        XCTAssertEqual(monitor.googleChatSource, .gws)
    }

    func testWithoutChoiceTheSourceIsAList() {
        let tool = opened()
        guard case .list(let via)? = content(tool.settingsPage(), Pages.Block.chatSource) else { return XCTFail("no list") }
        XCTAssertEqual(via.rows.map(\.id), ["auto", "api", "gws"])
        XCTAssertEqual(via.rows.map { $0.trailing?.text(for: "en") }, ["✓", nil, nil])
        XCTAssertTrue(texts(tool.settingsPage()).contains("Read Google Chat via"))
        let tree = event(tool, Pages.Block.chatSource, .tap, .string("api"))
        XCTAssertEqual(monitor.googleChatSource, .api)
        guard case .list(let picked)? = content(tree, Pages.Block.chatSource) else { return XCTFail("no list") }
        XCTAssertEqual(picked.rows.map { $0.trailing?.text(for: "en") }, [nil, "✓", nil])
    }

    func testWithoutChatAccessGrantSignsInForChat() {
        let tool = opened()
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Google grants Chat access separately from Home — a second sign-in."))
        XCTAssertEqual(button(tree, Pages.Block.grantChat)?.title.text(for: "en"), "Grant…")
        XCTAssertNil(content(tree, Pages.Block.disconnectChat))
        tree = event(tool, Pages.Block.grantChat, .tap)
        XCTAssertEqual(driver.jobs.last, .signIn(chatOnly: true))
        XCTAssertEqual(ProcessDriver.arguments(for: driver.jobs.last!), ["--sign-in", "--chat"])
        XCTAssertEqual(button(tree, Pages.Block.grantChat)?.enabled, false, "one sign-in at a time")
        chat.hasChatAccess = true
        driver.answer(.signIn(chatOnly: true), .done(["signed in as me@example.com; scopes: chat"]))
        XCTAssertEqual(tool.setupNotice, "Google Chat access granted")
        XCTAssertEqual(driver.jobs.count, 1, "a Chat sign-in finds no speakers")
        tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Chat access granted · "))
        XCTAssertEqual(icons(tree)["Chat access granted"], "checkmark.circle.fill")
        XCTAssertNil(content(tree, Pages.Block.grantChat))
    }

    func testDisconnectSignsOutOfChatOnly() {
        chat.hasChatAccess = true
        let tool = opened()
        let tree = tool.settingsPage()
        XCTAssertEqual(button(tree, Pages.Block.disconnectChat)?.title.text(for: "en"), "Disconnect")
        _ = event(tool, Pages.Block.disconnectChat, .tap)
        XCTAssertEqual(driver.jobs.last, .app(.signOut(chatOnly: true)))
        XCTAssertEqual(ProcessDriver.arguments(for: driver.jobs.last!), ["--sign-out", "--chat"])
        chat.hasChatAccess = false
        driver.answer(.app(.signOut(chatOnly: true)), .done(["signed out of Google Chat"]))
        XCTAssertEqual(tool.setupNotice, "Signed out of Google Chat")
        XCTAssertNotNil(content(tool.settingsPage(), Pages.Block.grantChat))
    }

    func testWithoutHomeSpeakerGrantAndDisconnectAreOff() {
        driver.isInstalled = false
        let tool = tool()
        _ = tool.settingsPage()
        let tree = event(tool, Pages.Block.section, .tap, .string("monitor"))
        XCTAssertEqual(button(tree, Pages.Block.grantChat)?.enabled, false)
        chat.hasChatAccess = true
        XCTAssertEqual(button(tool.settingsPage(), Pages.Block.disconnectChat)?.enabled, false)
        // The Slack token needs no HomeSpeaker: it is the secrets file.
        _ = event(tool, Pages.Block.slackToken, .submit, .string("xoxp-1"))
        XCTAssertEqual(chat.saved, ["xoxp-1"])
    }

    func testGwsIsShownWhereItIsAndItsAccountSaved() {
        gwsPath = "/opt/homebrew/bin/gws"
        setMonitor { $0.gwsAccount = "me@example.com" }
        let tool = opened()
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("gws is installed · /opt/homebrew/bin/gws"))
        XCTAssertTrue(texts(tree).contains { $0.contains("gws auth login") })
        XCTAssertEqual(field(tree, Pages.Block.gwsAccount)?.title?.text(for: "en"), "gws account (optional, e.g. you@gmail.com)")
        XCTAssertEqual(field(tree, Pages.Block.gwsAccount)?.value, "me@example.com")
        tree = event(tool, Pages.Block.gwsAccount, .submit, .string("  you@gmail.com "))
        XCTAssertEqual(monitor.gwsAccount, "you@gmail.com")
        XCTAssertEqual(field(tree, Pages.Block.gwsAccount)?.value, "you@gmail.com")
        event(tool, Pages.Block.gwsAccount, .change, .string(""))
        XCTAssertEqual(monitor.gwsAccount, "", "empty is gws's own default account")
    }

    func testEachSourceShowsOnlyItsOwnSetup() {
        gwsPath = "/usr/local/bin/gws"
        let tool = opened()
        // Automatic: both.
        var tree = tool.settingsPage()
        XCTAssertNotNil(content(tree, Pages.Block.grantChat))
        XCTAssertNotNil(content(tree, Pages.Block.gwsAccount))
        // The API: no gws.
        tree = event(tool, Pages.Block.chatSource, .tap, .string("api"))
        XCTAssertNotNil(content(tree, Pages.Block.grantChat))
        XCTAssertNil(content(tree, Pages.Block.gwsAccount))
        XCTAssertFalse(texts(tree).contains { $0.contains("gws is installed") })
        // gws: no Grant, no Disconnect.
        tree = event(tool, Pages.Block.chatSource, .tap, .string("gws"))
        XCTAssertNil(content(tree, Pages.Block.grantChat))
        XCTAssertNil(content(tree, Pages.Block.disconnectChat))
        XCTAssertNotNil(content(tree, Pages.Block.gwsAccount))
        chat.hasChatAccess = true
        XCTAssertFalse(texts(tool.settingsPage()).contains { $0.contains("Chat access granted") })
        // gws not installed: said, and no account field.
        gwsPath = nil
        tree = tool.settingsPage()
        XCTAssertNil(content(tree, Pages.Block.gwsAccount))
        XCTAssertTrue(texts(tree).contains("gws is not installed. Install the Google Workspace CLI and run gws auth login to use it."))
    }

    // MARK: - Options

    func testSkipMessagesISentIsSaved() {
        let tool = opened()
        event(tool, Pages.Block.muteOwnMessages, .toggle, .bool(false))
        XCTAssertFalse(monitor.muteOwnMessages)
        XCTAssertEqual(toggle(tool.settingsPage(), Pages.Block.muteOwnMessages)?.value, false)
    }

    func testThePollIntervalTakesOnlyWhatTheMonitorAccepts() {
        let tool = opened()
        XCTAssertEqual(field(tool.settingsPage(), Pages.Block.pollInterval)?.title?.text(for: "en"),
                       "Poll interval (\(ChatMonitorConfig.minPollInterval) to \(ChatMonitorConfig.maxPollInterval) s)")
        event(tool, Pages.Block.pollInterval, .submit, .string(" 60 "))
        XCTAssertEqual(monitor.pollIntervalSeconds, 60)
        let saves = store.saves
        // Out of range or no number: refused and said, never quietly clamped.
        for bad in ["1", "100000", "soon"] {
            let tree = event(tool, Pages.Block.pollInterval, .change, .string(bad))
            XCTAssertEqual(monitor.pollIntervalSeconds, 60, bad)
            XCTAssertEqual(tool.setupNotice, HomeSpeakerTool.Invalid.pollInterval, bad)
            XCTAssertEqual(field(tree, Pages.Block.pollInterval)?.value, "60", "\(bad): the field shows what is saved")
        }
        XCTAssertEqual(store.saves, saves, "nothing saved")
        event(tool, Pages.Block.pollInterval, .submit, .string(String(ChatMonitorConfig.maxPollInterval)))
        XCTAssertEqual(monitor.pollIntervalSeconds, ChatMonitorConfig.maxPollInterval)
        XCTAssertEqual(HomeSpeakerTool.clampedPollInterval(-5), ChatMonitorConfig.minPollInterval)
        XCTAssertEqual(HomeSpeakerTool.clampedPollInterval(30), 30)
    }

    /// A value out of range written by hand shows as the monitor uses it.
    func testTheFieldShowsTheClampedInterval() {
        setMonitor { $0.pollIntervalSeconds = 2 }
        let tool = opened()
        XCTAssertEqual(field(tool.settingsPage(), Pages.Block.pollInterval)?.value, String(ChatMonitorConfig.minPollInterval))
    }

    func testChatSettingsKeepTheRestOfTheFile() {
        let tool = opened()
        event(tool, Pages.Block.slackEnabled, .toggle, .bool(true))
        event(tool, Pages.Block.pollInterval, .submit, .string("30"))
        XCTAssertEqual(store.config?.defaultTarget, "kitchen")
        XCTAssertEqual(store.config?.enabled, true)
        XCTAssertEqual(monitor.slackEnabled, true)
        XCTAssertEqual(monitor.pollIntervalSeconds, 30)
    }

    func testACorruptFileIsNeverWrittenFromChatAndSlack() {
        let tool = opened()
        store.corrupt = "not JSON"
        _ = event(tool, Pages.Block.slackEnabled, .toggle, .bool(true))
        XCTAssertEqual(store.saves, 0)
        XCTAssertTrue(link.logged.contains { $0.contains("refusing to save") })
    }

    // MARK: - The Antigravity import tells the app

    func testTheAntigravityImportTellsTheApp() {
        account.hasAntigravityTokens = true
        let tool = tool()
        _ = tool.settingsPage()
        _ = event(tool, Pages.Block.importAntigravity, .tap)
        XCTAssertEqual(account.imports, 1)
        XCTAssertEqual(posted, 1)
        account.importFinds = false
        _ = event(tool, Pages.Block.importAntigravity, .tap)
        XCTAssertEqual(posted, 1, "nothing imported, nothing to tell")
    }

    // MARK: - The general footer

    func testTheGeneralPageNoLongerSendsAnythingToHomeSpeaker() {
        let page = Pages.settings(Pages.Status())
        XCTAssertFalse(texts(page).contains { $0.contains("set up in HomeSpeaker") }, "agents and Google Cloud are set up here now")
        XCTAssertFalse(texts(page).contains { $0.contains("coding-agent hooks") })
    }

    // MARK: - Beeper's networks

    func testTheMonitorSectionHasTheSameSwitches() throws {
        var status = Pages.Status()
        status.section = .monitor
        status.offersChoice = true
        status.config.effectiveChatMonitor = ChatMonitorConfig(beeperEnabled: true, beeperMutedNetworks: ["telegram"])
        status.chat = Pages.Chat(ownerRunning: true, monitor: ChatMonitorStatus(isRunning: true, beeperNetworkStates: [
            BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
            BeeperNetworkState(key: "slackgo", name: "Slack", state: .skipped),
            BeeperNetworkState(key: "telegram", name: "Telegram", state: .muted),
        ]), hasBeeperToken: true)
        let settings = Pages.settings(status)
        let order = ids(settings)
        let announceAt = try XCTUnwrap(order.firstIndex(of: Pages.Block.beeperAnnounce))
        XCTAssertEqual(Array(order[(announceAt + 1)...].prefix(4)),
                       ["beeper.network.slackgo", "beeper.network.telegram", "beeper.network.whatsapp", Pages.Block.beeperToken],
                       "after its Announce picker, before the token")
        // The island's switches, block for block.
        let island = Pages.island(status)
        func networkBlocks(_ tree: UITree) -> [UIBlock] {
            let blocks = tree.blocks
            guard let at = blocks.firstIndex(where: { $0.id == Pages.Block.beeperAnnounce }) else { return [] }
            return Array(blocks[(at + 1)...].prefix { $0.id.map { Pages.Block.beeperNetworkKey($0) != nil } ?? true })
        }
        XCTAssertEqual(networkBlocks(settings).count, 4, "the caption and three switches")
        XCTAssertEqual(networkBlocks(settings), networkBlocks(island))
        // Announce itself is one picker on both pages.
        XCTAssertEqual(settings.blocks.first { $0.id == Pages.Block.beeperAnnounce },
                       island.blocks.first { $0.id == Pages.Block.beeperAnnounce })
        XCTAssertEqual(Pages.settings({ var general = status; general.section = .general; return general }()).blocks
                        .first { $0.id == Pages.Block.speechLength },
                       island.blocks.first { $0.id == Pages.Block.speechLength })
    }

    func testTheMonitorSectionHasTheSameChips() throws {
        var status = Pages.Status()
        status.section = .monitor
        status.offersChoice = true
        status.offersChips = true
        status.config.effectiveChatMonitor = ChatMonitorConfig(beeperEnabled: true, beeperMutedNetworks: ["telegram"])
        status.chat = Pages.Chat(ownerRunning: true, monitor: ChatMonitorStatus(isRunning: true, beeperNetworkStates: [
            BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
            BeeperNetworkState(key: "slackgo", name: "Slack", state: .skipped),
        ]), hasBeeperToken: true)
        let settings = Pages.settings(status)
        let order = ids(settings)
        let announceAt = try XCTUnwrap(order.firstIndex(of: Pages.Block.beeperAnnounce))
        XCTAssertEqual(Array(order[(announceAt + 1)...].prefix(2)), [Pages.Block.beeperNetworks, Pages.Block.beeperToken],
                       "one block after its Announce picker, before the token")
        XCTAssertFalse(texts(settings).contains("Networks"), "the block's title is the caption")
        XCTAssertTrue(order.allSatisfy { Pages.Block.beeperNetworkKey($0) == nil }, "no switch each")
        // The island's block, as it is.
        let island = Pages.island(status)
        let block = try XCTUnwrap(settings.blocks.first { $0.id == Pages.Block.beeperNetworks })
        XCTAssertEqual(block, island.blocks.first { $0.id == Pages.Block.beeperNetworks })
        guard case .chips(let chips) = block.content else { return XCTFail("not chips: \(block)") }
        XCTAssertEqual(chips.options.map(\.value), ["slackgo", "telegram", "whatsapp"])
    }

    func testNetworkChipsChangedInTheSectionAreSaved() {
        setMonitor { $0.beeperEnabled = true; $0.beeperMutedNetworks = ["signal", "telegram"] }
        let tool = opened(choice: true)
        link.features = [.choice, .chips]
        let tree = event(tool, Pages.Block.beeperNetworks, .change, .array([.string("signal")]))
        XCTAssertEqual(monitor.beeperMutedNetworks, ["telegram"])
        guard case .chips(let chips)? = tree.blocks.first(where: { $0.id == Pages.Block.beeperNetworks })?.content else {
            return XCTFail("no chips")
        }
        // Not being read, so only the saved mutes are chips: Signal, read
        // again, is no longer one, as its switch was not.
        XCTAssertEqual(chips.options, [UIChipOption(value: "telegram", title: .plain("telegram"), on: false)])
    }

    func testANetworkSwitchedInTheSectionIsSaved() {
        setMonitor { $0.beeperEnabled = true }
        let tool = opened(choice: true)
        // Beeper on and not being read: the caption and where networks will show.
        let before = texts(tool.settingsPage())
        XCTAssertTrue(before.contains("Networks") && before.contains(Pages.beeperNetworksLater))
        let tree = event(tool, "beeper.network.signal", .toggle, .bool(false))
        XCTAssertEqual(monitor.beeperMutedNetworks, ["signal"])
        XCTAssertEqual(toggle(tree, "beeper.network.signal")?.value, false)
        event(tool, "beeper.network.signal", .toggle, .bool(true))
        XCTAssertEqual(monitor.beeperMutedNetworks, [])
    }

    // MARK: - Limits

    func testTheSectionIsWithinTheProtocolsLimits() throws {
        var status = Pages.Status()
        status.section = .monitor
        status.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true,
                                                               gwsAccount: String(repeating: "a", count: 300), beeperEnabled: true)
        // Every line the section can draw: tokens saved, running, every
        // network Beeper has read and skipped, a long error.
        let networks = (0..<30).map { "Network \($0) " + String(repeating: "n", count: 40) }
        status.chat = Pages.Chat(
            hasSlackToken: true, hasChatAccess: true, gwsPath: "/" + String(repeating: "p", count: 1000), ownerRunning: true,
            monitor: ChatMonitorStatus(isRunning: true, lastPollDate: Date(), lastError: String(repeating: "e", count: 2000),
                                       slackIdentity: "alice", activeGoogleChatBackend: "api", beeperNetworks: networks,
                                       beeperSkippedNetworks: networks, beeperNetworkStates: Self.manyNetworkStates()),
            hasBeeperToken: true)
        status.config.effectiveChatMonitor.beeperMutedNetworks = (0..<30).map { "saved-mute-\($0)" }
        status.configProblem = String(repeating: "x", count: 300)
        // Not exercised: every section on one page with a switch a network
        // and more than 64 of them. An app that draws sections draws chips
        // too, and chips carry up to 64 networks; switches stand in only
        // past that, which no Beeper account comes near.
        for (choice, offersChips) in [(false, false), (true, false), (true, true)] {
            status.offersChoice = choice
            status.offersChips = offersChips
            let tree = Pages.settings(status)
            if offersChips {
                guard case .chips(let chips)? = tree.blocks.first(where: { $0.id == Pages.Block.beeperNetworks })?.content else {
                    return XCTFail("no chips")
                }
                XCTAssertEqual(chips.options.count, 60, "30 listed and 30 saved")
                // What the app reads back: the block decodes, so within the kit's rules.
                let block = try XCTUnwrap(tree.blocks.first { $0.id == Pages.Block.beeperNetworks })
                XCTAssertEqual(try JSONDecoder().decode(UIBlock.self, from: JSONEncoder().encode(block)), block)
            } else {
                XCTAssertGreaterThanOrEqual(tree.blocks.filter { $0.id.map { Pages.Block.beeperNetworkKey($0) != nil } ?? false }.count, 30)
            }
            XCTAssertLessThan(try JSONEncoder().encode(tree).count, UILimits.maxTreeBytes)
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks)
        }
    }

    // MARK: Announcement style and the Gemini voice

    private func settings(on section: Pages.Section, sections: Bool = false) -> HomeSpeakerTool {
        link.features = sections ? [.sections] : []
        let tool = tool()
        _ = tool.settingsPage()
        if !sections { _ = event(tool, Pages.Block.section, .tap, .string(section.rawValue)) }
        return tool
    }

    private func islandPage(_ answer: PanelAnswer, file: StaticString = #filePath, line: UInt = #line) -> UITree {
        page(answer, file: file, line: line)
    }

    private var saved: SpeakerConfig { store.config ?? SpeakerConfig() }

    func testTheIslandPicksTheStyleAndCustomAsksForItsInstruction() throws {
        let tool = tool()
        var tree = tool.islandPage()
        let at = try XCTUnwrap(ids(tree).firstIndex(of: Pages.Block.speechLength))
        XCTAssertEqual(ids(tree)[at + 1], Pages.Block.announcementStyle, "right below Speak")
        XCTAssertNil(content(tree, Pages.Block.customStylePrompt))

        tree = islandPage(tool.islandEvent(PanelEvent(block: Pages.Block.announcementStyle, kind: .change, value: .string("custom"))))
        XCTAssertEqual(saved.effectiveAnnouncementStyle, .custom)
        XCTAssertEqual(ids(tree)[at + 2], Pages.Block.customStylePrompt)
        XCTAssertEqual(field(tree, Pages.Block.customStylePrompt)?.title?.text(for: "en"), "Custom style")
        XCTAssertEqual(field(tree, Pages.Block.customStylePrompt)?.placeholder?.text(for: "en"),
                       "e.g. One short sentence, like a ship captain")

        // Saved as it is typed, with no redraw to move the cursor.
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.customStylePrompt, kind: .change,
                                                   value: .string("like a pirate "))), .keep)
        XCTAssertEqual(saved.customStylePrompt, "like a pirate ")
        tree = islandPage(tool.islandEvent(PanelEvent(block: Pages.Block.customStylePrompt, kind: .submit,
                                                      value: .string("like a pirate"))))
        XCTAssertEqual(saved.effectiveCustomStylePrompt, "like a pirate")
        XCTAssertEqual(field(tree, Pages.Block.customStylePrompt)?.value, "like a pirate")

        // A style this version does not know changes nothing.
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.announcementStyle, kind: .change, value: .string("haiku"))), .keep)
        XCTAssertEqual(saved.effectiveAnnouncementStyle, .custom)
        // The island's picker is Settings' picker.
        XCTAssertEqual(tree.blocks.first { $0.id == Pages.Block.announcementStyle },
                       Pages.settings({ var s = Pages.Status(); s.config = saved; return s }()).blocks
                        .first { $0.id == Pages.Block.announcementStyle })
    }

    func testTheIslandAsksForTheGeminiKeyOnlyWhileGeminiSpeaksWithoutOne() throws {
        var config = saved
        config.effectiveSpeakLocal = true
        store.config = config
        let tool = tool()
        XCTAssertNil(content(tool.islandPage(), Pages.Block.geminiApiKey), "the Mac voice needs no key")

        config.effectiveLocalEngine = .gemini
        store.config = config
        var tree = tool.islandPage()
        let at = try XCTUnwrap(ids(tree).firstIndex(of: Pages.Block.outputPhone))
        XCTAssertEqual(Array(ids(tree)[(at + 1)...(at + 2)]), [Pages.Block.geminiApiKey, Pages.Block.saveGeminiApiKey])
        let keyField = try XCTUnwrap(field(tree, Pages.Block.geminiApiKey))
        XCTAssertEqual(keyField.kind, .secret)
        XCTAssertEqual(keyField.title?.text(for: "en"), "Gemini API key")
        XCTAssertEqual(keyField.placeholder?.text(for: "en"), "Paste Gemini API key and press Return")
        XCTAssertEqual(button(tree, Pages.Block.saveGeminiApiKey)?.title.text(for: "en"), "Save Key")

        // Nothing typed is refused; a paste is held, then saved trimmed.
        tree = islandPage(tool.islandEvent(PanelEvent(block: Pages.Block.saveGeminiApiKey, kind: .tap)))
        XCTAssertEqual(tool.notice, "Paste the Gemini API key first")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.geminiApiKey, kind: .change, value: .string(" AIza-pasted "))), .keep)
        XCTAssertEqual(chat.geminiSaved, [])
        tree = islandPage(tool.islandEvent(PanelEvent(block: Pages.Block.saveGeminiApiKey, kind: .tap)))
        XCTAssertEqual(chat.geminiSaved, ["AIza-pasted"])
        XCTAssertEqual(tool.notice, "Gemini API key saved")
        XCTAssertEqual(posted, 0, "the key is read at each announcement: nothing restarts")
        XCTAssertNil(content(tree, Pages.Block.geminiApiKey), "saved: the field goes")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(tree), as: UTF8.self).contains("AIza-pasted"))
        XCTAssertEqual(store.saves, 0, "the key never goes in the settings file")
    }

    func testGeneralOffersTheModelOnlyWhileAStyleRewords() throws {
        let tool = settings(on: .general)
        var tree = tool.settingsPage()
        let at = try XCTUnwrap(ids(tree).firstIndex(of: Pages.Block.speechLength))
        XCTAssertEqual(ids(tree)[at + 1], Pages.Block.announcementStyle)
        XCTAssertNil(content(tree, Pages.Block.styleModel), "As written uses no model")

        tree = event(tool, Pages.Block.announcementStyle, .change, .string("briefing"))
        XCTAssertEqual(saved.effectiveAnnouncementStyle, .briefing)
        XCTAssertEqual(ids(tree)[at + 2], Pages.Block.styleModel)
        guard case .list(let models)? = content(tree, Pages.Block.styleModel) else { return XCTFail("no model picker") }
        XCTAssertEqual(models.rows.map { $0.title.text(for: "en") }, ["Apple (On-device)", "Gemini"])
        XCTAssertNil(content(tree, Pages.Block.geminiApiKey), "Apple needs no key")

        tree = event(tool, Pages.Block.styleModel, .change, .string("gemini"))
        XCTAssertEqual(saved.effectiveStyleModel, .gemini)
        XCTAssertNotNil(content(tree, Pages.Block.geminiApiKey), "Gemini needs the key: here, as This Mac does not speak")
        tree = event(tool, Pages.Block.geminiApiKey, .submit, .string("  gem-key  "))
        XCTAssertEqual(chat.geminiSaved, ["gem-key"])
        XCTAssertTrue(texts(tree).contains("Gemini API key saved · "))
        tree = event(tool, Pages.Block.clearGeminiApiKey, .tap)
        XCTAssertEqual(chat.geminiCleared, 1)
        XCTAssertEqual(tool.setupNotice, "Gemini API key cleared")
    }

    func testSpeakersOffersTheGeminiVoiceKeyAndAFallbackMacVoice() throws {
        var config = saved
        config.effectiveSpeakLocal = true
        store.config = config
        let tool = settings(on: .speakers)
        var tree = tool.settingsPage()
        let at = try XCTUnwrap(ids(tree).firstIndex(of: Pages.Block.speakPhone))
        XCTAssertEqual(Array(ids(tree)[(at + 1)...]), [Pages.Block.localEngine, Pages.Block.voice, Pages.Block.previewVoice])

        tree = event(tool, Pages.Block.localEngine, .change, .string("gemini"))
        XCTAssertEqual(saved.effectiveLocalEngine, .gemini)
        XCTAssertEqual(Array(ids(tree)[(at + 1)...]),
                       [Pages.Block.localEngine, Pages.Block.geminiVoice, Pages.Block.geminiApiKey, Pages.Block.saveGeminiApiKey,
                        Pages.Block.voice, Pages.Block.previewVoice])
        XCTAssertTrue(texts(tree).contains("No Gemini API key saved · "))
        guard case .list(let voices)? = content(tree, Pages.Block.geminiVoice) else { return XCTFail("no voice picker") }
        XCTAssertEqual(voices.rows.first?.title.text(for: "en"), "Kore · Warm & clear")
        XCTAssertTrue(texts(tree).contains("Fallback Mac voice"), "the Mac voice is what speaks when Gemini cannot")
        XCTAssertFalse(texts(tree).contains("Voice"))

        event(tool, Pages.Block.geminiVoice, .change, .string("Puck"))
        XCTAssertEqual(saved.effectiveGeminiVoice, "Puck")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.geminiVoice, kind: .change, value: .string("Nobody"))), .keep)
        XCTAssertEqual(saved.effectiveGeminiVoice, "Puck")

        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.geminiApiKey, kind: .change, value: .string("k-1"))), .keep)
        tree = event(tool, Pages.Block.saveGeminiApiKey, .tap)
        XCTAssertEqual(chat.geminiSaved, ["k-1"])
        XCTAssertEqual(button(tree, Pages.Block.clearGeminiApiKey)?.title.text(for: "en"), "Clear Gemini Key")
        XCTAssertEqual(field(tree, Pages.Block.geminiApiKey)?.value, "", "the field is always empty")

        // General leaves the key to Speakers while Gemini speaks here.
        config = saved
        config.effectiveAnnouncementStyle = .plain
        config.effectiveStyleModel = .gemini
        store.config = config
        let general = event(tool, Pages.Block.section, .tap, .string(Pages.Section.general.rawValue))
        XCTAssertNil(content(general, Pages.Block.geminiApiKey))
    }

    /// With every section on one page, no block appears twice, however the
    /// style and the engine are set.
    func testEverySectionOnOnePageHasEachBlockOnce() {
        for style in AnnouncementStyle.allCases {
            for model in StyleModel.allCases {
                for engine in LocalVoiceEngine.allCases {
                    var config = saved
                    config.effectiveSpeakLocal = true
                    config.effectiveAnnouncementStyle = style
                    config.effectiveStyleModel = model
                    config.effectiveLocalEngine = engine
                    store.config = config
                    let tree = settings(on: .general, sections: true).settingsPage()
                    let all = ids(tree)
                    XCTAssertEqual(all.count, Set(all).count, "\(style) \(model) \(engine): \(all)")
                }
            }
        }
    }

    func testTheMonitorSaysWhenMessagesGoToGemini() {
        var config = saved
        config.effectiveSpeakLocal = true
        store.config = config
        let tool = opened()
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.hasSuffix("Nothing is sent anywhere except to Google Home.") })
        config.effectiveLocalEngine = .gemini
        store.config = config
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.contains("to Gemini to be spoken on this Mac") })
    }

    func testPhoneOutputTogglesOnIslandAndSettings() throws {
        let tool = settings(on: .speakers)
        var tree = tool.settingsPage()
        XCTAssertTrue(ids(tree).contains(Pages.Block.speakPhone))
        XCTAssertFalse(ids(tree).contains(Pages.Block.phonePauseMedia))
        XCTAssertFalse(ids(tree).contains(Pages.Block.phoneHeadphonesOnly))

        tree = event(tool, Pages.Block.speakPhone, .toggle, .bool(true))
        XCTAssertEqual(saved.effectiveSpeakPhone, true)
        XCTAssertTrue(ids(tree).contains(Pages.Block.phonePauseMedia))
        XCTAssertTrue(ids(tree).contains(Pages.Block.phoneHeadphonesOnly))

        tree = event(tool, Pages.Block.phonePauseMedia, .toggle, .bool(true))
        XCTAssertEqual(saved.effectivePhonePauseMedia, true)
        tree = event(tool, Pages.Block.phoneHeadphonesOnly, .toggle, .bool(true))
        XCTAssertEqual(saved.effectivePhoneHeadphonesOnly, true)

        let island = islandPage(tool.islandEvent(PanelEvent(block: Pages.Block.outputPhone, kind: .toggle, value: .bool(false))))
        XCTAssertEqual(saved.effectiveSpeakPhone, false)
        XCTAssertTrue(ids(island).contains(Pages.Block.outputPhone))
    }

    func testHomeCastVoiceToggleShowsTheVoiceEngineAndSaves() throws {
        let tool = settings(on: .speakers)
        var tree = tool.settingsPage()
        XCTAssertTrue(ids(tree).contains(Pages.Block.homeCastVoice))
        XCTAssertFalse(ids(tree).contains(Pages.Block.localEngine))

        tree = event(tool, Pages.Block.homeCastVoice, .toggle, .bool(true))
        XCTAssertEqual(saved.homeCastVoice, true)
        XCTAssertTrue(ids(tree).contains(Pages.Block.localEngine))

        tree = event(tool, Pages.Block.localEngine, .change, .string(LocalVoiceEngine.gemini.rawValue))
        XCTAssertTrue(ids(tree).contains(Pages.Block.geminiVoice))
        XCTAssertTrue(texts(tree).contains { $0.contains("play the Gemini voice over this Wi-Fi network") })

        // Home speakers off: the switch has nothing to apply to.
        tree = event(tool, Pages.Block.speakHome, .toggle, .bool(false))
        XCTAssertFalse(ids(tree).contains(Pages.Block.homeCastVoice))
        XCTAssertFalse(ids(tree).contains(Pages.Block.localEngine))
    }
}

extension ChatSlackTests {
    /// 30 networks with long names, in each state, as Beeper might list
    /// them for someone with many accounts.
    static func manyNetworkStates() -> [BeeperNetworkState] {
        let states: [BeeperNetworkState.State] = [.reading, .skipped, .muted]
        return (0..<30).map {
            BeeperNetworkState(key: "network\($0)" + String(repeating: "k", count: 40),
                               name: "Network \($0) " + String(repeating: "n", count: 60), state: states[$0 % 3])
        }
    }
}

// MARK: - The real credentials and the running app

final class ChatCredentialsSeamTests: XCTestCase {
    private func store() throws -> SecretStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-tool-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return SecretStore(fileURL: dir.appendingPathComponent("secrets.json"))
    }

    func testTheSecretsFileSeamSavesAndClearsTheTokenAndKeepsTheRest() throws {
        let store = try store()
        let google = GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r")
        try store.save(Secrets(google: google))
        let chat = SecretStoreChatCredentials(store: store)
        XCTAssertFalse(chat.hasSlackToken)
        try chat.saveSlackToken("xoxp-1")
        XCTAssertTrue(chat.hasSlackToken)
        XCTAssertEqual(store.load().slackToken, "xoxp-1")
        XCTAssertEqual(store.load().google, google, "the Google login is kept")
        try chat.clearSlackToken()
        XCTAssertFalse(chat.hasSlackToken)
        XCTAssertNil(store.load().slackToken)
        try chat.saveSlackToken("")
        XCTAssertNil(store.load().slackToken, "an empty token is no token")
        XCTAssertEqual(store.load().google, google)
    }

    func testTheSecretsFileSeamReadsChatAccess() throws {
        let store = try store()
        let chat = SecretStoreChatCredentials(store: store)
        XCTAssertFalse(chat.hasChatAccess)
        try store.update {
            $0.googleChat = GoogleCredentials(clientId: "c", clientSecret: "s", accessToken: "a", refreshToken: "r",
                                              scopes: GoogleAuth.chatScopes)
        }
        XCTAssertTrue(chat.hasChatAccess)
        try store.update { $0.googleChat?.scopes = Array(GoogleAuth.chatScopes.dropLast()) }
        XCTAssertFalse(chat.hasChatAccess, "every Chat scope, or none")
    }

    func testTheSecretsFileSeamSavesAndClearsTheBeeperTokenAndKeepsTheRest() throws {
        let store = try store()
        try store.save(Secrets(slackToken: "xoxp-1")) // gitleaks:allow (made-up test token)
        let chat = SecretStoreChatCredentials(store: store)
        XCTAssertFalse(chat.hasBeeperToken)
        try chat.saveBeeperToken("fake-beeper") // gitleaks:allow (made-up test token)
        XCTAssertTrue(chat.hasBeeperToken)
        XCTAssertEqual(store.load().beeperToken, "fake-beeper")
        XCTAssertEqual(store.load().slackToken, "xoxp-1", "the Slack token is kept")
        try chat.clearBeeperToken()
        XCTAssertNil(store.load().beeperToken)
        try chat.saveBeeperToken("")
        XCTAssertNil(store.load().beeperToken, "an empty token is no token")
        XCTAssertFalse(NoChatCredentials().hasBeeperToken)
    }

    func testNoCredentialsHaveNothing() throws {
        let none = NoChatCredentials()
        XCTAssertFalse(none.hasSlackToken)
        XCTAssertFalse(none.hasChatAccess)
        try none.saveSlackToken("x")
        XCTAssertFalse(none.hasSlackToken)
    }

    /// The menu bar app is an accessory; HomeSpeaker's own command-line
    /// runs carry its bundle id but are prohibited from being apps, and do
    /// not count.
    func testOnlyHomeSpeakerRunningAsAnAppCounts() {
        let id = ProcessDriver.bundleID
        XCTAssertTrue(ProcessDriver.isAppRunning([(id, .accessory)]))
        XCTAssertTrue(ProcessDriver.isAppRunning([(id, .regular)]))
        XCTAssertFalse(ProcessDriver.isAppRunning([(id, .prohibited)]), "a `--volume` run is not the app")
        XCTAssertFalse(ProcessDriver.isAppRunning([("com.example.other", .accessory), (nil, .regular)]))
        XCTAssertTrue(ProcessDriver.isAppRunning([(id, .prohibited), (id, .accessory)]))
        XCTAssertFalse(ProcessDriver.isAppRunning([]))
    }

    func testTheSecretsFileSeamSavesAndClearsTheGeminiKeyAndKeepsTheRest() throws {
        let store = try store()
        try store.save(Secrets(slackToken: "xoxp-1", beeperToken: "b")) // gitleaks:allow (made-up test token)
        let chat = SecretStoreChatCredentials(store: store)
        XCTAssertFalse(chat.hasGeminiKey)
        try chat.saveGeminiKey("fake-gemini") // gitleaks:allow (made-up test token)
        XCTAssertTrue(chat.hasGeminiKey)
        XCTAssertEqual(store.load().geminiApiKey, "fake-gemini")
        XCTAssertEqual(store.load().slackToken, "xoxp-1")
        XCTAssertEqual(store.load().beeperToken, "b")
        try chat.clearGeminiKey()
        XCTAssertNil(store.load().geminiApiKey)
        try chat.saveGeminiKey("")
        XCTAssertNil(store.load().geminiApiKey, "an empty key is no key")
        XCTAssertFalse(NoChatCredentials().hasGeminiKey)
    }
}
