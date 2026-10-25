// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

// MARK: - Start New Chat, New Group, and Blasts Sheet (Task 11)

/// Modal sheet for **New Chat** (`⌘N`), **New Group**, and **Blasts** (`⌘⇧N`).
///
/// - 1:1 mode: search contacts (`people.contacts`) or look up a phone number / `@username` (`people.resolve`)
///   on any connected account, or click **Add Multiple People** to switch to multi-select.
/// - Multi-select (`>= 2` recipients): switches between **New Group** (`room.createGroup`, enabled only when all
///   selected recipients share one account whose bridge implements `GroupCreatingNetworkAPI`, per Ruling 1) and
///   **Blast** (`blast.send`, available across any mix of networks/accounts with `{recipient.firstName}` support,
///   a pre-send confirmation listing people and networks, and per-recipient outcomes per Ruling 2).
public struct StartNewChatView: View {
    @State private var draft: StartNewChatDraft
    public var onQueryChanged: (StartNewChatDraft) -> Void
    public var onOpenDirectChat: (ContactCandidate) -> Void
    public var onLookup: (StartNewChatLookupAction) -> Void
    public var onCreateGroup: (StartNewChatDraft) -> Void
    public var onSendBlast: (StartNewChatDraft) -> Void
    public var onCancel: () -> Void

    public init(
        draft: StartNewChatDraft,
        onQueryChanged: @escaping (StartNewChatDraft) -> Void = { _ in },
        onOpenDirectChat: @escaping (ContactCandidate) -> Void = { _ in },
        onLookup: @escaping (StartNewChatLookupAction) -> Void = { _ in },
        onCreateGroup: @escaping (StartNewChatDraft) -> Void = { _ in },
        onSendBlast: @escaping (StartNewChatDraft) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        self.onQueryChanged = onQueryChanged
        self.onOpenDirectChat = onOpenDirectChat
        self.onLookup = onLookup
        self.onCreateGroup = onCreateGroup
        self.onSendBlast = onSendBlast
        self.onCancel = onCancel
    }

