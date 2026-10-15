// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianUI

/// What the catalog's screens say, as plain values: the sheet, the line the
/// agreement sheet adds, the refusals, and "Update available". No test draws
/// a view.
enum CatalogueScreensTests {
    static func run(_ suite: TestSuite) {
        theSheet(suite)
        theAgreement(suite)
        refusals(suite)
        rowsAndDetail(suite)
    }

    static let english = FeatureStrings.externalTools(.enUS)

    static func content(_ rig: CatalogueWatchTests.Rig, language: AppLanguage = .enUS) -> CatalogueSheetContent {
        CatalogueSheetContent(state: rig.watch.state, entries: rig.watch.entries, listed: rig.bench.store.listed,
                              update: rig.watch.update(for:), language: language,
                              strings: FeatureStrings.externalTools(language), close: "Close")
    }

    static func rows(_ content: CatalogueSheetContent) -> [CatalogueRow] {
        if case .rows(let rows) = content.body { return rows }
        return []
    }

    static func theSheet(_ suite: TestSuite) {
        let empty = CatalogueWatchTests.Rig()
        defer { empty.close() }
        let before = content(empty).body
        empty.serve([])
        empty.watch.refresh()
        suite.expect(before == .loading && content(empty).body == .message("There are no extensions or tools in the catalog yet.")
                         && content(empty).title == "The Vitruvian catalog",
                     "before the list arrives the sheet waits; an empty list says so in one line")
        empty.fetcher.answers = [:]
        let other = CatalogueWatchTests.Rig()
        defer { other.close() }
        other.watch.refresh()
        suite.expect(content(other).body == .message(english.catalogUnreachable),
                     "a list that cannot be fetched is one sentence in its place")

        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        rig.install()
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"]),
                   CatalogueFixtures.entry(["id": "com.acme.other", "name": ["en": "Other", "fr": "Autre"],
                                            "uses": ["keystrokes"]])])
        rig.watch.refresh()
        let listed = rows(content(rig))
        suite.expect(listed.map(\.action) == [.update, .install] && listed.map(\.actionText) == ["Update", "Install"]
                         && listed.first?.byline == "Acme · 1.3.0"
                         && listed.first?.summary == "Copies the address of your latest deploy."
                         && listed.last?.uses == ["Paste and press menu commands in other apps"]
                         && rows(content(rig, language: .fr)).last?.name == "Autre",
                     "each tool is listed with its name, publisher, version, summary and what it says it uses, and "
                         + "Install, or Update when a newer version of one installed from the catalog is listed")

        let byHand = CatalogueWatchTests.Rig()
        defer { byHand.close() }
        byHand.install(fromCatalog: false)
        byHand.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        byHand.watch.refresh()
        suite.expect(rows(content(byHand)).map(\.action) == [.installed]
                         && rows(content(byHand)).first?.actionText == "Installed",
                     "a tool added from a folder with the same id is shown as installed, and never offered as an update")
        byHand.serve([CatalogueFixtures.entry()], signer: .init(), etag: "\"x\"")
        byHand.watch.refresh()
        suite.expect(content(byHand).body == .message(english.catalogNotOurs),
                     "a list that is not ours is one sentence, and no tool is offered")
    }

    static func theAgreement(_ suite: TestSuite) {
        let rig = CatalogueInstallerTests.Rig()
        defer { rig.close() }
        guard case .success(let offer)? = rig.prepare(rig.entry(TestZip.tool())),
              case .success(let picked) = rig.bench.store.offer(from: rig.bench.folder()) else {
            suite.expect(false, "a tool from the catalog and a folder are offered")
            return
        }
        let fromCatalog = ToolAgreementContent(offer: offer, language: .enUS, strings: english, cancel: "Cancel")
        let fromFolder = ToolAgreementContent(offer: picked, language: .enUS, strings: english, cancel: "Cancel",
                                              home: rig.bench.root.path)
        suite.expect(fromCatalog.catalogue == english.agreeCatalog
                         && fromCatalog.from == "From github.com/acme/deploys"
                         && fromCatalog.headline == english.agreeHeadline && fromCatalog.agree == "Add Tool"
                         && ToolAgreementContent.defaultChoice == .cancel && fromCatalog.initialFocus == .cancel,
                     "a tool from the catalog is asked about on the same sheet, with one more line, its source as "
                         + "where it is from, and Cancel still the default")
        suite.expect(fromFolder.catalogue == nil && fromFolder.from == "From ~/picked",
                     "a folder the person picked is asked about as before")
        rig.installer.finished(with: offer)
    }

    static func refusals(_ suite: TestSuite) {
        let said: [(CatalogueRefusal, String)] = [
            (.unreachable, english.catalogUnreachable),
            (.mismatch, english.downloadMismatch),
            (.notTheTool, english.downloadNotTheTool),
        ]
        let wrong = said.filter { refusal, message in
            ToolRefusalMessage(catalogue: refusal, name: "Deploys", language: .enUS, strings: english)
                != ToolRefusalMessage(title: "“Deploys” was not installed", message: message)
        }
        suite.expect(wrong.isEmpty, "each refusal of a download is one plain sentence under a title that names the tool")
        let store = ToolRefusalMessage(catalogue: .store(.tooBig(bytes: 256 * 1_048_576, items: 10_000)), name: "Deploys",
                                       language: .enUS, strings: english)
        let folder = ToolRefusalMessage(.tooBig(bytes: 256 * 1_048_576, items: 10_000), language: .enUS,
                                        strings: english, numbers: Locale(identifier: "en_US"))
        suite.expect(store.title == "“Deploys” was not installed" && folder.title == "This folder can’t be added"
                         && store.message.hasPrefix("The folder is too large."),
                     "a refusal of the store's says what it says for a folder, under the catalog's title")
    }

    static func rowsAndDetail(_ suite: TestSuite) {
        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        rig.install()
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        rig.watch.refresh()
        let row = ExternalToolRow.all(store: rig.bench.store, language: .enUS, strings: english, watch: rig.watch).first
        let detail = ExternalToolDetail(rig.bench.store.listed[0], files: nil, language: .enUS, strings: english,
                                        updateAvailable: rig.watch.update(for: rig.bench.store.listed[0]) != nil)
        let plain = ExternalToolDetail(rig.bench.store.listed[0], files: nil, language: .enUS, strings: english)
        suite.expect(row?.updateText == "Update available" && detail.row.updateText == "Update available"
                         && detail.updateNow == "Update" && plain.updateNow == nil && plain.row.updateText == nil
                         && detail.initialFocus == .close,
                     "a tool from the catalog with a newer version says Update available in its row and its detail, "
                         + "which offers Update; the detail still opens on Close")
    }
}
