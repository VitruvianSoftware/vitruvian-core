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

// The extension's pages when the app is installed too (plan Task 14, design
// 7.4): the choice card, the side-by-side summary, the copy, closing the
// app, the quiet card and General's "Which HomeSpeaker" row.
//
// Both sides' files are in a scratch folder: the extension's profile, and an
// app-shaped profile beside it. The app itself is a stand-in that records
// what it is asked; the hooks are a scratch home's `.claude/settings.json`.
// Nothing here quits, switches off or moves this Mac's HomeSpeaker, and no
// message is posted: telling a side its sign-ins changed is recorded.

/// What was done, in order, from any thread.
private final class Order: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ item: String) { lock.withLock { items.append(item) } }
    var all: [String] { lock.withLock { items } }
}

/// A flag read from any thread.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on: Bool
    init(_ on: Bool) { self.on = on }
    var value: Bool {
        get { lock.withLock { on } }
        set { lock.withLock { on = newValue } }
    }
}

/// The app, as the extension closes it: each request is recorded, and
/// answered as an app 1.19 would.
private final class RecordingApp: OtherAppControlling, @unchecked Sendable {
    let order: Order
    let running: Flag
    private let lock = NSLock()
    private var shownVersion: String? = "1.19.0"
    var version: String? {
        get { lock.withLock { shownVersion } }
        set { lock.withLock { shownVersion = newValue } }
    }

    /// Whether it goes when asked to quit.
    let quits = Flag(true)
    /// Whether opening it works.
    let opens = Flag(true)
    private var loginItemAnswer: Result<Void, OtherAppProblem> = .success(())
    var turningOn: Result<Void, OtherAppProblem> {
        get { lock.withLock { loginItemAnswer } }
        set { lock.withLock { loginItemAnswer = newValue } }
    }

    init(order: Order, running: Flag) {
        self.order = order
        self.running = running
    }

    var isRunning: Bool { running.value }

    func quit(timeout: Double) async -> Bool {
        order.add("quit")
        if quits.value { running.value = false }
        return quits.value
    }

    func open() async -> Bool {
        order.add("open")
        return opens.value
    }

    func turnOnLoginItem() async -> Result<Void, OtherAppProblem> {
        order.add("loginItemOn")
        return turningOn
    }

    func turnOffLoginItem() async -> Result<Void, OtherAppProblem> {
        order.add("loginItemOff")
        return .success(())
    }

    func moveToTrash() throws -> URL {
        order.add("trash")
        return URL(fileURLWithPath: "/nonexistent/.Trash/HomeSpeaker.app")
    }
}

/// The extension's own engine, as far as the pages ask: installed, its own
/// program, and the jobs it was asked to run.
private final class OwnDriver: SpeakerDriver {
    let program: URL?
    var isInstalled: Bool { true }
    var jobs: [Job] = []
    init(program: URL) { self.program = program }
    func run(_ job: Job, then: @escaping @Sendable (JobResult) -> Void) { jobs.append(job) }
}

