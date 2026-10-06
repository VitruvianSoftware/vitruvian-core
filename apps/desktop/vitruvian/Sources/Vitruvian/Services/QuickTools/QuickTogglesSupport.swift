// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

/// Pure rules behind the quick toggles: the AppleScript sources, the Finder
/// preference parsing and the eject filter, kept free of AppKit so the unit
/// harness pins them down.
package enum QuickTogglesSupport {
    package static let finderDomain = "com.apple.finder"
    package static let showAllFilesKey = "AppleShowAllFiles"
    package static let createDesktopKey = "CreateDesktop"

    package static let emptyTrashSource = "tell application \"Finder\" to empty trash"
    package static let quitFinderSource = "tell application \"Finder\" to quit"

    /// Apple Event consent errors: not permitted, or the prompt was dismissed.
    package static let permissionErrorNumbers: Set<Int> = [-1743, -1744]

    package static func isPermissionError(_ errorNumber: Int?) -> Bool {
        guard let errorNumber else { return false }
        return permissionErrorNumbers.contains(errorNumber)
    }

    /// Finder preferences reach us as real booleans, numbers or the legacy
    /// "YES"/"TRUE"/"1" strings; anything unreadable means the given default.
    package static func finderFlag(_ value: Any?, default defaultValue: Bool) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return defaultValue
            }
        default:
            return defaultValue
        }
    }

    /// Which mounted volumes "Eject all disks" offers. The system flags
    /// describe two different things: the bus tells whether the drive is
    /// external, while removable and ejectable describe media that leaves the
    /// drive, like a card or a disc. An external drive with fixed media, which
    /// is what most desk drives are, answers no to both, so asking for
    /// removable media hid them all. The bus decides, and media that comes out
    /// of an internal reader still counts. Network shares, the volume the Mac
    /// booted from, internal fixed drives and drives in the user's exclusion list
    /// never qualify.
    package static func shouldOfferEject(isInternal: Bool,
                                 isRemovable: Bool,
                                 isEjectable: Bool,
                                 isLocal: Bool,
                                 isRootFileSystem: Bool,
                                 volumeName: String? = nil,
                                 volumeUUID: String? = nil,
                                 mountPath: String? = nil,
                                 excludedVolumes: Set<String> = []) -> Bool {
        guard isLocal && !isRootFileSystem && (!isInternal || isRemovable || isEjectable) else {
            return false
        }
        guard !excludedVolumes.isEmpty else { return true }
        return !isExcluded(volumeName: volumeName,
                           volumeUUID: volumeUUID,
                           mountPath: mountPath,
                           excludedVolumes: excludedVolumes)
    }

    /// Whether a volume matches any entry in the user's exclusion list by
    /// name (case-insensitive), volume UUID, full mount path or mount directory name.
    /// None of the four forms is optional to pass: an entry the user typed is
    /// honoured or ignored depending on which identifiers the caller happened
    /// to hand over, so a caller that has none says so with an explicit nil.
    package static func isExcluded(volumeName: String?,
                           volumeUUID: String?,
                           mountPath: String?,
                           excludedVolumes: Set<String>) -> Bool {
        guard !excludedVolumes.isEmpty else { return false }
        if let name = volumeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if excludedVolumes.contains(name) || excludedVolumes.contains(name.lowercased()) {
                return true
            }
        }
        if let uuid = volumeUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
            if excludedVolumes.contains(uuid) || excludedVolumes.contains(uuid.lowercased()) {
                return true
            }
        }
        if let mountPath = mountPath?.trimmingCharacters(in: .whitespacesAndNewlines), !mountPath.isEmpty {
            if excludedVolumes.contains(mountPath) || excludedVolumes.contains(mountPath.lowercased()) {
                return true
            }
            let lastComponent = (mountPath as NSString).lastPathComponent
            if !lastComponent.isEmpty && (excludedVolumes.contains(lastComponent) || excludedVolumes.contains(lastComponent.lowercased())) {
                return true
            }
        }
        return false
    }

    /// What a mounted volume is read for. The UUID is among them: an
    /// exclusion entered as a volume UUID matches only a volume read with it.
    package static var volumeKeys: Set<URLResourceKey> {
        [
            .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeIsLocalKey,
            .volumeIsRootFileSystemKey,
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeUUIDStringKey,
        ]
    }

    /// A mounted volume as the exclusions picker judges it.
    package struct Volume: Equatable {
        package var name: String
        package var uuid: String?
        package var mountPath: String
        package var isInternal: Bool
        package var isRemovable: Bool
        package var isEjectable: Bool
        package var isLocal: Bool
        package var isRootFileSystem: Bool

        // Spelled out because a memberwise initializer never leaves its module.
        package init(name: String, uuid: String?, mountPath: String, isInternal: Bool,
                     isRemovable: Bool, isEjectable: Bool, isLocal: Bool, isRootFileSystem: Bool) {
            self.name = name
            self.uuid = uuid
            self.mountPath = mountPath
            self.isInternal = isInternal
            self.isRemovable = isRemovable
            self.isEjectable = isEjectable
            self.isLocal = isLocal
            self.isRootFileSystem = isRootFileSystem
        }

        /// The volume mounted at `url`, read with `volumeKeys`; nil when it
        /// cannot be read.
        package init?(mountedAt url: URL) {
            guard let values = try? url.resourceValues(forKeys: QuickTogglesSupport.volumeKeys) else {
                return nil
            }
            self.init(name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
                      uuid: values.volumeUUIDString,
                      mountPath: url.path,
                      isInternal: values.volumeIsInternal ?? false,
                      isRemovable: values.volumeIsRemovable ?? false,
                      isEjectable: values.volumeIsEjectable ?? false,
                      isLocal: values.volumeIsLocal ?? false,
                      isRootFileSystem: values.volumeIsRootFileSystem ?? (url.path == "/"))
        }
    }

    /// The drives the exclusions picker offers, sorted by name: those an
    /// eject would take, minus any `excluded` already names. That is the same
    /// test the eject paths use, so an entry the user typed as a volume UUID
    /// or a mount path keeps its drive out of the picker just as its name does.
    package static func exclusionCandidates(_ volumes: [Volume], excluded: [String]) -> [String] {
        let currentExcluded = Set(excluded.map { $0.lowercased() })
        var results: [String] = []
        for volume in volumes {
            let isOfferable = shouldOfferEject(
                isInternal: volume.isInternal,
                isRemovable: volume.isRemovable,
                isEjectable: volume.isEjectable,
                isLocal: volume.isLocal,
                isRootFileSystem: volume.isRootFileSystem
            )
            guard isOfferable else { continue }
            let trimmed = volume.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let alreadyExcluded = isExcluded(
                volumeName: trimmed,
                volumeUUID: volume.uuid,
                mountPath: volume.mountPath,
                excludedVolumes: currentExcluded)
            if !trimmed.isEmpty, !alreadyExcluded, !results.contains(trimmed) {
                results.append(trimmed)
            }
        }
        return results.sorted()
    }
}
