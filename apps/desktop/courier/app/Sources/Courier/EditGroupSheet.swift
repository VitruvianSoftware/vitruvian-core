// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Edit Group / Edit Chat Sheet (Task 10)

/// Sheet for editing a group or 1:1 chat's name, topic, and avatar either **For Everyone** (on the remote network,
/// gated by `features.canSetName`, `features.canSetTopic`, `features.canSetAvatar`) or **Just for Me** (local override
/// on this Mac via `room.setLocalOverride`, always available).
public struct EditGroupSheet: View {
    @State private var draft: EditGroupDraft
    public var onSave: (EditGroupDraft) -> Void
    public var onResetLocalOverride: () -> Void
    public var onCancel: () -> Void

    public init(
        draft: EditGroupDraft,
        onSave: @escaping (EditGroupDraft) -> Void,
        onResetLocalOverride: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onResetLocalOverride = onResetLocalOverride
        self.onCancel = onCancel
    }

    private var networkDisplayName: String {
        NetworkNames.displayName(of: draft.network) ?? draft.network
    }

    private var availableScopes: [EditGroupScope] {
        if draft.canEditForEveryone {
            return [.forEveryone, .justForMe]
        }
        return [.justForMe]
    }

    private var canEditNameInCurrentScope: Bool {
        switch draft.scope {
        case .forEveryone: draft.features.canSetName
        case .justForMe: true
        }
    }

    private var canEditAvatarInCurrentScope: Bool {
        switch draft.scope {
        case .forEveryone: draft.features.canSetAvatar
        case .justForMe: true
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerSection
            scopePickerSection
            avatarSection
            fieldsSection
            Spacer(minLength: 0)
            Divider()
            footerButtons
        }
        .padding(20)
        .frame(width: 440)
        .frame(minHeight: 340)
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.isDirect ? String(localized: "Edit Chat") : String(localized: "Edit Group"))
                    .font(.headline)
                if !networkDisplayName.isEmpty {
                    Text(String(localized: "On \(networkDisplayName)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !draft.network.isEmpty {
                NetworkBadge(network: draft.network, name: networkDisplayName, size: 18)
            }
        }
    }

