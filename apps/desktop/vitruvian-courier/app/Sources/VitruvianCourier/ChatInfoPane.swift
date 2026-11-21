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
///   - Topics in their own rounded, labelled boxes: Participants (with `Admin` / `Bot` badges and **Add
///     Participants** button), Shared (the newest four photos, videos and links, and Show All), Files, Pinned,
///     Bookmarks (`search.query` with `sections: [.bookmarks]`, for this chat), Contact, Notes, Labels,
///     Notifications, Privacy (encryption, disappearing messages), Read Aloud and Tools (Summarize, Chat Theme,
///     **Export Chat…** (`NSSavePanel` in view only), and a More menu with **Reload Chat Details** and Merge).
public struct ChatInfoPane: View {
    public let info: RoomInfoResult
    public let bookmarks: [MessageHit]
    public var isRefreshing: Bool = false
    public var isMuted: Bool = false
    public var isPinned: Bool = false
    public var showsCloseButton: Bool = true
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
    /// My own picture, for my Participants row and my Shared Media badges when the member list has none for me.
    public var selfAvatarPath: String = ""
    /// Where the chats' private notes are kept (on this Mac only); nil is the app's own store.
    public var notesStore: ChatNotesStore? = nil
    /// The notification settings the per-chat sound is kept in; nil takes them from `inbox`. With neither, the
    /// Notification sound row is left out.
    public var notificationPreferences: NotificationPreferences? = nil
    /// The labels, for the Labels row; nil takes them from the environment (`chatInfoSpaces`).
    public var labelSpaces: SpacesModel? = nil

    @Environment(\.openWindow) private var openWindow
    @Environment(\.chatInfoSpaces) private var environmentSpaces
    @State private var participantsExpanded = true
    @State private var pinnedExpanded = true
    @State private var sharedExpanded = true
    @State private var filesExpanded = true
    @State private var bookmarksExpanded = true
    @State private var contactExpanded = true
    @State private var labelsExpanded = true
    @State private var notesExpanded = true

