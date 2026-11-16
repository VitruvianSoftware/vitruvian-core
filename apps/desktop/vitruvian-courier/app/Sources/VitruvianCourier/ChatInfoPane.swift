// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import SwiftUI
import UniformTypeIdentifiers

/// The Chat Info right pane and standalone window content (01 §11, Milestone 4.5a Task 9).
///
/// Renders at a minimum width of 280 pt (`ConversationView`'s right split pane):
///   - Header: avatar with network badge, effective chat title (`info.name`) + edit pencil button,
///     secondary network name line (`"On WhatsApp: <remoteName>"`) only when a local override is set (Ruling 1),
///     topic, 1:1 participant handle/phone and timezone (or group member count), and open-in-window / close buttons.
///   - Filter field (`@FocusState`) filtering participants, files, links, and bookmarks.
///   - Collapsible sections: Participants (with `Admin` / `Bot` badges and **Add Participants** button),
///     Pinned, Shared Media (3×3 grid), Files, Links, Bookmarks (`search.query` with `sections: [.bookmarks]`),
///     Encryption, Disappearing Messages, **Reload Chat Details**, and **Export Chat…** (`NSSavePanel` in view only).
public struct ChatInfoPane: View {
    public let info: RoomInfoResult
    public let bookmarks: [MessageHit]
    public var isRefreshing: Bool = false
    public var isMuted: Bool = false
    public var isPinned: Bool = false
    public var showsCloseButton: Bool = true
    public var focusSearchTrigger: Int = 0
    public var now: () -> Date = Date.init
    public var timerChoices: [DisappearingChoice] = []
    public var onSelectTimer: (DisappearingChoice) -> Void = { _ in }
    /// The chat's "Read Aloud on Vitruvian Speaker" choice; nil hides the row (Vitruvian Speaker is not installed).
    public var readAloud: ChatReadAloud? = nil
    public var onSelectReadAloud: (ChatReadAloud) -> Void = { _ in }
    public var onEditTitleAndAvatar: () -> Void = {}
    public var onAddParticipants: () -> Void = {}
    public var onSelectMember: (Member) -> Void = { _ in }
    public var onMessageMember: (Member) -> Void = { _ in }
    public var onToggleMemberAdmin: (Member, Bool) -> Void = { _, _ in }
    public var onRemoveMember: (Member) -> Void = { _ in }
    public var onCopyMemberID: (Member) -> Void = { member in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(member.userID, forType: .string)
    }
    public var onSelectEvent: (String) -> Void = { _ in }
    public var onRefresh: () -> Void = {}
    public var onExport: (URL) -> Void = { _ in }
    public var onMergeChat: (() -> Void)? = nil
    public var onLeaveGroup: () -> Void = {}
    public var onDeleteChat: () -> Void = {}
    public var onReportSpam: () -> Void = {}
    public var isAIAvailable: Bool = false
    public var onSummarizeChat: (() -> Void)? = nil
    public var onOpenAISettings: (() -> Void)? = nil
    public var onToggleMute: () -> Void = {}
    public var onTogglePin: () -> Void = {}
    public var onArchive: () -> Void = {}
    public var onRemind: () -> Void = {}
    public var onSearchInChat: () -> Void = {}
    public var onClose: () -> Void = {}
    public var inbox: InboxModel? = nil
    /// With glass in the main window the header is a toolbar item (`ChatInfoHeader`, placed by ConversationView), so
    /// the pane draws none of its own.
    public var headerInToolbar: Bool = false

    @Environment(\.openWindow) private var openWindow
    @State private var filterText: String = ""
    @FocusState private var isFilterFocused: Bool

    @State private var participantsExpanded = true
    @State private var pinnedExpanded = true
    @State private var mediaExpanded = true
    @State private var filesExpanded = true
    @State private var linksExpanded = true
    @State private var bookmarksExpanded = true

