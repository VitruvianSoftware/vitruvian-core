// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreServices
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Gets a received file ready to open in the app that is meant for it.
///
/// The engine keeps a received file under its content's hash, with no name and no extension (`<dir>/ab/<sha256>`),
/// so the system cannot tell which app opens it. This makes a copy under the file's real name in a folder of
/// Courier's cache (a clone on APFS, so it costs no space), marks the copy as downloaded from elsewhere so
/// Gatekeeper still checks the kinds of file that can run, and gives back that copy. The cache is emptied when
/// Courier starts.
public struct OpenFileCache: Sendable {
    /// The longest a file's name is made, in characters.
    public static let longestName = 100

    public static let shared = OpenFileCache(
        root: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.vitruviansoftware.courier/open", isDirectory: true))

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: - The name

    /// The name the copy is given: the file's own name, made safe to put in a folder. An empty name becomes `file`,
    /// and a name with no extension gets one from the mime type when the system knows one for it.
    public static func fileName(for name: String, mimeType: String) -> String {
        var safe = String(name.unicodeScalars.map { scalar in
            scalar == "/" || scalar == ":" || scalar.properties.generalCategory == .control ? "_" : Character(scalar)
        })
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        while safe.hasPrefix(".") { safe.removeFirst() }
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        if safe.isEmpty { safe = "file" }

        if (safe as NSString).pathExtension.isEmpty, !mimeType.isEmpty,
           let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension {
            safe += "." + ext
        }
        return capped(safe)
    }

    /// Cut to `longestName` characters, keeping a sensible extension.
    private static func capped(_ name: String) -> String {
        guard name.count > longestName else { return name }
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, ext.count <= 16 {
            let base = String((name as NSString).deletingPathExtension.prefix(longestName - ext.count - 1))
            return base + "." + ext
        }
        return String(name.prefix(longestName))
    }

    // MARK: - The copy

    /// A copy of `source` under its real name, ready to open. The same file gives the same copy.
    public func prepare(source: URL, fileName: String, mimeType: String) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let folder = root.appendingPathComponent(Self.folderName(for: source), isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(Self.fileName(for: fileName, mimeType: mimeType))
        if manager.fileExists(atPath: copy.path) { return copy }
        try manager.copyItem(at: source, to: copy) // a clone on APFS
        do {
            try Self.quarantine(copy)
        } catch {
            // Never leave a copy that Gatekeeper has not been told about.
            try? manager.removeItem(at: copy)
            throw error
        }
        return copy
    }

    /// Marks the file as one that came from elsewhere, as a browser does a download.
    static func quarantine(_ file: URL) throws {
        var values = URLResourceValues()
        values.quarantineProperties = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload as String,
            kLSQuarantineAgentNameKey as String: "Courier",
        ]
        var target = file
        try target.setResourceValues(values)
    }

    /// Removes every copy.
    public func clear() {
        try? FileManager.default.removeItem(at: root)
    }

    private static func folderName(for source: URL) -> String {
        SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
    }
}
