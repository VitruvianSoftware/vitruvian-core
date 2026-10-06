// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The list of drives excluded from "Eject all disks".
/// Sits quietly as a single row when empty, shows a count badge,
/// and lets the user quickly pick connected drives or add custom volume names.
package struct DiskExclusionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var protection = DiskProtectionService.shared
    @State private var isExpanded: Bool
    @State private var customDraft = ""
    @State private var showingCustomField = false

    private var strings: DiskExclusionStrings {
        FeatureStrings.diskExclusions(l10n.language)
    }

    package init() {
        _isExpanded = State(initialValue: !(UserDefaults.standard.stringArray(forKey: DefaultsKey.diskEjectExcludedVolumes) ?? []).isEmpty)
    }

    package var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(protection.excludedVolumes, id: \.self) { name in
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        protection.removeExcludedVolume(name)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(strings.removeButton)
                }
            }

            if showingCustomField {
                HStack(spacing: 8) {
                    TextField(strings.customPlaceholder, text: $customDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCustom)
                    Button(strings.addButton) {
                        addCustom()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(customDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(l10n.s.uninstallerCancel) {
                        customDraft = ""
                        showingCustomField = false
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                }
            } else {
                let candidateDrives = mountedCandidateDrives
                if !candidateDrives.isEmpty {
                    Menu {
                        ForEach(candidateDrives, id: \.self) { drive in
                            Button(drive) {
                                protection.addExcludedVolume(drive)
                            }
                        }
                        Divider()
                        Button(strings.otherDrive) {
                            showingCustomField = true
                        }
                    } label: {
                        Label(strings.addButton, systemImage: "plus")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        showingCustomField = true
                    } label: {
                        Label(strings.addButton, systemImage: "plus")
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text(strings.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(strings.listTitle)
                Spacer()
                if !protection.excludedVolumes.isEmpty {
                    Text("\(protection.excludedVolumes.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var mountedCandidateDrives: [String] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(QuickTogglesSupport.volumeKeys),
            options: [.skipHiddenVolumes]) else { return [] }
        return QuickTogglesSupport.exclusionCandidates(
            urls.compactMap(QuickTogglesSupport.Volume.init(mountedAt:)),
            excluded: protection.excludedVolumes)
    }

    private func addCustom() {
        let trimmed = customDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        protection.addExcludedVolume(trimmed)
        customDraft = ""
        showingCustomField = false
    }
}
