// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI

// MARK: - Start New Chat, New Group, and Blasts Sheet (Task 11)

/// Action executed when confirming the Start New Chat sheet (`Start Chat` button or `⌘↩`).
enum StartNewChatConfirmAction: Equatable, Sendable {
    case openDirectChat(ContactCandidate)
    case lookup(StartNewChatLookupAction)
}

/// Pure presentation logic for `StartNewChatView`: what the list shows, which rows the arrow keys visit, and what
/// **Start Chat** does.
///
/// Contacts always come from `draft.candidates` (the `people.contacts` result the search also queries): with an
/// empty query that is every contact, once typed it is the engine's matches.
enum StartNewChatPresentation {
    static let maxRecentChats = 8
    static let initialContactsLimit = 50

    static func hasTypedQuery(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func matchesAccountFilter(_ candidate: ContactCandidate, filter: String?) -> Bool {
        guard let filter else { return true }
        let key = "\(candidate.network):\(candidate.accountID)"
        return filter == key
            || filter == candidate.network
            || (!candidate.accountID.isEmpty && filter == candidate.accountID)
    }

    /// The most recent one-to-one chats (never groups, hidden chats or merged chats), newest first, as contacts
    /// that open the existing room. `limit == nil` returns all of them.
    static func recentDirectChats(
        from rows: [InboxRow],
        accounts: [Account],
        contacts: [ContactCandidate] = [],
        filter: String? = nil,
        limit: Int? = maxRecentChats
    ) -> [ContactCandidate] {
        var contactsByRoomID: [String: ContactCandidate] = [:]
        for candidate in contacts {
            if let roomID = candidate.roomID, !roomID.isEmpty, contactsByRoomID[roomID] == nil {
                contactsByRoomID[roomID] = candidate
            }
        }
        let sortedDirectRows = rows
            .filter { $0.isDirect && !$0.hidden && !$0.roomID.hasPrefix("merge:") }
            .sorted { lhs, rhs in
                if lhs.lastTS != rhs.lastTS {
                    return lhs.lastTS > rhs.lastTS
                }
                return lhs.roomID < rhs.roomID
            }
        var seenRooms = Set<String>()
        var seenCandidateIDs = Set<String>()
        var out: [ContactCandidate] = []
        for row in sortedDirectRows {
            guard seenRooms.insert(row.roomID).inserted else { continue }
            let matched = contactsByRoomID[row.roomID]
            let rowName = !row.localName.isEmpty ? row.localName : row.name
            let rowAvatar = !row.localAvatarPath.isEmpty ? row.localAvatarPath : row.avatarPath
            let candidate = ContactCandidate(
                userID: matched?.userID ?? row.roomID,
                name: !rowName.isEmpty ? rowName : (matched?.name ?? ""),
                avatarPath: !rowAvatar.isEmpty ? rowAvatar : (matched?.avatarPath ?? ""),
                network: row.network,
                accountID: matched?.accountID.isEmpty == false
                    ? matched!.accountID
                    : resolveAccountID(for: row, in: accounts),
                identifiers: matched?.identifiers ?? [],
                roomID: row.roomID
            )
            guard matchesAccountFilter(candidate, filter: filter) else { continue }
            guard seenCandidateIDs.insert(candidate.id).inserted else { continue }
            out.append(candidate)
            if let limit, out.count >= max(0, limit) {
                break
            }
        }
        return out
    }

    private static func resolveAccountID(for row: InboxRow, in accounts: [Account]) -> String {
        guard let account = accounts.first(where: { $0.network == row.network }) else {
            return ""
        }
        let connected = account.logins.filter { $0.state == .connected }
        let pool = connected.isEmpty ? account.logins : connected
        if pool.count == 1, let only = pool.first {
            return only.accountID
        }
        if !row.loginName.isEmpty,
           let matched = pool.first(where: { $0.remoteName == row.loginName }) {
            return matched.accountID
        }
        return ""
    }

    /// Contacts matching `filter`, sorted A–Z by display name.
    static func sortedContacts(_ candidates: [ContactCandidate], filter: String?) -> [ContactCandidate] {
        candidates
            .filter { matchesAccountFilter($0, filter: filter) }
            .sorted { lhs, rhs in
                let leftName = lhs.name.isEmpty ? lhs.userID : lhs.name
                let rightName = rhs.name.isEmpty ? rhs.userID : rhs.name
                let order = leftName.localizedStandardCompare(rightName)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
                if lhs.network != rhs.network {
                    return lhs.network < rhs.network
                }
                return lhs.userID < rhs.userID
            }
    }

    /// "No matching contacts found" shows only after the user has typed and there is nothing to pick: no contact
    /// result and no phone / email / `@handle` lookup to offer.
    static func shouldShowNoMatchingContacts(draft: StartNewChatDraft) -> Bool {
        hasTypedQuery(draft.query) && draft.filteredCandidates.isEmpty && draft.lookupActions.isEmpty
    }

    /// Row IDs in on-screen order: `lookup:` / `search:` once typed, else `recent:` then `contact:`.
    static func navigableRowIDs(
        draft: StartNewChatDraft,
        recentRows: [InboxRow],
        contactsLimit: Int = initialContactsLimit
    ) -> [String] {
        if hasTypedQuery(draft.query) {
            return draft.lookupActions.map { "lookup:\($0.id)" } + draft.filteredCandidates.map { "search:\($0.id)" }
        }
        let recents = recentDirectChats(
            from: recentRows,
            accounts: draft.accounts,
            contacts: draft.candidates,
            filter: draft.selectedAccountFilter,
            limit: maxRecentChats
        )
        let contacts = sortedContacts(draft.candidates, filter: draft.selectedAccountFilter).prefix(max(0, contactsLimit))
        return recents.map { "recent:\($0.id)" } + contacts.map { "contact:\($0.id)" }
    }

    static func candidate(
        forRowID rowID: String,
        draft: StartNewChatDraft,
        recentRows: [InboxRow],
        contactsLimit: Int = initialContactsLimit
    ) -> ContactCandidate? {
        if rowID.hasPrefix("recent:") {
            let id = String(rowID.dropFirst("recent:".count))
            return recentDirectChats(
                from: recentRows,
                accounts: draft.accounts,
                contacts: draft.candidates,
                filter: draft.selectedAccountFilter,
                limit: maxRecentChats
            ).first { $0.id == id }
        }
        if rowID.hasPrefix("contact:") {
            let id = String(rowID.dropFirst("contact:".count))
            return sortedContacts(draft.candidates, filter: draft.selectedAccountFilter)
                .prefix(max(0, contactsLimit))
                .first { $0.id == id }
        }
        if rowID.hasPrefix("search:") {
            let id = String(rowID.dropFirst("search:".count))
            return draft.filteredCandidates.first { $0.id == id }
        }
        return nil
    }

    /// What the primary **Start Chat** button (`⌘↩`) does, or `nil` when it is disabled: the selected row, else the
    /// first lookup when the query is a valid phone number, email or `@handle`.
    static func confirmAction(
        draft: StartNewChatDraft,
        recentRows: [InboxRow],
        contactsLimit: Int = initialContactsLimit,
        selectedRowID: String?
    ) -> StartNewChatConfirmAction? {
        guard !draft.isSubmitting, draft.selectedRecipients.count < 2 else { return nil }
        if draft.selectedRecipients.count == 1, let single = draft.selectedRecipients.first {
            return .openDirectChat(single)
        }
        if let selectedRowID {
            if selectedRowID.hasPrefix("lookup:") {
                let rawID = String(selectedRowID.dropFirst("lookup:".count))
                if let action = draft.lookupActions.first(where: { $0.id == rawID }) {
                    return .lookup(action)
                }
            } else if let candidate = candidate(
                forRowID: selectedRowID,
                draft: draft,
                recentRows: recentRows,
                contactsLimit: contactsLimit
            ) {
                return .openDirectChat(candidate)
            }
        }
        if let firstLookup = draft.lookupActions.first {
            return .lookup(firstLookup)
        }
        return nil
    }
}

/// Modal sheet for **New Chat** (`⌘N`), **New Group**, and **Blasts** (`⌘⇧N`).
///
/// - 1:1 mode: shows **Recent** (up to 8 most recent 1:1 chats) and **Contacts** (A–Z, first 50 with **Show more**)
///   before typing, or search contacts (`people.contacts`) and look up a phone number / email / `@username`
///   (`people.resolve`) on any connected account, with **Start Chat** (`⌘↩`) and ↑/↓ keyboard selection.
/// - Multi-select (`>= 2` recipients): switches between **New Group** (`room.createGroup`, enabled only when all
///   selected recipients share one account whose bridge implements `GroupCreatingNetworkAPI`, per Ruling 1) and
///   **Blast** (`blast.send`, available across any mix of networks/accounts with `{recipient.firstName}` support,
///   a pre-send confirmation listing people and networks, and per-recipient outcomes per Ruling 2).
public struct StartNewChatView: View {
    private let externalDraft: StartNewChatDraft
    private let recentRows: [InboxRow]
    @State private var draft: StartNewChatDraft
    @State private var contactsLimit: Int = StartNewChatPresentation.initialContactsLimit
    @State private var selectedRowID: String?
    @State private var hoveredRowID: String?
    @State private var chipViewportWidth: CGFloat = 0
    @State private var chipContentWidth: CGFloat = 0
    @State private var chipContentMaxX: CGFloat = 0

