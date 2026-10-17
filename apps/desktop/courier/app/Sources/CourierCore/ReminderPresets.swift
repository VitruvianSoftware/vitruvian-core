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
    /// - Parameters:
    ///   - now: the moment the menu opens.
    ///   - calendar: the calendar, and so the time zone, the times are worked out in.
    ///   - lastUsed: the time of the last reminder set; it leads the list if it is after `now`.
    public static func presets(now: Date, calendar: Calendar, lastUsed: Date? = nil) -> [(title: String, date: Date)] {
        var presets: [(title: String, date: Date)] = []
        if let lastUsed, lastUsed > now {
            let time = lastUsed.formatted(Date.FormatStyle(
                date: .abbreviated, time: .shortened, locale: calendar.locale ?? .current, calendar: calendar,
                timeZone: calendar.timeZone))
            presets.append((String(localized: "Last Used \(time)"), lastUsed))
        }
        presets.append((String(localized: "In an Hour"), now.addingTimeInterval(3600)))
        presets.append((String(localized: "In Two Hours"), now.addingTimeInterval(7200)))
        if calendar.component(.hour, from: now) < 17,
           let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) {
            presets.append((String(localized: "This Evening"), evening))
        }
        if let tomorrow = morning(daysAfter: 1, now: now, calendar: calendar) {
            presets.append((String(localized: "Tomorrow"), tomorrow))
        }
        // Monday to Thursday; from Friday the weekend is here (or close enough to say "Tomorrow").
        let weekday = calendar.component(.weekday, from: now)
        if (2 ... 5).contains(weekday), let saturday = morning(onWeekday: 7, now: now, calendar: calendar) {
            presets.append((String(localized: "This Weekend"), saturday))
        }
        if let monday = morning(onWeekday: 2, now: now, calendar: calendar) {
            presets.append((String(localized: "Next Week"), monday))
        }
        return presets
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
