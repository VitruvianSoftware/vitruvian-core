// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore
import VitruvianServices

/// A tool folder nothing may be written in, as one copied out of a build
/// or unpacked from a zip can be: it is added, updated and removed like any
/// other, and a copy that failed never stands in the way of the next.
extension ExternalToolStoreTests {
    static func readOnlyFolders(_ suite: TestSuite) {
        aReadOnlyFolderIsAdded(suite)
        aFailedCopyLeavesNothing(suite)
        whatAnOlderVersionLeftIsCleared(suite)
        aReadOnlyCopyIsReplacedAndDeleted(suite)
        aReadOnlyToolThroughTheStore(suite)
    }

    private static func mode(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }

    /// Takes away leave to write from `folder` and all it holds, or with
    /// `writable` gives it back to the folders, which is all it takes to
    /// delete them. A link is left as it is, and so is what it points at.
    private static func make(_ folder: URL, writable: Bool) {
        let manager = FileManager.default
        let inside = ((try? manager.subpathsOfDirectory(atPath: folder.path)) ?? []).sorted()
        // A folder is closed after what it holds, and opened before.
        for path in writable ? [""] + inside : inside.reversed() + [""] {
            let url = path.isEmpty ? folder : folder.appendingPathComponent(path)
            guard let found = try? manager.attributesOfItem(atPath: url.path),
                  let type = found[.type] as? FileAttributeType, type != .typeSymbolicLink,
                  let mode = found[.posixPermissions] as? Int else { continue }
            let next = writable ? mode | (type == .typeDirectory ? 0o700 : 0) : mode & ~0o222
            try? manager.setAttributes([.posixPermissions: next], ofItemAtPath: url.path)
        }
    }

    /// Deletes a bench's folders, whatever a test left read-only in them.
    private static func discard(_ bench: Bench) {
        make(bench.root, writable: true)
        bench.close()
    }

    private static func aReadOnlyFolderIsAdded(_ suite: TestSuite) {
        let bench = Bench()
        defer { discard(bench) }
        let folders = ToolFolders(root: bench.support)
        // Somebody else's folder, which a link in the picked one points at.
        let elsewhere = bench.root.appendingPathComponent("elsewhere", isDirectory: true)
        let theirs = elsewhere.appendingPathComponent("theirs")
        try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try? Data("theirs".utf8).write(to: theirs)
        make(elsewhere, writable: false)
        let before = [mode(elsewhere), mode(theirs)]

        let picked = bench.folder()
        try? Data("notes".utf8).write(to: picked.appendingPathComponent("README"))
        FileManager.default.createFile(atPath: picked.appendingPathComponent("private").path,
                                       contents: Data("mine".utf8), attributes: [.posixPermissions: 0o600])
        try? FileManager.default.createSymbolicLink(at: picked.appendingPathComponent("out"),
                                                    withDestinationURL: elsewhere)
        make(picked, writable: false)
        let asPicked = ["", "bin", "bin/deploys", "vitruvian-tool.json", "README", "private"]
            .map { mode(picked.appendingPathComponent($0)) }

        let added = folders.install(id, from: picked)
        suite.expect(added == .success(.init(files: bench.files, data: bench.data))
                         && bench.exists(bench.files.appendingPathComponent("bin/deploys"))
                         && !bench.exists(bench.support.appendingPathComponent("Tools/.incoming")),
                     "a folder nothing may be written in is added, and nothing half-made is left beside the copy")
        suite.expect(asPicked == [0o555, 0o555, 0o555, 0o444, 0o444, 0o400]
                         && ["", "bin", "bin/deploys", "vitruvian-tool.json", "README", "private"]
                             .map { mode(bench.files.appendingPathComponent($0)) }
                             == [0o755, 0o755, 0o755, 0o644, 0o644, 0o600],
                     "in the app's copy the person may write every folder and file; nothing else about who may "
                         + "do what is changed: what could be run can be, and nothing more")
        suite.expect(["", "bin", "bin/deploys", "vitruvian-tool.json", "README", "private"]
                         .map { mode(picked.appendingPathComponent($0)) } == asPicked
                         && [mode(elsewhere), mode(theirs)] == before && before == [0o555, 0o444]
                         && (try? FileManager.default.destinationOfSymbolicLink(
                             atPath: bench.files.appendingPathComponent("out").path)) == elsewhere.path,
                     "the picked folder is left as it was, and so is what a link in it points at: "
                         + "only the copy is opened up")
        suite.expect(folders.delete(id, data: true) && !bench.exists(bench.files) && bench.exists(theirs)
                         && [mode(elsewhere), mode(theirs)] == before,
                     "deleting that copy leaves what its link points at as it was")
    }

