// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import EventKit

package struct NotchCalendarColor: Equatable, Sendable {
    package let red: Double
    package let green: Double
    package let blue: Double

    package static let fallback = Self(red: 0.35, green: 0.65, blue: 1)

    // Spelled out because a memberwise initializer never leaves its module.
    package init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

package struct NotchCalendarEvent: Equatable, Identifiable, Sendable {
    package let id: String
    package let title: String
    package let calendar: String
    package let start: Date
    package let end: Date
    package let allDay: Bool
    package let location: String
    package var color: NotchCalendarColor = .fallback
    package var calendarItemIdentifier = ""
    package var recurring = false
    /// How a countdown chosen from the event's menu remembers it; see
    /// `NotchCalendarSupport.countdownKey`.
    package var countdownKey = ""

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, title: String, calendar: String, start: Date, end: Date, allDay: Bool, location: String, color: NotchCalendarColor = .fallback, calendarItemIdentifier: String = "", recurring: Bool = false, countdownKey: String = "") {
        self.id = id
        self.title = title
        self.calendar = calendar
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.color = color
        self.calendarItemIdentifier = calendarItemIdentifier
        self.recurring = recurring
        self.countdownKey = countdownKey
    }
}

/// What the closed island counts down to: an event's start or, while the
/// event is happening, its end.
package struct NotchCalendarCountdown: Equatable, Sendable {
    package let event: NotchCalendarEvent
    package let ongoing: Bool

    package var target: Date { ongoing ? event.end : event.start }

    /// Each moment shows during the hour before it; an end, only once its event has begun.
    package func isShown(at now: Date) -> Bool {
        target > now && target.timeIntervalSince(now) <= NotchCalendarSupport.countdownLeadTime
            && (!ongoing || event.start <= now)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(event: NotchCalendarEvent, ongoing: Bool) {
        self.event = event
        self.ongoing = ongoing
    }
}

/// One calendar offered in Settings, grouped under its account like Calendar.app.
package struct NotchCalendarChoice: Equatable, Identifiable, Sendable {
    package let id: String
    package let title: String
    package let sourceID: String
    package let source: String
    package var color: NotchCalendarColor = .fallback

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, title: String, sourceID: String, source: String, color: NotchCalendarColor = .fallback) {
        self.id = id
        self.title = title
        self.sourceID = sourceID
        self.source = source
        self.color = color
    }
}

