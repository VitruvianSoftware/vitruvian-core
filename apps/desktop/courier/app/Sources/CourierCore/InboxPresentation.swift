// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// How an inbox row reads. Plain values, so the logic is tested here and the views only draw it.

/// What a chat's newest message is, when its text alone would not say. The view gives each a name.
public enum PreviewLabel: Equatable, Sendable {
    case image, video, voiceNote, file, sticker, poll
    /// A note that the disappearing timer changed: the bridge's English is never shown (Ruling 40).
    case timerChange
    /// A bridge's notice of a call, and whether the call was mine: said in Courier's words.
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

/// A row's time: the time of day if it is today, the weekday within the last six days, the short date otherwise.
/// All in the person's locale and calendar. A row asks for it on every render, so the formatters are kept: one per
/// style, locale and calendar.
public enum RelativeTime {
    private enum Style: String { case time, weekday, date }

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
            case .date:
                formatter.timeStyle = .none
                formatter.dateStyle = .short
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
        case 1 ... 6: style = .weekday
        default: style = .date // older, or ahead of this clock
        }
        if style == .time, timeFormat != .system {
            return timeFormat.formatTime(date, locale: locale, timeZone: calendar.timeZone)
        }
        return formatter(style, calendar: calendar, locale: locale).string(from: date)
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
/// or some do. Courier's own state stays on this Mac either way.
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
