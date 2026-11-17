// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class SendLaterNudgeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: hour, minute: minute))!
    }

    func testLateRunsFrom2200Through0659() {
        XCTAssertFalse(SendLaterNudge.isLate(now: at(21, 59), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(22, 0), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(23, 30), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(0, 0), calendar: calendar))
        XCTAssertTrue(SendLaterNudge.isLate(now: at(6, 59), calendar: calendar))
        XCTAssertFalse(SendLaterNudge.isLate(now: at(7, 0), calendar: calendar))
        XCTAssertFalse(SendLaterNudge.isLate(now: at(14, 0), calendar: calendar))
    }

    func testShowsOnlyWhenLateWithTextAndNotDismissed() {
        let late = at(23)
        XCTAssertTrue(SendLaterNudge.shows(hasText: true, now: late, calendar: calendar, dismissed: false))
        XCTAssertFalse(SendLaterNudge.shows(hasText: false, now: late, calendar: calendar, dismissed: false))
        XCTAssertFalse(SendLaterNudge.shows(hasText: true, now: late, calendar: calendar, dismissed: true))
        XCTAssertFalse(SendLaterNudge.shows(hasText: true, now: at(12), calendar: calendar, dismissed: false))
    }
}

final class SpaceShortcutLabelTests: XCTestCase {
    func testLabelIsTheModifierThenThePosition() {
        let control = KeyChord(key: "", control: true)
        XCTAssertEqual(SpaceShortcutLabel.label(position: 2, modifier: control), "⌃2")
        XCTAssertEqual(SpaceShortcutLabel.label(position: 9, modifier: KeyChord(key: "", command: true)), "⌘9")
    }

    func testNoLabelPastNineOrWhenOff() {
        let control = KeyChord(key: "", control: true)
        XCTAssertNil(SpaceShortcutLabel.label(position: 10, modifier: control))
        XCTAssertNil(SpaceShortcutLabel.label(position: 0, modifier: control))
        XCTAssertNil(SpaceShortcutLabel.label(position: 1, modifier: nil))
    }
}