    public var onQueryChanged: (StartNewChatDraft) -> Void
    public var onOpenDirectChat: (ContactCandidate) -> Void
    public var onLookup: (StartNewChatLookupAction) -> Void
    public var onCreateGroup: (StartNewChatDraft) -> Void
    public var onSendBlast: (StartNewChatDraft) -> Void
    public var onCancel: () -> Void

    public init(
        draft: StartNewChatDraft,
        recentRows: [InboxRow] = [],
        onQueryChanged: @escaping (StartNewChatDraft) -> Void = { _ in },
        onOpenDirectChat: @escaping (ContactCandidate) -> Void = { _ in },
        onLookup: @escaping (StartNewChatLookupAction) -> Void = { _ in },
        onCreateGroup: @escaping (StartNewChatDraft) -> Void = { _ in },
        onSendBlast: @escaping (StartNewChatDraft) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.externalDraft = draft
        self.recentRows = recentRows
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
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: externalDraft) { _, updated in
            // The model owns the contact results, accounts and submit state, and publishes them after the engine
            // answers. Group name, blast text and mode live only in this sheet until it is submitted, so they stay.
            var merged = updated
            merged.mode = draft.mode
            merged.groupName = draft.groupName
            merged.blastText = draft.blastText
            merged.isConfirmingBlast = draft.isConfirmingBlast
            guard merged != draft else { return }
            if draft.selectedAccountFilter != updated.selectedAccountFilter {
                contactsLimit = StartNewChatPresentation.initialContactsLimit
            }
            draft = merged
            pruneSelectionIfNeeded()
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
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
                    onQueryChanged(draft)
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
                return String(localized: "Search contacts or enter a phone number, email, or @username.")
            }
        }
        return String(localized: "Search contacts or enter a phone number, email, or @username.")
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

