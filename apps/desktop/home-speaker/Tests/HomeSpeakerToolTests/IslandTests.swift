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

/// The island as HomeSpeaker's menu bar has it: the settings file's
/// warning, first-run setup, where to speak, the chat monitor's problems
/// and the shared Recent Broadcasts.
final class IslandTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Account = HomeSpeakerToolTests.Account
    typealias Chat = ChatSlackTests.Chat

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var account: Account!
    private var chat: Chat!
    private var appRunning = false
    private var folder: URL!

    override func setUp() {
        link = Link()
        store = Store()
        driver = Driver()
        account = Account()
        account.isSignedIn = true
        chat = Chat()
        appRunning = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-island-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private var settingsURL: URL { folder.appendingPathComponent("speaker_broadcast.json") }
    private var historyURL: URL { folder.appendingPathComponent("speaker_history.json") }

    private func tool() -> HomeSpeakerTool {
        HomeSpeakerTool(parts: .init(link: link, store: store, driver: driver, later: { $0() }, account: account, chat: chat,
                                     gwsLocation: { nil }, ownerRunning: { [unowned self] in appRunning },
                                     settingsURL: settingsURL))
    }

    // MARK: - Reading the page

    private func ids(_ tree: UITree) -> [String] { tree.blocks.compactMap(\.id) }

    private func texts(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .heading(let heading): return heading.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en") + " · " + (row.subtitle?.text(for: "en") ?? "")
            default: return nil
            }
        }
    }

    private func button(_ tree: UITree, _ id: String) -> ButtonBlock? {
        guard case .button(let button)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return button
    }

    private func toggle(_ tree: UITree, _ id: String) -> ToggleBlock? {
        guard case .toggle(let toggle)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return toggle
    }

    private func page(_ answer: PanelAnswer) -> UITree? {
        if case .page(let tree) = answer { return tree }
        return nil
    }

    /// Signed in with a speaker: the island as most people see it.
    private func ready() -> Pages.Status {
        var status = Pages.Status()
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                                      targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
        return status
    }

    // MARK: - The settings file's warning

    func testACorruptSettingsFileIsSaidFirstOnTheIsland() {
        var status = ready()
        XCTAssertFalse(texts(Pages.island(status)).contains { $0.hasPrefix("The settings file does not read") })
        status.configProblem = "line 3: expected a value"
        let page = Pages.island(status)
        guard case .heading = page.blocks.first?.content, case .row(let warning) = page.blocks.dropFirst().first?.content else {
            return XCTFail("the warning is not first")
        }
        XCTAssertEqual(warning.title.text(for: "en"), "The settings file does not read")
        XCTAssertEqual(warning.subtitle?.text(for: "en"), "line 3: expected a value")
        XCTAssertTrue(texts(page).contains("Nothing is saved until it reads again: fix or remove the file."))
        // The same block Settings draws.
        XCTAssertTrue(texts(Pages.settings(status)).contains("The settings file does not read · line 3: expected a value"))
        status.installed = false
        XCTAssertTrue(texts(Pages.island(status)).contains("The settings file does not read · line 3: expected a value"),
                      "said even without HomeSpeaker: the file is shared")
    }

    func testTheToolsIslandCarriesTheFilesProblem() {
        store.corrupt = "not JSON"
        let page = tool().islandPage()
        XCTAssertTrue(texts(page).contains { $0.hasPrefix("The settings file does not read") })
    }

    // MARK: - First-run setup

    func testSetupReplacesTheSpeakerPickerUntilSignedInWithSpeakers() {
        var status = ready()
        XCTAssertFalse(status.needsSetup)
        XCTAssertFalse(texts(Pages.island(status)).contains("Setup"))
        XCTAssertTrue(ids(Pages.island(status)).contains("speakers"))

        status.account.isSignedIn = false
        XCTAssertTrue(status.needsSetup)
        let signedOut = Pages.island(status)
        XCTAssertTrue(texts(signedOut).contains("Setup"))
        XCTAssertFalse(ids(signedOut).contains("speakers"), "setup stands where the picker was")
        XCTAssertFalse(ids(signedOut).contains("mute"))
        XCTAssertTrue(ids(signedOut).contains(Pages.Block.setupSignIn))

        status.account.isSignedIn = true
        status.config.targets = [:]
        let noSpeakers = Pages.island(status)
        XCTAssertTrue(texts(noSpeakers).contains("Setup"))
        XCTAssertFalse(ids(noSpeakers).contains(Pages.Block.setupSignIn), "signed in: step 1 says so")
        XCTAssertTrue(texts(noSpeakers).contains("1 · Google sign-in · Signed in"))
        XCTAssertEqual(button(noSpeakers, Pages.Block.setupDiscover)?.enabled, true)
    }

    func testSetupButtonsAreEnabledOnlyWhenTheyCanRun() {
        var status = ready()
        status.account = Pages.Account(isSignedIn: false, hasOAuthClient: true, hasAntigravityTokens: true)
        var page = Pages.island(status)
        XCTAssertEqual(button(page, Pages.Block.setupSignIn)?.enabled, true)
        XCTAssertEqual(button(page, Pages.Block.setupImportAntigravity)?.enabled, true)
        XCTAssertEqual(button(page, Pages.Block.setupDiscover)?.enabled, false, "nothing to find before a sign-in")
        XCTAssertFalse(texts(page).contains { $0.contains("Settings > Google Cloud") })

        // No OAuth client: Sign In cannot work, and the caption says where to fix it.
        status.account.hasOAuthClient = false
        page = Pages.island(status)
        XCTAssertEqual(button(page, Pages.Block.setupSignIn)?.enabled, false)
        XCTAssertTrue(texts(page).contains { $0.contains("Settings > Google Cloud") })

        // A setup job running: every setup button waits, and the job says what it is doing.
        status.account.hasOAuthClient = true
        status.setupBusy = .signIn(chatOnly: false)
        status.setupNotice = "Imported the Antigravity Google Home login"
        page = Pages.island(status)
        XCTAssertEqual(button(page, Pages.Block.setupSignIn)?.enabled, false)
        XCTAssertEqual(button(page, Pages.Block.setupImportAntigravity)?.enabled, false)
        XCTAssertTrue(texts(page).contains("Finish signing in in your browser…"))
        XCTAssertTrue(texts(page).contains("Imported the Antigravity Google Home login"))

        status.account.isSignedIn = true
        status.config.targets = [:]
        XCTAssertEqual(button(Pages.island(status), Pages.Block.setupDiscover)?.enabled, false, "waits for the job running")

        // No Antigravity login on this Mac: no import button, as in Settings.
        status = ready()
        status.account = Pages.Account(isSignedIn: false, hasOAuthClient: true)
        XCTAssertNil(button(Pages.island(status), Pages.Block.setupImportAntigravity))
    }

    func testSeveralHomesEachGetAButton() {
        var status = ready()
        status.config.targets = [:]
        status.homes = [HomeStructure(id: "h1", name: "Lake House")]
        XCTAssertFalse(ids(Pages.island(status)).contains(Pages.Block.setupDiscoverHome(0)), "one home needs no choosing")
        status.homes = [HomeStructure(id: "h1", name: "Lake House"), HomeStructure(id: "h2", name: "Cabin")]
        let page = Pages.island(status)
        XCTAssertEqual(button(page, "setup.discoverHome.0")?.title.text(for: "en"), "Lake House")
        XCTAssertEqual(button(page, "setup.discoverHome.1")?.title.text(for: "en"), "Cabin")
        XCTAssertEqual(button(page, "setup.discoverHome.1")?.enabled, true)
        XCTAssertEqual(Pages.Block.setupDiscoverHomeIndex("setup.discoverHome.1"), 1)
        XCTAssertNil(Pages.Block.setupDiscoverHomeIndex("setup.discoverHome.-1"))
        XCTAssertNil(Pages.Block.setupDiscoverHomeIndex("setup.discover"))
        status.homes = (0..<40).map { HomeStructure(id: "h\($0)", name: "Home \($0)") }
        XCTAssertEqual(ids(Pages.island(status)).filter { $0.hasPrefix("setup.discoverHome.") }.count, Pages.maxSetupHomes)
    }

    func testSaySomethingWorksBeforeSetupWhenThisMacSpeaks() {
        var status = ready()
        status.account.isSignedIn = false
        XCTAssertFalse(ids(Pages.island(status)).contains(Pages.Block.say), "only Home speakers, and none set up: nothing would speak")
        status.config.effectiveSpeakLocal = true
        XCTAssertTrue(ids(Pages.island(status)).contains(Pages.Block.say), "this Mac speaks without a sign-in")
    }

    func testTheToolsSetupButtonsDoWhatSettingsDoes() {
        account.isSignedIn = false
        account.hasAntigravityTokens = true
        store.config?.targets = [:]
        store.config?.defaultTarget = ""
        let tool = tool()
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs, [], "not signed in: nothing to list")

        _ = tool.islandEvent(PanelEvent(block: Pages.Block.setupSignIn, kind: .tap))
        XCTAssertEqual(driver.jobs.last, .signIn(chatOnly: false))
        driver.answer(.signIn(chatOnly: false), .failed("the browser was closed"))
        XCTAssertEqual(tool.setupNotice, "The browser was closed")

        // Import: the login, then speakers found, as Settings' Import does.
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.setupImportAntigravity, kind: .tap))
        XCTAssertEqual(account.imports, 1)
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: true, home: nil)))
        driver.answer(.app(.discover(save: true, home: nil)), .failed("no homes visible to this account"))

        _ = tool.islandEvent(PanelEvent(block: Pages.Block.setupDiscover, kind: .tap))
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: true, home: nil)))
        driver.answer(.app(.discover(save: true, home: nil)), .done(["saved 1 target(s) from Lake House"]))
        XCTAssertEqual(tool.setupNotice, "Saved 1 target(s) from Lake House")
        XCTAssertEqual(link.rendered.last?.panel, HomeSpeakerTool.islandPanel, "the island is drawn again when setup answers")
    }

    func testTheIslandListsTheHomesOnceAndFindsTheOnePicked() {
        store.config?.targets = [:]
        store.config?.defaultTarget = ""
        let tool = tool()
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs, [.app(.discover(save: false, home: nil))], "signed in with no speakers: the homes are listed")
        driver.answer(.app(.discover(save: false, home: nil)), .homes([HomeStructure(id: "h1", name: "Lake House"),
                                                                      HomeStructure(id: "h2", name: "Cabin")]))
        let page = tool.islandPage()
        XCTAssertEqual(driver.jobs.count, 1, "once an opening")
        XCTAssertNotNil(button(page, "setup.discoverHome.1"))
        _ = tool.islandEvent(PanelEvent(block: "setup.discoverHome.1", kind: .tap))
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: true, home: "h2")))
        XCTAssertEqual(tool.selectedHomeId, "h2")
        driver.answer(.app(.discover(save: true, home: "h2")), .done(["saved 2 target(s) from Cabin"]))
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "setup.discoverHome.9", kind: .tap)), .keep, "no such home")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: "setup.nothing", kind: .tap)), .keep)
    }

    // MARK: - Where to speak

    func testTheOutputsAreTogglesWithWhatTheyAddUpTo() {
        var status = ready()
        var page = Pages.island(status)
        XCTAssertEqual(toggle(page, Pages.Block.outputHome)?.value, true)
        XCTAssertEqual(toggle(page, Pages.Block.outputLocal)?.value, false)
        XCTAssertEqual(toggle(page, Pages.Block.outputHome)?.title.text(for: "en"), "Home speakers")
        XCTAssertEqual(toggle(page, Pages.Block.outputLocal)?.title.text(for: "en"), "This Mac")
        XCTAssertTrue(texts(page).contains("Speaking on \(status.config.activeOutputsLabel)"))
        XCTAssertTrue(texts(page).contains("Speaking on Kitchen"))
        status.config.effectiveSpeakLocal = true
        XCTAssertTrue(texts(Pages.island(status)).contains("Speaking on Kitchen + This Mac"))

        // Home speakers off: no volume to read or set, and a note says why.
        status.config.effectiveSpeakHome = false
        status.volume = Volume(speaker: "Kitchen", percent: 40)
        page = Pages.island(status)
        XCTAssertTrue(texts(page).contains("Kitchen · Home speakers are off"))
        XCTAssertFalse(ids(page).contains(Pages.Block.mute))
        XCTAssertFalse(ids(page).contains(Pages.Block.volume))
        XCTAssertFalse(ids(page).contains(Pages.Block.refresh))
        XCTAssertTrue(texts(page).contains("Speaking on This Mac"))
        status.config.effectiveSpeakLocal = false
        XCTAssertTrue(texts(Pages.island(status)).contains("Both are off, so nothing is spoken anywhere."))
    }

    func testTheOutputTogglesSaveTheFile() {
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30)))
        let page = self.page(tool.islandEvent(PanelEvent(block: Pages.Block.outputLocal, kind: .toggle, value: .bool(true))))
        XCTAssertEqual(store.config?.effectiveSpeakLocal, true)
        XCTAssertTrue(page.map(texts)?.contains("Speaking on Kitchen + This Mac") == true)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.outputHome, kind: .toggle, value: .bool(false)))
        XCTAssertEqual(store.config?.effectiveSpeakHome, false)
        XCTAssertNil(tool.volume, "the reading from before is dropped")
        XCTAssertEqual(store.saves, 2)
    }

    func testWithHomeSpeakersOffTheVolumeIsNeverRead() {
        store.config?.effectiveSpeakHome = false
        let tool = tool()
        tool.start()
        _ = tool.islandPage()
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs, [], "nothing waits on a Cast speaker nobody is using")
        store.config?.targets["office"] = SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office")
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .tap, value: .string("office")))
        XCTAssertEqual(store.config?.defaultTarget, "office")
        XCTAssertEqual(driver.jobs, [], "picking a speaker reads nothing either")
        // Back on: the island reads it again.
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.outputHome, kind: .toggle, value: .bool(true)))
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs, [.volume])
    }

    // MARK: - The chat monitor's problems

    func testTheChatMonitorsProblemsAreWarnedAbove() {
        var status = ready()
        XCTAssertEqual(Pages.chatWarnings(status), [], "every source off: nothing to warn about")
        status.config.effectiveChatMonitor.slackEnabled = true
        status.chat = Pages.Chat(hasSlackToken: false, ownerRunning: false)
        XCTAssertEqual(Pages.chatWarnings(status), [ChatMonitorError.slackTokenMissing.localizedDescription, Pages.appNotReadingChat])
        XCTAssertEqual(Pages.appNotReadingChat, "HomeSpeaker isn't running, so nothing is reading chat")
        let page = Pages.island(status)
        XCTAssertTrue(texts(page).contains("\(ChatMonitorError.slackTokenMissing.localizedDescription) · "))
        XCTAssertTrue(texts(page).contains("HomeSpeaker isn't running, so nothing is reading chat · "))
        XCTAssertTrue(texts(page).contains("Fix it in Settings > Chat & Slack"))
        guard let warning = texts(page).firstIndex(of: "Fix it in Settings > Chat & Slack"),
              let say = page.blocks.firstIndex(where: { $0.id == Pages.Block.say }) else { return XCTFail("missing") }
        XCTAssertLessThan(warning, say, "warned above the controls")

        // Running, with its token: nothing to say.
        status.chat = Pages.Chat(hasSlackToken: true, ownerRunning: true)
        XCTAssertEqual(Pages.chatWarnings(status), [])
        XCTAssertFalse(texts(Pages.island(status)).contains("Fix it in Settings > Chat & Slack"))
        // Only the app not running.
        status.chat.ownerRunning = false
        XCTAssertEqual(Pages.chatWarnings(status), [Pages.appNotReadingChat])
    }

    func testTheToolLooksAtTheChatMonitorOnlyWhileItIsOn() {
        let tool = tool()
        XCTAssertFalse(texts(tool.islandPage()).contains(Pages.fixChatInSettings))
        store.config?.effectiveChatMonitor.slackEnabled = true
        chat.token = "xoxp-1"
        var page = tool.islandPage()
        XCTAssertTrue(texts(page).contains("\(Pages.appNotReadingChat) · "))
        appRunning = true
        page = tool.islandPage()
        XCTAssertFalse(texts(page).contains(Pages.fixChatInSettings))
    }

    // MARK: - Recent Broadcasts

    func testRecentBroadcastsListsTheNewestFiveOrSaysThereAreNone() {
        var status = ready()
        var page = Pages.island(status)
        XCTAssertTrue(texts(page).contains("Recent Broadcasts"))
        XCTAssertTrue(texts(page).contains(Pages.noRecentBroadcasts))
        XCTAssertEqual(Pages.noRecentBroadcasts, "No recent announcements")

        let when = Date(timeIntervalSince1970: 1_760_000_000)
        status.recentBroadcasts = (0..<8).map {
            BroadcastLogItem(timestamp: when, text: "message \($0)", targetName: "Kitchen + This Mac", source: $0 == 0 ? "Claude Code" : "Say")
        }
        page = Pages.island(status)
        XCTAssertFalse(texts(page).contains(Pages.noRecentBroadcasts))
        let listed = texts(page).filter { $0.hasPrefix("message ") }
        XCTAssertEqual(listed.count, Pages.maxRecentBroadcasts)
        XCTAssertEqual(Pages.maxRecentBroadcasts, 5)
        let time = when.formatted(date: .abbreviated, time: .shortened)
        XCTAssertEqual(listed.first, "message 0 · Claude Code · Kitchen + This Mac · \(time)", "newest first: source, where, when")
        XCTAssertEqual(listed.last, "message 4 · Say · Kitchen + This Mac · \(time)")
        status.installed = false
        XCTAssertTrue(texts(Pages.island(status)).contains("Recent Broadcasts"), "the history is there without HomeSpeaker too")
    }

    // MARK: - The shared history

    func testTheHistoryIsBesideTheSettingsFileUnlessNamed() {
        let settings = URL(fileURLWithPath: "/tmp/somewhere/.gemini/speaker_broadcast.json")
        XCTAssertEqual(HomeSpeakerTool.Parts(link: link, store: store, driver: driver, later: { $0() }, settingsURL: settings).historyURL.path,
                       "/tmp/somewhere/.gemini/speaker_history.json")
        let named = URL(fileURLWithPath: "/tmp/elsewhere/history.json")
        XCTAssertEqual(HomeSpeakerTool.Parts(link: link, store: store, driver: driver, later: { $0() }, settingsURL: settings,
                                             historyURL: named).historyURL, named)
        XCTAssertEqual(HomeSpeakerTool.Parts.historyURL(beside: ConfigManager.defaultConfigURL()), BroadcastHistory.defaultURL(),
                       "the real one is where HomeSpeaker keeps it")
    }

    func testTheIslandReadsTheSharedHistory() throws {
        let history = BroadcastHistory(fileURL: historyURL)
        try history.append(BroadcastLogItem(text: "from the menu bar", targetName: "Kitchen", source: "Quick Announce"))
        let tool = tool()
        XCTAssertEqual(tool.status().recentBroadcasts, [], "read only while the island is open")
        _ = tool.islandPage()
        XCTAssertEqual(tool.status().recentBroadcasts.map(\.text), ["from the menu bar"])
        try history.append(BroadcastLogItem(text: "from the Stop hook", targetName: "Kitchen", source: "Claude Code"))
        XCTAssertEqual(tool.status().recentBroadcasts.map(\.text), ["from the Stop hook", "from the menu bar"], "read afresh, newest first")
    }

    /// `HomeSpeaker --say`, which the tool runs, writes what was heard to
    /// the history itself; the tool writing it too would list it twice.
    func testSayingLeavesTheHistoryToHomeSpeaker() throws {
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30)))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        driver.answer(.say("dinner"), .notSpoken("Quiet hours active until 07:00. Nothing spoken."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyURL.path), "nothing heard, nothing written")
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        // What HomeSpeaker's --say does when it is heard, then the answer.
        try BroadcastHistory(fileURL: historyURL).append(BroadcastLogItem(text: "dinner", targetName: "Kitchen", source: "Say"))
        driver.answer(.say("dinner"), .spoke("sent to Kitchen"))
        XCTAssertEqual(BroadcastHistory(fileURL: historyURL).load().map(\.text), ["dinner"], "once, not twice")
        guard let page = link.rendered.last?.tree else { return XCTFail("not drawn") }
        XCTAssertTrue(texts(page).contains { $0.hasPrefix("dinner · Say · Kitchen") }, "the redraw shows it")
    }
}
