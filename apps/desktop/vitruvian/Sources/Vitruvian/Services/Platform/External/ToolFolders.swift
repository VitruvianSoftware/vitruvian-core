// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Darwin
import Foundation
import VitruvianCore

/// Where a tool that runs as its own program lives once it is added: two
/// folders under the app's support folder, each named by the tool's id.
///
///     <support>/Tools/<id>/     the app's copy of the tool's files
///     <support>/ToolData/<id>/  a folder for what the tool saves
///
/// An id is letters, digits, dots, hyphens and underscores, with no dot at
/// either end and no two in a row, so it is always one safe folder name.
/// Only an id with a dot has folders: one with none is the app's own.
///
/// The copy is for stability, not safety: the folder the person picked can
/// move or be deleted. A tool is trusted like an app and can rewrite its
/// copy.
///
/// The picked folder may be one nothing can be written in, as a folder
/// copied out of a build or unpacked from a zip can be. In the app's copy
/// the person may read, write and enter every folder and read and write
/// every file; nothing else about who may do what is changed, so what
/// could be run still can be and nothing more can. And whatever the app is
/// to delete here, it can: a folder that may not be written in is opened
/// up first.
package struct ToolFolders: Equatable, Sendable {
    package enum Problem: Error, Equatable, Sendable {
        /// The id has no dot.
        case notAnOutsideTool
        /// The folder to add is one of the app's own tool folders, or
        /// inside one. Copying it over itself would lose it.
        case insideTheApp
        /// One of the tool's folders is, through a link, somewhere other
        /// than under the app's support folder. Nothing is copied there and
        /// nothing there is deleted.
        case linkedElsewhere
        /// The files could not be copied, or a folder could not be made.
        case notCopied
    }

    /// A tool's two folders.
    package struct Place: Equatable, Sendable {
        package let files: URL
        package let data: URL

        package init(files: URL, data: URL) {
            self.files = files
            self.data = data
        }
    }

    /// How much a folder holds: the bytes of its files, and how many things
    /// are in it, files, folders and links together.
    package struct Weight: Equatable, Sendable {
        package let bytes: Int
        package let items: Int

        package init(bytes: Int, items: Int) {
            self.bytes = bytes
            self.items = items
        }
    }

    /// The app's support folder.
    package let root: URL

    package init(root: URL) {
        self.root = root
    }

    /// Under the app's own support folder; nil outside a real app bundle.
    package static var live: ToolFolders? { PrivateFileStore.containerURL.map(ToolFolders.init(root:)) }

    /// The tool's two folders; nil for an id with no dot.
    package func place(for id: ToolID) -> Place? {
        guard !id.isBundledForm else { return nil }
        return Place(files: root.appendingPathComponent("Tools", isDirectory: true)
                         .appendingPathComponent(id.rawValue, isDirectory: true),
                     data: root.appendingPathComponent("ToolData", isDirectory: true)
                         .appendingPathComponent(id.rawValue, isDirectory: true))
    }

    /// The file the tool store keeps its records in.
    package var records: URL { root.appendingPathComponent(ToolRecords.fileName) }

    /// The tool's two folders, when the app's copy of it is there and each
    /// folder is still where it is said to be, with every link followed.
    /// The data folder is made again when it has gone. Nil otherwise: there
    /// is nothing the app may run.
    package func existing(_ id: ToolID, fileManager: FileManager = .default) -> Place? {
        guard let place = place(for: id) else { return nil }
        let home = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var isFolder: ObjCBool = false
        guard fileManager.fileExists(atPath: place.files.path, isDirectory: &isFolder), isFolder.boolValue,
              stays(place.files.deletingLastPathComponent(), at: home + ["Tools"], fileManager),
              stays(place.files, at: home + ["Tools", id.rawValue], fileManager),
              stays(place.data.deletingLastPathComponent(), at: home + ["ToolData"], fileManager),
              stays(place.data, at: home + ["ToolData", id.rawValue], fileManager),
              PrivateFileStore.createDirectory(at: place.data, container: root) else { return nil }
        return place
    }

    /// Copies the folder at `source` to be the app's copy of the tool,
    /// in place of any copy already there, and makes the tool's data
    /// folder when it has none. What the tool saved before is kept.
    ///
    /// The copy is made beside its place and moved in when it is whole, so
    /// a copy that fails leaves the old one as it was. Whatever an earlier
    /// copy left beside it is deleted first, and nothing is left there
    /// after, whether this one fails or not.
    package func install(_ id: ToolID, from source: URL,
                         fileManager: FileManager = .default) -> Result<Place, Problem> {
        guard let place = place(for: id) else { return .failure(.notAnOutsideTool) }
        guard !holds(source) else { return .failure(.insideTheApp) }
        let home = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        // With every link followed, each folder this writes to or deletes
        // from is still where it is said to be, under the support folder.
        for (folder, names) in [(place.files.deletingLastPathComponent(), ["Tools"]),
                                (place.data.deletingLastPathComponent(), ["ToolData"]),
                                (place.data, ["ToolData", id.rawValue])]
        where !stays(folder, at: home + names, fileManager) {
            return .failure(.linkedElsewhere)
        }
        // No id can be named this: an id never starts with a dot.
        let incoming = place.files.deletingLastPathComponent()
            .appendingPathComponent(".incoming", isDirectory: true)
        let copy = incoming.appendingPathComponent(id.rawValue, isDirectory: true)
        Self.remove(incoming, fileManager)
        defer { Self.remove(incoming, fileManager) }
        guard PrivateFileStore.createDirectory(at: incoming, container: root),
              (try? fileManager.copyItem(at: source, to: copy)) != nil else { return .failure(.notCopied) }
        // A folder may only be moved, and later replaced or deleted, when
        // it can be written in. The copy has the picked folder's modes.
        Self.letOwnerChange(copy, files: true, fileManager)
        Self.remove(place.files, fileManager)
        guard (try? fileManager.moveItem(at: copy, to: place.files)) != nil,
              PrivateFileStore.createDirectory(at: place.data, container: root) else { return .failure(.notCopied) }
        return .success(place)
    }

    /// Deletes the app's copy of a tool and, with `data`, the folder of
    /// what the tool saved. False when something that should have gone is
    /// still there.
    ///
    /// It can delete two things only: `Tools/<id>` and `ToolData/<id>`. An
    /// id is one folder name, so neither can be `Tools`, `ToolData` or the
    /// support folder. The folder each is in must be the app's own with
    /// every link followed, or nothing in it is touched. When `Tools/<id>`
    /// is itself a link, the link goes and what it points at stays.
    @discardableResult
    package func delete(_ id: ToolID, data: Bool, fileManager: FileManager = .default) -> Bool {
        guard let place = place(for: id) else { return false }
        let home = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var gone = true
        for (folder, parent) in [(place.files, "Tools")] + (data ? [(place.data, "ToolData")] : []) {
            // Asked of the entry itself, not of what a link points at.
            guard (try? fileManager.attributesOfItem(atPath: folder.path)) != nil else { continue }
            guard stays(folder.deletingLastPathComponent(), at: home + [parent], fileManager),
                  Self.remove(folder, fileManager) else {
                gone = false
                continue
            }
        }
        return gone
    }

    /// What is still there of a tool that was to be deleted: its copy, and
    /// with `data` the folder of what it saved, the copy first. Empty when
    /// `delete` did all it was asked. Asked of each entry itself, not of
    /// what a link points at.
    package func undeleted(_ id: ToolID, data: Bool, fileManager: FileManager = .default) -> [URL] {
        guard let place = place(for: id) else { return [] }
        return ([place.files] + (data ? [place.data] : [])).filter {
            (try? fileManager.attributesOfItem(atPath: $0.path)) != nil
        }
    }

    /// Whether `folder` is, with every link followed, one of the app's own
    /// tool folders or inside one.
    package func holds(_ folder: URL) -> Bool {
        let from = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let home = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return ["Tools", "ToolData"].contains { Array(from.prefix(home.count + 1)) == home + [$0] }
    }

    /// Adds up what `folder` holds, and stops as soon as it holds more than
    /// `limit` in bytes or in things: nil then. A link is counted as one
    /// thing and never followed, which is also how the folder is copied. A
    /// folder that cannot be read weighs nothing; copying it fails later.
    package static func weight(of folder: URL, within limit: Weight,
                               fileManager: FileManager = .default) -> Weight? {
        var bytes = 0
        var items = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walk = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                                errorHandler: { _, _ in true }) else {
            return Weight(bytes: 0, items: 0)
        }
        for case let url as URL in walk {
            items += 1
            if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                bytes += values.fileSize ?? 0
            }
            if bytes > limit.bytes || items > limit.items { return nil }
        }
        return Weight(bytes: bytes, items: items)
    }

    /// Whether macOS has quarantined the file at `url`, as it does to what
    /// is downloaded from the web. It will not start such a program.
    package static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0
    }

    /// Deletes what is at `url`, a folder with all it holds or a single
    /// file or link. False when it is still there. Nothing there is done.
    ///
    /// `removeItem` cannot empty a folder that may not be written in, and
    /// stops there with part of the tree deleted. So when it fails, every
    /// folder in the tree is opened to the person and it is tried again.
    /// A link is deleted as a link: what it points at is never opened,
    /// changed or deleted.
    @discardableResult
    private static func remove(_ url: URL, _ fileManager: FileManager) -> Bool {
        var entry = stat()
        guard lstat(url.path, &entry) == 0 else { return true }
        if (try? fileManager.removeItem(at: url)) != nil { return true }
        letOwnerChange(url, files: false, fileManager)
        return (try? fileManager.removeItem(at: url)) != nil
    }

    /// Lets the person read, write and enter the folder at `url` and every
    /// folder in it, and with `files` read and write every file in it. No
    /// other bit of a mode is touched, so nothing becomes a program that
    /// was not one, and nobody else gains anything.
    ///
    /// Each entry is asked about and changed as itself: a link is neither
    /// followed nor changed, so nothing outside `url` is.
    private static func letOwnerChange(_ url: URL, files: Bool, _ fileManager: FileManager) {
        var entry = stat()
        guard lstat(url.path, &entry) == 0 else { return }
        let mode = entry.st_mode & 0o7777
        switch entry.st_mode & S_IFMT {
        case S_IFDIR:
            if mode & 0o700 != 0o700 { _ = lchmod(url.path, mode | 0o700) }
            for name in (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? [] {
                letOwnerChange(url.appendingPathComponent(name), files: files, fileManager)
            }
        case S_IFREG where files:
            if mode & 0o600 != 0o600 { _ = lchmod(url.path, mode | 0o600) }
        default:
            break
        }
    }

    /// False when something is at `url` and, with every link followed, it
    /// is somewhere other than `components`. Nothing there yet is fine: it
    /// is made as a plain folder.
    private func stays(_ url: URL, at components: [String], _ fileManager: FileManager) -> Bool {
        guard (try? fileManager.attributesOfItem(atPath: url.path)) != nil else { return true }
        return url.resolvingSymlinksInPath().standardizedFileURL.pathComponents == components
    }
}
