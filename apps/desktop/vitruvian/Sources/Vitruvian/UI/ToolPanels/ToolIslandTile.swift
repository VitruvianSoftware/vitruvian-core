// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// A tool's island page, as Explore lists it among the island's sections,
/// with the tool's badge. Plain values, so the tests check what the tile
/// says without drawing it.
package struct ToolIslandEntry: Identifiable, Equatable, Sendable {
    package let key: ToolPanelHost.Key
    /// The page's title in the person's language, as the tool wrote it.
    package let title: String
    package let symbol: String
    /// The count on the badge, as it is drawn; nil for none.
    package let count: String?
    /// True for a dot in place of a count.
    package let dot: Bool

    package var id: String { key.tool.rawValue + "/" + key.panel }

    /// The highest count a badge draws; above it, the count and a plus.
    package static let mostCounted = 99

    package init(key: ToolPanelHost.Key, title: String, symbol: String, badge: ToolPanelHost.Badge?) {
        self.key = key
        self.title = title
        self.symbol = symbol
        switch badge {
        case .count(let count)?:
            self.count = count > Self.mostCounted ? "\(Self.mostCounted)+" : "\(count)"
            dot = false
        case .dot?:
            count = nil
            dot = true
        case nil:
            count = nil
            dot = false
        }
    }

    /// The island pages the person shows, in the order the store keeps.
    @MainActor
    package static func all(store: ExternalToolStore, host: ToolPanelHost, language: AppLanguage) -> [ToolIslandEntry] {
        entries(store.islandPanels(), store: store, host: host, language: language)
    }

    /// Every island page there is, including those the person turned off:
    /// what the island's editor offers to show or hide.
    @MainActor
    package static func available(store: ExternalToolStore, host: ToolPanelHost, language: AppLanguage) -> [ToolIslandEntry] {
        entries(store.availableIslandPanels(), store: store, host: host, language: language)
    }

    @MainActor
    private static func entries(_ keys: [ToolPanelHost.Key], store: ExternalToolStore, host: ToolPanelHost,
                                language: AppLanguage) -> [ToolIslandEntry] {
        keys.compactMap { key in
            guard let panel = store.installed[key.tool]?.tool.panel(key.panel) else { return nil }
            return ToolIslandEntry(key: key, title: panel.title.text(for: language.rawValue) ?? key.panel,
                                   symbol: panel.symbol, badge: host.badges[key.tool])
        }
    }
}

/// A tool's island page drawn as one of the island's own sections in
/// Explore: the same tile, size and states as `NotchSectionsView` draws for
/// a module, with the tool's badge on its icon. A tool's page has no
/// keyboard shortcut, so the tile has no shortcut line.
package struct ToolSectionTile: View {
    package let entry: ToolIslandEntry
    /// The page is the one the island has open.
    package let current: Bool
    /// The keyboard's highlight is on it.
    package let highlighted: Bool
    package let open: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    package init(entry: ToolIslandEntry, current: Bool, highlighted: Bool, open: @escaping () -> Void) {
        self.entry = entry
        self.current = current
        self.highlighted = highlighted
        self.open = open
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button(action: open) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: entry.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 25, height: 25)
                    if let count = entry.count {
                        Text(verbatim: count)
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Color.red, in: Capsule())
                            .offset(x: 10, y: -6)
                    } else if entry.dot {
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 4, y: -3)
                    }
                }
                // The tool's own words: plain text, two lines at most.
                Text(verbatim: entry.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(height: 27)
                // Where a module's tile has its shortcut, so the titles line up.
                Color.clear.frame(height: 12)
            }
            .padding(.horizontal, 6)
            .frame(minWidth: 0, idealWidth: NotchLayout.sectionTileWidth, maxWidth: .infinity)
            .frame(height: NotchLayout.sectionTileHeight)
            .background(.white.opacity(highlighted ? 0.12 : 0.045), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(highlighted ? 0.55 : contrast == .increased ? 0.4 : 0.04), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if current {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(7)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 16, lifts: false))
        .accessibilityLabel(Text(verbatim: entry.count.map { "\(entry.title), \($0)" } ?? entry.title))
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("notch.tool.\(entry.key.tool.rawValue)")
        .help(entry.title)
    }
}
