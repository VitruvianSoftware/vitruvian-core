// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreServices
import CryptoKit
import Darwin
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
    /// The longest a file's name is made, in bytes of UTF-8, extension included. (A folder entry can be 255.)
    public static let longestNameBytes = 200

    public static let shared = OpenFileCache(
        root: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.vitruviansoftware.courier/open", isDirectory: true))

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    // MARK: - The name

    /// The name the copy is given: the file's own name, made safe to put in a folder and to be shown as it is.
    /// Slashes, colons and control characters become `_`. Invisible format characters are removed (the
    /// right-to-left override and the other direction marks, zero-width characters, line and paragraph
    /// separators): left in, they let `evil<U+202E>fdp.command` show as a harmless name while it runs as a
    /// `.command`. An empty name becomes `file`, and a name with no extension gets one from the mime type when the
    /// system knows one for it.
    public static func fileName(for name: String, mimeType: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .format || category == .lineSeparator || category == .paragraphSeparator { continue }
            if scalar == "/" || scalar == ":" || category == .control {
                kept.append("_")
            } else {
                kept.append(scalar)
            }
        }
        var safe = String(kept).trimmingCharacters(in: .whitespacesAndNewlines)
        while safe.hasPrefix(".") { safe.removeFirst() }
        safe = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        if safe.isEmpty { safe = "file" }

        if (safe as NSString).pathExtension.isEmpty, !mimeType.isEmpty,
           let ext = UTType(mimeType: mimeType)?.preferredFilenameExtension {
            safe += "." + ext
        }
        return capped(safe)
    }

    /// Cut to `longestNameBytes` bytes (never through a character), keeping a sensible extension.
    private static func capped(_ name: String) -> String {
        guard name.utf8.count > longestNameBytes else { return name }
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty, ext.utf8.count <= 32 {
            let base = prefix(of: (name as NSString).deletingPathExtension, bytes: longestNameBytes - ext.utf8.count - 1)
            return base + "." + ext
        }
        return prefix(of: name, bytes: longestNameBytes)
    }

    private static func prefix(of text: String, bytes limit: Int) -> String {
        var result = String.UnicodeScalarView()
        var used = 0
        for scalar in text.unicodeScalars {
            let size = String(scalar).utf8.count
            if used + size > limit { break }
            result.append(scalar)
            used += size
        }
        return String(result)
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
        // A file in its place is always a finished, quarantined one: it is only ever put there by the rename below.
        if manager.fileExists(atPath: copy.path) { return copy }

        // Copied under a temporary name, marked, and only then renamed into place, so another open that comes
        // while this one is copying never finds a file that has not been marked.
        let partial = folder.appendingPathComponent(".\(UUID().uuidString).partial")
        do {
            try manager.copyItem(at: source, to: partial) // a clone on APFS
            try Self.quarantine(partial)
            if renamex_np(partial.path, copy.path, UInt32(RENAME_EXCL)) != 0 {
                if errno == EEXIST {
                    // Another open finished first, and its copy is as good.
                    try? manager.removeItem(at: partial)
                    return copy
                }
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            // Never leave a copy that Gatekeeper has not been told about.
            try? manager.removeItem(at: partial)
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
