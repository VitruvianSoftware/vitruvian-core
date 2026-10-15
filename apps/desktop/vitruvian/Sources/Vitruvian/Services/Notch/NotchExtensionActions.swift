// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore

/// What a quick-access button that opens a tool's island page says, and
/// whether the island shows it. Core cannot see the tools, so the island,
/// its buttons and the layout editor ask here: the title and symbol are
/// the ones the tool's island panel declares, the same as its tile in
/// Explore. Plain values, so the tests check it without a running tool.
package struct NotchExtensionActions: Equatable, Sendable {
    package struct Entry: Equatable, Sendable {
        package let tool: ToolID
        /// The page's title in the person's language, in the tool's words.
        package let title: String
        package let symbol: String
        /// The island lists the page now: the person has not hidden it.
        package let shown: Bool

        package init(tool: ToolID, title: String, symbol: String, shown: Bool) {
            self.tool = tool
            self.title = title
            self.symbol = symbol
            self.shown = shown
        }
    }

    /// Each tool's island page there is to show, in the order the tools
    /// were added.
    package let entries: [Entry]

    /// What a button for a tool with no island page now (switched off,
    /// held back or removed) draws in the layout editor, where it waits.
    package static let fallbackSymbol = "puzzlepiece.extension"

    package init(entries: [Entry]) {
        self.entries = entries
    }

    /// From the store's lists: `available` every island page there is,
    /// `shown` those the island lists; `panel` reads a page's declaration.
    package init(available: [ToolPanelHost.Key], shown: [ToolPanelHost.Key], language: AppLanguage,
                 panel: (ToolPanelHost.Key) -> ToolPanelDescriptor?) {
        let listed = Set(shown)
        entries = available.compactMap { key in
            guard let declared = panel(key) else { return nil }
            return Entry(tool: key.tool, title: declared.title.text(for: language.rawValue) ?? key.panel,
                         symbol: declared.symbol, shown: listed.contains(key))
        }
    }

    /// The tools added to this Mac now.
    @MainActor
    package static func live(language: AppLanguage, store: ExternalToolStore = .shared) -> Self {
        Self(available: store.availableIslandPanels(), shown: store.islandPanels(), language: language) { key in
            store.installed[key.tool]?.tool.panel(key.panel)
        }
    }

    private func entry(_ tool: ToolID) -> Entry? {
        entries.first { $0.tool == tool }
    }

    /// The buttons a chooser offers in "Open a section": one for each
    /// tool's island page there is.
    package var actions: [NotchQuickAction] {
        entries.map { .extensionPanel($0.tool) }
    }

    /// The tools whose page the island lists, for
    /// `NotchQuickAction.isAvailable(in:shownIslandTools:)`.
    package var shownTools: Set<ToolID> {
        Set(entries.filter(\.shown).map(\.tool))
    }

    /// Whether the island shows the button now. A tool's button shows
    /// while the island lists its page; any other asks Core.
    package func isAvailable(_ action: NotchQuickAction, in defaults: UserDefaults = .standard) -> Bool {
        action.isAvailable(in: defaults, shownIslandTools: shownTools)
    }

    /// A tool's button's title: its island page's, else the tool's id for
    /// a page there is no more. Nil for a button of the island's own.
    package func title(_ action: NotchQuickAction) -> String? {
        guard case .extensionPanel(let tool) = action else { return nil }
        return entry(tool)?.title ?? tool.rawValue
    }

    /// A tool's button's SF Symbol: its island page's, else a puzzle
    /// piece. Nil for a button of the island's own.
    package func symbol(_ action: NotchQuickAction) -> String? {
        guard case .extensionPanel(let tool) = action else { return nil }
        return entry(tool)?.symbol ?? Self.fallbackSymbol
    }
}
