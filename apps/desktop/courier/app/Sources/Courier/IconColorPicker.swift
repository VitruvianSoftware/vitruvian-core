// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// A label's colours: the system colours, in LabelsModel.colors' order. The engine keeps the index.
enum LabelColor {
    static func color(_ index: Int) -> Color {
        switch index {
        case 0: .red
        case 1: .orange
        case 2: .yellow
        case 3: .green
        case 4: .mint
        case 5: .teal
        case 6: .cyan
        case 7: .blue
        case 8: .indigo
        case 9: .purple
        case 10: .pink
        case 11: .brown
        default: .gray
        }
    }

    /// The colour's name, for VoiceOver and the tooltip.
    static func name(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "Red")
        case 1: String(localized: "Orange")
        case 2: String(localized: "Yellow")
        case 3: String(localized: "Green")
        case 4: String(localized: "Mint")
        case 5: String(localized: "Teal")
        case 6: String(localized: "Cyan")
        case 7: String(localized: "Blue")
        case 8: String(localized: "Indigo")
        case 9: String(localized: "Purple")
        case 10: String(localized: "Pink")
        case 11: String(localized: "Brown")
        default: String(localized: "Grey")
        }
    }
}

/// A label's look: a row of the 12 colours, a quick-pick grid of the default icons, and an expandable searchable
/// catalog of all 151 §22 icons (`CourierIconCatalog`).
public struct IconColorPicker: View {
    @Binding public var color: Int
    @Binding public var icon: String
    @State private var showsCatalog: Bool
    @State private var searchQuery: String
    @State private var selectedCategory: CourierIconCategory

    static let columns = 8

    public init(
        color: Binding<Int>,
        icon: Binding<String>,
        showsAllIconsInitially: Bool = false,
        initialSearchQuery: String = "",
        initialCategory: CourierIconCategory = .all
    ) {
        self._color = color
        self._icon = icon
        self._showsCatalog = State(initialValue: showsAllIconsInitially)
        self._searchQuery = State(initialValue: initialSearchQuery)
        self._selectedCategory = State(initialValue: initialCategory)
    }

    private var filteredCatalogIcons: [CourierIconEntry] {
        CourierIconCatalog.search(query: searchQuery, category: selectedCategory)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Colour"))
                .font(.subheadline.weight(.semibold))
            ColorRow(color: $color)

            HStack {
                Text(String(localized: "Icon"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showsCatalog.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(String(localized: "All Icons (\(CourierIconCatalog.labelAndSpaceIcons.count))…"))
                            .font(.caption.weight(.medium))
                        Image(systemName: showsCatalog ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(String(localized: "All Icons"))
            }

            IconGrid(icon: $icon, tint: LabelColor.color(color))

            if showsCatalog {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField(String(localized: "Search icons…"), text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.callout)
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Clear icon search"))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(CourierIconCategory.allCases) { category in
                                Button {
                                    selectedCategory = category
                                } label: {
                                    Text(category.title)
                                        .font(.caption2.weight(selectedCategory == category ? .semibold : .regular))
                                        .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule().fill(
                                                selectedCategory == category
                                                    ? LabelColor.color(color)
                                                    : Color.primary.opacity(0.08)
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    let entries = filteredCatalogIcons
                    if entries.isEmpty {
                        Text(String(localized: "No matching icons"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: Self.columns),
                                alignment: .leading,
                                spacing: 6
                            ) {
                                ForEach(entries) { entry in
                                    let isSelected = entry.sfSymbol == icon
                                    Image(systemName: entry.sfSymbol)
                                        .font(.system(size: 15))
                                        .frame(width: 34, height: 34)
                                        .foregroundStyle(isSelected ? Color.white : LabelColor.color(color))
                                        .background(
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(isSelected ? LabelColor.color(color) : Color.primary.opacity(0.06))
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture { icon = entry.sfSymbol }
                                        .help(entry.title)
                                        .accessibilityLabel(entry.title)
                                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                                }
                            }
                            .padding(4)
                        }
                        .frame(maxHeight: 164)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
            }
        }
    }
}

private struct ColorRow: View {
    @Binding var color: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(LabelsModel.colors), id: \.self) { index in
                Circle()
                    .fill(LabelColor.color(index))
                    .frame(width: 22, height: 22)
                    .overlay {
                        if index == color {
                            Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4)
                        }
                    }
                    .padding(4)
                    .contentShape(Circle())
                    .onTapGesture { color = index }
                    .help(LabelColor.name(index))
                    .accessibilityLabel(LabelColor.name(index))
                    .accessibilityAddTraits(index == color ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0))
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Colour"))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        color = min(max(color + step, LabelsModel.colors.lowerBound), LabelsModel.colors.upperBound - 1)
        return .handled
    }
}

private struct IconGrid: View {
    @Binding var icon: String
    let tint: Color
    @FocusState private var focused: Bool

    private var index: Int { LabelsModel.icons.firstIndex(of: icon) ?? 0 }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: IconColorPicker.columns),
                  alignment: .leading, spacing: 6) {
            ForEach(Array(LabelsModel.icons.enumerated()), id: \.element) { number, name in
                Image(systemName: name)
                    .font(.system(size: 15))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(name == icon ? Color.white : tint)
                    .background(RoundedRectangle(cornerRadius: 7).fill(name == icon ? tint : Color.primary.opacity(0.06)))
                    .contentShape(Rectangle())
                    .onTapGesture { icon = name }
                    .accessibilityLabel(String(localized: "Icon \(number + 1)"))
                    .accessibilityAddTraits(name == icon ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0))
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-IconColorPicker.columns) }
        .onKeyPress(.downArrow) { move(IconColorPicker.columns) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Icon"))
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let next = index + step
        guard LabelsModel.icons.indices.contains(next) else { return .handled }
        icon = LabelsModel.icons[next]
        return .handled
    }
}
