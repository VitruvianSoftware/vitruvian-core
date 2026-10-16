// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianUI

/// The Extensions page in Settings, as plain values: where it sits in the
/// sidebar, the line the Features page shows in place of the old card, the
/// catalog under what is installed, the sidebar's count of updates, and
/// every way in landing on it. No test draws a view.
enum ExtensionsPageTests {
    static func run(_ suite: TestSuite) {
        sidebar(suite)
        featuresLine(suite)
        catalog(suite)
        updateCount(suite)
        waysIn(suite)
        installButtons(suite)
        installsOutliveThePage(suite)
        spokenButtons(suite)
        sdkLink(suite)
    }

    /// Closures the installer hands back to the main thread, held until the
    /// test lets them run: a download that is still under way.
    final class Held: @unchecked Sendable {
        // Written by the installer's hand-back and read by the test, both on the main thread.
        nonisolated(unsafe) var work: [@Sendable @MainActor () -> Void] = []

        func finish() {
            let all = work
            work = []
            MainActor.assumeIsolated { for step in all { step() } }
        }
    }

    /// Installs over a real installer and store, whose last step, back on
    /// the main thread, waits for `held.finish()`.
    static func installs(_ rig: CatalogueInstallerTests.Rig, _ held: Held)
        -> (installer: CatalogueInstaller, installs: CatalogueInstalls) {
        let bench = rig.bench
        let installer = CatalogueInstaller(
            parts: .init(fetcher: rig.fetcher, source: CatalogueFixtures.source, scratch: rig.scratch,
                         work: { $0() }, toMain: { work in held.work.append(work) }),
            store: { bench.store })
        return (installer, CatalogueInstalls(installer: installer))
    }

    static func installButtons(_ suite: TestSuite) {
        guard let deploys = ToolID("com.acme.deploys"), let other = ToolID("com.acme.other") else {
            suite.expect(false, "two tool ids")
            return
        }
        typealias Button = ExtensionsPageContent.InstallButton
        func button(_ id: ToolID, fetching: ToolID? = nil, waiting: Bool = false, adding: Set<ToolID> = []) -> Button {
            ExtensionsPageContent.installButton(for: id, fetching: fetching, waiting: waiting, adding: adding)
        }
        suite.expect(button(deploys) == .enabled
                         && button(deploys, fetching: deploys) == .progress && button(other, fetching: deploys) == .disabled
                         && button(deploys, adding: [deploys]) == .progress && button(other, adding: [deploys]) == .disabled
                         && button(deploys, waiting: true) == .disabled,
                     "while a tool downloads, its row's Update or Install is a spinner and every other row's button "
                         + "is there and disabled, as while one is added or its result waits")
    }

    static func installsOutliveThePage(_ suite: TestSuite) {
        let rig = CatalogueInstallerTests.Rig()
        defer { rig.close() }
        let held = Held()
        let (installer, installs) = installs(rig, held)
        let entry = rig.entry(TestZip.tool())
        let started = installs.start(entry)
        let during = (installs.fetching, installs.waiting, installs.isBusy)
        let second = installs.start(rig.entry(TestZip.tool(version: "1.3.0"), version: "1.3.0"))
        suite.expect(started && during.0 == entry.id && during.1 == nil && during.2 && !second
                         && rig.fetcher.asked.count == 1,
                     "an install from the catalog is under way in the shared installs, whatever page is open, and "
                         + "a second press while it downloads fetches nothing")

        // The page that asked is gone: nothing takes the result as it arrives.
        held.finish()
        guard case .ready(let offer)? = installs.waiting else {
            suite.expect(false, "a download that finishes with no page open keeps its offer for the page")
            return
        }
        let busy = installs.isBusy && !installs.start(entry)
        let taken = installs.take()
        suite.expect(installs.fetching == nil && offer.tool.manifest.id == entry.id && busy
                         && taken == .ready(offer) && installs.take() == nil && !installs.isBusy
                         && rig.bench.store.listed.isEmpty,
                     "a download that finishes with no page open keeps its offer for the page, which shows it once "
                         + "when opened again; nothing is installed until the person agrees")
        installer.finished(with: offer)

        let bad = rig.entry(TestZip.tool(), pin: ["sha256": String(repeating: "0", count: 64)])
        installs.start(bad)
        held.finish()
        suite.expect(installs.waiting == .refused(.mismatch, entry: bad) && installs.take() == .refused(.mismatch, entry: bad)
                         && !installs.isBusy,
                     "a refused download waits for the page too, to be said once")
    }

