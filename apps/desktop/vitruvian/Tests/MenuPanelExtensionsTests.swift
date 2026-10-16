// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// The menu bar panel's Extensions tab: its place among the panel's saved
/// sections, when it shows by default, the switch each extension has for it,
/// which extensions it lists, and the one page an extension's island panel
/// is whether the island, the tab, or both show it.
enum MenuPanelExtensionsTests {
    static func run(_ suite: TestSuite) {
        theSectionHasANewSavedName(suite)
        itShowsByDefaultOnlyWithAnIslandPage(suite)
        eachExtensionHasASwitchThatIsSaved(suite)
        savedLayoutsStillRead(suite)
        itListsOnlyIslandPages(suite)
        theTabOpensAPageTheIslandDoesNotHave(suite)
        theIslandAndTheTabShareOnePage(suite)
        twoViewsOfTheTabShareOnePage(suite)
        whatThePersonDoesInTheTabReachesTheTool(suite)
        aPageEndsWithItsToolInTheTabToo(suite)
        theIslandKeepsAWebPage(suite)
        anUpdatedExtensionIsAskedAgain(suite)
        whetherAnyExtensionHasAnIslandPageIsKnownOncePerChange(suite)
    }

    /// The names saved in a layout before the tab existed.
    static let earlierSections = ["keepAwake", "brightness", "mixer", "system", "network", "disk", "power",
                                  "fanControl", "utilities", "controls", "toggles", "wallpaper"]

    /// Preferences of their own, empty, for one check.
    static func withDefaults(_ name: String, _ body: (UserDefaults) -> Void) {
        let domain = "com.vitruviansoftware.vitruvian.tests.menu-extensions.\(name)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        body(defaults)
    }

