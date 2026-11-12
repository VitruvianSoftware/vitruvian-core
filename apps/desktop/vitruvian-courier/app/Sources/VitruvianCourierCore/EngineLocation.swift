// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Where the engine and its data are.
public enum EngineLocation {
    /// Overrides the data directory: for development and testing, never for James's real data.
    public static let dataDirectoryVariable = "COURIER_DATA_DIR"
    /// Overrides the engine: for `swift run`, which has no bundle to find it in.
    public static let enginePathVariable = "COURIER_ENGINE_PATH"

    /// `~/Library/Application Support/Courier`, or COURIER_DATA_DIR. The test copy (`TestCopy`) never falls back to
    /// the real folder: without COURIER_DATA_DIR it uses `~/Library/Application Support/Courier Test Copy`.
    public static func dataDirectory(environment: [String: String] = ProcessInfo.processInfo.environment,
                                     home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                     bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URL {
        if let path = environment[dataDirectoryVariable], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let folder = bundleIdentifier == TestCopy.bundleIdentifier ? "Courier Test Copy" : "Courier"
        return home.appendingPathComponent("Library/Application Support/\(folder)", isDirectory: true)
    }

    /// `Contents/Helpers/courier-engine` in the app's bundle, or COURIER_ENGINE_PATH.
    public static func enginePath(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  bundleURL: URL = Bundle.main.bundleURL) -> String {
        if let path = environment[enginePathVariable], !path.isEmpty { return path }
        return bundleURL.appendingPathComponent("Contents/Helpers/courier-engine").path
    }
}

/// The test copy: a build of Courier with its own bundle identifier (`:CourierTestCopy`, run by `:run_test_copy`), for
/// trying a change in a real running app. Its own identifier gives it its own settings (UserDefaults), notification
/// permission and Login Items entry; with it, Courier also keeps its data (`EngineLocation.dataDirectory`) and its
/// Keychain items (`TelegramCredentials.service`) apart from the installed app's.
public enum TestCopy {
    public static let bundleIdentifier = "com.vitruviansoftware.courier.dev"
}
