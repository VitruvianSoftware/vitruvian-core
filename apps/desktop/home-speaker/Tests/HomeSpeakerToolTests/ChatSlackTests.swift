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

/// The settings panel's Chat & Slack section, driven as the app drives it,
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

    /// Settings opened on Chat & Slack, the login item answered.
    private func opened(choice: Bool = false) -> HomeSpeakerTool {
        link.features = choice ? [.choice] : []
        let tool = tool()
        _ = tool.settingsPage()
        driver.answer(.app(.loginItem(.status)), .loginItem(.notRegistered))
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

    func testTheSectionHasMonitoringSlackGoogleChatAndOptions() {
        let tool = opened()
        let tree = tool.settingsPage()
        XCTAssertEqual(texts(tree).filter { ["Background Monitoring", "Slack", "Google Chat", "Options"].contains($0) },
                       ["Background Monitoring", "Slack", "Google Chat", "Options"])
        // Defaults: both sources off, Automatic, no token, no Chat access,
        // no gws.
        XCTAssertEqual(ids(tree), ["section", "slackEnabled", "slackToken", "googleChatEnabled", "chatSource", "grantChat",
                                   "muteOwnMessages", "pollInterval"])
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
        XCTAssertTrue(texts(tree).contains { $0.hasPrefix("HomeSpeaker reads new messages in the background while Slack or Google Chat is on") })
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
                                                                hasChatScopes: access, gwsInstalled: gws))
            }
        }
        XCTAssertEqual(Pages.monitorProblems(Pages.Status()), [])
    }

    func testTheEnvironmentIsAskedOnlyOnChatAndSlack() {
        let tool = tool()
        _ = tool.settingsPage()
        driver.answer(.app(.loginItem(.status)), .loginItem(.notRegistered))
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

    func testAFailedSaveIsSaidAndTheAppIsNotTold() {
        chat.refuses = true
        let tool = opened()
        _ = event(tool, Pages.Block.slackToken, .submit, .string("xoxp-1"))
        XCTAssertEqual(posted, 0)
        XCTAssertNotNil(tool.setupNotice)
        XCTAssertNotEqual(tool.setupNotice, "Slack token saved")
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
        XCTAssertEqual(driver.jobs.count, 2, "a Chat sign-in finds no speakers")
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
        driver.answer(.app(.loginItem(.status)), .loginItem(.notRegistered))
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

    // MARK: - Limits

    func testTheSectionIsWithinTheProtocolsLimits() throws {
        var status = Pages.Status()
        status.section = .monitor
        status.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true,
                                                               gwsAccount: String(repeating: "a", count: 300))
        status.chat = Pages.Chat(gwsPath: "/" + String(repeating: "p", count: 1000))
        status.configProblem = String(repeating: "x", count: 300)
        for choice in [false, true] {
            status.offersChoice = choice
            let tree = Pages.settings(status)
            XCTAssertLessThan(try JSONEncoder().encode(tree).count, UILimits.maxTreeBytes)
            XCTAssertLessThanOrEqual(tree.blocks.count, UILimits.maxBlocks)
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
}
