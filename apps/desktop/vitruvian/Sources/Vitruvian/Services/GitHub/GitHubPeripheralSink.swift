// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// Translates the aggregate GitHub status verdict into physical GravaStar mouse RGB signals.
@MainActor
package final class GitHubPeripheralSink {
    /// Runs one mouse command, e.g. `["color", "green"]`.
    package typealias Executor = @MainActor ([String]) -> Void

    package static let shared = GitHubPeripheralSink()

    /// What the mouse was last told to show. An approval hides the verdict
    /// behind it, so a verdict that moves while one is pending writes nothing.
    private enum Shown: Equatable {
        case awaitingApproval
        case verdict(Verdict)
    }

    private var lastShown: Shown?
    private let defaults: UserDefaults
    private let executor: Executor?

    /// `executor` stands in for the mouse binary; nil runs the binary itself.
    package init(defaults: UserDefaults = .standard, executor: Executor? = nil) {
        self.defaults = defaults
        self.executor = executor
    }

    /// Shows what `summary` comes to: its approval flag first, else its
    /// aggregate verdict.
    package func update(summary: GitHubSummary, force: Bool = false) {
        update(verdict: summary.aggregate, awaitingApproval: summary.awaitingApproval, force: force)
    }

    /// Updates the GravaStar mouse RGB lighting based on the current aggregate verdict.
    /// `awaitingApproval` outranks every verdict, red included; when it clears,
    /// the next call writes the verdict again.
    /// A repeated state writes nothing, unless `force`: the mouse keeps its
    /// last LED state across app restarts, so the first snapshot after launch
    /// always writes, even when it matches what this process last sent.
    package func update(verdict: Verdict, awaitingApproval: Bool = false, force: Bool = false) {
        let shown: Shown = awaitingApproval ? .awaitingApproval : .verdict(verdict)
        guard force || shown != lastShown else { return }
        lastShown = shown

        if awaitingApproval {
            signal(color: defaults[Preferences.githubMouseApprovalColor],
                   mode: defaults[Preferences.githubMouseApprovalMode],
                   speed: defaults[Preferences.githubMouseApprovalSpeed])
            return
        }

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
    /// `speed` is the breathe speed, held to the mouse's 0-9; nil leaves it to
    /// the mouse command, and a solid colour has none.
    package func signal(color: String, mode: String, speed: Int? = nil) {
        let cleanColor = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanMode == "breathe" {
            var arguments = ["breathe", cleanColor]
            if let speed {
                arguments += ["--speed", String(min(9, max(0, speed)))]
            }
            execute(arguments: arguments)
        } else {
            execute(arguments: ["color", cleanColor])
        }
    }

    /// Restores the mouse lighting back to the user's personal baseline.
    package func restore() {
        lastShown = nil
        execute(arguments: ["restore"])
    }

    private func execute(arguments: [String]) {
        if let executor {
            executor(arguments)
            return
        }
        // Looked up on every write, so a binary installed while the app runs
        // is picked up. Without one there is no mouse to drive.
        guard let binary = GitHubMouseBinary.locate(configured: defaults[Preferences.githubMouseBinaryPath],
                                                    environment: ProcessInfo.processInfo.environment,
                                                    home: NSHomeDirectory(),
                                                    isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
