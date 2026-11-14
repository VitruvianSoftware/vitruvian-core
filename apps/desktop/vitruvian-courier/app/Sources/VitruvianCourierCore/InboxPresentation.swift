// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// How an inbox row reads. Plain values, so the logic is tested here and the views only draw it.

/// What a chat's newest message is, when its text alone would not say. The view gives each a name.
public enum PreviewLabel: Equatable, Sendable {
    case image, video, voiceNote, file, sticker, poll
    /// A note that the disappearing timer changed: the bridge's English is never shown (Ruling 40).
    case timerChange
    /// A bridge's notice of a call, and whether the call was mine: said in Vitruvian Courier's words.
    case call(CallNote, mine: Bool)
}

extension PreviewLabel {
    /// The label as people read it: in a chat row's preview, and in a notification for a message with no text.
    public var title: String {
        switch self {
        case .image: String(localized: "Image")
        case .video: String(localized: "Video")
        case .voiceNote: String(localized: "Voice note")
        case .file: String(localized: "File")
        case .sticker: String(localized: "Sticker")
        case .poll: String(localized: "Poll")
        case .timerChange: String(localized: "Disappearing messages changed")
        case let .call(note, mine): note.words(mine: mine)
        }
    }
}

extension InboxRow {
    /// The label before the preview text; nil for text, and for a kind this app does not know (an engine newer
    /// than the app), which is shown as the text it has.
    public var previewLabel: PreviewLabel? {
        switch previewKind {
        case .image: .image
        case .video: .video
        case .audio: .voiceNote
        case .file: .file
        case .sticker: .sticker
        case .poll: .poll
        case .timerChange: .timerChange
        case .call: .call(previewCall ?? CallNote(state: .ringing), mine: previewMine)
        default: nil
        }
    }

    /// Before a reaction preview, whose body the engine words as "😂 to “…”": "You reacted ", "<Name> reacted " in a
    /// group, "Reacted " in a direct chat. Nil when the newest activity is not a reaction.
    public var reactionPreviewLead: String? {
        guard previewKind == .reaction else { return nil }
        if previewMine { return String(localized: "You reacted ") }
        if !isDirect, !previewSenderName.isEmpty { return String(localized: "\(previewSenderName) reacted ") }
        return String(localized: "Reacted ")
    }

    /// Before the preview when the newest message is a reply that stays in its thread, which the chat's timeline
    /// doesn't show: "You, in a thread: ", "<Name>, in a thread: " in a direct chat, or "In a thread: " in a group.
    /// Nil otherwise.
    public var previewThreadPrefix: String? {
        guard previewInThread else { return nil }
        if previewMine {
            return String(localized: "You, in a thread: ")
        }
        if isDirect, !name.isEmpty {
            return String(localized: "\(name), in a thread: ")
        }
        return String(localized: "In a thread: ")
    }

    /// Who the compact thread glyph is followed by: "You: " for my reply, "<Name>: " in a direct chat, nil in a group
    /// (the engine doesn't say who) and for a message that isn't a thread reply.
    public var previewThreadSender: String? {
        guard previewInThread else { return nil }
        if previewMine { return String(localized: "You: ") }
        if isDirect, !name.isEmpty { return String(localized: "\(name): ") }
        return nil
    }

    /// The preview body.
    public var previewBody: String {
        preview
    }

    /// The full plain-text preview string for an inbox row.
    public var formattedPreviewText: String {
        if let lead = reactionPreviewLead { return lead + preview }
        var result = ""
        if let prefix = previewThreadPrefix {
            result += prefix
        } else if previewMine {
            result += String(localized: "You: ")
        }
        if let label = previewLabel {
            result += label.title
        }
        let body = previewBody
        if !body.isEmpty {
            result += previewLabel == nil ? body : " " + body
        }
        return result
    }

    /// The unread count as the row shows it: nothing at 0, and 99+ past 99.
    public var unreadBadge: String? {
        switch unread {
        case ..<1: nil
        case 1 ... 99: String(unread)
        default: "99+"
        }
    }

    /// Up to two letters for a chat with no picture: the first of each of the first two words.
    public static func initials(of name: String) -> String {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }

    public var initials: String { Self.initials(of: name) }
}

