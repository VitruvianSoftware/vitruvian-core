// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// How a row reads: its time, initials, preview label, unread count and network badge.
final class InboxPresentationTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    /// Friday 16 October 2026, 15:30 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_792_164_600) }

    private func time(daysAgo days: Int, hour: Int = 9, minute: Int = 5) -> Int64 {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    private func text(_ ms: Int64) -> String {
        plain(RelativeTime.text(forMillis: ms, now: now, calendar: calendar, locale: locale))
    }

    /// ICU puts a narrow no-break space before AM and PM.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func row(_ json: [String: Any]) throws -> InboxRow {
        try JSONDecoder().decode(InboxRow.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testTodayShowsTheTimeOfDay() {
        XCTAssertEqual(text(time(daysAgo: 0)), "9:05 AM")
        // The locale decides how: 24 hours in Germany.
        XCTAssertEqual(plain(RelativeTime.text(forMillis: time(daysAgo: 0, hour: 15), now: now, calendar: calendar,
                                               locale: Locale(identifier: "de_DE"))), "15:05")
    }

    func testTheLastSixDaysShowTheWeekday() {
        XCTAssertEqual(text(time(daysAgo: 1)), "Thursday")
        XCTAssertEqual(text(time(daysAgo: 6)), "Saturday")
    }

    func testOlderShowsTheShortDate() {
        XCTAssertEqual(text(time(daysAgo: 7)), "10/9/26")
        XCTAssertEqual(text(time(daysAgo: 200)), "3/30/26")
        XCTAssertEqual(plain(RelativeTime.text(forMillis: time(daysAgo: 7), now: now, calendar: calendar,
                                               locale: Locale(identifier: "en_GB"))), "09/10/2026")
    }

    func testNoTimeAndTheFutureAreHandled() {
        XCTAssertEqual(text(0), "", "a chat with no message yet shows no time")
        // A clock a little ahead is still today; a day ahead is a date, not a weekday.
        XCTAssertEqual(text(time(daysAgo: 0, hour: 23, minute: 59)), "11:59 PM")
        XCTAssertEqual(text(time(daysAgo: -1)), "10/17/26")
    }

    func testFormattersAreKeptNotBuiltPerRow() {
        _ = text(time(daysAgo: 0))
        _ = text(time(daysAgo: 1))
        _ = text(time(daysAgo: 9))
        let kept = RelativeTime.cachedFormatterCount
        for index in 0 ..< 500 { _ = text(time(daysAgo: index % 12)) }
        XCTAssertEqual(RelativeTime.cachedFormatterCount, kept, "500 rows, no new formatter")
        XCTAssertEqual(text(time(daysAgo: 1)), "Thursday")
    }

    func testTheTimeFollowsNow() {
        // The same message reads as today's time in the evening and as the weekday the next morning.
        let sent = time(daysAgo: 0)
        XCTAssertEqual(text(sent), "9:05 AM")
        let tomorrow = now.addingTimeInterval(24 * 3600)
        XCTAssertEqual(RelativeTime.text(forMillis: sent, now: tomorrow, calendar: calendar, locale: locale), "Friday")
    }

    func testInitials() {
        XCTAssertEqual(InboxRow.initials(of: "Ada Lovelace"), "AL")
        XCTAssertEqual(InboxRow.initials(of: "ada"), "A")
        XCTAssertEqual(InboxRow.initials(of: "  grace   brewster   hopper "), "GB", "two letters at most")
        XCTAssertEqual(InboxRow.initials(of: "Zoë"), "Z")
        XCTAssertEqual(InboxRow.initials(of: ""), "?")
        XCTAssertEqual(InboxRow.initials(of: "+1 555 0100"), "+5", "a number has no letters, so its characters stand in")
    }

    func testPreviewLabelsAndText() throws {
        let image = try row(room("!a", ts: 1, preview: "", kind: "image"))
        XCTAssertEqual(image.previewLabel, .image)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "video")).previewLabel, .video)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "audio")).previewLabel, .voiceNote)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "file")).previewLabel, .file)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "sticker")).previewLabel, .sticker)
        XCTAssertNil(try row(room("!a", ts: 1, kind: "text")).previewLabel)
        XCTAssertNil(try row(room("!a", ts: 1, kind: "")).previewLabel)
        XCTAssertEqual(try row(room("!a", ts: 1, kind: "poll")).previewLabel, .poll)
        XCTAssertEqual(PreviewLabel.poll.title, "Poll")
        // Ruling 40: a timer-change note previews in Courier's words, never the bridge's English (the engine sends no
        // text for it).
        let note = try row(room("!a", ts: 1, preview: "", kind: "timer_change"))
        XCTAssertEqual(note.previewLabel, .timerChange)
        XCTAssertEqual(PreviewLabel.timerChange.title, "Disappearing messages changed")
        XCTAssertNil(try row(room("!a", ts: 1, kind: "location")).previewLabel, "a kind from a newer engine is just text")
    }

    func testUnreadBadge() throws {
        XCTAssertNil(try row(room("!a", ts: 1, unread: 0)).unreadBadge)
        XCTAssertEqual(try row(room("!a", ts: 1, unread: 7)).unreadBadge, "7")
        XCTAssertEqual(try row(room("!a", ts: 1, unread: 99)).unreadBadge, "99")
        XCTAssertEqual(try row(room("!a", ts: 1, unread: 100)).unreadBadge, "99+")
    }

    func testEveryNetworkHasANeutralBadge() {
        var seen = Set<String>()
        for network in ["whatsapp", "signal", "telegram", "slack", "gmessages"] {
            let appearance = NetworkAppearance.of(network)
            XCTAssertNotEqual(appearance, NetworkAppearance.fallback, network)
            XCTAssertTrue(appearance.symbol.hasSuffix(".fill") || !appearance.symbol.isEmpty)
            seen.insert("\(appearance.symbol)/\(appearance.red)/\(appearance.green)/\(appearance.blue)")
        }
        XCTAssertEqual(seen.count, 5, "each network is told apart")
        XCTAssertEqual(NetworkAppearance.of("a-network-added-later"), NetworkAppearance.fallback)
    }
}