    private var scopePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(
                String(localized: "Scope"),
                selection: Binding(
                    get: { draft.scope },
                    set: { newScope in draft.selectScope(newScope) }
                )
            ) {
                ForEach(availableScopes, id: \.self) { scope in
                    switch scope {
                    case .forEveryone:
                        Text(String(localized: "For Everyone")).tag(EditGroupScope.forEveryone)
                    case .justForMe:
                        Text(String(localized: "Just for Me")).tag(EditGroupScope.justForMe)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if draft.scope == .justForMe {
                Label(
                    String(localized: "Changes apply only on this Mac."),
                    systemImage: "laptopcomputer"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !networkDisplayName.isEmpty {
                Label(
                    String(localized: "Changes are visible to everyone on \(networkDisplayName)."),
                    systemImage: "globe"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var avatarSection: some View {
        HStack(spacing: 12) {
            avatarPreview
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button(String(localized: "Choose Photo…")) {
                        pickAvatar()
                    }
                    .controlSize(.small)
                    .disabled(!canEditAvatarInCurrentScope)

                    if draft.scope == .justForMe {
                        Button(String(localized: "Reset to network name")) {
                            draft.name = draft.remoteName
                            draft.avatarPath = ""
                            draft.localName = ""
                            draft.localAvatarPath = ""
                            onResetLocalOverride()
                        }
                        .controlSize(.small)
                    }
                }

                if draft.scope == .justForMe, !draft.remoteName.isEmpty {
                    Text(String(localized: "Network name: \(draft.remoteName)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        let seed = draft.name.isEmpty ? draft.remoteName : draft.name
        if !draft.avatarPath.isEmpty {
            AvatarView(path: draft.avatarPath, initials: Self.initials(of: seed), seed: seed)
        } else if !draft.isDirect {
            GroupAvatar(seed: seed)
        } else {
            AvatarView(path: "", initials: Self.initials(of: seed), seed: seed)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Name"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    draft.remoteName.isEmpty ? String(localized: "Chat name") : draft.remoteName,
                    text: $draft.name
                )
                .textFieldStyle(.roundedBorder)
                .disabled(!canEditNameInCurrentScope)
            }

            if draft.scope == .forEveryone, draft.features.canSetTopic {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Topic"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        String(localized: "Add a group topic or description…"),
                        text: $draft.topic,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var footerButtons: some View {
        HStack {
            Spacer(minLength: 0)
            Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Save")) {
                onSave(draft)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func pickAvatar() {
        if let url = AppLockGate.shared.runOpenPanel(action: .settingsChange, configure: { panel in
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
        })?.first {
            draft.avatarPath = url.path
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

// MARK: - Add Participants Sheet (Task 10)

/// Sheet for inviting contacts or people from shared groups (`people.contacts` + `search.query(sections: ["in_groups"])`)
/// into a group chat (`room.invite`).
public struct AddParticipantsSheet: View {
    public let roomName: String
    public let network: String
    public let candidates: [ContactCandidate]
    @State private var selectedUserIDs: Set<String>
    @State private var searchText: String
    public var onSearch: ((String) -> Void)?
    public var onAdd: ([String]) -> Void
    public var onCancel: () -> Void

    public init(
        roomName: String,
        network: String = "whatsapp",
        candidates: [ContactCandidate],
        selectedUserIDs: Set<String> = [],
        searchText: String = "",
        onSearch: ((String) -> Void)? = nil,
        onAdd: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.roomName = roomName
        self.network = network
        self.candidates = candidates
        _selectedUserIDs = State(initialValue: selectedUserIDs)
        _searchText = State(initialValue: searchText)
        self.onSearch = onSearch
        self.onAdd = onAdd
        self.onCancel = onCancel
    }

    public init(
        roomName: String,
        network: String = "whatsapp",
        initialCandidates: [ContactCandidate],
        initialSelectedIDs: Set<String> = [],
        onSearch: ((String) -> [ContactCandidate])? = nil,
        onInvite: @escaping ([String]) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.roomName = roomName
        self.network = network
        self.candidates = initialCandidates
        _selectedUserIDs = State(initialValue: initialSelectedIDs)
        _searchText = State(initialValue: "")
        self.onSearch = { query in _ = onSearch?(query) }
        self.onAdd = onInvite
        self.onCancel = onCancel
    }

    private var networkDisplayName: String {
        NetworkNames.displayName(of: network) ?? network
    }

    private var filteredCandidates: [ContactCandidate] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return candidates }
        return candidates.filter { candidate in
            candidate.name.localizedCaseInsensitiveContains(trimmed)
                || candidate.userID.localizedCaseInsensitiveContains(trimmed)
                || candidate.identifiers.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private var selectedCandidates: [ContactCandidate] {
        candidates.filter { selectedUserIDs.contains($0.userID) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Add Participants"))
                        .font(.headline)
                    Text(
                        roomName.isEmpty
                            ? String(localized: "On \(networkDisplayName)")
                            : String(localized: "\(roomName) · \(networkDisplayName)")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !network.isEmpty {
                    NetworkBadge(network: network, name: networkDisplayName, size: 18)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search contacts or people in groups…"), text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        onSearch?(newValue)
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            if !selectedCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedCandidates) { candidate in
                            HStack(spacing: 4) {
                                Text(candidate.name.isEmpty ? candidate.userID : candidate.name)
                                    .font(.caption.weight(.medium))
                                Button {
                                    selectedUserIDs.remove(candidate.userID)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Remove \(candidate.name)"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filteredCandidates.isEmpty {
                        Text(String(localized: "No matching contacts found"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        ForEach(filteredCandidates) { candidate in
                            let isSelected = selectedUserIDs.contains(candidate.userID)
                            Button {
                                if isSelected {
                                    selectedUserIDs.remove(candidate.userID)
                                } else {
                                    selectedUserIDs.insert(candidate.userID)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    AvatarView(
                                        path: candidate.avatarPath,
                                        initials: Self.initials(of: candidate.name),
                                        seed: candidate.name
                                    )
                                    .frame(width: 32, height: 32)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(candidate.name.isEmpty ? candidate.userID : candidate.name)
                                            .font(.callout.weight(.medium))
                                            .lineLimit(1)
                                        if let firstID = candidate.identifiers.first {
                                            Text(verbatim: firstID)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
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

            Divider()

            HStack {
                Text(
                    selectedUserIDs.count == 1
                        ? String(localized: "1 selected")
                        : String(localized: "\(selectedUserIDs.count) selected")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Add")) {
                    let ordered = candidates.map(\.userID).filter { selectedUserIDs.contains($0) }
                    onAdd(ordered.isEmpty ? Array(selectedUserIDs) : ordered)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedUserIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .frame(minHeight: 380)
    }

    private static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap {
            $0.first(where: { $0.isLetter || $0.isNumber })
        }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }
}

// MARK: - Report as Spam Sheet (Task 10)

/// Confirmation sheet for reporting a chat as spam (`room.reportSpam`).
/// Per Ruling: the leave/delete checkbox is unticked by default and shown only when `canLeave` (group) or `canDelete`.
public struct ReportSpamSheet: View {
    @State private var draft: ReportSpamDraft
    public var onConfirm: (ReportSpamDraft) -> Void
    public var onCancel: () -> Void

    public init(
        draft: ReportSpamDraft,
        onConfirm: @escaping (ReportSpamDraft) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public init(
        draft: ReportSpamDraft,
        onReport: @escaping (ReportSpamDraft) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        self.onConfirm = onReport
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Report as Spam"))
                        .font(.headline)
                    if !draft.chatName.isEmpty {
                        Text(verbatim: draft.chatName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(String(localized: "Hide this chat on this Mac and mark it as spam?"))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if let checkboxLabel = draft.leaveOrDeleteLabel {
                Toggle(isOn: $draft.alsoLeaveOrDelete) {
                    Text(checkboxLabel)
                        .font(.callout)
                }
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)
            Divider()

            HStack {
                Spacer(minLength: 0)
                Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Report Spam"), role: .destructive) {
                    onConfirm(draft)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .frame(minHeight: 200)
    }
}

// MARK: - Participant Context Menu (Task 10)

/// Context menu items for a group participant row in `ChatInfoPane`:
/// - **Message `<Name>`** (`room.directChat`)
/// - **Make Admin** / **Remove Admin** (when `features.canSetAdmin`)
/// - **Remove from Group** (when `features.canKick`)
/// - **Copy User ID**
public struct ParticipantContextMenu: View {
    public let member: Member
    public let features: ChatFeatures
    public var onMessage: () -> Void
    public var onToggleAdmin: (Bool) -> Void
    public var onRemove: () -> Void
    public var onCopyUserID: () -> Void

    public init(
        member: Member,
        features: ChatFeatures,
        onMessage: @escaping () -> Void = {},
        onToggleAdmin: @escaping (Bool) -> Void = { _ in },
        onRemove: @escaping () -> Void = {},
        onCopyUserID: @escaping () -> Void = {}
    ) {
        self.member = member
        self.features = features
        self.onMessage = onMessage
        self.onToggleAdmin = onToggleAdmin
        self.onRemove = onRemove
        self.onCopyUserID = onCopyUserID
    }

    public init(
        member: Member,
        features: ChatFeatures,
        onMessage: @escaping () -> Void = {},
        onToggleAdmin: @escaping () -> Void,
        onRemoveFromGroup: @escaping () -> Void,
        onCopyUserID: @escaping () -> Void = {}
    ) {
        self.member = member
        self.features = features
        self.onMessage = onMessage
        self.onToggleAdmin = { _ in onToggleAdmin() }
        self.onRemove = onRemoveFromGroup
        self.onCopyUserID = onCopyUserID
    }

    private var displayName: String {
        member.name.isEmpty ? member.userID : member.name
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onMessage) {
                Label(String(localized: "Message \(displayName)"), systemImage: "bubble.left")
            }

            if features.canSetAdmin {
                Button {
                    onToggleAdmin(!member.isAdmin)
                } label: {
                    Label(
                        member.isAdmin
                            ? String(localized: "Remove Admin")
                            : String(localized: "Make Admin"),
                        systemImage: member.isAdmin ? "shield.slash" : "shield.lefthalf.filled"
                    )
                }
            }

            if features.canKick {
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label(String(localized: "Remove from Group"), systemImage: "person.badge.minus")
                }
            }

            Divider()
            Button(action: onCopyUserID) {
                Label(String(localized: "Copy User ID"), systemImage: "doc.on.doc")
            }
        }
    }
}
