// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// How a search result's row reads: its date, its place tag, its sender and a person's groups.
final class SearchPresentationTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    /// Friday 16 October 2026, 15:30 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_792_164_600) }

    private func millis(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 5) -> Int64 {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private func text(_ ms: Int64, locale: Locale? = nil) -> String {
        SearchDate.text(forMillis: ms, now: now, calendar: calendar, locale: locale ?? self.locale)
            .replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testDateIsTheTimeTodayTheDayThisYearElseTheWholeDate() {
        XCTAssertEqual(text(millis(2026, 10, 16)), "9:05 AM", "today: the time")
        XCTAssertEqual(text(millis(2026, 10, 15, 23, 59)), "Oct 15", "yesterday is a day, not a weekday")
        XCTAssertEqual(text(millis(2026, 1, 2)), "Jan 2", "this year: day and month")
        XCTAssertEqual(text(millis(2025, 12, 31)), "Dec 31, 2025", "last year: the whole date")
        XCTAssertEqual(text(millis(2025, 12, 31), locale: Locale(identifier: "en_GB")), "31 Dec 2025",
                       "the locale decides the order")
        XCTAssertEqual(text(0), "")
    }

    func testPlaceTagsOutsideTheInbox() throws {
        XCTAssertNil(ChatPlace.inbox.tag)
        XCTAssertEqual(ChatPlace.archive.tag, "Archived")
        XCTAssertEqual(ChatPlace.lowPriority.tag, "Low priority")
        XCTAssertEqual(ChatPlace.hidden.tag, "Hidden")
        XCTAssertEqual(ChatPlace.requests.tag, "Request")
        XCTAssertNil(ChatPlace(rawValue: "somewhere_new").tag)

        // A chat row's place, decided as the engine decides a message's.
        var row = InboxRow(roomID: "!a", network: "whatsapp", name: "A", avatarPath: "", isDirect: true, lastTS: 1,
                           preview: "", previewKind: .text, previewMine: false, unread: 0, muted: false)
        XCTAssertEqual(row.place, .inbox)
        row.archived = true
        XCTAssertEqual(row.place, .archive)
        row.lowPriority = true
        XCTAssertEqual(row.place, .lowPriority, "low priority before archived")
        row.request = true
        XCTAssertEqual(row.place, .requests)
        row.hidden = true
        XCTAssertEqual(row.place, .hidden, "hidden first")
    }

    func testSenderIsYouForMine() {
        var hit = MessageHit(eventID: "$1", roomID: "!a", roomName: "A", network: "signal", isDirect: true,
                             sender: "@signal_x:courier.local", senderName: "Sam", mine: false, ts: 1, seq: 1,
                             snippet: "hi")
        XCTAssertEqual(hit.senderLine, "Sam")
        hit.senderName = ""
        XCTAssertEqual(hit.senderLine, "@signal_x:courier.local", "no name: their ID")
        hit.mine = true
        XCTAssertEqual(hit.senderLine, "You")
    }

    func testPersonSaysWhichGroups() {
        var person = PersonHit(userID: "@x", name: "Sam", network: "signal", roomID: "!g", roomName: "Hiking",
                               groups: 1)
        XCTAssertEqual(person.groupsLine, "In Hiking")
        person.groups = 2
        XCTAssertEqual(person.groupsLine, "In Hiking and 1 other group")
        person.groups = 4
        XCTAssertEqual(person.groupsLine, "In Hiking and 3 other groups")
    }
}
