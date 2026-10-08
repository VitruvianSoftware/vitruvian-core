// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

package enum NotchSettingsTab: CaseIterable {
    case layout, content, activity, behavior, companion
}

/// The Dynamic Island page's tabs, with the button that opens the island.
/// Four tab names can need more room than the narrowest window leaves the
/// page in longer languages, and a page wider than its column is centered and
/// cut on both sides, under the sidebar. The segments give way to a menu
/// whenever they don't fit beside the button.
package struct NotchSettingsTabRow: View {
    @Binding package var tab: NotchSettingsTab
    package let language: AppLanguage
    /// The companion's tab, once it is installed.
    package var showsCompanion = false
    package let canOpen: Bool
    package let open: () -> Void

    package var body: some View {
        let text = FeatureStrings.notch(language)
        HStack {
            ViewThatFits(in: .horizontal) {
                picker.pickerStyle(.segmented)
                picker.pickerStyle(.menu)
            }
            Button(action: open) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.bordered).disabled(!canOpen).help(text.open).accessibilityLabel(text.open)
        }
    }

    private var picker: some View {
        let editor = FeatureStrings.notchEditor(language)
        return Picker(FeatureStrings.notch(language).title, selection: $tab) {
            Text(editor.layout).tag(NotchSettingsTab.layout)
            Text(editor.content).tag(NotchSettingsTab.content)
            Text(editor.activity).tag(NotchSettingsTab.activity)
            Text(editor.behavior).tag(NotchSettingsTab.behavior)
            if showsCompanion {
                Text(FeatureStrings.notchMascot(language).title).tag(NotchSettingsTab.companion)
            }
        }
        .labelsHidden()
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(tab: Binding<NotchSettingsTab>, language: AppLanguage, showsCompanion: Bool = false,
                 canOpen: Bool, open: @escaping () -> Void) {
        self._tab = tab
        self.language = language
        self.showsCompanion = showsCompanion
        self.canOpen = canOpen
        self.open = open
    }
}
