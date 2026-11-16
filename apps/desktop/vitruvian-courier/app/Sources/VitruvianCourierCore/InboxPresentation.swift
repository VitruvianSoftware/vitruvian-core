// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
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
    /// The chat's display name: rewrites unnamed bridge-built member lists (e.g. `"Eddie Stecker, Kent Hua, GitHub"`)
    /// into concise first-name lists (`"Eddie, Kent & GitHub"`), only when every segment is confirmed by known members.
    public var displayTitle: String {
        displayTitle(knownMembers: nil)
    }

    /// Formats the chat's display name using `knownMembers` when provided, otherwise falling back to `memberPreview`.
    public func displayTitle(knownMembers: [GroupTitleMember]?, isCompleteMemberList: Bool = true) -> String {
        if let knownMembers, !knownMembers.isEmpty {
            return ChatDisplayTitle.format(
                name: name,
                isDirect: isDirect,
                localName: localName,
                members: knownMembers,
                isCompleteMemberList: isCompleteMemberList
            )
        }
        return ChatDisplayTitle.format(
            name: name,
            isDirect: isDirect,
            localName: localName,
            members: memberPreview.map { GroupTitleMember(userID: $0.userID, name: $0.name) },
            isCompleteMemberList: false
        )
    }

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

/// Resolves the resource bundle holding `Localizable.stringsdict` in both the `.app` bundle and `swift_test` runs.
enum CourierLocalization {
    static let bundle: Bundle = resolveBundle()

    private static func resolveBundle() -> Bundle {
        if Bundle.main.url(forResource: "Localizable", withExtension: "stringsdict") != nil {
            return .main
        }
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        for rootKey in ["TEST_SRCDIR", "RUNFILES_DIR"] {
            if let root = env[rootKey], !root.isEmpty {
                let rootURL = URL(fileURLWithPath: root, isDirectory: true)
                candidates.append(
                    rootURL.appendingPathComponent("_main/apps/desktop/vitruvian-courier/app/Resources", isDirectory: true)
                )
                candidates.append(
                    rootURL.appendingPathComponent("vitruvian-core/apps/desktop/vitruvian-courier/app/Resources", isDirectory: true)
                )
            }
        }
        let sourceFallback = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        candidates.append(sourceFallback)
        for candidate in candidates {
            let dictURL = candidate.appendingPathComponent("en.lproj/Localizable.stringsdict")
            if fm.fileExists(atPath: dictURL.path), let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        return .main
    }
}

/// Shared per-`AppModel` cache of confirmed room members (from `room.members` and `room.info`) so inbox rows,
/// pinned tiles, and the conversation header can shorten bridge-built group lists without changing the Go engine.
@MainActor
public final class KnownGroupMembersStore {
    public static let shared = KnownGroupMembersStore()

    private final class WeakApp {
        weak var value: AppModel?
        init(_ value: AppModel) { self.value = value }
    }

    public struct Entry: Equatable {
        public let members: [GroupTitleMember]
        public let isComplete: Bool
    }

    private var entries: [ObjectIdentifier: (app: WeakApp, rooms: [String: Entry])] = [:]
    public let didUpdate = PassthroughSubject<ObjectIdentifier, Never>()

    private init() {}

    public func entry(for roomID: String, in appModel: AppModel) -> Entry? {
        pruneDeallocated()
        return entries[ObjectIdentifier(appModel)]?.rooms[roomID]
    }

    public func record(_ members: [GroupTitleMember], isComplete: Bool, for roomID: String, in appModel: AppModel) {
        guard !roomID.isEmpty, !members.isEmpty else { return }
        pruneDeallocated()
        let appID = ObjectIdentifier(appModel)
        let next = Entry(members: members, isComplete: isComplete)
        var bucket = entries[appID] ?? (app: WeakApp(appModel), rooms: [:])
        if bucket.rooms[roomID] == next { return }
        bucket.rooms[roomID] = next
        entries[appID] = bucket
        didUpdate.send(appID)
    }

