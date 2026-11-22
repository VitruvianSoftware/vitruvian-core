// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// Locates the Node runtime and Claude helper bundle shipped inside the app or
/// tool folder.
///
/// Never looks on `PATH`, in Homebrew, nvm, or the user's home directory:
/// returns `nil` when either bundled file is missing or invalid.
public struct BundledNode: Equatable, Sendable {

    /// File name of the bundled Node executable.
    public static let nodeExecutableName = "node"

    /// Relative path of the bundled helper script inside `Resources`, `bin/`, or
    /// a SwiftPM resource bundle.
    public static let helperRelativePath = "claude-helper/claude-helper.mjs"

    /// Absolute file URL to the bundled `node` Mach-O executable.
    public let nodeURL: URL

    /// Absolute file URL to the bundled `claude-helper.mjs` script.
    public let helperURL: URL

    public init(nodeURL: URL, helperURL: URL) {
        self.nodeURL = nodeURL
        self.helperURL = helperURL
    }

    /// Finds both the bundled `node` binary and `claude-helper.mjs` for `bundle`.
    ///
    /// Search order:
    /// 1. App bundle: `Contents/Helpers/node` and `Contents/Resources/claude-helper/claude-helper.mjs`.
    /// 2. Tool / executable folder: `<execDir>/node` and `<execDir>/claude-helper/claude-helper.mjs`.
    /// 3. SwiftPM resource bundle (`VitruvianCode_VitruvianCodeCore.bundle` / `VitruvianCode_VitruvianCodeUI.bundle`).
    public static func locate(in bundle: Bundle = .main, fileManager: FileManager = .default) -> BundledNode? {
        locate(
            bundleURL: bundle.bundleURL,
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            fileManager: fileManager
        )
    }

    /// Overload with explicit bundle URLs for unit tests and custom layouts.
    public static func locate(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?,
        fileManager: FileManager = .default
    ) -> BundledNode? {
        guard let nodeURL = nodeURL(
            bundleURL: bundleURL,
            resourceURL: resourceURL,
            executableURL: executableURL,
            fileManager: fileManager
        ),
              let helperURL = helperURL(
                  bundleURL: bundleURL,
                  resourceURL: resourceURL,
                  executableURL: executableURL,
                  fileManager: fileManager
              ) else {
            return nil
        }
        return BundledNode(nodeURL: nodeURL, helperURL: helperURL)
    }

    /// Candidate file URLs for the bundled `node` binary, in priority order.
    public static func nodeCandidates(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?
    ) -> [URL] {
        var candidates: [URL] = []

        // 1. App bundle Contents/Helpers/node (Mach-O code never lives in Resources).
        if let bundleURL {
            candidates.append(bundleURL.appendingPathComponent("Contents/Helpers/\(nodeExecutableName)", isDirectory: false))
        }
        if let executableURL {
            let execDir = executableURL.deletingLastPathComponent()
            candidates.append(execDir.appendingPathComponent("../Helpers/\(nodeExecutableName)", isDirectory: false))
            // 2. Folder beside executable (tool `bin/` layout).
            candidates.append(execDir.appendingPathComponent(nodeExecutableName, isDirectory: false))
        }
        // Unpackaged directory `Bundle(url: binDir)` has resourceURL == bundleURL
        // and no executableURL; allow that folder as a sibling layout while never
        // accepting `Contents/Resources/node` inside a `.app`.
        if let resourceURL,
           resourceURL.pathExtension != "app",
           resourceURL.lastPathComponent != "Resources" || resourceURL.deletingLastPathComponent().lastPathComponent != "Contents" {
            candidates.append(resourceURL.appendingPathComponent(nodeExecutableName, isDirectory: false))
        }

        // 3. SwiftPM resource bundle directories.
        for dir in BundleResources.swiftPMResourceDirectories(resourceURL: resourceURL, executableURL: executableURL) {
            candidates.append(dir.appendingPathComponent(nodeExecutableName, isDirectory: false))
        }

        return BundleResources.deduplicated(candidates)
    }

    /// Candidate file URLs for `claude-helper/claude-helper.mjs`, in priority order.
    public static func helperCandidates(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?
    ) -> [URL] {
        var candidates: [URL] = []

        // 1. App bundle Contents/Resources/claude-helper/claude-helper.mjs.
        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent(helperRelativePath, isDirectory: false))
        } else if let bundleURL {
            candidates.append(bundleURL.appendingPathComponent("Contents/Resources/\(helperRelativePath)", isDirectory: false))
        }

        // 2. Folder beside executable (tool `bin/` layout).
        if let executableURL {
            let execDir = executableURL.deletingLastPathComponent()
            candidates.append(execDir.appendingPathComponent(helperRelativePath, isDirectory: false))
        }

        // 3. SwiftPM resource bundle directories.
        for dir in BundleResources.swiftPMResourceDirectories(resourceURL: resourceURL, executableURL: executableURL) {
            candidates.append(dir.appendingPathComponent(helperRelativePath, isDirectory: false))
        }

        return BundleResources.deduplicated(candidates)
    }

    /// Returns the first valid bundled `node` executable URL for `bundle`, or `nil`.
    public static func nodeURL(in bundle: Bundle = .main, fileManager: FileManager = .default) -> URL? {
        nodeURL(
            bundleURL: bundle.bundleURL,
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            fileManager: fileManager
        )
    }

    /// Returns the first valid bundled `node` executable URL, or `nil`.
    public static func nodeURL(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        nodeCandidates(bundleURL: bundleURL, resourceURL: resourceURL, executableURL: executableURL)
            .first { isUsableExecutable($0, fileManager: fileManager) }?
            .standardizedFileURL
    }

    /// Returns the first readable non-empty bundled `claude-helper.mjs` URL for `bundle`, or `nil`.
    public static func helperURL(in bundle: Bundle = .main, fileManager: FileManager = .default) -> URL? {
        helperURL(
            bundleURL: bundle.bundleURL,
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            fileManager: fileManager
        )
    }

    /// Returns the first readable non-empty bundled `claude-helper.mjs` URL, or `nil`.
    public static func helperURL(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        helperCandidates(bundleURL: bundleURL, resourceURL: resourceURL, executableURL: executableURL)
            .first { isReadableNonEmptyFile($0, fileManager: fileManager) }?
            .standardizedFileURL
    }

    private static func isUsableExecutable(_ url: URL, fileManager: FileManager) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return fileManager.isExecutableFile(atPath: resolved.path)
    }

    private static func isReadableNonEmptyFile(_ url: URL, fileManager: FileManager) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: resolved.path),
              let attrs = try? fileManager.attributesOfItem(atPath: resolved.path),
              let size = attrs[.size] as? NSNumber else {
            return false
        }
        return size.uint64Value > 0
    }
}
