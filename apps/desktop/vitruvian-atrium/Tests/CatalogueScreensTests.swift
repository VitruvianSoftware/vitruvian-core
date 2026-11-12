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
                              strings: FeatureStrings.externalTools(language))
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
                                            "uses": ["keystrokes"], "panels": [] as [String]]),
                   CatalogueFixtures.entry(["id": "com.acme.github", "name": ["en": "GitHub"],
                                            "panels": ["island", "settings"]])])
        rig.watch.refresh()
        let listed = rows(content(rig))
        suite.expect(listed.map(\.action) == [.update, .install, .install]
                         && listed.map(\.actionText) == ["Update", "Install", "Install"]
                         && listed.map(\.kindBadge) == [nil, "Tool", "Extension"]
                         && rows(content(rig, language: .fr)).map(\.kindBadge) == [nil, "Outil", "Module d’extension"]
                         && listed.first?.byline == "Acme · 1.3.0"
                         && listed.first?.summary == "Copies the address of your latest deploy."
                         && listed[1].uses == ["Paste and press menu commands in other apps"]
                         && rows(content(rig, language: .fr))[1].name == "Autre",
                     "each tool is listed with its name, publisher, version, kind pill when its entry carries panels, "
                         + "summary and what it says it uses, and Install, or Update when a newer version of one "
                         + "installed from the catalog is listed")

        let byHand = CatalogueWatchTests.Rig()
        defer { byHand.close() }
        byHand.install(fromCatalog: false)
        byHand.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        byHand.watch.refresh()
        let newer = rows(content(byHand))
        byHand.serve([CatalogueFixtures.entry()], generated: "2026-11-03T10:00:00Z", etag: "\"s\"")
        byHand.watch.refresh()
        suite.expect(newer.map(\.action) == [.update] && newer.first?.actionText == "Update from the catalog"
                         && rows(content(byHand)).map(\.action) == [.installed]
                         && rows(content(byHand)).first?.actionText == "Installed",
                     "a tool added from a folder with the same id is offered the catalog's newer version as "
                         + "\"Update from the catalog\", and at the same version is shown as installed")
        byHand.serve([CatalogueFixtures.entry()], generated: "2026-11-04T10:00:00Z", signer: .init(), etag: "\"x\"")
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
        suite.expect(fromCatalog.movesToCatalogue == nil && fromFolder.movesToCatalogue == nil,
                     "a first install from the catalog, and a folder, say nothing of a move to the catalog")
        rig.installer.finished(with: offer)

        // A tool added from a folder, then offered from the catalog.
        let moving = CatalogueInstallerTests.Rig()
        defer { moving.close() }
        let added = moving.bench.folder("Remote")
        moving.bench.add(added)
        guard case .success(let move)? = moving.prepare(moving.entry(TestZip.tool(version: "1.3.0"), version: "1.3.0")) else {
            suite.expect(false, "a tool added from a folder is offered its newer version from the catalog")
            return
        }
        let sheet = ToolAgreementContent(offer: move, language: .enUS, strings: english, cancel: "Cancel",
                                         home: moving.bench.root.path)
        suite.expect(sheet.isUpdate && sheet.title == "Update “Deploys”?" && sheet.agree == "Update Tool"
                         && sheet.movesToCatalogue
                         == "You added it from the folder ~/Remote; from now on it comes from the Vitruvian catalog."
                         && sheet.catalogue == english.agreeCatalog && sheet.from == "From github.com/acme/deploys"
                         && sheet.versions == "You have version 1.2.0. The catalog has version 1.3.0."
                         && sheet.keepsData == english.updateKeepsData && sheet.initialFocus == .cancel,
                     "updating from the catalog a tool added from a folder is asked on the usual sheet, which says "
                         + "in one sentence that it moves from its folder to the catalog, and that what it saved is kept")
        suite.expect(sheet.changed == english.updateChanged,
                     "and when what the tool says about itself changed, the sheet still asks the person to read it again")
        moving.installer.finished(with: move)

        // A tool from the catalog, updated from the catalog.
        let updating = CatalogueInstallerTests.Rig()
        defer { updating.close() }
        guard case .success(let first)? = updating.prepare(updating.entry(TestZip.tool())),
              (try? updating.bench.store.add(ToolConsent(to: first)).get()) != nil else {
            suite.expect(false, "a tool from the catalog is installed")
            return
        }
        updating.installer.finished(with: first)
        guard case .success(let update)? = updating.prepare(updating.entry(TestZip.tool(version: "1.3.0"),
                                                                           version: "1.3.0")) else {
            suite.expect(false, "a newer version from the catalog is offered")
            return
        }
        let catalogUpdate = ToolAgreementContent(offer: update, language: .enUS, strings: english, cancel: "Cancel")
        let folderUpdate = ToolAgreementContent(offer: (try? moving.bench.store.offer(from: added).get()) ?? update,
                                                language: .enUS, strings: english, cancel: "Cancel")
        suite.expect(catalogUpdate.versions == "You have version 1.2.0. The catalog has version 1.3.0."
                         && catalogUpdate.movesToCatalogue == nil
                         && folderUpdate.versions == "You have version 1.2.0. This folder has version 1.2.0.",
                     "an update from the catalog says the catalog has the new version, never a folder the person "
                         + "cannot see; an update from a folder still names the folder")
        updating.installer.finished(with: update)
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
        suite.expect(row?.updateButton == "Update" && row?.updateSpoken == "Update, Deploys",
                     "a tool from the catalog's row offers Update")

        let byHand = CatalogueWatchTests.Rig()
        defer { byHand.close() }
        byHand.install(fromCatalog: false)
        byHand.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        byHand.watch.refresh()
        let listed = byHand.bench.store.listed[0]
        let folderRow = ExternalToolRow.all(store: byHand.bench.store, language: .enUS, strings: english,
                                            watch: byHand.watch).first
        let folderDetail = ExternalToolDetail(listed, files: nil, language: .enUS, strings: english,
                                              updateAvailable: byHand.watch.update(for: listed) != nil)
        let french = ExternalToolRow(listed, language: .fr, strings: FeatureStrings.externalTools(.fr),
                                     updateAvailable: true)
        suite.expect(folderRow?.updateText == "Update available" && folderRow?.updateButton == "Update from the catalog"
                         && folderRow?.updateSpoken == "Update from the catalog, Deploys"
                         && folderDetail.updateNow == "Update from the catalog"
                         && french.updateButton == "Mettre à jour depuis le catalogue",
                     "a tool added from a folder whose newer version the catalog lists says Update available, and "
                         + "its row and detail offer \"Update from the catalog\"")
    }
}
