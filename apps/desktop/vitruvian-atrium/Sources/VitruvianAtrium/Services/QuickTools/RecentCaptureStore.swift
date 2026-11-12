// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package struct RecentCaptureEntry: Codable, Equatable, Identifiable {
    package enum Kind: String, Codable {
        case screenshot
        case recording
    }

    package let id: UUID
    package let kind: Kind
    package let createdAt: Date
    package let screenshotName: String?
    package let recordingPath: String?
    package let thumbnailName: String?
    package let scale: Double?
    package let anchorX: Double?
    package let anchorY: Double?
    package let anchorWidth: Double?
    package let anchorHeight: Double?

    package var recordingURL: URL? {
        guard let recordingPath else { return nil }
        return URL(fileURLWithPath: recordingPath)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: UUID, kind: Kind, createdAt: Date, screenshotName: String?, recordingPath: String?, thumbnailName: String?, scale: Double?, anchorX: Double?, anchorY: Double?, anchorWidth: Double?, anchorHeight: Double?) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.screenshotName = screenshotName
        self.recordingPath = recordingPath
        self.thumbnailName = thumbnailName
        self.scale = scale
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.anchorWidth = anchorWidth
        self.anchorHeight = anchorHeight
    }
}

/// Queue-confined history storage. Only a readable index permits writes, and
/// only a committed index permits cleanup of the files it no longer references.
package final class RecentCaptureStore {
    package let directoryURL: URL?
    package var entries: [RecentCaptureEntry] = []
    private var loaded = false
    private var persistedEntries: [RecentCaptureEntry]?
    private let manager = FileManager.default

    package init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }

    package func loadIfNeeded() -> Bool {
        if loaded { return true }
        guard let directoryURL else { return false }
        let indexURL = directoryURL.appendingPathComponent("history.json")
        do {
            try prepareRoot(directoryURL)
            let decoded: [RecentCaptureEntry]
            do {
                let values = try indexURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                decoded = try JSONDecoder().decode([RecentCaptureEntry].self,
                                                    from: Data(contentsOf: indexURL))
                persistedEntries = decoded
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // A missing index with existing captures is also an unreadable
                // history, not permission to erase those captures on the next save.
                let files = try manager.contentsOfDirectory(atPath: directoryURL.path)
                guard !files.contains(where: ScreenshotSupport.isRecentCaptureCacheFileName) else {
                    return false
                }
                decoded = []
            }
            entries = decoded.sorted { $0.createdAt > $1.createdAt }
            loaded = true
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    package func persist() -> Bool {
        guard loaded, let directoryURL else { return false }
        if entries != persistedEntries {
            do {
                try prepareRoot(directoryURL)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                try Self.write(encoder.encode(entries),
                               to: directoryURL.appendingPathComponent("history.json"))
                persistedEntries = entries
            } catch {
                return false
            }
        }
        removeOrphanedCacheFiles(in: directoryURL)
        return true
    }

    private func prepareRoot(_ root: URL) throws {
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    package static func write(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path),
           (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try data.write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func removeOrphanedCacheFiles(in root: URL) {
        let referenced = Set(entries.flatMap { entry in
            [entry.screenshotName, entry.thumbnailName].compactMap { $0 }
        })
        guard let files = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { return }
        for file in files where ScreenshotSupport.isRecentCaptureCacheFileName(
            file.lastPathComponent) && !referenced.contains(file.lastPathComponent) {
            if Self.isRegularFile(file) { try? manager.removeItem(at: file) }
        }
    }

    package static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}
