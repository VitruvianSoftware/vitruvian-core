// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import os
import VitruvianCore
import VitruvianToolProtocol

/// What the Nexus Agent feature kept goes to the Nexus Agent tool
/// (`dev.vitruvian.nexus-agent`), once, when the tool is added: the bot
/// folder, whether the bot starts with the app, plan mode, worktree mode,
/// the provider chosen, the providers of the person's own, the prompt
/// history and the archived Claude sessions, each written as one of the
/// tool's own preferences through `storage`, the only thing the app lets a
/// tool read; and the Quick Prompt's shortcut, when it is on, written as
/// the shortcut of the tool's `quickPrompt` command, which is the app's
/// own to keep. The model chosen for each provider, and the sessions the
/// person pinned or renamed, go too when there are any; a tool whose
/// manifest does not declare them is handed the rest. The tool takes the four untitled ones into a file of its
/// own on its first run and clears the handed copies.
///
/// The feature itself went in 3.73; this stays one release more, for a
/// person who skipped 3.72, where the feature offered the tool, reading the
/// feature's old preference keys, which stay declared for it. The Telegram
/// bot a person had running is the tool's to adopt through the PID file
/// both share.
/// Design: `docs/superpowers/specs/2026-10-12-vitruvian-tools-for-everyone-design.md`,
/// section 9.
@MainActor
package enum NexusAgentHandoff {
    package static let toolID = ToolID("dev.vitruvian.nexus-agent")!
    /// The tool's command the Quick Prompt's shortcut goes to.
    package static let quickPromptCommand = CommandID(tool: toolID, name: "quickPrompt")!

    /// The tool's preferences, by the ids its manifest declares.
    package enum Key {
        package static let botDirectory = "botDirectory"
        package static let autoStart = "autoStart"
        package static let planMode = "planMode"
        package static let worktreeMode = "worktreeMode"
        package static let chosenProvider = "chosenProvider"
        package static let savedProviders = "savedProviders"
        package static let promptHistory = "promptHistory"
        package static let hiddenClaudeSessions = "hiddenClaudeSessions"
        package static let chosenModels = "chosenModels"
        package static let pinnedSessions = "pinnedSessions"
        package static let renamedSessions = "renamedSessions"
    }

    package struct Parts {
        package var defaults: UserDefaults
        /// The archived Claude sessions, which the feature kept in the
        /// app's own defaults whatever `defaults` is.
        package var hiddenClaudeSessions: () -> [String]
        /// Where a tool's preferences are kept: the broker's storage backing.
        package var backing: StorageAccess.Backing
        /// Gives the tool's command the shortcut the feature had.
        package var saveShortcut: (GlobalShortcut) -> Void
        package var log: (String) -> Void

        package init(defaults: UserDefaults, hiddenClaudeSessions: @escaping () -> [String],
                     backing: StorageAccess.Backing, saveShortcut: @escaping (GlobalShortcut) -> Void,
                     log: @escaping (String) -> Void) {
            self.defaults = defaults
            self.hiddenClaudeSessions = hiddenClaudeSessions
            self.backing = backing
            self.saveShortcut = saveShortcut
            self.log = log
        }

        /// The key the feature's host kept the archived Claude sessions
        /// under, in the app's own defaults.
        package static let hiddenClaudeSessionsKey = "vitruvian.claude.hiddenSessionIds"
        /// The keys the feature's chat kept the model chosen for each
        /// provider, and the sessions pinned and renamed, under: its own,
        /// not in `Preferences`, and read here alone now the feature is gone.
        package static let chosenModelsKey = "vitruvian.nexusAgent.chosenModels"
        package static let pinnedSessionsKey = "vitruvian.nexusAgent.pinnedSessionIds"
        package static let renamedSessionsKey = "vitruvian.nexusAgent.renamedSessionTitles"

        @MainActor package static let live = Parts(
            defaults: .standard,
            hiddenClaudeSessions: { UserDefaults.standard.stringArray(forKey: hiddenClaudeSessionsKey) ?? [] },
            backing: CapabilityBroker.shared.backings.storage,
            saveShortcut: { shortcut in
                var shortcuts = ToolCommandShortcuts.load(from: .standard)
                shortcuts[quickPromptCommand.rawValue] = shortcut
                ToolCommandShortcuts.save(shortcuts, to: .standard)
                ToolShortcutRegistrar.shared.sync()
            },
            log: { Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian", category: "nexus-agent-handoff").notice("\($0, privacy: .public)") })
    }

    package enum Outcome: Equatable, Sendable {
        /// Not the Nexus Agent tool: nothing to do.
        case notTheTool
        /// Handed over already; the tool was updated.
        case alreadyHanded
        /// Handed over, these preferences written, and whether the
        /// shortcut went with them. A preference the tool's manifest does
        /// not declare is left out and logged.
        case handed([String], shortcut: Bool)
    }

    /// Writes the feature's settings into the tool's storage. Called by the
    /// tool store before the tool's program starts, for a tool added from
    /// the catalog or from a folder alike.
    @discardableResult
    package static func perform(_ installed: ExternalToolStore.Installed, from origin: CatalogueOrigin?,
                                parts: Parts) -> Outcome {
        guard installed.tool.manifest.id == toolID else { return .notTheTool }
        guard !parts.defaults[Preferences.nexusAgentReplacedByTool] else { return .alreadyHanded }
        // The tool's own storage, by its manifest's keys and kinds: a value
        // of another kind, or a key the manifest lacks, is refused as it
        // would be for the tool.
        let storage = StorageAccess(gate: { nil }, manifest: installed.tool.manifest, backing: parts.backing)
        var written: [String] = []
        for (name, value) in values(defaults: parts.defaults, hiddenClaudeSessions: parts.hiddenClaudeSessions()) {
            let key = ExternalToolManifest.storageKey(tool: toolID, preference: name)
            if let problem = storage.set(value, for: key) {
                parts.log("the Nexus Agent tool does not take \(name): \(problem)")
            } else {
                written.append(name)
            }
        }
        let shortcut = shortcut(defaults: parts.defaults)
        if let shortcut { parts.saveShortcut(shortcut) }
        parts.defaults[Preferences.nexusAgentReplacedByTool] = true
        parts.log("handed the Nexus Agent feature's settings to the Nexus Agent tool"
            + (origin.map { ", version \($0.version) from the catalog" } ?? ", added from a folder"))
        return .handed(written.sorted(), shortcut: shortcut != nil)
    }

    /// The tool was removed: added again, it is handed the settings again.
    package static func toolRemoved(_ id: ToolID, defaults: UserDefaults) {
        guard id == toolID, defaults[Preferences.nexusAgentReplacedByTool] else { return }
        defaults[Preferences.nexusAgentReplacedByTool] = false
    }

    /// What is handed over, by the tool's preference ids, from the
    /// feature's preferences. The lists go as JSON text, as the feature
    /// kept them; the providers as the JSON the feature saved, when it
    /// saved any.
    package static func values(defaults: UserDefaults, hiddenClaudeSessions: [String]) -> [String: PreferenceDeclaration.Value] {
        var values: [String: PreferenceDeclaration.Value] = [
            Key.botDirectory: .string(defaults[Preferences.nexusAgentBotDirectory]),
            Key.autoStart: .bool(defaults[Preferences.nexusAgentAutoStart]),
            Key.planMode: .bool(defaults[Preferences.nexusAgentPlanMode]),
            Key.worktreeMode: .bool(defaults[Preferences.nexusAgentWorktreeMode]),
            Key.chosenProvider: .string(defaults[Preferences.nexusAgentChosenProvider]),
            Key.promptHistory: .string(json(defaults[Preferences.nexusAgentPromptHistory])),
            Key.hiddenClaudeSessions: .string(json(hiddenClaudeSessions)),
        ]
        let providers = defaults[Preferences.nexusAgentSavedProviders]
        values[Key.savedProviders] = .string(providers.isEmpty ? "" : String(decoding: providers, as: UTF8.self))
        // Kept by the chat in keys of the app's own, not in `Preferences`:
        // handed only when the person set some, as JSON text.
        // A model is kept only for a provider whose id reads, as the chat
        // read it.
        let savedModels = defaults.dictionary(forKey: Parts.chosenModelsKey) as? [String: String] ?? [:]
        var models: [String: String] = [:]
        for (provider, model) in savedModels {
            if let id = UUID(uuidString: provider) { models[id.uuidString] = model }
        }
        if !models.isEmpty { values[Key.chosenModels] = .string(json(models)) }
        let pinned = Set(defaults.stringArray(forKey: Parts.pinnedSessionsKey) ?? [])
        if !pinned.isEmpty { values[Key.pinnedSessions] = .string(json(pinned.sorted())) }
        let renamed = defaults.dictionary(forKey: Parts.renamedSessionsKey) as? [String: String] ?? [:]
        if !renamed.isEmpty { values[Key.renamedSessions] = .string(json(renamed)) }
        return values
    }

    /// The Quick Prompt's shortcut, when its switch is on; nil otherwise.
    /// Read from `defaults`, as the feature read it: a saved text that is no
    /// shortcut is the feature's default.
    package static func shortcut(defaults: UserDefaults) -> GlobalShortcut? {
        guard defaults[Preferences.nexusAgentShortcutEnabled] else { return nil }
        return GlobalShortcut(storageValue: defaults[Preferences.nexusAgentShortcut]) ?? .nexusAgentDefault
    }

    private static func json(_ list: [String]) -> String {
        guard !list.isEmpty, let data = try? JSONEncoder().encode(list) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A map as JSON text, its keys in order, so the same map is always
    /// the same text.
    private static func json(_ map: [String: String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard !map.isEmpty, let data = try? encoder.encode(map) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
