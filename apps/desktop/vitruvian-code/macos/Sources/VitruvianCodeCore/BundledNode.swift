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

/// The architecture this process runs as: `arm64` or `x86_64`.
///
/// It is the slice that is executing, not the Mac's chip, so a universal app
/// run under Rosetta reports `x86_64`.
public enum HelperArchitecture {
    #if arch(arm64)
    public static let current = "arm64"
    #elseif arch(x86_64)
    public static let current = "x86_64"
    #else
    #error("Vitruvian Code ships helpers for arm64 and x86_64 only")
    #endif

    /// Both architectures a universal app carries a helper for.
    public static let all = ["arm64", "x86_64"]

    /// `name-arm64` or `name-x86_64`: the file a universal app holds for `name`.
    public static func fileName(_ name: String, architecture: String = current) -> String {
        "\(name)-\(architecture)"
    }

    /// The file names to try for `name`, in order: this architecture's thin
    /// copy first (what the universal app ships), then the plain name (what a
    /// single-architecture app and the tool folder ship).
    public static func fileNames(_ name: String, architecture: String = current) -> [String] {
        [fileName(name, architecture: architecture), name]
    }
}

/// Locates the Node runtime and Claude helper bundle shipped inside the app or
/// tool folder.
///
/// Never looks on `PATH`, in Homebrew, nvm, or the user's home directory:
/// returns `nil` when either bundled file is missing or invalid.
///
/// The universal app ships `node-arm64` and `node-x86_64`, each a thin Mach-O,
/// instead of one fat `node` (XProtect refuses a universal app that holds a
/// fat helper). The one for this process's architecture is tried first, then
/// the plain `node` that single-architecture apps and the tool folder ship.
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
    /// Search order (`node` below means `node-<architecture>`, then `node`):
    /// 1. App bundle: `Contents/Helpers/node` and `Contents/Resources/claude-helper/claude-helper.mjs`.
    /// 2. Tool / executable folder: `<execDir>/node` and `<execDir>/claude-helper/claude-helper.mjs`.
    /// 3. SwiftPM resource bundle (`VitruvianCode_VitruvianCodeCore.bundle` / `VitruvianCode_VitruvianCodeUI.bundle`).
    public static func locate(
        in bundle: Bundle = .main,
        architecture: String = HelperArchitecture.current,
        fileManager: FileManager = .default
    ) -> BundledNode? {
        locate(
            bundleURL: bundle.bundleURL,
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            architecture: architecture,
            fileManager: fileManager
        )
    }

    /// Overload with explicit bundle URLs for unit tests and custom layouts.
    public static func locate(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?,
        architecture: String = HelperArchitecture.current,
        fileManager: FileManager = .default
    ) -> BundledNode? {
        guard let nodeURL = nodeURL(
            bundleURL: bundleURL,
            resourceURL: resourceURL,
            executableURL: executableURL,
            architecture: architecture,
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
    ///
    /// In each folder `node-<architecture>` comes before `node`.
    public static func nodeCandidates(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?,
        architecture: String = HelperArchitecture.current
    ) -> [URL] {
        let names = HelperArchitecture.fileNames(nodeExecutableName, architecture: architecture)
        var candidates: [URL] = []
        func add(_ directory: URL) {
            for name in names {
                candidates.append(directory.appendingPathComponent(name, isDirectory: false))
            }
        }

        // 1. App bundle Contents/Helpers (Mach-O code never lives in Resources).
        if let bundleURL {
            add(bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true))
        }
        if let executableURL {
            let execDir = executableURL.deletingLastPathComponent()
            add(execDir.appendingPathComponent("../Helpers", isDirectory: true))
            // 2. Folder beside executable (tool `bin/` layout).
            add(execDir)
        }
        // Unpackaged directory `Bundle(url: binDir)` has resourceURL == bundleURL
        // and no executableURL; allow that folder as a sibling layout while never
        // accepting `Contents/Resources/node` inside a `.app`.
        if let resourceURL,
           resourceURL.pathExtension != "app",
           resourceURL.lastPathComponent != "Resources" || resourceURL.deletingLastPathComponent().lastPathComponent != "Contents" {
            add(resourceURL)
        }

        // 3. SwiftPM resource bundle directories.
        for dir in BundleResources.swiftPMResourceDirectories(resourceURL: resourceURL, executableURL: executableURL) {
            add(dir)
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
    public static func nodeURL(
        in bundle: Bundle = .main,
        architecture: String = HelperArchitecture.current,
        fileManager: FileManager = .default
    ) -> URL? {
        nodeURL(
            bundleURL: bundle.bundleURL,
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            architecture: architecture,
            fileManager: fileManager
        )
    }

    /// Returns the first valid bundled `node` executable URL, or `nil`.
    public static func nodeURL(
        bundleURL: URL?,
        resourceURL: URL?,
        executableURL: URL?,
        architecture: String = HelperArchitecture.current,
        fileManager: FileManager = .default
    ) -> URL? {
        nodeCandidates(
            bundleURL: bundleURL,
            resourceURL: resourceURL,
            executableURL: executableURL,
            architecture: architecture
        )
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