    private var isMultiSelectActive: Bool {
        draft.startsInMultiSelect || !draft.selectedRecipients.isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            accountFilterBar
            searchAndTokensSection

            if draft.selectedRecipients.count >= 2 {
                multiRecipientModeSection
            }

            if let errorMessage = draft.errorMessage, !errorMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.14)))
            }

            if !draft.blastOutcomes.isEmpty {
                blastOutcomesSection
            }

            Divider()

            resultsListSection

            Divider()

            footerSection
        }
        .padding(16)
        .frame(width: 520)
        .frame(minHeight: 460)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isMultiSelectActive {
                Button {
                    draft.startsInMultiSelect = true
                } label: {
                    Label(String(localized: "New Group or Blast"), systemImage: "person.2.badge.plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var headerTitle: String {
        if draft.selectedRecipients.count >= 2 {
            switch draft.mode {
            case .newGroup: return String(localized: "New Group Chat")
            case .blast: return String(localized: "New Blast Message")
            case .directChat: return String(localized: "New Chat")
            }
        }
        return isMultiSelectActive ? String(localized: "New Group or Blast") : String(localized: "New Chat")
    }

    private var headerSubtitle: String {
        if draft.selectedRecipients.count >= 2 {
            switch draft.mode {
            case .newGroup:
                return String(localized: "Create a group chat with everyone on the same network account.")
            case .blast:
                return String(localized: "Send an individual 1:1 message to each person.")
            case .directChat:
                return String(localized: "Search contacts or enter a phone number or @username.")
            }
        }
        return String(localized: "Search contacts or enter a phone number or @username.")
    }

    // MARK: - Account Filter Bar

    private struct AccountPillItem: Identifiable {
        let id: String
        let filterValue: String?
        let network: String?
        let label: String
    }

    private var accountPills: [AccountPillItem] {
        var items: [AccountPillItem] = [
            AccountPillItem(
                id: "all",
                filterValue: nil,
                network: nil,
                label: String(localized: "All Networks")
            ),
        ]
        for account in draft.accounts {
            let connectedLogins = account.logins.filter { $0.state == .connected }
            if connectedLogins.count > 1 {
                for login in connectedLogins {
                    let key = "\(account.network):\(login.accountID)"
                    let title = login.remoteName.isEmpty
                        ? account.displayName
                        : "\(account.displayName) (\(login.remoteName))"
                    items.append(
                        AccountPillItem(
                            id: key,
                            filterValue: key,
                            network: account.network,
                            label: title
                        )
                    )
                }
            } else if !connectedLogins.isEmpty || account.state == .connected {
                let firstID = connectedLogins.first?.accountID ?? ""
                let key = firstID.isEmpty ? account.network : "\(account.network):\(firstID)"
                items.append(
                    AccountPillItem(
                        id: key,
                        filterValue: key,
                        network: account.network,
                        label: account.displayName
                    )
                )
            }
        }
        return items
    }

    private var accountFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(accountPills) { pill in
                    let isSelected = draft.selectedAccountFilter == pill.filterValue
                    Button {
                        draft.selectedAccountFilter = pill.filterValue
                        onQueryChanged(draft)
                    } label: {
                        HStack(spacing: 5) {
                            if let network = pill.network {
                                NetworkBadge(network: network, name: pill.label, size: 12)
                            }
                            Text(pill.label)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                isSelected ? Color.accentColor.opacity(0.55) : Color.clear,
                                lineWidth: 1
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Search & Recipient Tokens

    private var searchAndTokensSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !draft.selectedRecipients.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(draft.selectedRecipients) { recipient in
                            HStack(spacing: 5) {
                                NetworkBadge(
                                    network: recipient.network,
                                    name: NetworkNames.displayName(of: recipient.network) ?? recipient.network,
                                    size: 12
                                )
                                Text(recipient.name.isEmpty ? recipient.userID : recipient.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Button {
                                    draft.removeRecipient(recipient)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Remove \(recipient.name)"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "Search name, phone number (+1…), or @username…"),
                    text: Binding(
                        get: { draft.query },
                        set: { newValue in
                            draft.query = newValue
                            onQueryChanged(draft)
                        }
                    )
                )
                .textFieldStyle(.plain)
                if !draft.query.isEmpty {
                    Button {
                        draft.query = ""
                        onQueryChanged(draft)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Clear search"))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: - Multi-recipient Mode (New Group vs Blast)

    private var multiRecipientModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(
                    String(localized: "Mode"),
                    selection: Binding(
                        get: { draft.mode },
                        set: { newMode in
                            if newMode == .newGroup, !draft.isNewGroupEnabled { return }
                            draft.mode = newMode
                            draft.isConfirmingBlast = false
                        }
                    )
                ) {
                    Text(String(localized: "New Group"))
                        .tag(StartNewChatMode.newGroup)
                    Text(String(localized: "Blast (1:1 to Each)"))
                        .tag(StartNewChatMode.blast)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let reason = draft.newGroupDisabledReason {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            switch draft.mode {
            case .newGroup:
                HStack(spacing: 8) {
                    Text(String(localized: "Group Name"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Optional group name…"), text: $draft.groupName)
                        .textFieldStyle(.roundedBorder)
                }
            case .blast:
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Blast Message"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(String(localized: "Supports {recipient.firstName}"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    TextField(
                        String(localized: "Write a message to send to each person individually…"),
                        text: $draft.blastText,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 4)
                    .textFieldStyle(.roundedBorder)

                    if draft.isConfirmingBlast {
                        blastConfirmationBanner
                    }
                }
            case .directChat:
                EmptyView()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var blastConfirmationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane.circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.blastConfirmationText)
                    .font(.callout.weight(.semibold))
                Text(
                    draft.blastNetworks
                        .map { NetworkNames.displayName(of: $0) ?? $0 }
                        .joined(separator: ", ")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Cancel")) {
                draft.isConfirmingBlast = false
            }
            .controlSize(.small)
            Button(String(localized: "Confirm Send")) {
                onSendBlast(draft)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(draft.isSubmitting)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Per-Recipient Blast Outcomes

    private var blastOutcomesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Blast Delivery Results"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(draft.blastOutcomes) { outcome in
                HStack(spacing: 8) {
                    NetworkBadge(
                        network: outcome.recipient.network,
                        name: NetworkNames.displayName(of: outcome.recipient.network) ?? outcome.recipient.network,
                        size: 13
                    )
                    Text(outcome.recipient.name.isEmpty ? outcome.recipient.userID : outcome.recipient.name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    outcomeStatusBadge(outcome)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    @ViewBuilder
    private func outcomeStatusBadge(_ outcome: BlastRecipientOutcome) -> some View {
        switch outcome.status {
        case "sent":
            Label(String(localized: "Sent"), systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
        case "waiting", "queued", "pending":
            Label(String(localized: "Waiting"), systemImage: "clock.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
        default:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                Text(
                    outcome.error.isEmpty
                        ? String(localized: "Failed")
                        : String(localized: "Failed: \(outcome.error)")
                )
                .lineLimit(1)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.red)
        }
    }

    // MARK: - Results List & Lookup Actions

    private var resultsListSection: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                let lookupActions = draft.lookupActions
                if !lookupActions.isEmpty {
                    ForEach(lookupActions) { action in
                        Button {
                            onLookup(action)
                        } label: {
                            HStack(spacing: 8) {
                                NetworkBadge(
                                    network: action.network,
                                    name: action.networkDisplayName,
                                    size: 16
                                )
                                Text(action.title)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right.circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.08))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                let candidates = draft.filteredCandidates
                if candidates.isEmpty, lookupActions.isEmpty {
                    Text(String(localized: "No matching contacts found"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(candidates) { candidate in
                        candidateRow(candidate)
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: ContactCandidate) -> some View {
        let selected = draft.isSelected(candidate)
        let networkName = NetworkNames.displayName(of: candidate.network) ?? candidate.network
        return Button {
            if isMultiSelectActive {
                draft.toggleRecipient(candidate)
            } else {
                onOpenDirectChat(candidate)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        path: candidate.avatarPath,
                        initials: Self.initials(of: candidate.name),
                        seed: candidate.name
                    )
                    .frame(width: 32, height: 32)
                    NetworkBadge(network: candidate.network, name: networkName, size: 13)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.name.isEmpty ? candidate.userID : candidate.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(networkName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let firstID = candidate.identifiers.first {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(verbatim: firstID)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                if isMultiSelectActive {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                        .font(.body)
                } else {
                    Button {
                        draft.startsInMultiSelect = true
                        draft.toggleRecipient(candidate)
                    } label: {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Select for Group or Blast"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if !draft.selectedRecipients.isEmpty {
                Text(
                    draft.selectedRecipients.count == 1
                        ? String(localized: "1 person selected")
                        : String(localized: "\(draft.selectedRecipients.count) people selected")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "Cancel"), role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)

            if draft.selectedRecipients.count == 1, let single = draft.selectedRecipients.first {
                Button(String(localized: "Open Chat")) {
                    onOpenDirectChat(single)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.isSubmitting)
                .keyboardShortcut(.defaultAction)
            } else if draft.selectedRecipients.count >= 2 {
                switch draft.mode {
                case .newGroup:
                    Button(String(localized: "Create Group")) {
                        onCreateGroup(draft)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isNewGroupEnabled || draft.isSubmitting)
                    .keyboardShortcut(.defaultAction)
                case .blast:
                    Button(String(localized: "Send Blast…")) {
                        draft.isConfirmingBlast = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        draft.blastText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.isSubmitting
                    )
                    .keyboardShortcut(.defaultAction)
                case .directChat:
                    EmptyView()
                }
            }
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