/// A row's time: the time of day if it is today, "Yesterday", the weekday for two to six days ago, "November 4" for
/// the rest of this year, and "Nov 4, 2025" before that. All in the person's locale and calendar. A row asks for it on every render, so the formatters are kept: one per
/// style, locale and calendar.
public enum RelativeTime {
    private enum Style: String { case time, weekday, monthDay, fullDate }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]

    /// How many formatters are kept (a test reads it).
    static var cachedFormatterCount: Int { lock.withLock { formatters.count } }

    private static func formatter(_ style: Style, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(style.rawValue)|\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        return lock.withLock {
            if let kept = formatters[key] { return kept }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            switch style {
            case .time:
                formatter.timeStyle = .short
                formatter.dateStyle = .none
            case .weekday:
                formatter.setLocalizedDateFormatFromTemplate("EEEE")
            case .monthDay:
                formatter.setLocalizedDateFormatFromTemplate("MMMMd")
            case .fullDate:
                formatter.setLocalizedDateFormatFromTemplate("yMMMd")
            }
            if formatters.count >= 32 { formatters = [:] } // a person changes locale rarely; this is only a bound
            formatters[key] = formatter
            return formatter
        }
    }

    public static func text(forMillis millis: Int64, now: Date = Date(), calendar: Calendar = .current,
                            locale: Locale = .current,
                            timeFormat: TimeFormatPreference = .system) -> String {
        guard millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        let style: Style
        switch days {
        case 0: style = .time
        case 1: return String(localized: "Yesterday")
        case 2 ... 6: style = .weekday
        default: // older, or ahead of this clock
            style = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? .monthDay : .fullDate
        }
        if style == .time, timeFormat != .system {
            return timeFormat.formatTime(date, locale: locale, timeZone: calendar.timeZone)
        }
        return formatter(style, calendar: calendar, locale: locale).string(from: date)
    }
}

/// One person on a group's composite avatar: a name, and a local picture when there is one.
public struct AvatarMember: Equatable, Sendable {
    public let name: String
    public let avatarPath: String?

    public init(name: String, avatarPath: String? = nil) {
        self.name = name
        self.avatarPath = avatarPath
    }
}

/// How a group with no picture of its own is drawn.
public enum GroupAvatarStyle: Equatable, Sendable {
    /// A channel ("#data-science"): a tile with a "#" on the channel's colour. The associated value is its name.
    case channel(String)
    /// A name that lists people ("Eddie Stecker, Kent Hua, GitHub"): up to three small circles, overlapping.
    case people([AvatarMember])
    /// Any other name: its initials on the group's colour.
    case single

    /// The most people a composite shows.
    public static let maxMembers = 3

