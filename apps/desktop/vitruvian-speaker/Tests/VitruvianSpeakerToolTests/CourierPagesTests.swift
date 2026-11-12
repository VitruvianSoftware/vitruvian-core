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

import VitruvianSpeakerCore
import VitruvianSpeakerToolCore
import VitruvianToolKit
import VitruvianToolProtocol

/// Courier on the extension's pages, as Vitruvian Speaker's own Settings has it
/// (#4237): its own switch, which stays off until a token is saved; its
/// Announce choice; its network switches, where a network Vitruvian Speaker
/// reads itself is "read it here as well", not a mute; and its token,
/// which goes in and never comes back out.
final class CourierPagesTests: XCTestCase {
    typealias Link = VitruvianSpeakerToolTests.Link
    typealias Store = VitruvianSpeakerToolTests.Store
    typealias Driver = VitruvianSpeakerToolTests.Driver
    typealias Account = VitruvianSpeakerToolTests.Account
    typealias Chat = ChatSlackTests.Chat

    private var link: Link!
    private var store: Store!
    private var chat: Chat!
    private var appRunning = false
    private var posted = 0
    private var folder: URL!

    override func setUp() {
        link = Link()
        store = Store()
        chat = Chat()
        appRunning = false
        posted = 0
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-speaker-courier-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private var settingsURL: URL { folder.appendingPathComponent("speaker_broadcast.json") }
    private var monitor: ChatMonitorConfig { store.config?.effectiveChatMonitor ?? ChatMonitorConfig() }

    private func tool() -> VitruvianSpeakerTool {
        let account = Account()
        account.isSignedIn = true
        return VitruvianSpeakerTool(parts: .init(
            link: link, store: store, driver: Driver(), later: { $0() }, account: account, chat: chat,
            gwsLocation: { nil }, ownerRunning: { [unowned self] in appRunning },
            credentialsChanged: { [unowned self] in posted += 1 }, settingsURL: settingsURL))
    }

    /// The monitor running and saying it reads `states` from Courier.
    private func courierRunning(_ states: [BeeperNetworkState]) throws {
        appRunning = true
        try ChatMonitorStatusFile(url: ChatMonitorStatusFile.url(beside: settingsURL))
            .write(ChatMonitorStatus(isRunning: true, courierNetworks: states.filter { $0.state == .reading }.map(\.name),
                                     courierSkippedNetworks: states.filter { $0.state == .skipped }.map(\.name),
                                     courierNetworkStates: states, pid: 99))
    }

    /// Signed in with a speaker, Settings on Chats.
    private func ready() -> Pages.Status {
        var status = Pages.Status()
        status.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        status.config = store.config!
        status.offersChoice = true
        status.section = .monitor
        return status
    }

    // MARK: - Reading a page

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

    private func toggle(_ tree: UITree, _ id: String) -> ToggleBlock? {
        guard case .toggle(let toggle)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return toggle
    }

    private func field(_ tree: UITree, _ id: String) -> FieldBlock? {
        guard case .field(let field)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return field
    }

    private func choice(_ tree: UITree, _ id: String) -> ChoiceBlock? {
        guard case .choice(let choice)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return choice
    }

    private func chips(_ tree: UITree, _ id: String) -> ChipsBlock? {
        guard case .chips(let chips)? = tree.blocks.first(where: { $0.id == id })?.content else { return nil }
        return chips
    }

    private func page(_ answer: PanelAnswer, file: StaticString = #filePath, line: UInt = #line) -> UITree {
        guard case .page(let tree) = answer else {
            XCTFail("no page: \(answer)", file: file, line: line)
            return UITree(blocks: [])
        }
        return tree
    }

    private func courierSwitches(_ tree: UITree) -> [String] {
        ids(tree).filter { $0.hasPrefix(Pages.Block.courierNetworkPrefix) }
    }

    // MARK: - Off, with no token

    func testWithNoTokenTheIslandHasOnlyTheSwitchAndSettingsAsksForTheToken() throws {
        let status = ready()
        let island = Pages.island(status)
        let courier = try XCTUnwrap(toggle(island, Pages.Block.courierEnabled))
        XCTAssertEqual(courier.title.text(for: "en"), "Courier")
        XCTAssertFalse(courier.value)
        XCTAssertNil(courier.enabled, "the island asks for the token when it is turned on")
        XCTAssertNil(field(island, Pages.Block.courierToken), "no token field until Courier is wanted")
        XCTAssertEqual(ids(island).firstIndex(of: Pages.Block.courierEnabled),
                       ids(island).firstIndex(of: Pages.Block.beeperEnabled).map { $0 + 1 }, "right after Beeper")

        let settings = Pages.settings(status)
        XCTAssertTrue(texts(settings).contains("Courier"), "its own heading")
        let announce = try XCTUnwrap(toggle(settings, Pages.Block.courierEnabled))
        XCTAssertEqual(announce.title.text(for: "en"), "Announce Courier messages")
        XCTAssertEqual(announce.enabled, false, "off until a token is saved, as in Vitruvian Speaker's own Settings")
        XCTAssertEqual(field(settings, Pages.Block.courierToken)?.kind, .secret)
        XCTAssertEqual(field(settings, Pages.Block.courierToken)?.value, "")
        XCTAssertTrue(texts(settings).contains("No Courier token saved"))
        XCTAssertTrue(texts(settings).contains(Pages.courierTokenFirst))
        for line in Pages.courierHelpLines {
            XCTAssertTrue(texts(settings).contains(line))
            // The app cuts a caption at four lines: none reaches it on a
            // settings page (about 90 characters a line at 560 points; the
            // rendered page shows each in three).
            XCTAssertLessThanOrEqual(line.count, 3 * 90, line)
        }
        XCTAssertTrue(Pages.courierHelp.hasPrefix("In Courier: Settings › Integrations › New connection…, then paste the token here."))
        XCTAssertNil(choice(settings, Pages.Block.courierAnnounce), "nothing to announce while it is off")
        XCTAssertFalse(texts(settings).contains { $0.contains("Stub") })
    }

    // MARK: - On

    func testOnItHasItsOwnAnnounceAndNetworksThatShowOnceItIsRead() throws {
        var status = ready()
        status.config.effectiveChatMonitor.courierEnabled = true
        status.config.effectiveChatMonitor.courierAnnounce = .all
        status.chat = Pages.Chat(hasCourierToken: true)
        for page in [Pages.island(status), Pages.settings(status)] {
            let announce = try XCTUnwrap(choice(page, Pages.Block.courierAnnounce))
            XCTAssertEqual(announce.value, "all")
            XCTAssertEqual(announce.options.map { $0.title.text(for: "en") }, ["Direct messages and mentions", "Every message"])
            XCTAssertNil(choice(page, Pages.Block.beeperAnnounce), "Beeper's is Beeper's")
            XCTAssertTrue(texts(page).contains("Other networks show here once Courier is being read."))
            XCTAssertFalse(texts(page).contains(Pages.beeperNetworksLater))
        }
        XCTAssertNil(field(Pages.island(status), Pages.Block.courierToken), "a token is saved")
        let settings = Pages.settings(status)
        XCTAssertNotEqual(toggle(settings, Pages.Block.courierEnabled)?.enabled, false)
        XCTAssertTrue(texts(settings).contains("Courier token saved"))
        XCTAssertTrue(texts(settings).contains("Clear Courier Token"))
        XCTAssertFalse(texts(settings).contains(Pages.courierTokenFirst))
        XCTAssertNotNil(toggle(Pages.island(status), Pages.Block.muteOwnMessages), "Courier on is a chat app on")
    }

    func testOnWithNoTokenTheIslandAsksForItAndBothPagesWarn() throws {
        var status = ready()
        status.config.effectiveChatMonitor.courierEnabled = true
        let island = Pages.island(status)
        XCTAssertEqual(field(island, Pages.Block.courierToken)?.placeholder?.text(for: "en"), Pages.pasteCourierToken)
        XCTAssertTrue(texts(island).contains(Pages.courierTokenSteps))
        XCTAssertTrue(Pages.courierTokenSteps.contains("Settings › Integrations › New connection…"))
        let missing = ChatMonitorError.chatAppTokenMissing(.courier).localizedDescription
        XCTAssertEqual(Pages.chatWarnings(status), [missing])
        status.chat = Pages.Chat(hasCourierToken: true)
        XCTAssertEqual(Pages.chatWarnings(status), [])
    }

    func testANetworkVitruvianSpeakerReadsItselfIsReadHereAsWellNotMuted() throws {
        var status = ready()
        status.config.effectiveChatMonitor.courierEnabled = true
        status.config.effectiveChatMonitor.courierMutedNetworks = ["telegram"]
        status.chat = Pages.Chat(ownerRunning: true, monitor: ChatMonitorStatus(isRunning: true, courierNetworks: ["WhatsApp"],
                                                                                 courierSkippedNetworks: ["Slack"],
                                                                                 courierNetworkStates: [
            BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
            BeeperNetworkState(key: "slack", name: "Slack", state: .skipped),
            BeeperNetworkState(key: "telegram", name: "Telegram", state: .muted),
        ]), hasCourierToken: true)
        var page = Pages.island(status)
        XCTAssertEqual(courierSwitches(page), ["courier.network.slack", "courier.network.telegram", "courier.network.whatsapp"])
        let slack = try XCTUnwrap(toggle(page, "courier.network.slack"))
        XCTAssertEqual(slack.title.text(for: "en"), "Slack · Read directly")
        XCTAssertFalse(slack.value)
        XCTAssertNil(slack.enabled, "unlike Beeper's, it can be read through Courier as well")
        XCTAssertEqual(toggle(page, "courier.network.telegram")?.value, false)
        XCTAssertEqual(toggle(page, "courier.network.whatsapp")?.value, true)
        XCTAssertFalse(texts(page).contains("Other networks show here once Courier is being read."), "read already")
        XCTAssertTrue(texts(Pages.settings(status)).contains("Reading Courier: WhatsApp · Slack skipped (read directly)"))

        // Read anyway: the monitor reads it, and the switch says so.
        status.config.effectiveChatMonitor.courierReadAnyway = ["slack"]
        status.chat.monitor?.courierNetworkStates?[1].state = .reading
        page = Pages.island(status)
        let also = try XCTUnwrap(toggle(page, "courier.network.slack"))
        XCTAssertEqual(also.title.text(for: "en"), "Slack · Also read here")
        XCTAssertTrue(also.value)

        // As chips, for an app that draws them.
        status.offersChips = true
        let networks = try XCTUnwrap(chips(Pages.island(status), Pages.Block.courierNetworks))
        XCTAssertEqual(networks.options, [
            UIChipOption(value: "slack", title: .plain("Slack · Also read here"), on: true),
            UIChipOption(value: "telegram", title: .plain("Telegram"), on: false),
            UIChipOption(value: "whatsapp", title: .plain("WhatsApp"), on: true),
        ])
        XCTAssertEqual(courierSwitches(Pages.island(status)), [], "one block, no switch each")
    }

    // MARK: - The island, round trip

    func testTheIslandSwitchAsksForTheTokenAndTurnsCourierOnOnceItIsSaved() throws {
        let secret = "fake-courier-token-for-the-tool-test" // gitleaks:allow (made-up test token)
        let tool = tool()
        _ = tool.islandPage()
        var island = page(tool.islandEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(true))))
        XCTAssertFalse(monitor.courierEnabled, "not on without a token")
        XCTAssertEqual(store.saves, 0)
        XCTAssertEqual(toggle(island, Pages.Block.courierEnabled)?.value, false)
        XCTAssertNotNil(field(island, Pages.Block.courierToken), "it asks for the token")
        XCTAssertTrue(texts(island).contains(Pages.courierTokenSteps))

