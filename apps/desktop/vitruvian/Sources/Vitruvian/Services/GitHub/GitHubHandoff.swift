// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import os
import VitruvianCore
import VitruvianToolProtocol

/// What the GitHub feature kept goes to the GitHub tool
/// (`dev.vitruvian.github`), once, when the tool is added: the token from
/// the feature's Keychain item, the watched repositories, the poll
/// intervals, the mouse settings and the client ID, each written as one of
/// the tool's own preferences through `storage`, the only thing the app
/// lets a tool read. The tool moves the token into a file of its own on its
/// first run and clears the handed copy.
///
/// The feature itself went in 3.47; this stays one release more, for a
/// person who skipped 3.46, where the feature offered the tool. Stage F
/// removes it with the feature's preferences and its Keychain store.
///
/// The token comes from the Keychain, which may hold the read until the
/// person answers its prompt (the app is signed ad hoc, so macOS asks again
/// after an update). `prepare` has it read off the main thread before the
/// tool is added (`GitHubSavedToken`); `perform` then takes what was read,
/// and waits for nothing.
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
        /// Reads the feature's token from its Keychain item, off the main
        /// thread, and calls back on it once `token` can answer at once.
        package var readToken: (@escaping @MainActor () -> Void) -> Void
        /// The feature's token as it was read; nil with none, or when the
        /// person refused the Keychain's prompt. It never waits.
        package var token: () -> String?
        /// Where a tool's preferences are kept: the broker's storage backing.
        package var backing: StorageAccess.Backing
        package var log: (String) -> Void

        @MainActor package init(defaults: UserDefaults, readToken: @escaping (@escaping @MainActor () -> Void) -> Void = { $0() },
                     token: @escaping () -> String?, backing: StorageAccess.Backing,
                     log: @escaping (String) -> Void) {
            self.defaults = defaults
            self.readToken = readToken
            self.token = token
            self.backing = backing
            self.log = log
        }

        @MainActor package static let live = Parts(
            defaults: .standard,
            readToken: { ready in GitHubSavedToken.shared.load { _ in ready() } },
            token: { GitHubSavedToken.shared.current() },
            backing: CapabilityBroker.shared.backings.storage,
            log: { Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "github-handoff").notice("\($0, privacy: .public)") })
    }

    package enum Outcome: Equatable, Sendable {
        /// Not the GitHub tool: nothing to do.
        case notTheTool
        /// Handed over already; the tool was updated.
        case alreadyHanded
        /// Handed over, these preferences written. A preference the tool's
        /// manifest does not declare is left out and logged.
        case handed([String])
    }

    /// Has the token read before a tool is added, and calls `ready` on the
    /// main thread when `perform` can run without waiting: at once for any
    /// other tool, and for the GitHub tool once the feature is handed over
    /// already. The main thread is never held: the Keychain may take as long
    /// as the person takes to answer its prompt. A refused prompt is ready
    /// too, with no token, so the tool starts signed out.
    package static func prepare(_ id: ToolID, parts: Parts, then ready: @escaping @MainActor () -> Void) {
        guard id == toolID, !parts.defaults[Preferences.githubReplacedByTool] else { return ready() }
        parts.readToken(ready)
    }

    /// Writes the feature's settings into the tool's storage. Called by the
    /// tool store before the tool's program starts, for a tool added from
    /// the catalog or from a folder alike. `prepare` comes first
    /// (`ExternalToolStore.add(_:then:)`), so the token is there to take.
    @discardableResult
    package static func perform(_ installed: ExternalToolStore.Installed, from origin: CatalogueOrigin?,
                                parts: Parts) -> Outcome {
        guard installed.tool.manifest.id == toolID else { return .notTheTool }
        guard !parts.defaults[Preferences.githubReplacedByTool] else { return .alreadyHanded }
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
        parts.log("handed the GitHub feature's settings to the GitHub tool"
            + (origin.map { ", version \($0.version) from the catalog" } ?? ", added from a folder"))
        return .handed(written.sorted())
    }

    /// The tool was removed: added again, it is handed the settings again.
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
            Key.watchlist: .string(watchlist(defaults[Preferences.githubWatchedRepositories])),
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

    /// The feature's watchlist, a JSON array of `owner/name`, as the tool's
    /// field reads it: `owner/name, owner/name`. What cannot be read is the
    /// feature's default, as the feature read it.
    static func watchlist(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8), let names = try? JSONDecoder().decode([String].self, from: data) else {
            return "VitruvianSoftware/vitruvian-core"
        }
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: "/").count == 2 && seen.insert($0.lowercased()).inserted }
            .joined(separator: ", ")
    }

    /// One light as the tool's setting reads: `breathe <colour> [speed]`
    /// for the breathe style, else the colour alone.
    static func light(_ color: String, _ mode: String, speed: Int? = nil) -> String {
        let color = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "breathe" else { return color }
        return speed.map { "breathe \(color) \(min(9, max(0, $0)))" } ?? "breathe \(color)"
    }
}

/// The GitHub feature's saved token, read from its Keychain item off the
/// main thread, once. The feature's sign-in did this while there was one
/// (`GitHubAuthService.loadToken`); the feature is gone, and its token is
/// still what the hand-off gives the tool.
///
/// The app is signed ad hoc, so after an update macOS asks the person before
/// the new build may read the item an older one saved, and holds the read
/// until they answer. On the main thread that froze every window and the
/// menu bar icon behind a prompt that may be under another window.
@MainActor
package final class GitHubSavedToken {
    package static let shared = GitHubSavedToken(store: KeychainGitHubTokenStore())

    private let store: any GitHubTokenStore
    /// One read at a time: it may wait for the person's answer to the
    /// Keychain's prompt.
    private let keychainQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.github-handoff.keychain",
                                              qos: .userInitiated)
    private var token: String?
    private var loaded = false
    /// Who waits for the read; nil while no read is out.
    private var waiters: [@MainActor (String?) -> Void]?

    package init(store: any GitHubTokenStore) {
        self.store = store
    }

    /// The token as it was read, or nil: none saved, not read yet, or the
    /// person refused the Keychain's prompt. It never asks the Keychain, so
    /// it never waits.
    package func current() -> String? {
        token
    }

    /// Reads the saved token off the main thread, once, and calls `done` on
    /// the main thread with it; at once when it was read already. The read
    /// may take as long as the person takes to answer the Keychain's prompt,
    /// and the main thread never waits for it. A refusal (the person pressed
    /// Deny) is no token.
    package func load(then done: @escaping @MainActor (String?) -> Void) {
        guard !loaded else { return done(token) }
        guard waiters == nil else {
            waiters?.append(done)
            return
        }
        waiters = [done]
        let store = store
        keychainQueue.async { [weak self] in
            let read = try? store.load()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.wasRead(read) }
            }
        }
    }

    private func wasRead(_ read: String?) {
        let waiting = waiters ?? []
        waiters = nil
        loaded = true
        token = read
        for waiter in waiting { waiter(token) }
    }
}
