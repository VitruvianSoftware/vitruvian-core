// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import os
import VitruvianCore
import VitruvianToolProtocol

/// The GitHub feature hands what it kept to the GitHub tool
/// (`dev.vitruvian.github`), once, when the tool is added: the token, the
/// watched repositories, the poll intervals, the mouse settings and the
/// client ID, each written as one of the tool's own preferences through
/// `storage`, the only thing the app lets a tool read. The feature's switch
/// goes off and the feature is hidden (`AppFeature.isReplaced`) until the
/// tool is removed. The tool moves the token into a file of its own on its
/// first run and clears the handed copy; the feature's Keychain item stays,
/// so turning the tool off and the feature back on costs nothing.
///
/// What does not move: signing in through a browser window, which needs
/// the app's URL scheme; the feature's page in the island, which becomes a
/// tile on the island's Tools page; and the `h` key that opened it.
/// Design: `docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md`,
/// section 9.
@MainActor
package enum GitHubHandoff {
    package static let toolID = ToolID("dev.vitruvian.github")!

    /// The tool's preferences, by the ids its manifest declares.
    package enum Key {
        package static let migratedToken = "migratedToken"
        package static let watchlist = "watchlist"
        package static let pollInterval = "pollInterval"
        package static let pollActiveInterval = "pollActiveInterval"
        package static let mouseIndicator = "mouseIndicator"
        package static let mouseCommand = "mouseCommand"
        package static let mouseSuccess = "mouseSuccess"
        package static let mouseRunning = "mouseRunning"
        package static let mouseFailure = "mouseFailure"
        package static let mouseApproval = "mouseApproval"
        package static let mouseIdle = "mouseIdle"
        package static let clientID = "clientID"
    }

    package struct Parts {
        package var defaults: UserDefaults
        /// The feature's token, from its Keychain item; nil with none.
        package var token: () -> String?
        /// Where a tool's preferences are kept: the broker's storage backing.
        package var backing: StorageAccess.Backing
        /// Stops the feature's sign-in and its polling, now.
        package var featureOff: () -> Void
        package var log: (String) -> Void

        package init(defaults: UserDefaults, token: @escaping () -> String?, backing: StorageAccess.Backing,
                     featureOff: @escaping () -> Void, log: @escaping (String) -> Void) {
            self.defaults = defaults
            self.token = token
            self.backing = backing
            self.featureOff = featureOff
            self.log = log
        }

        @MainActor package static let live = Parts(
            defaults: .standard,
            token: { GitHubAuthService.shared.currentToken() },
            backing: CapabilityBroker.shared.backings.storage,
            featureOff: { GitHubAuthService.shared.cancel() },
            log: { Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "github-handoff").notice("\($0, privacy: .public)") })
    }

    package enum Outcome: Equatable, Sendable {
        /// Not the GitHub tool: nothing to do.
        case notTheTool
        /// The feature was handed over already; the tool was updated.
        case alreadyReplaced
        /// Handed over, these preferences written. A preference the tool's
        /// manifest does not declare is left out and logged.
        case handed([String])
    }

    /// Writes the feature's settings into the tool's storage, turns the
    /// feature off and hides it. Called by the tool store before the tool's
    /// program starts, for a tool added from the catalog or from a folder
    /// alike: a build of the tool a person tries by hand gets the same.
    @discardableResult
    package static func perform(_ installed: ExternalToolStore.Installed, from origin: CatalogueOrigin?,
                                parts: Parts) -> Outcome {
        guard installed.tool.manifest.id == toolID else { return .notTheTool }
        guard !parts.defaults[Preferences.githubReplacedByTool] else { return .alreadyReplaced }
        // The tool's own storage, by its manifest's keys and kinds: a value
        // of another kind, or a key the manifest lacks, is refused as it
        // would be for the tool.
        let storage = StorageAccess(gate: { nil }, manifest: installed.tool.manifest, backing: parts.backing)
        var written: [String] = []
        for (name, value) in values(defaults: parts.defaults, token: parts.token()) {
            let key = ExternalToolManifest.storageKey(tool: toolID, preference: name)
            if let problem = storage.set(value, for: key) {
                parts.log("the GitHub tool does not take \(name): \(problem)")
            } else {
                written.append(name)
            }
        }
        parts.defaults[Preferences.githubReplacedByTool] = true
        parts.defaults[Preferences.notchGitHubEnabled] = false
        parts.featureOff()
        parts.log("handed the GitHub feature's settings to the GitHub tool"
            + (origin.map { ", version \($0.version) from the catalog" } ?? ", added from a folder"))
        return .handed(written.sorted())
    }

    /// The tool was removed: the feature comes back, switched off, with
    /// its token still in the Keychain.
    package static func toolRemoved(_ id: ToolID, defaults: UserDefaults) {
        guard id == toolID, defaults[Preferences.githubReplacedByTool] else { return }
        defaults[Preferences.githubReplacedByTool] = false
    }

    /// What is handed over, by the tool's preference ids, from the
    /// feature's preferences and its token. The watched repositories go as
    /// the tool's field shows them, `owner/name, owner/name`; each mouse
    /// light as the tool reads it, `green` or `breathe orange` or
    /// `breathe blue 9`. The token goes only when there is one.
    package static func values(defaults: UserDefaults, token: String?) -> [String: PreferenceDeclaration.Value] {
        var values: [String: PreferenceDeclaration.Value] = [
            Key.watchlist: .string(GitHubWatchlist.decode(defaults[Preferences.githubWatchedRepositories])
                .map(\.fullName).joined(separator: ", ")),
            Key.pollInterval: .int(defaults[Preferences.githubPollInterval]),
            Key.pollActiveInterval: .int(defaults[Preferences.githubPollActiveInterval]),
            Key.mouseIndicator: .bool(defaults[Preferences.githubMouseIndicator]),
            Key.mouseCommand: .string(defaults[Preferences.githubMouseBinaryPath]),
            Key.mouseSuccess: .string(light(defaults[Preferences.githubMouseSuccessColor],
                                            defaults[Preferences.githubMouseSuccessMode])),
            Key.mouseRunning: .string(light(defaults[Preferences.githubMouseRunningColor],
                                            defaults[Preferences.githubMouseRunningMode])),
            Key.mouseFailure: .string(light(defaults[Preferences.githubMouseFailureColor],
                                            defaults[Preferences.githubMouseFailureMode])),
            Key.mouseApproval: .string(light(defaults[Preferences.githubMouseApprovalColor],
                                             defaults[Preferences.githubMouseApprovalMode],
                                             speed: defaults[Preferences.githubMouseApprovalSpeed])),
            Key.mouseIdle: .string(defaults[Preferences.githubMouseIdleBehavior]),
            Key.clientID: .string(defaults[Preferences.githubClientID]),
        ]
        if let token, !token.isEmpty { values[Key.migratedToken] = .string(token) }
        return values
    }

    /// One light as the tool's setting reads: `breathe <colour> [speed]`
    /// for the breathe style, else the colour alone.
    static func light(_ color: String, _ mode: String, speed: Int? = nil) -> String {
        let color = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "breathe" else { return color }
        return speed.map { "breathe \(color) \(min(9, max(0, $0)))" } ?? "breathe \(color)"
    }
}
