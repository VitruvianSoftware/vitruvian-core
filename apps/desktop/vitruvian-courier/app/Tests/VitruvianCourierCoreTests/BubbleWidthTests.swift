// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class BubbleWidthTests: XCTestCase {
    func testCapIsSixtyPercentOfTheRowBetweenTheFloorAndTheCeiling() {
        // (row width, cap)
        let table: [(CGFloat, CGFloat)] = [
            (300, 640), (800, 640), (1000, 640), // the old cap holds on medium windows
            (1200, 720), (1500, 900), // it grows with a wide window: 60%
            (1600, 960), (2400, 960), // and stops where long lines get hard to read
        ]
        for (row, cap) in table {
            XCTAssertEqual(BubbleWidth.maxWidth(rowWidth: row), cap, accuracy: 0.01, "row \(row)")
        }
    }

    func testCapFromTheRoomLeftForTheBubble() {
        // A 1500 pt row leaves 1432 for the bubble beside the 60 pt spacer and its gap; a group chat 36 less.
        XCTAssertEqual(BubbleWidth.maxWidth(offered: 1432, hasAvatarColumn: false), 900, accuracy: 0.01)
        XCTAssertEqual(BubbleWidth.maxWidth(offered: 1396, hasAvatarColumn: true), 900, accuracy: 0.01)
    }
}
