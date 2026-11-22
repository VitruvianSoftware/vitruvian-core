// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

/// Tests for `CalendarBridge`, video-meeting URL extraction, noise-free future date detection,
/// on-demand EventKit authorization, and privacy isolation from the engine. All data is synthetic.
@MainActor
final class CalendarBridgeTests: XCTestCase {
    private var harnesses: [ConversationHarness] = []

    /// 2026-10-24 12:00:00 UTC.
    private let refDate = Date(timeIntervalSince1970: 1_792_843_200)

    override func tearDown() async throws {
        for harness in harnesses { await harness.stop() }
        harnesses = []
    }

    func testExtractsVideoMeetingURLs() {
        let extracted = CalendarBridge.extractMeetingURL(
            from: "Join at https://meet.google.com/abc-defg-hij or https://acme.zoom.us/j/12345"
        )
        XCTAssertEqual(extracted?.absoluteString, "https://meet.google.com/abc-defg-hij")

        XCTAssertEqual(
            CalendarBridge.extractMeetingURL(from: "Dial in: https://acme.zoom.us/j/12345")?.absoluteString,
            "https://acme.zoom.us/j/12345"
        )
        XCTAssertEqual(
            CalendarBridge.extractMeetingURL(from: "https://zoom.us/j/99999")?.absoluteString,
            "https://zoom.us/j/99999"
        )
        XCTAssertEqual(
            CalendarBridge.extractMeetingURL(from: "Teams: https://teams.microsoft.com/l/meetup-join/19%3ameeting")?.absoluteString,
            "https://teams.microsoft.com/l/meetup-join/19%3ameeting"
        )
        XCTAssertEqual(
            CalendarBridge.extractMeetingURL(from: "Webex: https://acme.webex.com/meet/alice")?.absoluteString,
            "https://acme.webex.com/meet/alice"
        )
        XCTAssertEqual(
            CalendarBridge.extractMeetingURL(from: "https://webex.com/meet/bob")?.absoluteString,
            "https://webex.com/meet/bob"
        )

        // Non-meeting URLs must be ignored.
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Read the doc at https://example.com/notes"))

        // Non-HTTPS URLs must be rejected.
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Insecure http://meet.google.com/abc-defg-hij"))
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "http://zoom.us/j/12345"))

        // Lookalike hosts must never match.
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Phishing https://zoom.us.evil.com/j/12345"))
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Phishing https://meet.google.com.evil.com/abc-defg-hij"))
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Phishing https://notzoom.us/j/12345"))
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Phishing https://evil-webex.com/meet/alice"))
        XCTAssertNil(CalendarBridge.extractMeetingURL(from: "Phishing https://teams.microsoft.com.attacker.example/join"))
    }

    func testDetectsDatesInMessageText() {
        let detected = CalendarBridge.detectDates(
            in: "Let's meet on 2026-10-25 at 14:30 UTC",
            referenceDate: refDate
        )
        XCTAssertEqual(detected.count, 1)
        XCTAssertTrue(detected[0].matchedText.contains("2026-10-25"))
        XCTAssertEqual(detected[0].durationSeconds, 3600)
        XCTAssertGreaterThan(detected[0].startDate, refDate)

        // Past dates must not be detected ("I was born in 1990" is not underlined).
        let pastDates = CalendarBridge.detectDates(
            in: "I was born in 1990",
            referenceDate: refDate
        )
        XCTAssertTrue(pastDates.isEmpty, "Past dates must not be underlined: \(pastDates)")

        // Future relative dates ("lunch tomorrow at 1pm") must be detected.
        let tomorrowDates = CalendarBridge.detectDates(
            in: "lunch tomorrow at 1pm",
            referenceDate: refDate
        )
        XCTAssertEqual(tomorrowDates.count, 1)
        XCTAssertTrue(tomorrowDates[0].matchedText.lowercased().contains("tomorrow"))
        XCTAssertGreaterThan(tomorrowDates[0].startDate, refDate)
        XCTAssertEqual(tomorrowDates[0].durationSeconds, 3600)

        // Dates inside markdown inline code spans or links must never be detected.
        XCTAssertTrue(
            CalendarBridge.detectDates(
                in: "Run `deploy --at 2026-10-25 14:30 UTC` in terminal",
                referenceDate: refDate
            ).isEmpty
        )
        XCTAssertTrue(
            CalendarBridge.detectDates(
                in: "See https://example.com/2026-10-25/schedule for details",
                referenceDate: refDate
            ).isEmpty
        )

        // Dates inside RichText code, pre, or link entities must never be detected.
        let codeText = "Check 2026-10-25 at 14:30 UTC in code"
        let codeRich = RichText(
            text: codeText,
            entities: [TextEntity(kind: .code, offset: 6, length: 23)]
        )
        XCTAssertTrue(CalendarBridge.detectDates(in: codeRich, referenceDate: refDate).isEmpty)
    }

    /// Ordinary day words are not dates; a date or a time is. Each row is (text, stays a detected date).
    func testBareDayWordsAreNotDetectedAsDates() {
        let table: [(String, Bool)] = [
            ("today", false), ("Today", false), ("tonight", false), ("tomorrow", false), ("yesterday", false),
            ("Sunday", false), ("Saturday", false), ("on Monday", false), ("this weekend", false),
            ("next Friday", false), ("tomorrow morning", false), ("Sat", false),
            ("Sunday at 7pm", true), ("tomorrow at 1pm", true), ("Nov 30", true), ("7:30pm", true),
            ("Nov 30 at 7pm", true), ("2026-10-25", true), ("next Friday at 3", true),
        ]
        for (text, keeps) in table {
            XCTAssertEqual(!CalendarBridge.isBareDayReference(text), keeps, "isBareDayReference(\(text))")
        }
        XCTAssertFalse(CalendarBridge.isBareDayReference(""))
        // What the detector says about the match decides first: one with a length or a time zone states a time.
        XCTAssertTrue(CalendarBridge.isBareDayReference("Sunday"))
        XCTAssertFalse(CalendarBridge.isBareDayReference("Sunday", duration: 3600), "a range is a stated time")
        XCTAssertFalse(CalendarBridge.isBareDayReference("Sunday", hasTimeZone: true), "a time zone is a stated time")

        // Through the real detector, from a date long ago so every match counts as upcoming.
        let long = Date(timeIntervalSince1970: 946_684_800)
        for (text, keeps) in table {
            let found = CalendarBridge.detectDates(in: "see you \(text) ok", referenceDate: long)
            if !keeps {
                XCTAssertTrue(found.isEmpty, "\"\(text)\" must stay ordinary, got \(found.map(\.matchedText))")
            } else if text != "next Friday at 3" {
                XCTAssertFalse(found.isEmpty, "\"\(text)\" must stay a date")
            }
        }
    }

    /// Words in other languages are never judged by the English day list: whatever the detector finds is kept, and a
    /// message that happens to be in English around them changes nothing.
    func testOtherLanguagesAreNotCaughtByTheBareDayFilter() {
        for text in ["domingo", "dimanche", "Sonntag", "hoy", "demain", "mañana a las 7", "dimanche à 19h", "日曜日", "明日"] {
            XCTAssertFalse(CalendarBridge.isBareDayReference(text), "\(text) is not English, so it is left as the detector found it")
        }
        // Not made only of day words: kept.
        for text in ["Sunday dinner", "today at noon", "this weekend trip", "Monday 3", "May 5"] {
            XCTAssertFalse(CalendarBridge.isBareDayReference(text), text)
        }
        // End to end with the real detector: a non-English message keeps whatever it matched before.
        let long = Date(timeIntervalSince1970: 946_684_800)
        for text in ["nos vemos el 5 de diciembre a las 19:00", "à demain 19h30", "Treffen am 30. November um 19 Uhr"] {
            let before = CalendarBridge.detectDates(in: text, referenceDate: long)
            XCTAssertFalse(before.isEmpty, "\(text) is a date the detector knows")
        }
    }

    func testDeniedCalendarAccessDoesNotPromptAndReportsDenied() async throws {
        let sampleEvent = CalendarEventItem(
            id: "ev-1",
            title: "Design Sync",
            startDate: refDate.addingTimeInterval(3600),
            endDate: refDate.addingTimeInterval(7200),
            isAllDay: false,
            calendarColorHex: "#0A84FF",
            location: "Room 3B",
            meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
        let store = FakeCalendarStore(status: .denied, events: [sampleEvent])
        let bridge = CalendarBridge(store: store, now: { self.refDate })

        // Never prompts at launch/init.
        XCTAssertEqual(bridge.status, .denied)
        XCTAssertEqual(store.requestAccessCalls, 0)
        XCTAssertEqual(bridge.events, [])
        XCTAssertTrue(bridge.isAccessDenied)

        // Opening the Calendar pane when denied never prompts again.
        await bridge.loadSelectedDay()
        XCTAssertEqual(bridge.status, .denied)
        XCTAssertEqual(store.requestAccessCalls, 0)
        XCTAssertEqual(bridge.events, [])

        // Restricted also never prompts and reports access denied.
        let restrictedStore = FakeCalendarStore(status: .restricted, events: [sampleEvent])
        let restrictedBridge = CalendarBridge(store: restrictedStore, now: { self.refDate })
        await restrictedBridge.loadSelectedDay()
        XCTAssertEqual(restrictedBridge.status, .restricted)
        XCTAssertEqual(restrictedStore.requestAccessCalls, 0)
        XCTAssertEqual(restrictedBridge.events, [])
        XCTAssertTrue(restrictedBridge.isAccessDenied)

        // When notDetermined, does not prompt at init, and prompts once when the pane opens.
        let promptStore = FakeCalendarStore(status: .notDetermined, requestGrantResult: true, events: [sampleEvent])
        let promptBridge = CalendarBridge(store: promptStore, now: { self.refDate })
        XCTAssertEqual(promptStore.requestAccessCalls, 0)
        XCTAssertEqual(promptBridge.events, [])
        await promptBridge.loadSelectedDay()
        XCTAssertEqual(promptStore.requestAccessCalls, 1)
        XCTAssertEqual(promptBridge.status, .fullAccess)
        XCTAssertEqual(promptBridge.events, [sampleEvent])
    }

    func testCalendarDataNeverSentToEngine() async throws {
        let secretEvent = CalendarEventItem(
            id: "ev-secret-99",
            title: "Secret Board Acquisition Sync",
            startDate: refDate.addingTimeInterval(1800),
            endDate: refDate.addingTimeInterval(5400),
            isAllDay: false,
            calendarColorHex: "#FF9F0A",
            location: "Confidential Room 404",
            meetingURL: URL(string: "https://meet.google.com/sec-retc-all")
        )
        let store = FakeCalendarStore(status: .fullAccess, events: [secretEvent])
        let time = FakeTime()
        let event = textEvent(id: "$m1", room: "!g", at: 1, body: "Lunch tomorrow at 1pm?", mine: false)
        let h = try await startConversation(
            ["!g": [event]],
            features: ["!g": featuresJSON()],
            rows: ["!g": chatRow("!g", name: "Team", network: "signal", direct: false)],
            sleep: { try await time.sleep(for: $0) }
        )
        harnesses.append(h)
        h.conversation.calendarBridge = CalendarBridge(store: store, now: { self.refDate })
        try await h.open("!g")

        // Toggle Calendar pane open and navigate days.
        h.conversation.toggleCalendar()
        XCTAssertTrue(h.conversation.isShowingCalendar)
        await h.conversation.calendarBridge.loadSelectedDay()
        XCTAssertEqual(h.conversation.calendarBridge.events.first?.title, "Secret Board Acquisition Sync")

        await h.conversation.calendarBridge.selectNextDay()
        await h.conversation.calendarBridge.selectPreviousDay()
        await h.conversation.calendarBridge.selectToday()

        // Create an event from a detected date popover click.
        let created = try await h.conversation.calendarBridge.addEvent(
            title: "Private Dentist Appointment",
            startDate: refDate.addingTimeInterval(86_400),
            endDate: refDate.addingTimeInterval(90_000),
            notes: "PrivateCalendarNote99"
        )
        XCTAssertEqual(created.title, "Private Dentist Appointment")

        // Verify no engine RPC request ever contains anything from EventKit / CalendarBridge.
        let serializedRequests = try JSONSerialization.data(withJSONObject: h.server.received)
        let payload = String(decoding: serializedRequests, as: UTF8.self)
        for forbidden in [
            "Secret Board Acquisition Sync",
            "Confidential Room 404",
            "sec-retc-all",
            "ev-secret-99",
            "Private Dentist Appointment",
            "PrivateCalendarNote99",
        ] {
            XCTAssertFalse(payload.contains(forbidden), "Engine RPC payload leaked calendar field: \(forbidden)")
        }
    }

    func testWriteOnlyAuthStatusOffersFullAccessUpgrade() async throws {
        let sampleEvent = CalendarEventItem(
            id: "ev-upgrade-1",
            title: "Architecture Review",
            startDate: refDate.addingTimeInterval(3600),
            endDate: refDate.addingTimeInterval(7200),
            isAllDay: false,
            calendarColorHex: "#0A84FF"
        )
        let writeOnlyStore = FakeCalendarStore(status: .writeOnly, requestGrantResult: true, events: [sampleEvent])
        let bridge = CalendarBridge(store: writeOnlyStore, now: { self.refDate })

        XCTAssertEqual(bridge.status, .writeOnly)
        XCTAssertFalse(bridge.isAccessDenied, "writeOnly is limited add-only access, not turned off")
        XCTAssertTrue(bridge.isWriteOnly)

        await bridge.loadSelectedDay()
        XCTAssertEqual(writeOnlyStore.requestAccessCalls, 1, "loadSelectedDay must request full access when status is .writeOnly")
        XCTAssertEqual(bridge.status, .fullAccess)
        XCTAssertEqual(bridge.events, [sampleEvent])
    }
}
