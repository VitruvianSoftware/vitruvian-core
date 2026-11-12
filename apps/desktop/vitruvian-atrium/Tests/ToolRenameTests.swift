// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianAtriumCore
import VitruvianAtriumServices

/// A tool the catalog renamed: its entry names the old id (`replaces`), a
/// tool added under the old id is offered the entry as its update, and
/// agreeing moves it to the new id with what it saved and the app's
/// settings for it, in its place in the list, with its switch as it was.
enum ToolRenameTests {
    static func run(_ suite: TestSuite) {
        theListReadsReplaces(suite)
        theOldIdIsOfferedTheNewEntry(suite)
        agreeingMovesTheTool(suite)
        aSwitchedOffToolStaysOff(suite)
        dataInTheWayChangesNothing(suite)
        theAppsSettingsMove(suite)
    }

    static let old = ToolID("com.acme.olddeploys")!
    static let new = ToolID("com.acme.deploys")!

    static func theListReadsReplaces(_ suite: TestSuite) {
        let list = CatalogueFixtures.list([
            CatalogueFixtures.entry(["replaces": ["com.acme.olddeploys", "com.acme.deploys", "nodot",
                                                  "com.acme.olddeploys", "com.acme.other"]]),
            CatalogueFixtures.entry(["id": "com.acme.other"]),
        ])
        let read = Catalogue.read(list, permits: { _ in true })
        suite.expect(read?.tools.first?.replaces == [old],
                     "an entry's former ids are read once each, leaving out its own id, one that is not an outside "
                         + "tool's, and one the list still has an entry for")
        let plain = Catalogue.read(CatalogueFixtures.list([CatalogueFixtures.entry()]), permits: { _ in true })
        suite.expect(plain?.tools.first?.replaces == [], "an entry that names none replaces nothing")
    }