    public func clear(for roomID: String? = nil, in appModel: AppModel) {
        pruneDeallocated()
        let appID = ObjectIdentifier(appModel)
        if let roomID {
            guard entries[appID]?.rooms.removeValue(forKey: roomID) != nil else { return }
            didUpdate.send(appID)
        } else {
            guard entries.removeValue(forKey: appID) != nil else { return }
            didUpdate.send(appID)
        }
    }

    private func pruneDeallocated() {
        entries = entries.filter { $0.value.app.value != nil }
    }
}

/// Someone in a group chat considered when formatting an unnamed group's display title.
public struct GroupTitleMember: Equatable, Sendable {
    public let userID: String
    public let name: String
    public let isBot: Bool

    public init(userID: String = "", name: String, isBot: Bool = false) {
        self.userID = userID
        self.name = name
        self.isBot = isBot
    }
}

/// Formats a chat's display title cleanly.
///
/// When a group chat has no custom title and its display name is a bridge-built comma-separated list of member names
/// confirmed against the chat's member list (e.g. `"Eddie Stecker, Kent Hua, GitHub"`), this condenses it to first
/// names (`"Eddie, Kent & GitHub"`, or `"Eddie, Kent, GitHub & 2 others"` for 4+ members). Chats without a member
/// list, explicit custom titles, channels (`#general`), local overrides (`localName`), and 1:1 chats are never rewritten.
public enum ChatDisplayTitle {
    private static let clauseStarters: Set<String> = [
        "if", "or", "but", "when", "while", "unless", "because", "though",
        "although", "since", "where", "which", "that", "then", "so", "for",
    ]

    /// Whether `name` looks like a comma-separated bridge member list eligible for member confirmation lookup.
    public static func isCandidateGroupList(name: String, isDirect: Bool, localName: String = "") -> Bool {
        guard !isDirect else { return false }
        guard localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return false }
        return splitCommaSegments(trimmed) != nil
    }

    public static func format(
        name: String,
        isDirect: Bool = false,
        localName: String = "",
        members: [GroupTitleMember] = [],
        isCompleteMemberList: Bool = true
    ) -> String {
        guard !isDirect else { return name }
        guard localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return name }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { return name }

        let selfMembers = deduplicatedMembers(
            members.filter { $0.userID == Timeline.meUserID }
        )
        let otherMembers = deduplicatedMembers(
            members.filter { $0.userID != Timeline.meUserID }
        )
        guard !otherMembers.isEmpty else { return name }

        if trimmed.isEmpty {
            guard otherMembers.count >= 2 else { return name }
            return render(entries: otherMembers, totalCount: otherMembers.count) ?? name
        }

        guard let parsed = parseBridgeMemberList(
            trimmed,
            selfMembers: selfMembers,
            otherMembers: otherMembers
        ) else {
            return name
        }

        let entries: [GroupTitleMember]
        let totalCount: Int
        if isCompleteMemberList, otherMembers.count >= 2 {
            let ordered = orderMembers(otherMembers, matching: parsed.segments)
            entries = ordered
            totalCount = max(ordered.count, parsed.segments.count + parsed.extraCount)
        } else {
            let mapped = parsed.segments.compactMap { matchedMember(for: $0, in: otherMembers) }
            entries = mapped
            totalCount = entries.count + parsed.extraCount
        }

