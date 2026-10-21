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

/// The settings panel's General and Speakers sections, driven as the app
/// drives them: pages opened, blocks tapped, HomeSpeaker's program answering.
final class SettingsTests: XCTestCase {
    typealias Link = HomeSpeakerToolTests.Link
    typealias Store = HomeSpeakerToolTests.Store
    typealias Driver = HomeSpeakerToolTests.Driver
    typealias Account = HomeSpeakerToolTests.Account

    private var link: Link!
    private var store: Store!
    private var driver: Driver!
    private var account: Account!
    private var voices: [LocalVoice] = []
    private var later: @Sendable (@escaping @Sendable () -> Void) -> Void = { $0() }
    private var previewVoice: @Sendable (String) async throws -> Void = { _ in }

    private let ava = LocalVoice(id: "com.apple.voice.premium.en-US.Ava", name: "Ava", language: "en-US", quality: .premium)
    private let daniel = LocalVoice(id: "com.apple.voice.compact.en-GB.Daniel", name: "Daniel", language: "en-GB", quality: .standard)

    override func setUp() {
        link = Link()
        store = Store()
        driver = Driver()
        account = Account()
        voices = [ava, daniel]
        store.config = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "h2", structureName: "City Flat",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen"),
                                               "office": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office")])
    }

    private func tool() -> HomeSpeakerTool {
        let voices = self.voices
        return HomeSpeakerTool(parts: .init(link: link, store: store, driver: driver, later: later, account: account,
                                            voices: { voices }, previewVoice: previewVoice,
                                            historyURL: HomeSpeakerToolTests.noHistory))
    }

    /// Settings opened.
    private func opened(choice: Bool = false) -> HomeSpeakerTool {
        link.features = choice ? [.choice] : []
        let tool = tool()
        _ = tool.settingsPage()
        return tool
    }

    private func page(_ answer: PanelAnswer, file: StaticString = #filePath, line: UInt = #line) -> UITree {
        guard case .page(let tree) = answer else {
            XCTFail("no page: \(answer)", file: file, line: line)
            return UITree(blocks: [])
        }
        return tree
    }

    private func event(_ tool: HomeSpeakerTool, _ block: String, _ kind: UIEventKind, _ value: JSONValue? = nil) -> UITree {
        page(tool.settingsEvent(PanelEvent(block: block, kind: kind, value: value)))
    }

    private func show(_ tool: HomeSpeakerTool, _ section: Pages.Section) -> UITree {
        event(tool, Pages.Block.section, .tap, .string(section.rawValue))
    }

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

    private func toggle(_ tree: UITree, _ id: String) -> ToggleBlock? {
        if case .toggle(let t)? = content(tree, id) { return t }
        return nil
    }

    private func button(_ tree: UITree, _ id: String) -> ButtonBlock? {
        if case .button(let b)? = content(tree, id) { return b }
        return nil
    }

    private func rows(_ tree: UITree, _ id: String) -> [UIListRow] {
        if case .list(let l)? = content(tree, id) { return l.rows }
        return []
    }

    // MARK: - The switcher

