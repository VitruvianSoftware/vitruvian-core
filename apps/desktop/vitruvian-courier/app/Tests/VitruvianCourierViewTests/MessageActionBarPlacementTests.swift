// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import VitruvianCourier

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

    func testCompactHoverPillGoesRightOfTheirsAndLeftOfMine() {
        let hoverPill = CGSize(width: 84, height: 28)
        let theirs = CGRect(x: 36, y: 3, width: 120, height: 30)
        let theirSpot = MessageActionBarPlacement.origin(bubble: theirs, row: row, bar: hoverPill, mine: false)
        XCTAssertEqual(theirSpot.x, theirs.maxX + MessageActionBarPlacement.gap)
        XCTAssertEqual(theirSpot.y, theirs.minY)

        let mine = CGRect(x: 520, y: 3, width: 140, height: 30)
        let mySpot = MessageActionBarPlacement.origin(bubble: mine, row: row, bar: hoverPill, mine: true)
        XCTAssertEqual(mySpot.x + hoverPill.width, mine.minX - MessageActionBarPlacement.gap)
        XCTAssertEqual(mySpot.y, mine.minY)
    }
}

/// The compact hover pill (React, Reply, More) sits right beside the hovered bubble, centred on its last line.
final class HoverPillPlacementTests: XCTestCase {
    private let row = CGSize(width: 1000, height: 120)
    private let pill = CGSize(width: 84, height: 28)
    private let gap = MessageActionBarPlacement.gap

    func testSixPointsRightOfAShortBubbleOfTheirsWhateverTheRowsWidth() {
        let okay = CGRect(x: 36, y: 3, width: 52, height: 30)
        for width in [400.0, 1000.0, 2400.0] {
            let spot = MessageActionBarPlacement.origin(bubble: okay, row: CGSize(width: width, height: 40), bar: pill,
                                                        mine: false, level: .lastLine)
            XCTAssertEqual(spot.x, okay.maxX + gap, "next to the bubble, not at a place that follows the row")
        }
    }

    func testSixPointsLeftOfAShortBubbleOfMine() {
        let okay = CGRect(x: 900, y: 3, width: 52, height: 30)
        let spot = MessageActionBarPlacement.origin(bubble: okay, row: row, bar: pill, mine: true, level: .lastLine)
        XCTAssertEqual(spot.x + pill.width, okay.minX - gap)
    }

    func testCentredOnTheOnlyLineOfAShortBubble() {
        let okay = CGRect(x: 36, y: 3, width: 52, height: 30)
        let spot = MessageActionBarPlacement.origin(bubble: okay, row: row, bar: pill, mine: false, level: .lastLine)
        XCTAssertEqual(spot.y + pill.height / 2, okay.midY, accuracy: 1)
    }

    func testCentredOnTheLastLineOfAMultiLineTextBubbleNotItsTop() {
        let lines = CGRect(x: 36, y: 3, width: 300, height: 90)
        let spot = MessageActionBarPlacement.origin(bubble: lines, row: row, bar: pill, mine: false, level: .lastLine)
        XCTAssertEqual(spot.y + pill.height / 2, lines.maxY - MessageActionBarPlacement.lastLineCentreInset)
        XCTAssertGreaterThan(spot.y, lines.minY, "not at the top, as the selected message's bar is")
        let top = MessageActionBarPlacement.origin(bubble: lines, row: row, bar: pill, mine: false, level: .top)
        XCTAssertEqual(top.y, lines.minY)
    }

    /// A bubble taller than ~120 pt (a long text, a picture) takes the pill at its middle, not at its far-down last line.
    func testATallBubbleTakesThePillAtItsMiddleWhateverItHolds() {
        let tall = CGRect(x: 36, y: 3, width: 300, height: 260)
        let wasLastLine = MessageActionBarPlacement.origin(bubble: tall, row: CGSize(width: 1000, height: 300), bar: pill,
                                                           mine: false, level: .lastLine)
        XCTAssertEqual(wasLastLine.y + pill.height / 2, tall.midY, "a tall text bubble: the middle, not the last line")
        let photo = MessageActionBarPlacement.origin(bubble: tall, row: CGSize(width: 1000, height: 300), bar: pill,
                                                     mine: false, level: .centre)
        XCTAssertEqual(photo.y + pill.height / 2, tall.midY, "a picture: the middle")
        XCTAssertEqual(photo.x, tall.maxX + gap)
    }

    func testTheTallLimitIsAboutOneHundredAndTwentyPoints() {
        let atLimit = CGRect(x: 36, y: 3, width: 300, height: MessageActionBarPlacement.tallBubble)
        let over = CGRect(x: 36, y: 3, width: 300, height: MessageActionBarPlacement.tallBubble + 1)
        let r = CGSize(width: 1000, height: 300)
        XCTAssertEqual(MessageActionBarPlacement.tallBubble, 120)
        XCTAssertEqual(MessageActionBarPlacement.origin(bubble: atLimit, row: r, bar: pill, mine: false, level: .lastLine).y
                       + pill.height / 2, atLimit.maxY - MessageActionBarPlacement.lastLineCentreInset)
        XCTAssertEqual(MessageActionBarPlacement.origin(bubble: over, row: r, bar: pill, mine: false, level: .lastLine).y
                       + pill.height / 2, over.midY)
    }

    func testAShortPictureIsCentredToo() {
        let small = CGRect(x: 36, y: 3, width: 90, height: 60)
        let spot = MessageActionBarPlacement.origin(bubble: small, row: row, bar: pill, mine: false, level: .centre)
        XCTAssertEqual(spot.y + pill.height / 2, small.midY)
    }

    func testOverTheTopCornerWhenThereIsNoRoomBeside() {
        let wide = CGRect(x: 36, y: 3, width: 900, height: 40)
        let spot = MessageActionBarPlacement.origin(bubble: wide, row: row, bar: pill, mine: false, level: .lastLine)
        XCTAssertEqual(spot.y, wide.minY - pill.height + MessageActionBarPlacement.cornerOverlap)
        XCTAssertLessThanOrEqual(spot.x + pill.width, row.width - MessageActionBarPlacement.edgeMargin)
        let mine = CGRect(x: 60, y: 3, width: 900, height: 40)
        let mySpot = MessageActionBarPlacement.origin(bubble: mine, row: row, bar: pill, mine: true, level: .lastLine)
        XCTAssertEqual(mySpot.y, mine.minY - pill.height + MessageActionBarPlacement.cornerOverlap)
        XCTAssertGreaterThanOrEqual(mySpot.x, MessageActionBarPlacement.edgeMargin)
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
