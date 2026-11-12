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

/// The settings panel's AI Agents and Google Cloud sections, driven as the
/// app drives them, against a home folder of its own and a launchctl that
/// only records: nothing here touches this Mac's agents or login session.
final class AgentsCloudTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Account = HomeSpeakerToolTests.Account

    /// launchctl, as the tests see it: what it was asked to stop.
    final class Bootouts: @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [String] = []
        var targets: [String] { lock.withLock { asked } }
        func record(_ target: String) { lock.withLock { asked.append(target) } }
    }

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var account: Account!
    private var bootouts: Bootouts!
    private var home: URL!
    private var homeSpeakerVersion: String?
    private let appProgram = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"

    override func setUpWithError() throws {
        link = Link()
        store = Store()
        driver = Driver()
        account = Account()
        bootouts = Bootouts()
        homeSpeakerVersion = "1.13.2"
        home = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen")])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func tool() -> HomeSpeakerTool {
        let bootouts = self.bootouts!
        return HomeSpeakerTool(parts: .init(
            link: link, store: store, driver: driver, later: { $0() }, account: account, home: home,
            settingsURL: URL(fileURLWithPath: "/u/.gemini/speaker_broadcast.json"),
            secretsURL: URL(fileURLWithPath: "/u/Library/Application Support/HomeSpeaker/secrets.json"),
            homeSpeakerVersion: { [unowned self] in homeSpeakerVersion },
            launchctlBootout: { bootouts.record($0) }))
    }

    /// Settings opened on `section`, the login item answered when there
    /// is a HomeSpeaker to ask.
    private func opened(_ section: Pages.Section) -> HomeSpeakerTool {
        let tool = tool()
        _ = tool.settingsPage()
        _ = event(tool, Pages.Block.section, .tap, .string(section.rawValue))
        XCTAssertEqual(tool.section, section)
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
    private func event(_ tool: HomeSpeakerTool, _ block: String, _ kind: UIEventKind, _ value: JSONValue? = nil,
                       file: StaticString = #filePath, line: UInt = #line) -> UITree {
        page(tool.settingsEvent(PanelEvent(block: block, kind: kind, value: value)), file: file, line: line)
    }

    private func answer(_ tool: HomeSpeakerTool, _ block: String, _ kind: UIEventKind, _ text: String) -> PanelAnswer {
        tool.settingsEvent(PanelEvent(block: block, kind: kind, value: .string(text)))
    }

    private func content(_ tree: UITree, _ id: String) -> UIBlock.Content? { tree.blocks.first { $0.id == id }?.content }

    private func texts(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .heading(let heading): return heading.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en") + " · " + (row.subtitle?.text(for: "en") ?? "")
            case .button(let button): return button.title.text(for: "en")
            case .link(let link): return link.title.text(for: "en")
            default: return nil
            }
        }
    }

    private func button(_ tree: UITree, _ id: String) -> ButtonBlock? {
        if case .button(let b)? = content(tree, id) { return b }
        return nil
    }

    private func field(_ tree: UITree, _ id: String) -> FieldBlock? {
        if case .field(let f)? = content(tree, id) { return f }
        return nil
    }

    // MARK: - Files on disk

    private func write(_ text: String, _ path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) -> String? {
        try? String(contentsOf: home.appendingPathComponent(path), encoding: .utf8)
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent(path).path) }

    /// Claude Code is on this Mac, with HomeSpeaker's hook pointed at `program`.
    private func claudeHook(_ program: String) throws {
        let settings = AgentIntegration.mergeHook(into: [:], command: AgentIntegration.hookCommand(executable: program), agent: .claudeCode)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try write(String(decoding: data, as: UTF8.self), ".claude/settings.json")
    }

    private func installedHookCommand() -> String? {
        guard let data = read(".claude/settings.json").map({ Data($0.utf8) }),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return AgentIntegration.installedHookCommand(in: json, agent: .claudeCode)
    }

    // MARK: - Google Cloud: the client typed, then saved with one button

    func testTypingTheSecretKeepsThePageSoARedrawNeverWipesIt() {
        let tool = opened(.googleCloud)
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientSecret, .change, "s3cret"), .keep, "a redraw would draw the field empty")
        XCTAssertEqual(tool.draftClientSecret, "s3cret")
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientSecret, .submit, "s3cret2"), .keep)
        XCTAssertEqual(tool.draftClientSecret, "s3cret2")
        XCTAssertTrue(account.oauthSaves.isEmpty, "nothing is saved before Save")

        // The id's first character redraws the page (Save turns on): the
        // secret's field is drawn empty, but what was typed is held.
        let tree = event(tool, Pages.Block.oauthClientId, .change, .string("id.apps.googleusercontent.com"))
        XCTAssertEqual(field(tree, Pages.Block.oauthClientSecret)?.value, "", "a secret is never drawn back")
        XCTAssertEqual(field(tree, Pages.Block.oauthClientSecret)?.kind, .secret)
        XCTAssertEqual(field(tree, Pages.Block.oauthClientSecret)?.placeholder?.text(for: "en"), "Typed — press Save to keep it")
        XCTAssertEqual(tool.draftClientSecret, "s3cret2", "the redraw did not lose it")

        event(tool, Pages.Block.saveOAuthClient, .tap)
        XCTAssertEqual(account.oauthSaves.count, 1)
        XCTAssertEqual(account.oauthSaves.first?.id, "id.apps.googleusercontent.com")
        XCTAssertEqual(account.oauthSaves.first?.secret, "s3cret2")
    }

    func testTheClientIdRedrawsOnlyWhenSaveTurnsOnOrOff() {
        let tool = opened(.googleCloud)
        var tree = tool.settingsPage()
        XCTAssertEqual(button(tree, Pages.Block.saveOAuthClient)?.enabled, false, "nothing typed, nothing to save")

        tree = event(tool, Pages.Block.oauthClientId, .change, .string("a"))
        XCTAssertEqual(button(tree, Pages.Block.saveOAuthClient)?.enabled, true)
        XCTAssertEqual(field(tree, Pages.Block.oauthClientId)?.value, "a")
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientId, .change, "ab"), .keep, "still typed: nothing on the page changes")
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientId, .submit, "abc"), .keep)
        XCTAssertEqual(tool.draftClientId, "abc")

        tree = event(tool, Pages.Block.oauthClientId, .change, .string("   "))
        XCTAssertEqual(button(tree, Pages.Block.saveOAuthClient)?.enabled, false, "blank again: Save turns off")
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientId, .change, ""), .keep, "still blank")
        tree = event(tool, Pages.Block.oauthClientId, .submit, .string("x"))
        XCTAssertEqual(button(tree, Pages.Block.saveOAuthClient)?.enabled, true)
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientId, .tap, ""), .keep, "only typing changes the draft")
    }

    func testSaveKeepsTheSavedSecretForTheSameIdAndDropsItForANewOne() {
        account.customOAuthClientId = "old.apps.googleusercontent.com"
        account.customOAuthClientSecret = "old-secret"
        let tool = opened(.googleCloud)
        XCTAssertEqual(tool.draftClientId, "old.apps.googleusercontent.com", "the saved id is where typing starts")
        var tree = tool.settingsPage()
        XCTAssertEqual(field(tree, Pages.Block.oauthClientSecret)?.placeholder?.text(for: "en"), "Saved — type a new one to replace it")
        XCTAssertTrue(texts(tree).contains("Your OAuth client is saved · old.apps.googleusercontent.com"))

        // Same id, a secret typed then blanked: the saved secret is kept.
        XCTAssertEqual(answer(tool, Pages.Block.oauthClientSecret, .change, "   "), .keep)
        tree = event(tool, Pages.Block.saveOAuthClient, .tap)
        XCTAssertEqual(account.oauthSaves.count, 1, "one write")
        XCTAssertNil(account.oauthSaves.first?.secret ?? nil, "no secret typed")
        XCTAssertEqual(account.customOAuthClientSecret, "old-secret", "same client: the saved secret stays")
        XCTAssertEqual(tool.setupNotice, "OAuth client saved. Sign in from General to use it")
        XCTAssertTrue(texts(tree).contains("OAuth client saved. Sign in from General to use it"))

        // A new id with no secret typed: the old client's secret is dropped.
        _ = answer(tool, Pages.Block.oauthClientId, .change, "  new.apps.googleusercontent.com  ")
        tree = event(tool, Pages.Block.saveOAuthClient, .tap)
        XCTAssertEqual(account.oauthSaves.last?.id, "new.apps.googleusercontent.com", "trimmed")
        XCTAssertNil(account.oauthSaves.last?.secret ?? nil)
        XCTAssertNil(account.customOAuthClientSecret, "a new client never inherits the old one's secret")
        XCTAssertEqual(field(tree, Pages.Block.oauthClientId)?.value, "new.apps.googleusercontent.com")
    }

    func testSaveIsRefusedWithNoIdAndClearForgetsBoth() {
        let tool = opened(.googleCloud)
        var tree = event(tool, Pages.Block.saveOAuthClient, .tap)
        XCTAssertTrue(account.oauthSaves.isEmpty)
        XCTAssertTrue(texts(tree).contains("Type the Client ID first"))
        XCTAssertNil(content(tree, Pages.Block.clearOAuthClient), "nothing saved, nothing to clear")

        _ = answer(tool, Pages.Block.oauthClientId, .change, "id")
        _ = answer(tool, Pages.Block.oauthClientSecret, .change, "secret")
        tree = event(tool, Pages.Block.saveOAuthClient, .tap)
        XCTAssertEqual(account.customOAuthClientSecret, "secret")
        XCTAssertNotNil(button(tree, Pages.Block.clearOAuthClient))

        tree = event(tool, Pages.Block.clearOAuthClient, .tap)
        XCTAssertEqual(account.oauthClears, 1)
        XCTAssertNil(account.customOAuthClientId)
        XCTAssertNil(account.customOAuthClientSecret)
        XCTAssertEqual(tool.draftClientId, "")
        XCTAssertEqual(tool.draftClientSecret, "")
        XCTAssertEqual(field(tree, Pages.Block.oauthClientId)?.value, "")
        XCTAssertEqual(button(tree, Pages.Block.saveOAuthClient)?.enabled, false)
        XCTAssertTrue(texts(tree).contains("OAuth client cleared"))
    }

    func testTheDraftsStartAfreshEachTimeSettingsOpens() {
        account.customOAuthClientId = "saved"
        let tool = opened(.googleCloud)
        _ = answer(tool, Pages.Block.oauthClientId, .change, "typed")
        _ = answer(tool, Pages.Block.oauthClientSecret, .change, "typed-secret")
        _ = tool.settingsPage()
        XCTAssertEqual(tool.draftClientId, "typed", "a redraw keeps what is typed")
        XCTAssertEqual(tool.draftClientSecret, "typed-secret")

        tool.panelClosed(HomeSpeakerTool.settingsPanel)
        _ = tool.settingsPage()
        XCTAssertEqual(tool.draftClientId, "saved", "opened again: the saved id")
        XCTAssertEqual(tool.draftClientSecret, "", "and no secret")
    }

    func testSetUpGoesToGoogleCloudAndLeavesRemovingSpeakers() {
        account.hasOAuthClient = false
        let tool = opened(.speakers)
        event(tool, Pages.Block.editSpeakers, .tap)
        XCTAssertTrue(tool.removingSpeakers)
        // Set up… leaves a section as the switcher does: removing ends.
        let tree = event(tool, Pages.Block.openGoogleCloud, .tap)
        XCTAssertEqual(tool.section, .googleCloud)
        XCTAssertFalse(tool.removingSpeakers)
        XCTAssertNotNil(content(tree, Pages.Block.oauthClientId))
    }

    func testTheGoogleCloudSectionHasTheStepsTheClientAndTheFiles() {
        let tool = opened(.googleCloud)
        let tree = tool.settingsPage()
        let said = texts(tree)
        XCTAssertTrue(said.contains("Your Google Cloud project"))
        XCTAssertTrue(said.contains { $0.hasPrefix("4 · Create an OAuth client") })
        XCTAssertTrue(said.contains(GoogleAuth.allRedirectURIs.joined(separator: "\n")))
        XCTAssertTrue(said.contains("Open Google Cloud Console"))
        XCTAssertTrue(said.contains("One-time setup. Your client ID and secret never leave this Mac."))
        XCTAssertTrue(said.contains("Settings · /u/.gemini/speaker_broadcast.json"))
        XCTAssertTrue(said.contains("Secrets · /u/Library/Application Support/HomeSpeaker/secrets.json"))
        XCTAssertTrue(said.contains("Tool version · \(ToolVersion.current)"))
        XCTAssertTrue(said.contains("HomeSpeaker version · 1.13.2"))

        account.hasBundledOAuthClient = true
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.hasPrefix("This build also ships with a shared OAuth client") })
        homeSpeakerVersion = nil
        XCTAssertTrue(texts(tool.settingsPage()).contains("HomeSpeaker version · Unknown"))
    }

    func testFilesShowsHomeSpeakersVersionOnlyWhenItIsInstalled() {
        driver.isInstalled = false
        let tool = opened(.googleCloud)
        let said = texts(tool.settingsPage())
        XCTAssertTrue(said.contains("Tool version · \(ToolVersion.current)"))
        XCTAssertFalse(said.contains { $0.hasPrefix("HomeSpeaker version") })
        XCTAssertNotNil(content(tool.settingsPage(), Pages.Block.saveOAuthClient), "the client is saved without HomeSpeaker too")
    }

    func testTheSecretStoreAccountSavesBothInOneWriteAndKeepsTheSecret() throws {
        let secrets = SecretStore(fileURL: home.appendingPathComponent("secrets/secrets.json"))
        try secrets.update { $0.slackToken = "xoxp-kept" }
        let account = SecretStoreAccount(
            store: secrets, antigravityTokens: home.appendingPathComponent("none.json"), profile: .app(home: home))
        XCTAssertNil(account.customOAuthClientId)
        XCTAssertFalse(account.hasCustomOAuthClientSecret)
        XCTAssertFalse(account.hasBundledOAuthClient, "the test bundle ships no client")

        try account.saveOAuthClient(id: "id-1", secret: "secret-1")
        XCTAssertEqual(secrets.load().oauthClientIdOverride, "id-1")
        XCTAssertEqual(secrets.load().oauthClientSecretOverride, "secret-1")
        XCTAssertEqual(account.customOAuthClientId, "id-1")
        XCTAssertTrue(account.hasCustomOAuthClientSecret)

        try account.saveOAuthClient(id: "id-1", secret: nil)
        XCTAssertEqual(secrets.load().oauthClientIdOverride, "id-1")
        XCTAssertEqual(secrets.load().oauthClientSecretOverride, "secret-1", "same id, no secret given: the saved one stays")

        try account.saveOAuthClient(id: "id-2", secret: nil)
        XCTAssertEqual(secrets.load().oauthClientIdOverride, "id-2")
        XCTAssertNil(secrets.load().oauthClientSecretOverride, "a new id never inherits the old client's secret")
        XCTAssertFalse(account.hasCustomOAuthClientSecret)

        try account.saveOAuthClient(id: "id-2", secret: "secret-2")
        XCTAssertEqual(secrets.load().oauthClientSecretOverride, "secret-2")

        try account.clearOAuthClient()
        XCTAssertNil(secrets.load().oauthClientIdOverride)
        XCTAssertNil(secrets.load().oauthClientSecretOverride)
        XCTAssertEqual(secrets.load().slackToken, "xoxp-kept", "nothing else in the file is touched")
    }

    // MARK: - AI Agents

    func testAgentBlockIdsNameTheActionAndTheAgent() {
        XCTAssertEqual(Pages.Block.agent(.installHook, .claudeCode), "installHook.claudeCode")
        XCTAssertEqual(Pages.Block.agent(.removeHook, .claudeCode), "removeHook.claudeCode")
        XCTAssertEqual(Pages.Block.agent(.disableRival, .claudeCode), "disableRival.claudeCode")
        XCTAssertEqual(Pages.Block.agent(.addInstruction, .antigravity), "addInstruction.antigravity")
        for action in Pages.Block.AgentAction.allCases {
            for agent in CodingAgent.allCases {
                let parsed = Pages.Block.agentAction(Pages.Block.agent(action, agent))
                XCTAssertEqual(parsed?.0, action)
                XCTAssertEqual(parsed?.1, agent)
            }
        }
        for id in ["installHook", "installHook.", "installHook:", "installHook.nobody", "installHook:nobody", "nothing.claudeCode",
                   "nothing:claudeCode", Pages.Block.say] {
            XCTAssertNil(Pages.Block.agentAction(id), id)
        }
    }

    func testTheAgentsFilesAreReadOnlyOnTheirSection() throws {
        try write("{}", ".claude/settings.json")
        try write("", "Library/LaunchAgents/\(AgentIntegration.legacyLaunchAgentLabel).plist")
        let tool = opened(.general)
        XCTAssertTrue(tool.status().agents.statuses.isEmpty, "General reads no agent file")
        XCTAssertFalse(tool.status().agents.legacyLaunchAgent)
        _ = event(tool, Pages.Block.section, .tap, .string(Pages.Section.agents.rawValue))
        XCTAssertEqual(tool.status().agents.statuses.map(\.agent), CodingAgent.allCases)
        XCTAssertTrue(tool.status().agents.legacyLaunchAgent)
    }

    func testWithHomeSpeakerAHookIsInstalledShownAndRemoved() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let tool = opened(.agents)
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Claude Code hook · Not installed"))
        let install = Pages.Block.agent(.installHook, .claudeCode)
        XCTAssertNotEqual(button(tree, install)?.enabled, false)

        tree = event(tool, install, .tap)
        XCTAssertEqual(installedHookCommand(), "\"\(appProgram)\" --claude-stop-hook", "pointed at HomeSpeaker, never bin/tool")
        XCTAssertTrue(texts(tree).contains("Claude Code hook · Installed"))
        XCTAssertTrue(texts(tree).contains("\"\(appProgram)\" --claude-stop-hook"), "the command it runs is shown")
        XCTAssertTrue(texts(tree).contains("Claude Code hook installed"))

        tree = event(tool, Pages.Block.agent(.removeHook, .claudeCode), .tap)
        XCTAssertNil(installedHookCommand())
        XCTAssertTrue(texts(tree).contains("Claude Code hook removed"))
    }

    func testWithHomeSpeakerAnOldHookNeedsAnUpdateAndTwoHooksAreFlagged() throws {
        try claudeHook("/Users/someone/Downloads/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        let tool = opened(.agents)
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Claude Code hook · Needs update"))
        XCTAssertEqual(button(tree, Pages.Block.agent(.installHook, .claudeCode))?.title.text(for: "en"), "Update Hook")
        XCTAssertFalse(texts(tree).contains { $0.contains("isn't installed") })

        try write("{\"command\": \"python3 stop_broadcast.py\"}", ".claude/skills/google-home/hooks/hooks.json")
        tree = event(tool, Pages.Block.agent(.installHook, .claudeCode), .tap)
        XCTAssertTrue(texts(tree).contains { $0.hasPrefix("Every reply is spoken twice") })
        let turnOff = Pages.Block.agent(.disableRival, .claudeCode)
        XCTAssertEqual(button(tree, turnOff)?.title.text(for: "en"), "Turn it off")
        tree = event(tool, turnOff, .tap)
        XCTAssertFalse(exists(".claude/skills/google-home/hooks/hooks.json"))
        XCTAssertTrue(exists(".claude/skills/google-home/hooks/hooks.json.disabled-by-homespeaker"))
        XCTAssertFalse(texts(tree).contains { $0.hasPrefix("Every reply is spoken twice") })
    }

    func testWithoutHomeSpeakerALeftoverHookSaysItCannotSpeakAndCanBeRemoved() throws {
        driver.isInstalled = false
        try claudeHook(appProgram)
        let tool = opened(.agents)
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Claude Code hook · Points at HomeSpeaker, which isn't installed — it can't speak"))
        XCTAssertFalse(texts(tree).contains { $0.contains("Needs update") }, "there is nothing to update it to")
        XCTAssertNil(button(tree, Pages.Block.agent(.installHook, .claudeCode)))
        let remove = Pages.Block.agent(.removeHook, .claudeCode)
        XCTAssertEqual(button(tree, remove)?.title.text(for: "en"), "Remove")
        XCTAssertEqual(button(tree, remove)?.enabled, true)
        XCTAssertFalse(texts(tree).contains { $0.contains("--claude-stop-hook") }, "no hook command: there is nothing it could run")

        tree = event(tool, remove, .tap)
        XCTAssertNil(installedHookCommand())
        XCTAssertTrue(texts(tree).contains("Claude Code hook · Not installed"))
        let install = Pages.Block.agent(.installHook, .claudeCode)
        XCTAssertEqual(button(tree, install)?.enabled, false, "a hook needs HomeSpeaker to run")
        XCTAssertTrue(texts(tree).contains("Install HomeSpeaker first: the hook runs it."))
        tree = event(tool, install, .tap)
        XCTAssertNil(installedHookCommand(), "refused, writing nothing")
        XCTAssertTrue(texts(tree).contains("HomeSpeaker is not installed"))
    }

    func testWithoutHomeSpeakerTheInstructionTheRivalAndTheLegacyAgentStillWork() throws {
        driver.isInstalled = false
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini/antigravity-cli"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try write("{\"command\": \"speaker-broadcast\"}", ".claude/skills/google-home/hooks/hooks.json")
        try write("<plist/>", "Library/LaunchAgents/\(AgentIntegration.legacyLaunchAgentLabel).plist")
        let tool = opened(.agents)
        var tree = tool.settingsPage()

        // Antigravity's plugin runs HomeSpeaker too, so it waits for it.
        let installPlugin = Pages.Block.agent(.installHook, .antigravity)
        XCTAssertEqual(button(tree, installPlugin)?.enabled, false, "a plugin needs HomeSpeaker to run")
        tree = event(tool, installPlugin, .tap)
        XCTAssertFalse(exists(".gemini/config/plugins/home-speaker"), "refused, writing nothing")

        tree = event(tool, Pages.Block.agent(.disableRival, .claudeCode), .tap)
        XCTAssertFalse(exists(".claude/skills/google-home/hooks/hooks.json"))
        XCTAssertTrue(texts(tree).contains("Disabled the duplicate hook; replies are announced once now"))

        XCTAssertTrue(texts(tree).contains { $0.hasPrefix("Legacy chat-monitor launch agent") })
        tree = event(tool, Pages.Block.removeLegacyAgent, .tap)
        XCTAssertFalse(exists("Library/LaunchAgents/\(AgentIntegration.legacyLaunchAgentLabel).plist"))
        XCTAssertEqual(bootouts.targets, [AgentIntegration.legacyLaunchAgentTarget], "launchctl asked through the seam, never run")
        XCTAssertTrue(texts(tree).contains("Legacy launch agent removed"))
        XCTAssertFalse(texts(tree).contains { $0.hasPrefix("Legacy chat-monitor launch agent") })
        XCTAssertNil(content(tree, Pages.Block.removeLegacyAgent))
    }

    /// Antigravity and OpenCode get the same Install, Update and Remove as
    /// Claude Code, each writing its own plugin, pointed at HomeSpeaker.
    func testWithHomeSpeakerEachAgentsPluginIsInstalledUpdatedAndRemoved() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".gemini/config"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)
        let tool = opened(.agents)
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Antigravity plugin · Not installed"))
        XCTAssertTrue(texts(tree).contains("OpenCode plugin · Not installed"))
        XCTAssertTrue(texts(tree).contains { $0.contains("~/.gemini/config/plugins/home-speaker") }, "says where it goes")
        XCTAssertTrue(texts(tree).contains { $0.contains("~/.config/opencode/plugins/home-speaker.ts") })

        tree = event(tool, Pages.Block.agent(.installHook, .antigravity), .tap)
        let hooks = try XCTUnwrap(read(".gemini/config/plugins/home-speaker/hooks.json"))
        XCTAssertTrue(hooks.contains("\"\\\"\(appProgram)\\\" --antigravity-hook\""), hooks)
        XCTAssertTrue(exists(".gemini/config/plugins/home-speaker/plugin.json"))
        XCTAssertTrue(texts(tree).contains("Antigravity plugin · Installed"))
        XCTAssertTrue(texts(tree).contains("Antigravity plugin installed"))

        tree = event(tool, Pages.Block.agent(.installHook, .opencode), .tap)
        let plugin = try XCTUnwrap(read(".config/opencode/plugins/home-speaker.ts"))
        XCTAssertTrue(plugin.contains("// Command: \"\(appProgram)\" --opencode-hook"), "pointed at HomeSpeaker, never bin/tool")
        XCTAssertTrue(texts(tree).contains("OpenCode plugin · Installed"))

        // An older plugin of the same program is one to update.
        try write("// Command: \"\(appProgram)\" --opencode-hook\n// an older plugin\n", ".config/opencode/plugins/home-speaker.ts")
        tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("OpenCode plugin · Needs update"))
        XCTAssertEqual(button(tree, Pages.Block.agent(.installHook, .opencode))?.title.text(for: "en"), "Update Hook")
        tree = event(tool, Pages.Block.agent(.installHook, .opencode), .tap)
        XCTAssertTrue(texts(tree).contains("OpenCode plugin · Installed"))

        tree = event(tool, Pages.Block.agent(.removeHook, .antigravity), .tap)
        XCTAssertFalse(exists(".gemini/config/plugins/home-speaker"))
        XCTAssertTrue(texts(tree).contains("Antigravity plugin removed"))
        tree = event(tool, Pages.Block.agent(.removeHook, .opencode), .tap)
        XCTAssertFalse(exists(".config/opencode/plugins/home-speaker.ts"))
        XCTAssertTrue(texts(tree).contains("OpenCode plugin · Not installed"))
    }

    func testTheHookSectionNamesTheAgentsOwnInstructionFile() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try write("Use speaker-broadcast.\n", ".claude/CLAUDE.md")
        let tool = opened(.agents)
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.hasPrefix("Already announcing: your ~/.claude/CLAUDE.md tells Claude Code") })
        event(tool, Pages.Block.agent(.installHook, .claudeCode), .tap)
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.hasPrefix("Your ~/.claude/CLAUDE.md also tells Claude Code") })
    }

    func testAnAgentNotOnThisMacHasNothingToDo() {
        let tool = opened(.agents)
        let tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Claude Code hook · Not installed on this Mac. Nothing to do here."))
        XCTAssertTrue(texts(tree).contains("Antigravity plugin · Not installed on this Mac. Nothing to do here."))
        XCTAssertTrue(texts(tree).contains("OpenCode plugin · Not installed on this Mac. Nothing to do here."))
        XCTAssertFalse(tree.blocks.contains { $0.id.flatMap(Pages.Block.agentAction) != nil }, "no agent buttons")
    }

    // MARK: - Each agent's switch, in Settings

    func testAIAgentsHasEachAgentsSwitchFirst() {
        let tool = opened(.agents)
        let page = tool.settingsPage()
        guard let heading = texts(page).firstIndex(of: "Announcements") else { return XCTFail("no Announcements") }
        XCTAssertEqual(heading, texts(page).firstIndex { $0 == "Announcements" || $0 == "Claude Code" || $0 == "Antigravity" || $0 == "OpenCode" },
                       "above the agents' hooks")
        guard case .toggle(let claude)? = content(page, Pages.Block.claudeCodeEnabled),
              case .toggle(let antigravity)? = content(page, Pages.Block.antigravityEnabled),
              case .toggle(let opencode)? = content(page, Pages.Block.opencodeEnabled) else { return XCTFail("no switches") }
        XCTAssertEqual(claude.title.text(for: "en"), "Announce Claude Code replies")
        XCTAssertEqual(antigravity.title.text(for: "en"), "Announce Antigravity replies")
        XCTAssertEqual(opencode.title.text(for: "en"), "Announce OpenCode replies")
        XCTAssertEqual(claude.value, true)
        XCTAssertEqual(antigravity.value, true)
        XCTAssertEqual(opencode.value, true)
        XCTAssertTrue(texts(page).contains(Pages.agentSwitchesHelp))
    }

    func testTheAgentSwitchesInSettingsSaveTheFile() {
        let tool = opened(.agents)
        let page = event(tool, Pages.Block.antigravityEnabled, .toggle, .bool(false))
        XCTAssertEqual(store.config?.announces(.antigravity), false)
        XCTAssertEqual(store.config?.announces(.claudeCode), true)
        XCTAssertEqual(store.config?.announces(.opencode), true)
        guard case .toggle(let antigravity)? = content(page, Pages.Block.antigravityEnabled) else { return XCTFail("no switch") }
        XCTAssertEqual(antigravity.value, false, "the redraw shows it")
        event(tool, Pages.Block.opencodeEnabled, .toggle, .bool(false))
        XCTAssertEqual(store.config?.announces(.opencode), false)
        event(tool, Pages.Block.claudeCodeEnabled, .toggle, .bool(false))
        XCTAssertEqual(store.config?.announces(.claudeCode), false)
        let saves = store.saves
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.claudeCodeEnabled, kind: .tap)), .keep, "no value, nothing saved")
        XCTAssertEqual(store.saves, saves)
    }
}
