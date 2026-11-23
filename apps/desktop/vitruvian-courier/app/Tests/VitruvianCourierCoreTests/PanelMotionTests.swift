// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class PanelMotionTests: XCTestCase {
    func testSidePaneMotionConstantsAndReduceMotion() {
        XCTAssertEqual(SidePaneMotion.duration, 0.2, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.riseOffset, 10, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.curve, .cubicBezier(0.165, 0.84, 0.44, 1.0))

        XCTAssertTrue(SidePaneMotion.usesRise(reduceMotion: false))
        XCTAssertFalse(SidePaneMotion.usesRise(reduceMotion: true))

        XCTAssertEqual(SidePaneMotion.yOffset(isRevealed: false, reduceMotion: false), 10, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.yOffset(isRevealed: true, reduceMotion: false), 0, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.yOffset(isRevealed: false, reduceMotion: true), 0, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.yOffset(isRevealed: true, reduceMotion: true), 0, accuracy: 0.001)

        XCTAssertEqual(SidePaneMotion.opacity(isRevealed: false), 0, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.opacity(isRevealed: true), 1, accuracy: 0.001)

        XCTAssertEqual(SidePaneMotion.effectiveDuration(reduceMotion: false), 0.2, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.effectiveDuration(reduceMotion: true), SidePaneMotion.reduceMotionFadeDuration, accuracy: 0.001)
        XCTAssertEqual(SidePaneMotion.effectiveCurve(reduceMotion: false), .cubicBezier(0.165, 0.84, 0.44, 1.0))
        XCTAssertEqual(SidePaneMotion.effectiveCurve(reduceMotion: true), .easeOut)
    }

    func testCommandBarMotionTimingsCurvesAndReduceMotion() {
        XCTAssertEqual(CommandBarMotion.fadeInDuration, 0.12, accuracy: 0.001)
        XCTAssertEqual(CommandBarMotion.fadeOutDuration, 0.10, accuracy: 0.001)
        XCTAssertEqual(CommandBarMotion.fadeInCurve, .easeOut)
        XCTAssertEqual(CommandBarMotion.fadeOutCurve, .easeIn)

        XCTAssertEqual(CommandBarMotion.duration(isPresented: true, reduceMotion: false), 0.12, accuracy: 0.001)
        XCTAssertEqual(CommandBarMotion.duration(isPresented: false, reduceMotion: false), 0.10, accuracy: 0.001)
        XCTAssertEqual(CommandBarMotion.duration(isPresented: true, reduceMotion: true), 0.10, accuracy: 0.001)
        XCTAssertEqual(CommandBarMotion.duration(isPresented: false, reduceMotion: true), 0.10, accuracy: 0.001)

        XCTAssertEqual(CommandBarMotion.curve(isPresented: true, reduceMotion: false), .easeOut)
        XCTAssertEqual(CommandBarMotion.curve(isPresented: false, reduceMotion: false), .easeIn)
        XCTAssertEqual(CommandBarMotion.curve(isPresented: true, reduceMotion: true), .easeOut)
        XCTAssertEqual(CommandBarMotion.curve(isPresented: false, reduceMotion: true), .easeOut)

        XCTAssertFalse(CommandBarMotion.usesMovementOrScaling(reduceMotion: false))
        XCTAssertFalse(CommandBarMotion.usesMovementOrScaling(reduceMotion: true))
        XCTAssertTrue(CommandBarMotion.animatesSelectionScroll(reduceMotion: false))
        XCTAssertFalse(CommandBarMotion.animatesSelectionScroll(reduceMotion: true))
    }

    func testTypingLineMotionFadeAndDotAnimation() {
        XCTAssertEqual(TypingLineMotion.fadeDuration, 0.15, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(TypingLineMotion.reservedHeight, 20)
        XCTAssertFalse(TypingLineMotion.isVisible(text: nil))
        XCTAssertTrue(TypingLineMotion.isVisible(text: "Ana is typing…"))
        XCTAssertEqual(TypingLineMotion.opacity(text: nil), 0, accuracy: 0.001)
        XCTAssertEqual(TypingLineMotion.opacity(text: "Ana is typing…"), 1, accuracy: 0.001)

        XCTAssertTrue(TypingLineMotion.animatesDots(isVisible: true, reduceMotion: false))
        XCTAssertFalse(TypingLineMotion.animatesDots(isVisible: false, reduceMotion: false))
        XCTAssertFalse(TypingLineMotion.animatesDots(isVisible: true, reduceMotion: true))
        XCTAssertFalse(TypingLineMotion.usesMovement(reduceMotion: false))
        XCTAssertFalse(TypingLineMotion.usesMovement(reduceMotion: true))
    }

    func testSkeletonShimmerMotionVisibilityPhaseAndOffset() {
        XCTAssertEqual(SkeletonShimmerMotion.duration, 1.0, accuracy: 0.001)
        XCTAssertEqual(SkeletonShimmerMotion.curve, .linear)

        XCTAssertTrue(SkeletonShimmerMotion.shouldAnimate(isVisible: true, reduceMotion: false))
        XCTAssertFalse(SkeletonShimmerMotion.shouldAnimate(isVisible: false, reduceMotion: false))
        XCTAssertFalse(SkeletonShimmerMotion.shouldAnimate(isVisible: true, reduceMotion: true))
        XCTAssertFalse(SkeletonShimmerMotion.shouldAnimate(isVisible: false, reduceMotion: true))

        XCTAssertEqual(SkeletonShimmerMotion.phase(elapsed: 0.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(SkeletonShimmerMotion.phase(elapsed: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SkeletonShimmerMotion.phase(elapsed: 1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(SkeletonShimmerMotion.phase(elapsed: 1.25), 0.25, accuracy: 0.0001)
        XCTAssertEqual(SkeletonShimmerMotion.phase(elapsed: -0.25), 0.75, accuracy: 0.0001)
        XCTAssertEqual(SkeletonShimmerMotion.phase(elapsed: -1.0), 0.0, accuracy: 0.0001)

        let bandWidth = SkeletonShimmerMotion.bandWidth(containerWidth: 200)
        XCTAssertEqual(bandWidth, 110, accuracy: 0.001)
        XCTAssertEqual(SkeletonShimmerMotion.bandOffsetX(phase: 0, containerWidth: 200), -110, accuracy: 0.001)
        XCTAssertEqual(SkeletonShimmerMotion.bandOffsetX(phase: 1, containerWidth: 200), 200, accuracy: 0.001)
        XCTAssertEqual(SkeletonShimmerMotion.bandOffsetX(phase: 0.5, containerWidth: 200), 45, accuracy: 0.001)
    }

    func testScrollEdgeFadeVisibilityFlippedAndNonFlipped() {
        XCTAssertEqual(ScrollEdgeFadeMotion.fadeHeight, 10, accuracy: 0.001)
        XCTAssertEqual(ScrollEdgeFadeMotion.effectiveFadeHeight(containerHeight: 200), 10, accuracy: 0.001)
        XCTAssertEqual(ScrollEdgeFadeMotion.effectiveFadeHeight(containerHeight: 12), 6, accuracy: 0.001)
        XCTAssertEqual(ScrollEdgeFadeMotion.effectiveFadeHeight(containerHeight: 0), 0, accuracy: 0.001)

        // Empty or invalid geometry never shows edge fades.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 0, clipMinY: 0, clipMaxY: 100),
            .none
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 200, clipMinY: 0, clipMaxY: 0),
            .none
        )

        // Content fits within the viewport: no fade on either edge.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 120, clipMinY: 0, clipMaxY: 200),
            ScrollEdgeFadeState(top: false, bottom: false)
        )

        // Flipped document: at top, scrolled into middle, and at bottom.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 500, clipMinY: 0, clipMaxY: 200),
            ScrollEdgeFadeState(top: false, bottom: true)
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 500, clipMinY: 100, clipMaxY: 300),
            ScrollEdgeFadeState(top: true, bottom: true)
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 500, clipMinY: 300, clipMaxY: 500),
            ScrollEdgeFadeState(top: true, bottom: false)
        )

        // Threshold tolerance: <= 1 pt stays hidden, > 1 pt activates.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 201, clipMinY: 1, clipMaxY: 200),
            ScrollEdgeFadeState(top: false, bottom: false)
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 201.5, clipMinY: 1.5, clipMaxY: 200),
            ScrollEdgeFadeState(top: true, bottom: true)
        )

        // Rubber-band overscroll past top keeps top fade off.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(documentMinY: 0, documentMaxY: 500, clipMinY: -12, clipMaxY: 188),
            ScrollEdgeFadeState(top: false, bottom: true)
        )

        // Flipped document with top/bottom clip insets.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(
                documentMinY: 0,
                documentMaxY: 500,
                clipMinY: -20,
                clipMaxY: 180,
                topInset: 20,
                bottomInset: 10
            ),
            ScrollEdgeFadeState(top: false, bottom: true)
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(
                documentMinY: 0,
                documentMaxY: 500,
                clipMinY: 310,
                clipMaxY: 510,
                topInset: 20,
                bottomInset: 10
            ),
            ScrollEdgeFadeState(top: true, bottom: false)
        )

        // Non-flipped document (origin at bottom): clipMaxY == docMaxY is top, clipMinY == docMinY is bottom.
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(
                documentMinY: 0,
                documentMaxY: 500,
                clipMinY: 300,
                clipMaxY: 500,
                isFlipped: false
            ),
            ScrollEdgeFadeState(top: false, bottom: true)
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(
                documentMinY: 0,
                documentMaxY: 500,
                clipMinY: 150,
                clipMaxY: 350,
                isFlipped: false
            ),
            ScrollEdgeFadeState(top: true, bottom: true)
        )
        XCTAssertEqual(
            ScrollEdgeFadeMotion.state(
                documentMinY: 0,
                documentMaxY: 500,
                clipMinY: 0,
                clipMaxY: 200,
                isFlipped: false
            ),
            ScrollEdgeFadeState(top: true, bottom: false)
        )

        XCTAssertTrue(ScrollEdgeFadeMotion.animatesMaskChange(reduceMotion: false))
        XCTAssertFalse(ScrollEdgeFadeMotion.animatesMaskChange(reduceMotion: true))
    }

    func testChatInfoSectionMotionConstantsAndReduceMotion() {
        XCTAssertEqual(ChatInfoSectionMotion.expandDuration, 0.25, accuracy: 0.001)
        XCTAssertEqual(ChatInfoSectionMotion.expandCurve, .easeInOut)
        XCTAssertEqual(ChatInfoSectionMotion.chevronDuration, 0.20, accuracy: 0.001)
        XCTAssertEqual(ChatInfoSectionMotion.chevronCurve, .easeInOut)

        XCTAssertEqual(ChatInfoSectionMotion.chevronRotationDegrees(isOpen: false), 0, accuracy: 0.001)
        XCTAssertEqual(ChatInfoSectionMotion.chevronRotationDegrees(isOpen: true), 90, accuracy: 0.001)

        XCTAssertTrue(ChatInfoSectionMotion.animatesExpand(reduceMotion: false))
        XCTAssertFalse(ChatInfoSectionMotion.animatesExpand(reduceMotion: true))
        XCTAssertTrue(ChatInfoSectionMotion.animatesChevron(reduceMotion: false))
        XCTAssertFalse(ChatInfoSectionMotion.animatesChevron(reduceMotion: true))
    }

    func testScheduledStripMotionBounceKeyframesAndReduceMotion() {
        XCTAssertEqual(ScheduledStripMotion.chevronDuration, 0.30, accuracy: 0.001)
        XCTAssertEqual(ScheduledStripMotion.bounceDuration, 0.30, accuracy: 0.001)
        XCTAssertEqual(ScheduledStripMotion.chevronRotationDegrees(isOpen: false), 0, accuracy: 0.001)
        XCTAssertEqual(ScheduledStripMotion.chevronRotationDegrees(isOpen: true), 180, accuracy: 0.001)

        XCTAssertEqual(
            ScheduledStripMotion.bounceKeyframes,
            [
                MotionKeyframe(offsetY: -4, duration: 0.10),
                MotionKeyframe(offsetY: 2, duration: 0.10),
                MotionKeyframe(offsetY: 0, duration: 0.10),
            ]
        )
        let totalBounceDuration = ScheduledStripMotion.bounceKeyframes.reduce(0) { $0 + $1.duration }
        XCTAssertEqual(totalBounceDuration, ScheduledStripMotion.bounceDuration, accuracy: 0.001)

        XCTAssertEqual(ScheduledStripMotion.bounceOffsets(reduceMotion: false), [0, -4, 2, 0])
        XCTAssertEqual(ScheduledStripMotion.bounceOffsets(reduceMotion: true), [0])

        XCTAssertTrue(ScheduledStripMotion.animatesChevron(reduceMotion: false))
        XCTAssertFalse(ScheduledStripMotion.animatesChevron(reduceMotion: true))
        XCTAssertTrue(ScheduledStripMotion.animatesToggle(reduceMotion: false))
        XCTAssertFalse(ScheduledStripMotion.animatesToggle(reduceMotion: true))
        XCTAssertTrue(ScheduledStripMotion.shouldBounce(reduceMotion: false))
        XCTAssertFalse(ScheduledStripMotion.shouldBounce(reduceMotion: true))

        XCTAssertTrue(ScheduledStripMotion.hasNewlyQueuedMessage(previousIDs: [], currentIDs: [1]))
        XCTAssertTrue(ScheduledStripMotion.hasNewlyQueuedMessage(previousIDs: [1], currentIDs: [1, 2]))
        XCTAssertFalse(ScheduledStripMotion.hasNewlyQueuedMessage(previousIDs: [1, 2], currentIDs: [1, 2]))
        XCTAssertFalse(ScheduledStripMotion.hasNewlyQueuedMessage(previousIDs: [1, 2], currentIDs: [1]))
        XCTAssertFalse(ScheduledStripMotion.hasNewlyQueuedMessage(previousIDs: [], currentIDs: []))
    }
}
