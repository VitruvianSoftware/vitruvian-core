// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The times Remind Me offers.
///
/// Inferred (inventory 02 §1.2): the inventory names the six suggestions but not when each one is. These are
/// worked out like this, in the time zone of the calendar given (the Mac's):
///
/// | Suggestion | Time | Offered |
/// |---|---|---|
/// | In an Hour | now + 1 hour | always |
/// | In Two Hours | now + 2 hours | always |
/// | This Evening | today 18:00 | before 17:00 |
/// | Tomorrow | tomorrow 09:00 | always |
/// | This Weekend | the coming Saturday 09:00 | Monday to Thursday |
/// | Next Week | the coming Monday 09:00 | always |
///
/// "Last Used <time>" comes first while the time of the last reminder set is still to come. The clock times are
/// found by calendar days, not by adding hours, so they stay 09:00 on the day the clocks change.
public enum ReminderPresets {
    public static let defaultSuggestions: [String] = [
        "In an Hour",
        "In Two Hours",
        "This Evening",
        "Tomorrow",
        "This Weekend",
        "Next Week",
    ]
    public static let minSuggestionsCount = 1
    public static let maxSuggestionsCount = 8

    /// - Parameters:
    ///   - now: the moment the menu opens.
    ///   - calendar: the calendar, and so the time zone, the times are worked out in.
    ///   - lastUsed: the time of the last reminder set; it leads the list if it is after `now`.
    ///   - suggestions: customizable list of suggestion labels (defaults to `defaultSuggestions`).
    public static func presets(
        now: Date,
        calendar: Calendar,
        lastUsed: Date? = nil,
        suggestions: [String] = defaultSuggestions
    ) -> [(title: String, date: Date)] {
        var presets: [(title: String, date: Date)] = []
        if let lastUsed, lastUsed > now {
            let time = lastUsed.formatted(Date.FormatStyle(
                date: .abbreviated, time: .shortened, locale: calendar.locale ?? .current, calendar: calendar,
                timeZone: calendar.timeZone))
            presets.append((String(localized: "Last Used \(time)"), lastUsed))
        }
        for suggestion in suggestions {
            if let resolved = resolveDate(for: suggestion, now: now, calendar: calendar) {
                presets.append((suggestion, resolved))
            }
        }
        return presets
    }

    public static func resolveDate(for suggestion: String, now: Date, calendar: Calendar) -> Date? {
        let trimmed = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch trimmed.lowercased() {
        case "in an hour", "in 1 hour":
            return now.addingTimeInterval(3600)
        case "in two hours", "in 2 hours":
            return now.addingTimeInterval(7200)
        case "this evening":
            guard calendar.component(.hour, from: now) < 17 else { return nil }
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
        case "tomorrow":
            return morning(daysAfter: 1, now: now, calendar: calendar)
        case "this weekend":
            let weekday = calendar.component(.weekday, from: now)
            guard (2 ... 5).contains(weekday) else { return nil }
            return morning(onWeekday: 7, now: now, calendar: calendar)
        case "next week":
            return morning(onWeekday: 2, now: now, calendar: calendar)
        default:
            return parseCustomSuggestion(trimmed, now: now, calendar: calendar)
        }
    }

    private static func parseCustomSuggestion(_ raw: String, now: Date, calendar: Calendar) -> Date? {
        let lower = raw.lowercased()
        let tokens = lower.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.count == 3, tokens[0] == "in", let amount = Int(tokens[1]), amount > 0 {
            let unit = tokens[2]
            if unit.hasPrefix("min") {
                return now.addingTimeInterval(TimeInterval(amount * 60))
            }
            if unit.hasPrefix("hour") || unit.hasPrefix("hr") {
                return now.addingTimeInterval(TimeInterval(amount * 3600))
            }
            if unit.hasPrefix("day") {
                return morning(daysAfter: amount, now: now, calendar: calendar)
            }
            if unit.hasPrefix("week") {
                return morning(daysAfter: amount * 7, now: now, calendar: calendar)
            }
        }
        if lower.contains("tomorrow") {
            let hour = extractClockHour(from: lower) ?? 9
            guard let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
                return nil
            }
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
        }
        // Fallback for custom free-text presets (e.g. "Friday afternoon"): default to tomorrow at 09:00 so it is always actionable.
        return morning(daysAfter: 1, now: now, calendar: calendar)
    }

    private static func extractClockHour(from lower: String) -> Int? {
        let pattern = #"(\d{1,2})\s*(am|pm)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..<lower.endIndex, in: lower)),
              let hourRange = Range(match.range(at: 1), in: lower),
              let meridiemRange = Range(match.range(at: 2), in: lower),
              var hour = Int(lower[hourRange]),
              (1...12).contains(hour)
        else { return nil }
        let meridiem = String(lower[meridiemRange])
        if meridiem == "pm", hour < 12 { hour += 12 }
        if meridiem == "am", hour == 12 { hour = 0 }
        return hour
    }

    /// 09:00 on the day `days` after the day of `now`.
    private static func morning(daysAfter days: Int, now: Date, calendar: Calendar) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }

    /// 09:00 on the first day after today that is `weekday` (1 is Sunday, as `Calendar` has it). Never today: on a
    /// Monday, next Monday is a week away.
    private static func morning(onWeekday weekday: Int, now: Date, calendar: Calendar) -> Date? {
        for days in 1 ... 7 {
            guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return nil }
            if calendar.component(.weekday, from: day) == weekday {
                return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
            }
        }
        return nil
    }
}
