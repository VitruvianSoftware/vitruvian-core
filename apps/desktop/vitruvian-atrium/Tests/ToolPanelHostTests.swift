// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// The panels of a tool from outside, as the host keeps them: asked for,
/// drawn at most four times a second, acted in, closed, and ended with the
/// tool. The tool is no program and the clock is moved by hand; a web
/// panel's page is a stand-in that records what it is told.
enum ToolPanelHostTests {
    static func run(_ suite: TestSuite) {
        opening(suite)
        refusals(suite)
        pagesUnprompted(suite)
        aRefusedFirstPageSaysWhy(suite)
        whatFollowsARefusedPage(suite)
        everyPageIsANewRevision(suite)
        fourASecond(suite)
        aPageReadLate(suite)
        acting(suite)
        aToolOpensItsOwnSettings(suite)
        closing(suite)
        aViewerDoesNotCloseTheIslandsPage(suite)
        aViewerAloneClosesWhenItLeaves(suite)
        twoViewersShareOnePage(suite)
        aViewerAndTheSheetShareTheSettingsPage(suite)
        aViewerAndTheMenuPanelShareOnePage(suite)
        aViewerIsRefusedWhatThePlaceRefuses(suite)
        aToolThatEnds(suite)
        webPanels(suite)
        calls(suite)
        aFloodOfCalls(suite)
        badges(suite)
        readAway(suite)
        links(suite)
        aStatusIsKeptAndReplaced(suite)
        noneTakesItAway(suite)
        anUndeclaredStatusIsRefused(suite)
        aStatusGoesWhenTheProgramEnds(suite)
        aStatusGoesWhenTheToolIsForgotten(suite)
        changesArePublishedOnceASecond(suite)
        noticesAndTheSlot(suite)
        declaredWordsAreKept(suite)
        undeclaredWordsAreLeftOutAndTheMarkStays(suite)
        aStatusWithoutWordsTakesThemAway(suite)
        theWordsGoWithTheProgram(suite)
    }

    static let id = ToolID("com.acme.deploys")!

    static func key(_ panel: String) -> ToolPanelHost.Key {
        ToolPanelHost.Key(tool: id, panel: panel)
    }

    /// A page of one text block, as a tool writes it.
    static func page(_ text: String) -> String {
        #"{"blocks":[{"type":"text","text":"\#(text)"}]}"#
    }

    /// The text of the one block of a page the host shows.
    static func text(_ shown: ToolPanelHost.Shown?) -> String? {
        guard case .page(let tree)? = shown, case .text(let block)? = tree.blocks.first?.content else { return nil }
        return block.text.text(for: "en")
    }

    /// A web panel's page that records what it is told.
    final class Page: ToolWebPage {
        var emitted: [String] = []
        var closed = 0

        func emit(_ name: String, _ params: JSONValue) {
            emitted.append(name)
        }

        func close() {
            closed += 1
        }
    }

    /// A tool with a panel in each place, two of them web pages, and the
    /// host that draws them.
    final class Bench {
        let clock = ManualToolClock()
        var runs: [FakeTool] = []
        var logged: [String] = []
        var beeps = 0
        var stopped: [ToolID] = []
        /// The links the tool's `open` service was asked to open, and
        /// whether it does.
        var opened: [URL] = []
        var opens = true
        /// The tools whose settings Settings was asked to show.
        var settingsOpened: [ToolID] = []
        /// How many pages the host has had read.
        var reads = 0
        /// Pages handed to the reader and not read yet, when reading waits.
        var reading: [(JSONValue, @MainActor (Result<UITree, ToolPanelProblem>) -> Void)] = []
        var readsAtOnce = true
        /// The notices shown, and how often the Agents slot was opened.
        var notices: [NotifyNoticeParams] = []
        var docks = 0
        let folder: URL
        let described: ExternalToolManifest
        private(set) var tool: ExternalTool!
        private(set) var host: ToolPanelHost!