    /// The style a group's name implies until the engine sends its real members.
    public static func of(name: String) -> GroupAvatarStyle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#"), trimmed.count > 1 { return .channel(trimmed.lowercased()) }
        let parts = trimmed.split(whereSeparator: { $0 == "," || $0 == "&" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Two or more short names. A long part is a sentence, not a person.
        guard parts.count >= 2, parts.allSatisfy({ $0.split(whereSeparator: \.isWhitespace).count <= 3 }) else {
            return .single
        }
        return .people(parts.prefix(maxMembers).map { AvatarMember(name: $0) })
    }
}

extension InboxRow {
    /// The engine's real members (`memberPreview`) win over what the name implies, except for a channel, which keeps
    /// its "#" tile.
    public var groupAvatarStyle: GroupAvatarStyle {
        let byName = GroupAvatarStyle.of(name: name)
        if case .channel = byName { return byName }
        let real = memberPreview.prefix(GroupAvatarStyle.maxMembers)
            .map { AvatarMember(name: $0.name, avatarPath: $0.avatarPath) }
        return real.isEmpty ? byName : .people(Array(real))
    }
}

/// A network's app-icon tile: a rounded square in the network's brand colour (a gradient for some) with a white SF
/// Symbol glyph. Colours and symbols only, never the network's own artwork.
public struct NetworkTile: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public let red: Double, green: Double, blue: Double
        public init(hex: UInt32) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
        }
    }

    /// The white glyph, an SF Symbol.
    public let glyph: String
    /// The tile's colour at its top leading corner, and at its bottom trailing one (the same for a flat tile).
    public let top: RGB
    public let bottom: RGB

    public init(glyph: String, top: UInt32, bottom: UInt32? = nil) {
        self.glyph = glyph
        self.top = RGB(hex: top)
        self.bottom = RGB(hex: bottom ?? top)
    }

    public static let fallback = NetworkTile(glyph: "bubble.left.fill", top: 0x73_78_85)

    /// Every network the app draws a tile for, in the order of `NetworkAppearance.of`.
    public static let knownNetworks = [
        "whatsapp", "signal", "telegram", "slack", "gmessages", "gchat", "discord", "facebook", "instagram",
        "twitter", "linkedin", "gvoice", "bluesky", "imessage",
    ]

    public static func of(_ network: String) -> NetworkTile {
        switch network {
        case "whatsapp": NetworkTile(glyph: "phone.bubble.fill", top: 0x25D366)
        case "signal": NetworkTile(glyph: "message.fill", top: 0x3A76F0)
        case "telegram": NetworkTile(glyph: "paperplane.fill", top: 0x2AABEE)
        case "slack": NetworkTile(glyph: "number", top: 0x4A154B)
        case "gmessages": NetworkTile(glyph: "bubble.left.fill", top: 0x1A73E8)
        case "gchat": NetworkTile(glyph: "bubble.left.and.bubble.right.fill", top: 0x00AC47)
        case "discord": NetworkTile(glyph: "gamecontroller.fill", top: 0x5865F2)
        case "facebook": NetworkTile(glyph: "bolt.fill", top: 0x0099FF, bottom: 0xA033FF)
        case "instagram": NetworkTile(glyph: "camera.fill", top: 0xF9A03F, bottom: 0xC13584)
        case "twitter": NetworkTile(glyph: "at", top: 0x1D9BF0)
        case "linkedin": NetworkTile(glyph: "briefcase.fill", top: 0x0A66C2)
        case "gvoice": NetworkTile(glyph: "phone.fill", top: 0x0B9D58)
        case "bluesky": NetworkTile(glyph: "cloud.fill", top: 0x1185FE)
        case "imessage": NetworkTile(glyph: "message.fill", top: 0x34C759)
        default: fallback
        }
    }
}

/// A network's badge: a symbol and a tint, nothing from the network itself. The view puts the network's name on it
/// as a tooltip and an accessibility label.
public struct NetworkAppearance: Equatable, Sendable {
    /// An SF Symbol.
    public let symbol: String
    /// The tint, 0 to 1 each.
    public let red: Double
    public let green: Double
    public let blue: Double

    public static let fallback = NetworkAppearance(symbol: "bubble.left.circle.fill", red: 0.45, green: 0.47, blue: 0.52)

    /// The badge of a network the engine names; the fallback for one this app has never heard of.
    public static func of(_ network: String) -> NetworkAppearance {
        switch network {
        case "whatsapp": NetworkAppearance(symbol: "phone.circle.fill", red: 0.15, green: 0.66, blue: 0.36)
        case "signal": NetworkAppearance(symbol: "lock.circle.fill", red: 0.23, green: 0.45, blue: 0.93)
        case "telegram": NetworkAppearance(symbol: "paperplane.circle.fill", red: 0.14, green: 0.60, blue: 0.85)
        case "slack": NetworkAppearance(symbol: "number.circle.fill", red: 0.55, green: 0.27, blue: 0.62)
        case "gmessages": NetworkAppearance(symbol: "message.circle.fill", red: 0.08, green: 0.50, blue: 0.62)
        case "gchat": NetworkAppearance(symbol: "bubble.left.and.bubble.right.fill", red: 0.00, green: 0.67, blue: 0.28)
        case "discord": NetworkAppearance(symbol: "gamecontroller.circle.fill", red: 0.35, green: 0.40, blue: 0.95)
        case "facebook": NetworkAppearance(symbol: "bolt.horizontal.circle.fill", red: 0.00, green: 0.52, blue: 1.00)
        case "instagram": NetworkAppearance(symbol: "camera.circle.fill", red: 0.88, green: 0.19, blue: 0.42)
        case "twitter": NetworkAppearance(symbol: "at.circle.fill", red: 0.11, green: 0.61, blue: 0.94)
        case "linkedin": NetworkAppearance(symbol: "briefcase.circle.fill", red: 0.04, green: 0.40, blue: 0.76)
        case "gvoice": NetworkAppearance(symbol: "phone.bubble.fill", red: 0.04, green: 0.62, blue: 0.35)
        case "bluesky": NetworkAppearance(symbol: "cloud.circle.fill", red: 0.07, green: 0.52, blue: 1.00)
        case "imessage": NetworkAppearance(symbol: "message.badge.filled.fill", red: 0.20, green: 0.78, blue: 0.35)
        default: fallback
        }
    }
}

