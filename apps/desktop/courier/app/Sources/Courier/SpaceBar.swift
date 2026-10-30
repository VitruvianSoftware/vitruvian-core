// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import SwiftUI

/// How a space looks and is named on the bar. The engine names accounts and labels; the app names its own spaces.
enum SpaceLook {
    static func title(_ space: Space) -> String {
        guard space.kind == .builtin else { return space.title }
        switch space.spaceID {
        case "inbox": return String(localized: "Inbox")
        case "reminders": return String(localized: "Reminders")
        case "requests": return String(localized: "Requests")
        case "low_priority": return String(localized: "Low Priority")
        case "send_later": return String(localized: "Send Later")
        case "archive": return String(localized: "Archive")
        default: return space.title.isEmpty ? space.spaceID : space.title
        }
    }

    static func symbol(_ spaceID: String) -> String {
        switch spaceID {
        case "inbox": "tray.fill"
        case "reminders": "alarm"
        case "requests": "person.crop.circle.badge.questionmark"
        case "low_priority": "arrow.down.to.line"
        case "send_later": "paperplane"
        case "archive": "archivebox"
        default: "square.dashed"
        }
    }

    /// What the tooltip counts: reminders in Reminders, requests in Requests, chats everywhere else.
    static func count(_ space: Space) -> String {
        switch space.spaceID {
        case "reminders": ChatCount.reminders(space.chats)
        case "requests": ChatCount.requests(space.chats)
        default: ChatCount.chats(space.chats)
        }
    }
}

/// The spaces bar at the far left: one icon per space shown, the unread chats as a badge, the counts as tooltips,
/// and each space's menu. View ▸ Hide Space Bar (⌘S) puts it away.
struct SpaceBar: View {
    @ObservedObject var spaces: SpacesModel
    @ObservedObject var inbox: InboxModel
    let labels: LabelsModel
    var onOpenSpaceInNewWindow: ((String) -> Void)? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openDetachedWindow) private var openDetachedWindow

    static let width: CGFloat = 60

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach(spaces.visible) { space in
                    SpaceIcon(space: space, isShown: inbox.query.space == space.spaceID,
                              isReconnecting: isReconnecting(space), isStarting: isStarting(space)) {
                        spaces.select(space.spaceID)
                    }
                    .contextMenu { menu(for: space) }
                }
                if !spaces.spaces.isEmpty, !spaces.spaces.contains(where: { $0.kind == .label }) {
                    NewLabelNudge {
                        openWindow(id: WindowID.label, value: LabelWindowTarget.new(applyTo: []))
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(width: Self.width)
        }
        .scrollIndicators(.never)
        .frame(width: Self.width)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Spaces"))
    }

    private func isReconnecting(_ space: Space) -> Bool {
        space.kind == .account && !isStarting(space)
            && inbox.statusItems.contains { $0.network == space.network && $0.isReconnecting }
    }

    /// The engine hasn't started the account's network yet this session.
    private func isStarting(_ space: Space) -> Bool {
        space.kind == .account && inbox.statusItems.contains { $0.network == space.network && $0.isStarting }
    }

    @ViewBuilder
    private func menu(for space: Space) -> some View {
        switch space.kind {
        case .account:
            Button(String(localized: "Open in New Window")) {
                if let onOpenSpaceInNewWindow {
                    onOpenSpaceInNewWindow(space.spaceID)
                } else {
                    openDetachedWindow?(.space(spaceID: space.spaceID))
                }
            }
            ShowInInboxMenu(space: space, spaces: spaces)
            Button(space.muted ? String(localized: "Unmute Space") : String(localized: "Mute Space")) {
                Task { await spaces.setMuted(space.spaceID, !space.muted) }
            }
            .help(String(localized: "Mutes every chat of this account on this Mac."))
            Button(String(localized: "Auto-Archive…")) {
                openWindow(id: WindowID.autoArchive, value: space.spaceID)
            }
            Divider()
            Button(String(localized: "Edit Spaces…")) {
                spaces.isEditing = true
                openWindow(id: WindowID.editSpaces)
            }
            Button(String(localized: "Add a Network…"), action: inbox.addNetwork)
            // One Reconnect per account that needs it, naming the account when the network has more than one.
            ForEach(inbox.banners.filter { $0.network == space.network && $0.action == .reconnect }) { banner in
                Button(banner.accountName.map { String(localized: "Reconnect \($0)") }
                    ?? String(localized: "Reconnect")) { inbox.perform(banner) }
            }
        case .label:
            Button(String(localized: "Open in New Window")) {
                if let onOpenSpaceInNewWindow {
                    onOpenSpaceInNewWindow(space.spaceID)
                } else {
                    openDetachedWindow?(.space(spaceID: space.spaceID))
                }
            }
            ShowInInboxMenu(space: space, spaces: spaces)
            Button(space.muted ? String(localized: "Unmute Label") : String(localized: "Mute Label")) {
                Task { await spaces.setMuted(space.spaceID, !space.muted) }
            }
            .help(String(localized: "Mutes every chat with this label on this Mac."))
            Divider()
            Button(String(localized: "Edit Label…")) {
                openWindow(id: WindowID.label, value: LabelWindowTarget.edit(labelID: space.labelID))
            }
            Button(String(localized: "Delete Label")) {
                Task { await LabelDeletion.confirmAndDelete(space.labelID, labels: labels) }
            }
        default:
            Button(String(localized: "Open in New Window")) {
                if let onOpenSpaceInNewWindow {
                    onOpenSpaceInNewWindow(space.spaceID)
                } else {
                    openDetachedWindow?(.space(spaceID: space.spaceID))
                }
            }
            Button(String(localized: "Edit Spaces…")) {
                spaces.isEditing = true
                openWindow(id: WindowID.editSpaces)
            }
            Button(inbox.preferences.showSpaceBar ? String(localized: "Hide Space Bar")
                : String(localized: "Show Space Bar")) {
                inbox.preferences.showSpaceBar.toggle()
            }
        }
    }
}