@MainActor
final class DoorPagesTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Account = HomeSpeakerToolTests.Account

    private var root: URL!
    private var home: URL!
    private var mine: HomeSpeakerProfile!
    private var app: HomeSpeakerProfile!
    private var door: DoorFile!
    private var link: Link!
    private var account: Account!
    private var order: Order!
    private var appInstalled: Flag!
    private var appRunning: Flag!
    private var otherApp: RecordingApp!
    private var driver: OwnDriver!
    private var told: [HomeSpeakerProfile.Door] = []
    private var asked: [ChatMonitorAction] = []
    private var ownerRunning = true
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    /// Where the app's program is found now; nil: nowhere.
    private var appFound: URL?
    /// What the copy throws instead of copying; nil: it copies.
    private var copyStops: DoorCopyPartial?

    private var appProgram: URL { root.appendingPathComponent("Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker") }
    private var extensionProgram: URL { root.appendingPathComponent("Tools/dev.vitruvian.homespeaker/bin/tool") }

    /// Made-up sign-ins: nothing on a page may ever show them.
    static let appRefresh = "app-refresh-made-up-1" // gitleaks:allow (made-up test token)
    static let appAccess = "app-access-made-up-2" // gitleaks:allow (made-up test token)
    static let slackToken = "xoxp-made-up-3" // gitleaks:allow (made-up test token)
    static let clientSecret = "client-secret-made-up-4" // gitleaks:allow (made-up test token)
    static let extensionRefresh = "extension-refresh-made-up-5" // gitleaks:allow (made-up test token)

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("homespeaker-door-pages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        self.root = root
        home = root.appendingPathComponent("home")
        let prefix = "test.\(UUID().uuidString).homespeaker"
        mine = .extension(dataFolder: root.appendingPathComponent("ToolData/dev.vitruvian.homespeaker"),
                          toolFolder: root.appendingPathComponent("Tools/dev.vitruvian.homespeaker"), messagePrefix: prefix)
        let gemini = root.appendingPathComponent("app/.gemini")
        app = HomeSpeakerProfile(
            door: .app, settingsURL: gemini.appendingPathComponent("speaker_broadcast.json"),
            historyURL: gemini.appendingPathComponent("speaker_history.json"),
            secretsURL: root.appendingPathComponent("app/secrets.json"), messagePrefix: "test.app.\(prefix)",
            liveLockURL: nil, toolFolder: nil)
        for url in [mine.settingsURL, mine.secretsURL, mine.historyURL, app.settingsURL, app.secretsURL, app.historyURL] {
            XCTAssertTrue(url.path.hasPrefix(root.path + "/"), "\(url.path) is outside the scratch folder")
        }
        door = DoorFile(url: DoorFile.defaultURL(home: home))
        link = Link()
        account = Account()
        order = Order()
        appInstalled = Flag(true)
        appRunning = Flag(true)
        otherApp = RecordingApp(order: order, running: appRunning)
        driver = OwnDriver(program: extensionProgram)
        told = []
        asked = []
        ownerRunning = true
        now = Date(timeIntervalSince1970: 1_800_000_000)
        appFound = appProgram
        copyStops = nil

        // The app is set up: signed in, with a speaker. The extension is new.
        let appConfig = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "h1", structureName: "Lake House",
                                      targets: ["kitchen": SpeakerDevice(id: "d1", type: "SPEAKER", name: "Kitchen")])
        try SpeakerConfigFile(url: app.settingsURL).write(appConfig)
        try SecretStore(fileURL: app.secretsURL).save(Secrets(
            google: GoogleCredentials(clientId: "made-up-client", clientSecret: Self.clientSecret, accessToken: Self.appAccess,
                                      refreshToken: Self.appRefresh, expiry: Date().addingTimeInterval(3_600),
                                      scopes: GoogleAuth.identityScopes, userId: "1", email: "app@example.test"),
            slackToken: Self.slackToken))
    }

    private func tool() -> HomeSpeakerTool {
        let check = DoorCheck(file: door, appInstalled: { [appInstalled] in appInstalled!.value }, fileExists: { _ in false })
        let order = self.order!
        return HomeSpeakerTool(parts: .init(
            link: link, store: FileConfigStore(url: mine.settingsURL), driver: driver,
            later: { work in DispatchQueue.main.async(execute: work) }, now: { [unowned self] in now },
            account: account, ownerRunning: { [unowned self] in ownerRunning },
            home: home, settingsURL: mine.settingsURL, secretsURL: mine.secretsURL, historyURL: mine.historyURL,
            monitorStatusURL: mine.monitorStatusURL,
            controlChatMonitor: { [unowned self] in asked.append($0) },
            role: { check.role(me: .extension) }, other: otherApp, door: door,
            copy: { [unowned self] from, to in
                order.add("copy")
                if let copyStops { throw copyStops }
                return try DoorCopy.copy(from: from, to: to)
            },
            profile: mine, appProfile: app, appProgram: { [unowned self] in appFound }, repairsHooks: true,
            otherInstalled: { check.appInstalled() },
            credentialsChangedIn: { [unowned self] in told.append($0.door) }))
    }

    // MARK: - Reading a page

    private func ids(_ tree: UITree) -> [String] { tree.blocks.compactMap(\.id) }

    private func words(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            switch block.content {
            case .text(let text): return text.text.text(for: "en")
            case .heading(let heading): return heading.text.text(for: "en")
            case .row(let row): return row.title.text(for: "en") + (row.subtitle.map { " · " + $0.text(for: "en") } ?? "")
            case .button(let button): return button.title.text(for: "en")
            case .toggle(let toggle): return toggle.title.text(for: "en")
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

    private func tap(_ tool: HomeSpeakerTool, _ id: String, island: Bool = true) -> UITree {
        let answer = island ? tool.islandEvent(PanelEvent(block: id, kind: .tap))
            : tool.settingsEvent(PanelEvent(block: id, kind: .tap))
        guard case .page(let tree) = answer else {
            XCTFail("\(id): no page")
            return UITree(blocks: [])
        }
        return tree
    }

    private func flip(_ tool: HomeSpeakerTool, _ id: String, _ isOn: Bool) {
        _ = tool.islandEvent(PanelEvent(block: id, kind: .toggle, value: .bool(isOn)))
    }

    /// Waits for the work the tool handed to the main queue.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<300 where !done() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    private func offersShown(_ tool: HomeSpeakerTool) -> Bool {
        if case .offers? = tool.doorStep { return true }
        return false
    }

    /// The extension picked, the app's settings kept or copied, and the
    /// app closed: the page with the two offers.
    private func chooseTheExtension(_ tool: HomeSpeakerTool, copy: Bool) async -> UITree {
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseExtension)
        _ = tap(tool, copy ? Pages.Block.doorCopy : Pages.Block.doorKeep)
        await settle { offersShown(tool) }
        return tool.islandPage()
    }

    /// Done, with the offers as they are.
    private func done(_ tool: HomeSpeakerTool) async {
        _ = tap(tool, Pages.Block.doorDone)
        await settle { tool.doorStep == nil }
    }

    // MARK: - The card

    func testTheCardShowsWhileWaiting() throws {
        let tool = tool()
        let island = tool.islandPage()
        let card = Array(words(island).prefix(4))
        XCTAssertEqual(card, [Pages.DoorWords.heading, Pages.DoorWords.body, "Use the extension", "Use the app"])
        XCTAssertEqual(Pages.DoorWords.heading, "HomeSpeaker is installed twice")
        XCTAssertEqual(Pages.DoorWords.body,
                       "The HomeSpeaker app and the Vitruvian extension can both speak on your speakers. Use one, so nothing is said twice.")
        XCTAssertEqual(Array(ids(island).prefix(2)), [Pages.Block.doorUseExtension, Pages.Block.doorUseApp], "at the top")
        XCTAssertTrue(ids(island).contains(Pages.Block.broadcasting), "a waiting extension still does what is asked by hand")

        let general = tool.settingsPage()
        XCTAssertEqual(Array(ids(general).prefix(3)), [Pages.Block.section, Pages.Block.doorUseExtension, Pages.Block.doorUseApp],
                       "at the top of General")
        XCTAssertFalse(words(general).contains(Pages.DoorWords.which), "nobody has chosen: nothing to switch")
        _ = tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string(Pages.Section.speakers.rawValue)))
        XCTAssertFalse(ids(tool.settingsPage()).contains(Pages.Block.doorUseExtension), "General only")
    }

    func testTheQuietCardReplacesTheIsland() throws {
        try door.update { $0.chosen = .app }
        let tool = tool()
        let island = tool.islandPage()
        XCTAssertEqual(ids(island), [Pages.Block.doorUseThis], "the card is all there is")
        XCTAssertEqual(words(island), ["The HomeSpeaker app is in use, so this one stays quiet.", "Use this one instead", Pages.moreSettings])

        let general = tool.settingsPage()
        let which = try XCTUnwrap(words(general).firstIndex(of: "Which HomeSpeaker"))
        XCTAssertEqual(Array(words(general)[which...].prefix(4)),
                       ["Which HomeSpeaker", "This Mac uses the app.", "Use the extension instead", "Copy settings from the extension"])
        XCTAssertNotNil(button(general, Pages.Block.doorSwitch))
        XCTAssertNotNil(button(general, Pages.Block.doorCopyAgain))

        // Use this one instead: the same compare step, choosing this one.
        let compare = tap(tool, Pages.Block.doorUseThis)
        XCTAssertNotNil(button(compare, Pages.Block.doorCopy))
        XCTAssertEqual(button(compare, Pages.Block.doorCopy)?.title.text(for: "en"), "Copy from the app")
    }

    func testNoCardWhenAlone() throws {
        appInstalled.value = false
        let tool = tool()
        for tree in [tool.islandPage(), tool.settingsPage()] {
            XCTAssertFalse(ids(tree).contains { $0.hasPrefix("door.") }, "\(ids(tree))")
            XCTAssertFalse(words(tree).contains(Pages.DoorWords.heading))
            XCTAssertFalse(words(tree).contains(Pages.DoorWords.which))
        }
        // A choice of the app left behind by an app that is gone: still alone.
        try door.update { $0.chosen = .app }
        XCTAssertFalse(ids(tool.islandPage()).contains(Pages.Block.doorUseThis))
        XCTAssertTrue(ids(tool.islandPage()).contains(Pages.Block.broadcasting))
    }

    // MARK: - Step 2: side by side

    func testTheSummaryNamesNoToken() throws {
        try SecretStore(fileURL: mine.secretsURL).save(Secrets(google: GoogleCredentials(
            clientId: "made-up-client", clientSecret: Self.clientSecret, accessToken: "x",
            refreshToken: Self.extensionRefresh, expiry: Date(), scopes: [], userId: "2", email: "ext@example.test")))
        let tool = tool()
        _ = tool.islandPage()
        let island = tap(tool, Pages.Block.doorUseExtension)
        let json = String(decoding: try JSONEncoder().encode(island), as: UTF8.self)
        for token in [Self.appRefresh, Self.appAccess, Self.slackToken, Self.clientSecret, Self.extensionRefresh] {
            XCTAssertFalse(json.contains(token), "the page shows a token")
        }
        XCTAssertTrue(words(island).contains("Google Home · App: Signed in as app@example.test · Extension: Signed in as ext@example.test"),
                      "\(words(island))")
        XCTAssertTrue(words(island).contains("Slack · App: Token saved · Extension: No token"))
        XCTAssertTrue(words(island).contains("Speakers · App: 1, default Kitchen · Extension: None"))
        XCTAssertTrue(words(island).contains(DoorCopy.copyNote))
        let settings = tool.settingsPage()
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(settings), as: UTF8.self).contains(Self.appRefresh))
    }

    func testTheSuggestedButtonIsFirst() throws {
        // The extension is not set up and the app is: copy is suggested.
        var tool = self.tool()
        _ = tool.islandPage()
        var page = tap(tool, Pages.Block.doorUseExtension)
        var buttons = ids(page).filter { [Pages.Block.doorCopy, Pages.Block.doorKeep].contains($0) }
        XCTAssertEqual(buttons, [Pages.Block.doorCopy, Pages.Block.doorKeep])
        XCTAssertEqual(button(page, Pages.Block.doorCopy)?.style, .prominent)
        XCTAssertNotEqual(button(page, Pages.Block.doorKeep)?.style, .prominent)
        XCTAssertEqual(button(page, Pages.Block.doorKeep)?.title.text(for: "en"), "Keep what this one has")

        // Choosing the app, which is set up: keep is suggested, and the copy
        // would come from the extension.
        tool = self.tool()
        _ = tool.islandPage()
        page = tap(tool, Pages.Block.doorUseApp)
        buttons = ids(page).filter { [Pages.Block.doorCopy, Pages.Block.doorKeep].contains($0) }
        XCTAssertEqual(buttons, [Pages.Block.doorKeep, Pages.Block.doorCopy])
        XCTAssertEqual(button(page, Pages.Block.doorKeep)?.style, .prominent)
        XCTAssertEqual(button(page, Pages.Block.doorCopy)?.title.text(for: "en"), "Copy from the extension")
    }

    func testCopyingFromASideWithNoSignInsWarnsFirst() throws {
        try SecretStore(fileURL: mine.secretsURL).save(Secrets(slackToken: Self.slackToken))
        let tool = tool()
        _ = tool.islandPage()
        // Choosing the app and copying from the extension: the extension has a sign-in.
        XCTAssertFalse(words(tap(tool, Pages.Block.doorUseApp)).contains { $0.contains("has no sign-ins") })
        try SecretStore(fileURL: app.secretsURL).save(Secrets())
        let fresh = self.tool()
        _ = fresh.islandPage()
        let page = tap(fresh, Pages.Block.doorUseExtension)
        let warning = "The app has no sign-ins, so copying from it signs the extension out."
        let at = try XCTUnwrap(words(page).firstIndex(of: warning), "\(words(page))")
        let copy = try XCTUnwrap(words(page).firstIndex(of: "Copy from the app"))
        XCTAssertLessThan(at, copy, "said before the button")
    }

    // MARK: - Step 3: closing the app

    func testCopyThenQuitThenOffer() async throws {
        let tool = tool()
        let page = await chooseTheExtension(tool, copy: true)
        XCTAssertEqual(order.all, ["copy", "quit"], "the copy reads the app's files while it is still the one writing them")
        XCTAssertEqual(SpeakerConfigFile(url: mine.settingsURL).read(), SpeakerConfigFile(url: app.settingsURL).read(),
                       "the app's settings came across")
        XCTAssertEqual(door.read()?.chosen, .extension)
        XCTAssertEqual(Array(words(page).prefix(2)), [Pages.DoorWords.heading, "The app has quit."])
        XCTAssertEqual(toggle(page, Pages.Block.doorLoginItem)?.title.text(for: "en"), "Turn off the app's Open at Login")
        XCTAssertEqual(toggle(page, Pages.Block.doorLoginItem)?.value, true)
        XCTAssertEqual(toggle(page, Pages.Block.doorTrash)?.title.text(for: "en"), "Move HomeSpeaker.app to the Trash")
        XCTAssertTrue(words(page).contains(
            "Your phone remote and scripts that call HomeSpeaker.app will stop working until they are pointed at the extension."))
        XCTAssertEqual(button(page, Pages.Block.doorDone)?.title.text(for: "en"), "Done")
        XCTAssertTrue(tool.monitorMayRun, "the app has quit: this side's monitor may run")
    }

    func testKeepingCopiesNothingAndStillClosesTheApp() async throws {
        let tool = tool()
        _ = await chooseTheExtension(tool, copy: false)
        XCTAssertEqual(order.all, ["quit"])
        XCTAssertEqual(SpeakerConfigFile(url: mine.settingsURL).read(), .missing)
        XCTAssertEqual(told, [], "nothing copied, nobody told")
    }

    func testTrashNeedsItsOwnTick() async throws {
        var tool = self.tool()
        var page = await chooseTheExtension(tool, copy: false)
        XCTAssertEqual(toggle(page, Pages.Block.doorTrash)?.value, false, "not ticked by default")
        _ = tap(tool, Pages.Block.doorDone)
        await settle { tool.doorStep == nil }
        XCTAssertEqual(order.all, ["quit", "loginItemOff"], "the login item only")
        XCTAssertTrue(words(tool.islandPage()).contains(Pages.DoorWords.loginItemOff))

        try door.update { $0.chosen = nil }
        appRunning.value = true
        tool = self.tool()
        page = await chooseTheExtension(tool, copy: false)
        flip(tool, Pages.Block.doorTrash, true)
        flip(tool, Pages.Block.doorLoginItem, false)
        _ = tap(tool, Pages.Block.doorDone)
        await settle { tool.doorStep == nil }
        XCTAssertEqual(Array(order.all.suffix(2)), ["quit", "trash"], "ticked: moved; unticked: left on")
        XCTAssertTrue(words(tool.islandPage()).contains(Pages.DoorWords.inTheTrash))
    }

    func testAnOldAppMustLoseItsLoginItem() async throws {
        otherApp.version = "1.18.0"
        let tool = tool()
        let page = await chooseTheExtension(tool, copy: false)
        XCTAssertTrue(words(page).contains(
            "This copy of the app is older than 1.19 and will take the Claude Code hook back if it is opened again. Move it to the Trash, or update it."))
        XCTAssertEqual(toggle(page, Pages.Block.doorLoginItem)?.enabled, false, "not optional for an old app")
        flip(tool, Pages.Block.doorLoginItem, false)
        XCTAssertEqual(toggle(tool.islandPage(), Pages.Block.doorLoginItem)?.value, true)
    }

    // MARK: - The copy tells the side that took it

    func testACopyTellsTheDestination() async throws {
        let tool = tool()
        _ = await chooseTheExtension(tool, copy: true)
        XCTAssertEqual(told, [.extension])
        await done(tool)

        // Later, from General: copy again, from the app into the extension.
        _ = tool.settingsPage()
        _ = tap(tool, Pages.Block.doorCopyAgain, island: false)
        _ = tap(tool, Pages.Block.doorCopy, island: false)
        XCTAssertEqual(told, [.extension, .extension])
        XCTAssertEqual(door.read()?.chosen, .extension, "a copy again changes no choice")
    }

    func testAFailedCopyChangesNothing() throws {
        try Data("{ not json".utf8).write(to: app.settingsURL)
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseExtension)
        let page = tap(tool, Pages.Block.doorCopy)
        XCTAssertTrue(words(page).contains { $0.contains(app.settingsURL.path) }, "it says which file: \(words(page))")
        XCTAssertNil(door.read()?.chosen, "nothing chosen")
        XCTAssertEqual(told, [])
        XCTAssertFalse(order.all.contains("quit"))
    }

    // MARK: - The hook follows the choice

    func testTheSwitchRepointsTheHook() async throws {
        let settings = home.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let own: [String: Any] = ["type": "command", "command": "echo mine"]
        let ours: [String: Any] = ["type": "command", "command": AgentIntegration.hookCommand(executable: appProgram.path), "timeout": 10]
        let groups: [[String: Any]] = [["hooks": [own]], ["hooks": [ours]]]
        let hooks: [String: Any] = ["hooks": ["Stop": groups]]
        try JSONSerialization.data(withJSONObject: hooks).write(to: settings)
        func installed() throws -> String? {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any] ?? [:]
            return AgentIntegration.installedHookCommand(in: json)
        }
        func stillMine() throws -> Bool { try String(decoding: Data(contentsOf: settings), as: UTF8.self).contains("echo mine") }

        let tool = tool()
        _ = await chooseTheExtension(tool, copy: false)
        XCTAssertEqual(try installed(), AgentIntegration.hookCommand(executable: extensionProgram.path))
        XCTAssertTrue(try stillMine(), "a hook of the person's own is left")
        await done(tool)

        // Switch back to the app, from General.
        _ = tool.settingsPage()
        _ = tap(tool, Pages.Block.doorSwitch, island: false)
        _ = tap(tool, Pages.Block.doorKeep, island: false)
        XCTAssertEqual(door.read()?.chosen, .app)
        XCTAssertEqual(try installed(), AgentIntegration.hookCommand(executable: appProgram.path))
        XCTAssertTrue(try stillMine())
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".gemini/antigravity-cli/settings.json").path),
                       "an agent with no HomeSpeaker hook gets none")
        // The app was quit when the extension was picked: picking it again
        // opens it, so something reads chat (review round 1, critical 2).
        await settle { tool.doorStep == nil }
        XCTAssertEqual(Array(order.all.suffix(2)), ["open", "loginItemOn"])
        XCTAssertEqual(ids(tool.islandPage()), [Pages.Block.doorUseThis], "and this side goes quiet")
    }

    func testNoHookIsAddedWhereThereWasNone() async throws {
        let tool = tool()
        _ = await chooseTheExtension(tool, copy: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/settings.json").path))
    }

    // MARK: - The chat monitor's buttons

    func testStartAndStopShowOnlyWhileThisSideIsActive() throws {
        var config = SpeakerConfig(enabled: true)
        config.effectiveChatMonitor.slackEnabled = true
        try SpeakerConfigFile(url: mine.settingsURL).write(config)
        let tool = tool()
        _ = tool.settingsPage()
        func monitorPage() -> UITree {
            guard case .page(let tree) = tool.settingsEvent(PanelEvent(
                block: Pages.Block.section, kind: .tap, value: .string(Pages.Section.monitor.rawValue))) else { return UITree(blocks: []) }
            return tree
        }
        var page = monitorPage()
        XCTAssertFalse(ids(page).contains(Pages.Block.startChatMonitor), "waiting: nothing to start")
        XCTAssertTrue(words(page).contains(HomeSpeakerTool.pickFirst), "and it says why")
        try door.update { $0.chosen = .app }
        page = monitorPage()
        XCTAssertFalse(ids(page).contains(Pages.Block.startChatMonitor), "quiet: the app's monitor runs")
        XCTAssertTrue(words(page).contains("The HomeSpeaker app is in use, so this one stays quiet."))
        try door.update { $0.chosen = .extension }
        page = monitorPage()
        XCTAssertTrue(ids(page).contains(Pages.Block.startChatMonitor), "active: Start")
        XCTAssertFalse(words(page).contains { $0.hasPrefix("Open HomeSpeaker") })
    }

    // MARK: - Review round 1

    /// Slack on in the extension's own settings, so a monitor allowed to
    /// run is asked to start.
    private func slackOnHere() throws {
        var config = SpeakerConfig(enabled: true)
        config.effectiveChatMonitor.slackEnabled = true
        try SpeakerConfigFile(url: mine.settingsURL).write(config)
    }

    private func hooksFile() -> URL { home.appendingPathComponent(".claude/settings.json") }

    /// A Claude Code settings file whose HomeSpeaker hook runs `program`.
    private func hook(at program: URL) throws {
        let ours: [String: Any] = ["type": "command", "command": AgentIntegration.hookCommand(executable: program.path), "timeout": 10]
        let settings: [String: Any] = ["hooks": ["Stop": [["hooks": [ours]]] as [[String: Any]]]]
        try FileManager.default.createDirectory(at: hooksFile().deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: hooksFile())
    }

    private func installedHook() throws -> String? {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile())) as? [String: Any] ?? [:]
        return AgentIntegration.installedHookCommand(in: json)
    }

    // Critical 1: an app older than 1.19 that does not quit.

    func testAnOldAppThatDoesNotQuitHoldsTheMonitorBack() async throws {
        try slackOnHere()
        otherApp.version = "1.18.0"
        otherApp.quits.value = false
        let tool = tool()
        let page = await chooseTheExtension(tool, copy: false)
        XCTAssertTrue(words(page).contains(Pages.DoorWords.didNotQuit))
        XCTAssertTrue(words(page).contains(OtherAppPlan.Step.oldAppWarning.text))
        XCTAssertEqual(button(page, Pages.Block.doorQuitAgain)?.title.text(for: "en"), "Quit the app")
        XCTAssertEqual(toggle(page, Pages.Block.doorTrash)?.enabled, false, "a running app is never moved")

        now += 60
        tool.refreshRole()
        XCTAssertFalse(asked.contains(.start), "the old app still reads chat: this side's monitor waits, past five seconds")
        XCTAssertFalse(tool.monitorMayRun)

        // Done, with the app still running: the island keeps saying so.
        await done(tool)
        now += 60
        tool.refreshRole()
        XCTAssertFalse(asked.contains(.start))
        let island = tool.islandPage()
        XCTAssertEqual(ids(island).first, Pages.Block.doorQuitAgain)
        XCTAssertTrue(words(island).contains(OtherAppPlan.Step.oldAppWarning.text))

        // Asked again, it goes: now this side reads chat.
        otherApp.quits.value = true
        _ = tap(tool, Pages.Block.doorQuitAgain)
        await settle { asked.contains(.start) }
        XCTAssertEqual(asked, [.start])
        XCTAssertFalse(ids(tool.islandPage()).contains(Pages.Block.doorQuitAgain))
    }

    /// An app running but not found (a test's `HOMESPEAKER_PROGRAM=""`
    /// beside a real one on this Mac): no line, no button, no quit.
    func testAnAppThatIsNotFoundIsNeverOfferedToQuit() throws {
        appInstalled.value = false
        appFound = nil
        otherApp.version = nil
        let tool = tool()
        tool.start()
        let island = tool.islandPage()
        XCTAssertFalse(ids(island).contains(Pages.Block.doorQuitAgain))
        XCTAssertFalse(words(island).contains(OtherAppPlan.Step.oldAppWarning.text))
        _ = tap(tool, Pages.Block.doorQuitAgain)
        XCTAssertEqual(order.all, [], "nothing asked to quit")
        now += 5
        tool.refreshRole()
        XCTAssertTrue(tool.monitorMayRun, "nothing found to wait for past the usual five seconds")
    }

    func testANewAppThatDoesNotQuitIsGivenFiveSeconds() async throws {
        try slackOnHere()
        otherApp.quits.value = false
        let tool = tool()
        _ = await chooseTheExtension(tool, copy: false)
        XCTAssertFalse(asked.contains(.start))
        now += 5
        tool.refreshRole()
        XCTAssertEqual(asked, [.start], "a 1.19 app hears the choice and goes quiet by itself")
    }

    // Critical 2: picking the app opens it.

    func testPickingTheAppOpensItWhenItIsNotRunning() async throws {
        appRunning.value = false
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseApp)
        _ = tap(tool, Pages.Block.doorKeep)
        await settle { tool.doorStep == nil }
        XCTAssertEqual(order.all, ["open", "loginItemOn"], "opened, and its Open at Login turned back on")
        XCTAssertEqual(door.read()?.chosen, .app)
        var island = tool.islandPage()
        XCTAssertEqual(ids(island), [Pages.Block.doorUseThis])
        XCTAssertTrue(words(island).contains("The HomeSpeaker app is starting, so this one stays quiet."), "\(words(island))")
        XCTAssertTrue(words(island).contains(Pages.DoorWords.loginItemOn))

        appRunning.value = true
        tool.refreshRole()
        island = tool.islandPage()
        XCTAssertTrue(words(island).contains("The HomeSpeaker app is in use, so this one stays quiet."))
    }

    func testAnAppThatCannotBeOpenedOrSwitchedOnSaysSo() async throws {
        appRunning.value = false
        otherApp.opens.value = false
        otherApp.turningOn = .failure(OtherAppProblem(
            "This copy of the app is too old to turn on its own Open at Login. \(SystemOtherApp.whereToTurnOn)"))
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseApp)
        _ = tap(tool, Pages.Block.doorKeep)
        await settle { tool.doorStep == nil }
        let island = tool.islandPage()
        XCTAssertTrue(words(island).contains(Pages.DoorWords.couldNotOpen))
        XCTAssertTrue(words(island).contains { $0.hasSuffix(SystemOtherApp.whereToTurnOn) })
        XCTAssertFalse(words(island).contains(Pages.DoorWords.starting), "not opened: not starting")
    }

    func testPickingARunningAppOpensNothing() async throws {
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseApp)
        _ = tap(tool, Pages.Block.doorKeep)
        await settle { tool.doorStep == nil }
        XCTAssertEqual(order.all, [])
        XCTAssertTrue(words(tool.islandPage()).contains("The HomeSpeaker app is in use, so this one stays quiet."))
    }

    func testTheAppIsNeverOfferedWhenItIsNotInstalled() throws {
        appInstalled.value = false
        let tool = tool()
        XCTAssertFalse(ids(tool.islandPage()).contains(Pages.Block.doorUseApp))
        XCTAssertFalse(ids(tool.settingsPage()).contains(Pages.Block.doorSwitch))
        _ = tap(tool, Pages.Block.doorUseApp)
        XCTAssertNil(tool.doorStep, "a stale tap starts nothing")
        XCTAssertNil(door.read()?.chosen)
    }

    func testACopyIntoTheAppTellsTheApp() async throws {
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseApp)
        _ = tap(tool, Pages.Block.doorCopy)
        await settle { tool.doorStep == nil }
        XCTAssertEqual(told, [.app], "under the app's own names")
    }

    // Important 1: Back, and a choice made elsewhere.

    func testBackLeavesEverythingAsItWas() throws {
        let tool = tool()
        _ = tool.islandPage()
        let compare = tap(tool, Pages.Block.doorUseExtension)
        XCTAssertEqual(button(compare, Pages.Block.doorBack)?.title.text(for: "en"), "Back")
        let back = tap(tool, Pages.Block.doorBack)
        XCTAssertNil(tool.doorStep)
        XCTAssertEqual(Array(ids(back).prefix(2)), [Pages.Block.doorUseExtension, Pages.Block.doorUseApp], "step 1 again")
        XCTAssertNil(door.read()?.chosen)
        XCTAssertEqual(order.all, [], "nothing copied, nothing quit")
    }

    func testAChoiceMadeInTheAppIsNeverOverridden() async throws {
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseExtension)
        try door.update { $0.chosen = .app }
        let page = tap(tool, Pages.Block.doorKeep)
        XCTAssertEqual(door.read()?.chosen, .app, "the app's choice stands")
        XCTAssertEqual(order.all, [], "nothing copied, nothing quit")
        XCTAssertNil(tool.doorStep)
        XCTAssertEqual(ids(page), [Pages.Block.doorUseThis], "the page shows what is")
        XCTAssertTrue(words(page).contains(Pages.DoorWords.choiceChanged))

        // Seen on the five-second tick, before any tap: the step goes too.
        try door.update { $0.chosen = nil }
        let other = self.tool()
        _ = other.islandPage()
        other.refreshRole()
        _ = tap(other, Pages.Block.doorUseExtension)
        try door.update { $0.chosen = .app }
        other.refreshRole()
        XCTAssertNil(other.doorStep)
    }

    // Important 2: the app's program, found at the switch.

    func testTheAppMustBeFoundToBePicked() throws {
        try hook(at: extensionProgram)
        appFound = nil
        let tool = tool()
        _ = tool.islandPage()
        var page = tap(tool, Pages.Block.doorUseApp)
        XCTAssertNil(tool.doorStep)
        XCTAssertTrue(words(page).contains(Pages.DoorWords.appNotFound))

        // Found when step 2 began, gone by Keep: nothing changes.
        appFound = appProgram
        _ = tap(tool, Pages.Block.doorUseApp)
        appFound = nil
        page = tap(tool, Pages.Block.doorCopy)
        XCTAssertTrue(words(page).contains(Pages.DoorWords.appNotFound), "\(words(page))")
        XCTAssertNil(door.read()?.chosen)
        XCTAssertEqual(order.all, [], "nothing copied")
        XCTAssertEqual(try installedHook(), AgentIntegration.hookCommand(executable: extensionProgram.path))

        // Only a copy in the Trash: the same.
        appFound = root.appendingPathComponent(".Trash/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        _ = tap(tool, Pages.Block.doorBack)
        page = tap(tool, Pages.Block.doorUseApp)
        XCTAssertTrue(words(page).contains(Pages.DoorWords.appNotFound))
        XCTAssertNil(door.read()?.chosen)
    }

    func testTheHookFollowsTheAppWhereItIsNow() async throws {
        try hook(at: extensionProgram)
        let tool = tool()
        _ = tool.islandPage()
        // Moved since the extension started.
        appFound = root.appendingPathComponent("Elsewhere/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        _ = tap(tool, Pages.Block.doorUseApp)
        _ = tap(tool, Pages.Block.doorKeep)
        XCTAssertEqual(try installedHook(), AgentIntegration.hookCommand(executable: try XCTUnwrap(appFound).path))
    }

    // Important 3: a copy that stops part-way.

    func testACopyThatStopsPartWayTellsTheDestinationAndSaysWhatCameAcross() throws {
        copyStops = DoorCopyPartial(
            copied: ["Settings: copied from the app.", "Sign-ins: copied from the app: Google Home (as app@example.test)."],
            notCopied: ["History: not copied (the disk is full)."], signInsWritten: true)
        let tool = tool()
        _ = tool.islandPage()
        _ = tap(tool, Pages.Block.doorUseExtension)
        let page = tap(tool, Pages.Block.doorCopy)
        XCTAssertEqual(told, [.extension], "its sign-ins were replaced: it is told")
        for line in ["Settings: copied from the app.", "Sign-ins: copied from the app: Google Home (as app@example.test).",
                     "History: not copied (the disk is full)."] {
            XCTAssertTrue(words(page).contains(line), line)
        }
        XCTAssertNil(door.read()?.chosen, "nothing chosen")
        XCTAssertFalse(order.all.contains("quit"))

        // Stopped before the sign-ins: nobody is told.
        told = []
        copyStops = DoorCopyPartial(copied: [], notCopied: ["Settings: not copied (no room).", "Sign-ins: not copied.",
                                                            "History: not copied."], signInsWritten: false)
        _ = tap(tool, Pages.Block.doorCopy)
        XCTAssertEqual(told, [])
    }

    // Important 4: a hook stranded on a program that is gone.

    func testAStrandedHookIsPointedHereWhileThisSideRuns() throws {
        appInstalled.value = false
        try hook(at: root.appendingPathComponent("Gone/HomeSpeaker.app/Contents/MacOS/HomeSpeaker"))
        let tool = tool()
        tool.start()
        XCTAssertEqual(try installedHook(), AgentIntegration.hookCommand(executable: extensionProgram.path))

        // Dragged to the Trash by hand, seen on the tick.
        let trashed = root.appendingPathComponent(".Trash/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        try FileManager.default.createDirectory(at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: trashed)
        try hook(at: trashed)
        tool.refreshRole()
        XCTAssertEqual(try installedHook(), AgentIntegration.hookCommand(executable: extensionProgram.path))
    }

    func testAHookOnAProgramThatIsThereIsLeftAlone() throws {
        appInstalled.value = false
        try FileManager.default.createDirectory(at: appProgram.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: appProgram)
        try hook(at: appProgram)
        let tool = tool()
        tool.start()
        XCTAssertEqual(try installedHook(), AgentIntegration.hookCommand(executable: appProgram.path))
    }

    func testAnOlderPluginPointedHereIsUpdatedOnStart() throws {
        appInstalled.value = false
        let plugin = home.appendingPathComponent(".config/opencode/plugins/home-speaker.ts")
        try FileManager.default.createDirectory(at: plugin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// Command: \"\(extensionProgram.path)\" --opencode-hook\nexport const HomeSpeaker = async () => ({})\n"
            .write(to: plugin, atomically: true, encoding: .utf8)
        let integration = AgentIntegration(home: home, executablePath: extensionProgram.path, bootout: { _ in })
        XCTAssertEqual(integration.status(of: .opencode).hook, .stale("\"\(extensionProgram.path)\" --opencode-hook"))

        let tool = tool()
        tool.start()
        XCTAssertEqual(integration.status(of: .opencode).hook, .installed)
    }

    func testAQuietSideRepairsNoHook() throws {
        try door.update { $0.chosen = .app }
        let gone = root.appendingPathComponent("Gone/HomeSpeaker.app/Contents/MacOS/HomeSpeaker")
        try hook(at: gone)
        let tool = tool()
        tool.start()
        XCTAssertEqual(try installedHook(), AgentIntegration.hookCommand(executable: gone.path))
    }
}