/// The tick after a row's time (01 §4's ThreadListReadIcon): how far my newest message has got.
public enum PreviewTick: Equatable, Sendable {
    /// It went: one tick.
    case sent
    /// Someone's device has it (one-to-one chats only): two ticks.
    case delivered
    /// Someone has read it: two ticks, filled with the accent colour.
    case seen

    /// How many ticks it draws.
    public var marks: Int { self == .sent ? 1 : 2 }

    /// What it says to VoiceOver and as its tooltip.
    public var label: String {
        switch self {
        case .sent: String(localized: "Sent")
        case .delivered: String(localized: "Delivered")
        case .seen: String(localized: "Seen")
        }
    }
}

extension InboxRow {
    /// The row's tick, only when its newest message is mine and has gone (`preview_status`); nil for someone
    /// else's message, mine not sent yet, a note, or a value this app doesn't know.
    public var previewTick: PreviewTick? {
        guard previewMine else { return nil }
        switch previewStatus {
        case .sent: return .sent
        case .delivered: return .delivered
        case .seen: return .seen
        default: return nil
        }
    }

    /// The account the chat is on, as a small tag after the network's mark, while its network has more than one
    /// account (`login_name`); nil otherwise.
    public var accountTag: String? { loginName.isEmpty ? nil : loginName }

    /// Who is typing, in place of the preview: "Name is typing…", or for more than one, "N people are typing…".
    /// Nil when no one is.
    public var typingLine: String? {
        switch typing.count {
        case 0: nil
        case 1: String(localized: "\(typing[0]) is typing…")
        case let count: String(localized: "\(count) people are typing…")
        }
    }

    /// What else mutes the chat, in the row: "Muted by Work" (a label) or "Muted by WhatsApp" (its account). Nil
    /// when nothing else does.
    public var mutedLine: String? {
        guard mutedBy != .none, !mutedByName.isEmpty else { return nil }
        return String(localized: "Muted by \(mutedByName)")
    }

    /// A reminder that came due and brought the chat back: the row's "Reminder" badge.
    public var reminderFired: Bool { reminder?.fired ?? false }

    /// The chat is marked unread with no unread messages: the row shows a dot in place of a count.
    public var showsUnreadDot: Bool { markedUnread && unread == 0 }
}

/// What an empty chat list says: a title, and a line that explains the place when it needs explaining (spec §8).
public struct EmptyState: Equatable, Sendable {
    public let title: String
    public let line: String?

    public init(title: String, line: String? = nil) {
        self.title = title
        self.line = line
    }

    /// The empty state of a query. A filter says more than the space it narrows, so filters win: first a place
    /// filter (Archived, Low Priority, Hidden, Requests, Reminders, Send Later), then the others in the Filter
    /// menu's order. With none, the space's own; an account's space reads as the inbox.
    public static func of(_ query: InboxQuery) -> EmptyState {
        let precedence: [InboxFilter] = [
            .archived, .lowPriority, .hidden, .requests, .reminders, .sendLater,
            .unread, .dms, .groups, .drafts, .unanswered, .noReply, .unknown, .muted,
        ]
        if let filter = precedence.first(where: query.filters.contains) { return of(filter) }
        switch query.space {
        case "archive": return of(.archived)
        case "low_priority": return of(.lowPriority)
        case "requests": return of(.requests)
        case "reminders": return of(.reminders)
        case "send_later": return of(.sendLater)
        case let space where space.hasPrefix("label:"):
            return EmptyState(title: String(localized: "No chats with this label"),
                              line: String(localized: "Right-click a chat and choose Label."))
        default:
            return EmptyState(title: String(localized: "You’re all caught up"),
                              line: String(localized: "New messages show up here."))
        }
    }