    public init(
        info: RoomInfoResult,
        bookmarks: [MessageHit] = [],
        isRefreshing: Bool = false,
        isMuted: Bool = false,
        isPinned: Bool = false,
        showsCloseButton: Bool = true,
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
        headerInToolbar: Bool = false,
        selfAvatarPath: String = "",
        notesStore: ChatNotesStore? = nil,
        notificationPreferences: NotificationPreferences? = nil,
        labelSpaces: SpacesModel? = nil
    ) {
        self.selfAvatarPath = selfAvatarPath
        self.notesStore = notesStore
        self.notificationPreferences = notificationPreferences
        self.labelSpaces = labelSpaces
        self.headerInToolbar = headerInToolbar
        self.inbox = inbox
        self.info = info
        self.bookmarks = bookmarks
        self.isRefreshing = isRefreshing
        self.isMuted = isMuted
        self.isPinned = isPinned
        self.showsCloseButton = showsCloseButton
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
                    if !info.isDirect {
                        participantsSection
                    }
                    sharedSection
                    if !info.sharedFiles.isEmpty {
                        filesSection
                    }
                    if !info.pinnedEventIDs.isEmpty {
                        pinnedSection
                    }
                    bookmarksSection
                    if info.isDirect {
                        contactSection
                    }
                    notesSection
                    labelsSection
                    notificationSoundSection
                    privacySection
                    readAloudSection
                    toolsSection
                    destructiveActionsSection
                }
                // The header's inset, so the sections line up under its title.
                .padding(PaneHeaderMetrics.inset)
            }
            .courierScrollEdges()
        }
        .frame(minWidth: 280)
        .courierSurface(.sidePane)
    }

    // MARK: - Notes

    private var notesSection: some View {
        ChatInfoSection(
            title: String(localized: "Notes"),
            count: nil,
            isExpanded: $notesExpanded
        ) {
            ChatInfoNotesField(roomID: info.roomID, store: notesStore)
        }
    }

    // MARK: - Labels

    @ViewBuilder
    private var labelsSection: some View {
        if let spaces = labelSpaces ?? environmentSpaces, let inbox {
            ObservedChatInfoLabelsSection(
                roomID: info.roomID,
                inbox: inbox,
                spaces: spaces,
                isExpanded: $labelsExpanded
            )
        }
    }

    // MARK: - Notification sound

    @ViewBuilder
    private var notificationSoundSection: some View {
        if let preferences = notificationPreferences ?? inbox?.preferences.notifications {
            ChatInfoSoundRow(
                roomID: info.roomID, preferences: preferences,
                isDirect: info.isDirect, network: info.network, accountID: info.accountID
            )
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
                // Their phone number and username are in the Contact box.
                if let localTime = Self.localTimeText(for: member.tz, now: now(), locale: .current) {
                    Label(localTime, systemImage: "clock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if !info.isDirect {
                Text(
                    info.members.count == 1
                        ? String(localized: "1 member")
                        : String(localized: "\(info.members.count) members")
                )
                .font(.callout)
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
            AvatarView(path: displayAvatar, initials: Self.initials(of: info.name), identity: info.avatarIdentity, size: 56)
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
            AvatarView(path: "", initials: Self.initials(of: info.name), identity: info.avatarIdentity, size: 56)
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
        let base = NetworkTag.stripped(member.name.trimmingCharacters(in: .whitespacesAndNewlines))
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

    // MARK: - Collections

    private var filteredMembers: [Member] { info.members }

    private var filteredFiles: [Event] { info.sharedFiles }

    /// My picture: the pane's `selfAvatarPath`, else one the chat's own info holds.
    private var ownAvatarPath: String {
        selfAvatarPath.isEmpty ? ChatInfoPresentation.ownAvatarPath(in: info) : selfAvatarPath
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
                                path: ChatInfoPresentation.participantAvatarPath(for: member, ownAvatarPath: ownAvatarPath),
                                initials: Self.initials(of: member.name.isEmpty ? participantName : member.name),
                                identity: member.avatarIdentity,
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

    // MARK: - Shared Section

    private var sharedTiles: [ChatInfoSharedTile] {
        ChatInfoShared.tiles(media: info.sharedMedia, links: info.sharedLinks)
    }

    private var sharedCount: Int {
        ChatInfoShared.count(media: info.sharedMedia, links: info.sharedLinks)
    }

    /// Show All opens the viewer on the tab of the first tile, so the links in Shared are always in reach.
    private var sharedViewerTab: MediaViewerModel.Tab {
        ChatInfoShared.viewerTab(media: info.sharedMedia, links: info.sharedLinks)
    }

    private var sharedSection: some View {
        ChatInfoSection(
            title: String(localized: "Shared"),
            count: sharedCount == 0 ? nil : sharedCount,
            countIsLowerBound: info.sharedCapped == true,
            isExpanded: $sharedExpanded,
            onSeeAll: sharedCount > 0 ? { showAllShared() } : nil,
            seeAllTitle: String(localized: "Show All")
        ) {
            if sharedTiles.isEmpty {
                ChatInfoEmptyLine(text: String(localized: "Photos, videos and links shared in this chat appear here."))
            } else {
                let columns = Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8), count: 2)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(sharedTiles) { tile in
                        switch tile {
                        case let .media(event):
                            ChatInfoMediaTile(
                                event: event,
                                sender: ChatInfoPresentation.mediaSender(
                                    for: event, members: info.members, ownAvatarPath: ownAvatarPath
                                )
                            ) {
                                onSelectEvent(event.eventID)
                            }
                        case let .link(link):
                            ChatInfoLinkTile(link: link, members: info.members, ownAvatarPath: ownAvatarPath) { onSelectEvent(link.eventID) }
                        }
                    }
                }
            }
        }
    }

    private func showAllShared() {
        openWindow(
            id: WindowID.mediaViewer,
            value: MediaViewerTarget(roomID: info.roomID, tab: sharedViewerTab)
        )
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

    // MARK: - Bookmarks Section

    private var bookmarkRows: [ChatInfoBookmarkRow] {
        ChatInfoPresentation.bookmarkRows(bookmarks)
    }

    private var bookmarksSection: some View {
        ChatInfoSection(
            title: String(localized: "Bookmarks"),
            count: bookmarkRows.isEmpty ? nil : bookmarkRows.count,
            isExpanded: $bookmarksExpanded
        ) {
            if bookmarkRows.isEmpty {
                ChatInfoEmptyLine(text: String(localized: "Bookmarked messages appear here."))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(bookmarkRows) { row in
                        Button {
                            onSelectEvent(row.eventID)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "bookmark.fill")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(verbatim: row.sender)
                                            .font(.callout.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Text(verbatim: ChatInfoPresentation.bookmarkDateText(ts: row.ts, now: now()))
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Text(verbatim: row.snippet)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Jump to this message"))
                        .chatInfoRowProbe("bookmark:\(row.sender):\(row.snippet)")
                    }
                }
            }
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        ChatInfoSection(
            title: String(localized: "Contact"),
            count: nil,
            isExpanded: $contactExpanded
        ) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ChatInfoPresentation.contactRows(for: directOtherMember)) { row in
                    ChatInfoContactRowView(row: row)
                }
                // The chat's name on this Mac only: the inbox, the header and the notifications all show it.
                Button(action: onEditTitleAndAvatar) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Edit name…"))
                    }
                    .font(.callout.weight(.medium))
                }
                .buttonStyle(.routineLink)
                .help(String(localized: "Give this person a name of your own. It is kept on this Mac only."))
            }
        }
    }

    // MARK: - Privacy: encryption and disappearing messages

    private var privacySection: some View {
        let encryption = ChatEncryption.of(info)
        return ChatInfoSection(title: String(localized: "Privacy"), count: nil, isExpanded: nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: encryption.symbolName)
                        .foregroundStyle(encryption.isEndToEnd ? Color.green : Color.secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(encryption.title)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = encryption.note {
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .chatInfoRowProbe("encryption:\(encryption.title)")

                if let row = ChatInfoPresentation.disappearingRow(for: info) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: row.isHistorySetting ? "clock.arrow.circlepath" : "timer")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(row.title)
                                .font(.body)
                            Spacer(minLength: 4)
                            if !row.isHistorySetting, !timerChoices.isEmpty {
                                Menu(row.value) {
                                    DisappearingItems(choices: timerChoices, set: onSelectTimer)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            } else {
                                Text(row.value)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chatInfoRowProbe("disappearing:\(row.title)=\(row.value)")
                        Text(row.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Read Aloud

    @ViewBuilder
    private var readAloudSection: some View {
        if let readAloud {
            ChatInfoSection(
                title: String(localized: "Read Aloud on Vitruvian Speaker"), count: nil, isExpanded: nil
            ) {
                VStack(alignment: .leading, spacing: 4) {
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
                    Text(readAloud.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        ChatInfoSection(title: String(localized: "Tools"), count: nil, isExpanded: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if let onSummarizeChat {
                    toolButton(
                        symbol: "text.redaction", title: String(localized: "Summarize Chat"),
                        dimmed: !isAIAvailable
                    ) {
                        if isAIAvailable {
                            onSummarizeChat()
                        } else {
                            onOpenAISettings?()
                        }
                    }
                    .disabled(!isAIAvailable && onOpenAISettings == nil)
                    .help(isAIAvailable ? "" : String(localized: "Set up AI in Settings"))
                }

                toolButton(symbol: "paintpalette", title: String(localized: "Chat Theme…")) {
                    openWindow(
                        id: WindowID.chatTheme,
                        value: ChatThemeWindowTarget(roomID: info.roomID, chatTitle: info.name)
                    )
                }

                toolButton(symbol: "square.and.arrow.up", title: String(localized: "Export Chat…"), action: promptExportChat)

                // The repair tools, out of the way.
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Menu {
                        Button(action: onRefresh) {
                            Label(String(localized: "Reload Chat Details"), systemImage: "arrow.clockwise")
                        }
                        .disabled(isRefreshing)
                        if info.isDirect, let onMergeChat {
                            Button(action: onMergeChat) {
                                Label(String(localized: "Merge with Another Chat…"), systemImage: "arrow.triangle.merge")
                            }
                        }
                    } label: {
                        Label(String(localized: "More"), systemImage: "ellipsis.circle")
                            .font(.callout.weight(.medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel(String(localized: "More"))
                    .accessibilityIdentifier("chat-info-more")
                    .help(String(localized: "More: Reload Chat Details, Merge with Another Chat…"))
                }
            }
        }
    }

    private func toolButton(
        symbol: String, title: String, dimmed: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                Text(title)
                    .font(.body)
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// A topic of Chat Info in a rounded box with its name above it. With `isExpanded` the box folds up from its title;
/// without, it stays open.
private struct ChatInfoSection<Content: View>: View {
    let title: String
    /// The number in the badge by the title; nil for a section with nothing to count (Notes).
    let count: Int?
    /// The count is "at least" (a chat with more than the pane was given): it reads "50+".
    var countIsLowerBound: Bool = false
    let isExpanded: Binding<Bool>?
    var onSeeAll: (() -> Void)? = nil
    var seeAllTitle: String = String(localized: "See All")
    @ViewBuilder let content: () -> Content

    private var open: Bool { isExpanded?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let isExpanded {
                    Button {
                        isExpanded.wrappedValue.toggle()
                    } label: {
                        titleRow(showsChevron: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityValue(open ? String(localized: "Expanded") : String(localized: "Collapsed"))
                } else {
                    titleRow(showsChevron: false)
                }

                if let onSeeAll {
                    Button(action: onSeeAll) {
                        HStack(spacing: 3) {
                            Text(seeAllTitle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.routineLink)
                }
            }

            if open {
                content()
            }
        }
        .padding(ChatInfoBoxMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ChatInfoBoxMetrics.cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ChatInfoBoxMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func titleRow(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            if showsChevron {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
            }
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let count {
                Text(verbatim: ChatInfoShared.countText(count, capped: countIsLowerBound))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// The one padding and corner every Chat Info box shares.
private enum ChatInfoBoxMetrics {
    static let padding: CGFloat = 12
    static let cornerRadius: CGFloat = 10
}

/// What an empty box says, in the same secondary type as the rest of the pane.
private struct ChatInfoEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .chatInfoRowProbe("empty:\(text)")
    }
}

/// One of the Contact box's lines: what it is and its value, which a click copies.
private struct ChatInfoContactRowView: View {
    let row: ChatContactRow
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(row.value, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 52, alignment: .leading)
                Text(verbatim: row.value)
                    .font(.body)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(copied ? String(localized: "Copied") : String(localized: "Copy \(row.label)"))
        .accessibilityLabel(String(localized: "\(row.label): \(row.value)"))
        .accessibilityHint(String(localized: "Copies it"))
        .chatInfoRowProbe("contact:\(row.label)=\(row.value)")
    }
}

/// A link in the Shared box: the preview's picture when it has one, the page's title (two lines), then who shared it
/// and the site on one line. With no preview at all, a globe and the site.
private struct ChatInfoLinkTile: View {
    let link: RoomLink
    let card: ChatInfoLinkCard
    let action: () -> Void
    @State private var image: CGImage?

    init(link: RoomLink, members: [Member], ownAvatarPath: String, action: @escaping () -> Void) {
        self.link = link
        card = ChatInfoLinkCard(link: link, members: members, ownAvatarPath: ownAvatarPath)
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                if card.imagePath != nil {
                    Color.primary.opacity(0.07)
                        .overlay {
                            if let image {
                                Image(decorative: image, scale: 1)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                                    .clipped()
                            } else {
                                Image(systemName: card.symbolName)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if card.isFallback {
                    Image(systemName: card.symbolName)
                        .font(.title3)
                        .foregroundStyle(card.isMap ? Color.red : Color.secondary)
                        .padding(8)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let headline = card.headline {
                        Text(verbatim: headline)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(ChatInfoLinkCard.titleLineLimit)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 4) {
                        if let sender = card.sender {
                            AvatarView(path: sender.avatarPath, initials: sender.initials,
                                       identity: sender.identity, size: 14)
                                .frame(width: 14, height: 14)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                        }
                        // The site on one line, cut in the middle when long: never broken across lines ("usatoday.-com").
                        Text(verbatim: card.domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(ChatInfoLinkCard.domainLineLimit)
                            .truncationMode(.middle)
                            .allowsTightening(false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1, contentMode: .fit)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .task(id: card.imagePath ?? "") {
            guard let path = card.imagePath else {
                image = nil
                return
            }
            image = await ThumbnailLoader.shared.thumbnail(atPath: path)?.image
        }
        .help(link.url)
        .contextMenu {
            Button(String(localized: "Open Link")) {
                if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
            }
            Button(String(localized: "Copy Link")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url, forType: .string)
            }
        }
        .accessibilityLabel(String(localized: "Link: \(link.cardTitle), \(link.displayDomain)"))
        .chatInfoRowProbe("link:\(link.url)")
    }
}

#if DEBUG
/// Tells a view test which Chat Info rows were drawn (`name`), without relying on the accessibility tree. Not in
/// release builds.
struct ChatInfoRowProbeKey: EnvironmentKey {
    static let defaultValue: (@MainActor (String) -> Void)? = nil
}

extension EnvironmentValues {
    var chatInfoRowProbe: (@MainActor (String) -> Void)? {
        get { self[ChatInfoRowProbeKey.self] }
        set { self[ChatInfoRowProbeKey.self] = newValue }
    }
}

private struct ChatInfoRowProbeModifier: ViewModifier {
    let name: () -> String
    @Environment(\.chatInfoRowProbe) private var probe

    func body(content: Content) -> some View {
        content.onAppear { probe?(name()) }
    }
}

extension View {
    fileprivate func chatInfoRowProbe(_ name: @autoclosure @escaping () -> String) -> some View {
        modifier(ChatInfoRowProbeModifier(name: name))
    }
}
#else
extension View {
    fileprivate func chatInfoRowProbe(_ name: @autoclosure @escaping () -> String) -> some View { self }
}
#endif

/// The environment's spaces (and so the labels), for a Chat Info pane built without them.
private struct ChatInfoSpacesKey: EnvironmentKey {
    static let defaultValue: SpacesModel? = nil
}

extension EnvironmentValues {
    var chatInfoSpaces: SpacesModel? {
        get { self[ChatInfoSpacesKey.self] }
        set { self[ChatInfoSpacesKey.self] = newValue }
    }
}

/// Reads the chat's labels live from the inbox, so adding or removing one shows at once.
private struct ObservedChatInfoLabelsSection: View {
    let roomID: String
    @ObservedObject var inbox: InboxModel
    @ObservedObject var spaces: SpacesModel
    @Binding var isExpanded: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let all = spaces.spaces.filter { $0.kind == .label }
        let assigned = inbox.row(of: roomID)?.labels ?? []
        ChatInfoLabelsSection(
            labels: all,
            assignedIDs: assigned,
            isExpanded: $isExpanded,
            onSet: { label, on in Task { await inbox.setLabel(label.labelID, on: on, ids: [roomID]) } },
            onNewLabel: { openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: [roomID])) }
        )
    }
}

/// The note for one chat. It reads and writes the shared store, so a second window on the chat shows the same text,
/// and it saves on a chat switch and when the pane goes away.
struct ChatInfoNotesField: View {
    let roomID: String
    @ObservedObject var store: ChatNotesStore

    init(roomID: String, store: ChatNotesStore? = nil) {
        self.roomID = roomID
        self.store = store ?? .shared
    }

    /// The text of this chat's note: read from and written to the store, which every window on the chat shares.
    var text: Binding<String> {
        Binding(get: { store.note(for: roomID) }, set: { store.setNote($0, for: roomID) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(String(localized: "Notes"), text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(3...10)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            .accessibilityIdentifier("chat-info-notes")
            .chatInfoRowProbe("notes:\(store.note(for: roomID))")
            Text(String(localized: "Only you can see this. It stays on this Mac."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .onChange(of: roomID) { _, _ in store.flush() }
        .onDisappear { store.flush() }
    }
}

/// Chat Info's Labels: this chat's labels as chips, and "Add to a Label" to change them.
struct ChatInfoLabelsSection: View {
    let labels: [Space]
    let assignedIDs: [Int64]
    @Binding var isExpanded: Bool
    let onSet: (Space, Bool) -> Void
    let onNewLabel: () -> Void

    private var assigned: [Space] { labels.filter { assignedIDs.contains($0.labelID) } }

    /// What ticking a label in the Add to a Label menu does: ticked puts it on the chat, unticked takes it off.
    func menuBinding(for label: Space) -> Binding<Bool> {
        Binding(get: { assignedIDs.contains(label.labelID) }, set: { onSet(label, $0) })
    }

    /// What the x on a label's chip does.
    func removeChip(_ label: Space) {
        onSet(label, false)
    }

    var body: some View {
        ChatInfoSection(title: String(localized: "Labels"), count: assigned.count, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !assigned.isEmpty {
                    ChatInfoChipFlow(spacing: 6) {
                        ForEach(assigned) { label in
                            HStack(spacing: 4) {
                                LabelIcon(color: label.color, icon: label.icon, size: 14)
                                Text(verbatim: label.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Button {
                                    removeChip(label)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "Remove label \(label.title)"))
                            }
                            .chatInfoRowProbe("chip:\(label.title)")
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
                Menu {
                    ForEach(labels) { label in
                        Toggle(label.title, isOn: menuBinding(for: label))
                    }
                    if !labels.isEmpty { Divider() }
                    Button(String(localized: "New Label…"), action: onNewLabel)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tag").foregroundStyle(.secondary)
                        Text(String(localized: "Add to a Label"))
                    }
                    .font(.callout.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("chat-info-add-label")
                .chatInfoRowProbe("add-label")
                .help(String(localized: "A label puts the chat in a space of its own, on this Mac."))
            }
        }
        .accessibilityIdentifier("chat-info-labels")
    }
}

/// Lays its children out in rows, starting a new row when one is full.
private struct ChatInfoChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}

/// Chat Info's Notifications box: this chat's own alert sound, or Default for the usual one, and what that means.
struct ChatInfoSoundRow: View {
    let roomID: String
    @ObservedObject var preferences: NotificationPreferences
    /// What the chat is, to name the sound Default stands for. Without them Default is shown as it is.
    var isDirect: Bool = true
    var network: String = ""
    var accountID: String = ""

    static func title(_ choice: NotificationSoundChoice) -> String {
        choice == .default ? String(localized: "Default") : NotificationsSettingsPane.soundLabel(choice)
    }

    private var chosen: NotificationSoundChoice { preferences.chatSound(for: roomID) ?? .default }

    private var resolvedDefault: NotificationSoundChoice {
        preferences.defaultSound(isDirect: isDirect, network: network, accountID: accountID)
    }

    /// The picker's names: "Default (Pop)" says which sound Default is now.
    func pickerTitle(_ choice: NotificationSoundChoice) -> String {
        ChatInfoPresentation.soundPickerTitle(
            choice, resolvedDefault: resolvedDefault, name: NotificationsSettingsPane.soundLabel
        )
    }

    var body: some View {
        ChatInfoSection(title: String(localized: "Notifications"), count: nil, isExpanded: nil) {
            VStack(alignment: .leading, spacing: 4) {
                // The info pane can be narrow: keep the label whole and move the picker under it when both don't fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        soundLabel
                        Spacer(minLength: 4)
                        soundPicker
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        soundLabel
                        soundPicker
                            .padding(.leading, 24)
                    }
                }
                Text(ChatInfoPresentation.soundExplanation(chosen: chosen))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)
            }
        }
        .accessibilityIdentifier("chat-info-sound")
        .chatInfoRowProbe("sound:\(preferences.chatSound(for: roomID)?.rawValue ?? "default")")
    }

    private var soundLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(String(localized: "Notification sound"))
                .font(.body)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var soundPicker: some View {
        Picker(
            String(localized: "Notification sound"),
            selection: Binding(
                get: { chosen },
                set: { preferences.setChatSound($0, for: roomID) }
            )
        ) {
            ForEach(NotificationSoundChoice.allCases, id: \.self) { choice in
                Text(pickerTitle(choice)).tag(choice)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
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
            // Remind… asks for a time, so it is "Remind…" to the pointer and to VoiceOver; the label under the icon is
            // "Remind", which is as short as its neighbours and fits the narrowest pane.
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

/// The type of the five quick-action labels: one size for all, so no label is smaller than its neighbours.
enum ChatInfoQuickActionMetrics {
    static let labelFont = Font.caption

    /// What is written under the icon for a button called `title`. "Remind…" asks for a time, so to the pointer and to
    /// VoiceOver it keeps its ellipsis; under the icon it is "Remind", as short as its neighbours.
    static func visibleLabel(for title: String) -> String {
        title == String(localized: "Remind…") ? String(localized: "Remind") : title
    }
}

private struct ChatInfoQuickActionButton: View {
    let symbol: String
    /// What the button is called to the pointer (its help), to VoiceOver and to tests.
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
                Text(ChatInfoQuickActionMetrics.visibleLabel(for: title))
                    .font(ChatInfoQuickActionMetrics.labelFont)
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
                            identity: sender.identity,
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
                    inbox: resolvedInbox,
                    selfAvatarPath: conversation.ownAvatarPath(for: info)
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