        XCTAssertEqual(tool.islandEvent(PanelEvent(block: Pages.Block.courierToken, kind: .change, value: .string(secret))), .keep)
        island = page(tool.islandEvent(PanelEvent(block: Pages.Block.saveCourierToken, kind: .tap)))
        XCTAssertEqual(chat.courierSaved, [secret])
        XCTAssertEqual(posted, 1, "the running monitor is told")
        XCTAssertTrue(monitor.courierEnabled, "what the switch was turned on for")
        XCTAssertEqual(toggle(island, Pages.Block.courierEnabled)?.value, true)
        XCTAssertNil(field(island, Pages.Block.courierToken))
        XCTAssertTrue(ids(island).contains(Pages.Block.courierAnnounce), "its Announce choice follows")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(island), as: UTF8.self).contains(secret))
        XCTAssertFalse(link.logged.contains { $0.contains(secret) })

        // Off, and on again with the token saved: saved at once.
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(false)))
        XCTAssertFalse(monitor.courierEnabled)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(true)))
        XCTAssertTrue(monitor.courierEnabled)
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.courierAnnounce, kind: .change, value: .string("all")))
        XCTAssertEqual(monitor.courierAnnounce, .all)
        XCTAssertEqual(monitor.beeperAnnounce, .directAndMentions, "Beeper's is left alone")
    }

    func testTurningTheIslandSwitchOffForgetsTheAsk() {
        let tool = tool()
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(true)))
        let island = page(tool.islandEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(false))))
        XCTAssertNil(field(island, Pages.Block.courierToken))
        XCTAssertFalse(monitor.courierEnabled)
    }

    // MARK: - Settings, round trip

    func testSettingsRefusesCourierWithoutATokenThenSavesEachSetting() throws {
        let secret = "fake-courier-token-for-the-settings-test" // gitleaks:allow (made-up test token)
        let tool = tool()
        _ = tool.settingsPage()
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string(Pages.Section.monitor.rawValue)))
        var settings = page(tool.settingsEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(true))))
        XCTAssertFalse(monitor.courierEnabled, "an app that ignores `enabled` still cannot turn it on")
        XCTAssertEqual(tool.setupNotice, Pages.courierTokenFirst)

        settings = page(tool.settingsEvent(PanelEvent(block: Pages.Block.courierToken, kind: .submit, value: .string("  \(secret)\n"))))
        XCTAssertEqual(chat.courierSaved, [secret], "trimmed")
        XCTAssertEqual(tool.setupNotice, "Courier token saved")
        XCTAssertEqual(posted, 1)
        XCTAssertNotEqual(toggle(settings, Pages.Block.courierEnabled)?.enabled, false, "it can be turned on now")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains(secret))

        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.courierEnabled, kind: .toggle, value: .bool(true)))
        XCTAssertTrue(monitor.courierEnabled)
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.courierAnnounce, kind: .change, value: .string("all")))
        XCTAssertEqual(monitor.courierAnnounce, .all)
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.courierAnnounce, kind: .change, value: .string("vips")))
        XCTAssertEqual(monitor.courierAnnounce, .all, "a mode Vitruvian Speaker does not have is not saved")
        XCTAssertFalse(monitor.beeperEnabled, "Beeper is left alone")

        // Cleared: Courier goes off with it, as in Vitruvian Speaker's own Settings.
        settings = page(tool.settingsEvent(PanelEvent(block: Pages.Block.clearCourierToken, kind: .tap)))
        XCTAssertEqual(chat.courierCleared, 1)
        XCTAssertFalse(monitor.courierEnabled)
        XCTAssertEqual(toggle(settings, Pages.Block.courierEnabled)?.enabled, false)
    }

    func testANetworkSwitchMutesItOrReadsItHereAsWell() throws {
        chat.courierToken = "saved"
        store.config?.effectiveChatMonitor.courierEnabled = true
        try courierRunning([BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
                            BeeperNetworkState(key: "slack", name: "Slack", state: .skipped)])
        let tool = tool()
        _ = tool.islandPage()
        _ = tool.islandEvent(PanelEvent(block: "courier.network.whatsapp", kind: .toggle, value: .bool(false)))
        XCTAssertEqual(monitor.courierMutedNetworks, ["whatsapp"])
        XCTAssertEqual(monitor.beeperMutedNetworks, [], "Beeper's mutes are Beeper's")
        _ = tool.settingsEvent(PanelEvent(block: "courier.network.whatsapp", kind: .toggle, value: .bool(true)))
        XCTAssertEqual(monitor.courierMutedNetworks, [])

        _ = tool.islandEvent(PanelEvent(block: "courier.network.slack", kind: .toggle, value: .bool(true)))
        XCTAssertEqual(monitor.courierReadAnyway, ["slack"], "read through Courier as well")
        XCTAssertEqual(monitor.courierMutedNetworks, [], "never muted")
        _ = tool.settingsEvent(PanelEvent(block: "courier.network.slack", kind: .toggle, value: .bool(false)))
        XCTAssertEqual(monitor.courierReadAnyway, [], "left to Vitruvian Speaker's own Slack again")
        XCTAssertEqual(monitor.courierMutedNetworks, [])
    }

    func testAChipsEventSavesMutesAndReadAnyway() throws {
        chat.courierToken = "saved"
        store.config?.effectiveChatMonitor.courierEnabled = true
        link.features = [.choice, .chips]
        try courierRunning([BeeperNetworkState(key: "whatsapp", name: "WhatsApp", state: .reading),
                            BeeperNetworkState(key: "signal", name: "Signal", state: .reading),
                            BeeperNetworkState(key: "slack", name: "Slack", state: .skipped)])
        let tool = tool()
        _ = tool.settingsPage()
        let chipsEvent = { (values: [String]) in
            PanelEvent(block: Pages.Block.courierNetworks, kind: .change, value: .array(values.map { .string($0) }))
        }
        _ = tool.islandPage()
        _ = tool.islandEvent(chipsEvent(["signal", "slack"]))
        XCTAssertEqual(monitor.courierMutedNetworks, ["whatsapp"])
        XCTAssertEqual(monitor.courierReadAnyway, ["slack"])
        XCTAssertEqual(monitor.beeperMutedNetworks, [])
        _ = tool.settingsEvent(chipsEvent(["whatsapp", "signal"]))
        XCTAssertEqual(monitor.courierMutedNetworks, [])
        XCTAssertEqual(monitor.courierReadAnyway, [])
    }

    func testNetworkIdsSayWhichApp() {
        XCTAssertEqual(Pages.Block.network(.courier, "whatsapp"), "courier.network.whatsapp")
        XCTAssertEqual(Pages.Block.networkKey("courier.network.whatsapp")?.app, .courier)
        XCTAssertEqual(Pages.Block.networkKey("beeper.network.whatsapp")?.app, .beeper)
        XCTAssertNil(Pages.Block.beeperNetworkKey("courier.network.whatsapp"))
        XCTAssertNil(Pages.Block.networkKey("courier.network.Bad!"))
        XCTAssertTrue(ManifestRules.isWellFormedName(Pages.Block.network(.courier,
                                                                         String(repeating: "k", count: ChatAppClient.maxNetworkKeyLength))))
    }
}
