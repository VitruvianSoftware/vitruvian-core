// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// A single keyboard key drawn like a physical keycap. Used across Settings and
/// onboarding to show shortcuts such as ⌘X / ⌘V.
package struct KeyCap: View {
    package let label: String

    package var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 20, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
    }
}

/// A row of keycaps for a shortcut, e.g. ["⌘", "X"].
package struct ShortcutCaps: View {
    package let keys: [String]

    package var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(label: key)
            }
        }
    }
}

package struct FullDiskAccessNote: View {
    package var compact = false
    /// Why this surface needs the permission. The scan is the usual reason;
    /// a failed removal has its own, so it says so in its own words.
    package var reason: String?

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared

    package var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: compact ? 7 : 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(reason ?? l10n.s.uninstallerFDANote)
                    .font(compact ? .system(size: 10) : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(l10n.s.uninstallerFDAHint)
                .font(compact ? .system(size: 9) : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: compact ? 7 : 8) {
                Button(l10n.s.uninstallerFDAGrant) { permissions.requestFullDiskAccess() }
                // Shown alongside because access only takes effect on relaunch.
                Button(l10n.s.uninstallerFDARelaunch) { appShell()?.relaunchApp() }
            }
            .controlSize(.small)
            .font(compact ? .system(size: 10.5) : nil)
        }
        // Take the width the host offers, so the card lines up with the cards
        // around it instead of shrinking to its longest line.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 9 : 11)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                .fill(Color.primary.opacity(compact ? 0.045 : 0.05))
        )
    }
}

/// What a removal left behind, and why. Sandboxed app data lives in
/// ~/Library/Containers, which macOS keeps behind Full Disk Access; the
/// administrator prompt Finder shows covers file ownership, not that
/// permission, so those items are refused however the removal is attempted.
/// Naming them at the moment they survive is the only point where the
/// permission has visibly cost the person something.
package struct UninstallFailureNote: View {
    package let items: [AppUninstaller.Leftover]
    package var compact = false

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared

    private static let namesShown = 4

    package var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Text(l10n.s.uninstallerSomeFailed)
                .font(compact ? .system(size: 10) : .caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items.prefix(Self.namesShown)) { item in
                Text(item.name)
                    .font(compact ? .system(size: 9.5) : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if items.count > Self.namesShown {
                Text(String(format: l10n.s.uninstallerFailedMoreFormat,
                            items.count - Self.namesShown))
                    .font(compact ? .system(size: 9.5) : .caption2)
                    .foregroundStyle(.tertiary)
            }
            if !permissions.fullDiskAccess,
               UninstallerSupport.failureNeedsFullDiskAccess(paths: items.map(\.url.path)) {
                FullDiskAccessNote(compact: compact, reason: l10n.s.uninstallerFailedNeedsFDA)
            }
        }
    }
}

/// A disclosure header where the whole row toggles the group and the chevron
/// sits on the trailing side, the way a drop-down reads. The label supplies
/// the row's one Spacer, so trailing accessories stay flush to the chevron.
package struct DisclosureHeaderRow<Label: View>: View {
    @ObservedObject private var l10n = L10n.shared

    private let isExpanded: Binding<Bool>
    private let label: () -> Label

    package init(isExpanded: Binding<Bool>, @ViewBuilder label: @escaping () -> Label) {
        self.isExpanded = isExpanded
        self.label = label
    }

    package var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                label()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded.wrappedValue
            ? l10n.s.disclosureExpanded : l10n.s.disclosureCollapsed)
    }
}

extension View {
    /// Child rows sit inset under their group's header row.
    package func disclosureIndent() -> some View {
        padding(.leading, 25)
    }
}