    public init(
        info: RoomInfoResult,
        bookmarks: [MessageHit] = [],
        isRefreshing: Bool = false,
        isMuted: Bool = false,
        isPinned: Bool = false,
        showsCloseButton: Bool = true,
        focusSearchTrigger: Int = 0,
        now: @escaping () -> Date = Date.init,
        timerChoices: [DisappearingChoice] = [],
        onSelectTimer: @escaping (DisappearingChoice) -> Void = { _ in },
        readAloud: ChatReadAloud? = nil,
        onSelectReadAloud: @escaping (ChatReadAloud) -> Void = { _ in },
        onEditTitleAndAvatar: @escaping () -> Void = {},
        onAddParticipants: @escaping () -> Void = {},
        onSelectMember: @escaping (Member) -> Void = { _ in },
        onMessageMember: @escaping (Member) -> Void = { _ in },
        onToggleMemberAdmin: @escaping (Member, Bool) -> Void = { _, _ in },
        onRemoveMember: @escaping (Member) -> Void = { _ in },
        onCopyMemberID: @escaping (Member) -> Void = { member in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(member.userID, forType: .string)
        },
        onSelectEvent: @escaping (String) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {},
        onExport: @escaping (URL) -> Void = { _ in },
        onMergeChat: (() -> Void)? = nil,
        onLeaveGroup: @escaping () -> Void = {},
        onDeleteChat: @escaping () -> Void = {},
        onReportSpam: @escaping () -> Void = {},
        isAIAvailable: Bool = false,
        onSummarizeChat: (() -> Void)? = nil,
        onOpenAISettings: (() -> Void)? = nil,
        onToggleMute: @escaping () -> Void = {},
        onTogglePin: @escaping () -> Void = {},
        onArchive: @escaping () -> Void = {},
        onRemind: @escaping () -> Void = {},
        onSearchInChat: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {},
        inbox: InboxModel? = nil,
        headerInToolbar: Bool = false
    ) {
        self.headerInToolbar = headerInToolbar
        self.inbox = inbox
        self.info = info
        self.bookmarks = bookmarks
        self.isRefreshing = isRefreshing
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.showsCloseButton = showsCloseButton
        self.focusSearchTrigger = focusSearchTrigger
        self.now = now
        self.timerChoices = timerChoices
        self.onSelectTimer = onSelectTimer
        self.readAloud = readAloud
        self.onSelectReadAloud = onSelectReadAloud
        self.onEditTitleAndAvatar = onEditTitleAndAvatar
        self.onAddParticipants = onAddParticipants
        self.onSelectMember = onSelectMember
        self.onMessageMember = onMessageMember
        self.onToggleMemberAdmin = onToggleMemberAdmin
        self.onRemoveMember = onRemoveMember
        self.onCopyMemberID = onCopyMemberID
        self.onSelectEvent = onSelectEvent
        self.onRefresh = onRefresh
        self.onExport = onExport
        self.onMergeChat = onMergeChat
        self.onLeaveGroup = onLeaveGroup
        self.onDeleteChat = onDeleteChat
        self.onReportSpam = onReportSpam
        self.isAIAvailable = isAIAvailable
        self.onSummarizeChat = onSummarizeChat
        self.onOpenAISettings = onOpenAISettings
        self.onToggleMute = onToggleMute
        self.onTogglePin = onTogglePin
        self.onArchive = onArchive
        self.onRemind = onRemind
        self.onSearchInChat = onSearchInChat
        self.onClose = onClose
    }

