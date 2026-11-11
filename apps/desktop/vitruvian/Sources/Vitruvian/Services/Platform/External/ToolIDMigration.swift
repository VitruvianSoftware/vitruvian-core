// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

/// Brings a tool the person added under an id that has since been renamed
/// over to its new id, at launch, before any tool is started.
///
/// An id is what the app keys everything about a tool by: the folder of its
/// files, the folder of what it saved, its preferences, its shortcuts, its
/// place in the menu bar panel and its line in the file of what the person
/// agreed to. A tool whose id changes would otherwise be a stranger to all of
/// it, and its person would lose their settings. So the same tool, with the
/// same program, is given its new id in each place.
///
/// The one rename so far is Nexus Agent to Vitruvian Code
/// (`dev.vitruvian.nexus-agent` to `dev.vitruvian.code`, the brand standard in
/// docs/standards/brand.md). The copy of the old tool keeps working until the
/// catalog's tool, under the new id, updates it, which it does as an ordinary
/// update because the record now says which entry it came from.
///
/// Each step looks at what is there and does only what is left, so a launch
/// that stopped half way is finished by the next, and a second run changes
/// nothing. The record of the tool is rewritten last: until it is, the tool
/// is still waiting to be moved. Nothing is deleted, other than a folder
/// that the move left empty.
package enum ToolIDMigration {
    package struct Rename: Equatable, Sendable {
        package let from: ToolID
        package let to: ToolID

        package init(from: ToolID, to: ToolID) {
            self.from = from
            self.to = to
        }
    }

    /// The ids that have been renamed.
    package static let renames: [Rename] = [
        Rename(from: ToolID("dev.vitruvian.nexus-agent")!, to: ToolID("dev.vitruvian.code")!),
    ]

    package enum Outcome: Equatable, Sendable {
        /// Nobody added a tool under the old id, or the file of records
        /// cannot be read (and is left exactly as it is).
        case notInstalled
        /// Both ids are installed. Neither is touched: the person has
        /// added the new tool already, and the old one is theirs to remove.
        case bothInstalled
        /// The copy of the tool is not what the person agreed to (its
        /// manifest has other bytes than the record's fingerprint). The
        /// record and everything else are left exactly as they are, so the
        /// app holds the tool back as it already did; this says why.
        case heldBack([String])
        /// The catalog the app has loaded does not list the new id (or none
        /// has been loaded yet), so the tool stays as it is: moved, it would
        /// be a tool the catalog does not know, with no updates, while the old
        /// entry were offered for installing again. Tried again at every launch.
        case waitingForCatalogue
        /// Moved; what was done, in order.
        case migrated([String])
        /// Something could not be moved. What was done is kept, the record
        /// stays as it was, and the next launch tries the rest.
        case failed([String])
    }

    /// Runs every rename in `renames`. `defaults` is where the app keeps its
    /// preferences, including the tools'. `catalogue` is the ids of the tools
    /// the catalog the app has loaded lists (the one kept from the last
    /// launch), or nil when it has none: a tool moves to its new id only once
    /// the catalog lists that id.
    @discardableResult
    package static func run(_ renames: [Rename] = renames, folders: ToolFolders, defaults: UserDefaults,
                            catalogue: Set<ToolID>?, fileManager: FileManager = .default,
                            log: (String) -> Void) -> [Outcome] {
        renames.map {
            migrate($0, folders: folders, defaults: defaults, catalogue: catalogue, fileManager: fileManager, log: log)
        }
    }

    package static func migrate(_ rename: Rename, folders: ToolFolders, defaults: UserDefaults,
                                catalogue: Set<ToolID>?, fileManager: FileManager = .default,
                                log: (String) -> Void) -> Outcome {
        let from = rename.from
        let to = rename.to
        let records: [ToolRecord]
        switch ToolRecords.read(at: folders.records, fileManager: fileManager) {
        case .none, .unreadable:
            return .notInstalled
        case .records(let saved):
            records = saved
        }
        guard let index = records.firstIndex(where: { $0.id == from.rawValue }) else { return .notInstalled }
        if records.contains(where: { $0.id == to.rawValue }) {
            log("tool \(from.rawValue) and \(to.rawValue) are both installed; the old one is left alone")
            return .bothInstalled
        }
        guard catalogue?.contains(to) == true else {
            log("tool \(from.rawValue) stays as it is: the catalog does not list \(to.rawValue) yet")
            return .waitingForCatalogue
        }
        guard let old = folders.place(for: from), let new = folders.place(for: to) else {
            return .failed(["\(from.rawValue) or \(to.rawValue) is not an id an outside tool may have"])
        }
        // Only a copy the person agreed to is carried over. A copy that was
        // changed since stays as it is: moving it under a new id and writing
        // down a new fingerprint would make the app trust it.
        if let why = fingerprintProblem(records[index], from: from, to: to, old: old, new: new, fileManager) {
            log("tool \(from.rawValue) is left alone: \(why)")
            return .heldBack([why])
        }

        var done: [String] = []
        var problems: [String] = []
        func note(_ step: String) {
            done.append(step)
            log("\(from.rawValue) to \(to.rawValue): \(step)")
        }
        func problem(_ text: String) {
            problems.append(text)
            log("\(from.rawValue) to \(to.rawValue): FAILED, will retry at the next launch: \(text)")
        }

        // What the tool saved. Moved piece by piece, so a folder the new id
        // already has (the app makes one when it starts a tool) is filled
        // in, not replaced.
        switch mergeMove(old.data, into: new.data, fileManager) {
        case .nothing: break
        case .moved(let count): note("moved \(count) item(s) of what the tool saved")
        case .failed(let why): problem("what the tool saved: \(why)")
        }

        // The app's copy of the tool.
        let hasOldCopy = exists(old.files, fileManager)
        let hasNewCopy = exists(new.files, fileManager)
        if hasOldCopy && !hasNewCopy {
            do {
                try fileManager.createDirectory(at: new.files.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
                try fileManager.moveItem(at: old.files, to: new.files)
                note("moved the tool's files")
            } catch {
                problem("the tool's files: \(error.localizedDescription)")
            }
        } else if hasOldCopy && hasNewCopy {
            problem("the tool's files are in both \(old.files.lastPathComponent) and \(new.files.lastPathComponent)")
        }
        if exists(new.files, fileManager) {
            switch rewriteManifest(in: new.files, from: from, to: to, fileManager) {
            case .unchanged: break
            case .rewritten: note("gave the tool's manifest its new id")
            case .failed(let why): problem("the tool's manifest: \(why)")
            }
        } else {
            problem("the app has no copy of the tool's files")
        }

        // What the tool is keeps its preferences, its shortcuts and its
        // place in the menu bar panel under the id.
        let preferences = movePreferences(from: from, to: to, defaults, log: log)
        if preferences > 0 { note("moved \(preferences) preference(s)") }
        if moveShortcuts(from: from, to: to, defaults) { note("moved the tool's shortcuts") }
        if movePanelLists(from: from, to: to, defaults) { note("moved the tool's place in the menu bar panel") }

        // The record last: once it is rewritten, there is nothing left to do.
        guard problems.isEmpty else { return .failed(problems) }
        guard let fingerprint = ToolFingerprint.ofManifest(in: new.files, fileManager: fileManager) else {
            return .failed(["the tool's manifest cannot be read"])
        }
        var rewritten = records
        rewritten[index] = renamed(records[index], to: to, from: from, fingerprint: fingerprint)
        if ToolRecords.write(rewritten, to: folders.records) {
            note("renamed the tool in the record of added tools")
            return .migrated(done)
        }
        problem("the record of added tools could not be written")
        return .failed(problems)
    }

    // MARK: - The record

    /// Why the copy is not the one agreed to; nil when it is, or when there
    /// is no single copy to judge (the steps below say that). Judged by the
    /// bytes of its manifest, as the app does at every launch. A copy this
    /// migration has already given the new id is judged as it was.
    private static func fingerprintProblem(_ record: ToolRecord, from: ToolID, to: ToolID,
                                           old: ToolFolders.Place, new: ToolFolders.Place,
                                           _ fileManager: FileManager) -> String? {
        let agreed = record.agreement.fingerprint
        let hasOld = exists(old.files, fileManager)
        let hasNew = exists(new.files, fileManager)
        guard hasOld != hasNew else { return nil }
        let folder = hasOld ? old.files : new.files
        guard let data = fileManager.contents(atPath: folder.appendingPathComponent(ToolManifestFile.fileName).path) else {
            return "its manifest cannot be read"
        }
        if ToolFingerprint.of(data) == agreed { return nil }
        if hasNew, let text = String(data: data, encoding: .utf8),
           ToolFingerprint.of(Data(text.replacingOccurrences(of: "\"\(to.rawValue)\"", with: "\"\(from.rawValue)\"").utf8)) == agreed {
            return nil
        }
        return "its manifest is not the one the person agreed to"
    }

    private static func renamed(_ record: ToolRecord, to: ToolID, from: ToolID, fingerprint: String) -> ToolRecord {
        let agreement = ToolAgreement(date: record.agreement.date, name: record.agreement.name,
                                      version: record.agreement.version, publisher: record.agreement.publisher,
                                      fingerprint: fingerprint, source: record.agreement.source)
        let catalogue = record.catalogue.map { origin in
            origin.id == from.rawValue
                ? CatalogueOrigin(id: to.rawValue, version: origin.version, source: origin.source,
                                  download: origin.download)
                : origin
        }
        return ToolRecord(id: to.rawValue, isOn: record.isOn, agreement: agreement, catalogue: catalogue,
                          showsInIsland: record.showsInIsland, showsStatus: record.showsStatus)
    }

    // MARK: - Files

    private static func exists(_ url: URL, _ fileManager: FileManager) -> Bool {
        // Asked of the entry itself, not of what a link points at.
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }

    private enum Moved {
        case nothing
        case moved(Int)
        case failed(String)
    }

    /// Moves what is in `source` that `destination` does not have, and takes
    /// `source` away when that leaves it empty. What both have stays where
    /// it is, and `destination`'s is the one that counts.
    private static func mergeMove(_ source: URL, into destination: URL, _ fileManager: FileManager) -> Moved {
        guard exists(source, fileManager) else { return .nothing }
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isFolder), isFolder.boolValue else {
            return .failed("\(source.lastPathComponent) is not a folder")
        }
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            if !exists(destination, fileManager) {
                try fileManager.moveItem(at: source, to: destination)
                let count = (try? fileManager.subpathsOfDirectory(atPath: destination.path).count) ?? 0
                return .moved(max(count, 1))
            }
            var moved = 0
            try merge(source, into: destination, fileManager, moved: &moved)
            if (try? fileManager.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
                try fileManager.removeItem(at: source)
            }
            return moved == 0 ? .nothing : .moved(moved)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func merge(_ source: URL, into destination: URL, _ fileManager: FileManager,
                              moved: inout Int) throws {
        for name in try fileManager.contentsOfDirectory(atPath: source.path).sorted() {
            let from = source.appendingPathComponent(name)
            let to = destination.appendingPathComponent(name)
            if !exists(to, fileManager) {
                try fileManager.moveItem(at: from, to: to)
                moved += 1
                continue
            }
            var fromIsFolder: ObjCBool = false
            var toIsFolder: ObjCBool = false
            if fileManager.fileExists(atPath: from.path, isDirectory: &fromIsFolder), fromIsFolder.boolValue,
               fileManager.fileExists(atPath: to.path, isDirectory: &toIsFolder), toIsFolder.boolValue {
                try merge(from, into: to, fileManager, moved: &moved)
                if (try? fileManager.contentsOfDirectory(atPath: from.path))?.isEmpty == true {
                    try fileManager.removeItem(at: from)
                }
            }
        }
    }

    private enum Rewrite {
        case unchanged
        case rewritten
        case failed(String)
    }

    /// Puts the new id in the manifest of the app's copy, which has the old
    /// one: the app refuses a copy whose manifest names another id than its
    /// folder's. Only the id's text is replaced; the rest is as it was.
    private static func rewriteManifest(in folder: URL, from: ToolID, to: ToolID, _ fileManager: FileManager) -> Rewrite {
        let file = folder.appendingPathComponent(ToolManifestFile.fileName)
        guard let data = fileManager.contents(atPath: file.path), let text = String(data: data, encoding: .utf8) else {
            return .failed("cannot be read")
        }
        let old = "\"\(from.rawValue)\""
        let new = "\"\(to.rawValue)\""
        guard text.contains(old) else {
            return text.contains(new) ? .unchanged : .failed("names neither \(from.rawValue) nor \(to.rawValue)")
        }
        let mode = (try? fileManager.attributesOfItem(atPath: file.path))?[.posixPermissions]
        do {
            try Data(text.replacingOccurrences(of: old, with: new).utf8).write(to: file, options: .atomic)
            if let mode { try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: file.path) }
            return .rewritten
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Preferences

    /// Every preference saved under the old id (`<id>/<preference>`) is saved
    /// under the new one, and the old one goes. Where the new id already has a
    /// value the new one counts and the old one is kept, and the log says so:
    /// it may be something the person set. Returns how many were moved.
    private static func movePreferences(from: ToolID, to: ToolID, _ defaults: UserDefaults,
                                        log: (String) -> Void) -> Int {
        let prefix = from.rawValue + "/"
        var moved = 0
        for key in defaults.dictionaryRepresentation().keys.sorted() where key.hasPrefix(prefix) {
            let target = to.rawValue + "/" + key.dropFirst(prefix.count)
            guard defaults.object(forKey: target) == nil, let value = defaults.object(forKey: key) else {
                log("\(from.rawValue) to \(to.rawValue): kept \(key) as it is, \(target) has a value already")
                continue
            }
            defaults.set(value, forKey: target)
            defaults.removeObject(forKey: key)
            moved += 1
        }
        return moved
    }

    /// The shortcuts the person gave the tool's commands, which are saved
    /// by command id (`<tool id>/<command>`).
    private static func moveShortcuts(from: ToolID, to: ToolID, _ defaults: UserDefaults) -> Bool {
        var shortcuts = ToolCommandShortcuts.load(from: defaults)
        let theirs = shortcuts.keys.filter { CommandID($0)?.tool == from }.sorted()
        guard !theirs.isEmpty else { return false }
        for key in theirs {
            let shortcut = shortcuts.removeValue(forKey: key)
            if let name = CommandID(key)?.name, let renamed = CommandID(tool: to, name: name),
               shortcuts[renamed.rawValue] == nil, let shortcut {
                shortcuts[renamed.rawValue] = shortcut
            }
        }
        ToolCommandShortcuts.save(shortcuts, to: defaults)
        return true
    }

    /// The menu bar panel's Extensions tab keeps three lists of tool ids,
    /// each as one line of ids with commas between: which are switched off,
    /// in what order, and which are collapsed.
    private static func movePanelLists(from: ToolID, to: ToolID, _ defaults: UserDefaults) -> Bool {
        var changed = false
        for key in [DefaultsKey.panelHiddenExtensions, DefaultsKey.panelExtensionOrder,
                    DefaultsKey.panelCollapsedExtensions] {
            guard let line = defaults.string(forKey: key) else { continue }
            let ids = line.split(separator: ",").map(String.init)
            guard ids.contains(from.rawValue) else { continue }
            var next: [String] = []
            for id in ids {
                let mapped = id == from.rawValue ? to.rawValue : id
                if !next.contains(mapped) { next.append(mapped) }
            }
            defaults.set(next.joined(separator: ","), forKey: key)
            changed = true
        }
        return changed
    }
}