/// Show in Inbox ▸ All Messages / Only DMs / None, ticked.
private struct ShowInInboxMenu: View {
    let space: Space
    let spaces: SpacesModel

    var body: some View {
        Picker(String(localized: "Show in Inbox"), selection: Binding(
            get: { space.showInInbox.rawValue },
            set: { value in Task { await spaces.setShowInInbox(space.spaceID, value) } })) {
            Text(String(localized: "All Messages")).tag(ShowInInbox.all.rawValue)
            Text(String(localized: "Only DMs")).tag(ShowInInbox.dms.rawValue)
            Text(String(localized: "None")).tag(ShowInInbox.none.rawValue)
        }
        .pickerStyle(.menu)
        .help(String(localized: "Which of these chats also show in your inbox."))
    }
}

/// One space on the bar.
private struct SpaceIcon: View {
    let space: Space
    let isShown: Bool
    let isReconnecting: Bool
    let isStarting: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            mark
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(background))
                .overlay(alignment: .topTrailing) { badge }
                .overlay(alignment: .bottomTrailing) {
                    if isReconnecting {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, .orange)
                            .offset(x: 3, y: 3)
                            .accessibilityLabel(String(localized: "Reconnecting…"))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isStarting {
                        Image(systemName: "hourglass.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, .gray)
                            .offset(x: 3, y: 3)
                            .accessibilityLabel(NetworkChoice.startingLabel)
                    }
                }
                .opacity(space.muted || isStarting ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tooltip)
        .accessibilityLabel(SpaceLook.title(space))
        .accessibilityValue(tooltip)
        .accessibilityAddTraits(isShown ? [.isSelected] : [])
    }

    private var background: Color {
        isShown ? Color.accentColor.opacity(0.22) : hovering ? Color.primary.opacity(0.08) : Color.clear
    }

    @ViewBuilder
    private var mark: some View {
        switch space.kind {
        case .account:
            NetworkBadge(network: space.network, name: space.title, size: 26)
                .accessibilityHidden(true)
        case .label:
            LabelIcon(color: space.color, icon: space.icon, size: 28)
        default:
            Image(systemName: SpaceLook.symbol(space.spaceID))
                .font(.system(size: 18))
                .foregroundStyle(isShown ? Color.accentColor : Color.secondary)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if space.unreadChats > 0 {
            Text(space.unreadChats > 99 ? "99+" : String(space.unreadChats))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(space.muted ? Color.gray : Color.red))
                .offset(x: 5, y: -4)
                .accessibilityHidden(true)
        }
    }

    /// "Inbox · 12 chats", and for an account that is reconnecting, so.
    private var tooltip: String {
        var parts = [SpaceLook.title(space), SpaceLook.count(space)]
        if space.unreadChats > 0 { parts.append(String(localized: "\(space.unreadChats) unread")) }
        if isStarting { parts.append(NetworkChoice.startingLabel) }
        if isReconnecting { parts.append(String(localized: "Reconnecting…")) }
        if space.muted { parts.append(String(localized: "Muted")) }
        return parts.joined(separator: " · ")
    }
}

/// With no label yet: the nudge to make one.
private struct NewLabelNudge: View {
    let create: () -> Void

    var body: some View {
        Button(action: create) {
            Image(systemName: "tag")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.tertiary))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
        .help(String(localized: "New label: put chats from any network into a space of their own."))
        .accessibilityLabel(String(localized: "New label"))
    }
}
