// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The small date capsule that floats under the chat's header while the person scrolls the timeline: which day the
/// messages at the top belong to, and how that day reads.
///
/// Pure: the timeline's table tells it which row is at the top and it answers, so the rule is tested without a window.
public enum FloatingDay {
    /// How long the capsule stays after the scrolling stops.
    public static let fadeOutDelay: TimeInterval = 1.0
    /// How long its fade takes.
    public static let fadeDuration: TimeInterval = 0.2

    /// The day the row at `topRow` belongs to: the nearest day separator above it. Nil when there is nothing to show:
    /// the row is a day separator itself (the day is already on screen), or it is not a timeline item (the "load
    /// earlier" row). `itemAt` gives the item of a row (nil for a row that holds none).
    ///
    /// With no separator above (the chat's older messages are not loaded and the list starts mid-day), the day is the
    /// top message's own.
    public static func day(topRow: Int, itemAt: (Int) -> TimelineItem?, calendar: Calendar = .current) -> Date? {
        guard topRow >= 0, let top = itemAt(topRow) else { return nil }
        if case .dateSeparator = top { return nil }
        var row = topRow
        while row >= 0 {
            if case let .dateSeparator(day)? = itemAt(row) { return day }
            row -= 1
        }
        switch top {
        case let .message(message):
            return calendar.startOfDay(for: Date(timeIntervalSince1970: Double(message.ts) / 1000))
        case let .membershipRun(_, events, _):
            return events.first.map { calendar.startOfDay(for: Date(timeIntervalSince1970: Double($0.ts) / 1000)) }
        case .newDivider, .dateSeparator:
            return nil
        }
    }

    /// Whether a change of the timeline's scroll position shows the capsule: only when the person is scrolling (the
    /// wheel, the trackpad, dragging the scroller), not when the app moves the timeline itself (a new message, the
    /// button to the newest one, opening a search result).
    public static func showsForScroll(isProgrammatic: Bool, secondsSinceUserScroll: TimeInterval,
                                      grace: TimeInterval = 0.6) -> Bool {
        !isProgrammatic && secondsSinceUserScroll <= grace
    }

    /// How a day reads in the capsule.
    public enum Label: Equatable, Sendable {
        case today
        case yesterday
        /// Two to six days ago: the weekday alone ("Tuesday").
        case weekday(Date)
        /// Older: "Sat, Nov 14", with the year when it is not this year.
        case date(Date, includesYear: Bool)

        public static func of(day: Date, now: Date, calendar: Calendar = .current) -> Label {
            let from = calendar.startOfDay(for: day)
            let to = calendar.startOfDay(for: now)
            let daysAgo = calendar.dateComponents([.day], from: from, to: to).day ?? 0
            switch daysAgo {
            case 0: return .today
            case 1: return .yesterday
            case 2 ... 6: return .weekday(day)
            default:
                return .date(day, includesYear: !calendar.isDate(day, equalTo: now, toGranularity: .year))
            }
        }
    }

    /// The capsule's words for `day`.
    public static func text(day: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        switch Label.of(day: day, now: now, calendar: calendar) {
        case .today:
            return String(localized: "Today")
        case .yesterday:
            return String(localized: "Yesterday")
        case let .weekday(date):
            return format(date, "EEEE", calendar: calendar, locale: locale)
        case let .date(date, includesYear):
            return format(date, includesYear ? "EEEMMMdy" : "EEEMMMd", calendar: calendar, locale: locale)
        }
    }

    /// How many date formatters have been built, for the test that proves they are reused (one per format, not one per
    /// scroll event).
    public static var formatterBuildCount: Int { formatters.builds }

    private static let formatters = FormatterCache()

    private static func format(_ date: Date, _ template: String, calendar: Calendar, locale: Locale) -> String {
        formatters.formatter(template: template, calendar: calendar, locale: locale).string(from: date)
    }

    /// Date formatters are costly to make and the capsule needs one on every scroll event that crosses to another day:
    /// they are made once per format, calendar and locale.
    private final class FormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: [String: DateFormatter] = [:]
        private var buildCount = 0
        var builds: Int {
            lock.lock()
            defer { lock.unlock() }
            return buildCount
        }

        func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
            let key = "\(template)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(locale.identifier)"
            lock.lock()
            defer { lock.unlock() }
            if let hit = cached[key] { return hit }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            cached[key] = formatter
            buildCount += 1
            return formatter
        }
    }
}