        /// `declaresStatus` is whether the tool's manifest declares a status;
        /// `declaresActivity`, whether that status says `"activity": true`;
        /// `name`, the tool's name in English, when not the example's.
        init(limits: ToolLimits = .standard, declaresStatus: Bool = true, declaresActivity: Bool = false,
             name: String? = nil, declaresSlot: Bool = false) {
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("vitruvian-panels-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent("ui"),
                                                     withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: folder.appendingPathComponent("ui/dashboard.html").path,
                                           contents: Data("<p>".utf8))
            described = ExternalToolManifestTests.tool(#"""
                {\#(name.map { #""name": {"en": "\#($0)"}, "# } ?? "")"protocol": "2", "uses": ["notify", "storage"], "contributes": {"panels": [
                  {"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"},
                  {"id": "settings", "title": {"en": "Deploys"}, "placement": "settings"},
                  {"id": "log", "title": {"en": "Deploy log"}, "placement": "window"},
                  {"id": "dashboard", "title": {"en": "Dashboard"}, "placement": "window", "kind": "web", "entry": "ui/dashboard.html"},
                  {"id": "broken", "title": {"en": "Broken"}, "placement": "window", "kind": "web", "entry": "ui/missing.html"}
                ]\#(declaresStatus ? #", "status": {"placement": "island"\#(declaresActivity ? #", "activity": true"# : "")}"# : "")\#(declaresSlot ? #", "slot": {"placement": "agents"}"# : "")}}
                """#)!
            tool = ExternalTool(
                manifest: described.manifest, clock: clock, limits: limits,
                makeLink: { [unowned self] events in
                    let run = FakeTool()
                    runs.append(run)
                    return ToolLink(transport: run, clock: clock, limits: limits,
                                    hello: InitializeParams(protocolVersions: ["1", "2"], language: "en",
                                                            dataFolder: "/data"),
                                    serve: { _, _, reply in reply(.success(.object([:]))) }, events: events)
                },
                events: .init(onRender: { [unowned self] panel, tree in host.rendered(id, panel: panel, tree: tree) },
                              onRunEnded: { [unowned self] in host.toolEnded(id) }))
            host = ToolPanelHost(parts: .init(
                clock: clock, limits: limits,
                tool: { [unowned self] in $0 == id ? tool : nil },
                // Held, not reached through the bench: a panel drawn in an
                // earlier test asks for the tool's name again when the app's
                // language changes, after its bench is gone.
                described: { [described] in $0 == id ? described : nil },
                folder: { [unowned self] in $0 == id ? folder : nil },
                read: { [unowned self] value, then in
                    reads += 1
                    if readsAtOnce { then(ToolPanelTree.read(value)) } else { reading.append((value, then)) }
                },
                log: { [unowned self] _, text in logged.append(text) },
                beep: { [unowned self] in beeps += 1 },
                misbehaved: { [unowned self] in stopped.append($0) },
                openLink: { [unowned self] _, url in
                    opened.append(url)
                    return opens
                },
                openSettings: { [unowned self] in settingsOpened.append($0) },
                notice: { [unowned self] in notices.append($0) },
                dockAgents: { [unowned self] in docks += 1 }))
            tool.start()
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }

        var current: FakeTool { runs[runs.count - 1] }

        /// The island panel, open and drawn: its program runs and has
        /// answered with a first page.
        static func open(_ panel: String = "deploys", in place: ToolPanelPlacement = .island,
                         limits: ToolLimits = .standard) -> Bench {
            let bench = Bench(limits: limits)
            bench.host.open(key(panel), in: place)
            bench.current.greets()
            if let asked = bench.current.lastRequest { bench.current.answers(asked, #"{"tree":\#(page("first"))}"#) }
            return bench
        }

        func render(_ panel: String, _ text: String) {
            current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"\#(panel)","tree":\#(page(text))}}"#)
        }

        /// The last message the tool's program was sent.
        var lastSent: RPCMessage? { current.sent.last }
    }

    static func opening(_ suite: TestSuite) {
        let bench = Bench()
        suite.expect(bench.host.open(key("deploys"), in: .island) == nil
                         && bench.host.shown[key("deploys")] == .waiting && bench.host.island == key("deploys"),
                     "opening the island panel shows it waiting for its first page")
        suite.expect(bench.runs.count == 1, "it starts the tool's program, which was resting")
        bench.current.greets()
        suite.expect(bench.lastSent == .request(id: .number(2), method: "ui/open",
                                                params: .object(["panel": .string("deploys")])),
                     "once greeted, the tool is asked for the panel's first page")
        bench.current.answers(2, #"{"tree":\#(page("Today"))}"#)
        suite.expect(text(bench.host.shown[key("deploys")]) == "Today" && bench.reads == 1,
                     "its answer is read and drawn")
        suite.expect(bench.host.open(key("deploys"), in: .island) == nil && bench.current.sent.count == 2,
                     "opening a panel that is open again asks nothing")

        let silent = Bench()
        silent.host.open(key("deploys"), in: .island)
        silent.current.greets()
        silent.clock.advance(by: 2)
        suite.expect(silent.host.shown[key("deploys")] == .notShown(nil) && silent.logged.last?.contains("not opened") == true,
                     "a tool that does not answer in two seconds leaves the panel not shown, and its log says so")
    }

    static func refusals(_ suite: TestSuite) {
        let bench = Bench()
        suite.expect(bench.host.open(key("nothing"), in: .island) == .unknownPanel("nothing")
                         && bench.host.open(key("deploys"), in: .window) == .wrongPlace("deploys")
                         && bench.host.open(key("log"), in: .settings) == .wrongPlace("log"),
                     "a panel the manifest does not declare, or opened in another place, is refused")
        suite.expect(bench.host.shown.isEmpty && bench.runs.isEmpty,
                     "and nothing is shown or started for it")
        suite.expect(ToolPanelHost.Refusal.unknownPanel("x").error.code == -32602
                         && ToolPanelHost.Refusal.notOpen("x").error.code == -32602
                         && ToolPanelHost.Refusal.wrongPlace("x").error.code == -32602,
                     "each refusal is the protocol's invalid params, -32602")
        suite.expect(bench.host.act(key("deploys"), block: "again", event: .tap) == .notOpen("deploys"),
                     "acting in a panel that is not open is refused")
    }

    static func pagesUnprompted(_ suite: TestSuite) {
        let bench = Bench.open()
        bench.render("nothing", "stray")
        suite.expect(text(bench.host.shown[key("deploys")]) == "first"
                         && bench.logged.last == "a page for the panel nothing, which the manifest does not declare, was dropped",
                     "a page for a panel the manifest does not declare is dropped, and logged")
        bench.render("log", "stray")
        suite.expect(bench.host.shown[key("log")] == nil
                         && bench.logged.last == "a page for the panel log, which is not open, was dropped",
                     "a page for a panel that is not open is dropped, and logged")
        bench.render("deploys", "second")
        suite.expect(text(bench.host.shown[key("deploys")]) == "second",
                     "a page for the open panel is drawn")
        bench.clock.advance(by: 1)
        bench.current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":{"blocks":[{"type":"button","title":"Go"}]}}}"#)
        suite.expect(text(bench.host.shown[key("deploys")]) == "second"
                         && bench.logged.last == "a page for the panel deploys was not drawn: blocks[0].id is not well formed",
                     "a page that is not well formed leaves the last one drawn, and the log says where")
        let large = String(repeating: "x", count: UILimits.maxTreeBytes)
        bench.clock.advance(by: 1)
        bench.render("deploys", large)
        suite.expect(text(bench.host.shown[key("deploys")]) == "second"
                         && bench.logged.last?.hasPrefix("a page of 262") == true,
                     "a page over 256 KB leaves the last one drawn, and the log says how large it was")
    }

    /// A page the app refuses is never drawn. Until one is, the panel says
    /// it could not be shown and why, in place of a spinner that never ends:
    /// in 3.64.0 HomeSpeaker's settings spun forever, its page refused for
    /// `blocks[76].id is not well formed`, and only its log said so. Once a
    /// page is drawn, a refused one leaves it, as before.
    static func aRefusedFirstPageSaysWhy(_ suite: TestSuite) {
        let button = #"{"blocks":[{"type":"button","title":"Go"}]}"#
        let malformed = Bench()
        malformed.host.open(key("settings"), in: .settings)
        malformed.current.greets()
        if let asked = malformed.current.lastRequest { malformed.current.answers(asked, #"{"tree":\#(button)}"#) }
        suite.expect(malformed.host.shown[key("settings")] == .notShown(.notWellFormed("blocks[0].id"))
                         && malformed.logged.last == "a page for the panel settings was not drawn: blocks[0].id is not well formed",
                     "a first page that is not well formed leaves the panel not shown, saying where, not waiting: "
                         + String(describing: malformed.host.shown[key("settings")]))
        malformed.render("settings", "fixed")
        suite.expect(text(malformed.host.shown[key("settings")]) == "fixed",
                     "a page the tool sends after a refused first one is drawn in its place")

        let large = Bench()
        large.host.open(key("deploys"), in: .island)
        large.current.greets()
        let huge = page(String(repeating: "x", count: UILimits.maxTreeBytes))
        if let asked = large.current.lastRequest { large.current.answers(asked, #"{"tree":\#(huge)}"#) }
        var bytes: Int?
        if case .notShown(.tooLarge(let size)?)? = large.host.shown[key("deploys")] { bytes = size }
        suite.expect((bytes ?? 0) > UILimits.maxTreeBytes && large.logged.last?.hasPrefix("a page of 262") == true,
                     "a first page over 256 KB leaves the panel not shown, saying how large it was, not waiting: "
                         + String(describing: large.host.shown[key("deploys")].map { "\($0)".prefix(80) }))

        let drawn = Bench.open()
        drawn.clock.advance(by: 1)
        drawn.current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":\#(button)}}"#)
        drawn.clock.advance(by: 1)
        drawn.render("deploys", String(repeating: "x", count: UILimits.maxTreeBytes))
        suite.expect(text(drawn.host.shown[key("deploys")]) == "first" && drawn.logged.filter { $0.contains("was not drawn") }.count == 2,
                     "a refused page after one was drawn keeps that page, and the log says why each time")
        let named = Bench(name: "HomeSpeaker")
        suite.expect(drawn.host.name(of: id, language: "en") == "Deploys"
                         && named.host.name(of: id, language: "en") == "HomeSpeaker"
                         && drawn.host.name(of: ToolID("com.acme.other")!, language: "en") == "com.acme.other",
                     "the panel names the tool as its manifest does, or by its id when the app knows no name")
    }

    /// After a refused page: the open answer still draws, a newer refusal
    /// says the newer reason, a page being read keeps the panel waiting, and
    /// a viewer or the menu bar panel letting go still tells the tool.
    static func whatFollowsARefusedPage(_ suite: TestSuite) {
        let button = #"{"blocks":[{"type":"button","title":"Go"}]}"#
        let early = Bench()
        early.host.open(key("deploys"), in: .island)
        early.current.greets()
        let asked = early.current.lastRequest
        early.current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":\#(button)}}"#)
        let refused = early.host.shown[key("deploys")]
        if let asked { early.current.answers(asked, #"{"tree":\#(page("Today"))}"#) }
        suite.expect(refused == .notShown(.notWellFormed("blocks[0].id")) && text(early.host.shown[key("deploys")]) == "Today",
                     "a refused page the tool sent before answering the open does not stop the answer's page being "
                         + "drawn: \(String(describing: refused)), then \(String(describing: early.host.shown[key("deploys")]))")

        let twice = Bench()
        twice.host.open(key("deploys"), in: .island)
        twice.current.greets()
        if let asked = twice.current.lastRequest { twice.current.answers(asked, #"{"tree":\#(button)}"#) }
        twice.render("deploys", String(repeating: "x", count: UILimits.maxTreeBytes))
        var newest: ToolPanelProblem?
        if case .notShown(let problem?)? = twice.host.shown[key("deploys")] { newest = problem }
        suite.expect({ if case .tooLarge? = newest { return true } else { return false } }(),
                     "a second refused page, before any is drawn, says its own reason, the newest: "
                         + String(describing: newest.map { "\($0)".prefix(60) }))

        let slow = Bench()
        slow.readsAtOnce = false
        slow.host.open(key("deploys"), in: .island)
        slow.current.greets()
        if let asked = slow.current.lastRequest { slow.current.answers(asked, #"{"tree":\#(page("Today"))}"#) }
        suite.expect(slow.host.shown[key("deploys")] == .waiting && slow.reading.count == 1,
                     "a page still being read keeps the panel waiting, not refused")
        if let (value, then) = slow.reading.first { then(ToolPanelTree.read(value)) }
        suite.expect(text(slow.host.shown[key("deploys")]) == "Today", "and is drawn once it is read")

        let viewed = Bench()
        let viewer = UUID()
        viewed.host.openAsViewer(key("deploys"), in: .island, viewer: viewer)
        viewed.current.greets()
        if let asked = viewed.current.lastRequest { viewed.current.answers(asked, #"{"tree":\#(button)}"#) }
        let viewedShown = viewed.host.shown[key("deploys")]
        viewed.host.closeAsViewer(key("deploys"), viewer: viewer)
        suite.expect(viewedShown == .notShown(.notWellFormed("blocks[0].id")) && viewed.host.shown[key("deploys")] == nil
                         && closes(viewed) == 1,
                     "a viewer letting go of a refused page closes it, and the tool is told")

        let card = UUID()
        let menu = Bench()
        menu.host.openInMenuPanel(key("deploys"), viewer: card)
        menu.current.greets()
        if let asked = menu.current.lastRequest { menu.current.answers(asked, #"{"tree":\#(button)}"#) }
        let menuShown = menu.host.shown[key("deploys")]
        menu.host.closeInMenuPanel(key("deploys"), viewer: card)
        suite.expect(menuShown == .notShown(.notWellFormed("blocks[0].id")) && menu.host.shown[key("deploys")] == nil
                         && closes(menu) == 1,
                     "the menu bar panel letting go of a refused page closes it, and the tool is told")
    }

    /// Each page a tool sends is counted, the same page again too, so a
    /// page that holds a chip pick the tool refused still ends it.
    static func everyPageIsANewRevision(_ suite: TestSuite) {
        let bench = Bench.open()
        let first = bench.host.revisions[key("deploys")]
        bench.clock.advance(by: 1)
        bench.render("deploys", "first")
        let again = bench.host.revisions[key("deploys")]
        bench.clock.advance(by: 1)
        bench.current.says(#"{"jsonrpc":"2.0","method":"ui/render","params":{"panel":"deploys","tree":{"blocks":[{"type":"button","title":"Go"}]}}}"#)
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && first != nil
                         && again == first.map { $0 + 1 } && bench.host.revisions[key("deploys")] == again,
                     "the same page sent again is a new revision of the panel; a page that is not drawn is none: "
                         + "\(String(describing: first)), \(String(describing: again))")
    }

    static func fourASecond(_ suite: TestSuite) {
        let bench = Bench.open()
        let before = bench.reads
        bench.render("deploys", "a")
        suite.expect(text(bench.host.shown[key("deploys")]) == "a" && bench.reads == before + 1,
                     "a page after a quiet while is drawn at once")
        bench.clock.advance(by: 0.05)
        bench.render("deploys", "b")
        bench.clock.advance(by: 0.05)
        bench.render("deploys", "c")
        bench.render("deploys", "d")
        suite.expect(text(bench.host.shown[key("deploys")]) == "a" && bench.reads == before + 1,
                     "pages that come within a quarter of a second of the last one drawn wait")
        bench.clock.advance(by: 0.1)
        suite.expect(text(bench.host.shown[key("deploys")]) == "a", "until the quarter second has passed")
        bench.clock.advance(by: 0.1)
        suite.expect(text(bench.host.shown[key("deploys")]) == "d" && bench.reads == before + 2,
                     "then the last of them is drawn, and the ones between never are")
        for index in 0..<40 {
            bench.render("deploys", "n\(index)")
            bench.clock.advance(by: 0.025)
        }
        bench.clock.advance(by: 1)
        suite.expect(UILimits.rendersPerSecond == 4 && bench.reads <= before + 2 + 5
                         && text(bench.host.shown[key("deploys")]) == "n39",
                     "forty pages in a second are drawn four or five times, and the last one is what shows")
    }

    static func aPageReadLate(_ suite: TestSuite) {
        let bench = Bench.open()
        bench.readsAtOnce = false
        bench.render("deploys", "older")
        bench.host.act(key("deploys"), block: "again", event: .tap)
        if let asked = bench.current.lastRequest { bench.current.answers(asked, #"{"tree":\#(page("newer"))}"#) }
        suite.expect(bench.reading.count == 2, "both pages are being read")
        let (newer, drawNewer) = bench.reading[1]
        let (older, drawOlder) = bench.reading[0]
        drawNewer(ToolPanelTree.read(newer))
        drawOlder(ToolPanelTree.read(older))
        suite.expect(text(bench.host.shown[key("deploys")]) == "newer",
                     "a page that was read after a newer one is not drawn over it")
    }

    static func acting(_ suite: TestSuite) {
        let bench = Bench.open()
        suite.expect(bench.host.act(key("deploys"), block: "again", event: .tap) == nil
                         && bench.lastSent == .request(id: .number(3), method: "ui/event",
                                                       params: .object(["panel": .string("deploys"),
                                                                        "block": .string("again"),
                                                                        "event": .string("tap")])),
                     "a tap is the request ui/event, naming the panel and the block")
        bench.current.answers(3, #"{"tree":\#(page("Deploying"))}"#)
        suite.expect(text(bench.host.shown[key("deploys")]) == "Deploying", "its answer's page is drawn")

        bench.host.act(key("deploys"), block: "notify", event: .toggle, value: .bool(false))
        suite.expect(bench.lastSent == .request(id: .number(4), method: "ui/event",
                                                params: .object(["panel": .string("deploys"),
                                                                 "block": .string("notify"),
                                                                 "event": .string("toggle"),
                                                                 "value": .bool(false)])),
                     "a switch's event carries its new state")
        bench.current.answers(4, #"{"keep":true,"tree":\#(page("ignored"))}"#)
        suite.expect(text(bench.host.shown[key("deploys")]) == "Deploying", "keep leaves the page as it is")

        bench.host.act(key("deploys"), block: "deploys", event: .tap, value: .string("api"))
        bench.current.answers(5, #"{"open":"log"}"#)
        suite.expect(bench.host.windows == [key("log")] && bench.host.shown[key("log")] == .waiting
                         && bench.lastSent == .request(id: .number(6), method: "ui/open",
                                                       params: .object(["panel": .string("log")])),
                     "an answer may open one of the tool's windows, which is asked for its page")
        bench.host.act(key("deploys"), block: "deploys", event: .tap, value: .string("web"))
        bench.current.answers(7, #"{"open":"deploys"}"#)
        suite.expect(bench.host.windows == [key("log")]
                         && bench.logged.last == "the window deploys was not opened: not a panel of this place",
                     "an answer that names a panel that is not a window opens nothing")

        let beeps = bench.beeps
        bench.host.act(key("deploys"), block: "again", event: .tap)
        bench.clock.advance(by: 2)
        suite.expect(bench.beeps == beeps + 1 && text(bench.host.shown[key("deploys")]) == "Deploying",
                     "an event the tool does not answer plays the alert sound and leaves the page")
    }

    /// `open` naming the tool's own settings panel opens Settings on the
    /// tool's detail, and only the asking tool's: the id is looked up in its
    /// own manifest. Anything else it may not open is refused as before.
    static func aToolOpensItsOwnSettings(_ suite: TestSuite) {
        func answer(_ bench: Bench, _ result: String) {
            bench.host.act(key("deploys"), block: "more", event: .tap)
            if let asked = bench.current.lastRequest { bench.current.answers(asked, result) }
        }

        let bench = Bench.open()
        let sent = bench.current.sent.count
        answer(bench, #"{"open":"settings"}"#)
        suite.expect(bench.settingsOpened == [id] && bench.host.shown[key("settings")] == nil
                         && bench.host.windows.isEmpty && bench.current.sent.count == sent + 1 && bench.logged.isEmpty,
                     "an answer that names the tool's settings panel opens Settings on that tool's detail, and no window")

        answer(bench, #"{"open":"settings","tree":\#(page("Opening"))}"#)
        suite.expect(bench.settingsOpened == [id, id] && text(bench.host.shown[key("deploys")]) == "Opening",
                     "a page sent with it is drawn too")

        answer(bench, #"{"open":"com.acme.other"}"#)
        answer(bench, #"{"open":"deploys"}"#)
        suite.expect(bench.settingsOpened == [id, id]
                         && bench.logged == ["the window com.acme.other was not opened: no such panel",
                                             "the window deploys was not opened: not a panel of this place"],
                     "an id the manifest does not declare, or its island page, opens nothing, and the tool's log says so")

        let menu = Bench()
        menu.host.openInMenuPanel(key("deploys"), viewer: UUID())
        menu.current.greets()
        if let asked = menu.current.lastRequest { menu.current.answers(asked, #"{"tree":\#(page("first"))}"#) }
        answer(menu, #"{"open":"settings"}"#)
        suite.expect(menu.settingsOpened == [id], "the button works the same from the menu bar panel's tab")
    }

    static func closing(_ suite: TestSuite) {
        let bench = Bench.open()
        bench.render("deploys", "a")
        bench.render("deploys", "waiting")
        bench.host.close(key("deploys"))
        suite.expect(bench.host.shown[key("deploys")] == nil && bench.host.island == nil
                         && bench.lastSent == .notice(method: "ui/close", params: .object(["panel": .string("deploys")])),
                     "closing a panel tells the tool and forgets the page")
        let reads = bench.reads
        bench.clock.advance(by: 1)
        bench.render("deploys", "late")
        suite.expect(bench.reads == reads && bench.host.shown[key("deploys")] == nil,
                     "the page that was waiting, and any page after, is not drawn")
    }

    // MARK: - Viewers: the Dynamic Island page in Settings

    /// How many times the tool was asked for `panel`'s page.
    static func opens(_ bench: Bench, _ panel: String = "deploys") -> Int {
        bench.runs.flatMap(\.sent).filter {
            if case .request(_, "ui/open", .object(let params)?) = $0 { return params["panel"] == .string(panel) }
            return false
        }.count
    }

    /// How many times the tool was told `panel` closed.
    static func closes(_ bench: Bench, _ panel: String = "deploys") -> Int {
        bench.runs.flatMap(\.sent).filter { $0 == .notice(method: "ui/close", params: .object(["panel": .string(panel)])) }.count
    }

    /// The viewer opens a page no place has open, and the tool answers.
    static func answered(_ bench: Bench) {
        bench.current.greets()
        if let asked = bench.current.lastRequest { bench.current.answers(asked, #"{"tree":\#(page("first"))}"#) }
    }

    static func aViewerDoesNotCloseTheIslandsPage(_ suite: TestSuite) {
        let bench = Bench.open()
        let viewer = UUID()
        suite.expect(bench.host.openAsViewer(key("deploys"), in: .island, viewer: viewer) == nil
                         && opens(bench) == 1 && text(bench.host.shown[key("deploys")]) == "first",
                     "a viewer of a page the island has open is shown it as it is, and the tool is asked nothing")
        bench.host.closeAsViewer(key("deploys"), viewer: viewer)
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && bench.host.island == key("deploys")
                         && closes(bench) == 0,
                     "the viewer letting go leaves the island's page open, and the tool is not told")

        let other = UUID()
        bench.host.openAsViewer(key("deploys"), in: .island, viewer: other)
        bench.host.close(key("deploys"))
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && bench.host.island == nil && closes(bench) == 0,
                     "the island letting go of a page a viewer shows leaves it open, and the tool is not told")
        bench.host.closeAsViewer(key("deploys"), viewer: other)
        suite.expect(bench.host.shown[key("deploys")] == nil && closes(bench) == 1,
                     "the viewer letting go last closes it, and tells the tool once")
    }

    static func aViewerAloneClosesWhenItLeaves(_ suite: TestSuite) {
        let bench = Bench()
        let viewer = UUID()
        suite.expect(bench.host.openAsViewer(key("deploys"), in: .island, viewer: viewer) == nil
                         && bench.host.shown[key("deploys")] == .waiting && bench.host.island == nil,
                     "a viewer opens a page no place has open, waiting for its first page, without making it the "
                         + "island's page")
        answered(bench)
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && opens(bench) == 1,
                     "the tool is asked once, as the island asks, and its page is drawn")
        bench.host.closeAsViewer(key("deploys"), viewer: viewer)
        bench.host.closeAsViewer(key("deploys"), viewer: viewer)
        suite.expect(bench.host.shown[key("deploys")] == nil && bench.host.viewers.isEmpty && closes(bench) == 1,
                     "when it leaves, the page closes and the tool is told once, however often it lets go")
    }

    static func twoViewersShareOnePage(_ suite: TestSuite) {
        let bench = Bench()
        let first = UUID()
        let second = UUID()
        bench.host.openAsViewer(key("deploys"), in: .island, viewer: first)
        answered(bench)
        bench.host.openAsViewer(key("deploys"), in: .island, viewer: second)
        suite.expect(opens(bench) == 1 && bench.host.viewers[key("deploys")] == [first, second],
                     "two viewers share one page, and the tool is asked to open it once")
        bench.host.closeAsViewer(key("deploys"), viewer: first)
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && closes(bench) == 0,
                     "one of them letting go leaves the page open for the other")
        bench.host.closeAsViewer(key("deploys"), viewer: second)
        suite.expect(bench.host.shown[key("deploys")] == nil && closes(bench) == 1,
                     "the last one letting go closes it, once")
    }

    static func aViewerAndTheSheetShareTheSettingsPage(_ suite: TestSuite) {
        let bench = Bench.open("settings", in: .settings)
        let viewer = UUID()
        bench.host.openAsViewer(key("settings"), in: .settings, viewer: viewer)
        bench.host.close(key("settings"))
        suite.expect(text(bench.host.shown[key("settings")]) == "first" && opens(bench, "settings") == 1
                         && closes(bench, "settings") == 0,
                     "the Extensions sheet closing leaves the settings page a viewer shows open, and the tool is not told")
        bench.host.closeAsViewer(key("settings"), viewer: viewer)
        suite.expect(bench.host.shown[key("settings")] == nil && closes(bench, "settings") == 1,
                     "the viewer letting go last closes it")

        let later = Bench()
        later.host.openAsViewer(key("settings"), in: .settings, viewer: viewer)
        answered(later)
        later.host.open(key("settings"), in: .settings)
        later.host.closeAsViewer(key("settings"), viewer: viewer)
        suite.expect(text(later.host.shown[key("settings")]) == "first" && opens(later, "settings") == 1
                         && closes(later, "settings") == 0,
                     "the sheet opening a page a viewer has open asks nothing, and the viewer leaving leaves it the "
                         + "sheet's")
        later.host.close(key("settings"))
        suite.expect(later.host.shown[key("settings")] == nil && closes(later, "settings") == 1,
                     "and the sheet closing it then closes it")
    }

    static func aViewerAndTheMenuPanelShareOnePage(_ suite: TestSuite) {
        let bench = Bench()
        let card = UUID()
        let viewer = UUID()
        bench.host.openInMenuPanel(key("deploys"), viewer: card)
        answered(bench)
        bench.host.openAsViewer(key("deploys"), in: .island, viewer: viewer)
        bench.host.closeInMenuPanel(key("deploys"), viewer: card)
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && opens(bench) == 1 && closes(bench) == 0,
                     "the menu bar panel letting go leaves a viewer's page open")
        bench.host.openInMenuPanel(key("deploys"), viewer: card)
        bench.host.closeAsViewer(key("deploys"), viewer: viewer)
        suite.expect(text(bench.host.shown[key("deploys")]) == "first" && closes(bench) == 0,
                     "and a viewer letting go leaves the menu bar panel's page open")
        bench.host.closeInMenuPanel(key("deploys"), viewer: card)
        suite.expect(bench.host.shown[key("deploys")] == nil && closes(bench) == 1,
                     "the last of them closes it, once")
    }

    static func aViewerIsRefusedWhatThePlaceRefuses(_ suite: TestSuite) {
        let bench = Bench()
        let viewer = UUID()
        suite.expect(bench.host.openAsViewer(key("settings"), in: .island, viewer: viewer) == .wrongPlace("settings")
                         && bench.host.openAsViewer(key("nothing"), in: .island, viewer: viewer) == .unknownPanel("nothing")
                         && bench.host.shown.isEmpty && bench.host.viewers.isEmpty && bench.runs.isEmpty,
                     "a viewer is refused a panel that is not of its place, or not declared, and nothing starts")
        bench.host.openAsViewer(key("deploys"), in: .island, viewer: viewer)
        answered(bench)
        bench.current.ends(0)
        let sent = bench.runs.flatMap(\.sent).count
        bench.host.closeAsViewer(key("deploys"), viewer: viewer)
        suite.expect(bench.host.shown.isEmpty && bench.host.viewers.isEmpty && bench.runs.flatMap(\.sent).count == sent,
                     "a page a viewer shows ends with its tool's program, and the viewer letting go afterwards sends "
                         + "nothing")
    }

    static func aToolThatEnds(_ suite: TestSuite) {
        let bench = Bench.open()
        bench.host.open(key("dashboard"), in: .window)
        bench.current.answers(3)
        let page = Page()
        bench.host.keep(page, for: key("dashboard"))
        bench.host.badge(id, UIBadgeParams(count: 2))
        bench.current.ends(1)
        suite.expect(bench.host.shown.isEmpty && bench.host.windows.isEmpty && bench.host.island == nil
                         && page.closed == 1 && bench.host.page(for: key("dashboard")) == nil,
                     "every panel ends with its tool's program, and a web page with it")
        suite.expect(bench.host.badges[id] == .count(2), "the badge stays across runs of the program")
        bench.host.forget(id)
        suite.expect(bench.host.badges[id] == nil, "and goes when the tool is switched off or removed")
    }

    static func webPanels(_ suite: TestSuite) {
        let bench = Bench()
        bench.host.open(key("dashboard"), in: .window)
        let file = bench.folder.appendingPathComponent("ui/dashboard.html").resolvingSymlinksInPath().standardizedFileURL
        suite.expect(bench.host.shown[key("dashboard")] == .web(page: file, folder: bench.folder),
                     "a web panel shows its page, a file inside the tool's folder")
        bench.current.greets()
        suite.expect(bench.lastSent == .request(id: .number(2), method: "ui/open",
                                                params: .object(["panel": .string("dashboard")])),
                     "and its tool is told it opened")
        bench.current.answers(2)
        suite.expect(bench.host.shown[key("dashboard")] == .web(page: file, folder: bench.folder),
                     "a web panel's answer of {} changes nothing")
        let first = Page()
        let second = Page()
        bench.host.keep(first, for: key("dashboard"))
        bench.host.keep(second, for: key("dashboard"))
        suite.expect(bench.host.page(for: key("dashboard")) === second && first.closed == 1,
                     "the host keeps one page for each panel, and closes one it is no longer keeping")
        let stray = Page()
        bench.host.keep(stray, for: key("log"))
        suite.expect(stray.closed == 1 && bench.host.page(for: key("log")) == nil,
                     "a page for a panel that is not open is closed at once")

        bench.host.tellPages(of: id, .languageChanged, .object(["language": .string("fr")]))
        suite.expect(second.emitted == ["language/changed"], "a page hears the app's notices its tool hears")

        bench.host.notShown(key("dashboard"), why: "it tried to go to https://example.com/")
        suite.expect(bench.host.shown[key("dashboard")] == .notShown(nil)
                         && bench.logged.last == "the page of the panel dashboard could not be shown: it tried to go to https://example.com/",
                     "a page that fails to load, or leaves its folder, is not shown, and the log says why")

        bench.host.open(key("broken"), in: .window)
        suite.expect(bench.host.shown[key("broken")] == .notShown(nil)
                         && bench.logged.last == "the page of the panel broken, ui/missing.html, is not a file inside the tool's folder",
                     "a web panel whose page is not there is not shown")
    }

    /// What a web panel's page asks of the app goes to the tool's program,
    /// under the tool's own `uses`.
    static func calls(_ suite: TestSuite) {
        let bench = Bench()
        bench.host.open(key("dashboard"), in: .window)
        bench.current.greets()
        bench.current.answers(2)
        var answers: [Result<JSONValue, RPCErrorObject>] = []
        bench.host.call(key("dashboard"), method: "notify/hud",
                        params: .object(["icon": .string("checkmark"), "message": .string("Saved")])) { answers.append($0) }
        let asked = JSONValue.object(["method": .string("notify/hud"),
                                      "params": .object(["icon": .string("checkmark"), "message": .string("Saved")])])
        suite.expect(bench.lastSent == .request(id: .number(3), method: "ui/event",
                                                params: .object(["panel": .string("dashboard"),
                                                                 "event": .string("bridge"), "value": asked])),
                     "a page's call is passed to the tool's program as ui/event, bridge, with the method and its params")
        bench.current.answers(3, #"{"reply":{"shown":true}}"#)
        suite.expect(answers == [.success(.object(["shown": .bool(true)]))], "the tool's reply is the call's answer")

        bench.host.call(key("dashboard"), method: "tool/refresh", params: nil) { answers.append($0) }
        bench.current.refuses(4, code: -32010)
        suite.expect(answers.last == .failure(RPCErrorObject(code: -32010, message: "no")),
                     "a method of the tool's own is passed on too, and a refusal is the call's answer")

        let sent = bench.current.sent.count
        bench.host.call(key("dashboard"), method: "clipboard/readText", params: nil) { answers.append($0) }
        bench.host.call(key("dashboard"), method: "island/draw", params: nil) { answers.append($0) }
        bench.host.call(key("dashboard"), method: "initialize", params: nil) { answers.append($0) }
        bench.host.call(key("dashboard"), method: "ui/render", params: nil) { answers.append($0) }
        bench.host.call(key("log"), method: "notify/beep", params: nil) { answers.append($0) }
        suite.expect(Array(answers.suffix(5)).map { if case .failure(let error) = $0 { return error.code } else { return 0 } }
                         == [-32001, -32601, -32601, -32601, -32602]
                         && bench.current.sent.count == sent,
                     "a call for a service the manifest does not list, one that is no request a tool makes, or from "
                         + "a panel that is not open, is refused and never reaches the tool")
        if case .failure(let error)? = answers.suffix(5).first {
            suite.expect(error.data == .object(["service": .string("clipboard.read")]),
                         "the refusal names the service, as the app's own does")
        }
    }

    static func aFloodOfCalls(_ suite: TestSuite) {
        var limits = ToolLimits()
        limits.messagesPerSecond = 5
        limits.floodSeconds = 3
        limits.answer = 100
        let bench = Bench(limits: limits)
        bench.host.open(key("dashboard"), in: .window)
        bench.current.greets()
        bench.current.answers(2)
        var codes: [Int] = []
        func calls(_ count: Int) {
            for _ in 0..<count {
                bench.host.call(key("dashboard"), method: "tool/ping", params: nil) {
                    if case .failure(let error) = $0 { codes.append(error.code) }
                }
            }
        }
        calls(5)
        suite.expect(codes.isEmpty, "as many calls in a second as the link allows lines are passed on")
        calls(1)
        suite.expect(codes == [-32004] && bench.stopped.isEmpty,
                     "one more in the same second is refused as not available, and the tool runs on")
        bench.clock.advance(by: 1)
        calls(6)
        bench.clock.advance(by: 1)
        calls(5)
        suite.expect(bench.stopped.isEmpty, "two busy seconds in a row are not yet a flood")
        calls(1)
        suite.expect(bench.stopped == [id] && bench.logged.last?.contains("too many calls") == true,
                     "three busy seconds in a row, as the link counts, are a flood: the tool is stopped")
    }

    static func badges(_ suite: TestSuite) {
        let bench = Bench()
        bench.host.badge(id, UIBadgeParams(count: 3))
        suite.expect(bench.host.badges[id] == .count(3), "a count is a count")
        bench.host.badge(id, UIBadgeParams(count: 0, dot: true))
        suite.expect(bench.host.badges[id] == .dot, "a count of nothing with a dot is a dot")
        bench.host.badge(id, UIBadgeParams())
        suite.expect(bench.host.badges[id] == nil, "neither is no badge")
    }

    /// The app's own reader hands a page back later, on the main thread:
    /// never in the call that asked for it.
    static func readAway(_ suite: TestSuite) {
        var read: Result<UITree, ToolPanelProblem>?
        var onMain = false
        ToolPanelHost.readAway(ToolPanelTests.json(page("away"))) {
            read = $0
            onMain = Thread.isMainThread
        }
        suite.expect(read == nil, "a page is not read in the call that asks for it")
        ToolRuntimeSupport.wait(upTo: 5) { read != nil }
        suite.expect((try? read?.get())?.blocks.count == 1 && onMain,
                     "it is read on a queue of its own and handed back on the main thread")
    }

    static func links(_ suite: TestSuite) {
        let bench = Bench.open()
        let page = URL(string: "https://example.com/deploys")!
        bench.host.follow(key("deploys"), page)
        suite.expect(bench.opened == [page] && bench.beeps == 0,
                     "a link block opens through the tool's own open service")
        bench.opens = false
        bench.host.follow(key("deploys"), page)
        suite.expect(bench.beeps == 1 && bench.logged.last == "the link https://example.com/deploys of the panel deploys was not opened",
                     "a link the service refuses plays the alert sound, and the log says so")
        bench.host.follow(key("deploys"), URL(string: "file:///etc/hosts")!)
        suite.expect(bench.opened.count == 2 && bench.beeps == 2,
                     "a link that is no web or mail address is never handed to the service")
        bench.host.follow(key("log"), page)
        suite.expect(bench.opened.count == 2, "a link of a panel that is not open does nothing")
    }
}

extension ToolPanelHostTests {
    static func status(_ state: StatusState, _ text: UIText? = nil, icon: String? = nil) -> UIStatusParams {
        UIStatusParams(state: state, text: text, icon: icon)
    }

    static func aStatusIsKeptAndReplaced(_ suite: TestSuite) {
        let bench = Bench()
        suite.expect(bench.host.statuses.isEmpty, "a tool that has said nothing has no status")
        suite.expect(bench.host.status(id, status(.busy, "Checks are running", icon: "arrow.triangle.branch")) == nil
                         && bench.host.statuses[id]
                         == ToolStatus(state: .busy, text: "Checks are running", icon: "arrow.triangle.branch"),
                     "a status is kept as the tool sent it: its state, its words and its glyph")
        bench.clock.advance(by: 1)
        suite.expect(bench.host.status(id, status(.failure, "main is red")) == nil
                         && bench.host.statuses[id] == ToolStatus(state: .failure, text: "main is red", icon: nil),
                     "each one replaces the last, glyph and all")
        suite.expect(bench.runs.isEmpty, "keeping a status starts nothing")
    }

    static func noneTakesItAway(_ suite: TestSuite) {
        let bench = Bench()
        bench.host.status(id, status(.ok))
        bench.clock.advance(by: 1)
        suite.expect(bench.host.status(id, status(.none, "gone", icon: "xmark")) == nil && bench.host.statuses[id] == nil,
                     "none takes the status away, whatever came with it")
        bench.clock.advance(by: 1)
        suite.expect(bench.host.status(id, status(.none)) == nil && bench.host.statuses.isEmpty,
                     "and none for a tool with no status changes nothing")
    }

    static func anUndeclaredStatusIsRefused(_ suite: TestSuite) {
        let bench = Bench(declaresStatus: false)
        suite.expect(bench.host.status(id, status(.failure, "main is red")) == .noStatus && bench.host.statuses.isEmpty,
                     "a status from a tool whose manifest declares none is refused, and none is kept")
        suite.expect(bench.host.status(id, status(.none)) == .noStatus,
                     "taking one away is refused the same: the tool has none to take")
        suite.expect(ToolPanelHost.Refusal.noStatus.error
                         == RPCErrorObject(code: -32602, message: "the manifest declares no status"),
                     "the refusal is the protocol's invalid params, -32602, and says why")
        let stranger = ToolID("com.acme.nobody")!
        suite.expect(bench.host.status(stranger, status(.ok)) == .noStatus && bench.host.statuses.isEmpty,
                     "and so is one from a tool the app does not have")
    }

    static func aStatusGoesWhenTheProgramEnds(_ suite: TestSuite) {
        let bench = Bench.open()
        bench.host.status(id, status(.failure, "main is red"))
        bench.host.badge(id, UIBadgeParams(count: 2))
        bench.current.ends(1)
        suite.expect(bench.host.statuses[id] == nil,
                     "a status goes when the tool's program ends, at once: it never outlives its program")
        suite.expect(bench.host.badges[id] == .count(2), "the badge stays, as it always did")

        // One that was waiting for its second to be up goes too, and does
        // not come back when the second is.
        let waiting = Bench.open()
        waiting.host.status(id, status(.ok))
        waiting.host.status(id, status(.failure))
        waiting.current.ends(0)
        waiting.clock.advance(by: 2)
        suite.expect(waiting.host.statuses[id] == nil && waiting.clock.waiting == 0,
                     "a status that was waiting to be shown is dropped with the program, and no timer is left")
    }

    static func aStatusGoesWhenTheToolIsForgotten(_ suite: TestSuite) {
        let bench = Bench()
        bench.host.status(id, status(.attention, "A check is waiting for approval"))
        bench.host.forget(id)
        suite.expect(bench.host.statuses[id] == nil,
                     "a tool that is switched off, updated or removed takes its status with it")
    }

    static func changesArePublishedOnceASecond(_ suite: TestSuite) {
        let bench = Bench()
        var published: [StatusState?] = []
        let watching = bench.host.$statuses.dropFirst().sink { published.append($0[id]?.state) }
        defer { watching.cancel() }
        bench.host.status(id, status(.busy))
        suite.expect(published == [.busy], "the first status after a quiet while is shown at once")
        bench.clock.advance(by: 0.2)
        bench.host.status(id, status(.ok))
        bench.clock.advance(by: 0.2)
        bench.host.status(id, status(.attention))
        bench.host.status(id, status(.busy))
        bench.clock.advance(by: 0.2)
        bench.host.status(id, status(.failure, "main is red"))
        suite.expect(published == [.busy] && bench.host.statuses[id]?.state == .busy && bench.clock.waiting == 1,
                     "four more within the second are not shown yet, and one timer waits for all of them")
        bench.clock.advance(by: 0.39)
        suite.expect(published == [.busy], "not before the second is up")
        bench.clock.advance(by: 0.02)
        suite.expect(published == [.busy, .failure]
                         && bench.host.statuses[id] == ToolStatus(state: .failure, text: "main is red", icon: nil)
                         && bench.clock.waiting == 0,
                     "when the second is up the newest is shown, once: of five, the first and the last")
        bench.clock.advance(by: 0.5)
        bench.host.status(id, status(.none))
        suite.expect(published == [.busy, .failure], "taking a status away within the second waits its turn too")
        bench.clock.advance(by: 0.5)
        suite.expect(published == [.busy, .failure, nil] && bench.host.statuses[id] == nil, "and is then done")
        bench.clock.advance(by: 5)
        bench.host.status(id, status(.ok))
        suite.expect(published.last == .ok && published.count == 4, "after a quiet while the next is shown at once again")
    }
}

/// A status's few words: kept for a tool that declares them, left out for
/// one that does not, and gone with the status.
extension ToolPanelHostTests {
    static let start = Date(timeIntervalSince1970: 1_760_450_400.5)

    static func worded(_ state: StatusState, activity: UIText? = "3", since: Double? = nil) -> UIStatusParams {
        UIStatusParams(state: state, text: "Checks are running", activity: activity, since: since)
    }

    static func declaredWordsAreKept(_ suite: TestSuite) {
        let bench = Bench(declaresActivity: true)
        suite.expect(bench.host.status(id, worded(.busy, since: 1_760_450_400.5)) == nil
                         && bench.host.statuses[id] == ToolStatus(state: .busy, text: "Checks are running", icon: nil,
                                                                  activity: "3", since: start)
                         && bench.logged.isEmpty,
                     "a tool that declares its words has them kept with its status, its start time too")
    }

    static func undeclaredWordsAreLeftOutAndTheMarkStays(_ suite: TestSuite) {
        let bench = Bench()
        let leftOut = "the words of its status were left out: the manifest does not declare them"
        suite.expect(bench.host.status(id, worded(.busy)) == nil
                         && bench.host.statuses[id] == ToolStatus(state: .busy, text: "Checks are running", icon: nil),
                     "a status with words its tool did not declare is kept without them, and answered with no "
                         + "refusal: the mark is drawn")
        bench.clock.advance(by: 1)
        bench.host.status(id, worded(.failure, activity: nil, since: 12))
        suite.expect(bench.host.statuses[id] == ToolStatus(state: .failure, text: "Checks are running", icon: nil)
                         && bench.logged == [leftOut],
                     "a start time is left out the same, and the tool's log says so once for the run")
        bench.host.toolEnded(id)
        bench.host.status(id, worded(.busy))
        suite.expect(bench.logged == [leftOut, leftOut], "and once again for the program's next run")
    }

    static func aStatusWithoutWordsTakesThemAway(_ suite: TestSuite) {
        let bench = Bench(declaresActivity: true)
        bench.host.status(id, worded(.busy, since: 1_760_450_400.5))
        bench.clock.advance(by: 1)
        bench.host.status(id, status(.busy, "Checks are running"))
        suite.expect(bench.host.statuses[id] == ToolStatus(state: .busy, text: "Checks are running", icon: nil),
                     "each status replaces all of the last: one without words takes them away, and the mark stays")
        bench.clock.advance(by: 1)
        bench.host.status(id, worded(.none))
        suite.expect(bench.host.statuses[id] == nil, "none takes the mark and any words with it")
    }

    static func theWordsGoWithTheProgram(_ suite: TestSuite) {
        let bench = Bench(declaresActivity: true)
        bench.host.status(id, worded(.busy))
        bench.host.toolEnded(id)
        suite.expect(bench.host.statuses[id] == nil, "a status's words go with its program, as the mark does")
        let forgotten = Bench(declaresActivity: true)
        forgotten.host.status(id, worded(.busy))
        forgotten.host.forget(id)
        suite.expect(forgotten.host.statuses[id] == nil, "and with a tool that is switched off, updated or removed")
    }

    static func noticesAndTheSlot(_ suite: TestSuite) {
        let plain = Bench()
        plain.host.notice(id, NotifyNoticeParams(icon: "bell", title: "Done", detail: "All green", system: true))
        suite.expect(plain.notices == [NotifyNoticeParams(icon: "bell", title: "Done", detail: "All green", system: true)],
                     "a notice is shown as the tool sent it, the macOS notification asked for with it")
        suite.expect(plain.host.dock(id) == .noSlot && plain.docks == 0,
                     "a tool whose manifest declares no slot is refused ui/dock, and the island does not open")
        suite.expect(plain.host.dock(ToolID("com.acme.nobody")!) == .noSlot && plain.docks == 0,
                     "and so is a tool nobody added")
        suite.expect(ToolPanelHost.Refusal.noSlot.error
                         == RPCErrorObject(code: -32602, message: "the manifest declares no slot"),
                     "the refusal is invalid params, and says why")
        let docked = Bench(declaresSlot: true)
        suite.expect(docked.described.slot == .agents && plain.described.slot == nil,
                     "the manifest's slot is read")
        suite.expect(docked.host.dock(id) == nil && docked.docks == 1,
                     "a tool in the Agents slot that asks for it opens the island on it")
        // The program is not running yet: it is told nothing, and nothing
        // is started for it.
        docked.tool.slot(UISlotParams(visible: true, x: 1, y: 2, width: 3, height: 4))
        suite.expect(docked.runs.isEmpty, "a tool that is not running is not started to be told where its slot is")
        docked.host.open(key("deploys"), in: .island)
        docked.current.greets()
        docked.tool.slot(UISlotParams(visible: false, popOut: true))
        var told: JSONValue?
        if case .notice("ui/slot", let params)? = docked.current.sent.last { told = params }
        suite.expect(told == .object(["visible": .bool(false), "popOut": .bool(true)]),
                     "a running tool is told, as a notice: \(String(describing: docked.current.sent.last))")
    }
}