        return render(entries: entries, totalCount: totalCount) ?? name
    }

    private struct ParsedMemberList {
        let segments: [String]
        let extraCount: Int
    }

    private static func splitCommaSegments(_ trimmed: String) -> ParsedMemberList? {
        guard trimmed.contains(", ") else { return nil }
        var rawSegments = trimmed.components(separatedBy: ", ").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !rawSegments.contains(where: \.isEmpty) else { return nil }
        var extraCount = 0
        if let last = rawSegments.last {
            if rawSegments.count >= 3, let count = standaloneOthersCount(last) {
                rawSegments.removeLast()
                extraCount = count
            } else if let stripped = stripOthersSuffix(from: last) {
                rawSegments[rawSegments.count - 1] = stripped.prefix
                extraCount = stripped.count
            }
        }

        rawSegments = rawSegments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard rawSegments.count >= 2, rawSegments.allSatisfy({ !$0.isEmpty }) else { return nil }

        for (index, segment) in rawSegments.enumerated() {
            if segment.contains(":") || segment.contains(";") || segment.contains("?") || segment.contains("!") {
                return nil
            }
            let words = segment.split(whereSeparator: \.isWhitespace)
            if words.isEmpty || words.count > 4 {
                return nil
            }
            if index > 0, let firstWord = words.first, clauseStarters.contains(firstWord.lowercased()) {
                return nil
            }
        }

        let uniqueSegments = deduplicatedStrings(rawSegments)
        guard uniqueSegments.count >= 2 else { return nil }
        return ParsedMemberList(segments: uniqueSegments, extraCount: extraCount)
    }

    private static func parseBridgeMemberList(
        _ trimmed: String,
        selfMembers: [GroupTitleMember],
        otherMembers: [GroupTitleMember]
    ) -> ParsedMemberList? {
        guard let split = splitCommaSegments(trimmed) else { return nil }

        let selfKeys = Set(selfMembers.map { canonical($0.name) }.filter { !$0.isEmpty })
        let otherKeys = Set(otherMembers.map { canonical($0.name) })

        let nonSelfSegments = split.segments.filter { segment in
            let key = canonical(segment)
            if selfKeys.contains(key), !otherKeys.contains(key) {
                return false
            }
            return true
        }
        guard nonSelfSegments.count >= 2 else { return nil }

        // Every comma-separated segment must match a non-self member's full display name (case-insensitive).
        guard nonSelfSegments.allSatisfy({ otherKeys.contains(canonical($0)) }) else {
            return nil
        }

        return ParsedMemberList(segments: nonSelfSegments, extraCount: split.extraCount)
    }

    private static func standaloneOthersCount(_ segment: String) -> Int? {
        let lower = segment.lowercased()
        let remainder: Substring
        if lower.hasPrefix("and ") {
            remainder = segment.dropFirst(4)
        } else if lower.hasPrefix("& ") {
            remainder = segment.dropFirst(2)
        } else {
            return nil
        }
        let parts = remainder.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace)
        guard parts.count == 2,
              let count = Int(parts[0]), count >= 1,
              parts[1].lowercased() == "other" || parts[1].lowercased() == "others"
        else {
            return nil
        }
        return count
    }

    private static func stripOthersSuffix(from segment: String) -> (prefix: String, count: Int)? {
        for separator in [" and ", " & "] {
            guard let range = segment.range(of: separator, options: [.backwards, .caseInsensitive]) else {
                continue
            }
            let prefix = segment[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = segment[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = suffix.split(whereSeparator: \.isWhitespace)
            guard parts.count == 2,
                  let count = Int(parts[0]), count >= 1,
                  parts[1].lowercased() == "other" || parts[1].lowercased() == "others",
                  !prefix.isEmpty
            else {
                continue
            }
            return (prefix, count)
        }
        return nil
    }

    private static func render(entries: [GroupTitleMember], totalCount: Int) -> String? {
        guard !entries.isEmpty else { return nil }
        let limit = totalCount <= 3 ? min(totalCount, entries.count) : min(3, entries.count)
        let shownEntries = Array(entries.prefix(limit))
        let displayNames = disambiguatedShortNames(for: shownEntries)

        switch shownEntries.count {
        case 0:
            return nil
        case 1:
            return displayNames[0]
        case 2:
            if totalCount > 2 {
                let others = totalCount - 2
                return String(
                    localized: "\(displayNames[0]), \(displayNames[1]) & \(others) others",
                    bundle: CourierLocalization.bundle
                )
            }
            return String(
                localized: "\(displayNames[0]) & \(displayNames[1])",
                bundle: CourierLocalization.bundle
            )
        default:
            if totalCount > 3 {
                let others = totalCount - 3
                return String(
                    localized: "\(displayNames[0]), \(displayNames[1]), \(displayNames[2]) & \(others) others",
                    bundle: CourierLocalization.bundle
                )
            }
            return String(
                localized: "\(displayNames[0]), \(displayNames[1]) & \(displayNames[2])",
                bundle: CourierLocalization.bundle
            )
        }
    }

    private static func disambiguatedShortNames(for entries: [GroupTitleMember]) -> [String] {
        let baseNames = entries.map(baseShortName(of:))
        var baseCounts: [String: Int] = [:]
        for name in baseNames {
            baseCounts[canonical(name), default: 0] += 1
        }

        let candidates: [String] = entries.enumerated().map { index, entry in
            let base = baseNames[index]
            guard (baseCounts[canonical(base)] ?? 0) > 1 else { return base }
            let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = trimmed.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2,
                  !entry.isBot,
                  words.last?.caseInsensitiveCompare("bot") != .orderedSame,
                  let initial = words[1].first(where: { $0.isLetter || $0.isNumber })
            else {
                return trimmed
            }
            return "\(words[0]) \(initial)."
        }

        var candidateCounts: [String: Int] = [:]
        for name in candidates {
            candidateCounts[canonical(name), default: 0] += 1
        }

        return entries.enumerated().map { index, entry in
            let candidate = candidates[index]
            if (candidateCounts[canonical(candidate)] ?? 0) > 1 {
                return entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return candidate
        }
    }

    private static func baseShortName(of member: GroupTitleMember) -> String {
        let trimmed = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let words = trimmed.split(whereSeparator: \.isWhitespace)
        if words.count <= 1 { return trimmed }
        if member.isBot || words.last?.caseInsensitiveCompare("bot") == .orderedSame {
            return trimmed
        }
        if isPhoneOrNumericHandle(trimmed) {
            return trimmed
        }
        return String(words[0])
    }

    private static func isPhoneOrNumericHandle(_ text: String) -> Bool {
        guard let first = text.first, first == "+" || first.isASCII && first.isNumber else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789+-(). ").union(.whitespaces)
        return text.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func deduplicatedMembers(_ members: [GroupTitleMember]) -> [GroupTitleMember] {
        var seenIDs = Set<String>()
        var seenNames = Set<String>()
        var out: [GroupTitleMember] = []
        for member in members {
            let trimmedName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }
            if !member.userID.isEmpty {
                guard seenIDs.insert(member.userID).inserted else { continue }
            }
            let key = canonical(trimmedName)
            if member.userID.isEmpty {
                guard seenNames.insert(key).inserted else { continue }
            } else {
                seenNames.insert(key)
            }
            out.append(GroupTitleMember(userID: member.userID, name: trimmedName, isBot: member.isBot))
        }
        return out
    }

    private static func deduplicatedStrings(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in strings {
            let key = canonical(item)
            if seen.insert(key).inserted {
                out.append(item)
            }
        }
        return out
    }

    private static func matchedMember(for segment: String, in members: [GroupTitleMember]) -> GroupTitleMember? {
        let segKey = canonical(segment)
        return members.first { canonical($0.name) == segKey }
    }

    private static func orderMembers(_ members: [GroupTitleMember], matching segments: [String]) -> [GroupTitleMember] {
        var remaining = members
        var ordered: [GroupTitleMember] = []
        for segment in segments {
            let segKey = canonical(segment)
            if let idx = remaining.firstIndex(where: { canonical($0.name) == segKey }) {
                ordered.append(remaining.remove(at: idx))
            }
        }
        ordered.append(contentsOf: remaining)
        return ordered
    }

    private static func canonical(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension RoomInfoResult {
    /// The chat's display name: rewrites unnamed bridge-built member lists into concise first-name lists, while
    /// leaving explicit custom titles untouched.
    public var displayTitle: String {
        ChatDisplayTitle.format(
            name: name,
            isDirect: isDirect,
            localName: localName,
            members: members.map { GroupTitleMember(userID: $0.userID, name: $0.name, isBot: $0.isBot) },
            isCompleteMemberList: true
        )
    }
}
