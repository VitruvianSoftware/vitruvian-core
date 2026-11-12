// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What the menu bar panel's Extensions tab lists: of each extension that is
/// switched on and is what the person agreed to, its island page, with the
/// extension's name and symbol. The page itself is the panel host's, the same
/// page the island shows (`ToolPanelHost.openInMenuPanel`).
///
/// The tab shows an extension's island page whether or not the island lists
/// it ("Show in the Dynamic Island" is the island's switch); the tab has its
/// own edit mode to reorder and hide extensions in place.
@MainActor
package enum MenuPanelExtensions {
    /// One extension's island page, as the tab and its switches name it.
    package struct Entry: Identifiable, Hashable, Sendable {
        package let key: ToolPanelHost.Key
        /// The extension's name in the person's language, as its author
        /// wrote it.
        package let name: String
        /// The page's symbol: its own, else the extension's.
        package let symbol: String
        /// The extension's count of `ExternalToolStore.activations`. An
        /// extension updated, or switched off and on, is another entry, so
        /// its card asks for its page again instead of keeping the old one's
        /// "could not be shown".
        package let activation: Int

        package var id: String { key.tool.rawValue + "/" + key.panel + "#\(activation)" }

        package init(key: ToolPanelHost.Key, name: String, symbol: String, activation: Int = 0) {
            self.key = key
            self.name = name
            self.symbol = symbol
            self.activation = activation
        }
    }

    /// Every extension with an island page, in the order they were added,
    /// whether or not the tab shows it.
    package static func available(store: ExternalToolStore, language: AppLanguage) -> [Entry] {
        store.availableIslandPanels().compactMap { key in
            guard let tool = store.installed[key.tool]?.tool, let panel = tool.panel(key.panel) else { return nil }
            let name = tool.name.text(for: language.rawValue) ?? tool.manifest.tool.name
            return Entry(key: key, name: name, symbol: panel.symbol, activation: store.activations[key.tool] ?? 0)
        }
    }

    /// Every extension with an island page, in the tab's saved order: what
    /// the tab's edit mode lists to reorder and show or hide.
    package static func ordered(store: ExternalToolStore, defaults: UserDefaults, language: AppLanguage) -> [Entry] {
        let entries = available(store: store, language: language)
        let byTool = Dictionary(entries.map { ($0.key.tool, $0) }, uniquingKeysWith: { first, _ in first })
        return MenuPanelExtensionsSupport.ordered(entries.map(\.key.tool), in: defaults)
            .compactMap { byTool[$0] }
    }

    /// The ones the tab shows: every extension with an island page, in the
    /// tab's saved order, without those the person switched off for it.
    package static func shown(store: ExternalToolStore, defaults: UserDefaults, language: AppLanguage) -> [Entry] {
        let entries = ordered(store: store, defaults: defaults, language: language)
        let kept = Set(MenuPanelExtensionsSupport.shown(entries.map(\.key.tool), in: defaults))
        return entries.filter { kept.contains($0.key.tool) }
    }

    /// Where extensions are added and managed: Settings' Extensions page.
    /// The one place the tab says so.
    nonisolated package static var extensionSettings: FeatureSettingsDestination {
        ExtensionsPageSupport.destination
    }

    /// Opens Settings on the Extensions page, from the tab's empty state.
    package static func openExtensionSettings() {
        SettingsRouter.shared.request(extensionSettings)
        appShell()?.openSettingsWindow()
    }

    /// Opens the Dynamic Island on an extension's page, from the line the tab
    /// shows while the island holds that page. The popover goes first, so
    /// the island is in front; the island's own rule decides, and does
    /// nothing for a page it does not list.
    package static func showInIsland(_ key: ToolPanelHost.Key) {
        appShell()?.closePopover(preservingNotch: true)
        NotchService.shared.openExtensionSection(key)
    }
}
