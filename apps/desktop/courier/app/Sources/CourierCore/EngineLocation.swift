// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Where the engine and its data are.
public enum EngineLocation {
    /// Overrides the data directory: for development and testing, never for James's real data.
    public static let dataDirectoryVariable = "COURIER_DATA_DIR"
    /// Overrides the engine: for `swift run`, which has no bundle to find it in.
    public static let enginePathVariable = "COURIER_ENGINE_PATH"

    /// `~/Library/Application Support/Courier`, or COURIER_DATA_DIR.
    public static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                     home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let path = environment[dataDirectoryVariable], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return home.appendingPathComponent("Library/Application Support/Courier", isDirectory: true)
    }

    /// `Contents/Helpers/courier-engine` in the app's bundle, or COURIER_ENGINE_PATH.
    public static func enginePath(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  bundleURL: URL = Bundle.main.bundleURL) -> String {
        if let path = environment[enginePathVariable], !path.isEmpty { return path }
        return bundleURL.appendingPathComponent("Contents/Helpers/courier-engine").path
    }
}
