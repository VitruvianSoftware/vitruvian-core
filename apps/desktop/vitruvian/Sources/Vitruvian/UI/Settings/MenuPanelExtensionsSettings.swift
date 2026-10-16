// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// Settings › Menu bar, under the panel's tabs: one switch per extension
/// with an island page, deciding whether the Extensions tab shows it. On
/// until the person turns it off. Drawn only while some extension has an
/// island page; the tab's own switch is its row in the list above.
package struct MenuPanelExtensionsSettings: View {
    @ObservedObject private var l10n = L10n.shared
    /// The store bumps the registry whenever an extension is added, removed,
    /// switched or held back.
    @ObservedObject private var registry = ToolRegistry.shared
    /// Read so each switch redraws as soon as it is saved.
    @AppStorage(DefaultsKey.panelHiddenExtensions) private var hiddenRaw = ""

    package init() {}

    private var text: MenuPanelExtensionsStrings { FeatureStrings.menuPanelExtensions(l10n.language) }

    package var body: some View {
        _ = (registry.revision, hiddenRaw)
        let entries = MenuPanelExtensions.available(store: .shared, language: l10n.language)
        return Group {
            if !entries.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRow(symbol: nil, title: text.settingsTitle, caption: text.settingsCaption) {
                        EmptyView()
                    }
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                            if entry.id != entries.last?.id {
                                Divider().padding(.leading, 26)
                            }
                        }
                    }
                    .padding(.leading, settingsRowTextInset)
                }
            }
        }
    }

    private func row(_ entry: MenuPanelExtensions.Entry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            // The extension's own words: plain text, one line.
            Text(verbatim: entry.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Toggle(entry.name, isOn: Binding(
                get: { MenuPanelExtensionsSupport.isShown(entry.key.tool, in: .standard) },
                set: { MenuPanelExtensionsSupport.setShown($0, for: entry.key.tool, in: .standard) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 5)
    }
}