    func testTheSectionSwitcherIsAChoiceWhereTheAppDrawsOneAndAListElse() {
        let tool = opened(choice: true)
        var tree = tool.settingsPage()
        guard case .choice(let switcher)? = tree.blocks.first?.content, tree.blocks.first?.id == Pages.Block.section else {
            return XCTFail("the switcher comes first, as a choice")
        }
        XCTAssertEqual(switcher.value, "general")
        XCTAssertEqual(switcher.options.map(\.value), ["general", "speakers", "monitor", "agents", "googleCloud"])
        XCTAssertEqual(switcher.options.map { $0.title.text(for: "en") }, ["General", "Speakers", "Chats", "AI Agents", "Google Cloud"])
        tree = event(tool, Pages.Block.section, .change, .string("speakers"))
        XCTAssertEqual(tool.section, .speakers)
        XCTAssertNotNil(content(tree, Pages.Block.discover))
        XCTAssertNil(content(tree, Pages.Block.broadcasting))
        XCTAssertNotNil(content(tool.settingsPage(), Pages.Block.discover), "the section stays across redraws")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .change, value: .string("chat"))), .keep)

        link.features = []
        tree = show(tool, .general)
        XCTAssertEqual(tool.section, .general)
        XCTAssertEqual(rows(tree, Pages.Block.section).map(\.id), ["general", "speakers", "monitor", "agents", "googleCloud"])
        XCTAssertEqual(rows(tree, Pages.Block.section).map { $0.trailing?.text(for: "en") }, ["✓", nil, nil, nil, nil])
        XCTAssertNotNil(content(tree, Pages.Block.broadcasting))
    }

    // MARK: - Every section on one page, for an app that draws sections

    /// The headings that start a section, in page order.
    private func sectionHeadings(_ tree: UITree) -> [String] {
        tree.blocks.compactMap { block in
            guard case .heading(let heading) = block.content, heading.section == true else { return nil }
            return heading.text.text(for: "en")
        }
    }

    /// Every control on the page that carries help, by id.
    private func helped(_ tree: UITree) -> [String: String] {
        var help: [String: String] = [:]
        for block in tree.blocks {
            guard let id = block.id else { continue }
            switch block.content {
            case .toggle(let toggle): help[id] = toggle.help?.text(for: "en")
            case .field(let field): help[id] = field.help?.text(for: "en")
            case .choice(let choice): help[id] = choice.help?.text(for: "en")
            case .chips(let chips): help[id] = chips.help?.text(for: "en")
            default: break
            }
        }
        return help
    }

    func testWithSectionsEverySectionIsOnOnePage() throws {
        link.features = [.choice, .sections]
        store.config?.effectiveSpeakLocal = true
        let tool = tool()
        let tree = tool.settingsPage()
        XCTAssertNil(content(tree, Pages.Block.section), "no section picker")
        XCTAssertEqual(sectionHeadings(tree), ["General", "Speakers", "Chats", "AI Agents", "Google Cloud"])
        // Each heading, then its section's blocks.
        func at(_ id: String) throws -> Int { try XCTUnwrap(tree.blocks.firstIndex { $0.id == id }, id) }
        func heading(_ title: String) throws -> Int {
            try XCTUnwrap(tree.blocks.firstIndex {
                if case .heading(let heading) = $0.content { return heading.section == true && heading.text.text(for: "en") == title }
                return false
            }, title)
        }
        let order = [try heading("General"), try at(Pages.Block.broadcasting), try at(Pages.Block.quiet),
                     try heading("Speakers"), try at(Pages.Block.voice), try at(Pages.Block.discover),
                     try heading("Chats"), try at(Pages.Block.slackEnabled), try at(Pages.Block.pollInterval),
                     try heading("AI Agents"), try at(Pages.Block.claudeCodeEnabled),
                     try heading("Google Cloud"), try at(Pages.Block.oauthClientId)]
        XCTAssertEqual(order, order.sorted(), "each section under its own heading, in order")
        // Every other heading is a plain one, under its section.
        let headings = tree.blocks.compactMap { block -> HeadingBlock? in
            if case .heading(let heading) = block.content { return heading }
            return nil
        }
        XCTAssertGreaterThan(headings.count, 5)
        XCTAssertEqual(headings.filter { $0.section == true }.count, 5)
        XCTAssertTrue(headings.allSatisfy { $0.section == true || $0.section == nil })
        // What each section reads is read with no section picked: the voices
        // for Speakers, the files for Google Cloud.
        guard case .choice(let voice)? = content(tree, Pages.Block.voice) else { return XCTFail("no voice choice") }
        XCTAssertTrue(voice.options.map(\.value).contains(ava.id))
        XCTAssertTrue(texts(tree).contains { $0.hasPrefix("Settings · /") }, "Files names the settings file")
        XCTAssertEqual(tool.section, .general)

        // A section event from a page drawn before changes nothing.
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .change, value: .string("speakers"))), .keep)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.section, kind: .tap, value: .string("monitor"))), .keep)
        XCTAssertEqual(tool.section, .general)
        XCTAssertEqual(sectionHeadings(tool.settingsPage()).count, 5)
    }

    func testWithoutSectionsThePopUpStays() throws {
        store.config?.effectiveAnnounceVolumeEnabled = true
        store.config?.effectivePauseMedia = true
        store.config?.quietHoursEnabled = true
        for features in [[.choice], [.choice, .chips], []] as [Set<ProtocolFeature>] {
            link.features = features
            let tool = tool()
            var tree = tool.settingsPage()
            XCTAssertEqual(tree.blocks.compactMap(\.id).first, Pages.Block.section, "\(features): the picker first")
            XCTAssertEqual(sectionHeadings(tree), [], "\(features)")
            XCTAssertNotNil(content(tree, Pages.Block.broadcasting))
            XCTAssertNil(content(tree, Pages.Block.discover), "\(features): General alone")
            for section in Pages.Section.allCases {
                tree = show(tool, section)
                XCTAssertEqual(tool.section, section)
                XCTAssertEqual(sectionHeadings(tree), [], "\(features) \(section): no heading starts a section")
                XCTAssertEqual(helped(tree), [:], "\(features) \(section): no help, which this app leaves out")
            }
        }
    }

    func testCaptionsMoveIntoHelpOnlyWithSections() throws {
        store.config?.effectiveAnnounceVolumeEnabled = true
        store.config?.effectivePauseMedia = true
        store.config?.quietHoursEnabled = true
        store.config?.effectiveLocalEngine = .gemini  // casting is offered with Gemini only
        store.config?.effectiveChatMonitor.slackEnabled = true
        let moved: [String: String] = [
            Pages.Block.announceVolume: Pages.announceVolumeHelp,
            Pages.Block.pauseMedia: Pages.pauseMediaHelp,
            Pages.Block.quiet: Pages.quietHoursHelp,
            Pages.Block.slackToken: Pages.slackTokenHelp,
            Pages.Block.homeCastVoice: Pages.homeCastVoiceHelp,
        ]
        link.features = [.choice, .sections]
        let all = tool().settingsPage()
        XCTAssertEqual(helped(all), moved, "these captions, and only these, are their control's help")
        for caption in moved.values {
            XCTAssertFalse(texts(all).contains(caption), "and no longer a caption: \(caption)")
        }

        // Without sections each is the caption it was.
        link.features = [.choice]
        let tool = tool()
        let general = tool.settingsPage()
        let chats = show(tool, .monitor)
        XCTAssertEqual(helped(general), [:])
        XCTAssertEqual(helped(chats), [:])
        for caption in [Pages.announceVolumeHelp, Pages.pauseMediaCaption, Pages.quietHoursHelp] {
            XCTAssertTrue(texts(general).contains(caption), caption)
        }
        XCTAssertTrue(texts(chats).contains(Pages.slackTokenHelp))

        // A report is what happened, not help: it stays a caption.
        var status = Pages.Status()
        status.offersSections = true
        status.config.effectiveAnnounceVolumeEnabled = true
        status.config.effectivePauseMedia = true
        status.mediaPauseReport = "Paused Music for 3 seconds"
        status.volumeRestoreReport = "Kitchen went back to 40 %"
        let reported = Pages.settings(status)
        XCTAssertTrue(texts(reported).contains("Paused Music for 3 seconds"))
        XCTAssertTrue(texts(reported).contains("Kitchen went back to 40 %"))
        XCTAssertEqual(helped(reported)[Pages.Block.pauseMedia], Pages.pauseMediaHelp)
        XCTAssertEqual(helped(reported)[Pages.Block.announceVolume], Pages.announceVolumeHelp)
        // Pause media's help says what the switch does, so it is there
        // while it is off; announce volume's, about the level, is not.
        status.config.effectivePauseMedia = false
        status.config.effectiveAnnounceVolumeEnabled = false
        XCTAssertEqual(helped(Pages.settings(status))[Pages.Block.pauseMedia], Pages.pauseMediaHelp)
        XCTAssertNil(helped(Pages.settings(status))[Pages.Block.announceVolume])
        XCTAssertTrue(Pages.pauseMediaHelp.hasPrefix("Pauses what this Mac is playing"), "about the switch")
        XCTAssertTrue(Pages.pauseMediaHelp.hasSuffix(" Test pauses it for 3 seconds."), "and what Test does, for how long")
        XCTAssertTrue(Pages.pauseMediaCaption.hasPrefix("Test pauses what this Mac is playing for 3 seconds"), "an older app's, as it was")
    }

    /// Signed out with no OAuth client: an app with every section on one
    /// page has Google Cloud below, so General says so and offers no
    /// Set up… button, which would have nowhere to go.
    func testWithSectionsSignInPointsToGoogleCloudBelow() throws {
        account.hasOAuthClient = false
        link.features = [.choice, .sections]
        let tool = tool()
        let tree = tool.settingsPage()
        XCTAssertNil(content(tree, Pages.Block.openGoogleCloud), "no Set up… button")
        XCTAssertTrue(texts(tree).contains(Pages.signInNeedsCloudBelow))
        XCTAssertTrue(Pages.signInNeedsCloudBelow.contains("Google Cloud below"))
        // The caption sits under Sign In, and Google Cloud is further down.
        let caption = try XCTUnwrap(tree.blocks.firstIndex {
            if case .text(let text) = $0.content { return text.text.text(for: "en") == Pages.signInNeedsCloudBelow }
            return false
        })
        let signIn = try XCTUnwrap(tree.blocks.firstIndex { $0.id == Pages.Block.signIn })
        let client = try XCTUnwrap(tree.blocks.firstIndex { $0.id == Pages.Block.oauthClientId })
        XCTAssertLessThan(signIn, caption)
        XCTAssertLessThan(caption, client)

        // An older app keeps the button and its caption.
        link.features = [.choice]
        let old = tool.settingsPage()
        XCTAssertNotNil(content(old, Pages.Block.openGoogleCloud))
        XCTAssertFalse(texts(old).contains(Pages.signInNeedsCloudBelow))
    }

    func testSpeechLengthIsPickedFromAChoiceOrAList() {
        let tool = opened(choice: true)
        guard case .choice(let lengths)? = content(tool.settingsPage(), Pages.Block.speechLength) else { return XCTFail("no choice") }
        XCTAssertEqual(lengths.value, "summary")
        _ = event(tool, Pages.Block.speechLength, .change, .string("full"))
        XCTAssertEqual(store.config?.effectiveSpeechLength, .full)
        link.features = []
        let tree = event(tool, Pages.Block.speechLength, .tap, .string("headline"))
        XCTAssertEqual(store.config?.effectiveSpeechLength, .headline)
        XCTAssertEqual(rows(tree, Pages.Block.speechLength).map { $0.trailing?.text(for: "en") }, ["✓", nil, nil])
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.speechLength, kind: .change, value: .string("epic"))), .keep)
    }

    // MARK: - General

    func testACorruptFileIsShownAndNothingIsSavedOverIt() {
        let tool = opened()
        store.corrupt = "not JSON"
        let tree = event(tool, Pages.Block.broadcasting, .toggle, .bool(false))
        XCTAssertNotNil(tool.configProblem)
        XCTAssertTrue(texts(tree).contains { $0.hasPrefix("The settings file does not read · ") && $0.contains("not JSON") })
        XCTAssertTrue(texts(tree).contains { $0.contains("Nothing is saved until it reads again") })
        XCTAssertEqual(store.saves, 0, "a file that does not read is never written")
        XCTAssertTrue(link.logged.contains { $0.contains("refusing to save") })
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.toggleQuietHours))
        XCTAssertEqual(store.saves, 0)
        // Mended, the banner goes and saving works again.
        store.corrupt = nil
        let mended = event(tool, Pages.Block.broadcasting, .toggle, .bool(false))
        XCTAssertNil(tool.configProblem)
        XCTAssertFalse(texts(mended).contains { $0.contains("does not read") })
        XCTAssertEqual(store.saves, 1)
        XCTAssertEqual(store.config?.enabled, false)
    }

    func testTheBannerShowsOnEverySection() {
        store.corrupt = "permission denied"
        let tool = opened()
        XCTAssertTrue(texts(tool.settingsPage()).contains { $0.contains("does not read") })
        XCTAssertTrue(texts(show(tool, .speakers)).contains { $0.contains("does not read") })
        XCTAssertTrue(texts(show(tool, .monitor)).contains { $0.contains("does not read") })
        XCTAssertTrue(texts(show(tool, .agents)).contains { $0.contains("does not read") })
        XCTAssertTrue(texts(show(tool, .googleCloud)).contains { $0.contains("does not read") })
    }

    func testSignedOutOffersSignInAndTheAntigravityImport() {
        account.hasOAuthClient = false
        account.hasAntigravityTokens = true
        let tool = opened()
        var tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Not signed in · "))
        XCTAssertEqual(button(tree, Pages.Block.signIn)?.title.text(for: "en"), "Sign In…")
        XCTAssertNil(content(tree, Pages.Block.signOut))
        XCTAssertTrue(texts(tree).contains { $0.contains("Google Cloud project of your own") })
        XCTAssertEqual(button(tree, Pages.Block.openGoogleCloud)?.title.text(for: "en"), "Set up…")
        XCTAssertNotNil(button(tree, Pages.Block.importAntigravity))
        XCTAssertTrue(texts(tree).contains { $0.contains("Antigravity connector") })
        account.hasOAuthClient = true
        account.hasAntigravityTokens = false
        tree = tool.settingsPage()
        XCTAssertFalse(texts(tree).contains { $0.contains("Google Cloud project of your own") })
        XCTAssertNil(content(tree, Pages.Block.openGoogleCloud))
        XCTAssertNil(content(tree, Pages.Block.importAntigravity))
    }

    func testSignInRunsHomeSpeakersBrowserSignIn() {
        let tool = opened()
        var tree = event(tool, Pages.Block.signIn, .tap)
        XCTAssertEqual(driver.jobs.last, .signIn(chatOnly: false))
        XCTAssertEqual(tool.setupBusy, .signIn(chatOnly: false))
        XCTAssertTrue(texts(tree).contains("Finish signing in in your browser…"))
        XCTAssertEqual(button(tree, Pages.Block.signIn)?.enabled, false, "one sign-in at a time")
        account.isSignedIn = true
        account.email = "me@example.com"
        driver.answer(.signIn(chatOnly: false), .done(["signed in as me@example.com; scopes: x"]))
        XCTAssertNil(tool.setupBusy)
        XCTAssertEqual(tool.setupNotice, "Signed in as me@example.com")
        XCTAssertEqual(driver.jobs.count, 1, "speakers known already: nothing discovered")
        tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("me@example.com · Signed in"))
        XCTAssertEqual(link.rendered.last?.panel, HomeSpeakerTool.settingsPanel, "the open panel is drawn again")
        // A failed sign-in says why, without "error:".
        account.isSignedIn = false
        _ = event(tool, Pages.Block.signIn, .tap)
        driver.answer(.signIn(chatOnly: false),
                      ProcessDriver.result(of: .signIn(chatOnly: false), status: 1, output: "", error: "error: the browser was closed\n"))
        XCTAssertEqual(tool.setupNotice, "The browser was closed")
    }

    func testSigningInWithNoSpeakersFindsThem() {
        store.config = SpeakerConfig()
        let tool = opened()
        _ = event(tool, Pages.Block.signIn, .tap)
        account.isSignedIn = true
        driver.answer(.signIn(chatOnly: false), .done(["signed in as unknown"]))
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: true, home: nil)), "as HomeSpeaker's Settings does")
    }

    func testSignOutSignsOutOfEveryGoogleLogin() {
        account.isSignedIn = true
        let tool = opened()
        let tree = tool.settingsPage()
        XCTAssertTrue(texts(tree).contains("Connected · Signed in"), "no email known: Connected")
        XCTAssertTrue(texts(tree).contains { $0.contains("also signs out of Google Chat and stops the Chat monitor") })
        _ = event(tool, Pages.Block.signOut, .tap)
        XCTAssertEqual(driver.jobs.last, .app(.signOut(chatOnly: false)))
        XCTAssertEqual(ProcessDriver.arguments(for: driver.jobs.last!), ["--sign-out"])
        account.isSignedIn = false
        driver.answer(.app(.signOut(chatOnly: false)), .done(["signed out of Google (Home and Chat)"]))
        XCTAssertEqual(tool.setupNotice, "Signed out of Google (Home and Chat)")
        XCTAssertNotNil(button(tool.settingsPage(), Pages.Block.signIn))
    }

    func testTheAntigravityImportSignsInAndFindsSpeakersWhenThereAreNone() {
        account.hasAntigravityTokens = true
        store.config = SpeakerConfig()
        let tool = opened()
        let tree = event(tool, Pages.Block.importAntigravity, .tap)
        XCTAssertEqual(account.imports, 1)
        XCTAssertTrue(texts(tree).contains("Connected · Signed in"), "the account is read again")
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: true, home: nil)))
        XCTAssertEqual(tool.setupBusy, .app(.discover(save: true, home: nil)))
        XCTAssertTrue(texts(tree).contains("Finding speakers…"))
    }

    func testAnImportWithSpeakersAlreadyDoesNotDiscoverAndAnEmptyFileSaysSo() {
        account.hasAntigravityTokens = true
        let tool = opened()
        _ = event(tool, Pages.Block.importAntigravity, .tap)
        XCTAssertEqual(tool.setupNotice, "Imported the Antigravity Google Home login")
        XCTAssertEqual(driver.jobs.count, 0, "nothing was asked")
        account.isSignedIn = false
        account.importFinds = false
        _ = event(tool, Pages.Block.importAntigravity, .tap)
        XCTAssertEqual(tool.setupNotice, "No Google Home login found in the Antigravity token file")
    }

    /// The extension has no login item of its own: it runs while Vitruvian
    /// does, and General says so where the switch was. Nothing is asked.
    func testGeneralSaysItRunsWithVitruvianInPlaceOfOpenAtLogin() {
        let tool = opened()
        let tree = tool.settingsPage()
        XCTAssertNil(content(tree, "loginItem"))
        XCTAssertTrue(texts(tree).contains(Pages.DoorWords.runsWithVitruvian))
        XCTAssertFalse(driver.jobs.contains { if case .app(.loginItem) = $0 { return true } else { return false } },
                       "Settings asks nothing about a login item")
    }

    func testWithoutHomeSpeakerTheSetupControlsAreOff() {
        driver.isInstalled = false
        let tool = tool()
        let tree = tool.settingsPage()
        XCTAssertTrue(driver.jobs.isEmpty)
        XCTAssertEqual(button(tree, Pages.Block.signIn)?.enabled, false)
        _ = event(tool, Pages.Block.signIn, .tap)
        XCTAssertEqual(tool.setupNotice, "HomeSpeaker is not installed")
    }

    func testPauseMediaHasItsResumeDelayAndATest() {
        store.config?.effectivePauseMedia = true
        let tool = opened()
        var tree = tool.settingsPage()
        guard case .field(let extra)? = content(tree, Pages.Block.pauseExtra) else { return XCTFail("no field") }
        XCTAssertEqual(extra.title?.text(for: "en"), "Resume after (0 to 10 s)")
        XCTAssertEqual(extra.value, "1", "one second unless chosen")
        XCTAssertEqual(extra.kind, .number)
        XCTAssertTrue(texts(tree).contains { $0.contains("for 3 seconds") })
        _ = event(tool, Pages.Block.pauseExtra, .submit, .string(" 4 "))
        XCTAssertEqual(store.config?.pauseMediaExtraSeconds, 4)
        _ = event(tool, Pages.Block.pauseExtra, .submit, .string("10"))
        XCTAssertEqual(store.config?.pauseMediaExtraSeconds, 10)
        _ = event(tool, Pages.Block.pauseExtra, .submit, .string("0"))
        XCTAssertEqual(store.config?.pauseMediaExtraSeconds, 0)
        // Out of range or no number: refused and said, the saved value kept.
        for bad in ["25", "-3", "soon"] {
            _ = event(tool, Pages.Block.pauseExtra, .submit, .string(bad))
            XCTAssertEqual(store.config?.pauseMediaExtraSeconds, 0, bad)
            XCTAssertEqual(tool.setupNotice, HomeSpeakerTool.Invalid.pauseExtra, bad)
        }

        tree = event(tool, Pages.Block.testMediaPause, .tap)
        XCTAssertEqual(driver.jobs.last, .app(.testMediaPause))
        XCTAssertEqual(button(tree, Pages.Block.testMediaPause)?.title.text(for: "en"), "Paused…")
        XCTAssertEqual(button(tree, Pages.Block.testMediaPause)?.enabled, false)
        driver.answer(.app(.testMediaPause),
                      ProcessDriver.result(of: .app(.testMediaPause), status: 0, output: "paused Chrome (1 tab)\nresumed\n", error: ""))
        XCTAssertEqual(tool.mediaPauseReport, "Paused Chrome (1 tab). resumed")
        XCTAssertTrue(texts(tool.settingsPage()).contains("Paused Chrome (1 tab). resumed"))
        _ = event(tool, Pages.Block.testMediaPause, .tap)
        driver.answer(.app(.testMediaPause),
                      ProcessDriver.result(of: .app(.testMediaPause), status: 1, output: "could not pause Safari: not allowed\n", error: ""))
        XCTAssertEqual(tool.mediaPauseReport, "Could not pause Safari: not allowed")

        store.config?.effectivePauseMedia = false
        XCTAssertNil(content(tool.settingsPage(), Pages.Block.pauseExtra), "only while pausing is on")
    }

    func testQuietHoursAndTheAnnouncementVolume() {
        let tool = opened()
        let tree = tool.settingsPage()
        XCTAssertEqual(toggle(tree, Pages.Block.quiet)?.title.text(for: "en"), "Enable Quiet Hours")
        XCTAssertEqual(toggle(tree, Pages.Block.broadcasting)?.title.text(for: "en"), "Enable Voice Broadcasting")
        _ = event(tool, Pages.Block.quiet, .toggle, .bool(true))
        _ = event(tool, Pages.Block.quietEnd, .submit, .string("06:30"))
        _ = event(tool, Pages.Block.announceVolume, .toggle, .bool(true))
        _ = event(tool, Pages.Block.announceLevel, .submit, .string("75"))
        XCTAssertEqual(store.config?.quietHoursEnabled, true)
        XCTAssertEqual(store.config?.quietHoursEnd, "06:30")
        XCTAssertEqual(store.config?.announceVolume, 75)
        _ = event(tool, Pages.Block.announceLevel, .submit, .string("140"))
        XCTAssertEqual(store.config?.announceVolume, 75, "out of range: refused, not held to 100")
        XCTAssertEqual(tool.setupNotice, HomeSpeakerTool.Invalid.announceLevel)
    }

    // MARK: - Speakers

    private let listed = "home: Lake House (Annex) (h1)\n  kitchen\tSpeakerDevice\tKitchen\td1\nhome: City Flat (h2)\n  office\tSpeakerDevice\tOffice\td2\n"

    func testSpeakersListsTheHomesFirstThenSavesTheOnePicked() {
        account.isSignedIn = true
        let tool = opened(choice: true)
        var tree = show(tool, .speakers)
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: false, home: nil)), "the homes are listed when Speakers opens")
        XCTAssertTrue(texts(tree).contains("Listing your homes…"))
        XCTAssertEqual(button(tree, Pages.Block.discover)?.enabled, false, "not while the homes are listed")
        driver.answer(.app(.discover(save: false, home: nil)),
                      ProcessDriver.result(of: .app(.discover(save: false, home: nil)), status: 0, output: listed, error: ""))
        XCTAssertEqual(tool.homes, [HomeStructure(id: "h1", name: "Lake House (Annex)"), HomeStructure(id: "h2", name: "City Flat")])
        XCTAssertEqual(tool.selectedHomeId, "h2", "the home in the file is picked")
        tree = tool.settingsPage()
        guard case .choice(let homes)? = content(tree, Pages.Block.home) else { return XCTFail("no home picker") }
        XCTAssertEqual(homes.value, "h2")
        XCTAssertEqual(homes.options.map { $0.title.text(for: "en") }, ["Lake House (Annex)", "City Flat"])
        XCTAssertEqual(button(tree, Pages.Block.discover)?.title.text(for: "en"), "Refresh from Google Home")
        _ = show(tool, .general)
        _ = show(tool, .speakers)
        XCTAssertEqual(driver.jobs.filter { $0 == .app(.discover(save: false, home: nil)) }.count, 1, "listed once while open")

        _ = event(tool, Pages.Block.home, .change, .string("h1"))
        XCTAssertEqual(tool.selectedHomeId, "h1")
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.home, kind: .change, value: .string("h9"))), .keep)
        _ = event(tool, Pages.Block.discover, .tap)
        XCTAssertEqual(driver.jobs.last, .app(.discover(save: true, home: "h1")))
        XCTAssertEqual(ProcessDriver.arguments(for: driver.jobs.last!), ["--discover", "--save", "--home", "h1"])
        // HomeSpeaker writes the file; the tool reads it when it is done.
        store.config?.applyDiscovery(structureId: "h1", structureName: "Lake House (Annex)",
                                     targets: ["lake": SpeakerDevice(id: "d9", type: "SpeakerDevice", name: "Lake")])
        driver.answer(.app(.discover(save: true, home: "h1")),
                      .done(["home: Lake House (Annex) (h1)", "saved 1 target(s) from Lake House (Annex)"]))
        XCTAssertEqual(tool.config.structureId, "h1")
        XCTAssertEqual(tool.config.targets.keys.sorted(), ["lake"])
        XCTAssertEqual(tool.setupNotice, "Saved 1 target(s) from Lake House (Annex)")
    }

    func testOneHomeIsARowAndTheListIsAListWithoutChoice() {
        account.isSignedIn = true
        let tool = opened()
        _ = show(tool, .speakers)
        driver.answer(.app(.discover(save: false, home: nil)), .homes([HomeStructure(id: "h2", name: "City Flat")]))
        var tree = tool.settingsPage()
        XCTAssertNil(content(tree, Pages.Block.home))
        XCTAssertTrue(texts(tree).contains("City Flat · Home"))
        tool.finished(.app(.discover(save: false, home: nil)), .homes([HomeStructure(id: "h1", name: "Lake"), HomeStructure(id: "h2", name: "City Flat")]))
        tree = tool.settingsPage()
        XCTAssertEqual(rows(tree, Pages.Block.home).map(\.id), ["h1", "h2"])
        XCTAssertEqual(rows(tree, Pages.Block.home).map { $0.trailing?.text(for: "en") }, [nil, "✓"])
        _ = event(tool, Pages.Block.home, .tap, .string("h1"))
        XCTAssertEqual(tool.selectedHomeId, "h1")
    }

    func testSignedOutSpeakersAsksNothingAndSaysToSignIn() {
        store.config = SpeakerConfig()
        let tool = opened()
        let tree = show(tool, .speakers)
        XCTAssertEqual(driver.jobs.count, 0, "no homes listed without a sign-in")
        XCTAssertEqual(button(tree, Pages.Block.discover)?.title.text(for: "en"), "Find Speakers")
        XCTAssertEqual(button(tree, Pages.Block.discover)?.enabled, false)
        XCTAssertTrue(texts(tree).contains("Sign in under General first."))
        XCTAssertTrue(texts(tree).contains("No speakers yet."))
    }

    func testAFailedListingIsSaidAndNotAskedAgainAtEveryRedraw() {
        account.isSignedIn = true
        let tool = opened()
        _ = show(tool, .speakers)
        driver.answer(.app(.discover(save: false, home: nil)),
                      ProcessDriver.result(of: .app(.discover(save: false, home: nil)), status: 1, output: "",
                                           error: "error: no homes visible to this account\n"))
        XCTAssertEqual(tool.homes, [])
        XCTAssertEqual(tool.setupNotice, "No homes visible to this account")
        _ = tool.settingsPage()
        XCTAssertEqual(driver.jobs.filter { $0 == .app(.discover(save: false, home: nil)) }.count, 1)
    }

    func testEverySpeakerIsListedAndATapMakesItTheDefault() {
        store.config?.targets["kitchen_display"] = SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen")
        let tool = opened()
        var tree = show(tool, .speakers)
        let listed = rows(tree, Pages.Block.targets)
        XCTAssertEqual(listed.map(\.id), ["kitchen", "kitchen_display", "office"], "every alias, by key")
        XCTAssertEqual(listed.map { $0.title.text(for: "en") }, ["Kitchen", "Kitchen", "Office"])
        XCTAssertEqual(listed.map { $0.subtitle?.text(for: "en") }, ["Alias: kitchen • Room: Kitchen", "Alias: kitchen_display • Room: Kitchen", "Alias: office"])
        XCTAssertEqual(listed.map { $0.trailing?.text(for: "en") }, ["Default", nil, nil])
        tree = event(tool, Pages.Block.targets, .tap, .string("office"))
        XCTAssertEqual(store.config?.defaultTarget, "office")
        XCTAssertEqual(rows(tree, Pages.Block.targets).map { $0.trailing?.text(for: "en") }, [nil, nil, "Default"])
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.targets, kind: .tap, value: .string("nowhere"))), .keep)
        XCTAssertEqual(tool.settingsEvent(PanelEvent(block: Pages.Block.targets, kind: .tap, value: .string("office"))), .keep,
                       "already the default")
    }

    func testRemovingSpeakersGoesThroughTheConfigsOwnRule() {
        let tool = opened()
        _ = show(tool, .speakers)
        var tree = event(tool, Pages.Block.editSpeakers, .tap)
        XCTAssertTrue(tool.removingSpeakers)
        XCTAssertEqual(button(tree, Pages.Block.editSpeakers)?.title.text(for: "en"), "Done")
        XCTAssertEqual(rows(tree, Pages.Block.targets).map { $0.trailing?.text(for: "en") }, ["Remove", "Remove"])
        let saves = store.saves
        tree = event(tool, Pages.Block.targets, .tap, .string("kitchen"))
        var expected = SpeakerConfig(enabled: true, defaultTarget: "kitchen", structureId: "h2", structureName: "City Flat",
                                     targets: ["kitchen": SpeakerDevice(id: "d1", type: "SpeakerDevice", name: "Kitchen", room: "Kitchen"),
                                               "office": SpeakerDevice(id: "d2", type: "SpeakerDevice", name: "Office")])
        expected.removeTarget("kitchen")
        XCTAssertEqual(store.config, expected)
        XCTAssertEqual(store.config?.defaultTarget, "office", "the default moves on")
        XCTAssertEqual(store.saves, saves + 1)
        tree = event(tool, Pages.Block.targets, .tap, .string("office"))
        XCTAssertEqual(store.config?.targets, [:])
        XCTAssertEqual(store.config?.defaultTarget, "")
        XCTAssertFalse(tool.removingSpeakers, "nothing left to remove")
        XCTAssertTrue(texts(tree).contains("No speakers yet."))
    }

    func testThisMacHasAVoicePickerAndPreview() {
        store.config?.effectiveSpeakLocal = true
        store.config?.effectiveLocalVoice = ava.id
        let tool = opened(choice: true)
        var tree = show(tool, .speakers)
        guard case .choice(let voice)? = content(tree, Pages.Block.voice) else { return XCTFail("no voice picker") }
        XCTAssertEqual(voice.value, ava.id)
        XCTAssertEqual(voice.options.map { $0.title.text(for: "en") }, ["Ava (en-US) · Premium", "Daniel (en-GB) · Default"])
        XCTAssertEqual(button(tree, Pages.Block.previewVoice)?.title.text(for: "en"), "Preview")
        XCTAssertTrue(texts(tree).contains { $0.contains("Both speak at the same time") })
        _ = event(tool, Pages.Block.voice, .change, .string(daniel.id))
        XCTAssertEqual(store.config?.localVoice, daniel.id)
        link.features = []
        tree = event(tool, Pages.Block.voice, .tap, .string(ava.id))
        XCTAssertEqual(store.config?.localVoice, ava.id)
        XCTAssertEqual(rows(tree, Pages.Block.voice).map { $0.trailing?.text(for: "en") }, ["✓", nil])
        _ = event(tool, Pages.Block.speakLocal, .toggle, .bool(false))
        tree = tool.settingsPage()
        XCTAssertNil(content(tree, Pages.Block.voice), "no voice without This Mac")
        _ = event(tool, Pages.Block.speakHome, .toggle, .bool(false))
        XCTAssertTrue(texts(tool.settingsPage()).contains("All outputs are off, so nothing is spoken anywhere."))
    }

    func testASavedVoiceThatIsNotInstalledKeepsItsPlaceAndSaysWhatPlays() {
        store.config?.effectiveSpeakLocal = true
        store.config?.effectiveLocalVoice = "com.apple.voice.premium.en-US.Zoe"
        let tool = opened(choice: true)
        guard case .choice(let voice)? = content(show(tool, .speakers), Pages.Block.voice) else { return XCTFail("no voice picker") }
        XCTAssertEqual(voice.value, "com.apple.voice.premium.en-US.Zoe")
        XCTAssertEqual(voice.options.first?.value, "com.apple.voice.premium.en-US.Zoe")
        XCTAssertEqual(voice.options.first?.title.text(for: "en"), "Zoe (not installed; using Ava)")
        XCTAssertEqual(voice.options.count, 3)
        XCTAssertEqual(Pages.missingVoiceLabel("x.Zoe", voices: []), "Zoe (not installed; using the system voice)")
    }

    func testPreviewSpeaksTheVoicePickedAndSaysWhenItCannot() {
        store.config?.effectiveSpeakLocal = true
        store.config?.effectiveLocalVoice = daniel.id
        let spoken = expectation(description: "spoken")
        let handed = expectation(description: "handed back")
        let said = Said()
        let back = Handed()
        previewVoice = { voice in
            said.add(voice)
            spoken.fulfill()
        }
        later = { back.take($0) }
        let tool = opened()
        _ = show(tool, .speakers)
        back.hold(handed)
        let tree = event(tool, Pages.Block.previewVoice, .tap)
        XCTAssertTrue(tool.previewing)
        XCTAssertEqual(button(tree, Pages.Block.previewVoice)?.title.text(for: "en"), "Speaking…")
        XCTAssertEqual(button(tree, Pages.Block.previewVoice)?.enabled, false)
        wait(for: [spoken, handed], timeout: 5)
        XCTAssertEqual(said.all, [daniel.id])
        back.run()
        XCTAssertFalse(tool.previewing)
        XCTAssertEqual(button(tool.settingsPage(), Pages.Block.previewVoice)?.title.text(for: "en"), "Preview")
        XCTAssertNil(tool.setupNotice)
    }

    func testAFailedPreviewIsSaid() {
        store.config?.effectiveSpeakLocal = true
        let handed = expectation(description: "handed back")
        let back = Handed()
        previewVoice = { _ in throw LocalSpeechError.timedOut }
        later = { back.take($0) }
        let tool = opened()
        _ = show(tool, .speakers)
        back.hold(handed)
        _ = event(tool, Pages.Block.previewVoice, .tap)
        wait(for: [handed], timeout: 5)
        back.run()
        XCTAssertFalse(tool.previewing)
        XCTAssertEqual(tool.setupNotice, "This Mac did not finish speaking in time.")
    }

    // MARK: - Two slots

    func testASetupJobNeverHoldsUpSpeech() throws {
        let tool = opened()
        _ = event(tool, Pages.Block.signIn, .tap)
        XCTAssertEqual(tool.setupBusy, .signIn(chatOnly: false))
        // The island speaks and mutes while the browser sign-in waits.
        _ = tool.islandPage()
        XCTAssertEqual(tool.busy, .volume, "the island reads the volume beside the sign-in")
        driver.answer(.volume, .volume(Volume(speaker: "Kitchen", percent: 30, muted: false)))
        _ = tool.islandEvent(PanelEvent(block: Pages.Block.say, kind: .submit, value: .string("dinner")))
        XCTAssertEqual(tool.busy, .say("dinner"))
        XCTAssertEqual(tool.setupBusy, .signIn(chatOnly: false))
        driver.answer(.say("dinner"), .spoke("sent to Kitchen"))
        try tool.run(command: HomeSpeakerTool.Command.mute)
        XCTAssertEqual(tool.busy, .mute)
        // A second setup job waits for the first; a second speaker job for its own.
        let tree = event(tool, Pages.Block.testMediaPause, .tap)
        XCTAssertTrue(tool.setupNotice?.contains("busy") == true, "\(String(describing: tool.setupNotice))")
        XCTAssertTrue(texts(tree).contains("Finish signing in in your browser…"))
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.unmute))
        driver.answer(.mute, .volume(Volume(speaker: "Kitchen", percent: 30, muted: true)))
        XCTAssertEqual(tool.setupBusy, .signIn(chatOnly: false), "the speaker's answer leaves the sign-in running")
        driver.answer(.signIn(chatOnly: false), .done(["signed in as unknown"]))
        XCTAssertNil(tool.setupBusy)
        XCTAssertNil(tool.busy)
    }

    func testSetupNeedsHomeSpeakerButNoSpeaker() {
        store.config = SpeakerConfig()
        let tool = opened()
        _ = event(tool, Pages.Block.signIn, .tap)
        XCTAssertEqual(tool.setupBusy, .signIn(chatOnly: false), "no default speaker is needed to sign in")
        XCTAssertThrowsError(try tool.run(command: HomeSpeakerTool.Command.mute), "but a mute needs one")
    }
}

/// What a closure on another thread was given.
final class Said: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func add(_ value: String) { lock.withLock { values.append(value) } }
    var all: [String] { lock.withLock { values } }
}

/// Work handed to the kit's thread: run at once, as the kit's thread would,
/// until the test holds it; then kept, and run when the test says.
final class Handed: @unchecked Sendable {
    private let lock = NSLock()
    private var work: [@Sendable () -> Void] = []
    private var holding: XCTestExpectation?
    /// Keeps what is handed over from now on, and fulfils `kept` when it comes.
    func hold(_ kept: XCTestExpectation) { lock.withLock { holding = kept } }
    func take(_ item: @escaping @Sendable () -> Void) {
        let kept: XCTestExpectation? = lock.withLock {
            guard let holding else { return nil }
            work.append(item)
            return holding
        }
        guard let kept else { return item() }
        kept.fulfill()
    }
    func run() {
        let items = lock.withLock { () -> [@Sendable () -> Void] in
            defer { work.removeAll() }
            return work
        }
        items.forEach { $0() }
    }
}
