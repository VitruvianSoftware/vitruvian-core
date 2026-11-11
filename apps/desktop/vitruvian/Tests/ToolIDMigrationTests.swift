// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol

/// A tool added under an id that has been renamed (Nexus Agent, which became
/// Code) is the same tool under the new id after the next launch: its
/// folders, preferences, shortcuts, place in the menu bar panel and record.
/// A second run changes nothing, and one that stopped half way is finished.
enum ToolIDMigrationTests {
    static func run(_ suite: TestSuite) {
        theIdsThatWereRenamed(suite)
        movesTheWholeTool(suite)
        aSecondRunChangesNothing(suite)
        aLaunchThatStoppedHalfWayIsFinished(suite)
        whatTheNewIdHasIsKept(suite)
        bothInstalledIsLeftAlone(suite)
        anUnreadableRecordIsLeftAlone(suite)
        aTwoCopiesTrapKeepsTheRecord(suite)
        waitsForTheCatalogue(suite)
        aChangedManifestIsNotCarriedOver(suite)
        aResumedLaunchTrustsItsOwnRewrite(suite)
        theStoreDoesItAtLaunch(suite)
    }

    static let old = ToolID("dev.vitruvian.nexus-agent")!
    static let new = ToolID("dev.vitruvian.code")!

    /// The tool as the old catalog shipped it: the manifest names the old id.
    static var oldManifest: Data {
        Data(String(decoding: NexusAgentHandoffTests.manifest, as: UTF8.self)
            .replacingOccurrences(of: "dev.vitruvian.code", with: old.rawValue).utf8)
    }

    final class Rig {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-tool-id-migration-\(UUID().uuidString)", isDirectory: true)
        let defaults: UserDefaults
        var logged: [String] = []
        let date = Date(timeIntervalSince1970: 1_760_000_000)

        init(_ name: String) {
            let domain = "com.vitruviansoftware.vitruvian.tests.tool-id-migration.\(name)"
            defaults = ScratchDefaults.suite(named: domain)!
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }

        var support: URL { root.appendingPathComponent("support", isDirectory: true) }
        var folders: ToolFolders { ToolFolders(root: support) }
        func files(_ id: ToolID) -> URL { folders.place(for: id)!.files }
        func data(_ id: ToolID) -> URL { folders.place(for: id)!.data }
        func close() { try? FileManager.default.removeItem(at: root) }

