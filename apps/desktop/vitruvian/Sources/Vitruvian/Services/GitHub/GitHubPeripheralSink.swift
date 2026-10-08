// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Translates the aggregate GitHub status verdict into physical GravaStar mouse RGB signals.
@MainActor
package final class GitHubPeripheralSink {
    package static let shared = GitHubPeripheralSink()

    private var lastVerdict: Verdict?
    private let mouseBinaryPath = "/Users/james/bin/gravastar-mouse"
    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Updates the GravaStar mouse RGB lighting based on the current aggregate verdict.
    package func update(verdict: Verdict) {
        guard verdict != lastVerdict else { return }
        lastVerdict = verdict

        switch verdict {
        case .green:
            let color = defaults[Preferences.githubMouseSuccessColor]
            let mode = defaults[Preferences.githubMouseSuccessMode]
            signal(color: color, mode: mode)
        case .amber:
            let color = defaults[Preferences.githubMouseRunningColor]
            let mode = defaults[Preferences.githubMouseRunningMode]
            signal(color: color, mode: mode)
        case .red:
            let color = defaults[Preferences.githubMouseFailureColor]
            let mode = defaults[Preferences.githubMouseFailureMode]
            signal(color: color, mode: mode)
        case .grey:
            let behavior = defaults[Preferences.githubMouseIdleBehavior]
            if behavior == "off" {
                execute(arguments: ["off"])
            } else {
                restore()
            }
        }
    }

    /// Signals a specific color and mode (solid vs pulsing) on the mouse.
    package func signal(color: String, mode: String) {
        let cleanColor = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanMode == "breathe" {
            execute(arguments: ["breathe", cleanColor])
        } else {
            execute(arguments: ["color", cleanColor])
        }
    }

    /// Restores the mouse lighting back to the user's personal baseline.
    package func restore() {
        lastVerdict = nil
        execute(arguments: ["restore"])
    }

    private func execute(arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: mouseBinaryPath) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: mouseBinaryPath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
