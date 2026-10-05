// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

package struct NotchDownloadItem: Identifiable, Equatable {
    package let id: String
    package let url: URL
    package let name: String
    package let receivedBytes: Int64?
    package let fraction: Double?
    package let completed: Bool
    package var active = true
    package var date: Date = .distantPast

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, url: URL, name: String, receivedBytes: Int64?, fraction: Double?, completed: Bool, active: Bool = true, date: Date = .distantPast) {
        self.id = id
        self.url = url
        self.name = name
        self.receivedBytes = receivedBytes
        self.fraction = fraction
        self.completed = completed
        self.active = active
        self.date = date
    }
}

package struct NotchPartialDownload: Equatable {
    package let url: URL
    package let expectedURL: URL
    package let bytes: Int64
    package let resourceID: String?
    package let modified: Date
    package var contentURL: URL? = nil

    // Spelled out because a memberwise initializer never leaves its module.
    package init(url: URL, expectedURL: URL, bytes: Int64, resourceID: String?, modified: Date, contentURL: URL? = nil) {
        self.url = url
        self.expectedURL = expectedURL
        self.bytes = bytes
        self.resourceID = resourceID
        self.modified = modified
        self.contentURL = contentURL
    }
}

/// Capture native progress values once before validating paths on the file queue.
package struct NotchDownloadProgressSnapshot {
    package let fileURL: URL?
    package let fileOperationKind: Progress.FileOperationKind?
    package let isFile: Bool
    package let isFinished: Bool
    package let isPaused: Bool
    package let isCancelled: Bool
    package let completedUnitCount: Int64
    package let totalUnitCount: Int64
    package let fractionCompleted: Double
    package let isIndeterminate: Bool

    package init(_ progress: Progress) {
        fileURL = progress.fileURL
        fileOperationKind = progress.fileOperationKind
        isFile = progress.kind == .file
        isFinished = progress.isFinished
        isPaused = progress.isPaused
        isCancelled = progress.isCancelled
        completedUnitCount = progress.completedUnitCount
        totalUnitCount = progress.totalUnitCount
        fractionCompleted = progress.fractionCompleted
        isIndeterminate = progress.isIndeterminate
    }
}

/// A publisher can change its URL while a transfer is running. Keep the first
/// observed state of each destination so an unrelated existing file cannot
/// become a successful download just because the reported count reaches 100%.
package struct NotchDownloadPublication {
    private var url: URL
    private var initialFile: NotchDownloadSupport.FileSnapshot?
    private var lastFileIdentity: String?
    private let date = Date()

    package init?(_ progress: NotchDownloadProgressSnapshot, folder: URL) {
        guard !progress.isFinished, let url = NotchDownloadSupport.publishedURL(progress, folder: folder) else { return nil }
        self.url = url
        initialFile = NotchDownloadSupport.fileSnapshot(at: url)
        lastFileIdentity = initialFile?.identity
    }

    package mutating func item(_ progress: NotchDownloadProgressSnapshot, folder: URL) -> NotchDownloadItem? {
        guard let current = NotchDownloadSupport.publishedURL(progress, folder: folder) else { return nil }
        let file = NotchDownloadSupport.fileSnapshot(at: current)
        if current != url {
            // A moved file is new evidence at its final destination, even if
            // the URL and finished count arrive together. Existing aliases or
            // unrelated files must still establish their own baseline.
            let renamed = file != nil && file?.identity == lastFileIdentity
                && !FileManager.default.fileExists(atPath: url.path)
            initialFile = renamed ? nil : file
            url = current
            lastFileIdentity = file?.identity
        } else if let file {
            lastFileIdentity = file.identity
        }
        let completed = progress.isFinished && file != nil && file != initialFile
            && NotchDownloadSupport.expectedURL(for: current) == nil
        return NotchDownloadItem(id: current.path, url: current, name: current.lastPathComponent,
            receivedBytes: completed ? file?.bytes : progress.isFile ? max(0, progress.completedUnitCount) : nil,
            fraction: completed ? 1 : progress.isFinished ? nil : NotchDownloadSupport.fraction(
                completed: progress.completedUnitCount, total: progress.totalUnitCount,
                reportedFraction: progress.fractionCompleted, indeterminate: progress.isIndeterminate),
            completed: completed, active: !progress.isFinished && !progress.isPaused, date: date)
    }
}