    private static func aFailedCopyLeavesNothing(_ suite: TestSuite) {
        let bench = Bench()
        defer { discard(bench) }
        let folders = ToolFolders(root: bench.support)
        // A folder that is copied in part: one file in it cannot be read.
        // The part that was copied is read-only.
        let broken = bench.folder("broken")
        FileManager.default.createFile(atPath: broken.appendingPathComponent("zz-unreadable").path,
                                       contents: Data("no".utf8), attributes: [.posixPermissions: 0o000])
        make(broken, writable: false)
        let incoming = bench.support.appendingPathComponent("Tools/.incoming")
        suite.expect(folders.install(id, from: broken) == .failure(.notCopied) && !bench.exists(incoming)
                         && !bench.exists(bench.files),
                     "a read-only folder that cannot be copied whole is not added, and what was copied of it is gone")
        suite.expect(folders.install(id, from: bench.folder()) == .success(.init(files: bench.files, data: bench.data))
                         && bench.exists(bench.files.appendingPathComponent("bin/deploys")) && !bench.exists(incoming),
                     "and the next folder picked for that tool is added")
    }

    private static func whatAnOlderVersionLeftIsCleared(_ suite: TestSuite) {
        let bench = Bench()
        defer { discard(bench) }
        let folders = ToolFolders(root: bench.support)
        // What a version before this one left when a copy failed: a
        // read-only copy beside the tool's place, of it and of another.
        let incoming = bench.support.appendingPathComponent("Tools/.incoming", isDirectory: true)
        for left in [id.rawValue, "com.acme.other"] {
            let old = incoming.appendingPathComponent("\(left)/bin/old")
            try? FileManager.default.createDirectory(at: old.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? Data("old".utf8).write(to: old)
        }
        make(incoming, writable: false)
        suite.expect(mode(incoming.appendingPathComponent(id.rawValue)) == 0o555
                         && folders.install(id, from: bench.folder()) == .success(.init(files: bench.files, data: bench.data))
                         && bench.exists(bench.files.appendingPathComponent("bin/deploys"))
                         && !bench.exists(bench.files.appendingPathComponent("bin/old")) && !bench.exists(incoming),
                     "a read-only copy an earlier failure left behind is cleared first: it does not stop the tool "
                         + "being added, and none of it is in the new copy")
    }

    private static func aReadOnlyCopyIsReplacedAndDeleted(_ suite: TestSuite) {
        let bench = Bench()
        defer { discard(bench) }
        let folders = ToolFolders(root: bench.support)
        let picked = bench.folder()
        _ = folders.install(id, from: picked)
        // The app's copy, read-only: as a version before this one made it,
        // or as the tool itself left it.
        try? Data("old".utf8).write(to: bench.files.appendingPathComponent("bin/old"))
        make(bench.files, writable: false)
        try? Data("new".utf8).write(to: picked.appendingPathComponent("notes"))
        suite.expect(mode(bench.files) == 0o555
                         && folders.install(id, from: picked) == .success(.init(files: bench.files, data: bench.data))
                         && bench.exists(bench.files.appendingPathComponent("notes"))
                         && !bench.exists(bench.files.appendingPathComponent("bin/old"))
                         && !bench.exists(bench.support.appendingPathComponent("Tools/.incoming")),
                     "a copy nothing may be written in is replaced whole by the newer folder")

        try? FileManager.default.createDirectory(at: bench.data.appendingPathComponent("cache"),
                                                 withIntermediateDirectories: true)
        try? Data("kept".utf8).write(to: bench.data.appendingPathComponent("cache/saved"))
        make(bench.files, writable: false)
        make(bench.data, writable: false)
        suite.expect(folders.delete(id, data: false) && !bench.exists(bench.files)
                         && bench.exists(bench.data.appendingPathComponent("cache/saved")) && mode(bench.data) == 0o500,
                     "a copy nothing may be written in is deleted, and what the tool saved is left as it was")
        suite.expect(folders.delete(id, data: true) && !bench.exists(bench.data)
                         && folders.undeleted(id, data: true).isEmpty,
                     "and so is the folder of what it saved, when that is to go")
    }

    private static func aReadOnlyToolThroughTheStore(_ suite: TestSuite) {
        let bench = Bench()
        defer { discard(bench) }
        let picked = bench.folder()
        make(picked, writable: false)
        var added = false
        if case .success = bench.add(picked) { added = true }
        suite.expect(added && bench.store.isInstalled(id) && bench.records.count == 1
                         && !bench.exists(bench.support.appendingPathComponent("Tools/.incoming")),
                     "the store adds a tool whose folder is read-only")
        var updated = false
        if case .success = bench.add(picked, on: Date(timeIntervalSince1970: 1_770_000_000)) { updated = true }
        suite.expect(updated && bench.store.isInstalled(id) && bench.records.count == 1,
                     "and adds it again over its own copy, as an update does")
        make(bench.files, writable: false)
        suite.expect(bench.store.remove(id, deletingData: true) == .deleted && !bench.exists(bench.files)
                         && !bench.exists(bench.data) && !bench.store.isInstalled(id),
                     "and removes it with every file, read-only or not")
    }
}
