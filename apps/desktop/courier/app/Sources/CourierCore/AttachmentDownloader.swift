// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CoreServices
import Darwin
import Foundation

/// Copies received attachments from the engine's local media store to the configured Downloads folder
/// (or a path chosen via `NSSavePanel`), stamping `kLSQuarantineTypeOtherDownload` and deduplicating filenames
/// (`spec (1).pdf`, `spec (2).pdf`) without overwriting existing files.
@MainActor
public final class AttachmentDownloader {
    public let preferences: ComposerPreferences
    private let promptSavePanel: (String, URL) -> URL?

    public init(
        preferences: ComposerPreferences,
        promptSavePanel: @escaping (String, URL) -> URL? = AttachmentDownloader.defaultSavePanel
    ) {
        self.preferences = preferences
        self.promptSavePanel = promptSavePanel
    }

    /// Saves `sourcePath` with `suggestedName`, stamping `kLSQuarantineTypeOtherDownload` and deduplicating filenames (`report (1).pdf`).
    @discardableResult
    public func download(
        sourcePath: String,
        suggestedName: String?,
        mimeType: String = ""
    ) throws -> URL? {
        let trimmed = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("/"),
              !lower.hasPrefix("http://"),
              !lower.hasPrefix("https://"),
              !lower.hasPrefix("mxc://")
        else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let sourceURL = URL(fileURLWithPath: trimmed)
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let rawName = (suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? suggestedName!
            : sourceURL.lastPathComponent
        let safeFileName = OpenFileCache.fileName(for: rawName, mimeType: mimeType)

        let configuredPath = preferences.downloadsDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDir = configuredPath.isEmpty ? ComposerPreferences.defaultDownloadsDirectoryPath : configuredPath
        let expandedDir = (rawDir as NSString).expandingTildeInPath
        let defaultDirectoryURL = URL(fileURLWithPath: expandedDir, isDirectory: true)
        try manager.createDirectory(at: defaultDirectoryURL, withIntermediateDirectories: true)

        if preferences.alwaysAskWhereToSaveFiles {
            guard let chosenURL = promptSavePanel(safeFileName, defaultDirectoryURL) else {
                return nil
            }
            let targetDirectory = chosenURL.deletingLastPathComponent()
            try manager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let chosenFileName = OpenFileCache.fileName(for: chosenURL.lastPathComponent, mimeType: mimeType)
            return try Self.copyAtomicallyWithQuarantine(
                from: sourceURL,
                toDirectory: targetDirectory,
                baseFileName: chosenFileName
            )
        }

        return try Self.copyAtomicallyWithQuarantine(
            from: sourceURL,
            toDirectory: defaultDirectoryURL,
            baseFileName: safeFileName
        )
    }

    nonisolated public static func defaultSavePanel(suggestedName: String, defaultDirectoryURL: URL) -> URL? {
        MainActor.assumeIsolated {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedName
            panel.directoryURL = defaultDirectoryURL
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.prompt = String(localized: "Save")
            panel.message = String(localized: "Choose where to save this file")
            guard panel.runModal() == .OK else { return nil }
            return panel.url
        }
    }

    private static func copyAtomicallyWithQuarantine(
        from source: URL,
        toDirectory directory: URL,
        baseFileName: String
    ) throws -> URL {
        let manager = FileManager.default
        let partial = directory.appendingPathComponent(".courier-download-\(UUID().uuidString).partial")
        do {
            try manager.copyItem(at: source, to: partial)
            try OpenFileCache.quarantine(partial)

            var collisionIndex = 0
            while true {
                let candidateName = deduplicatedFileName(baseFileName, index: collisionIndex)
                let destination = directory.appendingPathComponent(candidateName)
                if renamex_np(partial.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
                    return destination
                }
                if errno == EEXIST {
                    collisionIndex += 1
                    continue
                }
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    public static func deduplicatedFileName(_ fileName: String, index: Int) -> String {
        guard index > 0 else { return fileName }
        let nsName = fileName as NSString
        let ext = nsName.pathExtension
        let stem = ext.isEmpty ? fileName : nsName.deletingPathExtension
        if ext.isEmpty {
            return "\(stem) (\(index))"
        }
        return "\(stem) (\(index)).\(ext)"
    }
}
