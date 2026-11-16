// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// An on/off switch row in Settings: the label on the left, the switch on the right, and under them an optional
/// footnote. It stands in for `Toggle` in Settings, and is built to be told apart from "off" at a glance.
///
/// - macOS draws its own switch grey and white whenever the window is not the one in front, so "on" and "off" look
///   alike in a Settings window that has lost focus, or is shown beside another app. This one keeps its colour: "on" is
///   the tint (the theme's accent, set by `SettingsWindow`), "off" a plain grey, in light and dark mode, in front or not.
/// - VoiceOver lands on the switch alone, not the row, and reads it by the row's title (and the footnote as its hint).
/// - The switch takes keyboard focus (Tab, with Full Keyboard Access on), shows a focus ring, and Space presses it.
struct SettingsSwitchRow<Label: View>: View {
    @Binding var isOn: Bool
    /// What VoiceOver calls the switch.
    let title: String
    let footnote: String?
    /// Whether the switch goes to the far side of the row (a form row), or sits next to its label (inside an `HStack`).
    let fillsWidth: Bool
    /// Whether the label is drawn. When it is not (the surrounding row draws its own text), `title` still names the switch.
    let showsLabel: Bool
    private let label: Label

    @Namespace private var pairing
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    /// A row with a label of its own making; `title` is what VoiceOver says for it.
    init(
        isOn: Binding<Bool>,
        title: String,
        footnote: String? = nil,
        fillsWidth: Bool = true,
        showsLabel: Bool = true,
        @ViewBuilder label: () -> Label
    ) {
        _isOn = isOn
        self.title = title
        self.footnote = footnote
        self.fillsWidth = fillsWidth
        self.showsLabel = showsLabel
        self.label = label()
    }

    /// The switch's size: regular, or small for `.controlSize(.small)` and `.mini`.
    static var regularSize: CGSize { CGSize(width: 38, height: 22) }
    static var smallSize: CGSize { CGSize(width: 30, height: 18) }

    private var track: CGSize {
        controlSize == .small || controlSize == .mini ? Self.smallSize : Self.regularSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                // The text is the switch's label, as a pair, so VoiceOver reads it once, with the switch. A click on it
                // still turns the switch, as a click on a checkbox's label does. (It stays in the accessibility tree:
                // a Form row with only one element would be reported as that element, as wide as the whole row.)
                HStack(spacing: 0) {
                    if showsLabel { label }
                }
                .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
                .accessibilityLabeledPair(role: .label, id: 0, in: pairing)
                switchControl
            }
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }

    private func toggle() {
        guard isEnabled else { return }
        withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
    }

    private var switchControl: some View {
        let thumb = track.height - 4
        return ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.38)))
            Circle()
                .fill(Color.white)
                .frame(width: thumb, height: thumb)
                .shadow(color: .black.opacity(0.28), radius: 1, y: 0.5)
                .padding(2)
        }
        .frame(width: track.width, height: track.height)
        .opacity(isEnabled ? 1 : 0.45)
        // VoiceOver lands on this element, and only this one: a switch named by the row's title.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
        .accessibilityHint(footnote ?? "")
        .accessibilityAddTraits(.isToggle)
        .accessibilityAction(.default) { toggle() }
        .accessibilityLabeledPair(role: .content, id: 0, in: pairing)
        .contentShape(Capsule())
        .focusable(isEnabled)
        .onKeyPress(.space) {
            toggle()
            return .handled
        }
        .onTapGesture { toggle() }
    }
}

extension SettingsSwitchRow where Label == Text {
    /// The usual row: a title, which is also what VoiceOver says.
    init(
        _ title: String,
        isOn: Binding<Bool>,
        footnote: String? = nil,
        fillsWidth: Bool = true,
        showsLabel: Bool = true
    ) {
        self.init(isOn: isOn, title: title, footnote: footnote, fillsWidth: fillsWidth, showsLabel: showsLabel) {
            Text(title)
        }
    }
}