        func write(_ text: String, to url: URL, mode: Int = 0o600) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: Data(text.utf8), attributes: [.posixPermissions: mode])
        }

        func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

        func mode(_ url: URL) -> Int? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
        }

        func exists(_ url: URL) -> Bool { (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil }

        /// The tool as an old install has it: its copy, what it saved, its
        /// line in the record, and the app's preferences about it.
        func seedOldInstall(extraRecords: [ToolRecord] = []) {
            let copy = files(old)
            try? FileManager.default.createDirectory(at: copy.appendingPathComponent("bin"), withIntermediateDirectories: true)
            try? oldManifest.write(to: copy.appendingPathComponent("vitruvian-tool.json"))
            FileManager.default.createFile(atPath: copy.appendingPathComponent("bin/tool").path, contents: Data("program".utf8),
                                           attributes: [.posixPermissions: 0o755])
            write(#"{"botDirectory":"~/bots"}"#, to: data(old).appendingPathComponent("settings.json"))
            write("prompts", to: data(old).appendingPathComponent("history/prompts.txt"))

            let agreement = ToolAgreement(date: date, name: "Nexus Agent", version: "1.32.7", publisher: "VitruvianSoftware",
                                          fingerprint: ToolFingerprint.of(oldManifest), source: "https://example.com/z.zip")
            let origin = CatalogueOrigin(id: old.rawValue, version: "1.32.7", source: "https://github.com/x/y",
                                         download: "https://example.com/z.zip")
            let record = ToolRecord(id: old.rawValue, isOn: true, agreement: agreement, catalogue: origin,
                                    showsInIsland: false, showsStatus: nil)
            ToolRecords.write([ToolRecord(id: "com.acme.deploys", isOn: false, agreement: agreement), record] + extraRecords,
                              to: folders.records)

            defaults.set("~/bots", forKey: "\(old.rawValue)/botDirectory")
            defaults.set(true, forKey: "\(old.rawValue)/autoStart")
            defaults.set("keep", forKey: "com.acme.deploys/note")
            ToolCommandShortcuts.save([
                "\(old.rawValue)/quickPrompt": GlobalShortcut(keyCode: 49, modifiers: [.command, .shift]),
                "com.acme.deploys/run": GlobalShortcut(keyCode: 2, modifiers: [.command]),
            ], to: defaults)
            defaults.set("com.acme.deploys,\(old.rawValue)", forKey: DefaultsKey.panelHiddenExtensions)
            defaults.set("\(old.rawValue),com.acme.deploys", forKey: DefaultsKey.panelExtensionOrder)
            defaults.set(old.rawValue, forKey: DefaultsKey.panelCollapsedExtensions)
        }

        /// By default the catalog the app has loaded lists the new id.
        @discardableResult
        func migrate(catalogue: Set<ToolID>? = [ToolIDMigrationTests.new]) -> [ToolIDMigration.Outcome] {
            ToolIDMigration.run(folders: folders, defaults: defaults, catalogue: catalogue) { [self] in logged.append($0) }
        }

        func records() -> [ToolRecord] {
            if case .records(let records) = ToolRecords.read(at: folders.records) { return records }
            return []
        }

        /// Everything a second run could change: the files, their bytes and
        /// the app's preferences.
        func snapshot() -> [String] {
            var lines: [String] = []
            for path in (FileManager.default.subpaths(atPath: support.path) ?? []).sorted() {
                let url = support.appendingPathComponent(path)
                lines.append("\(path) \(mode(url) ?? 0) \(read(url)?.count ?? -1)")
            }
            let prefs = defaults.dictionaryRepresentation().filter { $0.key.contains("/") || $0.key.hasPrefix("panel") || $0.key == "toolCommandShortcuts" }
            lines.append(contentsOf: prefs.map { "\($0.key)=\($0.value)" }.sorted())
            return lines
        }
    }

    static func theIdsThatWereRenamed(_ suite: TestSuite) {
        suite.expect(ToolIDMigration.renames == [.init(from: old, to: NexusAgentHandoff.toolID)],
                     "Nexus Agent's id is the one that was renamed, and the hand-off now goes to the new one")
    }

    static func movesTheWholeTool(_ suite: TestSuite) {
        let rig = Rig("whole")
        defer { rig.close() }
        rig.seedOldInstall()

        let outcomes = rig.migrate()
        guard case .migrated(let steps)? = outcomes.first else {
            return suite.expect(false, "the tool is migrated: \(outcomes), \(rig.logged)")
        }
        suite.expect(steps.count == 7, "every part of the tool is moved, and said: \(steps)")

        // The app's copy: moved, its manifest names the new id, the program is still a program.
        let copy = rig.files(new)
        suite.expect(!rig.exists(rig.files(old)) && rig.exists(copy.appendingPathComponent("bin/tool"))
                         && rig.mode(copy.appendingPathComponent("bin/tool")) == 0o755
                         && rig.read(copy.appendingPathComponent("bin/tool")) == "program",
                     "the copy of the tool is under the new id, and its program is untouched")
        if case .success(let tool) = ExternalToolManifest.read(folder: copy) {
            suite.expect(tool.manifest.id == new && tool.publisher == "VitruvianSoftware",
                         "its manifest reads, names the new id and keeps the rest")
        } else {
            suite.expect(false, "the moved copy's manifest reads")
        }

        // What it saved.
        suite.expect(!rig.exists(rig.data(old))
                         && rig.read(rig.data(new).appendingPathComponent("settings.json")) == #"{"botDirectory":"~/bots"}"#
                         && rig.read(rig.data(new).appendingPathComponent("history/prompts.txt")) == "prompts",
                     "what the tool saved is under the new id, nested files too")

        // Preferences, shortcuts, panel.
        suite.expect(rig.defaults.object(forKey: "\(old.rawValue)/botDirectory") == nil
                         && rig.defaults.string(forKey: "\(new.rawValue)/botDirectory") == "~/bots"
                         && rig.defaults.bool(forKey: "\(new.rawValue)/autoStart")
                         && rig.defaults.string(forKey: "com.acme.deploys/note") == "keep",
                     "its preferences are saved under the new id, and another tool's are not touched")
        let shortcuts = ToolCommandShortcuts.load(from: rig.defaults)
        suite.expect(shortcuts["\(new.rawValue)/quickPrompt"] == GlobalShortcut(keyCode: 49, modifiers: [.command, .shift])
                         && shortcuts["\(old.rawValue)/quickPrompt"] == nil
                         && shortcuts["com.acme.deploys/run"] == GlobalShortcut(keyCode: 2, modifiers: [.command]),
                     "its Quick Prompt shortcut goes with it: \(shortcuts)")
        suite.expect(rig.defaults.string(forKey: DefaultsKey.panelHiddenExtensions) == "com.acme.deploys,dev.vitruvian.code"
                         && rig.defaults.string(forKey: DefaultsKey.panelExtensionOrder) == "dev.vitruvian.code,com.acme.deploys"
                         && rig.defaults.string(forKey: DefaultsKey.panelCollapsedExtensions) == "dev.vitruvian.code",
                     "its place in the menu bar panel's lists is kept, in the same position")

        // The record.
        let records = rig.records()
        let mine = records.first { $0.id == new.rawValue }
        suite.expect(records.count == 2 && records.first { $0.id == old.rawValue } == nil
                         && mine?.isOn == true && mine?.showsInIsland == false
                         && mine?.catalogue?.id == new.rawValue && mine?.catalogue?.version == "1.32.7"
                         && mine?.agreement.name == "Nexus Agent" && mine?.agreement.version == "1.32.7"
                         && mine?.agreement.date == rig.date
                         && mine?.agreement.fingerprint == ToolFingerprint.ofManifest(in: copy),
                     "the record says the same of it under the new id, with the fingerprint of the manifest now in the copy, "
                         + "so the app does not hold it back: \(records)")
        suite.expect(rig.mode(rig.folders.records) == 0o600, "and is still the person's alone")
    }

    static func aSecondRunChangesNothing(_ suite: TestSuite) {
        let rig = Rig("second")
        defer { rig.close() }
        rig.seedOldInstall()
        rig.migrate()
        let before = rig.snapshot()
        let logged = rig.logged.count

        let outcomes = rig.migrate()
        suite.expect(outcomes == [.notInstalled], "once it is moved, there is no tool under the old id: \(outcomes)")
        suite.expect(rig.snapshot() == before && rig.logged.count == logged,
                     "a second run changes no file and no preference, and logs nothing")
    }

    static func aLaunchThatStoppedHalfWayIsFinished(_ suite: TestSuite) {
        let rig = Rig("half")
        defer { rig.close() }
        rig.seedOldInstall()
        // The first launch moved the two folders and one preference, then ended.
        try? FileManager.default.moveItem(at: rig.files(old), to: rig.files(new))
        try? FileManager.default.moveItem(at: rig.data(old), to: rig.data(new))
        rig.defaults.set("~/bots", forKey: "\(new.rawValue)/botDirectory")
        rig.defaults.removeObject(forKey: "\(old.rawValue)/botDirectory")

        let outcomes = rig.migrate()
        suite.expect({ if case .migrated? = outcomes.first { return true } else { return false } }(),
                     "the next launch finishes the job: \(outcomes), \(rig.logged)")
        suite.expect(rig.records().map(\.id).contains(new.rawValue) && !rig.records().map(\.id).contains(old.rawValue)
                         && rig.defaults.bool(forKey: "\(new.rawValue)/autoStart")
                         && rig.defaults.string(forKey: "\(new.rawValue)/botDirectory") == "~/bots"
                         && rig.records().first { $0.id == new.rawValue }?.agreement.fingerprint
                             == ToolFingerprint.ofManifest(in: rig.files(new)),
                     "with the manifest, the rest of the preferences and the record done")
    }

    static func whatTheNewIdHasIsKept(_ suite: TestSuite) {
        let rig = Rig("kept")
        defer { rig.close() }
        rig.seedOldInstall()
        // The new id already has a data folder with a setting of its own, and a preference.
        rig.write("{\"new\":true}", to: rig.data(new).appendingPathComponent("settings.json"))
        rig.defaults.set("~/new", forKey: "\(new.rawValue)/botDirectory")

        rig.migrate()
        suite.expect(rig.read(rig.data(new).appendingPathComponent("settings.json")) == "{\"new\":true}"
                         && rig.read(rig.data(new).appendingPathComponent("history/prompts.txt")) == "prompts"
                         && rig.defaults.string(forKey: "\(new.rawValue)/botDirectory") == "~/new"
                         && rig.defaults.string(forKey: "\(old.rawValue)/botDirectory") == "~/bots"
                         && rig.defaults.object(forKey: "\(old.rawValue)/autoStart") == nil
                         && rig.defaults.bool(forKey: "\(new.rawValue)/autoStart")
                         && rig.logged.contains { $0.contains("kept \(old.rawValue)/botDirectory") },
                     "a file or preference the new id already has is never replaced, and the old preference is kept, and logged; "
                         + "what the new id lacks is filled in: \(rig.logged)")
    }

    static func bothInstalledIsLeftAlone(_ suite: TestSuite) {
        let rig = Rig("both")
        defer { rig.close() }
        let agreement = ToolAgreement(date: rig.date, name: "Code", version: "1.0.0", publisher: "VitruvianSoftware",
                                      fingerprint: String(repeating: "0", count: 64), source: "x")
        rig.seedOldInstall(extraRecords: [ToolRecord(id: new.rawValue, isOn: true, agreement: agreement)])
        let before = rig.snapshot()
        let outcomes = rig.migrate()
        suite.expect(outcomes == [.bothInstalled] && rig.snapshot() == before,
                     "with the new tool installed as well, nothing is moved or changed: \(outcomes)")
    }

    static func anUnreadableRecordIsLeftAlone(_ suite: TestSuite) {
        let rig = Rig("unreadable")
        defer { rig.close() }
        rig.seedOldInstall()
        rig.write("not json", to: rig.folders.records)
        let before = rig.snapshot()
        suite.expect(rig.migrate() == [.notInstalled] && rig.snapshot() == before
                         && rig.read(rig.folders.records) == "not json",
                     "a file of records that cannot be read is not changed, and nothing else is moved")
    }

    static func aTwoCopiesTrapKeepsTheRecord(_ suite: TestSuite) {
        let rig = Rig("trap")
        defer { rig.close() }
        rig.seedOldInstall()
        // A copy under the new id as well: which is the tool's, the app cannot know.
        rig.write("someone's", to: rig.files(new).appendingPathComponent("vitruvian-tool.json"))
        let outcomes = rig.migrate()
        suite.expect({ if case .failed? = outcomes.first { return true } else { return false } }()
                         && rig.records().map(\.id).contains(old.rawValue) && !rig.records().map(\.id).contains(new.rawValue)
                         && rig.exists(rig.files(old)),
                     "a step that cannot be done is reported, and the record stays as it was so the next launch tries again: \(outcomes)")
        suite.expect(rig.logged.contains { $0.contains("FAILED") }, "and the log says so")
    }

    /// A tool moves to its new id only once the catalog the app has loaded
    /// lists it: otherwise it would be a tool the catalog does not know.
    static func waitsForTheCatalogue(_ suite: TestSuite) {
        let rig = Rig("catalogue")
        defer { rig.close() }
        rig.seedOldInstall()
        let before = rig.snapshot()
        let recordBefore = rig.read(rig.folders.records)

        for (what, ids) in [("no catalog loaded", nil), ("a catalog with only the old id", Set([old])),
                            ("a catalog without either", Set([ToolID("com.acme.deploys")!]))] as [(String, Set<ToolID>?)] {
            rig.logged = []
            let outcomes = rig.migrate(catalogue: ids)
            suite.expect(outcomes == [.waitingForCatalogue] && rig.snapshot() == before
                             && rig.read(rig.folders.records) == recordBefore && rig.exists(rig.files(old))
                             && !rig.exists(rig.files(new)),
                         "\(what): nothing is moved: \(outcomes)")
            suite.expect(rig.logged.count == 1 && rig.logged[0].contains("does not list"),
                         "\(what): and it is said once: \(rig.logged)")
        }

        let outcomes = rig.migrate(catalogue: [old, new])
        suite.expect({ if case .migrated? = outcomes.first { return true }; return false }()
                         && rig.records().map(\.id).contains(new.rawValue),
                     "once the catalog lists the new id, the tool moves: \(outcomes)")
        suite.expect(rig.migrate(catalogue: [new]) == [.notInstalled], "and a second run finds nothing to do")
    }

    /// A copy whose manifest is not what the person agreed to is not given a
    /// new fingerprint: the record, the folders and the preferences stay.
    static func aChangedManifestIsNotCarriedOver(_ suite: TestSuite) {
        let rig = Rig("changed")
        defer { rig.close() }
        rig.seedOldInstall()
        let manifest = rig.files(old).appendingPathComponent("vitruvian-tool.json")
        try? (String(decoding: oldManifest, as: UTF8.self) + "\n").write(to: manifest, atomically: true, encoding: .utf8)
        let before = rig.snapshot()
        let recordBefore = rig.read(rig.folders.records)

        let outcomes = rig.migrate()
        suite.expect({ if case .heldBack(let why)? = outcomes.first { return why.first?.contains("not the one") == true }; return false }(),
                     "a manifest that is not the agreed one is reported: \(outcomes)")
        suite.expect(rig.snapshot() == before && rig.read(rig.folders.records) == recordBefore
                         && rig.exists(rig.files(old)) && !rig.exists(rig.files(new)),
                     "and nothing is moved, rewritten or re-agreed to")
        suite.expect(rig.logged.contains { $0.contains("left alone") }, "and the log says so: \(rig.logged)")
    }

    /// Once the migration has given the copy the new id, a launch that picks
    /// up after it judges the copy by what it was, and goes on.
    static func aResumedLaunchTrustsItsOwnRewrite(_ suite: TestSuite) {
        let rig = Rig("resumed")
        defer { rig.close() }
        rig.seedOldInstall()
        try? FileManager.default.moveItem(at: rig.files(old), to: rig.files(new))
        let manifest = rig.files(new).appendingPathComponent("vitruvian-tool.json")
        try? String(decoding: NexusAgentHandoffTests.manifest, as: UTF8.self).write(to: manifest, atomically: true, encoding: .utf8)
        let outcomes = rig.migrate()
        suite.expect({ if case .migrated? = outcomes.first { return true }; return false }(),
                     "a copy this migration already rewrote is not mistaken for a changed one: \(outcomes)")
    }

    /// The store does it before it reads its file, so the tool is back under
    /// the new id and is not held back.
    static func theStoreDoesItAtLaunch(_ suite: TestSuite) {
        let bench = ExternalToolStoreTests.Bench()
        defer { bench.close() }
        let rig = Rig("store")
        defer { rig.close() }
        rig.seedOldInstall()
        // The bench's support folder is the rig's.
        let folders = ToolFolders(root: bench.support)
        try? FileManager.default.createDirectory(at: bench.support, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: rig.support.appendingPathComponent("Tools"), to: bench.support.appendingPathComponent("Tools"))
        try? FileManager.default.copyItem(at: rig.support.appendingPathComponent("ToolData"), to: bench.support.appendingPathComponent("ToolData"))
        try? FileManager.default.copyItem(at: rig.folders.records, to: folders.records)

        let before = bench.relaunched()
        before.renamed = { ToolIDMigration.run(folders: $0, defaults: rig.defaults, catalogue: [new]) { _ in } }
        before.store.restore()
        suite.expect(before.store.isInstalled(new) && !before.store.isInstalled(old)
                         && before.store.listed.map(\.id) == [ToolID("com.acme.deploys")!, new]
                         && before.store.listed.first { $0.id == new }?.isHeld == false,
                     "a launch with a tool under the old id brings it back under the new, and not held back: "
                         + "\(before.store.listed.map { "\($0.id) held=\($0.isHeld)" }), \(rig.logged)")

        let again = bench.relaunched()
        again.renamed = { ToolIDMigration.run(folders: $0, defaults: rig.defaults, catalogue: [new]) { _ in } }
        again.store.restore()
        suite.expect(again.store.isInstalled(new) && again.store.listed.count == 2,
                     "and the launch after it finds the same tools")
    }
}