    /// The old tool, added from the catalog under its old id.
    static func installOld(in bench: ExternalToolStoreTests.Bench, version: String = "1.41.0") {
        let folder = bench.folder("old", manifest: ExternalToolManifestTests.file(
            #"{"id": "com.acme.olddeploys", "version": "\#(version)"}"#))
        let origin = CatalogueOrigin(id: old.rawValue, version: version, source: "https://github.com/acme/deploys",
                                     download: "https://catalog.test/old-\(version).zip")
        if case .success(let offer) = bench.store.offer(from: folder, catalogue: origin) {
            bench.store.add(ToolConsent(to: offer))
        }
    }

    /// The renamed tool's folder, as the installer unpacks it, and the offer
    /// the store makes for it.
    static func offerNew(in bench: ExternalToolStoreTests.Bench, replacing: [ToolID] = [old])
        -> Result<ToolOffer, ExternalToolStore.Refusal> {
        let folder = bench.folder("new", manifest: ExternalToolManifestTests.file(#"{"version": "1.42.0"}"#))
        let origin = CatalogueOrigin(id: new.rawValue, version: "1.42.0", source: "https://github.com/acme/deploys",
                                     download: "https://catalog.test/deploys-1.42.0.zip")
        return bench.store.offer(from: folder, catalogue: origin, replacing: replacing)
    }

    static func theOldIdIsOfferedTheNewEntry(_ suite: TestSuite) {
        let rig = CatalogueWatchTests.Rig()
        defer { rig.close() }
        installOld(in: rig.bench, version: "2.0.0")
        // Older than the version installed: a rename is offered all the same.
        rig.serve([CatalogueFixtures.entry(["version": "1.42.0", "replaces": [old.rawValue]])])
        rig.watch.refresh()
        let listed = { rig.bench.store.listed.first { $0.id == old }! }
        suite.expect(rig.watch.update(for: listed())?.id == new,
                     "a tool whose id the catalog no longer lists is offered the entry that replaces it, whatever "
                         + "its version")
        rig.serve([CatalogueFixtures.entry(["version": "1.42.0", "replaces": [old.rawValue]]),
                   CatalogueFixtures.entry(["id": old.rawValue, "version": "2.0.0"])],
                  generated: "2026-11-03T10:00:00Z", etag: "\"b\"")
        rig.watch.refresh()
        suite.expect(rig.watch.update(for: listed()) == nil,
                     "while the catalog still lists the old id, the tool is that entry's, and is up to date")
        rig.serve([CatalogueFixtures.entry(["version": "1.42.0", "replaces": [old.rawValue]])],
                  generated: "2026-11-04T10:00:00Z", etag: "\"c\"")
        rig.watch.refresh()
        _ = rig.bench.add(rig.bench.folder("both", manifest: ExternalToolManifestTests.file()))
        suite.expect(rig.watch.update(for: listed()) == nil,
                     "a person who has the tool under its new id as well is offered no rename")
    }

    static func agreeingMovesTheTool(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        installOld(in: bench)
        _ = bench.add(bench.folder("other", manifest: ExternalToolManifestTests.file(#"{"id": "com.acme.other"}"#)))
        let support = bench.support
        let oldData = support.appendingPathComponent("ToolData/\(old.rawValue)")
        let oldFiles = support.appendingPathComponent("Tools/\(old.rawValue)")
        try? Data("signed in".utf8).write(to: oldData.appendingPathComponent("settings.json"))

        guard case .success(let offer) = offerNew(in: bench) else {
            return suite.expect(false, "the renamed tool is offered")
        }
        suite.expect(offer.renames == old && offer.replaces != nil,
                     "the offer says it replaces the tool under its old id, and what the person agreed to before")
        let added = bench.store.add(ToolConsent(to: offer))
        let ids = bench.store.listed.map(\.id)
        suite.expect((try? added.get()) != nil && ids == [new, ToolID("com.acme.other")!],
                     "agreeing adds it under the new id, in the old one's place in the list")
        suite.expect((try? String(contentsOf: bench.data.appendingPathComponent("settings.json"), encoding: .utf8))
                         == "signed in" && !bench.exists(oldData) && !bench.exists(oldFiles)
                         && bench.exists(bench.files),
                     "what it saved is under the new id, and nothing is left under the old one")
        suite.expect(bench.renamed.map { "\($0.from)>\($0.to)" } == ["\(old)>\(new)"]
                         && bench.store.isInstalled(new) && !bench.store.isInstalled(old),
                     "the app is told of the rename, and only the new id answers")
        let next = bench.relaunched()
        defer { next.close() }
        next.store.restore()
        suite.expect(next.store.listed.map(\.id) == ids && next.store.isInstalled(new)
                         && next.store.listed.first?.record.catalogue?.id == new.rawValue,
                     "at the next launch the tool is there under its new id, from the new entry")
    }

    static func aSwitchedOffToolStaysOff(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        installOld(in: bench)
        bench.store.setOn(old, false)
        guard case .success(let offer) = offerNew(in: bench) else {
            return suite.expect(false, "the renamed tool is offered while switched off")
        }
        bench.store.add(ToolConsent(to: offer))
        suite.expect(bench.store.listed.map(\.id) == [new] && bench.store.listed.first?.record.isOn == false
                         && !bench.store.isInstalled(new),
                     "a tool that was switched off is renamed and stays off")
    }

    static func dataInTheWayChangesNothing(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        installOld(in: bench)
        let oldData = bench.support.appendingPathComponent("ToolData/\(old.rawValue)")
        try? Data("old".utf8).write(to: oldData.appendingPathComponent("settings.json"))
        try? FileManager.default.createDirectory(at: bench.data, withIntermediateDirectories: true)
        try? Data("new".utf8).write(to: bench.data.appendingPathComponent("settings.json"))
        guard case .success(let offer) = offerNew(in: bench) else {
            return suite.expect(false, "the renamed tool is offered")
        }
        let added = bench.store.add(ToolConsent(to: offer))
        var refused: ExternalToolStore.Refusal?
        if case .failure(let refusal) = added { refused = refusal }
        suite.expect(refused == .renamedDataInTheWay(new),
                     "with something saved under the new id already, nothing is moved onto it")
        suite.expect(bench.store.listed.map(\.id) == [old] && bench.store.isInstalled(old)
                         && (try? String(contentsOf: oldData.appendingPathComponent("settings.json"), encoding: .utf8))
                         == "old" && !bench.exists(bench.files) && bench.renamed.isEmpty,
                     "and the tool under the old id is as it was, running, with what it saved")
    }

    static func theAppsSettingsMove(_ suite: TestSuite) {
        let name = "vitruvian-tool-rename-\(UUID().uuidString)"
        guard let defaults = ScratchDefaults.suite(named: name) else { return suite.expect(false, "a defaults domain") }
        defer { defaults.removePersistentDomain(forName: name) }
        let o = old.rawValue, n = new.rawValue
        defaults.set("Kitchen", forKey: "\(o)/room")
        defaults.set("kept", forKey: "\(n)/kept")
        defaults.set("lost", forKey: "\(o)/kept")
        defaults.set("other", forKey: "\(o)x/room")
        defaults.set(true, forKey: "\(DefaultsKey.toolCommandShortcuts).\(o)/mute")
        defaults.set(#"{"\#(o)/mute":"cmd+m","com.acme.other/go":"cmd+g"}"#, forKey: DefaultsKey.toolCommandShortcuts)
        defaults.set("tool.\(o)/mute\napp.settings", forKey: DefaultsKey.commandBarPins)
        defaults.set("tool.\(o)/unmute", forKey: DefaultsKey.commandBarHidden)
        defaults.set("com.acme.other,\(o)", forKey: DefaultsKey.panelExtensionOrder)
        defaults.set(o, forKey: DefaultsKey.panelHiddenExtensions)

        ToolRename.carryOverDefaults(from: old, to: new, in: defaults)

        let shortcuts = defaults.string(forKey: DefaultsKey.toolCommandShortcuts)
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] }
        suite.expect(defaults.string(forKey: "\(n)/room") == "Kitchen" && defaults.object(forKey: "\(o)/room") == nil
                         && defaults.string(forKey: "\(n)/kept") == "kept" && defaults.object(forKey: "\(o)/kept") == nil,
                     "the tool's preferences move to the new id, and one already there is kept")
        suite.expect(defaults.string(forKey: "\(o)x/room") == "other",
                     "a tool whose id only starts the same keeps its own")
        suite.expect(shortcuts == ["\(n)/mute": "cmd+m", "com.acme.other/go": "cmd+g"]
                         && defaults.bool(forKey: "\(DefaultsKey.toolCommandShortcuts).\(n)/mute")
                         && defaults.object(forKey: "\(DefaultsKey.toolCommandShortcuts).\(o)/mute") == nil,
                     "its command shortcuts and their take-overs move, and another tool's stay")
        suite.expect(defaults.string(forKey: DefaultsKey.commandBarPins) == "tool.\(n)/mute\napp.settings"
                         && defaults.string(forKey: DefaultsKey.commandBarHidden) == "tool.\(n)/unmute"
                         && defaults.string(forKey: DefaultsKey.panelExtensionOrder) == "com.acme.other,\(n)"
                         && defaults.string(forKey: DefaultsKey.panelHiddenExtensions) == n,
                     "its command bar pins, hidden rows and place in the island move, in the same order")
    }
}
