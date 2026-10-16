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
/// it ("Show in the Dynamic Island" is the island's switch); the tab has a
/// switch of its own for each, in Settings › Menu bar.
@MainActor
package enum MenuPanelExtensions {
    /// One extension's island page, as the tab and its switches name it.
    package struct Entry: Identifiable, Equatable, Sendable {
        package let key: ToolPanelHost.Key
        /// The extension's name in the person's language, as its author
        /// wrote it.
        package let name: String
        /// The page's symbol: its own, else the extension's.
        package let symbol: String

        package var id: String { key.tool.rawValue + "/" + key.panel }

        package init(key: ToolPanelHost.Key, name: String, symbol: String) {
            self.key = key
            self.name = name
            self.symbol = symbol
        }
    }

    /// Every extension with an island page, in the order they were added,
    /// whether or not the tab shows it: what Settings lists a switch for.
    package static func available(store: ExternalToolStore, language: AppLanguage) -> [Entry] {
        store.availableIslandPanels().compactMap { key in
            guard let tool = store.installed[key.tool]?.tool, let panel = tool.panel(key.panel) else { return nil }
            let name = tool.name.text(for: language.rawValue) ?? tool.manifest.tool.name
            return Entry(key: key, name: name, symbol: panel.symbol)
        }
    }

    /// The ones the tab shows: every extension with an island page, but those
    /// the person switched off for it.
    package static func shown(store: ExternalToolStore, defaults: UserDefaults, language: AppLanguage) -> [Entry] {
        let entries = available(store: store, language: language)
        let kept = Set(MenuPanelExtensionsSupport.shown(entries.map(\.key.tool), in: defaults))
        return entries.filter { kept.contains($0.key.tool) }
    }

    /// Opens Settings where extensions are added and managed. The one place
    /// that says where that is, so moving it moves one line.
    package static func openExtensionSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.features))
        appShell()?.openSettingsWindow()
    }

    /// Opens Settings › Menu bar, where the tab's switches are.
    package static func openTabSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration))
        appShell()?.openSettingsWindow()
    }
}
