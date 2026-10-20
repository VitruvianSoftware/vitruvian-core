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

/// Every page HomeSpeaker can send, read the way Vitruvian reads it.
///
/// Vitruvian refuses a WHOLE page when one block id, or one list row id,
/// breaks the protocol's name rule (`ManifestRules.isWellFormedName`):
/// the panel then spins, and only the app's log says why. HomeSpeaker
/// 1.27.1's AI Agents buttons were `installHook:claudeCode`, and the
/// colon took Settings down. The tests elsewhere drew those pages and
/// measured them but never read them back, so nothing saw it. Here each
/// page goes through `UITree(from:)`, the decoder the app uses, which
/// refuses exactly what the app refuses.
final class PageIdsTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Account = HomeSpeakerToolTests.Account

    // MARK: - Reading a page as Vitruvian does

    /// Why Vitruvian would not draw `tree`, or nil when it would: the
    /// page as the tool sends it (a `JSONValue`), written again the way
    /// the app writes it (`ToolPanelTree.read`), held to the size limit
    /// and decoded as a `UITree`.
    static func whyTheAppRefuses(_ tree: UITree) -> String? {
        do {
            let sent = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(tree))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(sent)
            guard data.count <= UILimits.maxTreeBytes else { return "\(data.count) bytes, over \(UILimits.maxTreeBytes)" }
            _ = try JSONDecoder().decode(UITree.self, from: data)
            return nil
        } catch let DecodingError.dataCorrupted(context) {
            return "\(place(context.codingPath)): \(context.debugDescription)"
        } catch let DecodingError.keyNotFound(key, context) {
            return "\(place(context.codingPath + [key])): missing"
        } catch {
            return "\(error)"
        }
    }

    private static func place(_ keys: [any CodingKey]) -> String {
        keys.map { key in key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)" }.joined()
    }

    /// Every block id and list row id on `tree` that the protocol's rule
    /// refuses, so a failure names the id and not only where it sat.
    static func malformedIds(_ tree: UITree) -> [String] {
        var bad: [String] = []
        for block in tree.blocks {
            if let id = block.id, !ManifestRules.isWellFormedName(id) { bad.append(id) }
            if case .list(let list) = block.content {
                bad += list.rows.map(\.id).filter { !ManifestRules.isWellFormedName($0) }
            }
        }
        return bad
    }

    private func assertTheAppDraws(_ tree: UITree, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Self.malformedIds(tree), [], "\(label): ids Vitruvian refuses", file: file, line: line)
        XCTAssertNil(Self.whyTheAppRefuses(tree), "\(label): Vitruvian would not draw it", file: file, line: line)
    }

    /// Every page `status` gives: the island, Settings on each section
    /// for an app without sections, and the one page with every section.
    static func pages(_ status: Pages.Status) -> [(String, UITree)] {
        var pages = [("island", Pages.island(status))]
        var single = status
        single.offersSections = false
        for section in Pages.Section.allCases {
            single.section = section
            pages.append(("settings/\(section.rawValue)", Pages.settings(single)))
        }
        var whole = status
        whole.offersSections = true
        pages.append(("settings/every-section", Pages.settings(whole)))
        return pages
    }

    /// `status` as every app might ask for it: with and without the
    /// choice and chips blocks, and HomeSpeaker installed or not. Sections
    /// are covered by `pages`.
    static func everyApp(_ status: Pages.Status) -> [(String, Pages.Status)] {
        var out: [(String, Pages.Status)] = []
        for choice in [false, true] {
            for chips in [false, true] {
                for opens in [false, true] {
                    for installed in [true, false] {
                        var app = status
                        app.offersChoice = choice
                        app.offersChips = chips
                        app.opensSettings = opens
                        app.installed = installed
                        out.append(("choice=\(choice) chips=\(chips) opens=\(opens) installed=\(installed)", app))
                    }
                }
            }
        }
        return out
    }

    // MARK: - Fixtures

    static let configured = SpeakerConfig(
        enabled: true, defaultTarget: "kitchen", structureId: "s1",
        targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen"),
                  "office": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office"),
                  "all": SpeakerDevice(id: "structure@s1", type: "Structure", name: "Whole Home")],
        quietHoursEnabled: true, quietHoursStart: "22:00", quietHoursEnd: "07:00")

    /// The AI Agents states that draw every button that section has: for
    /// Claude Code, which HomeSpeaker hooks, Install Hook, Update Hook,
    /// Remove (installed, and left behind by a HomeSpeaker that is gone)
    /// and Turn it off (a second hook speaks too); for Antigravity, which
    /// has no hook, Add Instruction. Then both set up, and both missing.
    static func agentFixtures() -> [(String, Pages.Agents)] {
        let rival = URL(fileURLWithPath: "/u/.claude/skills/google-home/hooks/hooks.json")
        let hookCommands: [CodingAgent: String] = [.claudeCode: "\"/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker\" --claude-stop-hook"]
        func agents(_ claude: AgentIntegration.HookStatus, rival claudeRival: URL? = nil, claudeInstruction: Bool = false,
                    antigravityInstruction: Bool = false, installed: Bool = true, legacy: Bool = true) -> Pages.Agents {
            Pages.Agents(
                statuses: [
                    AgentIntegration.AgentStatus(agent: .claudeCode, isInstalled: installed, hook: claude,
                                                 configuredByInstruction: claudeInstruction, rivalHook: claudeRival),
                    AgentIntegration.AgentStatus(agent: .antigravity, isInstalled: installed, hook: .notInstalled,
                                                 configuredByInstruction: antigravityInstruction, rivalHook: nil),
                ],
                hookCommands: hookCommands, legacyLaunchAgent: legacy)
        }
        return [
            ("install hook, add instruction", agents(.notInstalled)),
            ("remove hook, disable rival", agents(.installed, rival: rival, claudeInstruction: true)),
            ("update hook", agents(.stale("/Users/someone/Downloads/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"))),
            ("both set up", agents(.installed, antigravityInstruction: true, legacy: false)),
            ("neither on this Mac", agents(.notInstalled, installed: false, legacy: false)),
        ]
    }

    /// The island's and Settings' states, beside the agents': first run,
    /// first run with homes to pick, and everything on.
    static func contentFixtures() -> [(String, Pages.Status)] {
        var blank = Pages.Status()
        blank.account = Pages.Account(hasAntigravityTokens: true)

        var homes = Pages.Status()
        homes.account = Pages.Account(isSignedIn: true, email: "me@example.com", hasOAuthClient: true)
        homes.homes = [HomeStructure(id: "5219a9d7-d46d-7834-5cb3-19242d447eaf", name: "Lake House"),
                       HomeStructure(id: "h2", name: "City Flat")]
        homes.setupBusy = .app(.discover(save: false, home: nil))

        var full = Pages.Status()
        full.config = configured
        full.config.effectiveSpeakLocal = true
        full.config.effectiveAnnounceVolumeEnabled = true
        full.config.effectivePauseMedia = true
        full.config.effectiveChatMonitor = ChatMonitorConfig(slackEnabled: true, googleChatEnabled: true, beeperEnabled: true)
        full.config.effectiveChatMonitor.beeperMutedNetworks = ["telegram", "saved-mute"]
        full.account = Pages.Account(isSignedIn: true, email: "me@example.com", hasOAuthClient: true, customOAuthClientId: "id",
                                     hasCustomOAuthClientSecret: true, hasBundledOAuthClient: true)
        full.volume = Volume(speaker: "Kitchen", percent: 40, muted: false, online: true)
        full.busy = .volume
        full.notice = "Spoken on Kitchen"
        full.quietNow = true
        full.homes = [HomeStructure(id: "s1", name: "Lake House"), HomeStructure(id: "s2", name: "City Flat")]
        full.voices = [LocalVoice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .standard),
                       LocalVoice(id: "com.apple.voice.premium.en-GB.Malcolm", name: "Malcolm", language: "en-GB", quality: .premium)]
        full.recentBroadcasts = (0..<3).map { BroadcastLogItem(text: "message \($0)", targetName: "Kitchen", source: "Say") }
        full.chat = Pages.Chat(hasSlackToken: true, hasChatAccess: true, gwsPath: "/opt/homebrew/bin/gws", ownerRunning: true,
                               monitor: ChatMonitorStatus(isRunning: true, lastPollDate: Date(), lastError: "it failed",
                                                          beeperNetworkStates: ChatSlackTests.manyNetworkStates()),
                               hasBeeperToken: true)
        full.mediaPauseReport = "Paused Music"
        full.volumeRestoreReport = "Put Kitchen back to 40"
        full.draftClientId = "draft"
        full.draftClientSecretTyped = true
        full.files = Pages.Files(settings: "/u/settings.json", secrets: "/u/secrets.json", history: "/u/history.json",
                                 homeSpeakerVersion: "1.27.1")
        var removing = full
        removing.removingSpeakers = true
        removing.configProblem = "line 3 is not JSON"
        return [("first run", blank), ("homes to pick", homes), ("everything on", full), ("removing speakers", removing)]
    }

    /// A settings file written by hand, or by an older tool: speaker keys,
    /// Beeper mutes, a voice and homes that are not the protocol's names.
    static func handEditedFixture() -> Pages.Status {
        var status = contentFixtures().first { $0.0 == "everything on" }!.1
        let long = String(repeating: "x", count: 200)
        for key in ["Living Room", "kitchen:2", "café", ".hidden", "a..b", "trailing.", "", "row.speaker", long] {
            status.config.targets[key] = SpeakerDevice(id: "d-\(key.count)", type: "SpeakerDevice", name: "Hand \(key)")
        }
        status.config.defaultTarget = "Living Room"
        status.config.effectiveChatMonitor.beeperMutedNetworks = ["My Network", "WhatsApp", "a:b", long]
        status.config.effectiveLocalVoice = "Samantha (Enhanced)" + String(repeating: " ", count: 130)
        status.config.quietHoursStart = String(repeating: "9", count: 200)
        status.homes = [HomeStructure(id: "enterprises/p/structures/s 1", name: "Lake House"), HomeStructure(id: "home:2", name: "City Flat")]
        status.selectedHomeId = "home:2"
        return status
    }

    /// The choice card at each step, and each role, on both pages.
    static func doorFixtures() -> [(String, Pages.Status)] {
        var base = Pages.Status()
        base.config = configured
        base.account = Pages.Account(isSignedIn: true, hasOAuthClient: true)
        let snapshot = DoorSnapshot(settingsChanged: Date(), googleEmail: "me@example.com", hasHomeLogin: true, homeName: "Lake House",
                                    speakerCount: 3, defaultSpeaker: "Kitchen", quietHours: "22:00 to 07:00", chatSources: ["Slack"])
        let compare = Pages.DoorCompare(purpose: .choose, from: .app, into: .extension, source: snapshot, destination: DoorSnapshot(),
                                        problem: "the app's file did not read")
        var working = Pages.DoorOffers(quit: true, plan: OtherAppPlan.forChoosingTheExtension(appVersion: "1.18.0"))
        working.working = true
        let steps: [(String, Pages.DoorStep?)] = [
            ("no step", nil), ("compare", .compare(compare)), ("closing", .closing), ("opening", .opening),
            ("offers", .offers(Pages.DoorOffers(quit: false, plan: OtherAppPlan.forChoosingTheExtension(appVersion: nil)))),
            ("offers, old app, working", .offers(working)),
        ]
        let roles: [(String, DoorRole)] = [("active", .active), ("activeAsking", .activeAsking), ("waitingAsking", .waitingAsking),
                                           ("quiet", .quiet(other: .app))]
        var out: [(String, Pages.Status)] = []
        for (roleName, role) in roles {
            for otherInstalled in [true, false] {
                for (stepName, step) in steps {
                    var status = base
                    status.door = Pages.DoorState(role: role, otherInstalled: otherInstalled, step: step,
                                                  report: ["Copied the settings"], oldAppRunning: roleName == "active",
                                                  otherStarting: stepName == "opening")
                    out.append(("door \(roleName) other=\(otherInstalled) \(stepName)", status))
                }
            }
        }
        return out
    }

    // MARK: - Every page, read back

    func testEveryPageWithEveryAgentButtonIsOneVitruvianDraws() {
        var drawnAgentIds = Set<String>()
        for (agentsName, agents) in Self.agentFixtures() {
            for (appName, app) in Self.everyApp(Self.contentFixtures().first { $0.0 == "everything on" }!.1) {
                var status = app
                status.agents = agents
                for (pageName, tree) in Self.pages(status) {
                    assertTheAppDraws(tree, "\(agentsName) · \(appName) · \(pageName)")
                    drawnAgentIds.formUnion(tree.blocks.compactMap(\.id).filter { Pages.Block.agentAction($0) != nil })
                }
            }
        }
        // The fixtures reach every button AI Agents has: Claude Code's
        // four, and Antigravity's one (it has no hook to install, remove
        // or double up).
        let reachable: [(Pages.Block.AgentAction, CodingAgent)] = [
            (.installHook, .claudeCode), (.removeHook, .claudeCode), (.disableRival, .claudeCode), (.addInstruction, .antigravity),
        ]
        XCTAssertEqual(drawnAgentIds, Set(reachable.map { Pages.Block.agent($0.0, $0.1) }))
    }

    func testEveryIslandAndSettingsPageIsOneVitruvianDraws() {
        for (contentName, content) in Self.contentFixtures() {
            for (appName, app) in Self.everyApp(content) {
                for (pageName, tree) in Self.pages(app) {
                    assertTheAppDraws(tree, "\(contentName) · \(appName) · \(pageName)")
                }
            }
        }
    }

    func testEveryDoorStateIsOneVitruvianDraws() {
        for (doorName, door) in Self.doorFixtures() {
            for choice in [false, true] {
                var app = door
                app.offersChoice = choice
                for (pageName, tree) in Self.pages(app) {
                    assertTheAppDraws(tree, "\(doorName) · choice=\(choice) · \(pageName)")
                }
            }
        }
    }

    /// A settings file edited by hand: keys with spaces, colons, accents,
    /// dots in the wrong places, or too long. Each list row still gets an
    /// id Vitruvian takes, and a Beeper mute no network can have gets no
    /// switch.
    func testAHandEditedSettingsFileStillGivesPagesVitruvianDraws() {
        // And a home in the file no listed home has, too long for a menu.
        var unlisted = Self.handEditedFixture()
        unlisted.selectedHomeId = nil
        unlisted.config.structureId = String(repeating: "s", count: 200)
        for (fixtureName, fixture) in [("hand-edited", Self.handEditedFixture()), ("hand-edited, home unlisted", unlisted)] {
            for (appName, app) in Self.everyApp(fixture) {
                for (pageName, tree) in Self.pages(app) {
                    assertTheAppDraws(tree, "\(fixtureName) · \(appName) · \(pageName)")
                }
            }
        }
    }

    // MARK: - Every id builder

    func testEveryIdBuilderGivesAWellFormedName() {
        for action in Pages.Block.AgentAction.allCases {
            for agent in CodingAgent.allCases {
                let id = Pages.Block.agent(action, agent)
                XCTAssertTrue(ManifestRules.isWellFormedName(id), id)
            }
        }
        for agent in CodingAgent.allCases {
            XCTAssertTrue(ManifestRules.isWellFormedName(Pages.Block.agentEnabled(agent)))
        }
        let replay = Pages.Block.replayBroadcast(UUID())
        XCTAssertTrue(ManifestRules.isWellFormedName(replay), replay)
        for index in [0, 9, Pages.maxSetupHomes] {
            XCTAssertTrue(ManifestRules.isWellFormedName(Pages.Block.setupDiscoverHome(index)))
        }
        // The longest key the engine makes for a Beeper network.
        let key = String(repeating: "k", count: BeeperClient.maxNetworkKeyLength)
        XCTAssertTrue(ManifestRules.isWellFormedName(Pages.Block.beeperNetwork(key)))
        // Every value a picker can draw as a list row from an enum.
        let enumValues = Pages.Section.allCases.map(\.rawValue) + SpeechLength.allCases.map(\.rawValue)
            + ChatMonitorConfig.BeeperAnnounce.allCases.map(\.rawValue) + ChatMonitorConfig.GoogleChatSource.allCases.map(\.rawValue)
        for value in enumValues {
            XCTAssertTrue(ManifestRules.isWellFormedName(value), value)
            XCTAssertEqual(Pages.Block.rowId(value), value, "a name the protocol takes is its own row id")
        }
    }

    /// The AI Agents ids are `<action>.<agent>`. A page an older tool drew
    /// (`<action>:<agent>`) still answers, should its event arrive.
    func testAgentIdsUseADotAndTheOldColonStillReads() {
        XCTAssertEqual(Pages.Block.agent(.installHook, .claudeCode), "installHook.claudeCode")
        XCTAssertEqual(Pages.Block.agent(.addInstruction, .antigravity), "addInstruction.antigravity")
        for action in Pages.Block.AgentAction.allCases {
            for agent in CodingAgent.allCases {
                for id in ["\(action.rawValue).\(agent.rawValue)", "\(action.rawValue):\(agent.rawValue)"] {
                    let parsed = Pages.Block.agentAction(id)
                    XCTAssertEqual(parsed?.0, action, id)
                    XCTAssertEqual(parsed?.1, agent, id)
                }
            }
        }
        for id in ["installHook", "installHook.", "installHook:", "installHook.nobody", "nothing.claudeCode", "installHook.claudeCode.x",
                   Pages.Block.say, Pages.Block.setupDiscover, Pages.Block.doorCopy, Pages.Block.outputHome] {
            XCTAssertNil(Pages.Block.agentAction(id), id)
        }
    }

    /// A list row's id: the value itself when the protocol takes it, else
    /// a stand-in made from it, found again among the values drawn.
    func testARowIdIsTheValueOrAWellFormedStandIn() {
        let values = ["kitchen", "Living Room", "kitchen:2", "café", ".hidden", "a..b", "trailing.", "", "row.speaker",
                      "row.0123456789abcdef", String(repeating: "x", count: 200), "enterprises/p/structures/s 1"]
        var ids = Set<String>()
        for value in values {
            let id = Pages.Block.rowId(value)
            XCTAssertTrue(ManifestRules.isWellFormedName(id), "\(value) → \(id)")
            XCTAssertEqual(Pages.Block.rowValue(id, among: values), value, value)
            ids.insert(id)
        }
        XCTAssertEqual(ids.count, values.count, "no two values share a row id")
        XCTAssertEqual(Pages.Block.rowId("kitchen"), "kitchen")
        XCTAssertEqual(Pages.Block.rowId("Living Room"), Pages.Block.rowId("Living Room"), "the same every time it is drawn")
        XCTAssertNil(Pages.Block.rowValue(Pages.Block.rowId("attic"), among: values), "a value no longer there")
        XCTAssertNil(Pages.Block.rowValue(nil, among: values))
    }

    // MARK: - The rows answer by their new ids

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var account: Account!
    private var folder: URL!
    private let voices = [LocalVoice(id: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: .standard)]

    override func setUp() {
        link = Link()
        store = Store()
        driver = Driver()
        account = Account()
        account.isSignedIn = true
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-ids-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "s1",
                                   targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen"),
                                             "Living Room": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Living Room"),
                                             "den:2": SpeakerDevice(id: "d3", type: "SpeakerDevice", name: "Den")])
        config.effectiveSpeakLocal = true
        config.effectiveLocalVoice = "Samantha (Enhanced)"
        store.config = config
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func tool() -> HomeSpeakerTool {
        let voices = self.voices
        return HomeSpeakerTool(parts: .init(link: link, store: store, driver: driver, later: { $0() }, account: account,
                                            voices: { voices }, home: folder,
                                            settingsURL: folder.appendingPathComponent("speaker_broadcast.json"),
                                            historyURL: folder.appendingPathComponent("speaker_history.json")))
    }

    private func rows(_ tree: UITree, _ id: String) -> [UIListRow] {
        guard case .list(let list)? = tree.blocks.first(where: { $0.id == id })?.content else { return [] }
        return list.rows
    }

    func testTheIslandsSpeakerListPicksAKeyThatIsNotAName() {
        let tool = tool()   // no choice block: the speakers are a list
        let page = tool.islandPage()
        assertTheAppDraws(page, "island")
        let id = Pages.Block.rowId("Living Room")
        XCTAssertTrue(rows(page, Pages.Block.speakers).map(\.id).contains(id))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .tap, value: .string(id)))
        XCTAssertEqual(store.config?.defaultTarget, "Living Room")
        // The menu answers with its option's value, the same stand-in.
        link.features = [.choice]
        let menu = self.tool()
        let drawn = menu.islandPage()
        assertTheAppDraws(drawn, "island, menu")
        guard case .choice(let choice)? = drawn.blocks.first(where: { $0.id == Pages.Block.speakers })?.content else {
            return XCTFail("no menu")
        }
        XCTAssertEqual(choice.value, id, "the default, by its stand-in")
        let den = Pages.Block.rowId("den:2")
        XCTAssertTrue(choice.options.map(\.value).contains(den))
        _ = menu.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string(den)))
        XCTAssertEqual(store.config?.defaultTarget, "den:2")
        // A menu an older tool drew answers with the key itself, and still works.
        _ = menu.islandEvent(PanelEvent(block: Pages.Block.speakers, kind: .change, value: .string("Living Room")))
        XCTAssertEqual(store.config?.defaultTarget, "Living Room")
    }

    func testSettingsSpeakersAndVoiceAnswerByTheirRowIds() {
        let tool = tool()
        _ = tool.settingsPage()
        var page = page(tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string("speakers"))))
        assertTheAppDraws(page, "settings/speakers")

        // A speaker made the default by its row.
        let den = Pages.Block.rowId("den:2")
        XCTAssertTrue(rows(page, Pages.Block.targets).map(\.id).contains(den))
        page = self.page(tool.settingsEvent(PanelEvent(block: Pages.Block.targets, kind: .tap, value: .string(den))))
        XCTAssertEqual(store.config?.defaultTarget, "den:2")

        // The saved voice, not installed, is a row; the installed one is picked.
        let voiceRows = rows(page, Pages.Block.voice).map(\.id)
        XCTAssertTrue(voiceRows.contains(Pages.Block.rowId("Samantha (Enhanced)")))
        page = self.page(tool.settingsEvent(PanelEvent(block: Pages.Block.voice, kind: .tap,
                                                       value: .string(Pages.Block.rowId(voices[0].id)))))
        XCTAssertEqual(store.config?.effectiveLocalVoice, voices[0].id)

        // A home whose id is not a name, picked by its row.
        let odd = "enterprises/p/structures/s 1"
        tool.finished(.app(.discover(save: false, home: nil)),
                      .homes([HomeStructure(id: odd, name: "Lake House"), HomeStructure(id: "h2", name: "City Flat")]))
        page = tool.settingsPage()
        assertTheAppDraws(page, "settings/speakers, homes")
        XCTAssertEqual(rows(page, Pages.Block.home).map(\.id), [Pages.Block.rowId(odd), "h2"])
        page = self.page(tool.settingsEvent(PanelEvent(block: Pages.Block.home, kind: .tap, value: .string(Pages.Block.rowId(odd)))))
        XCTAssertEqual(tool.selectedHomeId, odd)

        // And removed by its row.
        page = self.page(tool.settingsEvent(PanelEvent(block: Pages.Block.editSpeakers, kind: .tap)))
        let living = Pages.Block.rowId("Living Room")
        page = self.page(tool.settingsEvent(PanelEvent(block: Pages.Block.targets, kind: .tap, value: .string(living))))
        XCTAssertNil(store.config?.targets["Living Room"])
        assertTheAppDraws(page, "settings/speakers, removing")
    }

    private func page(_ answer: PanelAnswer, file: StaticString = #filePath, line: UInt = #line) -> UITree {
        guard case .page(let tree) = answer else {
            XCTFail("no page: \(answer)", file: file, line: line)
            return UITree(blocks: [])
        }
        return tree
    }
}