    private var chipsHaveOverflow: Bool {
        chipViewportWidth > 0 && chipContentWidth > chipViewportWidth + 1
    }

    private var chipsOverflowTrailing: Bool {
        chipViewportWidth > 0 && chipContentMaxX > chipViewportWidth + 1
    }

    private var accountFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(accountPills) { pill in
                    let isSelected = draft.selectedAccountFilter == pill.filterValue
                    Button {
                        draft.selectedAccountFilter = pill.filterValue
                        contactsLimit = StartNewChatPresentation.initialContactsLimit
                        selectedRowID = nil
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
                        .fixedSize(horizontal: true, vertical: false)
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
            .background {
                GeometryReader { geo in
                    let frame = geo.frame(in: .named("startNewChatChips"))
                    Color.clear
                        .preference(key: ChipContentWidthKey.self, value: frame.width)
                        .preference(key: ChipContentMaxXKey.self, value: frame.maxX)
                }
            }
            .padding(.trailing, chipsHaveOverflow ? 24 : 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "startNewChatChips")
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ChipViewportWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(ChipViewportWidthKey.self) { chipViewportWidth = $0 }
        .onPreferenceChange(ChipContentWidthKey.self) { chipContentWidth = $0 }
        .onPreferenceChange(ChipContentMaxXKey.self) { chipContentMaxX = $0 }
        .overlay(alignment: .trailing) {
            if chipsOverflowTrailing {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor).opacity(0),
                        Color(nsColor: .windowBackgroundColor),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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
                                    onQueryChanged(draft)
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
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                StartNewChatSearchField(
                    text: Binding(
                        get: { draft.query },
                        set: { newValue in
                            draft.query = newValue
                            pruneSelectionIfNeeded()
                            onQueryChanged(draft)
                        }
                    ),
                    placeholder: String(localized: "Search name, phone number (+1…), email, or @username…"),
                    onCommand: handleSearchFieldCommand
                )
                .frame(height: 18)
                if !draft.query.isEmpty {
                    Button {
                        draft.query = ""
                        pruneSelectionIfNeeded()
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if StartNewChatPresentation.hasTypedQuery(draft.query) {
                        typedResultsContent
                    } else {
                        emptyQueryContent
                    }
                }
            }
            .onChange(of: selectedRowID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyQueryContent: some View {
        let recents = StartNewChatPresentation.recentDirectChats(
            from: recentRows,
            accounts: draft.accounts,
            contacts: draft.candidates,
            filter: draft.selectedAccountFilter,
            limit: StartNewChatPresentation.maxRecentChats
        )
        let allContacts = StartNewChatPresentation.sortedContacts(draft.candidates, filter: draft.selectedAccountFilter)
        let visibleContacts = Array(allContacts.prefix(contactsLimit))
        let hasMoreContacts = allContacts.count > contactsLimit

        if !recents.isEmpty {
            sectionHeader(String(localized: "Recent"))
            ForEach(recents) { candidate in
                candidateRow(candidate, rowID: "recent:\(candidate.id)")
            }
        }
        if !visibleContacts.isEmpty {
            sectionHeader(String(localized: "Contacts"))
                .padding(.top, recents.isEmpty ? 0 : 6)
            ForEach(visibleContacts) { candidate in
                candidateRow(candidate, rowID: "contact:\(candidate.id)")
            }
            if hasMoreContacts {
                Button {
                    contactsLimit += StartNewChatPresentation.initialContactsLimit
                } label: {
                    HStack {
                        Text(String(localized: "Show more"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        if recents.isEmpty && visibleContacts.isEmpty {
            Text(String(localized: "Enter a phone number, email, or @username above to start a chat."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var typedResultsContent: some View {
        let lookupActions = draft.lookupActions
        let candidates = draft.filteredCandidates

        if !lookupActions.isEmpty {
            ForEach(lookupActions) { action in
                lookupRow(action, rowID: "lookup:\(action.id)")
            }
        }

        if !candidates.isEmpty {
            ForEach(candidates) { candidate in
                candidateRow(candidate, rowID: "search:\(candidate.id)")
            }
        } else if lookupActions.isEmpty {
            Text(String(localized: "No matching contacts found"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.top, 2)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func lookupRow(_ action: StartNewChatLookupAction, rowID: String) -> some View {
        let isKeyboardSelected = selectedRowID == rowID
        let isHovered = hoveredRowID == rowID
        return Button {
            selectedRowID = rowID
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
                    .fill(
                        isKeyboardSelected
                            ? Color.accentColor.opacity(0.18)
                            : (isHovered ? Color.accentColor.opacity(0.13) : Color.accentColor.opacity(0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isKeyboardSelected ? Color.accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredRowID = rowID
            } else if hoveredRowID == rowID {
                hoveredRowID = nil
            }
        }
        .id(rowID)
    }

    private func candidateRow(_ candidate: ContactCandidate, rowID: String) -> some View {
        let isRecipientSelected = draft.isSelected(candidate)
        let isKeyboardSelected = selectedRowID == rowID
        let isHovered = hoveredRowID == rowID
        let displayName = candidate.name.isEmpty ? candidate.userID : candidate.name
        let networkName = NetworkNames.displayName(of: candidate.network) ?? candidate.network
        let firstDisplayID = ContactsBridge.displayableIdentifiers(candidate.identifiers).first
            .map(ContactsBridge.displayIdentifier)
        let allowsMultiSelect = !candidate.userID.hasPrefix("!")

        return Button {
            selectedRowID = rowID
            if isMultiSelectActive {
                if allowsMultiSelect {
                    draft.toggleRecipient(candidate)
                    onQueryChanged(draft)
                }
            } else {
                onOpenDirectChat(candidate)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        path: candidate.avatarPath,
                        initials: Self.initials(of: displayName),
                        seed: displayName,
                        size: 32
                    )
                    .frame(width: 32, height: 32)
                    NetworkBadge(network: candidate.network, name: networkName, size: 13, ringed: true)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(verbatim: networkName)
                        if let firstDisplayID {
                            Text(verbatim: "·")
                            Text(verbatim: firstDisplayID)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if isMultiSelectActive {
                    if allowsMultiSelect {
                        Image(systemName: isRecipientSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isRecipientSelected ? Color.accentColor : Color.secondary)
                            .font(.body)
                    }
                } else if allowsMultiSelect {
                    Button {
                        draft.startsInMultiSelect = true
                        draft.toggleRecipient(candidate)
                        onQueryChanged(draft)
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
                    .fill(
                        isKeyboardSelected
                            ? Color.accentColor.opacity(0.16)
                            : (isRecipientSelected
                                ? Color.accentColor.opacity(0.10)
                                : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isKeyboardSelected ? Color.accentColor.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredRowID = rowID
            } else if hoveredRowID == rowID {
                hoveredRowID = nil
            }
        }
        .id(rowID)
    }

    // MARK: - Footer

    private var currentConfirmAction: StartNewChatConfirmAction? {
        StartNewChatPresentation.confirmAction(
            draft: draft,
            recentRows: recentRows,
            contactsLimit: contactsLimit,
            selectedRowID: selectedRowID
        )
    }

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

            if draft.selectedRecipients.count >= 2 {
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
            } else {
                let confirm = currentConfirmAction
                Button(String(localized: "Start Chat")) {
                    performConfirm(confirm)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(confirm == nil || draft.isSubmitting)
            }
        }
    }

    // MARK: - Keyboard Navigation & Confirm

    private var navigableRowIDs: [String] {
        StartNewChatPresentation.navigableRowIDs(
            draft: draft,
            recentRows: recentRows,
            contactsLimit: contactsLimit
        )
    }

    private func pruneSelectionIfNeeded() {
        guard let selectedRowID else { return }
        if !navigableRowIDs.contains(selectedRowID) {
            self.selectedRowID = nil
        }
    }

    private func moveSelection(_ delta: Int) {
        let ids = navigableRowIDs
        guard !ids.isEmpty else {
            selectedRowID = nil
            return
        }
        guard let current = selectedRowID, let index = ids.firstIndex(of: current) else {
            selectedRowID = delta >= 0 ? ids.first : ids.last
            return
        }
        let nextIndex = min(max(0, index + delta), ids.count - 1)
        selectedRowID = ids[nextIndex]
    }

    private func performConfirm(_ action: StartNewChatConfirmAction?) {
        guard let action, !draft.isSubmitting else { return }
        switch action {
        case let .openDirectChat(candidate):
            onOpenDirectChat(candidate)
        case let .lookup(lookupAction):
            onLookup(lookupAction)
        }
    }

    private func handleSearchFieldCommand(_ command: StartNewChatFieldCommand) -> Bool {
        switch command {
        case .up:
            moveSelection(-1)
            return true
        case .down:
            moveSelection(1)
            return true
        case .confirm:
            if isMultiSelectActive,
               let rowID = selectedRowID,
               let candidate = StartNewChatPresentation.candidate(
                   forRowID: rowID,
                   draft: draft,
                   recentRows: recentRows,
                          contactsLimit: contactsLimit
               ),
               !candidate.userID.hasPrefix("!") {
                draft.toggleRecipient(candidate)
                onQueryChanged(draft)
                return true
            }
            if let action = currentConfirmAction {
                performConfirm(action)
                return true
            }
            return false
        case .cancel:
            onCancel()
            return true
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

private struct ChipViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ChipContentWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ChipContentMaxXKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private enum StartNewChatFieldCommand {
    case up
    case down
    case confirm
    case cancel
}

private struct StartNewChatSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onCommand: (StartNewChatFieldCommand) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = StartNewChatFocusTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
            field.setAccessibilityLabel(placeholder)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: StartNewChatSearchField

        init(_ parent: StartNewChatSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return parent.onCommand(.up)
            case #selector(NSResponder.moveDown(_:)):
                return parent.onCommand(.down)
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                    return false
                }
                return parent.onCommand(.confirm)
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
                return parent.onCommand(.cancel)
            default:
                return false
            }
        }
    }
}

private final class StartNewChatFocusTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            window.makeFirstResponder(self)
        }
    }
}
