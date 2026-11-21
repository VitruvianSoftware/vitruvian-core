// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// The floating date under the chat's header: which day the top of the timeline is in, how it reads, and when a scroll
/// shows it. All data here is made up.
final class FloatingDayTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ month: Int, _ day: Int, _ hour: Int = 12, year: Int = 2026) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = day; parts.hour = hour
        return utc.date(from: parts)!
    }

    private func event(_ id: String, at date: Date) -> Event {
        let content = try! JSONDecoder().decode(
            JSONValue.self, from: Data(#"{"msgtype":"m.text","body":"hi"}"#.utf8))
        return Event(eventID: id, roomID: "!room", sender: "@ann:example.test", senderName: "Ann", mine: false,
                     type: "m.room.message", content: content, ts: Int64(date.timeIntervalSince1970 * 1000), seq: 0,
                     status: .sent)
    }

    /// Two days of messages: Nov 10 ($a, $b) and Nov 12 ($c). Items: day, $a, $b, day, $c.
    private func items() -> [TimelineItem] {
        let events = [event("$a", at: at(11, 10, 9)), event("$b", at: at(11, 10, 10)), event("$c", at: at(11, 12, 8))]
        return Timeline.build(events: events, me: Timeline.meUserID, now: at(11, 21), calendar: utc)
    }

    func testTheDayOfTheMessageAtTheTopIsItsDividers() {
        let items = items()
        XCTAssertEqual(items.count, 5)
        let day = { (row: Int) in FloatingDay.day(topRow: row, itemAt: { items.indices.contains($0) ? items[$0] : nil },
                                                  calendar: self.utc) }
        XCTAssertEqual(day(1), at(11, 10, 0), "the first day's first message")
        XCTAssertEqual(day(2), at(11, 10, 0), "its second message, still that day")
        XCTAssertEqual(day(4), at(11, 12, 0), "past the next divider it is the next day")
    }

    func testNoCapsuleWhenTheTopRowIsADateDivider() {
        let items = items()
        let day = { (row: Int) in FloatingDay.day(topRow: row, itemAt: { items.indices.contains($0) ? items[$0] : nil },
                                                  calendar: self.utc) }
        XCTAssertNil(day(0), "the divider itself is the date")
        XCTAssertNil(day(3))
    }

    func testNoCapsuleForARowThatHoldsNoItem() {
        let items = items()
        // Row 0 is the "load earlier" row, which holds no item; the items follow it.
        let itemAt = { (row: Int) -> TimelineItem? in row >= 1 && row - 1 < items.count ? items[row - 1] : nil }
        XCTAssertNil(FloatingDay.day(topRow: 0, itemAt: itemAt, calendar: utc))
        XCTAssertNil(FloatingDay.day(topRow: -1, itemAt: itemAt, calendar: utc))
        XCTAssertNil(FloatingDay.day(topRow: 99, itemAt: itemAt, calendar: utc))
        XCTAssertEqual(FloatingDay.day(topRow: 2, itemAt: itemAt, calendar: utc), at(11, 10, 0),
                       "the rows above the top one are skipped when they hold nothing")
    }

    func testWithoutADividerAboveTheMessagesOwnDayIsUsed() {
        let items = items().filter { if case .dateSeparator = $0 { false } else { true } }
        XCTAssertEqual(FloatingDay.day(topRow: 2, itemAt: { items.indices.contains($0) ? items[$0] : nil }, calendar: utc),
                       at(11, 12, 0))
    }

    func testTheLabelFollowsTheDividersWording() {
        let now = at(11, 21)
        XCTAssertEqual(FloatingDay.Label.of(day: at(11, 21, 0), now: now, calendar: utc), .today)
        XCTAssertEqual(FloatingDay.Label.of(day: at(11, 20, 0), now: now, calendar: utc), .yesterday)
        XCTAssertEqual(FloatingDay.Label.of(day: at(11, 19, 0), now: now, calendar: utc), .weekday(at(11, 19, 0)))
        XCTAssertEqual(FloatingDay.Label.of(day: at(11, 15, 0), now: now, calendar: utc), .weekday(at(11, 15, 0)),
                       "six days ago is still a weekday")
        XCTAssertEqual(FloatingDay.Label.of(day: at(11, 14, 0), now: now, calendar: utc),
                       .date(at(11, 14, 0), includesYear: false), "seven days ago is a date")
        XCTAssertEqual(FloatingDay.Label.of(day: at(12, 30, 0, year: 2025), now: now, calendar: utc),
                       .date(at(12, 30, 0, year: 2025), includesYear: true))
    }

    func testTheWords() {
        let now = at(11, 21)
        let en = Locale(identifier: "en_US")
        func text(_ day: Date) -> String { FloatingDay.text(day: day, now: now, calendar: utc, locale: en) }
        XCTAssertEqual(text(at(11, 21, 0)), "Today")
        XCTAssertEqual(text(at(11, 20, 0)), "Yesterday")
        XCTAssertEqual(text(at(11, 19, 0)), "Thursday")
        XCTAssertEqual(text(at(11, 14, 0)), "Sat, Nov 14")
        XCTAssertEqual(text(at(11, 14, 0, year: 2025)), "Fri, Nov 14, 2025")
    }

    func testOnlyAPersonsScrollShowsIt() {
        XCTAssertTrue(FloatingDay.showsForScroll(isProgrammatic: false, secondsSinceUserScroll: 0.05))
        XCTAssertFalse(FloatingDay.showsForScroll(isProgrammatic: true, secondsSinceUserScroll: 0.05),
                       "the app moving the timeline (a new message) is not a scroll")
        XCTAssertFalse(FloatingDay.showsForScroll(isProgrammatic: false, secondsSinceUserScroll: 30),
                       "no gesture just now: the jump to the newest message, a search result")
    }

    func testTimings() {
        XCTAssertEqual(FloatingDay.fadeOutDelay, 1.0)
        XCTAssertEqual(FloatingDay.fadeDuration, 0.2)
    }

    func testTheHeaderButtonSaysWhatItDoes() {
        XCTAssertEqual(ChatInfoHeaderToggle.label(isShowing: false), "Show chat info")
        XCTAssertEqual(ChatInfoHeaderToggle.label(isShowing: true), "Hide chat info")
    }
}
