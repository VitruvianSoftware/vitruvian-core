// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

// MARK: - Merged Chat Editor Sheet (Task 11)

/// Modal sheet for creating or editing a merged chat (`merge.create`, `merge.update`, `merge.delete`, `merge.suggest`).
///
/// Displays automatic suggestions (`merge.suggest`, e.g. 1:1 chats sharing a phone number or exact display name across
/// networks), a merged display name field, a searchable checklist of 1:1 chats (`>= 2` required), and an **Unmerge**
/// button when editing an existing merge.
public struct MergedChatEditorSheet: View {
    @State private var draft: MergedChatEditorDraft
    public var onSave: (MergedChatEditorDraft) -> Void
    public var onUnmerge: (String) -> Void
    public var onCancel: () -> Void

    public init(
        draft: MergedChatEditorDraft,
        onSave: @escaping (MergedChatEditorDraft) -> Void = { _ in },
        onUnmerge: @escaping (String) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onUnmerge = onUnmerge
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            if !draft.suggestions.isEmpty {
                suggestionsSection
            }

            nameFieldSection

            searchFieldSection

            if let errorMessage = draft.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            directRoomsListSection

            Divider()

            footerSection
        }
        .padding(16)
        .frame(width: 480)
        .frame(minHeight: 420)
    }

    private var headerSection: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    draft.existingMerge == nil
                        ? String(localized: "Merge Chats")
                        : String(localized: "Edit Merged Chat")
                )
                .font(.headline)
                Text(String(localized: "Combine 1:1 chats with the same person across networks into one unified view."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Suggested Merges"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(draft.suggestions, id: \.self) { suggestion in
                HStack(spacing: 8) {
                    HStack(spacing: -4) {
                        ForEach(Array(suggestion.networks.prefix(3).enumerated()), id: \.offset) { _, net in
                            NetworkBadge(
                                network: net,
                                name: NetworkNames.displayName(of: net) ?? net,
                                size: 15
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(suggestion.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button(String(localized: "Use Suggestion")) {
                        draft.applySuggestion(suggestion)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.10)))
            }
        }
    }

    private var nameFieldSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Merged Chat Name"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Display name (e.g. Alice Example)"), text: $draft.name)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var searchFieldSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(String(localized: "Filter 1:1 chats…"), text: $draft.searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }

    private var directRoomsListSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                let rooms = draft.filteredDirectRooms
                if rooms.isEmpty {
                    Text(String(localized: "No 1:1 chats match that filter"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ForEach(rooms, id: \.roomID) { row in
                        let isSelected = draft.selectedRoomIDs.contains(row.roomID)
                        let networkName = NetworkNames.displayName(of: row.network) ?? row.network
                        Button {
                            draft.toggleRoom(row)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack(alignment: .bottomTrailing) {
                                    AvatarView(
                                        path: row.avatarValue,
                                        initials: Self.initials(of: row.name),
                                        seed: row.name
                                    )
                                    .frame(width: 30, height: 30)
                                    NetworkBadge(network: row.network, name: networkName, size: 13)
                                        .offset(x: 2, y: 2)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.name)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(networkName)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if !row.loginName.isEmpty {
                                            Text("· \(row.loginName)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                Spacer(minLength: 4)

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                    .font(.body)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack {
            if let existing = draft.existingMerge {
                Button(String(localized: "Unmerge"), role: .destructive) {
                    onUnmerge(existing.mergeID)
                }
                .disabled(draft.isSubmitting)
            } else {
                Text(
                    draft.selectedRoomIDs.count == 1
                        ? String(localized: "1 chat selected (pick at least 2)")
                        : String(localized: "\(draft.selectedRoomIDs.count) chats selected")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(
                draft.existingMerge == nil
                    ? String(localized: "Merge Chats")
                    : String(localized: "Save")
            ) {
                onSave(draft)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canSave || draft.isSubmitting)
            .keyboardShortcut(.defaultAction)
        }
    }

    private static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap {
            $0.first(where: { $0.isLetter || $0.isNumber })
        }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}

private extension InboxRow {
    var avatarValue: String {
        localAvatarPath.isEmpty ? avatarPath : localAvatarPath
    }
}