    static func theSectionHasANewSavedName(_ suite: TestSuite) {
        suite.expect(PanelSectionID.extensions.rawValue == "extensions"
                         && PanelSectionID(rawValue: "extensions") == .extensions,
                     "the Extensions tab is saved in a layout as \"extensions\"")
        suite.expect(PanelSectionID.allCases.map(\.rawValue) == earlierSections + ["extensions"],
                     "every section saved before keeps its name, and the new one comes last")
        suite.expect(PanelSectionID.extensions.visibilityKey == DefaultsKey.panelShowExtensions
                         && PanelSectionID.extensions.symbolName == ExternalToolManifest.defaultSymbol,
                     "the tab has a switch of its own and the extensions' symbol")
        suite.expect(PanelSectionID.extensions.isAvailable && PanelSectionID.extensions.featureGate.isEmpty,
                     "no hub feature keeps the tab: an extension is added in Settings, so the tab is always there "
                         + "to switch on")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.panelShowExtensions,
                                                                        DefaultsKey.panelHiddenExtensions]),
                     "the tab's switch and the extensions switched off for it go into a settings backup")
    }

    static func itShowsByDefaultOnlyWithAnIslandPage(_ suite: TestSuite) {
        suite.expect(!PanelSectionID.extensions.shownByDefault(anyIslandPanel: false)
                         && PanelSectionID.extensions.shownByDefault(anyIslandPanel: true),
                     "the Extensions tab is on by default only while an extension has an island page")
        suite.expect(PanelSectionID.allCases.filter { $0 != .extensions }
                         .allSatisfy { $0.shownByDefault(anyIslandPanel: false) && $0.shownByDefault(anyIslandPanel: true) },
                     "every other tab is on by default, extensions or not")
        withDefaults("default") { defaults in
            suite.expect(!PanelLayout.isShown(.extensions, in: defaults, shownByDefault: false)
                             && PanelLayout.isShown(.extensions, in: defaults, shownByDefault: true),
                         "with no choice made, the tab follows its default")
            defaults.set(true, forKey: DefaultsKey.panelShowExtensions)
            suite.expect(PanelLayout.isShown(.extensions, in: defaults, shownByDefault: false),
                         "switched on, it shows with no extension to show")
            defaults.set(false, forKey: DefaultsKey.panelShowExtensions)
            suite.expect(!PanelLayout.isShown(.extensions, in: defaults, shownByDefault: true),
                         "switched off, it stays off when an extension with an island page is added")
        }
    }

    static func eachExtensionHasASwitchThatIsSaved(_ suite: TestSuite) {
        let deploys = ToolID("com.acme.deploys")!
        let board = ToolID("com.acme.board")!
        let notes = ToolID("com.acme.notes")!
        withDefaults("switches") { defaults in
            suite.expect(MenuPanelExtensionsSupport.isShown(deploys, in: defaults)
                             && defaults.object(forKey: DefaultsKey.panelHiddenExtensions) == nil,
                         "an extension is in the tab until the person turns it off, and nothing is saved for that")
            MenuPanelExtensionsSupport.setShown(false, for: deploys, in: defaults)
            MenuPanelExtensionsSupport.setShown(false, for: board, in: defaults)
            suite.expect(defaults.string(forKey: DefaultsKey.panelHiddenExtensions) == "com.acme.board,com.acme.deploys",
                         "the extensions turned off are saved as their ids, in order")
            let again = UserDefaults(suiteName: "com.vitruviansoftware.vitruvian.tests.menu-extensions.switches")!
            suite.expect(!MenuPanelExtensionsSupport.isShown(deploys, in: again)
                             && !MenuPanelExtensionsSupport.isShown(board, in: again)
                             && MenuPanelExtensionsSupport.isShown(notes, in: again),
                         "the choice is read back from the saved preferences")
            suite.expect(MenuPanelExtensionsSupport.shown([notes, deploys, board], in: defaults) == [notes],
                         "the tab keeps the ones still on, in the order given")
            MenuPanelExtensionsSupport.setShown(true, for: deploys, in: defaults)
            MenuPanelExtensionsSupport.setShown(true, for: board, in: defaults)
            suite.expect(defaults.object(forKey: DefaultsKey.panelHiddenExtensions) == nil,
                         "with every extension on again, nothing is saved")
            defaults.set("com.acme.deploys,../x,,.bad", forKey: DefaultsKey.panelHiddenExtensions)
            suite.expect(MenuPanelExtensionsSupport.hidden(in: defaults) == [deploys],
                         "an id that is not well formed is dropped when read")
        }
    }

    static func savedLayoutsStillRead(_ suite: TestSuite) {
        withDefaults("layouts") { defaults in
            suite.expect(PanelLayout.order(in: defaults) == PanelSectionID.allCases,
                         "with nothing saved, the tab is the last one")
            let mine = ["wallpaper", "keepAwake", "mixer", "system", "network", "disk", "power",
                        "fanControl", "utilities", "controls", "toggles", "brightness"]
            defaults.set(mine.joined(separator: ","), forKey: DefaultsKey.panelSectionOrder)
            suite.expect(PanelLayout.order(in: defaults).map(\.rawValue) == mine + ["extensions"],
                         "a layout saved before the tab existed keeps its order, and the tab is added at its end")
            defaults.set("toggles,extensions,keepAwake,bogus", forKey: DefaultsKey.panelSectionOrder)
            let order = PanelLayout.order(in: defaults)
            suite.expect(Array(order.prefix(3)) == [.toggles, .extensions, .keepAwake]
                             && order.count == PanelSectionID.allCases.count && Set(order) == Set(PanelSectionID.allCases),
                     "a saved place for the tab is kept, a name the app does not know is dropped, and no section is lost")
            defaults.set("mixer,system", forKey: DefaultsKey.panelCollapsedSections)
            suite.expect(PanelLayout.isCollapsed(.mixer, in: defaults) && !PanelLayout.isCollapsed(.extensions, in: defaults),
                         "a saved set of collapsed sections reads as before, and the tab is open")
        }
    }

    /// Adds three extensions to a store: one with an island page, one with
    /// a page in Settings only, and one of protocol 1 with no page; then a
    /// second one with an island page.
    static func addExtensions(to bench: ExternalToolStoreTests.Bench) {
        bench.add(bench.folder(manifest: ExternalToolManifestTests.file(#"""
            {"protocol": "2", "uses": ["notify"], "contributes": {"panels": [
              {"id": "deploys", "title": {"en": "Deploys"}, "placement": "island"},
              {"id": "settings", "title": {"en": "Deploys"}, "placement": "settings"}]}}
            """#)))
        bench.add(bench.folder("settings-only", manifest: ExternalToolManifestTests.file(#"""
            {"id": "com.acme.settingsonly", "protocol": "2", "uses": ["notify"], "contributes": {"panels": [
              {"id": "options", "title": {"en": "Options"}, "placement": "settings"}]}}
            """#)))
        bench.add(bench.folder("plain", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.plain"}"#)))
        bench.add(bench.folder("board", manifest: ExternalToolManifestTests.file(#"""
            {"id": "com.acme.board", "name": {"en": "Board"}, "protocol": "2", "uses": ["notify"],
             "contributes": {"panels": [{"id": "board", "title": {"en": "Today"}, "placement": "island", "icon": "list.bullet"}]}}
            """#)))
    }

    static func itListsOnlyIslandPages(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let deploys = ToolPanelHost.Key(tool: ToolID("com.acme.deploys")!, panel: "deploys")
        let board = ToolPanelHost.Key(tool: ToolID("com.acme.board")!, panel: "board")
        suite.expect(MenuPanelExtensions.available(store: bench.store, language: .enUS).isEmpty,
                     "with no extension added, the tab has nothing to list")
        addExtensions(to: bench)
        let listed = MenuPanelExtensions.available(store: bench.store, language: .enUS)
        suite.expect(listed.map(\.key) == [deploys, board],
                     "the tab lists the extensions with an island page, in the order they were added, and not one "
                         + "with a page in Settings only or with no page")
        suite.expect(listed.map(\.name) == ["Deploys", "Board"]
                         && MenuPanelExtensions.available(store: bench.store, language: .fr).first?.name == "Déploiements"
                         && listed.map(\.symbol) == ["shippingbox", "list.bullet"],
                     "each is named with the extension's name in the person's language, and drawn with its page's symbol")
        bench.store.setShowsInIsland(deploys.tool, false)
        suite.expect(MenuPanelExtensions.available(store: bench.store, language: .enUS).map(\.key) == [deploys, board],
                     "hiding a page from the island leaves it in the tab, which has a switch of its own")
        bench.store.setOn(board.tool, false)
        suite.expect(MenuPanelExtensions.available(store: bench.store, language: .enUS).map(\.key) == [deploys],
                     "an extension that is switched off is not listed")
        withDefaults("listed") { defaults in
            suite.expect(MenuPanelExtensions.shown(store: bench.store, defaults: defaults, language: .enUS).map(\.key) == [deploys],
                         "every listed extension shows until it is turned off")
            MenuPanelExtensionsSupport.setShown(false, for: deploys.tool, in: defaults)
            suite.expect(MenuPanelExtensions.shown(store: bench.store, defaults: defaults, language: .enUS).isEmpty
                             && MenuPanelExtensions.available(store: bench.store, language: .enUS).map(\.key) == [deploys],
                         "one turned off leaves the tab and stays in Settings, where it can be turned on again")
        }
    }

    // MARK: - One page, whichever place shows it

    typealias Bench = ToolPanelHostTests.Bench

    static func key(_ panel: String) -> ToolPanelHost.Key { ToolPanelHostTests.key(panel) }

    /// How many times the tool was asked for a panel's page.
    static func opens(_ bench: Bench) -> Int {
        bench.runs.flatMap(\.sent).filter {
            if case .request(_, "ui/open", _) = $0 { return true }
            return false
        }.count
    }

    /// How many times the tool was told a panel closed.
    static func closes(_ bench: Bench) -> Int {
        bench.runs.flatMap(\.sent).filter { $0 == .notice(method: "ui/close", params: .object(["panel": .string("deploys")])) }.count
    }

    /// The tab opens the island page, which the tool answers.
    static func openedInTheTab() -> Bench {
        let bench = Bench()
        bench.host.openInMenuPanel(key("deploys"))
        bench.current.greets()
        if let asked = bench.current.lastRequest {
            bench.current.answers(asked, #"{"tree":\#(ToolPanelHostTests.page("first"))}"#)
        }
        return bench
    }

    static func theTabOpensAPageTheIslandDoesNotHave(_ suite: TestSuite) {
        let bench = Bench()
        suite.expect(bench.host.openInMenuPanel(key("settings")) == .wrongPlace("settings")
                         && bench.host.openInMenuPanel(key("nothing")) == .unknownPanel("nothing")
                         && bench.host.shown.isEmpty && bench.runs.isEmpty,
                     "the tab shows only island pages: any other panel is refused, and nothing starts")
        suite.expect(bench.host.openInMenuPanel(key("deploys")) == nil
                         && bench.host.shown[key("deploys")] == .waiting && bench.host.island == nil,
                     "the tab opens an extension's island page, waiting for its first page, without making it the "
                         + "island's page")
        bench.current.greets()
        if let asked = bench.current.lastRequest {
            bench.current.answers(asked, #"{"tree":\#(ToolPanelHostTests.page("Today"))}"#)
        }
        suite.expect(ToolPanelHostTests.text(bench.host.shown[key("deploys")]) == "Today" && opens(bench) == 1,
                     "the tool is asked once, as the island asks, and its page is drawn")
        bench.host.closeInMenuPanel(key("deploys"))
        suite.expect(bench.host.shown[key("deploys")] == nil && closes(bench) == 1,
                     "when the tab lets go of it, the page closes and the tool is told")
    }

    static func theIslandAndTheTabShareOnePage(_ suite: TestSuite) {
        let bench = openedInTheTab()
        suite.expect(bench.host.open(key("deploys"), in: .island) == nil && bench.host.island == key("deploys")
                         && opens(bench) == 1,
                     "the island opening a page the tab has open makes it the island's page, asking nothing")
        bench.host.close(key("deploys"))
        suite.expect(ToolPanelHostTests.text(bench.host.shown[key("deploys")]) == "first" && bench.host.island == nil
                         && closes(bench) == 0,
                     "the island letting go leaves the tab's page open, and the tool is not told")
        bench.host.closeInMenuPanel(key("deploys"))
        suite.expect(bench.host.shown[key("deploys")] == nil && closes(bench) == 1,
                     "the tab letting go last closes the page and tells the tool once")

        let islandFirst = Bench.open()
        islandFirst.host.openInMenuPanel(key("deploys"))
        suite.expect(opens(islandFirst) == 1 && ToolPanelHostTests.text(islandFirst.host.shown[key("deploys")]) == "first",
                     "the tab shows the page the island has open as it is, asking nothing")
        islandFirst.host.closeInMenuPanel(key("deploys"))
        suite.expect(islandFirst.host.island == key("deploys") && islandFirst.host.shown[key("deploys")] != nil
                         && closes(islandFirst) == 0,
                     "the tab letting go leaves the island's page open")
        islandFirst.host.close(key("deploys"))
        suite.expect(islandFirst.host.shown[key("deploys")] == nil && closes(islandFirst) == 1,
                     "and the island closing it then closes it")
    }

    static func twoViewsOfTheTabShareOnePage(_ suite: TestSuite) {
        let bench = openedInTheTab()
        bench.host.openInMenuPanel(key("deploys"))
        suite.expect(opens(bench) == 1 && bench.host.inMenuPanel[key("deploys")] == 2,
                     "a second view of the tab, the popover's and the island's copy, shares the page")
        bench.host.closeInMenuPanel(key("deploys"))
        suite.expect(bench.host.shown[key("deploys")] != nil && closes(bench) == 0,
                     "one of them letting go leaves the page open for the other")
        bench.host.closeInMenuPanel(key("deploys"))
        bench.host.closeInMenuPanel(key("deploys"))
        suite.expect(bench.host.shown[key("deploys")] == nil && closes(bench) == 1,
                     "the last closes it, once, and a further let-go does nothing")
    }

    static func whatThePersonDoesInTheTabReachesTheTool(_ suite: TestSuite) {
        let bench = openedInTheTab()
        bench.host.open(key("deploys"), in: .island)
        suite.expect(bench.host.act(key("deploys"), block: "again", event: .tap) == nil
                         && bench.lastSent == .request(id: .number(3), method: "ui/event",
                                                       params: .object(["panel": .string("deploys"),
                                                                        "block": .string("again"),
                                                                        "event": .string("tap")])),
                     "a tap in the tab is the same ui/event the island sends")
        bench.current.answers(3, #"{"tree":\#(ToolPanelHostTests.page("Deploying"))}"#)
        suite.expect(ToolPanelHostTests.text(bench.host.shown[key("deploys")]) == "Deploying",
                     "and its answer is the one page both the island and the tab draw")
    }

    static func aPageEndsWithItsToolInTheTabToo(_ suite: TestSuite) {
        let bench = openedInTheTab()
        bench.current.ends(0)
        suite.expect(bench.host.shown[key("deploys")] == nil && bench.host.inMenuPanel.isEmpty,
                     "a page the tab shows ends with its tool's program")
        let sent = bench.runs.flatMap(\.sent).count
        bench.host.closeInMenuPanel(key("deploys"))
        suite.expect(bench.runs.flatMap(\.sent).count == sent && bench.host.shown.isEmpty,
                     "and the tab letting go afterwards sends nothing")
    }

    // MARK: - Review fixes

    static func theIslandKeepsAWebPage(_ suite: TestSuite) {
        let page = URL(fileURLWithPath: "/tmp/tool/ui/index.html")
        let folder = URL(fileURLWithPath: "/tmp/tool", isDirectory: true)
        let web = ToolPanelHost.Shown.web(page: page, folder: folder)
        let deploys = key("deploys")
        suite.expect(ToolPanelHost.defersToIsland(deploys, shown: web, island: deploys),
                     "a web page the island shows is a line in the tab, so the island keeps its one web view")
        suite.expect(!ToolPanelHost.defersToIsland(deploys, shown: web, island: nil)
                         && !ToolPanelHost.defersToIsland(deploys, shown: web, island: key("other")),
                     "the tab draws the web page itself while the island does not show it")
        suite.expect(!ToolPanelHost.defersToIsland(deploys, shown: .page(UITree(blocks: [])), island: deploys)
                         && !ToolPanelHost.defersToIsland(deploys, shown: .waiting, island: deploys),
                     "a page of blocks shows in both places at once")
        let bench = Bench.open()
        bench.host.openInMenuPanel(deploys)
        suite.expect(!bench.host.defersToIsland(deploys),
                     "the host asks the rule with what it shows: a page of blocks the island has open")
    }

    static func anUpdatedExtensionIsAskedAgain(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        addExtensions(to: bench)
        let deploys = ToolID("com.acme.deploys")!
        let before = MenuPanelExtensions.available(store: bench.store, language: .enUS).first
        bench.store.setOn(deploys, false)
        bench.store.setOn(deploys, true)
        let after = MenuPanelExtensions.available(store: bench.store, language: .enUS).first { $0.key.tool == deploys }
        suite.expect(before?.key == after?.key && before?.id != after?.id && before.map { $0.activation + 1 } == after?.activation,
                     "an extension handed to the host again is another entry, so its card asks for its page anew")
    }

    static func whetherAnyExtensionHasAnIslandPageIsKnownOncePerChange(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        suite.expect(!bench.store.hasIslandPanels, "with no extension added, none has an island page")
        addExtensions(to: bench)
        suite.expect(bench.store.hasIslandPanels, "an extension with an island page added is known at once")
        bench.store.setOn(ToolID("com.acme.deploys")!, false)
        bench.store.setOn(ToolID("com.acme.board")!, false)
        suite.expect(!bench.store.hasIslandPanels,
                     "with both switched off, none has one: the answer is worked out again after each change")
    }
}
