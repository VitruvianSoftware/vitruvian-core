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
import os
import VitruvianCodeCore

extension VitruvianCodeLegacyMigration.Environment {
    /// This Mac, as the app sees it: the app's own saved settings, and the
    /// old app's, read from its domain without opening it as a suite.
    static func live(executablePath: String) -> Self {
        let logger = Logger(subsystem: "com.vitruviansoftware.code", category: "legacy-migration")
        let defaults = UserDefaults.standard
        return Self(
            home: NSHomeDirectory(),
            userID: getuid(),
            executablePath: executablePath,
            settings: .init(value: { defaults.object(forKey: $0) }, set: { defaults.set($0, forKey: $1) }),
            readLegacyDefaults: {
                defaults.persistentDomain(forName: VitruvianCodeLegacyMigration.legacyBundleID) ?? [:]
            },
            launchctl: VitruvianCodeLegacyMigration.runLaunchctl,
            log: { message in
                logger.notice("\(message, privacy: .public)")
                print("legacy-migration: \(message)")
            },
            canRewriteAutomations: Self.isInstalledForAutomations(bundlePath: Bundle.main.bundleURL.path,
                                                                  home: NSHomeDirectory()))
    }
}
