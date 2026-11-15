// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import VitruvianAtriumCore

/// Offers to review an app moved from an Applications folder to the local Trash.
/// Builds on the approach first proposed by ilim-cell in #3755.
///
/// The watch is off by default and needs Full Disk Access, since it reads the
/// Trash. Nothing is removed here: a witnessed move only opens the Uninstaller
/// with the app's leftovers listed and every row unchecked.
@MainActor
package final class TrashAppWatcher {
    package static let shared = TrashAppWatcher()

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var stream: FSEventStreamRef?
    private var renames = UninstallerSupport.TrashRenames()

    private init() {}

    package func syncWithPreferences() {
        let wanted = AppFeature.uninstaller.isAvailable
            && UserDefaults.standard[Preferences.uninstallerWatchesTrash]
            && Permissions.shared.fullDiskAccess
        wanted ? start() : stop()
    }

    private func start() {
        guard stream == nil else { return }
        let roots = ["/Applications", home.appendingPathComponent("Applications").path,
                     UninstallerSupport.trashURL(home: home).path]
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagUseExtendedData)
        // A C callback carries no isolation and captures nothing. The stream
        // is served by the main queue below, so the callback arrives on the
        // main thread and the watcher's own state is this actor's.
        let callback: FSEventStreamCallback = { stream, _, count, paths, flags, ids in
            MainActor.assumeIsolated {
                TrashAppWatcher.shared.handle(stream: stream, count: count, paths: paths,
                                              flags: flags, ids: ids)
            }
        }
        guard let created = FSEventStreamCreate(nil, callback, nil, roots as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                0.15, flags) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        renames = UninstallerSupport.TrashRenames()
    }

    /// One batch of file events, from the stream this watcher still owns.
    private func handle(stream: ConstFSEventStreamRef, count: Int,
                        paths: UnsafeMutableRawPointer,
                        flags: UnsafePointer<FSEventStreamEventFlags>,
                        ids: UnsafePointer<FSEventStreamEventId>) {
        guard stream == self.stream,
              let records = unsafeBitCast(paths, to: NSArray.self) as? [[String: Any]],
              records.count == count else { return }
        let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagEventIdsWrapped)
        // A dropped event leaves no pair to witness, so nothing is remembered.
        guard !(0..<count).contains(where: { flags[$0] & lost != 0 }) else {
            renames = UninstallerSupport.TrashRenames()
            return
        }
        let rename = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed
            | kFSEventStreamEventFlagItemIsDir)
        for index in 0..<count where flags[index] & rename == rename {
            guard let path = records[index]["path"] as? String,
                  let inode = records[index]["fileID"] as? NSNumber else { continue }
            if let move = renames.accept(URL(fileURLWithPath: path, isDirectory: true),
                                         inode: inode.uint64Value, eventID: ids[index], home: home) {
                offer(move)
            }
        }
    }

    private func offer(_ move: UninstallerSupport.TrashMove) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              AppUninstaller.shared.canOfferTrashCleanup(of: move) else { return }
        appShell()?.openUninstaller(for: move.selection.url, trashMove: move)
    }
}