package enum NotchDownloadSupport {
    package struct FolderSnapshot {
        package let partials: [URL: NotchPartialDownload]
        package let files: [NotchDownloadItem]

        // Spelled out because a memberwise initializer never leaves its module.
        package init(partials: [URL: NotchPartialDownload], files: [NotchDownloadItem]) {
            self.partials = partials
            self.files = files
        }
    }

    package static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
    ]

    package static func scanFolder(_ folder: URL) -> FolderSnapshot? {
        var readFailed = false
        guard let entries = FileManager.default.enumerator(at: folder,
            includingPropertiesForKeys: Array(keys), options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in readFailed = true; return false }) else { return nil }
        var result: [URL: NotchPartialDownload] = [:]
        var files: [NotchDownloadItem] = []
        for case let entry as URL in entries {
            let url = entry.standardizedFileURL
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true || values.isDirectory == true else { continue }
            guard let expected = expectedURL(for: url) else {
                files.append(NotchDownloadItem(id: url.path, url: url, name: url.lastPathComponent,
                    receivedBytes: values.fileSize.map(Int64.init), fraction: 1, completed: true,
                    active: false, date: values.addedToDirectoryDate ?? values.creationDate
                        ?? values.contentModificationDate ?? .distantPast))
                continue
            }
            guard result.count < maximumObservedFiles else { continue }
            var payloadValues = values
            var contentURL: URL?
            if values.isDirectory == true {
                // A partial package can hold the real file. Inspect only its
                // expected payload, never traverse other folders or resume data.
                let payload = url.appendingPathComponent(expected.lastPathComponent)
                if let found = try? payload.resourceValues(forKeys: keys),
                   found.isRegularFile == true, found.isSymbolicLink != true {
                    payloadValues = found
                    contentURL = payload
                }
            }
            result[url] = NotchPartialDownload(url: url, expectedURL: expected,
                bytes: payloadValues.isRegularFile == true ? Int64(payloadValues.fileSize ?? 0) : 0,
                resourceID: NotchDownloadSupport.fileIdentity(at: contentURL ?? url),
                modified: payloadValues.contentModificationDate ?? .distantPast,
                contentURL: contentURL)
        }
        // The main queue merges, sorts and compares this list on every
        // progress tick, so a crowded folder hands it only its newest entries.
        if files.count > maximumListedFiles {
            files.sort { $0.date != $1.date ? $0.date > $1.date : $0.url.path < $1.url.path }
            files.removeSubrange(maximumListedFiles...)
        }
        return readFailed ? nil : FolderSnapshot(partials: result, files: files)
    }

    /// Published progress owns its destination until it finishes. Folder files
    /// remain visible after the short completion notice expires.
    package static func mergedItems(active: [NotchDownloadItem], files: [NotchDownloadItem],
                            finished: [NotchDownloadItem]) -> [NotchDownloadItem] {
        var seen = Set<URL>()
        let represented = Set(active.flatMap { [$0.url.standardizedFileURL,
            (expectedURL(for: $0.url) ?? $0.url).standardizedFileURL] })
        let candidates = active + files.filter { !represented.contains($0.url.standardizedFileURL) }
            + finished.filter { !represented.contains($0.url.standardizedFileURL) }
        return candidates.filter { seen.insert($0.url.standardizedFileURL).inserted }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.url.path < $1.url.path
        }
    }

    package static let maximumObservedFiles = 32
    /// Folder entries the page lists, newest first.
    package static let maximumListedFiles = 200
    package static let percentSize: CGFloat = 10
    /// The wing a download keeps beside another activity, wide enough for
    /// its percentage.
    package static let companionWing: CGFloat = 80
    package static let compactNameWingThreshold: CGFloat = 94
    private static let compactNameMinimumWing: CGFloat = 64
    private static let compactNameMaximumWing: CGFloat = 160
    /// Progress rounds up to a full hundred near the end, and four of the
    /// languages part the number from its sign, so the narrowest wing cannot
    /// hold the widest reading at full size. It shrinks rather than wrap or
    /// lose a digit.
    package static let percentMinimumScale: CGFloat = 0.75

    package static func percentFormat(_ language: AppLanguage) -> FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0)).locale(Locale(identifier: language.rawValue))
    }

    /// Digits carry no descenders, so their ink is about the cap height.
    package static func percentInset(in geometry: NotchGeometry) -> CGFloat {
        geometry.compactReadingInset(textSize: percentSize)
    }

    /// Restore the file name only when menus leave a readable wing. Otherwise
    /// the arrow and percent keep their short strip beside the camera.
    package static func compactWing(for name: String?, in geometry: NotchGeometry) -> CGFloat {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let room = geometry.compactSideRoom, room.isFinite,
              room >= compactNameWingThreshold else { return 56 }
        let provisional = geometry.compactDownloadGeometry(wing: compactNameWingThreshold)
        let icon = min(17, provisional.compactActivityContentHeight - NotchLayout.compactEdgeGap * 2)
        let inset = provisional.compactActivityEdgeInset(boxHeight: icon, radius: icon / 2)
        return min(compactNameMaximumWing,
                   max(compactNameMinimumWing, (inset + compactNameContentWidth(name, icon: icon) + 4).rounded(.up)))
    }

    /// The island asks for its geometry on every layout and progress tick, so
    /// the one name on show is measured once rather than each time. The island
    /// lays out on the main thread, the only one that touches this.
    nonisolated(unsafe) private static var measuredCompactName: (name: String, icon: CGFloat, width: CGFloat)?

    private static func compactNameContentWidth(_ name: String, icon: CGFloat) -> CGFloat {
        if let measured = measuredCompactName, measured.name == name, measured.icon == icon {
            return measured.width
        }
        // The symbol draws wider than its point size; measuring the size alone
        // left every name a few points short and cut it in the middle.
        let symbol = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: icon, weight: .regular))?
            .size.width ?? icon + 3
        let title = (name as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium)
        ]).width.rounded(.up)
        let width = max(icon, symbol) + 6 + title
        measuredCompactName = (name, icon, width)
        return width
    }

    package static func showsCompactName(in geometry: NotchGeometry) -> Bool {
        geometry.compactActivityWingWidth >= compactNameMinimumWing
    }

    package struct FileSnapshot: Equatable {
        package let identity: String
        package let bytes: Int64
        package let modifiedSeconds: Int
        package let modifiedNanoseconds: Int

        // Spelled out because a memberwise initializer never leaves its module.
        package init(identity: String, bytes: Int64, modifiedSeconds: Int, modifiedNanoseconds: Int) {
            self.identity = identity
            self.bytes = bytes
            self.modifiedSeconds = modifiedSeconds
            self.modifiedNanoseconds = modifiedNanoseconds
        }
    }

    package static func publishedURL(_ progress: NotchDownloadProgressSnapshot, folder: URL) -> URL? {
        guard !progress.isCancelled, let url = progress.fileURL,
              progress.fileOperationKind == .downloading || progress.fileOperationKind == .receiving,
              isDirectChild(url, of: folder),
              isDirectChild(url.resolvingSymlinksInPath(), of: folder.resolvingSymlinksInPath()) else { return nil }
        return url.standardizedFileURL
    }

    package static func fraction(completed: Int64, total: Int64, reportedFraction: Double,
                         indeterminate: Bool) -> Double? {
        guard !indeterminate, total > 0, completed >= 0,
              reportedFraction.isFinite else { return nil }
        return min(1, max(0, reportedFraction))
    }

    package static func expectedURL(for partialURL: URL) -> URL? {
        guard partialURL.isFileURL,
              ["crdownload", "download", "part"].contains(partialURL.pathExtension.lowercased()) else { return nil }
        let output = partialURL.deletingPathExtension()
        return output.lastPathComponent.isEmpty ? nil : output
    }

    package static func isDirectChild(_ url: URL, of folder: URL) -> Bool {
        url.isFileURL && folder.isFileURL
            && url.standardizedFileURL.deletingLastPathComponent() == folder.standardizedFileURL
    }

    package static func fileIdentity(at url: URL) -> String? {
        fileSnapshot(at: url)?.identity
    }

    package static func fileSnapshot(at url: URL) -> FileSnapshot? {
        guard url.isFileURL else { return nil }
        var info = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            path.map { lstat($0, &info) == 0 } ?? false
        }), (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileSnapshot(identity: "\(info.st_dev):\(info.st_ino)", bytes: info.st_size,
                            modifiedSeconds: info.st_mtimespec.tv_sec,
                            modifiedNanoseconds: info.st_mtimespec.tv_nsec)
    }

    package static func didFinish(_ partial: NotchPartialDownload, at finalURL: URL,
                          resourceID: String?) -> Bool {
        guard partial.expectedURL.standardizedFileURL == finalURL.standardizedFileURL,
              let previousID = partial.resourceID, let resourceID else { return false }
        return previousID == resourceID
    }
}
