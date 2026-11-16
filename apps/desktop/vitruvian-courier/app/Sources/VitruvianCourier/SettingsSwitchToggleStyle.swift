// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The on/off switch in Settings: the label on the left, the switch on the right, as in a grouped form.
///
/// macOS draws its own switch grey and white whenever the window is not the one in front, so "on" and "off" look almost
/// alike in a Settings window that has lost focus, or is shown beside another app. This one keeps its colour: "on" is
/// the tint (the theme's accent, set by `SettingsWindow`), "off" a plain grey, in light and dark mode, in front or not.
struct SettingsSwitchToggleStyle: ToggleStyle {
    /// Whether the switch goes to the far side of its row (a form row), or sits next to its label (inside an `HStack`).
    var fillsWidth = true
    /// Whether the label is drawn. When it is not (the row draws its own text), it still names the switch for VoiceOver.
    var showsLabel = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var track: CGSize {
        controlSize == .small || controlSize == .mini ? CGSize(width: 30, height: 18) : CGSize(width: 38, height: 22)
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if showsLabel {
                // The switch below is what VoiceOver reads, named by this label: reading the text too would say it twice.
                configuration.label.accessibilityHidden(true)
            }
            if fillsWidth { Spacer(minLength: 8) }
            switchControl(configuration)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(configuration) }
        // The row is only a container: the switch inside it is the element VoiceOver lands on.
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ configuration: Configuration) {
        guard isEnabled else { return }
        withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
    }

    /// The switch itself. It takes keyboard focus (Tab, with Full Keyboard Access on) and Space presses it, with a focus
    /// ring round the switch. VoiceOver sees the system's own switch here, named by the label, and only the switch.
    private func switchControl(_ configuration: Configuration) -> some View {
        switchView(isOn: configuration.isOn)
            .contentShape(Capsule())
            .focusable(isEnabled)
            .onKeyPress(.space) {
                toggle(configuration)
                return .handled
            }
            .onTapGesture { toggle(configuration) }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .frame(width: track.width, height: track.height)
            }
    }

    private func switchView(isOn: Bool) -> some View {
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
    }
}
