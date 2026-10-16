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

/// The chat monitor as the running app reports it (`ChatMonitorStatusFile`
/// in a temporary folder), Start and Stop sent to a recorder, and the
/// settings fields that refuse what they cannot hold.
final class MonitorRuntimeTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Chat = ChatSlackTests.Chat

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var chat: Chat!
    private var appRunning = false
    private var asked: [ChatMonitorAction] = []
    private var statusFile: ChatMonitorStatusFile!

    override func setUpWithError() throws {
        link = Link()
        store = Store()
        driver = Driver()
        chat = Chat()
        chat.token = "xoxp-test"
        appRunning = true
        asked = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-tool-monitor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        statusFile = ChatMonitorStatusFile(url: dir.appendingPathComponent(ChatMonitorStatusFile.fileName))
        var config = SpeakerConfig(enabled: true, defaultTarget: "kitchen",
                                   targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
        config.effectiveChatMonitor.slackEnabled = true
        store.config = config
    }

    private func tool() -> HomeSpeakerTool {
        HomeSpeakerTool(parts: .init(
            link: link, store: store, driver: driver, later: { $0() }, chat: chat,
            ownerRunning: { [unowned self] in appRunning }, historyURL: HomeSpeakerToolTests.noHistory,
            monitorStatusURL: statusFile.url, controlChatMonitor: { [unowned self] in asked.append($0) }))
    }

    /// Settings opened on Chat & Slack, the login item answered.
    private func opened() -> HomeSpeakerTool {
        let tool = tool()
        _ = tool.settingsPage()
        driver.answer(.app(.loginItem(.status)), .loginItem(.notRegistered))
        _ = event(tool, Pages.Block.section, .tap, .string(Pages.Section.monitor.rawValue))
        return tool
    }

    @discardableResult
    private func event(_ tool: HomeSpeakerTool, _ block: String, _ kind: UIEventKind, _ value: JSONValue? = nil,
                       file: StaticString = #filePath, line: UInt = #line) -> UITree {
        guard case .page(let tree) = tool.settingsEvent(PanelEvent(block: block, kind: kind, value: value)) else {
            XCTFail("no page", file: file, line: line)
            return UITree(blocks: [])
        }
        return tree
    }

    private func running(error: String? = nil, polled: Date? = Date(timeIntervalSince1970: 1_760_000_000)) throws {
        try statusFile.write(ChatMonitorStatus(isRunning: true, lastPollDate: polled, lastError: error,
                                               slackIdentity: "alice", activeGoogleChatBackend: "gws", pid: 99))
    }

    private func ids(_ tree: UITree) -> [String] { tree.blocks.compactMap(\.id) }

    private func texts(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .heading(let heading): return heading.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en")
            case .button(let button): return button.title.text(for: "en")
            default: return nil
            }
        }
    }

    private func warningRows(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            guard case .row(let row) = block.content, row.icon == "exclamationmark.triangle.fill" else { return nil }
            return row.title.text(for: "en")
        }
    }

    // MARK: - Running or stopped, as the app says

    func testARunningMonitorShowsWhenItPolledWhoSlackSaysAndHowChatIsRead() throws {
        try running()
        let tree = opened().settingsPage()
        let all = texts(tree)
        XCTAssertTrue(all.contains("Chat monitor running"))
        XCTAssertTrue(ids(tree).contains(Pages.Block.stopChatMonitor))
        XCTAssertFalse(ids(tree).contains(Pages.Block.startChatMonitor))
        XCTAssertTrue(all.contains(Pages.polledLine(Date(timeIntervalSince1970: 1_760_000_000))))
        XCTAssertTrue(all.contains { $0.hasPrefix("Polled at ") })
        XCTAssertTrue(all.contains("Signed in as alice"))
        XCTAssertTrue(all.contains("Currently reading via gws"))
        XCTAssertEqual(Pages.readingViaLine("api"), "Currently reading via the Google API")
    }

    func testAStoppedMonitorOffersStartWhileTheAppRunsAndASourceIsOn() {
        let tree = opened().settingsPage()
        XCTAssertTrue(texts(tree).contains("Chat monitor stopped"))
        XCTAssertTrue(ids(tree).contains(Pages.Block.startChatMonitor))
        XCTAssertFalse(texts(tree).contains { $0.hasPrefix("Polled at") }, "nothing about polling while stopped")
    }

    func testNoStartOrStopWithoutTheAppOrWithEverySourceOff() throws {
        try running()
        appRunning = false
        var tree = opened().settingsPage()
        XCTAssertTrue(texts(tree).contains("Chat monitor stopped"), "a status left by a crashed app never reads as running")
        XCTAssertFalse(ids(tree).contains(Pages.Block.startChatMonitor))
        XCTAssertFalse(ids(tree).contains(Pages.Block.stopChatMonitor))
        XCTAssertFalse(texts(tree).contains("Signed in as alice"))

        appRunning = true
        store.config?.effectiveChatMonitor.slackEnabled = false
        try statusFile.write(ChatMonitorStatus(isRunning: false))
        tree = opened().settingsPage()
        XCTAssertFalse(ids(tree).contains(Pages.Block.startChatMonitor), "nothing to start with every source off")
    }

    func testTheRuntimeErrorIsAProblemRowOnlyWhileTheAppRuns() throws {
        try running(error: "Slack: invalid_auth")
        XCTAssertTrue(warningRows(opened().settingsPage()).contains("Slack: invalid_auth"))
        appRunning = false
        XCTAssertFalse(warningRows(opened().settingsPage()).contains("Slack: invalid_auth"))
    }

    /// The status a crashed app left behind is cleared where it is read,
    /// so no later reader of `Pages.Chat.monitor` can believe it.
    func testAStatusFromAnAppThatIsNotRunningIsReadAsStopped() {
        let left = ChatMonitorStatus(isRunning: true, lastPollDate: Date(), lastError: "Slack: invalid_auth",
                                     slackIdentity: "james", activeGoogleChatBackend: "gws")
        let crashed = Pages.Chat(hasSlackToken: true, ownerRunning: false, monitor: left)
        XCTAssertEqual(crashed.monitor?.isRunning, false)
        XCTAssertNil(crashed.monitor?.lastError)
        XCTAssertFalse(crashed.monitorRunning)
        XCTAssertNil(crashed.runtimeError)
        let live = Pages.Chat(hasSlackToken: true, ownerRunning: true, monitor: left)
        XCTAssertEqual(live.monitor, left)
    }

    func testARuntimeErrorThatRepeatsASetupProblemIsSaidOnce() throws {
        chat.token = nil
        try running(error: ChatMonitorError.slackTokenMissing.localizedDescription)
        let rows = warningRows(opened().settingsPage())
        XCTAssertEqual(rows.filter { $0 == ChatMonitorError.slackTokenMissing.localizedDescription }.count, 1)
    }

    // MARK: - The island

    func testTheIslandWarnsAboutTheRuntimeErrorAsTheMenuBarDoes() throws {
        try running(error: "Google Chat: 503")
        let tool = tool()
        _ = tool.islandPage()
        XCTAssertTrue(Pages.chatWarnings(tool.status()).contains("Google Chat: 503"))
        appRunning = false
        let warnings = Pages.chatWarnings(tool.status())
        XCTAssertFalse(warnings.contains("Google Chat: 503"))
        XCTAssertTrue(warnings.contains(Pages.appNotReadingChat))
    }

    func testChatWarningsListSetupProblemsThenTheRuntimeError() {
        var status = Pages.Status()
        status.config.effectiveChatMonitor.slackEnabled = true
        status.chat = Pages.Chat(hasSlackToken: false, ownerRunning: true,
                                 monitor: ChatMonitorStatus(isRunning: true, lastError: "Slack: ratelimited"))
        XCTAssertEqual(Pages.chatWarnings(status), [ChatMonitorError.slackTokenMissing.localizedDescription, "Slack: ratelimited"])
        status.config.effectiveChatMonitor.slackEnabled = false
        XCTAssertEqual(Pages.chatWarnings(status), [], "nothing while every source is off")
    }

    // MARK: - Start and Stop

    func testStartAndStopAskTheRunningApp() throws {
        let tool = opened()
        var tree = event(tool, Pages.Block.startChatMonitor, .tap)
        XCTAssertEqual(asked, [.start])
        XCTAssertEqual(tool.setupNotice, "Asked HomeSpeaker to start the chat monitor")
        XCTAssertTrue(texts(tree).contains("Asked HomeSpeaker to start the chat monitor"))
        try running()
        tree = event(tool, Pages.Block.stopChatMonitor, .tap)
        XCTAssertEqual(asked, [.start, .stop])
        XCTAssertEqual(tool.setupNotice, "Asked HomeSpeaker to stop the chat monitor")
    }

    func testStartNeedsNoRunningAppButIsRefusedWithoutASource() {
        let tool = opened()
        appRunning = false
        _ = event(tool, Pages.Block.startChatMonitor, .tap)
        XCTAssertEqual(asked, [.start], "the extension's monitor runs in its own process: no app is asked")
        asked = []
        appRunning = true
        store.config?.effectiveChatMonitor.slackEnabled = false
        _ = event(tool, Pages.Block.startChatMonitor, .tap)
        XCTAssertEqual(asked, [])
        XCTAssertEqual(tool.setupNotice, "Turn on Slack or Google Chat first")
    }

    func testAChangeTheAppWritesIsDrawnWithoutATap() throws {
        let tool = opened()
        link.rendered.removeAll()
        tool.refreshMonitorStatus()
        XCTAssertTrue(link.rendered.isEmpty, "nothing changed, nothing drawn")
        try running()
        tool.refreshMonitorStatus()
        XCTAssertEqual(link.rendered.map(\.panel), [HomeSpeakerTool.settingsPanel])
        XCTAssertTrue(texts(link.rendered[0].tree).contains("Chat monitor running"))
        tool.refreshMonitorStatus()
        XCTAssertEqual(link.rendered.count, 1, "drawn once a change")
        tool.panelClosed(HomeSpeakerTool.settingsPanel)
        try running(error: "Slack: boom")
        tool.refreshMonitorStatus()
        XCTAssertEqual(link.rendered.count, 1, "a closed page is not drawn")
    }

    // MARK: - Fields that refuse

    func testEachFieldOutOfRangeSaysWhatItTakesAndSavesNothing() {
        store.config?.effectiveAnnounceVolumeEnabled = true
        store.config?.effectivePauseMedia = true
        let tool = opened()
        _ = event(tool, Pages.Block.section, .tap, .string(Pages.Section.general.rawValue))
        let cases: [(String, String, String)] = [
            (Pages.Block.quietStart, "25:99", HomeSpeakerTool.Invalid.quietHour),
            (Pages.Block.quietEnd, "soon", HomeSpeakerTool.Invalid.quietHour),
            (Pages.Block.announceLevel, "140", HomeSpeakerTool.Invalid.announceLevel),
            (Pages.Block.announceLevel, "loud", HomeSpeakerTool.Invalid.announceLevel),
            (Pages.Block.pauseExtra, "25", HomeSpeakerTool.Invalid.pauseExtra),
            (Pages.Block.pauseExtra, "-3", HomeSpeakerTool.Invalid.pauseExtra),
            (Pages.Block.pollInterval, "1", HomeSpeakerTool.Invalid.pollInterval),
            (Pages.Block.pollInterval, "100000", HomeSpeakerTool.Invalid.pollInterval),
            (Pages.Block.pollInterval, "soon", HomeSpeakerTool.Invalid.pollInterval),
        ]
        for (block, value, notice) in cases {
            let saves = store.saves
            let tree = event(tool, block, .submit, .string(value))
            XCTAssertEqual(tool.setupNotice, notice, "\(block) = \(value)")
            XCTAssertTrue(texts(tree).contains(notice), "\(block) = \(value): said on the page")
            XCTAssertEqual(store.saves, saves, "\(block) = \(value): nothing saved")
        }
        XCTAssertTrue(HomeSpeakerTool.Invalid.pollInterval.contains("\(ChatMonitorConfig.minPollInterval) to \(ChatMonitorConfig.maxPollInterval)"))
        // A good value is saved and takes the complaint away.
        _ = event(tool, Pages.Block.pollInterval, .submit, .string("60"))
        XCTAssertEqual(store.config?.effectiveChatMonitor.pollIntervalSeconds, 60)
        XCTAssertNil(tool.setupNotice)
    }

    // MARK: - Heard here, not on the speaker

    func testSpokenHereWithTheSpeakerFailedIsWhatTheIslandSays() {
        let line = AnnounceOutcome.spokeLocallyHomeFailed("speaker offline")
        let result = ProcessDriver.result(of: .say("hi"), status: 0, output: line + "\n", error: "error: Home speakers: speaker offline\n")
        XCTAssertEqual(result, .spoke(line))
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30)))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("hi")))
        driver.answer(.say("hi"), result)
        XCTAssertEqual(tool.notice, "Spoke on this Mac (Home speaker failed: speaker offline)")
        XCTAssertEqual(link.messages.last, "Spoke on this Mac (Home speaker failed: speaker offline)")
    }
}