    /// Formats a person's current local time (e.g. `"3:27 PM local time"`) from an IANA timezone identifier
    /// using an injected clock (`now`). Returns `nil` when `timeZoneID` is empty or unrecognized.
    public static func localTimeText(
        for timeZoneID: String,
        now: Date,
        locale: Locale = Locale(identifier: "en_US")
    ) -> String? {
        let trimmed = timeZoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let tz = TimeZone(identifier: trimmed) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = tz
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: now)
            .replacingOccurrences(of: "\u{202f}", with: " ")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        guard !formatted.isEmpty else { return nil }
        return String(localized: "\(formatted) local time")
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !headerInToolbar {
                ChatInfoHeader(roomID: info.roomID, showsCloseButton: showsCloseButton, onClose: onClose,
                               inToolbar: false)
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    identityHeader
                    quickActionsRow
                    filterBar
                    if !info.isDirect {
                        participantsSection
                    }
                    if !info.pinnedEventIDs.isEmpty {
                        pinnedSection
                    }
                    if !mediaItems.isEmpty {
                        mediaSection
                    }
                    if !filteredFiles.isEmpty {
                        filesSection
                    }
                    if !filteredLinks.isEmpty {
                        linksSection
                    }
                    if !filteredBookmarks.isEmpty {
                        bookmarksSection
                    }
                    securityAndTimerSection
                    actionsSection
                    destructiveActionsSection
                }
                // The header's inset, so the sections line up under its title.
                .padding(PaneHeaderMetrics.inset)
            }
            .courierScrollEdges()
        }
        .frame(minWidth: 280)
        .courierSurface(.sidePane)
        .onChange(of: focusSearchTrigger) { _, _ in
            isFilterFocused = true
        }
    }

    // MARK: - Header (Ruling 1)

    private var networkDisplayName: String {
        NetworkNames.displayName(of: info.network) ?? info.network
    }

    /// Per Ruling 1: show the network's name as a secondary line only when a local override is set.
    private var networkNameOverrideLine: String? {
        let hasOverride = !info.localName.isEmpty && info.localName != info.remoteName
        let differsFromRemote = !info.remoteName.isEmpty && (hasOverride || info.name != info.remoteName)
        guard differsFromRemote else { return nil }
        return String(localized: "On \(networkDisplayName): \(info.remoteName)")
    }

    private var directOtherMember: Member? {
        guard info.isDirect else { return nil }
        return info.members.first { $0.userID != Timeline.meUserID } ?? info.members.first
    }

    private var identityHeader: some View {
        VStack(alignment: .center, spacing: 6) {
            avatarView
                .clipShape(Rectangle())
                .frame(width: 56, height: 56)
                .overlay(alignment: .bottomTrailing) {
                    NetworkBadge(network: info.network, name: networkDisplayName, size: 16, ringed: true)
                        .offset(x: 2, y: 2)
                }

            HStack(spacing: 4) {
                Text(info.name.isEmpty ? String(localized: "Unnamed chat") : info.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Button(action: onEditTitleAndAvatar) {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Edit chat name or avatar"))
                .accessibilityLabel(String(localized: "Edit chat name or avatar"))
            }

            if let overrideLine = networkNameOverrideLine {
                Text(overrideLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if !info.topic.isEmpty {
                Text(verbatim: info.topic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            if info.isDirect, let member = directOtherMember {
                ForEach(ContactsBridge.displayableIdentifiers(member.identifiers), id: \.self) { identifier in
                    Text(verbatim: ContactsBridge.displayIdentifier(identifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let localTime = Self.localTimeText(for: member.tz, now: now(), locale: .current) {
                    Label(localTime, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if !info.isDirect {
                Text(
                    info.members.count == 1
                        ? String(localized: "1 member")
                        : String(localized: "\(info.members.count) members")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatarView: some View {
        let displayAvatar = ChatInfoPresentation.displayAvatarPath(for: info)
        if !displayAvatar.isEmpty {
            AvatarView(path: displayAvatar, initials: Self.initials(of: info.name), seed: info.name, size: 56)
        } else if !info.isDirect {
            let compositeMembers = ChatInfoPresentation.groupCompositeMembers(for: info)
            if info.name.isEmpty && compositeMembers.isEmpty {
                UnknownAvatar()
            } else {
                GroupCompositeAvatar(name: info.name, members: compositeMembers, size: 56)
            }
        } else if info.name.isEmpty {
            UnknownAvatar()
        } else {
            AvatarView(path: "", initials: Self.initials(of: info.name), seed: info.name, size: 56)
        }
    }

    // MARK: - Quick Actions

    @ViewBuilder
    private var quickActionsRow: some View {
        if let inbox {
            ObservedChatInfoQuickActionsRow(
                roomID: info.roomID,
                inbox: inbox,
                fallbackMuted: isMuted,
                fallbackPinned: isPinned,
                onToggleMute: onToggleMute,
                onTogglePin: onTogglePin,
                onArchive: onArchive,
                onRemind: onRemind,
                onSearchInChat: onSearchInChat
            )
        } else {
            ChatInfoQuickActionsRow(
                isMuted: isMuted,
                isPinned: isPinned,
                onToggleMute: onToggleMute,
                onTogglePin: onTogglePin,
                onArchive: onArchive,
                onRemind: onRemind,
                onSearchInChat: onSearchInChat
            )
        }
    }

    private static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap {
            $0.first(where: { $0.isLetter || $0.isNumber })
        }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }

    public static func participantDisplayName(for member: Member) -> String {
        let base = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if member.userID == Timeline.meUserID {
            if base.isEmpty || base.caseInsensitiveCompare("me") == .orderedSame {
                return String(localized: "You")
            }
            if base.localizedCaseInsensitiveContains("(you)") {
                return base
            }
            return String(localized: "\(base) (you)")
        }
        return base.isEmpty ? member.userID : base
    }

    // MARK: - Filter Bar

    private var trimmedFilter: String {
        filterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField(String(localized: "Filter chat info…"), text: $filterText)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($isFilterFocused)
            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "Clear filter"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }

    // MARK: - Filtered Collections

    private var filteredMembers: [Member] {
        guard !trimmedFilter.isEmpty else { return info.members }
        return info.members.filter { member in
            member.name.localizedCaseInsensitiveContains(trimmedFilter)
                || member.userID.localizedCaseInsensitiveContains(trimmedFilter)
                || member.identifiers.contains { $0.localizedCaseInsensitiveContains(trimmedFilter) }
        }
    }

    private var filteredFiles: [Event] {
        guard !trimmedFilter.isEmpty else { return info.sharedFiles }
        return info.sharedFiles.filter { event in
            Self.eventBody(event).localizedCaseInsensitiveContains(trimmedFilter)
        }
    }

    private var mediaItems: [Event] {
        ChatInfoPresentation.sharedMediaEvents(info.sharedMedia)
    }

    private var deduplicatedLinks: [RoomLink] {
        RoomLink.deduplicated(info.sharedLinks)
    }

    private var filteredLinks: [RoomLink] {
        guard !trimmedFilter.isEmpty else { return deduplicatedLinks }
        return deduplicatedLinks.filter { link in
            link.url.localizedCaseInsensitiveContains(trimmedFilter)
                || link.displayDomain.localizedCaseInsensitiveContains(trimmedFilter)
        }
    }

    private var filteredBookmarks: [MessageHit] {
        guard !trimmedFilter.isEmpty else { return bookmarks }
        return bookmarks.filter { hit in
            hit.snippet.localizedCaseInsensitiveContains(trimmedFilter)
                || hit.senderName.localizedCaseInsensitiveContains(trimmedFilter)
        }
    }

    // MARK: - Participants Section

    private var participantsSection: some View {
        ChatInfoSection(
            title: String(localized: "Participants"),
            count: filteredMembers.count,
            isExpanded: $participantsExpanded
        ) {
            LazyVStack(alignment: .leading, spacing: 6) {
                if info.features.canInvite {
                    // A routine action: plain label text, not the accent (see RoutineLinkButtonStyle).
                    Button(action: onAddParticipants) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Add Participants…"))
                        }
                        .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.routineLink)
                    .padding(.bottom, 2)
                }

                ForEach(filteredMembers, id: \.userID) { member in
                    let participantName = Self.participantDisplayName(for: member)
                    let displayIdentifiers = ContactsBridge.displayableIdentifiers(member.identifiers)
                    Button {
                        onSelectMember(member)
                    } label: {
                        HStack(spacing: 8) {
                            AvatarView(
                                path: member.avatarPath,
                                initials: Self.initials(of: member.name.isEmpty ? participantName : member.name),
                                seed: member.name.isEmpty ? participantName : member.name,
                                size: 30
                            )
                            .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(participantName)
                                    .font(.callout)
                                    .lineLimit(1)
                                if let firstID = displayIdentifiers.first {
                                    Text(verbatim: ContactsBridge.displayIdentifier(firstID))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            if member.isBot {
                                ChatInfoBadge(text: String(localized: "Bot"))
                            }
                            if ChatInfoPresentation.showsAdminBadge(for: member, in: info.members) {
                                ChatInfoBadge(text: String(localized: "Admin"))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        ParticipantContextMenu(
                            member: member,
                            features: info.features,
                            onMessage: { onMessageMember(member) },
                            onToggleAdmin: { makeAdmin in onToggleMemberAdmin(member, makeAdmin) },
                            onRemove: { onRemoveMember(member) },
                            onCopyUserID: { onCopyMemberID(member) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        ChatInfoSection(
            title: String(localized: "Pinned"),
            count: info.pinnedEventIDs.count,
            isExpanded: $pinnedExpanded
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(info.pinnedEventIDs, id: \.self) { eventID in
                    Button {
                        onSelectEvent(eventID)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Pinned message"))
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Shared Media Section

    private var mediaSection: some View {
        ChatInfoSection(
            title: String(localized: "Shared Media"),
            count: mediaItems.count,
            isExpanded: $mediaExpanded,
            onSeeAll: {
                openWindow(
                    id: WindowID.mediaViewer,
                    value: MediaViewerTarget(roomID: info.roomID, tab: .media)
                )
            }
        ) {
            let columns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 4), count: 3)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(mediaItems.prefix(9), id: \.eventID) { event in
                    ChatInfoMediaTile(
                        event: event,
                        sender: ChatInfoPresentation.mediaSender(for: event, members: info.members)
                    ) {
                        onSelectEvent(event.eventID)
                    }
                }
            }
        }
    }

    // MARK: - Files Section

    private var filesSection: some View {
        ChatInfoSection(
            title: String(localized: "Files"),
            count: filteredFiles.count,
            isExpanded: $filesExpanded,
            onSeeAll: {
                openWindow(
                    id: WindowID.mediaViewer,
                    value: MediaViewerTarget(roomID: info.roomID, tab: .docs)
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(filteredFiles, id: \.eventID) { event in
                    Button {
                        onSelectEvent(event.eventID)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.secondary)
                            Text(verbatim: Self.eventBody(event))
                                .font(.callout)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Links Section

    private var linksSection: some View {
        ChatInfoSection(
            title: String(localized: "Links"),
            count: filteredLinks.count,
            isExpanded: $linksExpanded,
            onSeeAll: {
                openWindow(
                    id: WindowID.mediaViewer,
                    value: MediaViewerTarget(roomID: info.roomID, tab: .links)
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(filteredLinks) { link in
                    Button {
                        onSelectEvent(link.eventID)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: link.displayDomain)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(verbatim: link.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Bookmarks Section

    private var bookmarksSection: some View {
        ChatInfoSection(
            title: String(localized: "Bookmarks"),
            count: filteredBookmarks.count,
            isExpanded: $bookmarksExpanded
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(filteredBookmarks, id: \.eventID) { hit in
                    Button {
                        onSelectEvent(hit.eventID)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "bookmark.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: hit.senderName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(verbatim: hit.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Security & Disappearing Messages

    private var disappearingSummary: String {
        let ms = info.disappearingMS > 0
            ? info.disappearingMS
            : (info.features.currentTimer?.timerMS ?? 0)
        guard ms > 0 else { return String(localized: "Off") }
        return VitruvianCourierCore.MessageActions.duration(ms)
    }

    private var securityAndTimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: info.encrypted ? "lock.fill" : "lock.open")
                    .foregroundStyle(info.encrypted ? .green : .secondary)
                    .frame(width: 16)
                Text(info.encrypted ? String(localized: "Encrypted") : String(localized: "Not end-to-end encrypted"))
                    .font(.callout)
                Spacer(minLength: 0)
            }

            if info.features.disappearing != nil || info.disappearingMS > 0 || info.features.currentTimer != nil {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(String(localized: "Disappearing Messages"))
                        .font(.callout)
                    Spacer(minLength: 4)
                    if !timerChoices.isEmpty {
                        Menu(disappearingSummary) {
                            DisappearingItems(choices: timerChoices, set: onSelectTimer)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    } else {
                        Text(disappearingSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let readAloud {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(String(localized: "Read Aloud on Vitruvian Speaker"))
                            .font(.callout)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    // On its own line under the title, so the title never wraps mid-word in the narrow pane.
                    HStack(spacing: 8) {
                        Spacer().frame(width: 16)
                        Picker(
                            String(localized: "Read Aloud on Vitruvian Speaker"),
                            selection: Binding(get: { readAloud }, set: onSelectReadAloud)
                        ) {
                            ForEach(ChatReadAloud.settable, id: \.rawValue) { choice in
                                Text(choice.displayTitle).tag(choice)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    Text(String(localized: "Muted chats are never read aloud."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24)
                }
            }
        }
    }

    // MARK: - Actions Section (Reload & Export Chat)

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let onSummarizeChat {
                Button(action: {
                    if isAIAvailable {
                        onSummarizeChat()
                    } else {
                        onOpenAISettings?()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.redaction")
                            .frame(width: 16)
                        Text(String(localized: "Summarize Chat"))
                            .font(.callout)
                            .foregroundStyle(isAIAvailable ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isAIAvailable && onOpenAISettings == nil)
                .help(isAIAvailable ? "" : String(localized: "Set up AI in Settings"))
            }

            Button(action: onRefresh) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16)
                    Text(String(localized: "Reload Chat Details"))
                        .font(.callout)
                    Spacer(minLength: 0)
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            if info.isDirect, let onMergeChat {
                Button(action: onMergeChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.merge")
                            .frame(width: 16)
                        Text(String(localized: "Merge with Another Chat…"))
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                openWindow(
                    id: WindowID.chatTheme,
                    value: ChatThemeWindowTarget(roomID: info.roomID, chatTitle: info.name)
                )
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette")
                        .frame(width: 16)
                    Text(String(localized: "Chat Theme…"))
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: promptExportChat) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 16)
                    Text(String(localized: "Export Chat…"))
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Destructive Actions Section

    // Destructive actions: system red (never the accent, which can be any colour) and a leading symbol, so they
    // differ from accent-coloured controls by shape as well as colour.
    private var destructiveActionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if !info.isDirect, info.features.canLeave {
                Button(role: .destructive, action: onLeaveGroup) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .frame(width: 16)
                        Text(String(localized: "Leave Group…"))
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if info.features.canDelete {
                Button(role: .destructive, action: onDeleteChat) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .frame(width: 16)
                        Text(String(localized: "Delete Chat…"))
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(role: .destructive, action: onReportSpam) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.bubble")
                        .frame(width: 16)
                    Text(String(localized: "Report as Spam…"))
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Presents `NSSavePanel` in the view only and hands the chosen URL to `onExport`.
    private func promptExportChat() {
        let baseName = info.name.isEmpty ? "chat-export" : info.name.replacingOccurrences(of: "/", with: "-")
        guard let url = AppLockGate.shared.runSavePanel(action: .export, configure: { panel in
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "\(baseName).txt"
            panel.canCreateDirectories = true
        }) else {
            return
        }
        onExport(url)
    }

    private static func eventBody(_ event: Event) -> String {
        if case let .object(dict) = event.content, case let .string(body)? = dict["body"] {
            return body
        }
        return event.eventID
    }
}

// MARK: - Supporting Views

private struct ChatInfoSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    var onSeeAll: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: "\(count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text(String(localized: "See All"))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.routineLink)
                }
            }

            if isExpanded {
                content()
                    .padding(.leading, 4)
            }
        }
    }
}

private struct ObservedChatInfoQuickActionsRow: View {
    let roomID: String
    @ObservedObject var inbox: InboxModel
    let fallbackMuted: Bool
    let fallbackPinned: Bool
    let onToggleMute: () -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void
    let onRemind: () -> Void
    let onSearchInChat: () -> Void

    var body: some View {
        let row = inbox.row(of: roomID)
        ChatInfoQuickActionsRow(
            isMuted: row?.muted ?? fallbackMuted,
            isPinned: row?.pinned ?? fallbackPinned,
            onToggleMute: onToggleMute,
            onTogglePin: onTogglePin,
            onArchive: onArchive,
            onRemind: onRemind,
            onSearchInChat: onSearchInChat
        )
    }
}

private struct ChatInfoQuickActionsRow: View {
    let isMuted: Bool
    let isPinned: Bool
    let onToggleMute: () -> Void
    let onTogglePin: () -> Void
    let onArchive: () -> Void
    let onRemind: () -> Void
    let onSearchInChat: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ChatInfoQuickActionButton(
                symbol: isMuted ? "bell.slash" : "bell",
                title: isMuted ? String(localized: "Unmute") : String(localized: "Mute"),
                action: onToggleMute
            )
            ChatInfoQuickActionButton(
                symbol: isPinned ? "pin.slash" : "pin",
                title: isPinned ? String(localized: "Unpin") : String(localized: "Pin"),
                action: onTogglePin
            )
            ChatInfoQuickActionButton(
                symbol: "archivebox",
                title: String(localized: "Archive"),
                action: onArchive
            )
            ChatInfoQuickActionButton(
                symbol: "alarm",
                title: String(localized: "Remind…"),
                action: onRemind
            )
            ChatInfoQuickActionButton(
                symbol: "magnifyingglass",
                title: String(localized: "Search"),
                action: onSearchInChat
            )
        }
        .frame(maxWidth: .infinity)
    }
}

struct ChatInfoQuickActionProbeKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String, NSRect?) -> Void)? = nil
}

extension EnvironmentValues {
    var chatInfoQuickActionProbe: (@MainActor (String, NSRect?) -> Void)? {
        get { self[ChatInfoQuickActionProbeKey.self] }
        set { self[ChatInfoQuickActionProbeKey.self] = newValue }
    }
}

private struct QuickActionWindowRectProbe: NSViewRepresentable {
    let title: String
    let report: @MainActor (String, NSRect?) -> Void

    final class ProbeView: NSView {
        var title: String = ""
        var report: (@MainActor (String, NSRect?) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            publish()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            publish()
        }

        func publish() {
            guard window != nil, !bounds.isEmpty else { return }
            report?(title, convert(bounds, to: nil))
        }
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.title = title
        view.report = report
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        if nsView.title != title {
            let previous = nsView.title
            nsView.report?(previous, nil)
            nsView.title = title
        }
        nsView.report = report
        nsView.publish()
    }

    static func dismantleNSView(_ nsView: ProbeView, coordinator: ()) {
        nsView.report?(nsView.title, nil)
    }
}

private struct ChatInfoQuickActionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @Environment(\.chatInfoQuickActionProbe) private var quickActionProbe
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .frame(height: 18)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, 6)
            .frame(minWidth: 44, maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .background {
            if let quickActionProbe {
                QuickActionWindowRectProbe(title: title, report: quickActionProbe)
            }
        }
    }
}

private struct ChatInfoBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

private struct ChatInfoMediaTile: View {
    let event: Event
    let sender: ChatInfoPresentation.MediaSender?
    let action: () -> Void
    @State private var image: CGImage?

    private var isVideo: Bool {
        if case let .object(dict) = event.content, case let .string(msgtype)? = dict["msgtype"] {
            return msgtype == "m.video"
        }
        return false
    }

    private var thumbnailSourceKey: String {
        "\(event.thumbnailPath ?? "")|\(event.mediaPath)"
    }

    var body: some View {
        Button(action: action) {
            Color.primary.opacity(0.07)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                    } else {
                        Image(systemName: isVideo ? "film" : "photo")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let sender {
                        AvatarView(
                            path: sender.avatarPath,
                            initials: sender.initials,
                            seed: sender.name.isEmpty ? "?" : sender.name,
                            size: 16
                        )
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.75), lineWidth: 1))
                        .padding(4)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .task(id: thumbnailSourceKey) {
            if let thumbPath = event.thumbnailPath, !thumbPath.isEmpty,
               let loaded = await ThumbnailLoader.shared.thumbnail(atPath: thumbPath)?.image {
                image = loaded
                return
            }
            guard !event.mediaPath.isEmpty else {
                image = nil
                return
            }
            image = await ThumbnailLoader.shared.thumbnail(atPath: event.mediaPath)?.image
        }
    }
}

/// Standalone `WindowGroup(id: "chat-info", for: String.self)` scene content.
struct ChatInfoWindow: View {
    let roomID: String
    @ObservedObject var conversation: ConversationModel
    var inbox: InboxModel? = nil
    @State private var loadedInfo: RoomInfoResult?
    @State private var loadedBookmarks: [MessageHit] = []
    @State private var loadedRow: InboxRow?
    @State private var isRefreshing = false

    private var resolvedInbox: InboxModel? {
        inbox ?? conversation.inbox
    }

    private var effectiveInfo: RoomInfoResult? {
        if conversation.chatInfo?.roomID == roomID {
            return conversation.chatInfo
        }
        return loadedInfo
    }

    private var effectiveBookmarks: [MessageHit] {
        if conversation.roomID == roomID && !conversation.chatInfoBookmarks.isEmpty {
            return conversation.chatInfoBookmarks
        }
        return loadedBookmarks
    }

    var body: some View {
        Group {
            if let info = effectiveInfo {
                let row = resolvedInbox?.row(of: info.roomID) ?? conversation.chatRow(for: info.roomID) ?? loadedRow
                ChatInfoPane(
                    info: info,
                    bookmarks: effectiveBookmarks,
                    isRefreshing: isRefreshing,
                    isMuted: row?.muted ?? false,
                    isPinned: row?.pinned ?? false,
                    showsCloseButton: false,
                    now: { conversation.currentTime },
                    timerChoices: conversation.roomID == roomID ? conversation.timerChoices : [],
                    onSelectTimer: { choice in
                        Task { await conversation.setTimer(choice) }
                    },
                    onEditTitleAndAvatar: {
                        Task { await conversation.beginEditChat(info: info, roomID: info.roomID) }
                    },
                    onAddParticipants: {
                        Task { await conversation.beginAddParticipants(info: info) }
                    },
                    onMessageMember: { member in
                        Task { _ = await conversation.messageParticipant(userID: member.userID, in: info.roomID) }
                    },
                    onToggleMemberAdmin: { member, makeAdmin in
                        Task {
                            _ = await conversation.setParticipantAdmin(
                                userID: member.userID,
                                isAdmin: makeAdmin,
                                in: info.roomID
                            )
                        }
                    },
                    onRemoveMember: { member in
                        conversation.requestRemoveParticipant(member, info: info)
                    },
                    onSelectEvent: { eventID in
                        conversation.openEvent(eventID, in: info.roomID)
                    },
                    onRefresh: {
                        Task { await refresh(force: true) }
                    },
                    onExport: { url in
                        Task {
                            do {
                                let count = try await conversation.exportChat(roomID: info.roomID, to: url)
                                conversation.onToast(String(localized: "Exported \(count) messages"))
                            } catch {
                                conversation.onToast(
                                    EngineErrorText.text(
                                        for: error,
                                        fallback: String(localized: "Couldn’t export the chat.")
                                    )
                                )
                            }
                        }
                    },
                    onLeaveGroup: {
                        conversation.requestLeaveGroup(info: info, roomID: info.roomID)
                    },
                    onDeleteChat: {
                        conversation.requestDeleteChat(info: info, roomID: info.roomID)
                    },
                    onReportSpam: {
                        Task { await conversation.beginReportSpam(info: info, roomID: info.roomID) }
                    },
                    isAIAvailable: conversation.composer.aiProvider.isAvailable,
                    onSummarizeChat: {
                        conversation.summarizeChat()
                    },
                    onOpenAISettings: {
                        conversation.onOpenAISettings()
                    },
                    onToggleMute: {
                        if !conversation.performToggleMute(info.roomID), let resolvedInbox {
                            Task { await resolvedInbox.toggleMute(ids: [info.roomID]) }
                        }
                    },
                    onTogglePin: {
                        if !conversation.performTogglePin(info.roomID), let resolvedInbox {
                            Task { await resolvedInbox.togglePin(ids: [info.roomID]) }
                        }
                    },
                    onArchive: {
                        if !conversation.performToggleArchive(info.roomID), let resolvedInbox {
                            let rows = resolvedInbox.row(of: info.roomID).map { [$0] }
                                ?? resolvedInbox.targetRows([info.roomID])
                            Task { await resolvedInbox.archive(ChatInfoPresentation.shouldArchive(rows), ids: [info.roomID]) }
                        }
                    },
                    onRemind: {
                        if !conversation.performRemindLater(info.roomID),
                           let resolvedInbox,
                           !resolvedInbox.isLocked,
                           resolvedInbox.isEntitled(.reminders) {
                            resolvedInbox.customReminder = ReminderRequest(ids: [info.roomID])
                        }
                    },
                    onSearchInChat: {
                        conversation.onSearchInChat(info.roomID)
                    },
                    inbox: resolvedInbox
                )
            } else {
                ProgressView()
                    .frame(minWidth: 280, minHeight: 320)
            }
        }
        .frame(minWidth: 280, idealWidth: 340, minHeight: 480)
        .task(id: roomID) {
            await refresh(force: false)
        }
        .onChange(of: resolvedInbox?.rows ?? []) { _, _ in
            Task {
                await refreshRow()
            }
        }
    }

    private func refresh(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        let (info, bookmarks) = await conversation.fetchChatInfo(for: roomID, force: force)
        if let info {
            loadedInfo = info
        }
        loadedBookmarks = bookmarks
        await refreshRow()
    }

    private func refreshRow() async {
        guard let resolvedInbox else { return }
        if let row = resolvedInbox.row(of: roomID) {
            if loadedRow != row {
                loadedRow = row
            }
            return
        }
        if let fetched = await resolvedInbox.lookUpRow(roomID), loadedRow != fetched {
            loadedRow = fetched
        }
    }
}

/// Chat Info's header: its title, Open in Separate Window and Close. A strip at the pane's top, or with glass, the
/// pane's item in the window's toolbar (`inToolbar`).
struct ChatInfoHeader: View {
    let roomID: String
    var showsCloseButton = true
    var onClose: () -> Void = {}
    var inToolbar: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        PaneHeader(title: String(localized: "Chat Info"), inToolbar: inToolbar) {
            Button {
                openWindow(id: WindowID.chatInfo, value: roomID)
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .help(String(localized: "Open Chat Info in Separate Window"))
            .accessibilityLabel(String(localized: "Open Chat Info in Separate Window"))
            if showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .help(String(localized: "Close Chat Info (⌘⇧I)"))
                .accessibilityLabel(String(localized: "Close chat info"))
            }
        }
    }
}
