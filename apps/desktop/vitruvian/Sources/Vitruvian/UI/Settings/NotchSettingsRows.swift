// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// Whether one kind of content opens in the island or in a window of its own.
package struct NotchDestinationRow: View {
    private let title: String
    private let symbol: String
    @Binding private var value: Bool
    private let language: AppLanguage
    private let available: Bool

    package init(_ title: String, symbol: String, value: Binding<Bool>, language: AppLanguage,
                 available: Bool = true) {
        self.title = title
        self.symbol = symbol
        _value = value
        self.language = language
        self.available = available
    }

    package var body: some View {
        SettingsChoiceRow(symbol: symbol, title: title, selection: $value) {
            Text(FeatureStrings.notch(language).title).tag(true)
            Text(FeatureStrings.notchEditor(language).separate).tag(false)
        }.disabled(!available)
    }
}

/// The AI agents card's choices, each a row of its own so its layout can be
/// measured on its own.
package enum NotchAgentRows {
    /// Whether a limit reads as what is left or what is used.
    package struct Limits: View {
        private let text: NotchAgentStrings
        @Binding private var limitDisplay: String

        package init(text: NotchAgentStrings, limitDisplay: Binding<String>) {
            self.text = text
            _limitDisplay = limitDisplay
        }

        package var body: some View {
            SettingsChoiceRow(symbol: NotchAgentCard.limits.symbol, title: text.limitsAs, selection: $limitDisplay) {
                Text(text.remaining).tag(NotchAgentLimitDisplay.remaining.rawValue)
                Text(text.used).tag(NotchAgentLimitDisplay.used.rawValue)
            }
        }
    }

    /// Which allowance the resting island shows.
    package struct LimitFocus: View {
        private let text: NotchAgentStrings
        @Binding private var limitFocus: String

        package init(text: NotchAgentStrings, limitFocus: Binding<String>) {
            self.text = text
            _limitFocus = limitFocus
        }

        package var body: some View {
            SettingsMenuRow(symbol: "rectangle.topthird.inset.filled", title: text.limitFocus, selection: $limitFocus) {
                ForEach(NotchAgentLimitFocus.allCases) { focus in
                    Text(text.limitFocus(focus)).tag(focus.rawValue)
                }
            }
        }
    }

    /// What the live activity reads out.
    package struct Readout: View {
        private let text: NotchAgentStrings
        @Binding private var readout: String

        package init(text: NotchAgentStrings, readout: Binding<String>) {
            self.text = text
            _readout = readout
        }

        package var body: some View {
            SettingsMenuRow(symbol: "camera.metering.center.weighted", title: text.readout, selection: $readout) {
                ForEach(NotchAgentReadout.allCases) { option in
                    Text(text.readout(option)).tag(option.rawValue)
                }
            }
        }
    }

    /// How long a run lasts before its finish is announced.
    package struct FinishAfter: View {
        private let text: NotchAgentStrings
        private let locale: Locale
        @Binding private var finishMinimum: TimeInterval

        package init(text: NotchAgentStrings, locale: Locale, finishMinimum: Binding<TimeInterval>) {
            self.text = text
            self.locale = locale
            _finishMinimum = finishMinimum
        }

        package var body: some View {
            SettingsMenuRow(symbol: "timer", title: text.finishAfter, selection: $finishMinimum) {
                ForEach(NotchAgentSupport.finishMinimums, id: \.self) { seconds in
                    Text(seconds == 0 ? text.anyLength : AgentFormat.duration(seconds, locale: locale, style: .short))
                        .tag(seconds)
                }
            }
        }
    }

    /// The share of a limit that raises the alert.
    package struct LimitAt: View {
        private let text: NotchAgentStrings
        @Binding private var limitThreshold: Double

        package init(text: NotchAgentStrings, limitThreshold: Binding<Double>) {
            self.text = text
            _limitThreshold = limitThreshold
        }

        package var body: some View {
            SettingsMenuRow(symbol: "gauge.with.dots.needle.67percent", title: text.limitAt, selection: $limitThreshold) {
                ForEach(NotchAgentSupport.limitThresholds, id: \.self) { value in
                    Text(text.usedShare(AgentFormat.percent(value / 100))).tag(value)
                }
            }
        }
    }

    /// The daily spending the cost reading compares against.
    package struct Budget: View {
        private let text: NotchAgentStrings
        @Binding private var dailyBudget: Double

        package init(text: NotchAgentStrings, dailyBudget: Binding<Double>) {
            self.text = text
            _dailyBudget = dailyBudget
        }

        package var body: some View {
            SettingsMenuRow(symbol: "dollarsign.circle", title: text.budget, selection: $dailyBudget) {
                ForEach(NotchAgentSupport.budgets, id: \.self) { value in
                    Text(value == 0 ? text.off : AgentFormat.cost(value)).tag(value)
                }
            }
        }
    }
}
