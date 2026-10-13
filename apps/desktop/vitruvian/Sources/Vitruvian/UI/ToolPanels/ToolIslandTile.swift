// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianToolProtocol

/// A tool's page, as the island's Tools area lists it: a tile after the
/// quick tools, with the tool's badge. Plain values, so the tests check
/// what the tile says without drawing it.
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

    /// The island pages the Tools area lists, in the order the store keeps.
    @MainActor
    package static func all(store: ExternalToolStore, host: ToolPanelHost, language: AppLanguage) -> [ToolIslandEntry] {
        store.islandPanels().compactMap { key in
            guard let panel = store.installed[key.tool]?.tool.panel(key.panel) else { return nil }
            return ToolIslandEntry(key: key, title: panel.title.text(for: language.rawValue) ?? key.panel,
                                   symbol: panel.symbol, badge: host.badges[key.tool])
        }
    }
}

/// One tool's page in the island's Tools area: its icon and title, as a
/// quick tool's tile is drawn there, and its badge where a quick tool shows
/// that it is on. Clicking it opens the page.
package struct ToolIslandTile: View {
    package let entry: ToolIslandEntry
    package let open: () -> Void
    @State private var hovering = false

    package init(entry: ToolIslandEntry, open: @escaping () -> Void) {
        self.entry = entry
        self.open = open
    }

    package var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.16 : 0.1))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: entry.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                    if let count = entry.count {
                        Text(verbatim: count)
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Color.red, in: Capsule())
                            .offset(x: 6, y: -5)
                    } else if entry.dot {
                        Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: 3, y: -3)
                    }
                }
                // The tool's own words: plain text, two lines at most.
                Text(verbatim: entry.title)
                    .font(.system(size: 10, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(verbatim: entry.count.map { "\(entry.title), \($0)" } ?? entry.title))
    }
}

/// A tile of the island's Tools area: a quick tool, or a tool's page.
package enum ToolsRailItem: Identifiable, Equatable {
    case tile(QuickLauncherTile)
    case page(ToolIslandEntry)

    package var id: String {
        switch self {
        case .tile(let tile): return "tile:" + tile.id
        case .page(let entry): return "page:" + entry.id
        }
    }
}
