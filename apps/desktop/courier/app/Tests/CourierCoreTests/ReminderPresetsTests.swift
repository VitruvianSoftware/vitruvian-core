// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// The reminder times Remind Me offers, worked out in London's time zone. October 2026: the clocks go back on
/// Sunday the 25th, so the week of the 21st crosses the change.
final class ReminderPresetsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func titles(_ now: Date) -> [String] {
        ReminderPresets.presets(now: now, calendar: calendar).map(\.title)
    }

    private func preset(_ title: String, _ now: Date) -> Date? {
        ReminderPresets.presets(now: now, calendar: calendar).first { $0.title == title }?.date
    }

    private let all = ["In an Hour", "In Two Hours", "This Evening", "Tomorrow", "This Weekend", "Next Week"]

    func testWednesdayMorningOffersAllSix() {
        let now = at(2026, 10, 21, 10) // Wednesday
        XCTAssertEqual(titles(now), all)
        XCTAssertEqual(preset("In an Hour", now), at(2026, 10, 21, 11))
        XCTAssertEqual(preset("In Two Hours", now), at(2026, 10, 21, 12))
        XCTAssertEqual(preset("This Evening", now), at(2026, 10, 21, 18))
        XCTAssertEqual(preset("Tomorrow", now), at(2026, 10, 22, 9))
        XCTAssertEqual(preset("This Weekend", now), at(2026, 10, 24, 9), "the coming Saturday")
        // The Monday after the clocks go back: 09:00 there is 09:00 GMT.
        XCTAssertEqual(preset("Next Week", now), utc("2026-10-26T09:00:00Z"))
        XCTAssertEqual(preset("Next Week", now), at(2026, 10, 26, 9))
    }

    func testThisEveningIsOnlyBeforeFive() {
        XCTAssertFalse(titles(at(2026, 10, 21, 17, 30)).contains("This Evening"))
        XCTAssertEqual(titles(at(2026, 10, 21, 17, 30)), all.filter { $0 != "This Evening" })
        XCTAssertTrue(titles(at(2026, 10, 21, 16, 59)).contains("This Evening"))
        XCTAssertFalse(titles(at(2026, 10, 21, 17, 0)).contains("This Evening"), "from 17:00 it is no longer \"before\"")
        XCTAssertFalse(titles(at(2026, 10, 21, 23, 0)).contains("This Evening"))
        XCTAssertTrue(titles(at(2026, 10, 21, 0, 5)).contains("This Evening"))
        // The rest still stand late in the day.
        XCTAssertEqual(preset("In Two Hours", at(2026, 10, 21, 23, 0)), at(2026, 10, 22, 1))
        XCTAssertEqual(preset("Tomorrow", at(2026, 10, 21, 23, 0)), at(2026, 10, 22, 9))
    }

    func testSaturdayHasNoWeekendAndNextWeekIsMonday() {
        let now = at(2026, 10, 24, 10) // Saturday
        XCTAssertEqual(titles(now), all.filter { $0 != "This Weekend" })
        XCTAssertEqual(preset("Tomorrow", now), at(2026, 10, 25, 9))
        XCTAssertEqual(preset("Next Week", now), at(2026, 10, 26, 9))
    }

    func testThisWeekendIsOfferedMondayToThursday() {
        for (day, offered) in [(19, true), (20, true), (21, true), (22, true), (23, false), (24, false), (25, false)] {
            let now = at(2026, 10, day, 10)
            XCTAssertEqual(titles(now).contains("This Weekend"), offered, "October \(day)")
        }
        XCTAssertEqual(preset("This Weekend", at(2026, 10, 19, 10)), at(2026, 10, 24, 9))
        XCTAssertEqual(preset("This Weekend", at(2026, 10, 22, 23, 0)), at(2026, 10, 24, 9))
    }

    func testNextWeekIsTheComingMondayNeverToday() {
        // On a Monday, even before nine, next week is a week away.
        XCTAssertEqual(preset("Next Week", at(2026, 10, 19, 7)), at(2026, 10, 26, 9))
        XCTAssertEqual(preset("Next Week", at(2026, 10, 19, 10)), at(2026, 10, 26, 9))
        // On a Sunday it is tomorrow.
        XCTAssertEqual(preset("Next Week", at(2026, 10, 18, 10)), at(2026, 10, 19, 9))
        // Tomorrow is tomorrow even before nine.
        XCTAssertEqual(preset("Tomorrow", at(2026, 10, 21, 6)), at(2026, 10, 22, 9))
    }

    func testTheClocksChangingSundayStillGivesNineLocal() {
        // Saturday evening, with BST still on: tomorrow is 09:00 GMT, 25 hours-ish away, not 24 hours on.
        let saturday = at(2026, 10, 24, 20)
        XCTAssertEqual(preset("Tomorrow", saturday), utc("2026-10-25T09:00:00Z"))
        XCTAssertEqual(calendar.component(.hour, from: preset("Tomorrow", saturday)!), 9)

        // The Sunday itself, before and after the change at 02:00 BST.
        for now in [at(2026, 10, 25, 0, 30), at(2026, 10, 25, 10)] {
            let tomorrow = preset("Tomorrow", now)!
            XCTAssertEqual(tomorrow, utc("2026-10-26T09:00:00Z"))
            XCTAssertEqual(calendar.component(.hour, from: tomorrow), 9)
            XCTAssertEqual(preset("Next Week", now), tomorrow)
        }

        // "In an hour" is an hour on the clock on the wall of the world, whatever the wall clock does.
        let early = at(2026, 10, 25, 0, 30)
        XCTAssertEqual(preset("In an Hour", early)!.timeIntervalSince(early), 3600)
        XCTAssertEqual(preset("In Two Hours", early)!.timeIntervalSince(early), 7200)

        // And in March, when they go forward: Sunday 29th, 09:00 BST is 08:00 UTC.
        XCTAssertEqual(preset("Tomorrow", at(2026, 3, 28, 20)), utc("2026-03-29T08:00:00Z"))
    }

    func testThePlaceIsTheCalendarsNotTheMacs() {
        // The same instant is Wednesday 10:00 in London and Wednesday 02:00 in Los Angeles.
        var losAngeles = calendar
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = at(2026, 10, 21, 10)
        let there = ReminderPresets.presets(now: now, calendar: losAngeles)
        XCTAssertEqual(there.map(\.title), all)
        var components = DateComponents(year: 2026, month: 10, day: 21, hour: 18)
        XCTAssertEqual(there.first { $0.title == "This Evening" }?.date, losAngeles.date(from: components))
        components = DateComponents(year: 2026, month: 10, day: 22, hour: 9)
        XCTAssertEqual(there.first { $0.title == "Tomorrow" }?.date, losAngeles.date(from: components))
    }

    func testLastUsedLeadsWhileItIsInTheFuture() {
        let now = at(2026, 10, 21, 10)
        let later = at(2026, 10, 23, 15, 30)

        let with = ReminderPresets.presets(now: now, calendar: calendar, lastUsed: later)
        XCTAssertEqual(with.count, 7)
        XCTAssertTrue(with[0].title.hasPrefix("Last Used "), with[0].title)
        XCTAssertEqual(with[0].date, later)
        XCTAssertTrue(with[0].title.contains("15:30"), "the time on the calendar's clock: \(with[0].title)")
        XCTAssertEqual(with.dropFirst().map(\.title), all)

        // Past, or right now: not offered. Nor when there is none.
        XCTAssertEqual(ReminderPresets.presets(now: now, calendar: calendar, lastUsed: now).count, 6)
        XCTAssertEqual(ReminderPresets.presets(now: now, calendar: calendar, lastUsed: at(2026, 10, 20, 9)).count, 6)
        XCTAssertEqual(ReminderPresets.presets(now: now, calendar: calendar, lastUsed: nil).count, 6)
        XCTAssertEqual(ReminderPresets.presets(now: now, calendar: calendar).count, 6)
    }

    func testCustomTimeSuggestionsAddRemoveAndReset() {
        let store = TestDefaults()
        defer { store.remove() }
        let preferences = InboxPreferences(defaults: store.defaults)
        XCTAssertEqual(preferences.timeSuggestions, ReminderPresets.defaultSuggestions)

        XCTAssertTrue(preferences.addTimeSuggestion("In 3 weeks"))
        XCTAssertEqual(preferences.timeSuggestions.last, "In 3 weeks")

        let now = at(2026, 10, 21, 10)
        let resolved = ReminderPresets.presets(
            now: now,
            calendar: calendar,
            suggestions: preferences.timeSuggestions
        )
        XCTAssertTrue(resolved.contains { $0.title == "In 3 weeks" })

        preferences.removeTimeSuggestion("In Two Hours")
        XCTAssertFalse(preferences.timeSuggestions.contains("In Two Hours"))

        preferences.resetTimeSuggestions()
        XCTAssertEqual(preferences.timeSuggestions, ReminderPresets.defaultSuggestions)
    }
}
