// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum StorageFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: A failed removal explains itself where it failed
        // A green tick above "some items couldn't be moved to the Trash" told
        // nobody that sandboxed app data needs Full Disk Access, and the note
        // offering the permission only ever appeared before an app was picked.
        suite.expect(UninstallerSupport.doneSymbol(hasLeftovers: false) == "checkmark.circle.fill",
               "a removal that took everything ends on a tick")
        suite.expect(UninstallerSupport.doneSymbol(hasLeftovers: true)
                != UninstallerSupport.doneSymbol(hasLeftovers: false),
               "a removal that left something behind does not end on the same mark")
        // The permission note has to be true when it appears: only sandboxed
        // container data is gated by Full Disk Access, so a failure list made
        // of ownership or identity refusals must not offer it.
        let fdaHome = "/Users/someone"
        suite.expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Containers/com.vendor.editor"]),
               "a failed container is the case Full Disk Access would have changed")
        suite.expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Application Support/Editor",
                           fdaHome + "/Library/Group Containers/group.com.vendor.editor",
                           fdaHome + "/Library/Caches/com.vendor.editor"]),
               "one failed container among others is enough to offer the permission")
        suite.expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Application Scripts/com.vendor.editor"]),
               "application scripts sit behind the same permission as containers")
        suite.expect(!UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: ["/Applications/Editor.app",
                           fdaHome + "/Library/Application Support/Editor",
                           fdaHome + "/Library/Preferences/com.vendor.editor.plist",
                           "/Library/LaunchAgents/com.vendor.editor.plist"]),
               "failures outside containers never offer a permission that would not help")
        suite.expect(!UninstallerSupport.failureNeedsFullDiskAccess(paths: []),
               "no failure, no permission note")
        // Both done states have to route through that decision and name what
        // survived; neither may spell a tick of its own.
        let survivingContainer = AppUninstaller.Leftover(
            url: URL(fileURLWithPath: fdaHome + "/Library/Containers/com.vendor.editor"),
            category: .containers, size: 1, ownerBundleID: "com.vendor.editor", ownerGroupID: nil,
            evidenceBundleID: nil, confidence: .exact, fileIdentity: .init(device: 0, inode: 1))
        let survivingSupport = AppUninstaller.Leftover(
            url: URL(fileURLWithPath: fdaHome + "/Library/Application Support/Editor"),
            category: .support, size: 1, ownerBundleID: "com.vendor.editor", ownerGroupID: nil,
            evidenceBundleID: nil, confidence: .exact, fileIdentity: .init(device: 0, inode: 2))
        for (surface, compact) in [("the Settings uninstaller", false), ("the panel uninstaller", true)] {
            let clean = UninstallDoneContent(failed: [], compact: compact)
            let partial = UninstallDoneContent(failed: [survivingContainer], compact: compact)
            suite.expect(clean.failureNote == nil
                    && partial.failureNote?.items == [survivingContainer]
                    && partial.failureNote?.compact == compact,
                   "\(surface) names what the removal left behind")
            suite.expect(clean.symbol == UninstallerSupport.doneSymbol(hasLeftovers: false)
                    && partial.symbol == UninstallerSupport.doneSymbol(hasLeftovers: true),
                   "\(surface) takes its done symbol from UninstallerSupport")
        }
        let failureStrings = L10n.shared.s
        suite.expect(UninstallFailureNote.permissionReason(for: [survivingSupport, survivingContainer],
                                                           hasFullDiskAccess: false, strings: failureStrings)
                == failureStrings.uninstallerFailedNeedsFDA,
               "the failure note explains the permission the removal needed")
        suite.expect(UninstallFailureNote.permissionReason(for: [survivingContainer],
                                                           hasFullDiskAccess: true, strings: failureStrings) == nil
                && UninstallFailureNote.permissionReason(for: [survivingSupport],
                                                         hasFullDiskAccess: false, strings: failureStrings) == nil,
               "the failure note offers the permission only when it is missing and would have helped")

        // MARK: Private file store

        let privateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        let privateLeaf = privateRoot.appendingPathComponent("Sub", isDirectory: true)
        suite.expect(PrivateFileStore.directoriesToTighten(from: privateLeaf, container: privateRoot)
                .map(\.lastPathComponent) == ["Sub", privateRoot.lastPathComponent],
               "tightening walks a container path up to the container itself")
        suite.expect(PrivateFileStore.directoriesToTighten(from: privateRoot, container: privateRoot)
                .map(\.lastPathComponent) == [privateRoot.lastPathComponent],
               "the container is tightened without climbing past it")
        suite.expect(PrivateFileStore.directoriesToTighten(
                from: privateLeaf,
                container: FileManager.default.temporaryDirectory
                    .appendingPathComponent(privateRoot.lastPathComponent + "-other",
                                            isDirectory: true)).count == 1,
               "a path outside the container tightens only itself, never a sibling's parents")

        // A container an earlier version created world readable, and a file
        // written into it, both end up owner-only.
        try? FileManager.default.createDirectory(at: privateRoot,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        let privateFile = privateLeaf.appendingPathComponent("records.json")
        let privateCreated = PrivateFileStore.createDirectory(at: privateLeaf,
                                                              container: privateRoot)
        let privateWritten = PrivateFileStore.write(Data([0x7B, 0x7D]), to: privateFile)
        func privateMode(_ url: URL) -> Int? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
                .flatMap { ($0 as? NSNumber)?.intValue }
        }
        suite.expect(privateCreated && privateMode(privateLeaf) == 0o700,
               "a created store directory is owner-only")
        suite.expect(privateWritten
                && privateMode(privateFile) == 0o600
                && (try? Data(contentsOf: privateFile)) == Data([0x7B, 0x7D]),
               "a stored file lands complete and owner-only")
        suite.expect(privateMode(privateRoot) == 0o700,
               "a container an earlier version left world readable is tightened on the next write")
        try? FileManager.default.removeItem(at: privateRoot)

    }
}
