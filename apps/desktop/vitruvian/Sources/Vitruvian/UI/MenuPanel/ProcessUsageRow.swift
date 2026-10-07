// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

package struct ProcessUsageRow: View {
    package let row: ProcessUsage
    package let value: String
    package var iconSize: CGFloat = 15
    package var leadingPadding: CGFloat = 0

    @Environment(\.notchPresentation) private var inNotch
    @ObservedObject private var l10n = L10n.shared

    package var body: some View {
        Group {
            if AppFeature.killProcess.isAvailable {
                activatableContent
                    .contextMenu {
                        Button(FeatureStrings.killProcess(l10n.language).forceKillButton,
                               role: .destructive) {
                            confirmForceQuit()
                        }
                        .disabled(!ProcessUsageService.shared.canForceQuit(row))
                    }
            } else {
                activatableContent
            }
        }
        .help(row.name)
    }

    /// Asks before force quitting, above the island when the row is in it.
    /// The service checks the row's identity again once the answer is in.
    private func confirmForceQuit() {
        let service = ProcessUsageService.shared
        guard service.canForceQuit(row), let startedAt = row.startedAt else { return }
        let strings = FeatureStrings.killProcess(L10n.shared.language)
        let title = String(format: strings.confirmForceKillFormat, row.name)
        let cancel = L10n.shared.s.uninstallerCancel
        let row = row
        if inNotch {
            DispatchQueue.main.async {
                guard NSAlert.confirmAboveIsland(title, message: "", action: strings.forceKillButton,
                                                 destructive: true, cancel: cancel) else { return }
                service.forceQuit(row, startedAt: startedAt)
            }
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.addButton(withTitle: strings.forceKillButton).hasDestructiveAction = true
        // Escape cancels in every language, as in the island's confirmation.
        alert.addButton(withTitle: cancel).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        service.forceQuit(row, startedAt: startedAt)
    }

    private var activatableContent: some View {
        Group {
            if ProcessUsageService.shared.canActivate(row) {
                Button {
                    ProcessUsageService.shared.activate(row)
                } label: {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 7) {
            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            Text(row.name)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.leading, leadingPadding)
    }
}
