// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import VitruvianCourierCore
import SwiftUI

/// How a space looks and is named on the bar. The engine names accounts and labels; the app names its own spaces.
enum SpaceLook {
    static func title(_ space: Space) -> String {
        guard space.kind == .builtin else {
            if !space.title.isEmpty { return space.title }
            if !space.network.isEmpty { return NetworkNames.displayName(of: space.network) ?? space.network }
            return space.spaceID
        }
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
    var accountsAndBridges: AccountsAndBridgesModel? = nil
    var onOpenSpaceInNewWindow: ((String) -> Void)? = nil
    var onOpenAccountSettings: ((String) -> Void)? = nil
    /// Where Go to Space's modifier is read, for the shortcut in each icon's tooltip.
    var hotkeys: HotkeyRegistry? = nil
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openDetachedWindow) private var openDetachedWindow

    static let width: CGFloat = 60

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 6) {
                ForEach(Array(spaces.visible.enumerated()), id: \.element.id) { index, space in
                    spaceIcon(space, position: index + 1)
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
        .courierSurface(.sidebarStrip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Spaces"))
    }

    /// One icon. Its shortcut is what Go to Space would do, read from the registry the menu reads, watched so a
    /// rebind or turning it off shows at once.
    @ViewBuilder
    private func spaceIcon(_ space: Space, position: Int) -> some View {
        if let hotkeys {
            ShortcutObserving(registry: hotkeys, position: position, hasSpaces: !spaces.visible.isEmpty) {
                icon(space, shortcut: $0)
            }
        } else {
            icon(space, shortcut: nil)
        }
    }

    private func icon(_ space: Space, shortcut: String?) -> some View {
        SpaceIcon(space: space, isShown: inbox.query.space == space.spaceID,
                  isReconnecting: isReconnecting(space), isStarting: isStarting(space), shortcut: shortcut) {
            spaces.select(space.spaceID)
        }
    }

    private func isReconnecting(_ space: Space) -> Bool {
        space.kind == .account && !isStarting(space)
            && inbox.statusItems.contains { $0.network == space.network && $0.isReconnecting }
    }

    /// The engine hasn't started the account's network yet this session.
    private func isStarting(_ space: Space) -> Bool {
        space.kind == .account && inbox.statusItems.contains { $0.network == space.network && $0.isStarting }
    }

    private func primaryLogin(for network: String) -> Login? {
        accountsAndBridges?
            .bridges
            .first(where: { $0.network == network })?
            .accounts
            .flatMap(\.logins)
            .first
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
            Button(String(localized: "Account Settings…")) {
                if let login = primaryLogin(for: space.network) {
                    accountsAndBridges?.selectAccount(network: space.network, accountID: login.accountID)
                }
                onOpenAccountSettings?(space.network)
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
            Divider()
            Button(role: .destructive) {
                if let login = primaryLogin(for: space.network) {
                    accountsAndBridges?.requestRemoveAccount(
                        network: space.network,
                        accountID: login.accountID,
                        remoteName: login.remoteName,
                        displayName: space.title
                    )
                }
                onOpenAccountSettings?(space.network)
            } label: {
                Label(String(localized: "Remove Account…"), systemImage: "person.crop.circle.badge.minus")
            }
            Menu(String(localized: "Developer")) {
                Button(String(localized: "Copy Account ID")) {
                    if let login = primaryLogin(for: space.network) {
                        accountsAndBridges?.copyAccountID(login.accountID)
                    }
                }
                Button(String(localized: "Copy Bridge ID")) {
                    accountsAndBridges?.copyBridgeID(for: space.network)
                }
                Button(String(localized: "Copy Info as JSON")) {
                    accountsAndBridges?.copyBridgeInfoJSON(for: space.network)
                }
                Divider()
                Button(String(localized: "Restart Bridge")) {
                    Task { await accountsAndBridges?.restartBridge(network: space.network) }
                }
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

/// Redraws its content when the shortcuts change, with the shortcut the space at `position` has now.
private struct ShortcutObserving<Content: View>: View {
    @ObservedObject var registry: HotkeyRegistry
    let position: Int
    let hasSpaces: Bool
    @ViewBuilder let content: (String?) -> Content

    var body: some View {
        content(SpaceShortcutLabel.label(position: position, registry: registry, hasSpaces: hasSpaces))
    }
}

/// One space on the bar.
private struct SpaceIcon: View {
    let space: Space
    let isShown: Bool
    let isReconnecting: Bool
    let isStarting: Bool
    /// "⌃2": the keys that open this space, when it has some.
    var shortcut: String? = nil
    let select: () -> Void
    @State private var hovering = false
    @Environment(\.themeAccentColor) private var themeAccent
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Button(action: select) {
            mark
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(background)
                        .animation(
                            reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                            value: hovering
                        )
                )
                .overlay {
                    // The open space: the same accent wash and thin edge behind every kind of icon.
                    if isShown {
                        RoundedRectangle(cornerRadius: 10).strokeBorder(themeAccent.opacity(0.45), lineWidth: 1)
                    }
                }
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
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .courierTooltip(SpaceLook.title(space), shortcut: shortcut, detail: tooltipDetail, edge: .trailing)
        .accessibilityLabel(SpaceLook.title(space))
        .accessibilityValue(tooltip)
        .accessibilityAddTraits(isShown ? [.isSelected] : [])
    }

    private var background: Color {
        isShown ? themeAccent.opacity(0.2) : hovering ? Color.primary.opacity(0.08) : Color.clear
    }

    @ViewBuilder
    private var mark: some View {
        switch space.kind {
        case .account:
            // An app-icon tile; no tooltip of its own, so the button's (name and shortcut) is the one shown.
            NetworkBadge(network: space.network, name: SpaceLook.title(space), size: 26, showsTooltip: false)
                .opacity(isShown || hovering ? 1 : 0.88)
                .animation(
                    reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                    value: hovering
                )
                .accessibilityHidden(true)
        case .label:
            LabelIcon(color: space.color, icon: space.icon, size: 28)
        default:
            Image(systemName: SpaceLook.symbol(space.spaceID))
                .font(.system(size: 18))
                .foregroundStyle(isShown ? themeAccent : Color.secondary)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if space.unreadChats > 0 {
            if space.kind == .account {
                Circle()
                    .fill(space.muted ? Color.gray : themeAccent)
                    .frame(width: 6, height: 6)
                    .offset(x: 2, y: -2)
                    .accessibilityHidden(true)
            } else {
                Text(space.unreadChats > 99 ? "99+" : String(space.unreadChats))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(space.muted ? Color.gray : themeAccent))
                    .offset(x: 5, y: -4)
                    .accessibilityHidden(true)
            }
        }
    }

    private var detailParts: [String] {
        var parts = [SpaceLook.count(space)]
        if space.unreadChats > 0 { parts.append(String(localized: "\(space.unreadChats) unread")) }
        if isStarting { parts.append(NetworkChoice.startingLabel) }
        if isReconnecting { parts.append(String(localized: "Reconnecting…")) }
        if space.muted { parts.append(String(localized: "Muted")) }
        return parts
    }

    private var tooltipDetail: String {
        detailParts.joined(separator: " · ")
    }

    /// "Inbox  ⌃1 · 12 chats", and for an account that is reconnecting, so.
    private var tooltip: String {
        let name = shortcut.map { "\(SpaceLook.title(space))  \($0)" } ?? SpaceLook.title(space)
        return ([name] + detailParts).joined(separator: " · ")
    }
}

/// With no label yet: the nudge to make one.
private struct NewLabelNudge: View {
    let create: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var reduceMotionEnabled: Bool {
        accessibilityReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        Button(action: create) {
            Image(systemName: "plus")
                .font(.system(size: 18))
                .foregroundStyle(Color.secondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(hovering ? Color.primary.opacity(0.08) : Color.clear)
                        .animation(
                            reduceMotionEnabled ? nil : .easeInOut(duration: HoverFillMotion.duration),
                            value: hovering
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .courierTooltip(String(localized: "New label"), edge: .trailing)
        .accessibilityLabel(String(localized: "New label"))
    }
}
