// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// An in-place destination gallery of the island's own pages and tools'
/// island pages. It only observes navigation, never the contents or
/// services of the sections represented by its buttons; of a tool's page it
/// reads only the title, symbol and badge its tile shows.
///
/// Rows step in whole, so the grid always rests on a row boundary; a dot per
/// resting position shows where it is and that more rows follow. Rows that
/// have stepped away keep their place for the motion but take no clicks.
///
/// Customizing swaps the gallery for the Tools editor's grid: every section
/// showing, to drag into order or hide, with no scroll view, since a drag
/// needs every target in view and Explore keeps the wheel; the hidden ones
/// wait below to be shown again.
package struct NotchSectionsView: View {
    @ObservedObject package var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    /// Tools' badges, and their pages coming and going.
    @ObservedObject private var panels = ToolPanelHost.shared
    @ObservedObject private var registry = ToolRegistry.shared
    @State private var dragging: NotchSectionItem?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var sections: [NotchSectionItem] { service.filteredSectionItems }
    private static let pitch = NotchLayout.sectionTileHeight + NotchLayout.sectionSpacing

    /// What each tool's tile shows: its words, symbol and badge.
    private var toolEntries: [ToolID: ToolIslandEntry] {
        Dictionary(ToolIslandEntry.available(store: .shared, host: panels, language: l10n.language).map { ($0.key.tool, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    package var body: some View {
        Group {
            if service.editingSections {
                editor
            } else if sections.isEmpty {
                NotchEmptyView(symbol: "magnifyingglass", message: FeatureStrings.clipboard(l10n.language).noResults)
            } else {
                gallery
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: sections) { _, visible in
            if !visible.contains(where: { $0 == service.highlightedSection }) {
                service.highlightedSection = visible.first
            }
        }
    }

    private var gallery: some View {
        let entries = toolEntries
        let columns = service.geometry.sectionColumns
        let rows = NotchSectionPaging.rows(count: sections.count, columns: columns)
        let visible = service.geometry.sectionRows(count: sections.count)
        let positions = NotchSectionPaging.positions(rows: rows, visible: visible)
        let first = NotchSectionPaging.clamped(service.sectionRow, rows: rows, visible: visible)
        let shown = first..<(first + visible)
        return HStack(spacing: 0) {
            VStack(spacing: NotchLayout.sectionSpacing) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: NotchLayout.sectionSpacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < sections.count {
                                tile(sections[index], entries: entries, visible: shown.contains(row))
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: NotchLayout.sectionTileHeight)
                            }
                        }
                    }
                    .allowsHitTesting(shown.contains(row))
                    .accessibilityHidden(!shown.contains(row))
                }
            }
            .offset(y: -CGFloat(first) * Self.pitch)
            .frame(height: NotchLayout.railHeight(rows: visible, rowHeight: NotchLayout.sectionTileHeight,
                                                  spacing: NotchLayout.sectionSpacing), alignment: .top)
            .clipped()
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: first)
            .accessibilityScrollAction { edge in
                if edge == .bottom { service.scrollSections(by: 1) }
                else if edge == .top { service.scrollSections(by: -1) }
            }
            indicator(positions: positions, current: first)
                .frame(width: NotchLayout.sectionIndicatorWidth, alignment: .trailing)
        }
        .accessibilityHint(text.sectionKeyboardHint)
    }

    /// One dot per resting position, the current one lit. Clicking a dot
    /// rests the gallery there; the wheel and the arrow keys step rows. The
    /// column keeps its width when everything fits, so tiles never shift.
    @ViewBuilder private func indicator(positions: Int, current: Int) -> some View {
        if positions > 1 {
            VStack(spacing: 5) {
                ForEach(0..<positions, id: \.self) { position in
                    Button { service.showSectionRow(position) } label: {
                        Circle()
                            .fill(.white.opacity(position == current ? 0.9 : contrast == .increased ? 0.5 : 0.28))
                            .frame(width: 6, height: 6)
                            .frame(width: 12, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: current)
            .accessibilityHidden(true)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func tile(_ item: NotchSectionItem, entries: [ToolID: ToolIslandEntry], visible: Bool) -> some View {
        switch item {
        case .module(let module):
            tile(module, visible: visible)
        case .tool(let tool):
            if let entry = entries[tool] {
                ToolSectionTile(entry: entry, current: service.currentSection == item,
                                highlighted: service.highlightedSection == item) { service.selectSection(item) }
            } else {
                Color.clear.frame(maxWidth: .infinity).frame(height: NotchLayout.sectionTileHeight)
            }
        }
    }

    private func tile(_ module: NotchModule, visible: Bool) -> some View {
        let highlighted = service.highlightedSection == .module(module)
        let current = service.currentSection == .module(module)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { service.selectSection(.module(module)) } label: {
            VStack(spacing: 6) {
                Image(systemName: module.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint(for: module))
                    .frame(width: 25, height: 25)
                Text(module.title(l10n.language))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(height: 27)
                Text("⌥⌘" + module.shortcutKey.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
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
        .accessibilityLabel(module.title(l10n.language))
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("notch.module.\(module.rawValue)")
        // A stepped-away row sits under the header, clipped; it keeps no
        // tooltip there.
        .help(visible ? module.title(l10n.language) + "  ⌥⌘" + module.shortcutKey.uppercased() : "")
    }

    // MARK: Customizing

    /// The Tools page's columns: as many tiles as its width holds.
    private var editorColumns: [GridItem] {
        let count = NotchLayout.railCapacity(width: service.geometry.contentWidth, itemWidth: NotchLayout.toolWidth,
                                             spacing: NotchLayout.toolSpacing)
        return Array(repeating: GridItem(.flexible(), spacing: NotchLayout.toolSpacing), count: max(1, count))
    }

    private var order: Binding<[NotchSectionItem]> {
        Binding {
            service.sections
        } set: {
            service.saveSectionOrder($0, installedTools: Set(ExternalToolStore.shared.listed.map(\.id)))
        }
    }

    private var editor: some View {
        let entries = toolEntries
        let showing = service.sections
        let hidden = service.availableSectionItems.filter { !showing.contains($0) }
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: editorColumns, spacing: NotchLayout.toolSpacing) {
                ForEach(showing) { item in
                    PanelReorderableItem(item: item, order: order, dragging: $dragging) {
                        // The last section keeps its place: hiding it would
                        // leave Explore with nothing to open.
                        editorTile(item, entry: toolID(item).flatMap { entries[$0] }, hides: showing.count > 1)
                    }
                }
            }
            if !hidden.isEmpty {
                Divider().overlay(.white.opacity(0.12))
                hiddenTray(hidden, entries: entries)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.customizeSections)
    }

    private func toolID(_ item: NotchSectionItem) -> ToolID? {
        if case .tool(let tool) = item { return tool }
        return nil
    }

    private func title(_ item: NotchSectionItem, entry: ToolIslandEntry?) -> String {
        entry?.title ?? service.sectionTitle(item)
    }

    private func symbol(_ item: NotchSectionItem, entry: ToolIslandEntry?) -> String {
        switch item {
        case .module(let module): return module.symbol
        case .tool: return entry?.symbol ?? "square.grid.2x2"
        }
    }

    /// A section as the Tools editor draws a tool: its icon with the hide
    /// button on its corner, and its title.
    private func editorTile(_ item: NotchSectionItem, entry: ToolIslandEntry?, hides: Bool) -> some View {
        let name = title(item, entry: entry)
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: symbol(item, entry: entry))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tint(for: item))
                    )
                if hides {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { service.setSectionShown(item, false) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white, Color.red)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 7, y: -7)
                    .help(text.hideSection)
                    .accessibilityLabel(Text(verbatim: "\(text.hideSection), \(name)"))
                }
            }
            // A tool's title is its own words.
            Text(verbatim: name)
                .font(.system(size: 10, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: NotchLayout.toolHeight)
        .contentShape(Rectangle())
    }

    /// The sections not showing, each one click from coming back.
    private func hiddenTray(_ hidden: [NotchSectionItem], entries: [ToolID: ToolIslandEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.hiddenSections.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            FlowLayoutLite(spacing: 6) {
                ForEach(hidden) { item in
                    let name = title(item, entry: toolID(item).flatMap { entries[$0] })
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { service.setSectionShown(item, true) }
                    } label: {
                        Label(name, systemImage: "plus.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule(style: .continuous).fill(.black))
                    }
                    .buttonStyle(.plain)
                    .help(text.showSection)
                    .accessibilityLabel(Text(verbatim: "\(text.showSection), \(name)"))
                }
            }
        }
    }

    private func tint(for item: NotchSectionItem) -> Color {
        if case .module(let module) = item { return tint(for: module) }
        return .white.opacity(0.85)
    }

    private func tint(for module: NotchModule) -> Color {
        switch module {
        case .music: return .pink
        case .calendar: return .red
        case .timer: return .orange
        default: return .white.opacity(0.85)
        }
    }
}

/// The gallery's search lives in the header as a magnifier: the field
/// unfolds under the pointer or as soon as something is typed, since the
/// keyboard already goes to it while the gallery is open.
package struct NotchSectionSearch: View {
    @ObservedObject package var service: NotchService
    /// Infinite fills the room its parent gives it, up to the camera.
    package var maximumFieldWidth: CGFloat = 150
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var searching: Bool
    @State private var hovered = false
    @State private var fieldWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var expanded: Bool { hovered || !service.sectionQuery.isEmpty }

    /// The whole prompt where it fits, otherwise the plain word, and no
    /// prompt where even that would be cut, so the placeholder never ends
    /// in a letter cut in half. The magnifier and the accessibility label
    /// still say what the field is for.
    private var prompt: String {
        let font = NSFont.systemFont(ofSize: 12)
        // The field's text sits a few points inside its frame.
        func fits(_ prompt: String) -> Bool {
            (prompt as NSString).size(withAttributes: [.font: font]).width + 6 <= fieldWidth
        }
        if fits(text.searchSections) { return text.searchSections }
        return fits(l10n.s.actionSearch) ? l10n.s.actionSearch : ""
    }

    package var body: some View {
        HStack(spacing: expanded ? 4 : 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(expanded ? .white : .white.opacity(0.55))
                .frame(width: expanded ? 22 : 28, height: 28)
            // The field keeps its focus at a hair's width, so typing filters
            // the gallery before the field has even shown itself.
            TextField(prompt, text: Binding(get: { service.sectionQuery }, set: { service.searchSections($0) }))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searching)
                .frame(maxWidth: expanded ? maximumFieldWidth : 1)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fieldWidth = $0 }
                .opacity(expanded ? 1 : 0)
                .accessibilityLabel(text.searchSections)
            if !service.sectionQuery.isEmpty {
                Button { service.searchSections(""); searching = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.actionClear)
            }
        }
        .padding(.trailing, expanded ? 8 : 0)
        .frame(height: 28)
        .background(.white.opacity(expanded ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .clipped()
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovered = hovering }
        }
        .onTapGesture { searching = true }
        .onAppear { searching = true }
        .help(text.searchSections)
    }
}
