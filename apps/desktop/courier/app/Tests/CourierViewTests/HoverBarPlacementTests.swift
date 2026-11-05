// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import Courier

/// Where the hover bar goes: beside a bubble with room for it, so the message above stays readable; over the top
/// corner of one too wide for that, inside the row.
final class HoverBarPlacementTests: XCTestCase {
    private let row = CGSize(width: 672, height: 40)
    private let bar = CGSize(width: 260, height: 28)

    func testBesideTheirShortBubble() {
        let bubble = CGRect(x: 36, y: 3, width: 36, height: 30)
        let spot = HoverBarPlacement.origin(bubble: bubble, row: row, bar: bar, mine: false)
        XCTAssertEqual(spot.x, bubble.maxX + HoverBarPlacement.gap, "on the right, across the gap")
        XCTAssertEqual(spot.y, bubble.minY, "level with the bubble's top")
        XCTAssertGreaterThanOrEqual(spot.y, 0, "never above the row, over the message before it")
    }

    func testBesideMyShortBubble() {
        let bubble = CGRect(x: 580, y: 3, width: 92, height: 30)
        let spot = HoverBarPlacement.origin(bubble: bubble, row: row, bar: bar, mine: true)
        XCTAssertEqual(spot.x + bar.width, bubble.minX - HoverBarPlacement.gap, "on the left, across the gap")
        XCTAssertEqual(spot.y, bubble.minY)
    }

    func testCentredOnABubbleShorterThanTheBarButNeverAboveTheRow() {
        let low = CGRect(x: 36, y: 20, width: 40, height: 18)
        XCTAssertEqual(HoverBarPlacement.origin(bubble: low, row: row, bar: bar, mine: false).y,
                       low.midY - bar.height / 2)
        let top = CGRect(x: 36, y: 1, width: 40, height: 18)
        XCTAssertEqual(HoverBarPlacement.origin(bubble: top, row: row, bar: bar, mine: false).y, 0)
    }

    func testJustFitsBeside() {
        let edge = row.width - HoverBarPlacement.edgeMargin - bar.width - HoverBarPlacement.gap
        let fits = CGRect(x: 36, y: 3, width: edge - 36, height: 30)
        XCTAssertEqual(HoverBarPlacement.origin(bubble: fits, row: row, bar: bar, mine: false).x,
                       fits.maxX + HoverBarPlacement.gap)
        let tooWide = CGRect(x: 36, y: 3, width: edge - 35, height: 30)
        XCTAssertLessThan(HoverBarPlacement.origin(bubble: tooWide, row: row, bar: bar, mine: false).y, tooWide.minY,
                          "one point wider and it goes over the corner")
    }

    func testOverTheCornerOfAWideBubbleInsideTheRow() {
        let bubble = CGRect(x: 36, y: 3, width: 560, height: 60)
        let spot = HoverBarPlacement.origin(bubble: bubble, row: row, bar: bar, mine: false)
        XCTAssertEqual(spot.y, bubble.minY - bar.height + HoverBarPlacement.cornerOverlap, "raised over the top edge")
        XCTAssertEqual(spot.x, row.width - bar.width - HoverBarPlacement.edgeMargin, "held inside the row")
        let mine = CGRect(x: 60, y: 3, width: 612, height: 60)
        XCTAssertEqual(HoverBarPlacement.origin(bubble: mine, row: row, bar: bar, mine: true).x,
                       HoverBarPlacement.edgeMargin)
    }
}
