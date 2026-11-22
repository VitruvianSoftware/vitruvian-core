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

/// Shared bundle resource directory discovery for Bazel `.app` bundles,
/// SwiftPM `.bundle` resource folders, and unbundled `bin/` tool layouts.
public enum BundleResources {

    /// The folder SwiftPM puts the shared UI library's resources in, beside the
    /// executable it builds.
    public static let swiftPMUIResourceBundleName = "VitruvianCode_VitruvianCodeUI.bundle"

    /// The folder SwiftPM puts the shared Core library's resources in, if any.
    public static let swiftPMCoreResourceBundleName = "VitruvianCode_VitruvianCodeCore.bundle"

    /// Where bundled resources can live for an app or executable whose main
    /// bundle is `bundle`, most likely first.
    ///
    /// The two builds put resources in different places, and nothing the
    /// compiler defines tells them apart reliably (`Bundle.module` exists only
    /// under SwiftPM, and stops the app when its folder is not where it
    /// expects), so every place is tried:
    /// - Bazel copies resources straight into the app's `Contents/Resources`;
    /// - SwiftPM writes them into a resource `.bundle`, which the release
    ///   bundler copies into `Contents/Resources`, and which sits beside the
    ///   executable when run without being packaged.
    public static func resourceDirectories(
        for bundle: Bundle,
        swiftPMResourceBundleName: String = swiftPMUIResourceBundleName
    ) -> [URL] {
        resourceDirectories(
            resourceURL: bundle.resourceURL,
            executableURL: bundle.executableURL,
            swiftPMResourceBundleName: swiftPMResourceBundleName
        )
    }

    /// Lower-level overload for callers and tests supplying explicit URLs.
    public static func resourceDirectories(
        resourceURL: URL?,
        executableURL: URL?,
        swiftPMResourceBundleName: String = swiftPMUIResourceBundleName
    ) -> [URL] {
        var roots: [URL] = []
        if let resourceURL { roots.append(resourceURL) }
        if let executableURL { roots.append(executableURL.deletingLastPathComponent()) }
        var directories: [URL] = []
        for root in roots {
            let swiftPM = root.appendingPathComponent(swiftPMResourceBundleName, isDirectory: true)
            directories.append(root)
            directories.append(swiftPM)
            directories.append(swiftPM.appendingPathComponent("Contents/Resources", isDirectory: true))
        }
        return directories
    }

    /// SwiftPM resource bundle directories (both flat and `Contents/Resources`
    /// nested layouts) under `resourceURL` and the executable's directory.
    public static func swiftPMResourceDirectories(
        resourceURL: URL?,
        executableURL: URL?,
        bundleNames: [String] = [swiftPMCoreResourceBundleName, swiftPMUIResourceBundleName]
    ) -> [URL] {
        var roots: [URL] = []
        if let resourceURL { roots.append(resourceURL) }
        if let executableURL { roots.append(executableURL.deletingLastPathComponent()) }
        var directories: [URL] = []
        for root in roots {
            for bundleName in bundleNames {
                let swiftPM = root.appendingPathComponent(bundleName, isDirectory: true)
                directories.append(swiftPM)
                directories.append(swiftPM.appendingPathComponent("Contents/Resources", isDirectory: true))
            }
        }
        return deduplicated(directories)
    }

    /// Deduplicates URLs by standardized path while preserving order.
    static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
