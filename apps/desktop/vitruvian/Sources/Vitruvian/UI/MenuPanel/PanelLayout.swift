// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// A major panel section with a collapsible header. The header row (the section
/// title plus a chevron) toggles a persisted collapsed state; collapsing hides
/// the body but keeps the header so it can be reopened. Every major component in
/// the panel uses this so they all collapse and reorder consistently.
package struct PanelSection<Content: View>: View {
    @ObservedObject private var l10n = L10n.shared
    private let id: PanelSectionID
    private let title: String
    private let collapsible: Bool
    private let supportsEditing: Bool
    private let editButtonVisible: Bool
    private let resetAction: (() -> Void)?
    private let content: (Bool) -> Content
    @State private var collapsed: Bool
    @State private var editing = false

    package init(_ id: PanelSectionID, title: String, collapsible: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.collapsible = collapsible
        self.supportsEditing = false
        self.editButtonVisible = false
        self.resetAction = nil
        self.content = { _ in content() }
        _collapsed = State(initialValue: PanelLayout.isCollapsed(id))
    }

    package init(_ id: PanelSectionID, title: String, collapsible: Bool = true,
         supportsEditing: Bool,
         editButtonVisible: Bool = true,
         resetAction: (() -> Void)? = nil,
         @ViewBuilder content: @escaping (Bool) -> Content) {
        self.id = id
        self.title = title
        self.collapsible = collapsible
        self.supportsEditing = supportsEditing
        self.editButtonVisible = editButtonVisible
        self.resetAction = resetAction
        self.content = content
        _collapsed = State(initialValue: PanelLayout.isCollapsed(id))
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !collapsible || !collapsed {
                content(isEditing)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if collapsible {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        sectionTitle(title)
                        Spacer(minLength: 0)
                        collapseIcon
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                sectionTitle(title)
                Spacer(minLength: 0)
            }
            if supportsEditing {
                if isEditing, let resetAction {
                    resetButton(resetAction)
                        .opacity(editButtonVisible ? 1 : 0)
                        .disabled(!editButtonVisible)
                        .accessibilityHidden(!editButtonVisible)
                }
                editButton
                    .opacity(editButtonVisible ? 1 : 0)
                    .disabled(!editButtonVisible)
                    .accessibilityHidden(!editButtonVisible)
            }
        }
    }

    private var collapseIcon: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(collapsed ? 0 : 90))
    }

    private var editButton: some View {
        Button(action: toggleEditing) {
            if isEditing {
                Label("OK", systemImage: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 18)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEditing ? Color.white : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: isEditing ? 8 : 6, style: .continuous)
                .fill(isEditing ? Color.accentColor : Color.clear)
        )
        .help(isEditing ? l10n.s.uninstallerDoneTitle : l10n.s.menuEdit)
    }

    private func resetButton(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .help(l10n.s.mixerOutputDefault)
    }

    private var isEditing: Bool { supportsEditing && editButtonVisible && editing }

    private func toggleEditing() {
        if collapsed {
            collapsed = false
            PanelLayout.setCollapsed(false, for: id)
        }
        editing.toggle()
    }

    private func toggle() {
        collapsed.toggle()
        PanelLayout.setCollapsed(collapsed, for: id)
    }
}

package struct PanelDragHandle: View {
    package var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: PanelRowMetrics.dragHandleWidth, height: 22)
            .contentShape(Rectangle())
            .help(L10n.shared.s.monitorOrderHint)
    }
}

package struct PanelReorderableItem<Item: PanelOrderItem, Content: View>: View {
    package let item: Item
    package var isEnabled = true
    /// Rows inside a `PanelRowGroup` have no card of their own, so the one
    /// being dragged gets a card for its preview and stays readable over
    /// whatever sits under the pointer.
    package var previewsAsCard = false
    @Binding package var order: [Item]
    @Binding package var dragging: Item?
    package let content: () -> Content

    package var body: some View {
        if isEnabled {
            draggableContent
                .onDrop(of: [UTType.text], delegate: PanelItemDropDelegate(item: item,
                                                                           order: $order,
                                                                           dragging: $dragging))
        } else {
            content()
        }
    }

    @ViewBuilder
    private var draggableContent: some View {
        if previewsAsCard {
            content()
                .onDrag(itemProvider) {
                    content()
                        .frame(minWidth: 220, alignment: .leading)
                        .panelCard(interactive: false, padded: false)
                }
        } else {
            content()
                .onDrag(itemProvider)
        }
    }

    private func itemProvider() -> NSItemProvider {
        dragging = item
        return NSItemProvider(object: item.rawValue as NSString)
    }
}

private struct PanelItemDropDelegate<Item: PanelOrderItem>: DropDelegate {
    let item: Item
    @Binding var order: [Item]
    @Binding var dragging: Item?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: item) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

package struct PanelInlineHideButton: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding package var isVisible: Bool

    package var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isVisible ? Color.secondary : Color.accentColor)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill((isVisible ? Color.primary : Color.accentColor).opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(isVisible ? l10n.s.panelHideItem : l10n.s.panelShowItem)
        .accessibilityLabel(isVisible ? l10n.s.panelHideItem : l10n.s.panelShowItem)
    }
}

package struct PanelHiddenBadge: View {
    @ObservedObject private var l10n = L10n.shared

    package var body: some View {
        Label(l10n.s.panelHiddenItem, systemImage: "eye.slash.fill")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
    }
}

package struct PanelHiddenItemRow: View {
    package let title: String
    package let systemImage: String
    @Binding package var isVisible: Bool

    package var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            PanelHiddenBadge()
            PanelInlineHideButton(isVisible: $isVisible)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }
}
