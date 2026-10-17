// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The menu bar panel's Extensions tab: each extension's island page, under a
/// collapsible header with its symbol and name, drawn by the same view the
/// island draws it with. The page is the island's page, kept by the panel
/// host, so what the person does here reaches the tool as it does from the
/// island. Its edit mode reorders and hides extensions in place.
///
/// The menu panel builds this only while someone can see it (the popover is
/// up, or the panel is inside the island), so each page is open exactly
/// while it is on screen and expanded, and the tool is told when it goes.
package struct ExtensionsSection: View {
    @ObservedObject private var l10n = L10n.shared
    /// The store bumps the registry whenever an extension is added, removed,
    /// switched or held back.
    @ObservedObject private var registry = ToolRegistry.shared
    /// Read so a change to visibility, order or collapsed state redraws the
    /// tab at once.
    @AppStorage(DefaultsKey.panelHiddenExtensions) private var hiddenRaw = ""
    @AppStorage(DefaultsKey.panelExtensionOrder) private var orderRaw = ""
    @AppStorage(DefaultsKey.panelCollapsedExtensions) private var collapsedRaw = ""
    @Environment(\.notchPresentation) private var notchPresentation
    @State private var editing = false
    @State private var draggingItem: ExtensionOrderItem?
    package var collapsible = true

    package init(collapsible: Bool = true) {
        self.collapsible = collapsible
    }

    private var text: MenuPanelExtensionsStrings { FeatureStrings.menuPanelExtensions(l10n.language) }

    package var body: some View {
        _ = (registry.revision, hiddenRaw, orderRaw, collapsedRaw)
        let ordered = MenuPanelExtensions.ordered(store: .shared, defaults: .standard, language: l10n.language)
        let shown = MenuPanelExtensions.shown(store: .shared, defaults: .standard, language: l10n.language)
        return PanelSection(.extensions, title: text.title, collapsible: collapsible,
                            supportsEditing: true,
                            editButtonVisible: !ordered.isEmpty,
                            isEditing: $editing,
                            resetAction: { MenuPanelExtensionsSupport.reset(in: .standard) }) { isEditing in
            // With no extension that has a page, the way to add one; in edit
            // mode, every extension to reorder and show or hide; with every
            // one hidden, the way into edit mode.
            if ordered.isEmpty {
                emptyState(line: text.emptyNone, button: text.manage) { MenuPanelExtensions.openExtensionSettings() }
            } else if isEditing {
                editorList(ordered)
            } else if shown.isEmpty {
                emptyState(line: text.emptyAllOff, button: text.choose) { editing = true }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(shown) { entry in
                        MenuPanelExtensionCard(
                            entry: entry,
                            collapsed: MenuPanelExtensionsSupport.isCollapsed(entry.key.tool, in: .standard),
                            size: notchPresentation ? .island : .standard
                        )
                    }
                }
            }
        }
    }

    private func editorList(_ entries: [MenuPanelExtensions.Entry]) -> some View {
        let orderBinding = Binding<[ExtensionOrderItem]>(
            get: { entries.map { ExtensionOrderItem(tool: $0.key.tool) } },
            set: { MenuPanelExtensionsSupport.setOrder($0.map(\.tool), in: .standard) }
        )
        return PanelRowGroup(items: entries, showsDragHandles: true) { entry in
            PanelReorderableItem(item: ExtensionOrderItem(tool: entry.key.tool),
                                 isEnabled: true,
                                 previewsAsCard: true,
                                 order: orderBinding,
                                 dragging: $draggingItem) {
                editorRow(entry)
            }
        }
    }

    private func editorRow(_ entry: MenuPanelExtensions.Entry) -> some View {
        let isVisible = MenuPanelExtensionsSupport.isShown(entry.key.tool, in: .standard)
        let visibility = Binding<Bool>(
            get: { MenuPanelExtensionsSupport.isShown(entry.key.tool, in: .standard) },
            set: { MenuPanelExtensionsSupport.setShown($0, for: entry.key.tool, in: .standard) }
        )
        return HStack(spacing: PanelRowMetrics.iconSpacing) {
            PanelDragHandle()
            Image(systemName: entry.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isVisible ? Color.accentColor : Color.secondary)
                .frame(width: PanelRowMetrics.iconWidth)
                .accessibilityHidden(true)
            // The extension's own words: plain text, one line.
            Text(verbatim: entry.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isVisible ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if !isVisible {
                PanelHiddenBadge()
            }
            PanelInlineHideButton(isVisible: visibility)
        }
        .panelRowInsets()
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

private struct ExtensionOrderItem: PanelOrderItem {
    let tool: ToolID

    var rawValue: String { tool.rawValue }

    init(tool: ToolID) {
        self.tool = tool
    }

    init?(rawValue: String) {
        guard let tool = ToolID(rawValue) else { return nil }
        self.tool = tool
    }
}

/// One extension in the tab: a collapsible header with its symbol and name,
/// then its island page while expanded. The page is opened when expanded and
/// let go when collapsed or when the card goes; a page the island has open
/// already is shown as it is.
private struct MenuPanelExtensionCard: View {
    let entry: MenuPanelExtensions.Entry
    let collapsed: Bool
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
            if !collapsed {
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
                .onAppear {
                    host.openInMenuPanel(entry.key, viewer: viewer)
                    asked = true
                }
                .onDisappear {
                    host.closeInMenuPanel(entry.key, viewer: viewer)
                    asked = false
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard()
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                MenuPanelExtensionsSupport.setCollapsed(!collapsed, for: entry.key.tool, in: .standard)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .frame(width: 10)
                    .accessibilityHidden(true)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
