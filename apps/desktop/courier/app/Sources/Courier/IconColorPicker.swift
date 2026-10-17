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

/// A label's look: a row of the 12 colours and a grid of the 24 icons. Click one, or move with the arrow keys once
/// the row or the grid has focus (Tab moves between them).
struct IconColorPicker: View {
    @Binding var color: Int
    @Binding var icon: String

    static let columns = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Colour"))
                .font(.subheadline.weight(.semibold))
            ColorRow(color: $color)
            Text(String(localized: "Icon"))
                .font(.subheadline.weight(.semibold))
            IconGrid(icon: $icon, tint: LabelColor.color(color))
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
