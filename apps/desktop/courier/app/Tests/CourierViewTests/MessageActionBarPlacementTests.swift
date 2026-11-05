// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import Courier

/// Where the selected message's action bar goes: beside a bubble with room for it, so the message above stays
/// readable; over the top corner of one too wide for that, inside the row.
final class MessageActionBarPlacementTests: XCTestCase {
    private let row = CGSize(width: 672, height: 40)
    private let bar = CGSize(width: 260, height: 28)

    func testBesideTheirShortBubble() {
        let bubble = CGRect(x: 36, y: 3, width: 36, height: 30)
        let spot = MessageActionBarPlacement.origin(bubble: bubble, row: row, bar: bar, mine: false)
        XCTAssertEqual(spot.x, bubble.maxX + MessageActionBarPlacement.gap, "on the right, across the gap")
        XCTAssertEqual(spot.y, bubble.minY, "level with the bubble's top")
        XCTAssertGreaterThanOrEqual(spot.y, 0, "never above the row, over the message before it")
    }

    func testBesideMyShortBubble() {
        let bubble = CGRect(x: 580, y: 3, width: 92, height: 30)
        let spot = MessageActionBarPlacement.origin(bubble: bubble, row: row, bar: bar, mine: true)
        XCTAssertEqual(spot.x + bar.width, bubble.minX - MessageActionBarPlacement.gap, "on the left, across the gap")
        XCTAssertEqual(spot.y, bubble.minY)
    }

    func testCentredOnABubbleShorterThanTheBarButNeverAboveTheRow() {
        let low = CGRect(x: 36, y: 20, width: 40, height: 18)
        XCTAssertEqual(MessageActionBarPlacement.origin(bubble: low, row: row, bar: bar, mine: false).y,
                       low.midY - bar.height / 2)
        let top = CGRect(x: 36, y: 1, width: 40, height: 18)
        XCTAssertEqual(MessageActionBarPlacement.origin(bubble: top, row: row, bar: bar, mine: false).y, 0)
    }

    func testJustFitsBeside() {
        let edge = row.width - MessageActionBarPlacement.edgeMargin - bar.width - MessageActionBarPlacement.gap
        let fits = CGRect(x: 36, y: 3, width: edge - 36, height: 30)
        XCTAssertEqual(MessageActionBarPlacement.origin(bubble: fits, row: row, bar: bar, mine: false).x,
                       fits.maxX + MessageActionBarPlacement.gap)
        let tooWide = CGRect(x: 36, y: 3, width: edge - 35, height: 30)
        XCTAssertLessThan(MessageActionBarPlacement.origin(bubble: tooWide, row: row, bar: bar, mine: false).y, tooWide.minY,
                          "one point wider and it goes over the corner")
    }

    func testOverTheCornerOfAWideBubbleInsideTheRow() {
        let bubble = CGRect(x: 36, y: 3, width: 560, height: 60)
        let spot = MessageActionBarPlacement.origin(bubble: bubble, row: row, bar: bar, mine: false)
        XCTAssertEqual(spot.y, bubble.minY - bar.height + MessageActionBarPlacement.cornerOverlap, "raised over the top edge")
        XCTAssertEqual(spot.x, row.width - bar.width - MessageActionBarPlacement.edgeMargin, "held inside the row")
        let mine = CGRect(x: 60, y: 3, width: 612, height: 60)
        XCTAssertEqual(MessageActionBarPlacement.origin(bubble: mine, row: row, bar: bar, mine: true).x,
                       MessageActionBarPlacement.edgeMargin)
    }
}

/// Where the who-reacted card goes: above its chip, unless that would cover the selected message's action bar.
final class ReactionCardPlacementTests: XCTestCase {
    private let row = CGSize(width: 672, height: 90)
    private let card = CGSize(width: 220, height: 70)
    /// A chip under a short bubble, near the row's left.
    private let chip = CGRect(x: 40, y: 60, width: 40, height: 20)

    func testAboveTheChipWithNoBar() {
        let spot = ReactionCardPlacement.origin(chip: chip, row: row, card: card, avoiding: nil)
        XCTAssertEqual(spot.y, chip.minY - card.height - ReactionCardPlacement.gap)
        XCTAssertEqual(spot.x, ReactionCardPlacement.edgeMargin, "centred on the chip, but held inside the row")
    }

    func testAboveTheChipWhenTheBarIsElsewhere() {
        let bar = CGRect(x: 400, y: 10, width: 260, height: 28)
        let spot = ReactionCardPlacement.origin(chip: chip, row: row, card: card, avoiding: bar)
        XCTAssertEqual(spot.y, chip.minY - card.height - ReactionCardPlacement.gap)
    }

    /// The case in the running app: the bar beside a short bubble, right where the card above the chip would go.
    func testBelowTheChipWhenAboveWouldCoverTheBar() {
        let bar = CGRect(x: 120, y: 20, width: 260, height: 28)
        let spot = ReactionCardPlacement.origin(chip: chip, row: row, card: card, avoiding: bar)
        XCTAssertEqual(spot.y, chip.maxY + ReactionCardPlacement.gap, "below the chip, across the gap")
        XCTAssertEqual(spot.x, ReactionCardPlacement.edgeMargin, "still held inside the row")
        let placed = CGRect(origin: spot, size: card)
        XCTAssertFalse(placed.intersects(bar))
    }

    /// Before the bar has measured itself it has no size, and covers nothing.
    func testABarNotYetMeasuredIsIgnored() {
        let bar = CGRect(x: 60, y: 20, width: 0, height: 0)
        let spot = ReactionCardPlacement.origin(chip: chip, row: row, card: card, avoiding: bar)
        XCTAssertEqual(spot.y, chip.minY - card.height - ReactionCardPlacement.gap)
    }
}