    static func spokenButtons(_ suite: TestSuite) {
        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        rig.install()
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"]),
                   CatalogueFixtures.entry(["id": "com.acme.other", "name": ["en": "Other"]])])
        rig.watch.refresh()
        let row = ExternalToolRow.all(store: rig.bench.store, language: .enUS, strings: english, watch: rig.watch).first
        let plain = ExternalToolRow(rig.bench.store.listed[0], language: .enUS, strings: english)
        let install = CatalogueScreensTests.rows(CatalogueScreensTests.content(rig)).last
        suite.expect(row.map { $0.updateSpoken == "Update, " + $0.name } == true && plain.updateSpoken == nil
                         && install?.actionSpoken == "Install, Other"
                         && ExtensionsPageSupport.summary(installed: 3, strings: english).spoken
                             == "3 extensions installed. Manage",
                     "VoiceOver hears whose Update or Install a button is, and the Features line once, as its link")
    }

    static let english = FeatureStrings.externalTools(.enUS)

    static func sidebar(_ suite: TestSuite) {
        for available in [true, false] {
            let sections = SettingsDirectory.sidebarSections(Strings.enUS, language: .enUS,
                                                             isAvailable: { _ in available })
            let essentials = sections.first?.items.map(\.id) ?? []
            let features = essentials.firstIndex(of: .page(.features))
            let row = sections.first?.items.first { $0.id == .page(.extensions) }
            suite.expect(features != nil && essentials.firstIndex(of: .page(.extensions)) == features.map { $0 + 1 }
                             && row?.title == "Extensions" && row?.destination == FeatureSettingsDestination(.extensions)
                             && sections.dropFirst().allSatisfy { !$0.items.contains { $0.id == .page(.extensions) } },
                         "the sidebar lists Extensions once, in Essentials, right after Features, with every hub "
                             + "feature \(available ? "on" : "off")")
        }
        let french = SettingsDirectory.sidebarSections(Strings.enUS, language: .fr, isAvailable: { _ in true })
        suite.expect(french.first?.items.contains { $0.id == .page(.extensions) && $0.title == "Modules d’extension" } == true,
                     "the sidebar's row follows the app's language")
    }

    static func featuresLine(_ suite: TestSuite) {
        let none = ExtensionsPageSupport.summary(installed: 0, strings: english)
        let one = ExtensionsPageSupport.summary(installed: 1, strings: english)
        let many = ExtensionsPageSupport.summary(installed: 3, strings: english)
        suite.expect(none.text == "No extensions yet" && none.link == "Browse"
                         && one.text == "1 extension installed" && one.link == "Manage"
                         && many.text == "3 extensions installed" && many.link == "Manage"
                         && many.spoken == "3 extensions installed. Manage",
                     "the Features page says how many extensions are added, one in the singular, and none as "
                         + "No extensions yet with Browse")
        suite.expect([none, one, many].allSatisfy { $0.destination == FeatureSettingsDestination(.extensions) },
                     "the Features page's line leads to the Extensions page, whatever it says")
        let router = SettingsRouter()
        router.page = .features
        router.request(many.destination)
        suite.expect(router.page == .extensions && router.destination == ExtensionsPageSupport.destination
                         && router.canGoBack(),
                     "following the line opens the Extensions page, and Back returns to Features")

        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        let before = ExtensionsPageContent.summary(store: rig.bench.store, language: .enUS)
        rig.install()
        let after = ExtensionsPageContent.summary(store: rig.bench.store, language: .enUS)
        rig.bench.store.setOn(rig.bench.store.listed[0].id, false)
        let off = ExtensionsPageContent.summary(store: rig.bench.store, language: .enUS)
        suite.expect(before.text == "No extensions yet" && after.text == "1 extension installed" && off == after,
                     "the line counts what the store lists, a tool that is switched off included")
    }

    static func catalog(_ suite: TestSuite) {
        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        rig.install()
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"]),
                   CatalogueFixtures.entry(["id": "com.acme.other", "name": ["en": "Other"], "panels": [] as [String]]),
                   CatalogueFixtures.entry(["id": "com.acme.github", "name": ["en": "GitHub"],
                                            "panels": ["island"]])])
        rig.watch.refresh()
        let content = CatalogueScreensTests.content(rig)
        guard case .rows(let rows) = content.notInstalled else {
            suite.expect(false, "the Extensions page lists the catalog's tools that are not installed")
            return
        }
        suite.expect(rows.map(\.id.rawValue) == ["com.acme.other", "com.acme.github"]
                         && rows.allSatisfy { $0.action == .install }
                         && rows.map(\.kindBadge) == ["Tool", "Extension"] && content.title == "The Vitruvian catalog",
                     "the Extensions page lists the catalog's tools that are not installed, each with Install and "
                         + "its kind pill, under the catalog's heading")

        rig.serve([CatalogueFixtures.entry(["version": "1.2.0"])], etag: "\"b\"")
        rig.watch.refresh()
        suite.expect(CatalogueScreensTests.content(rig).notInstalled == .message(english.catalogAllInstalled),
                     "when everything the catalog lists is installed, one line says so")

        let byHand = CatalogueWatchTests.Rig()
        defer { byHand.close() }
        byHand.install(fromCatalog: false)
        byHand.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        byHand.watch.refresh()
        suite.expect(CatalogueScreensTests.content(byHand).notInstalled == .message(english.catalogAllInstalled),
                     "a tool added from a folder with the catalog's id is installed, and not listed again")

        let empty = CatalogueWatchTests.Rig()
        defer { empty.close() }
        let waiting = CatalogueScreensTests.content(empty).notInstalled
        empty.serve([])
        empty.watch.refresh()
        let unreachable = CatalogueWatchTests.Rig()
        defer { unreachable.close() }
        unreachable.watch.refresh()
        suite.expect(waiting == .loading && CatalogueScreensTests.content(empty).notInstalled == .message(english.catalogEmpty)
                         && CatalogueScreensTests.content(unreachable).notInstalled == .message(english.catalogUnreachable),
                     "waiting, an empty catalog and one that cannot be fetched say what the catalog's sheet said")
    }

    /// The quiet line under the catalog that leads to the SDK. The page draws
    /// it below the card's switch over the list, so it is there in every
    /// state the card can be in; these checks hold that the content carries
    /// it, with the right words and address, in each of them.
    static func sdkLink(_ suite: TestSuite) {
        let sdk = URL(string: "https://github.com/VitruvianSoftware/vitruvian-sdk")!
        let wanted = CatalogueSheetContent.SDKLine(english.sdkLine, url: AppInfo.sdkURL)

        let loading = CatalogueWatchTests.Rig()
        defer { loading.close() }
        let empty = CatalogueWatchTests.Rig()
        defer { empty.close() }
        empty.serve([])
        empty.watch.refresh()
        let offline = CatalogueWatchTests.Rig()
        defer { offline.close() }
        offline.watch.refresh()
        let refused = CatalogueWatchTests.Rig()
        defer { refused.close() }
        refused.serve([CatalogueFixtures.entry()], signer: .init())
        refused.watch.refresh()
        let listed = CatalogueWatchTests.Rig()
        defer { listed.close() }
        listed.serve([CatalogueFixtures.entry()])
        listed.watch.refresh()
        let allIn = CatalogueWatchTests.Rig()
        defer { allIn.close() }
        allIn.install()
        allIn.serve([CatalogueFixtures.entry(["version": "1.2.0"])])
        allIn.watch.refresh()

        let states: [(String, CatalogueSheetContent)] = [
            ("loading", CatalogueScreensTests.content(loading)),
            ("empty", CatalogueScreensTests.content(empty)),
            ("offline", CatalogueScreensTests.content(offline)),
            ("errored", CatalogueScreensTests.content(refused)),
            ("listed", CatalogueScreensTests.content(listed)),
            ("all installed", CatalogueScreensTests.content(allIn)),
        ]
        suite.expect(states.map { $0.1.notInstalled } == [
                         .loading, .message(english.catalogEmpty), .message(english.catalogUnreachable),
                         .message(english.catalogNotOurs), states[4].1.notInstalled,
                         .message(english.catalogAllInstalled),
                     ] && CatalogueScreensTests.rows(states[4].1).count == 1,
                     "the six states of the catalog's card are each reached")
        let missing = states.filter { $0.1.sdk != wanted }.map(\.0)
        suite.expect(missing.isEmpty,
                     "the line to the SDK is under the catalog however the list stands (\(missing.joined(separator: ", ")))")

        suite.expect(wanted.sentence == "Build your own extension with the Vitruvian SDK."
                         && wanted.before == "Build your own extension with the " && wanted.link == "Vitruvian SDK"
                         && wanted.after == ".",
                     "the line reads \"Build your own extension with the Vitruvian SDK.\", and the SDK's name is the link")
        suite.expect(AppInfo.sdkURL == sdk && wanted.url == sdk,
                     "the SDK link opens the vitruvian-sdk repository on GitHub")

        let unlinked = AppLanguage.allCases.filter { language in
            let line = CatalogueScreensTests.content(loading, language: language).sdk
            let text = FeatureStrings.externalTools(language).sdkLine
            return line.link != CatalogueSheetContent.SDKLine.name || line.url != sdk || line.sentence != text
                || text.components(separatedBy: CatalogueSheetContent.SDKLine.name).count != 2
        }
        suite.expect(unlinked.isEmpty,
                     "every language names the Vitruvian SDK once, untranslated, so its name is the link "
                         + "(\(unlinked.map(\.rawValue).joined(separator: ", ")))")
        let whole = CatalogueSheetContent.SDKLine("Build your own.", url: sdk)
        suite.expect(whole.link == "Build your own." && whole.before.isEmpty && whole.after.isEmpty,
                     "a sentence without the name is a link as a whole, never a line with no link")
    }

    static func updateCount(_ suite: TestSuite) {
        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        rig.install()
        let unfetched = ExtensionsPageContent.updates(store: rig.bench.store, watch: rig.watch)
        rig.serve([CatalogueFixtures.entry(["version": "1.3.0"])])
        rig.watch.refresh()
        let newer = ExtensionsPageContent.updates(store: rig.bench.store, watch: rig.watch)
        let row = ExternalToolRow.all(store: rig.bench.store, language: .enUS, strings: english, watch: rig.watch).first
        rig.serve([CatalogueFixtures.entry(["version": "1.2.0"])], etag: "\"b\"")
        rig.watch.refresh()
        let same = ExtensionsPageContent.updates(store: rig.bench.store, watch: rig.watch)

        suite.expect(unfetched == 0 && newer == 1 && row?.updateText == "Update available" && same == 0,
                     "the sidebar counts the tools installed from the catalog that it lists a newer version of, "
                         + "the ones whose rows say Update available; none before the list is fetched")

        // Two tools: one from the catalog, one added from a folder, both with
        // a newer version listed.
        let both = CatalogueWatchTests.Rig()
        defer { both.close() }
        both.install()
        let other = both.bench.folder("other", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.other"}"#))
        both.bench.add(other)
        let entries = { (deploys: String, other: String) -> [[String: Any]] in
            [CatalogueFixtures.entry(["version": deploys]),
             CatalogueFixtures.entry(["id": "com.acme.other", "version": other])]
        }
        both.serve(entries("1.3.0", "1.3.0"))
        both.watch.refresh()
        let two = ExtensionsPageContent.updates(store: both.bench.store, watch: both.watch)
        both.serve(entries("1.3.0", "1.2.0"), generated: "2026-11-03T10:00:00Z", etag: "\"b\"")
        both.watch.refresh()
        let sameFolder = ExtensionsPageContent.updates(store: both.bench.store, watch: both.watch)
        both.serve(entries("1.2.0", "1.1.0"), generated: "2026-11-04T10:00:00Z", etag: "\"c\"")
        both.watch.refresh()
        let none = ExtensionsPageContent.updates(store: both.bench.store, watch: both.watch)
        suite.expect(both.bench.store.listed.map { $0.record.catalogue == nil } == [false, true]
                         && two == 2 && sameFolder == 1 && none == 0,
                     "the sidebar counts a tool added from a folder whose newer version the catalog lists too, "
                         + "and not one at the same or an older version")
    }

    static func waysIn(_ suite: TestSuite) {
        suite.expect(ExtensionsPageSupport.destination == FeatureSettingsDestination(.extensions)
                         && ExtensionsPageSupport.destination.hasValidSectionAnchor
                         && FeatureVisibilitySupport.isPageVisible(.extensions, isAvailable: { _ in false })
                         && FeatureVisibilitySupport.features(for: .extensions).isEmpty,
                     "the Extensions page is one destination, with no anchor, and shows whatever the hub has on")

        let items = SettingsDirectory.searchItems(Strings.enUS, language: .enUS)
        for available in [true, false] {
            let lost = ["extensions", "tools", "catalog", "Add from Folder"].filter { query in
                let groups = SettingsSearchSupport.groupedMatchingItems(query: query, items: items,
                                                                        isAvailable: { _ in available })
                guard let group = groups.first(where: { $0.pageItem.destination.page == .extensions }) else { return true }
                let routes = ([group.parentSuggestion] + group.suggestions).map {
                    SettingsSearchSupport.route(for: $0, isAvailable: { _ in available }).destination
                }
                return !routes.allSatisfy { $0 == ExtensionsPageSupport.destination }
            }
            suite.expect(lost.isEmpty,
                         "the Settings search and the command bar, which lists the same items, find the Extensions "
                             + "page by \"extensions\", \"tools\", \"catalog\" and its Add button, and open it, with "
                             + "every hub feature \(available ? "on" : "off") (\(lost.joined(separator: ", ")))")
        }
        let page = items.first { $0.id == .page(.extensions) }
        suite.expect(page?.feature == nil && page?.destination == ExtensionsPageSupport.destination,
                     "the Extensions page belongs to no hub feature, so it never falls back to Features")

        suite.expect(FeatureStrings.notchEditor(.enUS).extensionSummary.hasSuffix("Its own settings are in Extensions.")
                         && english.openExtensions == "Open Extensions",
                     "an extension's island page in Settings says its own settings are in Extensions, and its button opens it")
        suite.expect(ByHandRules.Words.extensionsPage == english.pageTitle && ByHandRules.Words.addTool == english.addButton
                         && ByHandRules.Words.agreeToAdd == english.agreeAdd,
                     "the by-hand command looks for the page and presses its buttons by the app's own English words")
    }
}