package enum NotchCalendarSupport {
    package static let countdownLeadTime: TimeInterval = 60 * 60

    package static func monthDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: month.start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The seven days around `date`, from the calendar's first weekday. Every
    /// week lies inside the 42-day grid `monthDays` reads for any of its days.
    package static func weekDays(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    package static func readInterval(month: Date?, now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? now
        if let month {
            let days = monthDays(containing: month, calendar: calendar)
            if let first = days.first, let last = days.last,
               let end = calendar.date(byAdding: .day, value: 1, to: last) {
                return DateInterval(start: first, end: calendar.isDate(month, equalTo: now, toGranularity: .month)
                                    ? max(end, weekEnd) : end)
            }
        }
        return DateInterval(start: today, end: weekEnd)
    }

    package static func needsCurrentRead(visible: DateInterval, current: DateInterval,
                                 countdownEnabled: Bool) -> Bool {
        countdownEnabled && (visible.start > current.start || visible.end < current.end)
    }

    /// End dates are exclusive, including all-day events and midnight boundaries.
    package static func events(_ events: [NotchCalendarEvent], on day: Date,
                       calendar: Calendar = .current) -> [NotchCalendarEvent] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return events.filter { $0.start < interval.end && $0.end > interval.start }.sorted {
            if $0.allDay != $1.allDay { return $0.allDay }
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.id < $1.id
        }
    }

    package static func requestFailed(status: EKAuthorizationStatus, hasError: Bool) -> Bool {
        hasError || ![.fullAccess, .denied, .restricted].contains(status)
    }

    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && AppFeature.notchCalendar.isAvailable(in: defaults)
            && defaults[Preferences.notchCalendarEnabled]
            && NotchSupport.modules(in: defaults).contains(.calendar)
    }

    package static func showsCountdown(in defaults: UserDefaults = .standard) -> Bool {
        showsCountdown(chosen: false, in: defaults)
    }

    /// An event chosen from its menu counts down even while the countdown
    /// for every event is off.
    package static func showsCountdown(chosen: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && (chosen || defaults[Preferences.notchCalendarCountdown])
    }

    package static func showsTimeLeft(in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && defaults[Preferences.notchCalendarTimeLeft]
    }

    /// Names the event a countdown was chosen for across refreshes, edits and
    /// relaunches: the event itself or, in a series, one occurrence by the
    /// date it first fell on, which moving that occurrence leaves unchanged.
    package static func countdownKey(identifier: String, occurrence: Date?) -> String {
        guard let occurrence else { return identifier }
        return identifier + "@" + String(occurrence.timeIntervalSinceReferenceDate.rounded())
    }

    package static func isChosen(_ event: NotchCalendarEvent, in chosen: Set<String>) -> Bool {
        !event.countdownKey.isEmpty && chosen.contains(event.countdownKey)
    }

    /// Events chosen from their menu in the island, by countdown key, each
    /// with the end it had when last read. Only these identifiers are kept,
    /// never an event's text, and each is forgotten once its event ends.
    package static func chosenCountdowns(in defaults: UserDefaults = .standard) -> [String: Date] {
        (defaults.dictionary(forKey: DefaultsKey.notchCalendarChosenCountdowns) ?? [:]).compactMapValues { $0 as? Date }
    }

    package static func setCountdown(_ chosen: Bool, for event: NotchCalendarEvent, in defaults: UserDefaults = .standard) {
        guard !event.countdownKey.isEmpty else { return }
        var choices = chosenCountdowns(in: defaults)
        choices[event.countdownKey] = chosen ? event.end : nil
        storeChosenCountdowns(choices, in: defaults)
    }

    package static func storeChosenCountdowns(_ choices: [String: Date], in defaults: UserDefaults = .standard) {
        if choices.isEmpty { defaults.removeObject(forKey: DefaultsKey.notchCalendarChosenCountdowns) }
        else { defaults.set(choices, forKey: DefaultsKey.notchCalendarChosenCountdowns) }
    }

    /// The choices after a read: an event read again keeps its current end,
    /// so a moved event stays chosen, and a choice whose event has ended is
    /// forgotten. Nil when nothing changes, so a read writes no preference.
    package static func refreshedChoices(_ choices: [String: Date], events: [NotchCalendarEvent],
                                 now: Date) -> [String: Date]? {
        var refreshed = choices
        for event in events where refreshed[event.countdownKey] != nil { refreshed[event.countdownKey] = event.end }
        refreshed = refreshed.filter { $0.value > now }
        return refreshed == choices ? nil : refreshed
    }

    /// Stored as excluded identifiers so a calendar added later starts shown.
    package static func excludedCalendars(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: DefaultsKey.notchCalendarExcluded) ?? [])
    }

    package static func setCalendar(_ identifier: String, shown: Bool, in defaults: UserDefaults = .standard) {
        var excluded = excludedCalendars(in: defaults)
        if shown { excluded.remove(identifier) } else { excluded.insert(identifier) }
        defaults.set(excluded.sorted(), forKey: DefaultsKey.notchCalendarExcluded)
    }

    /// The calendars to pass to EventKit: nil reads every calendar, including
    /// ones added later. An empty result means read nothing; the caller must
    /// not hand `[]` to EventKit, which treats it like nil.
    package static func calendarsToRead<C>(_ calendars: [C], excluded: Set<String>,
                                   identifier: (C) -> String) -> [C]? {
        guard calendars.contains(where: { excluded.contains(identifier($0)) }) else { return nil }
        return calendars.filter { !excluded.contains(identifier($0)) }
    }

    /// Accounts in name order, each with its calendars in name order.
    package static func grouped(_ choices: [NotchCalendarChoice]) -> [[NotchCalendarChoice]] {
        Dictionary(grouping: choices, by: \.sourceID).values
            .map { $0.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }
            .sorted {
                let order = $0[0].source.localizedStandardCompare($1[0].source)
                return order == .orderedSame ? $0[0].sourceID < $1[0].sourceID : order == .orderedAscending
            }
    }

    package static func ordered(_ events: [NotchCalendarEvent]) -> [NotchCalendarEvent] {
        var seen = Set<String>()
        return events.filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite
                && $0.end.timeIntervalSinceReferenceDate.isFinite
                && $0.end > $0.start && seen.insert($0.id).inserted
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.id < $1.id
        }
    }

    package static func upcoming(_ events: [NotchCalendarEvent], now: Date) -> [NotchCalendarEvent] {
        ordered(events).filter { $0.end > now }
    }

    package static func next(_ events: [NotchCalendarEvent], now: Date) -> NotchCalendarEvent? {
        upcoming(events, now: now).first { !$0.allDay }
    }

    /// The compact island counts down to the nearer of the moments it follows:
    /// a timed event's start, with the countdown on or for an event chosen
    /// from its menu, and, with time left on, the end of one in progress. A
    /// start that coincides with an end leaves the event under way.
    package static func countdown(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                          chosen: Set<String> = []) -> NotchCalendarCountdown? {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                followedMoments(event, starts: starts, ends: ends, chosen: chosen)
                    .map { NotchCalendarCountdown(event: event, ongoing: $0) }
            }
            .filter { $0.isShown(at: now) }
            .min { $0.target != $1.target ? $0.target < $1.target : $0.ongoing && !$1.ongoing }
    }

    /// Whether the island follows the event's start (false) and its end (true).
    private static func followedMoments(_ event: NotchCalendarEvent, starts: Bool, ends: Bool,
                                        chosen: Set<String>) -> [Bool] {
        (starts || isChosen(event, in: chosen) ? [false] : []) + (ends ? [true] : [])
    }

    /// The Controls tile names the next start at any distance within the
    /// week read, not only in the countdown's hour. An appointment already
    /// in progress is known; the one after it is what comes next. The month
    /// grid can load weeks further ahead, where a weekday alone would read as
    /// this week's, so the tile stops at the week.
    package static func tileEvent(_ events: [NotchCalendarEvent], now: Date,
                          calendar: Calendar = .current) -> NotchCalendarEvent? {
        let week = readInterval(month: nil, now: now, calendar: calendar)
        return ordered(events).first { !$0.allDay && $0.start > now && $0.start < week.end }
    }

    /// A start later today reads as its time; a later day adds its weekday.
    package static func tileStartText(_ start: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        var style = calendar.isDate(start, inSameDayAs: now)
            ? Date.FormatStyle.dateTime.hour().minute()
            : Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return start.formatted(style)
    }

    /// The hour before each moment followed opens and closes; an end's hour
    /// opens no earlier than its event's start.
    package static func countdownTransition(_ events: [NotchCalendarEvent], now: Date, starts: Bool, ends: Bool,
                                    chosen: Set<String> = []) -> Date? {
        ordered(events).filter { !$0.allDay }
            .flatMap { event in
                followedMoments(event, starts: starts, ends: ends, chosen: chosen).flatMap { ongoing in
                    ongoing ? [max(event.start, event.end.addingTimeInterval(-countdownLeadTime)), event.end]
                        : [event.start.addingTimeInterval(-countdownLeadTime), event.start]
                }
            }
            .filter { $0 > now }.min()
    }

    package static let stripDotWidth: CGFloat = 6
    package static let stripTitleSpacing: CGFloat = 5
    package static let stripClockSpacing: CGFloat = 4

    /// The time beside the countdown clock in the closed island: when the
    /// event starts or, while it is happening, when it ends.
    package static func timeText(_ countdown: NotchCalendarCountdown, locale: Locale) -> String {
        (countdown.ongoing ? "→\u{2009}" : "·\u{2009}")
            + countdown.target.formatted(.dateTime.hour().minute().locale(locale))
    }

    package static func countdownText(until start: Date, now: Date) -> String {
        let seconds = max(0, Int(ceil(start.timeIntervalSince(now))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    package static func countdownAccessibilityText(until start: Date, now: Date, locale: Locale) -> String {
        let seconds = max(0, ceil(start.timeIntervalSince(now)))
        return Duration.seconds(seconds).formatted(.units(
            allowed: [.minutes, .seconds], width: .wide,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }

    /// The link Calendar resolves to one appointment. A series shares one
    /// identifier across its occurrences, so the clicked start (UTC, or the
    /// local day for all-day events) picks the right one.
    package static func eventURL(_ event: NotchCalendarEvent, calendar: Calendar = .current) -> URL? {
        guard !event.calendarItemIdentifier.isEmpty,
              let identifier = event.calendarItemIdentifier
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        var path = "ical://ekevent/"
        if event.recurring {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = event.allDay ? calendar.timeZone : TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            path += formatter.string(from: event.start) + "/"
        }
        return URL(string: path + identifier + "?method=show&options=more")
    }

    package static func nextRefresh(_ events: [NotchCalendarEvent], now: Date,
                            calendar: Calendar = .current) -> Date {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(900)
        return (upcoming(events, now: now).flatMap { [$0.start, $0.end] } + [midnight, now.addingTimeInterval(900)])
            .filter { $0 > now }.min() ?? now.addingTimeInterval(900)
    }
}
