// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// The floating date is asked on every scroll event, so a call must be cheap: its words made once per day, nothing
/// published when nothing changed, and one fade-out timer for a run of events.
@MainActor
final class FloatingDayControllerTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_792_000_000)
    private let otherDay = Date(timeIntervalSince1970: 1_792_000_000 + 86_400)

    func testAScrollOverOneDayMakesTheWordsOnce() {
        var made = 0
        let controller = FloatingDayController(words: { _, _ in made += 1; return "Today" })
        for _ in 0 ..< 300 { controller.userScrolled(day: day) }
        XCTAssertEqual(made, 1, "no date formatting per scroll event")
        controller.userScrolled(day: otherDay)
        XCTAssertEqual(made, 2, "another day: its words")
        controller.userScrolled(day: day)
        XCTAssertEqual(made, 3)
    }

    func testTheWordsAreMadeAgainAfterTheyAreOld() {
        var made = 0
        let controller = FloatingDayController(words: { _, _ in made += 1; return "Today" })
        let now = Date()
        controller.userScrolled(day: day, now: now)
        controller.userScrolled(day: day, now: now.addingTimeInterval(30))
        XCTAssertEqual(made, 1)
        controller.userScrolled(day: day, now: now.addingTimeInterval(120))
        XCTAssertEqual(made, 2, "past midnight 'Today' reads differently")
    }

    func testNothingIsPublishedWhenNothingChanged() {
        let controller = FloatingDayController(words: { _, _ in "Today" })
        controller.userScrolled(day: day)
        var published = 0
        let sink = controller.model.objectWillChange.sink { published += 1 }
        for _ in 0 ..< 300 { controller.userScrolled(day: day) }
        XCTAssertEqual(published, 0, "every write wakes the capsule's view")
        controller.userScrolled(day: otherDay)
        XCTAssertEqual(published, 0, "the same words (the stand-in's) are not a change either")
        controller.userScrolled(day: nil)
        XCTAssertEqual(published, 1, "going hidden is one change")
        controller.userScrolled(day: nil)
        XCTAssertEqual(published, 1)
        sink.cancel()
    }

    func testARunOfScrollEventsStartsOneFadeOutTimerAndItHidesAfterTheLastOne() async {
        let controller = FloatingDayController(words: { _, _ in "Today" })
        for _ in 0 ..< 50 { controller.userScrolled(day: day) }
        XCTAssertEqual(controller.hideTimerStarts, 1, "one timer, pushed back, not one per event")
        XCTAssertTrue(controller.model.isVisible)
        // Scrolling goes on for a while: the timer is pushed back past its first deadline.
        try? await Task.sleep(for: .milliseconds(400))
        controller.userScrolled(day: day)
        try? await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(controller.model.isVisible, "the last scroll was 0.4 s ago: still showing")
        XCTAssertEqual(controller.hideTimerStarts, 1)
        try? await Task.sleep(for: .milliseconds(1000))
        XCTAssertFalse(controller.model.isVisible, "a second after the last scroll it has faded")
        controller.userScrolled(day: day)
        XCTAssertEqual(controller.hideTimerStarts, 2, "a new run of scrolling starts a new timer")
    }
}
