// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianAtriumCore
import VitruvianAtriumDesign

/// The step, floor and ceiling the volume keys use on a monitor's speakers,
/// under the Displays page's volume key switch.
package struct MonitorVolumeKeyControls: View {
    package let strings: BrightnessFeatureStrings

    @AppStorage(Preferences.ddcVolumeStep) private var step: Double
    @AppStorage(Preferences.ddcVolumeMinimum) private var minimum: Int
    @AppStorage(Preferences.ddcVolumeMaximum) private var maximum: Int

    // Spelled out because a memberwise initializer never leaves its module.
    package init(strings: BrightnessFeatureStrings) {
        self.strings = strings
    }

    private var settings: MonitorVolumeKeySettings {
        MonitorVolumeKeySettings(stepPercent: step, minimumPercent: minimum, maximumPercent: maximum)
    }

    package var body: some View {
        SettingsRow(symbol: "plusminus", title: strings.speakersStep) {
            Picker(strings.speakersStep, selection: Binding(get: { settings.stepPercent }, set: { step = $0 })) {
                ForEach(MonitorVolumeKeySettings.stepChoices, id: \.self) { choice in
                    if choice == MonitorVolumeKeySettings.defaultStepPercent {
                        Text(strings.speakersStepStandard).tag(choice)
                    } else {
                        Text(choice / 100, format: .percent).tag(choice)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        SettingsRow(symbol: "speaker.fill", title: strings.speakersMinimum, caption: strings.speakersMinimumCaption) {
            limit(strings.speakersMinimum, value: Binding(get: { settings.minimumPercent }, set: { minimum = $0 }),
                  range: 0...(settings.maximumPercent - 1))
        }
        SettingsRow(symbol: "speaker.wave.3.fill", title: strings.speakersMaximum, caption: strings.speakersMaximumCaption) {
            limit(strings.speakersMaximum, value: Binding(get: { settings.maximumPercent }, set: { maximum = $0 }),
                  range: (settings.minimumPercent + 1)...100)
        }
    }

    private func limit(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 6) {
            if range.lowerBound < range.upperBound {
                Slider(value: Binding(get: { Double(value.wrappedValue) }, set: {
                    value.wrappedValue = Int($0.rounded())
                }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .frame(width: 150)
                    .accessibilityLabel(title)
            }
            Text(Double(value.wrappedValue) / 100, format: .percent)
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }
}
