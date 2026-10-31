// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI

/// How the settings shape a row (Settings ▸ Inbox ▸ Chat list), read once per list draw.
struct RowStyle: Equatable {
    var showPreviews = true
    var showUnreadCounts = true
    var compact = false
    var showNetworkIcons = true
    var colorNetworkIcons = true
    var hoverAction = HoverAction.archive
    var timeFormat = TimeFormatPreference.current()

    init(_ preferences: InboxPreferences) {
        showPreviews = preferences.showPreviews
        showUnreadCounts = preferences.showUnreadCounts
        compact = preferences.compactList
        showNetworkIcons = preferences.showNetworkIcons
        colorNetworkIcons = preferences.colorNetworkIcons
        hoverAction = preferences.hoverAction
        timeFormat = TimeFormatPreference.current()
    }
}

/// One chat in the inbox: avatar with its network badge, name, time, a preview (or who is typing, or the draft)
/// and what marks it: unread, a mention, a reminder that came due, muted, a message request.
struct InboxRowView<HoverMenu: View>: View {
    let row: InboxRow
    let networkName: String
    /// When this row represents a merged chat, the networks of its member rooms (`>= 2`).
    var mergedNetworks: [String] = []
    /// The moment the time is read against; the list moves it on every minute.
    let now: Date
    let style: RowStyle
    let isSelecting: Bool
    let isSelected: Bool
    let isHovered: Bool
    /// The hover button, when the setting is Archive or Mark Read/Unread.
    let hoverAct: () -> Void
    let accept: () -> Void
    let decline: () -> Void
    /// The hover button's menu, when the setting is Menu.
    @ViewBuilder let hoverMenu: () -> HoverMenu

    var body: some View {
        HStack(spacing: style.compact ? 8 : 10) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityLabel(isSelected ? String(localized: "Selected") : String(localized: "Not selected"))
            }
            avatar
            VStack(alignment: .leading, spacing: style.compact ? 1 : 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(row.name.isEmpty ? String(localized: "Unnamed chat") : row.name)
                        .font(style.compact ? .body : .headline)
                        .fontWeight(row.isUnread ? .semibold : .regular)
                        .lineLimit(1)
                        // The name keeps its room first; the account tag gives way before it.
                        .layoutPriority(1)
                    if let tag = row.accountTag { AccountTag(name: tag) }
                    Spacer(minLength: 4)
                    if isHovered, !isSelecting, style.hoverAction != .nothing {
                        hoverButton
                    } else {
                        HStack(spacing: 3) {
                            Text(RelativeTime.text(forMillis: row.lastTS, now: now, timeFormat: style.timeFormat))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let tick = row.previewTick { PreviewTickMark(tick: tick) }
                        }
                        .fixedSize()
                    }
                }
                HStack(alignment: .top, spacing: 6) {
                    secondLine
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(style.compact ? 1 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    marks
                }
                if row.request {
                    HStack(spacing: 6) {
                        Button(String(localized: "Accept"), action: accept)
                        Button(String(localized: "Decline"), action: decline)
                            .help(String(localized: "Hides the chat on this Mac. The person isn’t told."))
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                if let muted = row.mutedLine, !style.compact {
                    Label(muted, systemImage: "bell.slash")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
            }
            if style.showPreviews, !row.previewMediaPath.isEmpty, row.typing.isEmpty, row.draft.isEmpty {
                PreviewThumbnail(path: row.previewMediaPath)
                    .frame(width: style.compact ? 26 : 36, height: style.compact ? 26 : 36)
            }
        }
        .padding(.vertical, style.compact ? 1 : 4)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        let size: CGFloat = style.compact ? 28 : 40
        let badgeSize: CGFloat = style.compact ? 11 : 14
        return ChatAvatar(row: row)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if style.showNetworkIcons {
                    if mergedNetworks.count > 1 {
                        HStack(spacing: -4) {
                            ForEach(Array(mergedNetworks.prefix(3).enumerated()), id: \.offset) { _, net in
                                NetworkBadge(
                                    network: net,
                                    name: NetworkNames.displayName(of: net) ?? net,
                                    size: badgeSize,
                                    tinted: style.colorNetworkIcons
                                )
                                .background(Circle().fill(.background))
                            }
                        }
                        .offset(x: 4, y: 3)
                    } else {
                        NetworkBadge(network: row.network, name: networkName, size: style.compact ? 12 : 15,
                                     tinted: style.colorNetworkIcons)
                            .background(Circle().fill(.background))
                            .offset(x: 3, y: 3)
                    }
                }
            }
    }

