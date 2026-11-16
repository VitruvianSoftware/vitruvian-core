// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The on/off switch in Settings: the label on the left, the switch on the right, as in a grouped form.
///
/// macOS draws its own switch grey and white whenever the window is not the one in front, so "on" and "off" look almost
/// alike in a Settings window that has lost focus, or is shown beside another app. This one keeps its colour: "on" is
/// the tint (the theme's accent, set by `SettingsWindow`), "off" a plain grey, in light and dark mode, in front or not.
struct SettingsSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    private var track: CGSize {
        controlSize == .small || controlSize == .mini ? CGSize(width: 30, height: 18) : CGSize(width: 38, height: 22)
    }

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 8)
            switchView(isOn: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        }
        // Spoken, focused and pressed as the system's own switch, so VoiceOver and Full Keyboard Access are unchanged.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
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