    private static func of(_ filter: InboxFilter) -> EmptyState {
        switch filter {
        case .unread: EmptyState(title: String(localized: "No unread chats"))
        case .drafts: EmptyState(title: String(localized: "No drafts"),
                                 line: String(localized: "A chat shows up here when you start a message and don’t send it."))
        case .unanswered: EmptyState(title: String(localized: "Nothing waiting for your answer"))
        case .noReply: EmptyState(title: String(localized: "No one owes you a reply"))
        case .dms: EmptyState(title: String(localized: "No one-to-one chats"))
        case .groups: EmptyState(title: String(localized: "No group chats"))
        case .unknown: EmptyState(title: String(localized: "No chats from unknown numbers"))
        case .muted: EmptyState(title: String(localized: "No muted chats"))
        case .hidden: EmptyState(title: String(localized: "No hidden chats"),
                                 line: String(localized: "Hide a chat to take it out of your inbox without leaving it."))
        case .archived: EmptyState(title: String(localized: "Nothing archived"),
                                   line: String(localized: "Archive a chat to clear it from your inbox. It comes back when someone writes."))
        case .lowPriority: EmptyState(title: String(localized: "Nothing in Low Priority"),
                                      line: String(localized: "Chats here stay out of your inbox, even when new messages arrive."))
        case .requests: EmptyState(title: String(localized: "No message requests"),
                                   line: String(localized: "Messages from people you haven’t chatted with before show up here."))
        case .reminders: EmptyState(title: String(localized: "No reminders"),
                                    line: String(localized: "Right-click a chat and choose Remind Me. It comes back to your inbox at that time."))
        case .sendLater: EmptyState(title: String(localized: "No scheduled messages"),
                                    line: String(localized: "Messages you schedule show up here."))
        }
    }
}

/// Whether a change reaches the phone too, for the chats it is made to: every one's network takes it, none does,
/// or some do. Vitruvian Courier's own state stays on this Mac either way.
public enum SyncReach: Equatable, Sendable {
    case all, none, some

    /// How far `sync` reaches for chats on these networks: by each network's Account.syncs. A network the engine
    /// doesn't list takes nothing.
    public static func of(_ sync: AccountSync, networks: [String], accounts: [Account]) -> SyncReach {
        let takes = Set(accounts.filter { $0.syncs.contains(sync) }.map(\.network))
        let wanted = Set(networks)
        guard !wanted.isEmpty else { return .none }
        if wanted.isSubset(of: takes) { return .all }
        return wanted.isDisjoint(with: takes) ? .none : .some
    }
}

/// The help text on Pin, Mute and Mark as Unread: what reaches the phone (spec §8). A pin or a mute is sent only
/// while the account is connected: one made offline stays on this Mac until it is next changed, so the words say so.
public enum SyncHelp {
    /// Pin (`on`) or Unpin.
    public static func pin(_ on: Bool, reach: SyncReach) -> String {
        switch (on, reach) {
        case (true, .all): String(localized: "Also pinned on your phone when it’s connected")
        case (true, .none): String(localized: "Pinned on this Mac only")
        case (true, .some): String(localized: "Also pinned on your phone where its network takes pins, when it’s connected")
        case (false, .all): String(localized: "Also unpinned on your phone when it’s connected")
        case (false, .none): String(localized: "Unpinned on this Mac only")
        case (false, .some): String(localized: "Also unpinned on your phone where its network takes pins, when it’s connected")
        }
    }

    /// Mute (`on`) or Unmute.
    public static func mute(_ on: Bool, reach: SyncReach) -> String {
        switch (on, reach) {
        case (true, .all): String(localized: "Also muted on your phone when it’s connected")
        case (true, .none): String(localized: "Muted on this Mac only")
        case (true, .some): String(localized: "Also muted on your phone where its network takes mutes, when it’s connected")
        case (false, .all): String(localized: "Also unmuted on your phone when it’s connected")
        case (false, .none): String(localized: "Unmuted on this Mac only")
        case (false, .some): String(localized: "Also unmuted on your phone where its network takes mutes, when it’s connected")
        }
    }

    /// Mark as Unread. No network is ever sent an unread mark (Account.syncs never lists one), so this is always
    /// the same.
    public static var markUnread: String { String(localized: "On this Mac only") }
}
