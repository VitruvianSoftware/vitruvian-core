// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The menu bar panel's Extensions tab: each extension's island page, under a
/// small header with its symbol and name, drawn by the same view the island
/// draws it with. The page is the island's page, kept by the panel host, so
/// what the person does here reaches the tool as it does from the island.
///
/// The menu panel builds this only while someone can see it (the popover is
/// up, or the panel is inside the island), so each page is open exactly
/// while it is on screen and the tool is told when it goes.
package struct ExtensionsSection: View {
    @ObservedObject private var l10n = L10n.shared
    /// The store bumps the registry whenever an extension is added, removed,
    /// switched or held back.
    @ObservedObject private var registry = ToolRegistry.shared
    /// Read so a switch flipped in Settings redraws the tab at once.
    @AppStorage(DefaultsKey.panelHiddenExtensions) private var hiddenRaw = ""
    @Environment(\.notchPresentation) private var notchPresentation
    package var collapsible = true

    package init(collapsible: Bool = true) {
        self.collapsible = collapsible
    }

    private var text: MenuPanelExtensionsStrings { FeatureStrings.menuPanelExtensions(l10n.language) }

    package var body: some View {
        _ = (registry.revision, hiddenRaw)
        let available = MenuPanelExtensions.available(store: .shared, language: l10n.language)
        let shown = MenuPanelExtensions.shown(store: .shared, defaults: .standard, language: l10n.language)
        return PanelSection(.extensions, title: text.title, collapsible: collapsible) {
            // With no extension that has a page, the way to add one; with
            // every one switched off here, the way to the switches.
            if available.isEmpty {
                emptyState(line: text.emptyNone, button: text.manage) { MenuPanelExtensions.openExtensionSettings() }
            } else if shown.isEmpty {
                emptyState(line: text.emptyAllOff, button: text.choose) { MenuPanelExtensions.openTabSettings() }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(shown) { entry in
                        MenuPanelExtensionCard(entry: entry, size: notchPresentation ? .island : .standard)
                    }
                }
            }
        }
    }

    private func emptyState(line: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(button) { action() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }
}

/// One extension in the tab: its symbol and name, then its island page. The
/// page is opened when the card appears and let go when it goes; a page the
/// island has open already is shown as it is.
private struct MenuPanelExtensionCard: View {
    let entry: MenuPanelExtensions.Entry
    let size: BlockTreeContent.Size
    @ObservedObject private var host = ToolPanelHost.shared
    /// Set once the card has asked for its page, so a page that is gone
    /// (its tool stopped) reads as not shown rather than as nothing.
    @State private var asked = false
    /// This card's own token with the host: it lets go of its own view of
    /// the page, never another card's.
    @State private var viewer = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Group {
                if host.defersToIsland(entry.key) {
                    // The island holds the one web view; the page comes
                    // back here when the island lets go.
                    ShownInIsland(size: size) { MenuPanelExtensions.showInIsland(entry.key) }
                } else if asked, host.shown[entry.key] == nil {
                    ToolPanelNotShown(size: size)
                } else {
                    ToolPanelView(key: entry.key, size: size)
                }
            }
            // A page drawn for the island's width wraps to the panel's.
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
        .onAppear {
            host.openInMenuPanel(entry.key, viewer: viewer)
            asked = true
        }
        .onDisappear {
            host.closeInMenuPanel(entry.key, viewer: viewer)
            asked = false
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            // The extension's own words: plain text, one line.
            Text(verbatim: entry.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// In place of a web page the Dynamic Island is showing.
private struct ShownInIsland: View {
    let size: BlockTreeContent.Size
    let open: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.menuPanelExtensions(l10n.language)
        VStack(spacing: 8) {
            Text(text.shownInIsland)
                .font(size == .island ? .system(size: 11) : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(text.openInIsland) { open() }
                .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
