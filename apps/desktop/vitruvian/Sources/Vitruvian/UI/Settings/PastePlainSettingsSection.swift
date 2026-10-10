// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The Paste as plain text section of Settings › Clipboard. It is a file of
/// its own so that everything in it can be held to the tool's own rules; the
/// page decides whether it shows, and where.
struct PastePlainSettingsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var pastePlain = ToolHost.shared.tool(PastePlainService.self)
    @AppStorage(Preferences.pastePlainEnabled) private var pastePlainEnabled: Bool
    /// Whether Accessibility is granted, as the page that shows this section
    /// observes it.
    let accessibilityGranted: Bool

    var body: some View {
        Section {
            Toggle(l10n.s.pastePlainName, isOn: $pastePlainEnabled)
                .onChange(of: pastePlainEnabled) { _, _ in
                    ToolHost.shared.sync(PastePlainService.self)
                }
            Text(l10n.s.pastePlainCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ShortcutPreferenceRow(role: .pastePlain,
                                  isEnabled: pastePlainEnabled) {
                ToolHost.shared.sync(PastePlainService.self)
            }
            if pastePlainEnabled, pastePlain.shortcutRegistrationFailed {
                Text(l10n.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if pastePlainEnabled, !accessibilityGranted {
                PermissionRow(kind: .accessibility)
            }
        } header: {
            Text(l10n.s.pastePlainName)
        }
        .settingsFormSectionAnchor(.pastePlain)
    }
}