    /// Who is typing, else the draft, else the newest message (when previews are on).
    @ViewBuilder
    private var secondLine: some View {
        if let typing = row.typingLine {
            HStack(spacing: 3) {
                Image(systemName: "ellipsis")
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text(typing)
            }
            .foregroundStyle(Color.accentColor)
        } else if row.request {
            Text(String(localized: "Message request"))
                .foregroundStyle(Color.accentColor)
        } else if !row.draft.isEmpty {
            Text(String(localized: "Draft:")).foregroundStyle(.red) + Text(verbatim: " " + row.draft)
        } else if style.showPreviews {
            preview
        }
    }

    private var preview: Text { ChatPreview.text(row) }

    /// "@", "Reminder", muted, and the unread count or dot.
    @ViewBuilder
    private var marks: some View {
        if row.unreadMentions > 0 {
            Text(verbatim: "@")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
                .help(String(localized: "You were mentioned"))
                .accessibilityLabel(String(localized: "You were mentioned"))
        }
        if row.reminderFired {
            Text(String(localized: "Reminder"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().strokeBorder(Color.orange))
                .help(String(localized: "A reminder you set brought this chat back."))
        }
        if row.muted {
            Image(systemName: "bell.slash.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(String(localized: "Muted"))
                .accessibilityLabel(String(localized: "Muted"))
        }
        if style.showUnreadCounts, let badge = row.unreadBadge {
            Text(badge)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(row.muted || row.mutedBy != .none ? Color.gray.opacity(0.55) : Color.accentColor))
                .accessibilityLabel(String(localized: "\(row.unread) unread"))
        } else if row.showsUnreadDot || (!style.showUnreadCounts && row.isUnread) {
            Circle()
                .fill(row.muted || row.mutedBy != .none ? Color.gray.opacity(0.55) : Color.accentColor)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
                .help(row.markedUnread ? String(localized: "Marked as unread") : String(localized: "Unread"))
                .accessibilityLabel(String(localized: "Unread"))
        }
    }

    @ViewBuilder
    private var hoverButton: some View {
        switch style.hoverAction {
        case .archive:
            Button(action: hoverAct) {
                Image(systemName: row.archived ? "tray.and.arrow.up" : "archivebox")
            }
            .buttonStyle(.borderless)
            .disabled(row.pinned && !row.archived)
            .help(row.archived ? String(localized: "Unarchive")
                : row.pinned ? String(localized: "Unpin a chat to archive it") : String(localized: "Archive"))
        case .toggleRead:
            Button(action: hoverAct) {
                Image(systemName: row.isUnread ? "envelope.open" : "envelope.badge")
            }
            .buttonStyle(.borderless)
            .help(row.isUnread ? String(localized: "Mark as Read") : String(localized: "Mark as Unread"))
        case .menu:
            Menu(content: hoverMenu) {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "More"))
        default:
            EmptyView()
        }
    }
}

/// The account a chat is on, while its network has more than one: a small tag after the chat's name.
private struct AccountTag: View {
    let name: String

    var body: some View {
        Text(verbatim: name)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().strokeBorder(Color.secondary.opacity(0.45)))
            .frame(minWidth: 24, maxWidth: 96, alignment: .leading)
            .help(String(localized: "On your \(name) account"))
            .accessibilityLabel(String(localized: "On your \(name) account"))
    }
}

