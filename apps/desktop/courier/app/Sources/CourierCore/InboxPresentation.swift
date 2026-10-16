// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// How an inbox row reads. Plain values, so the logic is tested here and the views only draw it.

/// What a chat's newest message is, when its text alone would not say. The view gives each a name.
public enum PreviewLabel: Equatable, Sendable {
    case image, video, voiceNote, file, sticker
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
                            locale: Locale = .current) -> String {
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
        default: fallback
        }
    }
}
