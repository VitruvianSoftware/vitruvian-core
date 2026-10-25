// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
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
///     Encryption, Disappearing Messages, **Refresh Chat Info**, and **Export Chat…** (`NSSavePanel` in view only).
public struct ChatInfoPane: View {
    public let info: RoomInfoResult
    public let bookmarks: [MessageHit]
    public var isRefreshing: Bool = false
    public var showsCloseButton: Bool = true
    public var focusSearchTrigger: Int = 0
    public var now: () -> Date = Date.init
    public var timerChoices: [DisappearingChoice] = []
    public var onSelectTimer: (DisappearingChoice) -> Void = { _ in }
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
    public var onClose: () -> Void = {}

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
        showsCloseButton: Bool = true,
        focusSearchTrigger: Int = 0,
        now: @escaping () -> Date = Date.init,
        timerChoices: [DisappearingChoice] = [],
        onSelectTimer: @escaping (DisappearingChoice) -> Void = { _ in },
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
        onClose: @escaping () -> Void = {}
    ) {
        self.info = info
        self.bookmarks = bookmarks
        self.isRefreshing = isRefreshing
        self.showsCloseButton = showsCloseButton
        self.focusSearchTrigger = focusSearchTrigger
        self.now = now
        self.timerChoices = timerChoices
        self.onSelectTimer = onSelectTimer
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
            topBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    identityHeader
                    filterBar
                    if !info.isDirect {
                        participantsSection
                    }
                    if !info.pinnedEventIDs.isEmpty {
                        pinnedSection
                    }
                    if !info.sharedMedia.isEmpty {
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
                }
                .padding(12)
            }
        }
        .frame(minWidth: 280)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
        .onChange(of: focusSearchTrigger) { _, _ in
            isFilterFocused = true
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Chat Info"))
                .font(.headline)
            Spacer(minLength: 0)
            Button {
                openWindow(id: WindowID.chatInfo, value: info.roomID)
            } label: {
                Image(systemName: "macwindow.on.rectangle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Open Chat Info in Separate Window"))
            .accessibilityLabel(String(localized: "Open Chat Info in Separate Window"))

            if showsCloseButton {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Close Chat Info (⌘⇧I)"))
                .accessibilityLabel(String(localized: "Close chat info"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .accessibilityAddTraits(.isHeader)
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
                .frame(width: 52, height: 52)
                .overlay(alignment: .bottomTrailing) {
                    NetworkBadge(network: info.network, name: networkDisplayName, size: 16)
                        .background(Circle().fill(.background))
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
                ForEach(member.identifiers, id: \.self) { identifier in
                    Text(verbatim: ContactsBridge.displayIdentifier(identifier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let localTime = Self.localTimeText(for: member.tz, now: now()) {
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
        let displayAvatar = !info.localAvatarURI.isEmpty ? info.localAvatarURI : info.avatarPath
        if !displayAvatar.isEmpty {
            AvatarView(path: displayAvatar, initials: Self.initials(of: info.name), seed: info.name)
        } else if !info.isDirect {
            GroupAvatar(seed: info.name)
        } else {
            AvatarView(path: "", initials: Self.initials(of: info.name), seed: info.name)
        }
    }

    private static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap {
            $0.first(where: { $0.isLetter || $0.isNumber })
        }
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
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

    private var filteredLinks: [RoomLink] {
        guard !trimmedFilter.isEmpty else { return info.sharedLinks }
        return info.sharedLinks.filter { link in
            link.url.localizedCaseInsensitiveContains(trimmedFilter)
                || link.host.localizedCaseInsensitiveContains(trimmedFilter)
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
            VStack(alignment: .leading, spacing: 6) {
                if info.features.canInvite {
                    Button(action: onAddParticipants) {
                        Label(String(localized: "Add Participants…"), systemImage: "person.badge.plus")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 2)
                }

                ForEach(filteredMembers, id: \.userID) { member in
                    Button {
                        onSelectMember(member)
                    } label: {
                        HStack(spacing: 8) {
                            AvatarView(
                                path: member.avatarPath,
                                initials: Self.initials(of: member.name),
                                seed: member.name
                            )
                            .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.name.isEmpty ? member.userID : member.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                if let firstID = member.identifiers.first {
                                    Text(verbatim: ContactsBridge.displayIdentifier(firstID))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            if member.isBot {
                                ChatInfoBadge(text: String(localized: "Bot"), tinted: false)
                            }
                            if member.isAdmin {
                                ChatInfoBadge(text: String(localized: "Admin"), tinted: true)
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
            count: info.sharedMedia.count,
            isExpanded: $mediaExpanded
        ) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(info.sharedMedia.prefix(9), id: \.eventID) { event in
                    ChatInfoMediaTile(event: event) {
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
            isExpanded: $filesExpanded
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
            isExpanded: $linksExpanded
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(filteredLinks) { link in
                    Button {
                        onSelectEvent(link.eventID)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: link.host.isEmpty ? link.url : link.host)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text(verbatim: link.url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
        return CourierCore.MessageActions.duration(ms)
    }

    private var securityAndTimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: info.encrypted ? "lock.fill" : "lock.open")
                    .foregroundStyle(info.encrypted ? .green : .secondary)
                    .frame(width: 16)
                Text(info.encrypted ? String(localized: "Encrypted") : String(localized: "Transport TLS"))
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
        }
    }

    // MARK: - Actions Section (Refresh & Export Chat)

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Button(action: onRefresh) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 16)
                    Text(String(localized: "Refresh Chat Info"))
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

            if !info.isDirect, info.features.canLeave {
                Button(role: .destructive, action: onLeaveGroup) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .frame(width: 16)
                        Text(String(localized: "Leave Group…"))
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.red)
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
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(role: .destructive, action: onReportSpam) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield")
                        .frame(width: 16)
                    Text(String(localized: "Report as Spam…"))
                        .font(.callout)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Presents `NSSavePanel` in the view only and hands the chosen URL to `onExport`.
    private func promptExportChat() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let baseName = info.name.isEmpty ? "chat-export" : info.name.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(baseName).txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            onExport(url)
        }
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
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
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

            if isExpanded {
                content()
                    .padding(.leading, 4)
            }
        }
    }
}

private struct ChatInfoBadge: View {
    let text: String
    let tinted: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tinted ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(tinted ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.08))
            )
    }
}

private struct ChatInfoMediaTile: View {
    let event: Event
    let action: () -> Void
    @State private var image: CGImage?

    private var isVideo: Bool {
        if case let .object(dict) = event.content, case let .string(msgtype)? = dict["msgtype"] {
            return msgtype == "m.video"
        }
        return false
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.primary.opacity(0.07)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: isVideo ? "film" : "photo")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: event.mediaPath) {
            guard !event.mediaPath.isEmpty else { return }
            image = await ThumbnailLoader.shared.thumbnail(atPath: event.mediaPath)?.image
        }
    }
}

/// Standalone `WindowGroup(id: "chat-info", for: String.self)` scene content.
struct ChatInfoWindow: View {
    let roomID: String
    @ObservedObject var conversation: ConversationModel
    @State private var loadedInfo: RoomInfoResult?
    @State private var loadedBookmarks: [MessageHit] = []
    @State private var isRefreshing = false

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
                ChatInfoPane(
                    info: info,
                    bookmarks: effectiveBookmarks,
                    isRefreshing: isRefreshing,
                    showsCloseButton: false,
                    now: { conversation.currentTime },
                    timerChoices: conversation.roomID == roomID ? conversation.timerChoices : [],
                    onSelectTimer: { choice in
                        Task { await conversation.setTimer(choice) }
                    },
                    onEditTitleAndAvatar: {
                        Task { await conversation.beginEditChat(info: info, roomID: roomID) }
                    },
                    onAddParticipants: {
                        Task { await conversation.beginAddParticipants(info: info) }
                    },
                    onMessageMember: { member in
                        Task { _ = await conversation.messageParticipant(userID: member.userID, in: roomID) }
                    },
                    onToggleMemberAdmin: { member, makeAdmin in
                        Task {
                            _ = await conversation.setParticipantAdmin(
                                userID: member.userID,
                                isAdmin: makeAdmin,
                                in: roomID
                            )
                        }
                    },
                    onRemoveMember: { member in
                        conversation.requestRemoveParticipant(member, info: info)
                    },
                    onSelectEvent: { eventID in
                        conversation.openEvent(eventID, in: roomID)
                    },
                    onRefresh: {
                        Task { await refresh(force: true) }
                    },
                    onExport: { url in
                        Task {
                            do {
                                let count = try await conversation.exportChat(roomID: roomID, to: url)
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
                        conversation.requestLeaveGroup(info: info, roomID: roomID)
                    },
                    onDeleteChat: {
                        conversation.requestDeleteChat(info: info, roomID: roomID)
                    },
                    onReportSpam: {
                        Task { await conversation.beginReportSpam(info: info, roomID: roomID) }
                    }
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
    }

    private func refresh(force: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        let (info, bookmarks) = await conversation.fetchChatInfo(for: roomID, force: force)
        if let info {
            loadedInfo = info
        }
        loadedBookmarks = bookmarks
    }
}