/// How far my newest message has got, after the row's time (01 §4's ThreadListReadIcon): one tick for sent, two for
/// delivered, two in the accent colour for seen.
struct PreviewTickMark: View {
    let tick: PreviewTick

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0 ..< tick.marks, id: \.self) { index in
                Image(systemName: "checkmark")
                    .offset(x: CGFloat(index) * 4)
            }
        }
        .font(.system(size: 9, weight: tick == .seen ? .heavy : .semibold))
        .foregroundStyle(tick == .seen ? Color.accentColor : Color.secondary)
        .frame(width: tick.marks == 1 ? 10 : 14, alignment: .leading)
        .help(tick.label)
        .accessibilityElement()
        .accessibilityLabel(tick.label)
    }
}

/// A chat's newest message as its row shows it; search's chat rows show it the same way.
enum ChatPreview {
    /// "You: " when the newest message is mine, then the kind's label if it is not text, then the text.
    static func text(_ row: InboxRow) -> Text {
        var text = Text(verbatim: "")
        if row.previewMine { text = text + Text(String(localized: "You: ")) }
        if let label = row.previewLabel { text = text + Text(label.title).italic() }
        if !row.preview.isEmpty {
            text = text + Text(verbatim: row.previewLabel == nil ? row.preview : " " + row.preview)
        }
        return text
    }
}

/// A chat's picture: its own, else a group's mark, else "?" for a chat with no name, else its initials.
struct ChatAvatar: View {
    let row: InboxRow

    var body: some View {
        if !row.avatarPath.isEmpty {
            AvatarView(path: row.avatarPath, initials: row.initials, seed: row.name)
        } else if row.name.isEmpty {
            UnknownAvatar()
        } else if !row.isDirect {
            GroupAvatar(seed: row.name)
        } else {
            AvatarView(path: "", initials: row.initials, seed: row.name)
        }
    }
}

/// A group with no picture: people on its colour.
struct GroupAvatar: View {
    let seed: String

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(AvatarView.color(for: seed))
                Image(systemName: "person.2.fill")
                    .font(.system(size: proxy.size.width * 0.38))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A chat with no name: "?".
struct UnknownAvatar: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(Color.gray.opacity(0.5))
                Text(verbatim: "?")
                    .font(.system(size: proxy.size.width * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The newest message's picture, small, beside the preview.
private struct PreviewThumbnail: View {
    let path: String
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.primary.opacity(0.06)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityHidden(true)
        .task(id: path) { image = await ThumbnailLoader.shared.thumbnail(atPath: path)?.image }
    }
}

/// A network's mark: an SF Symbol in the network's tint (or plain, with "Colour network icons" off), named by its
/// tooltip and accessibility label.
struct NetworkBadge: View {
    let network: String
    let name: String
    let size: CGFloat
    var tinted = true

    var body: some View {
        let look = NetworkAppearance.of(network)
        Image(systemName: look.symbol)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(tinted ? Color(red: look.red, green: look.green, blue: look.blue) : Color.secondary)
            .help(name)
            .accessibilityLabel(name)
    }
}

/// A chat's picture, or its initials on a colour taken from its name.
struct AvatarView: View {
    let path: String
    let initials: String
    let seed: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(Self.color(for: seed))
                Text(initials)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: path) { image = await AvatarCache.shared.image(atPath: path) }
    }

    /// A colour that is the same for a name in every run (a Swift hash is not).
    static func color(for seed: String) -> Color {
        var hash: UInt32 = 5381
        for byte in seed.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.62)
    }
}

/// Pictures already read from disk, so scrolling back does not read them again.
final class AvatarCache: @unchecked Sendable {
    static let shared = AvatarCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 400 }

    func image(atPath path: String) async -> NSImage? {
        guard !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let image = await Task.detached(priority: .utility) { NSImage(contentsOfFile: path) }.value
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }
}
