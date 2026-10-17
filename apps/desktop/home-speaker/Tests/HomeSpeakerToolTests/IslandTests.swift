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
    /// The tool's clock: tests move it on by hand.
    private var now = Date(timeIntervalSince1970: 1_760_000_000)

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
        HomeSpeakerTool(parts: .init(link: link, store: store, driver: driver, later: { $0() }, now: { [unowned self] in now },
                                     account: account, chat: chat,
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
        guard case .row(let warning) = page.blocks.first?.content else { return XCTFail("the warning is not first") }
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
        XCTAssertFalse(ids(Pages.island(status)).contains(Pages.Block.sayClipboard), "nor would the clipboard")
        status.config.effectiveSpeakLocal = true
        XCTAssertTrue(ids(Pages.island(status)).contains(Pages.Block.say), "this Mac speaks without a sign-in")
        XCTAssertTrue(ids(Pages.island(status)).contains(Pages.Block.sayClipboard), "and so does Speak clipboard")
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
        XCTAssertTrue(texts(page).contains("Home speakers are off"))
        XCTAssertFalse(ids(page).contains(Pages.Block.mute))
        XCTAssertFalse(ids(page).contains(Pages.Block.volume))
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

    // MARK: - The speaker, the volume and Mute

    /// Signed in with two speakers, the volume read once: the tool as the
    /// island finds it.
    private func openedWithTwoSpeakers(choice: Bool) -> HomeSpeakerTool {
        store.config?.targets["office"] = SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office")
        link.features = choice ? [.choice] : []
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)))
        return tool
    }

    func testTheSpeakerIsAMenuOrAListByWhatTheAppDraws() {
        for choice in [true, false] {
            let tool = openedWithTwoSpeakers(choice: choice)
            let page = tool.islandPage()
            switch page.blocks.first(where: { $0.id == Pages.Block.speakers })?.content {
            case .choice(let menu)?:
                XCTAssertTrue(choice, "a menu only for an app that draws one")
                XCTAssertEqual(menu.value, "kitchen")
            case .list(let list)?:
                XCTAssertFalse(choice, "the list only for an app before 3.48")
                XCTAssertEqual(list.rows.map(\.id), ["kitchen", "office"])
            default:
                XCTFail("no speaker picker")
            }
            switch page.blocks.first(where: { $0.id == Pages.Block.volume })?.content {
            case .choice(let menu)?: XCTAssertTrue(choice); XCTAssertEqual(menu.value, "40")
            case .field(let field)?: XCTAssertFalse(choice); XCTAssertEqual(field.value, "40")
            default: XCTFail("no volume control")
            }
            driver.pending.removeAll()
        }
    }

    func testASpeakerPickedFromTheMenuOrTheListIsTheDefault() {
        // The menu answers with the key as text.
        let menu = openedWithTwoSpeakers(choice: true)
        _ = menu.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("office")))
        XCTAssertEqual(store.config?.defaultTarget, "office")
        XCTAssertNil(menu.volume, "the reading was the other speaker's")
        XCTAssertEqual(driver.jobs.last, .volume, "and the new one's is read")
        driver.answer(.volume, .volume(Volume(speaker: "Office", percent: 20)))

        // The list answers with the row tapped.
        let list = openedWithTwoSpeakers(choice: false)
        _ = list.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .tap, value: .string("kitchen")))
        XCTAssertEqual(store.config?.defaultTarget, "kitchen")

        // The speaker already picked, "None picked", or one not in the file: nothing changes.
        let saves = store.saves
        XCTAssertEqual(list.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("kitchen"))), .keep)
        XCTAssertEqual(list.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string(""))), .keep)
        XCTAssertEqual(list.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .tap, value: .string("attic"))), .keep)
        XCTAssertEqual(store.saves, saves)
    }

    func testMuteIsASwitch() {
        let tool = openedWithTwoSpeakers(choice: true)
        func mute() -> ToggleBlock? { toggle(Pages.island(tool.status()), Pages.Block.mute) }
        XCTAssertEqual(mute()?.title.text(for: "en"), "Mute")
        XCTAssertEqual(mute()?.value, false)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.mute, kind: .toggle, value: .bool(true)))
        XCTAssertEqual(driver.jobs.last, .mute)
        driver.answer(.mute, .volume(Volume(speaker: "Kitchen", percent: 40, muted: true)))
        XCTAssertEqual(mute()?.value, true, "muted: the switch is on")
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.mute, kind: .toggle, value: .bool(false)))
        XCTAssertEqual(driver.jobs.last, .unmute)
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.mute, kind: .tap)), .keep, "only a switch's on or off says which")
    }

    func testAVolumePickedFromTheMenuOrTypedIsSet() {
        let tool = openedWithTwoSpeakers(choice: true)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("70")))
        XCTAssertEqual(driver.jobs.last, .setVolume(70))
        driver.answer(.setVolume(70), .volume(Volume(speaker: "Kitchen", percent: 70)))
        let jobs = driver.jobs.count
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("70"))), .keep,
                       "the level it is at already")
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string(""))), .keep,
                       "the menu's dash asks nothing")
        XCTAssertEqual(driver.jobs.count, jobs)
        // Typed, before 3.48: the same, and a level out of range is said.
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .submit, value: .string(" 35 ")))
        XCTAssertEqual(driver.jobs.last, .setVolume(35))
        driver.answer(.setVolume(35), .volume(Volume(speaker: "Kitchen", percent: 35)))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .submit, value: .string("120")))
        XCTAssertEqual(tool.notice, "A volume is a whole number from 0 to 100")
        // Read back between two steps: the menu keeps it.
        guard case .choice(let menu)? = Pages.island(tool.status()).blocks.first(where: { $0.id == Pages.Block.volume })?.content else {
            return XCTFail("no menu")
        }
        XCTAssertEqual(menu.value, "35")
        XCTAssertTrue(menu.options.map(\.value).contains("35"))
    }

    func testAnOpeningReadsTheVolumeAgainOnceTheLastReadIsOld() {
        let tool = tool()
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs, [.volume])
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40)))
        // Opened and closed quickly: Google's Home API is not asked again.
        for _ in 0..<3 {
            tool.panelClosed(HomeSpeakerTool.islandPanel)
            now += 9
            _ = tool.islandPage()
        }
        XCTAssertEqual(driver.jobs, [.volume], "within 30 seconds of the last read, nothing is asked")
        XCTAssertEqual(HomeSpeakerTool.volumeFreshFor, 30)
        // Someone turned it up on the speaker meanwhile; a later opening sees it.
        tool.panelClosed(HomeSpeakerTool.islandPanel)
        now += HomeSpeakerTool.volumeFreshFor
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs, [.volume, .volume], "read again once the last read is 30 seconds old")
        XCTAssertFalse(texts(Pages.island(tool.status())).contains("Reading the volume…"), "quietly, with a level shown")
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 60)))
        XCTAssertEqual(tool.volume?.percent, 60)
        // One read at a time: an opening during a read asks for no other.
        now += 60
        _ = tool.islandPage()
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs.count, 3)
        // A read that failed leaves nothing to show, so the next opening reads.
        driver.answer(.volume, .unavailable("the speaker did not answer"))
        _ = tool.islandPage()
        XCTAssertEqual(driver.jobs.count, 4)
    }

    /// Opened again once the last read is old, so a read is running.
    private func reopenedWhileReading(choice: Bool = true) -> HomeSpeakerTool {
        let tool = openedWithTwoSpeakers(choice: choice)
        tool.panelClosed(HomeSpeakerTool.islandPanel)
        now += HomeSpeakerTool.volumeFreshFor
        _ = tool.islandPage()
        XCTAssertEqual(tool.busy, .volume)
        return tool
    }

    /// The read on opening takes seconds: what the person picks meanwhile
    /// waits for it, rather than being refused as busy.
    func testWhatIsPickedDuringTheReadWaitsForIt() {
        let tool = reopenedWhileReading()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("80")))
        XCTAssertNil(tool.notice, "not refused")
        XCTAssertEqual(tool.waiting, .setVolume(80))
        XCTAssertTrue(texts(Pages.island(tool.status())).contains("Setting the volume to 80 %…"))
        // A second waits for nobody: one is enough.
        XCTAssertNotNil(page(tool.islandEvent(PanelEvent(block: Pages.Block.mute, kind: .toggle, value: .bool(true)))))
        XCTAssertEqual(tool.notice, "HomeSpeaker is busy: Setting the volume to 80 %…")
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40)))
        XCTAssertEqual(driver.jobs.last, .setVolume(80), "run once the read ends")
        XCTAssertNil(tool.waiting)
        driver.answer(.setVolume(80), .volume(Volume(speaker: "Kitchen", percent: 80)))
        XCTAssertEqual(tool.volume?.percent, 80)
    }

    /// A volume picked during the read, then another speaker: the volume
    /// was meant for the old speaker, and HomeSpeaker would set it on the
    /// new one, so it is dropped and said to be. The old speaker's read is
    /// not shown as the new one's, and the new one is read.
    func testASpeakerChangeDropsAWaitingVolumeAndReadsTheNewSpeaker() {
        let tool = reopenedWhileReading()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("80")))
        XCTAssertEqual(tool.waiting, .setVolume(80))
        let picked = page(tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("office"))))
        XCTAssertEqual(store.config?.defaultTarget, "office", "the speaker is saved")
        XCTAssertNil(tool.waiting, "the volume for the old speaker is dropped")
        XCTAssertEqual(tool.notice, Pages.pendingDropped)
        XCTAssertTrue(picked.map(texts)?.contains(Pages.pendingDropped) == true, "and the island says so")
        XCTAssertTrue(tool.readPending, "the new speaker is read once the slot is free")
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40)))
        XCTAssertNil(tool.volume, "the old speaker's level is not shown as the new one's")
        XCTAssertEqual(driver.jobs.last, .volume, "the new speaker is read")
        XCTAssertFalse(driver.jobs.contains(.setVolume(80)), "never set on the new speaker")
        driver.answer(.volume, .volume(Volume(speaker: "Office", percent: 10)))
        XCTAssertEqual(tool.volume?.percent, 10)
        XCTAssertEqual(tool.notice, Pages.pendingDropped, "the read leaves the caption")

        // A waiting mute is dropped the same way.
        let muting = reopenedWhileReading()
        _ = muting.islandEvent(PanelEvent(block: Pages.Block.mute, kind: .toggle, value: .bool(true)))
        _ = muting.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("kitchen")))
        XCTAssertNil(muting.waiting)
        XCTAssertEqual(muting.notice, Pages.pendingDropped)
    }

    /// The same, with the speaker changed outside the island (the phone,
    /// the app, a hand edit): the island never hears of it, so the waiting
    /// volume is checked against the file when its turn comes.
    func testASpeakerChangedElsewhereDropsAWaitingVolume() {
        let tool = reopenedWhileReading()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("80")))
        XCTAssertEqual(tool.waiting, .setVolume(80))
        store.config?.defaultTarget = "office"
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40)))
        XCTAssertFalse(driver.jobs.contains(.setVolume(80)), "never set on the speaker the phone picked")
        XCTAssertEqual(tool.notice, Pages.pendingDropped)
        XCTAssertNil(tool.volume, "Kitchen's level is not shown as Office's")
        XCTAssertEqual(driver.jobs.last, .volume, "the new speaker is read")
        driver.answer(.volume, .volume(Volume(speaker: "Office", percent: 15)))
        XCTAssertEqual(tool.volume?.percent, 15)
    }

    /// A speaker changed elsewhere, then the island opened within 30
    /// seconds: the reading was the old speaker's, so it is neither shown
    /// nor counted as fresh, and the level it had can still be picked.
    func testAReadingForAnotherSpeakerIsNotFresh() {
        let tool = openedWithTwoSpeakers(choice: true)
        XCTAssertEqual(tool.volume?.percent, 40)
        store.config?.defaultTarget = "office"
        tool.panelClosed(HomeSpeakerTool.islandPanel)
        now += 5
        let page = tool.islandPage()
        XCTAssertEqual(driver.jobs, [.volume, .volume], "Office is read, however recent Kitchen's reading")
        XCTAssertNil(tool.volume)
        guard case .choice(let menu)? = page.blocks.first(where: { $0.id == Pages.Block.volume })?.content else {
            return XCTFail("no menu")
        }
        XCTAssertEqual(menu.value, "", "not Kitchen's 40 % under Office's name")
        XCTAssertEqual(toggle(page, Pages.Block.mute)?.value, false)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("40")))
        XCTAssertEqual(tool.waiting, .setVolume(40), "Kitchen's level is not taken as Office's, so picking it is not ignored")
    }

    /// A volume change running when the speaker changes: its answer is the
    /// old speaker's, so it is ignored, and the new speaker is read.
    func testAnAnswerForTheOldSpeakerIsIgnored() {
        let tool = openedWithTwoSpeakers(choice: true)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("70")))
        XCTAssertEqual(tool.busy, .setVolume(70))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("office")))
        XCTAssertNil(tool.notice, "nothing was waiting, so nothing was dropped")
        driver.answer(.setVolume(70), .volume(Volume(speaker: "Kitchen", percent: 70)))
        XCTAssertNil(tool.volume, "Kitchen's 70 % is not Office's")
        XCTAssertEqual(driver.jobs.last, .volume)
        driver.answer(.volume, .volume(Volume(speaker: "Office", percent: 25)))
        XCTAssertEqual(tool.volume?.percent, 25)
        // A failure for the old speaker is not said as the new one's either.
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("50")))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("kitchen")))
        driver.answer(.setVolume(50), .unavailable("office is offline"))
        XCTAssertNil(tool.notice)
        XCTAssertEqual(driver.jobs.last, .volume)
    }

    /// Changing speaker again while a read already waits: saved, and no
    /// "busy" said, since that one read covers whichever speaker is picked.
    func testASecondSpeakerChangeWhileAReadWaitsIsNotBusy() {
        let tool = openedWithTwoSpeakers(choice: true)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("70")))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("office")))
        XCTAssertTrue(tool.readPending)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("kitchen")))
        XCTAssertEqual(store.config?.defaultTarget, "kitchen")
        XCTAssertNil(tool.notice, "no busy refusal for a change that was saved")
        let jobs = driver.jobs.count
        driver.answer(.setVolume(70), .volume(Volume(speaker: "Kitchen", percent: 70)))
        XCTAssertEqual(driver.jobs.count, jobs + 1, "one read, not two")
        XCTAssertEqual(driver.jobs.last, .volume)
        XCTAssertFalse(tool.readPending)
    }

    /// What waited is checked again when it runs: Home speakers turned off
    /// meanwhile drop a waiting volume; a waiting read is not run either.
    func testAWaitingJobIsCheckedAgainWhenItRuns() {
        let tool = reopenedWhileReading()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.volume, kind: .change, value: .string("80")))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.outputHome, kind: .toggle, value: .bool(false)))
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40)))
        XCTAssertFalse(driver.jobs.contains(.setVolume(80)), "not set with Home speakers off")
        XCTAssertEqual(tool.notice, Pages.homeSpeakersOff)
        XCTAssertNil(tool.busy)

        // Broadcasting switched off while a typed message waited.
        store.config?.effectiveSpeakHome = true
        let saying = reopenedWhileReading()
        _ = saying.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        XCTAssertEqual(saying.waiting, .say("dinner"))
        _ = saying.islandEvent(PanelEvent(block: Pages.Block.broadcasting, kind: .toggle, value: .bool(false)))
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 40)))
        XCTAssertFalse(driver.jobs.contains(.say("dinner")))
        XCTAssertEqual(saying.notice, "Broadcasting is switched off")
    }

    // MARK: - More settings

    /// Every feature name an app from 3.50 to 3.57 gives: all but opening
    /// the settings panel.
    private static let before358: Set<ProtocolFeature> = [.status, .choice, .preferenceOptions, .statusActivity]

    func testAnAppThatOpensSettingsGetsAMoreSettingsButton() {
        link.features = Self.before358
        link.featureNames = [HomeSpeakerTool.openSettingsFeature]
        let page = tool().islandPage()
        XCTAssertEqual(page.blocks.last?.id, Pages.Block.moreSettings)
        XCTAssertEqual(button(page, Pages.Block.moreSettings)?.title.text(for: "en"), "More settings…")
        XCTAssertFalse(texts(page).contains(Pages.moreSettings), "the button replaces the caption")
    }

    func testTheFeatureIsAskedForByItsNameOnTheLink() {
        // The kit's name for it, from 1.6.0 (ProtocolFeature.openSettings):
        // the protocol's, which an app sends in its hello.
        XCTAssertEqual(HomeSpeakerTool.openSettingsFeature, "ui.open.settings")
    }

    func testAnAppWithoutItKeepsTheCaption() {
        for features in [[], Self.before358] as [Set<ProtocolFeature>] {
            link.features = features
            let page = tool().islandPage()
            XCTAssertEqual(texts(page).last, Pages.moreSettings, "\(features)")
            XCTAssertNil(button(page, Pages.Block.moreSettings), "\(features)")
        }
    }

    /// The tap is answered with `open` naming the settings panel, and no
    /// page: the island stays as it is, and nothing else happens.
    func testTheTapOpensTheSettingsPanel() {
        link.featureNames = [HomeSpeakerTool.openSettingsFeature]
        let tool = tool()
        _ = tool.islandPage()
        let saves = store.saves
        let jobs = driver.jobs
        let answer = tool.islandEvent(PanelEvent(block: Pages.Block.moreSettings, kind: .tap))
        XCTAssertEqual(answer, .open(HomeSpeakerTool.settingsPanel))
        XCTAssertEqual(HomeSpeakerTool.settingsPanel, "settings", "the manifest's settings panel")
        XCTAssertTrue(link.rendered.isEmpty, "nothing redrawn")
        XCTAssertEqual(store.saves, saves, "nothing saved")
        XCTAssertEqual(driver.jobs, jobs, "nothing more asked of HomeSpeaker than the opening's read")
        XCTAssertTrue(link.messages.isEmpty)
    }

    /// An app from 3.57 or before never gets `open`: it would open nothing
    /// and log it. A tap on the button's id (from a page drawn before, or
    /// any other app) is kept, and no block on its island answers `open`.
    func testAnOlderAppNeverGetsOpen() {
        for features in [[], Self.before358] as [Set<ProtocolFeature>] {
            link.features = features
            let tool = tool()
            _ = tool.islandPage()
            XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.moreSettings, kind: .tap)), .keep, "\(features)")
            for signedIn in [true, false] {
                account.isSignedIn = signedIn
                let tool = self.tool()
                for id in ids(tool.islandPage()) {
                    if case .open = tool.islandEvent(PanelEvent(block: id, kind: .tap)) {
                        XCTFail("a tap on \(id) answered open for an app without \(HomeSpeakerTool.openSettingsFeature)")
                    }
                }
            }
        }
    }

    // MARK: - The chat monitor's problems

    func testTheChatMonitorsProblemsAreWarnedAbove() {
        var status = ready()
        XCTAssertEqual(Pages.chatWarnings(status), [], "every source off: nothing to warn about")
        status.config.effectiveChatMonitor.slackEnabled = true
        status.chat = Pages.Chat(hasSlackToken: false, ownerRunning: false)
        XCTAssertEqual(Pages.chatWarnings(status), [ChatMonitorError.slackTokenMissing.localizedDescription],
                       "the extension is what reads chat: there is no app to start")
        let page = Pages.island(status)
        XCTAssertTrue(texts(page).contains("\(ChatMonitorError.slackTokenMissing.localizedDescription) · "))
        XCTAssertFalse(texts(page).contains { $0.contains("isn't running") })
        XCTAssertTrue(texts(page).contains(Pages.fixChatInSettings))
        guard let warning = texts(page).firstIndex(of: Pages.fixChatInSettings),
              let say = page.blocks.firstIndex(where: { $0.id == Pages.Block.say }) else { return XCTFail("missing") }
        XCTAssertLessThan(warning, say, "warned above the controls")

        // Running, with its token: nothing to say.
        status.chat = Pages.Chat(hasSlackToken: true, ownerRunning: true)
        XCTAssertEqual(Pages.chatWarnings(status), [])
        XCTAssertFalse(texts(Pages.island(status)).contains(Pages.fixChatInSettings))
        // Not running, with nothing wrong: nothing to warn about either.
        status.chat.ownerRunning = false
        XCTAssertEqual(Pages.chatWarnings(status), [])
    }

    func testTheToolLooksAtTheChatMonitorOnlyWhileItIsOn() {
        let tool = tool()
        XCTAssertFalse(texts(tool.islandPage()).contains(Pages.fixChatInSettings))
        store.config?.effectiveChatMonitor.slackEnabled = true
        var page = tool.islandPage()
        XCTAssertTrue(texts(page).contains("\(ChatMonitorError.slackTokenMissing.localizedDescription) · "))
        chat.token = "xoxp-1"
        appRunning = true
        page = tool.islandPage()
        XCTAssertFalse(texts(page).contains(Pages.fixChatInSettings))
    }

    // MARK: - Recent Broadcasts

    func testRecentBroadcastsListsTheNewestThreeOrSaysThereAreNone() {
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
        XCTAssertEqual(Pages.maxRecentBroadcasts, 3, "the island has little room")
        let time = when.formatted(date: .abbreviated, time: .shortened)
        XCTAssertEqual(listed.first, "message 0 · Claude Code · Kitchen + This Mac · \(time)", "newest first: source, where, when")
        XCTAssertEqual(listed.last, "message 2 · Say · Kitchen + This Mac · \(time)")
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

    // MARK: - What may speak: each agent and each chat app

    func testTheIslandHasASwitchForEachAgentAndChatAppUnderBroadcasting() {
        var status = ready()
        let page = Pages.island(status)
        let order = ids(page)
        let sources = [Pages.Block.claudeCodeEnabled, Pages.Block.antigravityEnabled,
                       Pages.Block.slackEnabled, Pages.Block.googleChatEnabled, Pages.Block.beeperEnabled]
        XCTAssertEqual(order.filter(sources.contains), sources, "agents first, then the chat apps, in that order")
        guard let broadcasting = order.firstIndex(of: Pages.Block.broadcasting),
              let quiet = order.firstIndex(of: Pages.Block.quiet),
              let first = order.firstIndex(of: Pages.Block.claudeCodeEnabled) else { return XCTFail("missing") }
        XCTAssertLessThan(broadcasting, quiet)
        XCTAssertLessThan(quiet, first, "the master switch and quiet hours stay on top")
        XCTAssertEqual(toggle(page, Pages.Block.claudeCodeEnabled)?.title.text(for: "en"), "Claude Code")
        XCTAssertEqual(toggle(page, Pages.Block.antigravityEnabled)?.title.text(for: "en"), "Antigravity")
        XCTAssertEqual(toggle(page, Pages.Block.slackEnabled)?.title.text(for: "en"), "Slack")
        XCTAssertEqual(toggle(page, Pages.Block.googleChatEnabled)?.title.text(for: "en"), "Google Chat")
        XCTAssertEqual(toggle(page, Pages.Block.beeperEnabled)?.title.text(for: "en"), "Beeper")
        XCTAssertTrue(texts(page).contains("Coding agents"))
        XCTAssertTrue(texts(page).contains("Chat apps"))
        // Agents speak unless switched off; chat is read only once switched on.
        XCTAssertEqual(toggle(page, Pages.Block.claudeCodeEnabled)?.value, true)
        XCTAssertEqual(toggle(page, Pages.Block.antigravityEnabled)?.value, true)
        XCTAssertEqual(toggle(page, Pages.Block.slackEnabled)?.value, false)
        XCTAssertEqual(toggle(page, Pages.Block.googleChatEnabled)?.value, false)
        XCTAssertEqual(toggle(page, Pages.Block.beeperEnabled)?.value, false)
        XCTAssertFalse(texts(page).contains(Pages.sourcesSilent))

        status.config.setAnnounces(.antigravity, false)
        status.config.effectiveChatMonitor.googleChatEnabled = true
        status.config.enabled = false
        let changed = Pages.island(status)
        XCTAssertEqual(toggle(changed, Pages.Block.antigravityEnabled)?.value, false)
        XCTAssertEqual(toggle(changed, Pages.Block.googleChatEnabled)?.value, true)
        XCTAssertTrue(texts(changed).contains(Pages.sourcesSilent), "Broadcasting off: said, not hidden")
        XCTAssertNotNil(toggle(changed, Pages.Block.claudeCodeEnabled), "still there to set for later")
    }

    func testTheAgentSwitchesSaveTheFile() {
        let tool = tool()
        _ = tool.islandPage()
        var page = page(tool.islandEvent(PanelEvent(block: Pages.Block.claudeCodeEnabled, kind: .toggle, value: .bool(false))))
        XCTAssertEqual(store.config?.announces(.claudeCode), false)
        XCTAssertEqual(store.config?.announces(.antigravity), true, "only the one switched")
        XCTAssertEqual(page.flatMap { toggle($0, Pages.Block.claudeCodeEnabled) }?.value, false, "the redraw shows it")
        page = self.page(tool.islandEvent(PanelEvent(block: Pages.Block.antigravityEnabled, kind: .toggle, value: .bool(false))))
        XCTAssertEqual(store.config?.announces(.antigravity), false)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.claudeCodeEnabled, kind: .toggle, value: .bool(true)))
        XCTAssertEqual(store.config?.announces(.claudeCode), true)
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.claudeCodeEnabled, kind: .tap)), .keep, "no value, no change")
        XCTAssertTrue(driver.jobs.allSatisfy { $0 == .volume }, "a switch runs nothing on the speaker")
    }

    func testTheChatSwitchesSaveTheFileAndWarnWhatCannotRun() {
        let tool = tool()
        XCTAssertFalse(texts(tool.islandPage()).contains(Pages.fixChatInSettings))
        // Saved, as Settings saves it: the engine follows the file and
        // starts its monitor (ChatMonitorReconciliation).
        let slack = page(tool.islandEvent(PanelEvent(block: Pages.Block.slackEnabled, kind: .toggle, value: .bool(true))))
        XCTAssertEqual(store.config?.effectiveChatMonitor.slackEnabled, true)
        guard let slack else { return XCTFail("not redrawn") }
        XCTAssertEqual(toggle(slack, Pages.Block.slackEnabled)?.value, true)
        XCTAssertTrue(texts(slack).contains("\(ChatMonitorError.slackTokenMissing.localizedDescription) · "),
                      "on without a token: warned at once")
        XCTAssertTrue(texts(slack).contains(Pages.fixChatInSettings))

        _ = tool.islandEvent(PanelEvent(block: Pages.Block.googleChatEnabled, kind: .toggle, value: .bool(true)))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.beeperEnabled, kind: .toggle, value: .bool(true)))
        XCTAssertEqual(store.config?.effectiveChatMonitor.googleChatEnabled, true)
        XCTAssertEqual(store.config?.effectiveChatMonitor.beeperEnabled, true)

        for block in [Pages.Block.slackEnabled, Pages.Block.googleChatEnabled, Pages.Block.beeperEnabled] {
            _ = tool.islandEvent(PanelEvent(block: block, kind: .toggle, value: .bool(false)))
        }
        XCTAssertEqual(store.config?.effectiveChatMonitor.anySourceEnabled, false)
        XCTAssertFalse(texts(tool.islandPage()).contains(Pages.fixChatInSettings), "every source off: nothing to warn about")
    }

    private func field(_ tree: UITree, _ id: String) -> FieldBlock? {
        guard case .field(let field)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return field
    }

    /// Turning Beeper or Slack on with no token puts the field to paste it
    /// right under its switch, with Save Token; once saved, both go.
    func testASourceOnWithNoTokenOffersItsFieldUnderItsSwitch() throws {
        let tool = tool()
        var page = tool.islandPage()
        XCTAssertNil(field(page, Pages.Block.beeperToken), "off: no field")
        XCTAssertNil(field(page, Pages.Block.slackToken))
        page = try XCTUnwrap(self.page(tool.islandEvent(PanelEvent(block: Pages.Block.beeperEnabled, kind: .toggle, value: .bool(true)))))
        let beeper = try XCTUnwrap(field(page, Pages.Block.beeperToken))
        XCTAssertEqual(beeper.kind, .secret)
        XCTAssertEqual(beeper.value, "")
        XCTAssertEqual(beeper.title?.text(for: "en"), "Access token")
        XCTAssertEqual(beeper.placeholder?.text(for: "en"), "Paste Beeper token and press Return")
        let order = ids(page)
        let toggleAt = try XCTUnwrap(order.firstIndex(of: Pages.Block.beeperEnabled))
        XCTAssertEqual(order[toggleAt + 1], Pages.Block.beeperToken, "directly under the switch")
        XCTAssertEqual(order[toggleAt + 2], Pages.Block.saveBeeperToken)
        XCTAssertEqual(button(page, Pages.Block.saveBeeperToken)?.title.text(for: "en"), "Save Token")
        XCTAssertNil(field(page, Pages.Block.slackToken), "only the source that is on")

        page = try XCTUnwrap(self.page(tool.islandEvent(PanelEvent(block: Pages.Block.slackEnabled, kind: .toggle, value: .bool(true)))))
        let slack = try XCTUnwrap(field(page, Pages.Block.slackToken))
        XCTAssertEqual(slack.title?.text(for: "en"), "User token (xoxp-…)")
        XCTAssertEqual(slack.placeholder?.text(for: "en"), "Paste Slack token and press Return")
        let slackAt = try XCTUnwrap(ids(page).firstIndex(of: Pages.Block.slackEnabled))
        XCTAssertEqual(ids(page)[slackAt + 1], Pages.Block.slackToken)

        // With its token saved, the source has no field.
        chat.token = "xoxp-1"
        page = tool.islandPage()
        XCTAssertNil(field(page, Pages.Block.slackToken))
        XCTAssertNotNil(field(page, Pages.Block.beeperToken))
    }

    func testReturnOnTheIslandSavesTheTokenAndTheWarningGoes() throws {
        store.config?.effectiveChatMonitor.beeperEnabled = true
        let tool = tool()
        XCTAssertTrue(texts(tool.islandPage()).contains("\(ChatMonitorError.beeperTokenMissing.localizedDescription) · "))
        let secret = "fake-island-beeper-token" // gitleaks:allow (made-up test token)
        let page = try XCTUnwrap(self.page(tool.islandEvent(PanelEvent(block: Pages.Block.beeperToken, kind: .submit,
                                                                         value: .string("  \(secret) ")))))
        XCTAssertEqual(chat.beeperSaved, [secret])
        XCTAssertEqual(tool.notice, "Beeper token saved")
        XCTAssertTrue(texts(page).contains("Beeper token saved"))
        XCTAssertFalse(texts(page).contains { $0.hasPrefix(ChatMonitorError.beeperTokenMissing.localizedDescription) },
                       "the warning goes at once")
        XCTAssertNil(field(page, Pages.Block.beeperToken), "and so does the field")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(page), as: UTF8.self).contains(secret))
        XCTAssertEqual(store.saves, 0, "the token never goes in the settings file")
    }

    /// A paste is held, not saved: each keystroke of a typed token would
    /// otherwise be saved, and the redraw wipe the field. Save Token saves.
    func testAPasteIsHeldUntilSaveTokenOnTheIsland() throws {
        store.config?.effectiveChatMonitor.slackEnabled = true
        let tool = tool()
        _ = tool.islandPage()
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.slackToken, kind: .change, value: .string("xoxp-pasted"))), .keep)
        XCTAssertEqual(chat.saved, [], "a change saves nothing")
        let page = try XCTUnwrap(self.page(tool.islandEvent(PanelEvent(block: Pages.Block.saveSlackToken, kind: .tap))))
        XCTAssertEqual(chat.saved, ["xoxp-pasted"])
        XCTAssertEqual(tool.notice, "Slack token saved")
        XCTAssertEqual(tool.draftSlackToken, "", "the draft goes once saved")
        XCTAssertNil(field(page, Pages.Block.slackToken))
        XCTAssertFalse(texts(page).contains { $0.hasPrefix(ChatMonitorError.slackTokenMissing.localizedDescription) })
    }

    func testAnEmptySaveOnTheIslandClearsNothing() throws {
        store.config?.effectiveChatMonitor.slackEnabled = true
        let tool = tool()
        _ = tool.islandPage()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.saveSlackToken, kind: .tap))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.slackToken, kind: .submit, value: .string("   ")))
        XCTAssertEqual(chat.saved, [])
        XCTAssertEqual(chat.cleared, 0)
        XCTAssertEqual(tool.notice, "Paste the Slack token first")
    }

    func testSavingOnTheIslandRedrawsAnOpenSettingsPanel() {
        store.config?.effectiveChatMonitor.beeperEnabled = true
        let tool = tool()
        _ = tool.settingsPage()
        _ = tool.islandPage()
        link.rendered = []
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.beeperToken, kind: .submit, value: .string("tok")))
        XCTAssertEqual(link.rendered.map(\.panel), [HomeSpeakerTool.settingsPanel])
    }

    /// The warning's way to the fix: a button that opens HomeSpeaker's
    /// settings on Chat & Slack, for an app that can open them.
    func testTheChatWarningOpensChatAndSlack() throws {
        link.featureNames = [HomeSpeakerTool.openSettingsFeature]
        store.config?.effectiveChatMonitor.slackEnabled = true
        let tool = tool()
        let page = tool.islandPage()
        XCTAssertEqual(button(page, Pages.Block.openChatSettings)?.title.text(for: "en"), "Open Chat & Slack…")
        XCTAssertFalse(texts(page).contains(Pages.fixChatInSettings), "the button replaces the caption")
        XCTAssertEqual(tool.section, .general)
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.openChatSettings, kind: .tap)), .open(HomeSpeakerTool.settingsPanel))
        XCTAssertEqual(tool.section, .monitor, "Settings opens on Chat & Slack")
        guard case .choice(let section)? = tool.settingsPage().blocks.first(where: { $0.id == Pages.Block.section })?.content else {
            // Without a choice the section is a picker of another kind; the
            // tool's own section is what matters.
            return
        }
        XCTAssertEqual(section.value, Pages.Section.monitor.rawValue)
    }

    func testTheChatWarningRedrawsAnOpenSettingsPanelOnChatAndSlack() {
        link.featureNames = [HomeSpeakerTool.openSettingsFeature]
        store.config?.effectiveChatMonitor.slackEnabled = true
        let tool = tool()
        _ = tool.settingsPage()
        _ = tool.islandPage()
        link.rendered = []
        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.openChatSettings, kind: .tap)), .open(HomeSpeakerTool.settingsPanel))
        XCTAssertEqual(link.rendered.map(\.panel), [HomeSpeakerTool.settingsPanel])
        XCTAssertTrue(link.rendered.last.map { $0.tree.blocks.contains { $0.id == Pages.Block.slackEnabled } } ?? false,
                      "redrawn on Chat & Slack")
    }

    /// An app that cannot open Settings gets the caption, naming where
    /// Chat & Slack is in Vitruvian, and a stray tap is kept.
    func testWithoutOpenSettingsTheWarningSaysWhereChatAndSlackIs() {
        for features in [[], Self.before358] as [Set<ProtocolFeature>] {
            link.features = features
            link.featureNames = []
            store.config?.effectiveChatMonitor.slackEnabled = true
            let tool = tool()
            let page = tool.islandPage()
            XCTAssertNil(button(page, Pages.Block.openChatSettings), "\(features)")
            XCTAssertTrue(texts(page).contains(Pages.fixChatInSettings), "\(features)")
            XCTAssertTrue(Pages.fixChatInSettings.contains("Vitruvian Settings › Extensions › HomeSpeaker"))
            XCTAssertTrue(Pages.fixChatInSettings.contains("Chat & Slack"))
            XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.openChatSettings, kind: .tap)), .keep, "\(features)")
            XCTAssertEqual(tool.section, .general)
        }
    }

    func testASwitchOverAFileThatDoesNotReadSavesNothing() {
        store.corrupt = "not JSON"
        let tool = tool()
        _ = tool.islandPage()
        let page = page(tool.islandEvent(PanelEvent(block: Pages.Block.beeperEnabled, kind: .toggle, value: .bool(true))))
        XCTAssertEqual(store.corrupt, "not JSON", "the file is left as it is")
        XCTAssertTrue(page.map(texts)?.contains { $0.hasPrefix("Refusing to save") } == true, "and the island says why")
    }

    // MARK: - Recent Broadcasts: a tap speaks it again

    func testEachRecentBroadcastIsATappableRowByItsId() {
        var status = ready()
        let items = (0..<4).map { BroadcastLogItem(text: "message \($0)", targetName: "Kitchen", source: "Say") }
        status.recentBroadcasts = items
        let page = Pages.island(status)
        let rows = ids(page).filter { $0.hasPrefix(Pages.Block.replayPrefix) }
        XCTAssertEqual(rows, items.prefix(Pages.maxRecentBroadcasts).map { Pages.Block.replayBroadcast($0.id) })
        XCTAssertEqual(rows.compactMap(Pages.Block.replayBroadcastId), items.prefix(3).map(\.id))
        XCTAssertTrue(texts(page).contains(Pages.replayHint))
        guard case .row(let row)? = page.blocks.first(where: { $0.id == rows.first })?.content else { return XCTFail("no row") }
        XCTAssertEqual(row.trailing?.text(for: "en"), Pages.replayMark)
        XCTAssertNil(Pages.Block.replayBroadcastId("replay.not-a-uuid"))
        XCTAssertNil(Pages.Block.replayBroadcastId(Pages.Block.say))

        status.installed = false
        let without = Pages.island(status)
        XCTAssertTrue(ids(without).filter { $0.hasPrefix(Pages.Block.replayPrefix) }.isEmpty, "nothing could speak it: no tap")
        XCTAssertFalse(texts(without).contains(Pages.replayHint))
    }

    func testTappingARecentBroadcastReplaysItWithoutListingItAgain() throws {
        let history = BroadcastHistory(fileURL: historyURL)
        try history.append(BroadcastLogItem(text: "the build is green", targetName: "Kitchen", source: "Claude Code"))
        try history.append(BroadcastLogItem(text: "dinner is ready", targetName: "Kitchen", source: "Say"))
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30)))
        let older = try XCTUnwrap(history.load().last)
        XCTAssertEqual(older.text, "the build is green")

        let busy = page(tool.islandEvent(PanelEvent(block: Pages.Block.replayBroadcast(older.id), kind: .tap)))
        XCTAssertEqual(driver.jobs.last, .replay("the build is green"), "the row tapped, not the newest")
        XCTAssertTrue(busy.map(texts)?.contains("Speaking it again…") == true)
        driver.answer(.replay("the build is green"), .spoke("sent to Kitchen"))
        XCTAssertEqual(history.load().map(\.text), ["dinner is ready", "the build is green"], "listed once, where it was")
        XCTAssertEqual(link.messages.last, "Sent to Kitchen")
    }

    func testAReplayFollowsSaysRules() throws {
        let history = BroadcastHistory(fileURL: historyURL)
        try history.append(BroadcastLogItem(text: "hello", targetName: "Kitchen", source: "Say"))
        let id = try XCTUnwrap(history.load().first?.id)
        let tool = tool()
        _ = tool.islandPage()
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30)))

        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.replayBroadcast(id), kind: .change)), .keep, "a tap only")
        store.config?.enabled = false
        var page = self.page(tool.islandEvent(PanelEvent(block: Pages.Block.replayBroadcast(id), kind: .tap)))
        XCTAssertTrue(page.map(texts)?.contains("Broadcasting is switched off") == true, "the master switch holds")
        XCTAssertFalse(driver.jobs.contains(.replay("hello")))

        store.config?.enabled = true
        page = self.page(tool.islandEvent(PanelEvent(block: Pages.Block.replayBroadcast(UUID()), kind: .tap)))
        XCTAssertTrue(page.map(texts)?.contains(Pages.replayGone) == true, "gone from the history since it was drawn")
        XCTAssertFalse(driver.jobs.contains { $0.spokenText != nil })

        // Quiet hours do not hold back what the person asked for.
        store.config?.quietHoursEnabled = true
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.replayBroadcast(id), kind: .tap))
        XCTAssertEqual(driver.jobs.last, .replay("hello"))
        // One at a time, as Say.
        page = self.page(tool.islandEvent(PanelEvent(block: Pages.Block.replayBroadcast(id), kind: .tap)))
        XCTAssertTrue(page.map(texts)?.contains("HomeSpeaker is busy: Speaking it again…") == true)
    }
}
