// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import XCTest

@testable import VitruvianCourierCore

final class StreamBMotionTests: XCTestCase {
    // MARK: - Tooltip placement inside the window (Items 3 & 4)

    func testTooltipPlacementStaysStrictlyInsideWindowBounds() {
        let window = CGRect(x: 0, y: 0, width: 900, height: 600)
        let tooltip = CGSize(width: 190, height: 48)
        let margin = CourierTooltipPlacement.windowMargin

        // Centered anchor above control fits on top edge.
        let middleAnchor = CGRect(x: 420, y: 300, width: 32, height: 28)
        let centered = CourierTooltipPlacement.place(
            tooltipSize: tooltip,
            anchor: middleAnchor,
            in: window,
            preferredEdge: .top
        )
        XCTAssertEqual(centered.resolvedEdge, .top)
        XCTAssertEqual(centered.frame.midX, middleAnchor.midX, accuracy: 0.5)
        XCTAssertLessThan(centered.frame.maxY, middleAnchor.minY)
        XCTAssertGreaterThanOrEqual(centered.frame.minX, margin)
        XCTAssertLessThanOrEqual(centered.frame.maxX, window.maxX - margin)

        // Item 4 regression: emoji button near the bottom-right corner must shift left and stay inside the window.
        let emojiAnchor = CGRect(x: 842, y: 556, width: 28, height: 34)
        let emojiResult = CourierTooltipPlacement.place(
            tooltipSize: CGSize(width: 220, height: 52),
            anchor: emojiAnchor,
            in: window,
            preferredEdge: .top
        )
        XCTAssertEqual(emojiResult.resolvedEdge, .top)
        XCTAssertGreaterThanOrEqual(emojiResult.frame.minX, margin)
        XCTAssertLessThanOrEqual(emojiResult.frame.maxX, window.maxX - margin)
        XCTAssertGreaterThanOrEqual(emojiResult.frame.minY, margin)
        XCTAssertLessThanOrEqual(emojiResult.frame.maxY, window.maxY - margin)

        // Top-edge anchor flips .top -> .bottom when there is no room above.
        let headerAnchor = CGRect(x: 200, y: 10, width: 26, height: 26)
        let topFlipped = CourierTooltipPlacement.place(
            tooltipSize: tooltip,
            anchor: headerAnchor,
            in: window,
            preferredEdge: .top
        )
        XCTAssertEqual(topFlipped.resolvedEdge, .bottom)
        XCTAssertGreaterThanOrEqual(topFlipped.frame.minY, headerAnchor.maxY)
        XCTAssertLessThanOrEqual(topFlipped.frame.maxY, window.maxY - margin)

        // Bottom-edge anchor flips .bottom -> .top when there is no room below.
        let bottomAnchor = CGRect(x: 200, y: 564, width: 26, height: 26)
        let bottomFlipped = CourierTooltipPlacement.place(
            tooltipSize: tooltip,
            anchor: bottomAnchor,
            in: window,
            preferredEdge: .bottom
        )
        XCTAssertEqual(bottomFlipped.resolvedEdge, .top)
        XCTAssertLessThanOrEqual(bottomFlipped.frame.maxY, bottomAnchor.minY)
        XCTAssertGreaterThanOrEqual(bottomFlipped.frame.minY, margin)

        // Left-rail anchor prefers .trailing and clamps near top/bottom edges.
        let railAnchor = CGRect(x: 10, y: 12, width: 40, height: 40)
        let railPlaced = CourierTooltipPlacement.place(
            tooltipSize: tooltip,
            anchor: railAnchor,
            in: window,
            preferredEdge: .trailing
        )
        XCTAssertEqual(railPlaced.resolvedEdge, .trailing)
        XCTAssertGreaterThanOrEqual(railPlaced.frame.minX, railAnchor.maxX)
        XCTAssertGreaterThanOrEqual(railPlaced.frame.minY, margin)
        XCTAssertLessThanOrEqual(railPlaced.frame.maxX, window.maxX - margin)

        // Right-edge anchor with .trailing preference flips to .leading.
        let farRightAnchor = CGRect(x: 860, y: 200, width: 30, height: 30)
        let rightFlipped = CourierTooltipPlacement.place(
            tooltipSize: tooltip,
            anchor: farRightAnchor,
            in: window,
            preferredEdge: .trailing
        )
        XCTAssertEqual(rightFlipped.resolvedEdge, .leading)
        XCTAssertLessThanOrEqual(rightFlipped.frame.maxX, farRightAnchor.minX)
        XCTAssertGreaterThanOrEqual(rightFlipped.frame.minX, margin)

        // Near left edge with .top preference clamps x >= margin.
        let leftEdgeAnchor = CGRect(x: 4, y: 300, width: 24, height: 24)
        let leftClamped = CourierTooltipPlacement.place(
            tooltipSize: tooltip,
            anchor: leftEdgeAnchor,
            in: window,
            preferredEdge: .top
        )
        XCTAssertGreaterThanOrEqual(leftClamped.frame.minX, margin)
    }

    func testShortcutKeyCapTokenization() {
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "⌘2"), ["⌘", "2"])
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "⌘⌥⇧S"), ["⌘", "⌥", "⇧", "S"])
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "⌃⌘Space"), ["⌃", "⌘", "Space"])
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "⌥Tab"), ["⌥", "Tab"])
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "Return"), ["Return"])
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "Esc"), ["Esc"])
        XCTAssertEqual(CourierShortcutKeyCaps.tokens(from: "   "), [])
    }

    // MARK: - Tooltip delay and neighbour warmup rules (Item 3)

    func testTooltipDelayAndNeighbourWarmupRules() {
        XCTAssertEqual(CourierTooltipMotion.initialDelay, 0.25, accuracy: 0.0001)
        XCTAssertEqual(CourierTooltipMotion.warmupWindow, 0.5, accuracy: 0.0001)
        XCTAssertEqual(CourierTooltipMotion.fadeDuration, 0.1, accuracy: 0.0001)

        var scheduler = CourierTooltipSchedulerState()

        // Cold hover requires 0.25 s delay.
        XCTAssertEqual(scheduler.hoverEntered(id: "archive", at: 10.0), 0.25, accuracy: 0.0001)
        XCTAssertFalse(scheduler.isVisible)

        // Leaving before 0.25 s cancels without warming up; stale timer firing returns false.
        XCTAssertFalse(scheduler.hoverExited(id: "archive", at: 10.1))
        XCTAssertFalse(scheduler.delayElapsed(for: "archive"))
        XCTAssertEqual(scheduler.hoverEntered(id: "reply", at: 10.15), 0.25, accuracy: 0.0001)

        // Delay completes -> tooltip becomes visible.
        XCTAssertTrue(scheduler.delayElapsed(for: "reply"))
        XCTAssertTrue(scheduler.isVisible)

        // Moving to a neighbour within 0.5 s after hiding shows immediately (0 s delay).
        XCTAssertTrue(scheduler.hoverExited(id: "reply", at: 10.5))
        XCTAssertFalse(scheduler.isVisible)
        XCTAssertEqual(scheduler.hoverEntered(id: "more", at: 10.9), 0)
        XCTAssertTrue(scheduler.isVisible)

        // Moving straight from one visible control to another before exit arrives keeps it visible immediately,
        // and the stale exit from the old control is ignored.
        XCTAssertEqual(scheduler.hoverEntered(id: "emoji", at: 11.2), 0)
        XCTAssertFalse(scheduler.hoverExited(id: "more", at: 11.21))
        XCTAssertTrue(scheduler.isVisible)
        XCTAssertEqual(scheduler.activeID, "emoji")

        // After leaving and waiting past 0.5 s, the 0.25 s delay returns.
        XCTAssertTrue(scheduler.hoverExited(id: "emoji", at: 12.0))
        XCTAssertEqual(scheduler.hoverEntered(id: "send", at: 12.51), 0.25, accuracy: 0.0001)
        XCTAssertFalse(scheduler.isVisible)

        // Explicit dismiss clears warmup.
        XCTAssertTrue(scheduler.delayElapsed(for: "send"))
        scheduler.dismiss(at: 13.0, preserveWarmup: false)
        XCTAssertFalse(scheduler.isVisible)
        XCTAssertEqual(scheduler.hoverEntered(id: "send", at: 13.1), 0.25, accuracy: 0.0001)
    }

    // MARK: - Emoji hover open/close rules (Item 5)

    func testEmojiPickerHoverOpenCloseAndClickPinRules() {
        XCTAssertEqual(EmojiPickerHoverMotion.openDelay, 0.15, accuracy: 0.0001)
        XCTAssertEqual(EmojiPickerHoverMotion.closeDelay, 0.3, accuracy: 0.0001)
        XCTAssertEqual(EmojiPickerHoverMotion.iconTintDuration, 0.1, accuracy: 0.0001)

        var hover = EmojiPickerHoverState()
        XCTAssertFalse(hover.isPresented)
        XCTAssertFalse(hover.isIconAccented)

        // Hovering while locked or without a room does nothing.
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: false), .none)
        XCTAssertFalse(hover.openDelayFired(canOpen: false))

        // Hovering button schedules open after 0.15 s; leaving early cancels open.
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: true), .scheduleOpen(0.15))
        XCTAssertEqual(hover.buttonHoverChanged(false, canOpen: true), .cancelOpen)
        XCTAssertFalse(hover.openDelayFired(canOpen: true))

        // Holding hover for 0.15 s opens in hoverOpen mode with accent icon and NO auto-focus theft.
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: true), .scheduleOpen(0.15))
        XCTAssertTrue(hover.openDelayFired(canOpen: true))
        XCTAssertEqual(hover.mode, .hoverOpen)
        XCTAssertTrue(hover.isPresented)
        XCTAssertTrue(hover.isIconAccented)
        XCTAssertFalse(hover.shouldAutoFocusSearch)

        // Moving pointer from button onto picker keeps it open and cancels pending close.
        XCTAssertEqual(hover.buttonHoverChanged(false, canOpen: true), .scheduleClose(0.3))
        XCTAssertEqual(hover.pickerHoverChanged(true), .cancelClose)
        XCTAssertFalse(hover.closeDelayFired())

        // Leaving picker while not on button schedules 0.3 s close; returning to button cancels close.
        XCTAssertEqual(hover.pickerHoverChanged(false), .scheduleClose(0.3))
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: true), .cancelClose)

        // Leaving both button and picker and firing 0.3 s timer closes and un-tints icon.
        XCTAssertEqual(hover.buttonHoverChanged(false, canOpen: true), .scheduleClose(0.3))
        XCTAssertTrue(hover.closeDelayFired())
        XCTAssertEqual(hover.mode, .closed)
        XCTAssertFalse(hover.isPresented)
        XCTAssertFalse(hover.isIconAccented)

        // Hover-open -> user interacts inside picker -> upgrades to pinned and cancels close.
        _ = hover.buttonHoverChanged(true, canOpen: true)
        XCTAssertTrue(hover.openDelayFired(canOpen: true))
        _ = hover.buttonHoverChanged(false, canOpen: true)
        XCTAssertEqual(hover.userInteractedWithPicker(), .cancelClose)
        XCTAssertEqual(hover.mode, .pinned)
        XCTAssertTrue(hover.shouldAutoFocusSearch)
        XCTAssertEqual(hover.pickerHoverChanged(false), .none)
        XCTAssertFalse(hover.closeDelayFired())

        // Click when pinned closes; click when closed opens pinned; click when hoverOpen pins it open.
        XCTAssertEqual(hover.buttonClicked(canOpen: true), .cancelAll)
        XCTAssertEqual(hover.mode, .closed)
        XCTAssertEqual(hover.buttonClicked(canOpen: true), .cancelAll)
        XCTAssertEqual(hover.mode, .pinned)
        XCTAssertTrue(hover.shouldAutoFocusSearch)

        _ = hover.externalDismiss()
        _ = hover.buttonHoverChanged(true, canOpen: true)
        XCTAssertTrue(hover.openDelayFired(canOpen: true))
        XCTAssertEqual(hover.buttonClicked(canOpen: true), .cancelAll)
        XCTAssertEqual(hover.mode, .pinned)
    }

    /// Dismissing the picker (Escape, an emoji chosen, a click on the button, a chat switch) while the pointer is still
    /// on the button must not open it again: the pointer has to leave the button first.
    func testEmojiPickerDoesNotReopenAfterDismissUntilPointerLeavesButton() {
        // Hover-opened, then dismissed from outside (Escape or an emoji chosen) with the pointer still on the button.
        var hover = EmojiPickerHoverState()
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: true), .scheduleOpen(0.15))
        XCTAssertTrue(hover.openDelayFired(canOpen: true))
        XCTAssertEqual(hover.externalDismiss(), .cancelAll)
        XCTAssertEqual(hover.mode, .closed)
        XCTAssertTrue(hover.awaitsPointerExit)
        // A second "pointer entered" for the same visit (AppKit sends one when the picker's window goes away).
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: true), .none)
        XCTAssertFalse(hover.openDelayFired(canOpen: true))
        XCTAssertEqual(hover.mode, .closed)
        // Leaving, then coming back, works as it did.
        XCTAssertEqual(hover.buttonHoverChanged(false, canOpen: true), .cancelOpen)
        XCTAssertFalse(hover.awaitsPointerExit)
        XCTAssertEqual(hover.buttonHoverChanged(true, canOpen: true), .scheduleOpen(0.15))
        XCTAssertTrue(hover.openDelayFired(canOpen: true))

        // Pinned by a click, then closed by a click, with the pointer on the button the whole time.
        var clicked = EmojiPickerHoverState()
        _ = clicked.buttonHoverChanged(true, canOpen: true)
        XCTAssertEqual(clicked.buttonClicked(canOpen: true), .cancelAll)
        XCTAssertEqual(clicked.mode, .pinned)
        XCTAssertEqual(clicked.buttonClicked(canOpen: true), .cancelAll)
        XCTAssertEqual(clicked.mode, .closed)
        XCTAssertEqual(clicked.buttonHoverChanged(true, canOpen: true), .none)
        XCTAssertFalse(clicked.openDelayFired(canOpen: true))
        _ = clicked.buttonHoverChanged(false, canOpen: true)
        XCTAssertEqual(clicked.buttonHoverChanged(true, canOpen: true), .scheduleOpen(0.15))

        // A dismissal while the pointer is elsewhere (the usual 0.3 s close) puts nothing in the way.
        var left = EmojiPickerHoverState()
        _ = left.buttonHoverChanged(true, canOpen: true)
        XCTAssertTrue(left.openDelayFired(canOpen: true))
        _ = left.buttonHoverChanged(false, canOpen: true)
        XCTAssertTrue(left.closeDelayFired())
        XCTAssertFalse(left.awaitsPointerExit)
        XCTAssertEqual(left.buttonHoverChanged(true, canOpen: true), .scheduleOpen(0.15))
    }

    // MARK: - Inbox hover archive visibility & selection checkbox motion (Items 2, 16, 18)

    func testInboxRowHoverArchiveVisibilityAndMotion() {
        XCTAssertEqual(InboxRowHoverMotion.duration, 0.1, accuracy: 0.0001)
        XCTAssertEqual(HoverFillMotion.duration, 0.1, accuracy: 0.0001)
        XCTAssertEqual(HoverFillMotion.animationDuration(reduceMotion: false), 0.1, accuracy: 0.0001)
        XCTAssertEqual(HoverFillMotion.animationDuration(reduceMotion: true), 0)

        // Shown on hover when not selecting and hoverAction != .nothing.
        XCTAssertTrue(InboxRowHoverMotion.showsHoverAction(isHovered: true, isSelecting: false, hoverAction: .archive))
        XCTAssertFalse(InboxRowHoverMotion.showsIndicators(isHovered: true, isSelecting: false, hoverAction: .archive))

        // Hidden when not hovered, when selecting, or when hoverAction == .nothing.
        XCTAssertFalse(InboxRowHoverMotion.showsHoverAction(isHovered: false, isSelecting: false, hoverAction: .archive))
        XCTAssertTrue(InboxRowHoverMotion.showsIndicators(isHovered: false, isSelecting: false, hoverAction: .archive))

        XCTAssertFalse(InboxRowHoverMotion.showsHoverAction(isHovered: true, isSelecting: true, hoverAction: .archive))
        XCTAssertFalse(InboxRowHoverMotion.showsIndicators(isHovered: true, isSelecting: true, hoverAction: .archive))

        XCTAssertFalse(InboxRowHoverMotion.showsHoverAction(isHovered: true, isSelecting: false, hoverAction: .nothing))
        XCTAssertTrue(InboxRowHoverMotion.showsIndicators(isHovered: true, isSelecting: false, hoverAction: .nothing))

        // Archive vs unarchive symbol and pinned guard.
        XCTAssertEqual(
            InboxRowHoverMotion.hoverActionSymbol(isArchived: false, isUnread: false, hoverAction: .archive),
            "archivebox"
        )
        XCTAssertEqual(
            InboxRowHoverMotion.hoverActionSymbol(isArchived: true, isUnread: false, hoverAction: .archive),
            "tray.and.arrow.up"
        )
        XCTAssertFalse(InboxRowHoverMotion.isHoverActionEnabled(isPinned: true, isArchived: false, hoverAction: .archive))
        XCTAssertTrue(InboxRowHoverMotion.isHoverActionEnabled(isPinned: false, isArchived: false, hoverAction: .archive))
        XCTAssertTrue(InboxRowHoverMotion.isHoverActionEnabled(isPinned: true, isArchived: true, hoverAction: .archive))

        // Scale 0 -> 1 normally; always 1 (fade only) under Reduce Motion.
        XCTAssertEqual(InboxRowHoverMotion.scale(isVisible: false, reduceMotion: false), 0)
        XCTAssertEqual(InboxRowHoverMotion.scale(isVisible: true, reduceMotion: false), 1)
        XCTAssertEqual(InboxRowHoverMotion.scale(isVisible: false, reduceMotion: true), 1)
        XCTAssertEqual(InboxRowHoverMotion.scale(isVisible: true, reduceMotion: true), 1)
        XCTAssertEqual(InboxRowHoverMotion.opacity(isVisible: false), 0)
        XCTAssertEqual(InboxRowHoverMotion.opacity(isVisible: true), 1)
    }

    func testSelectionCheckboxChoreographyAndReduceMotion() {
        let enter = InboxSelectionMotion.timing(entering: true, reduceMotion: false)
        XCTAssertTrue(enter.animatesWidth)
        XCTAssertEqual(enter.widthDuration, 0.16, accuracy: 0.0001)
        XCTAssertEqual(enter.widthDelay, 0)
        XCTAssertEqual(enter.opacityDuration, 0.12, accuracy: 0.0001)
        XCTAssertEqual(enter.opacityDelay, 0.16, accuracy: 0.0001)

        let exit = InboxSelectionMotion.timing(entering: false, reduceMotion: false)
        XCTAssertTrue(exit.animatesWidth)
        XCTAssertEqual(exit.opacityDuration, 0.12, accuracy: 0.0001)
        XCTAssertEqual(exit.opacityDelay, 0)
        XCTAssertEqual(exit.widthDuration, 0.16, accuracy: 0.0001)
        XCTAssertEqual(exit.widthDelay, 0.12, accuracy: 0.0001)

        let reduced = InboxSelectionMotion.timing(entering: true, reduceMotion: true)
        XCTAssertFalse(reduced.animatesWidth)
        XCTAssertEqual(reduced.widthDuration, 0)
        XCTAssertEqual(reduced.opacityDelay, 0)
        XCTAssertEqual(reduced.opacityDuration, 0.12, accuracy: 0.0001)

        XCTAssertEqual(InboxSelectionMotion.checkboxWidth(isSelecting: false, rowSpacing: 10), 0)
        XCTAssertGreaterThan(InboxSelectionMotion.checkboxWidth(isSelecting: true, rowSpacing: 10), 20)
        XCTAssertEqual(InboxSelectionMotion.checkboxOpacity(isSelecting: false), 0)
        XCTAssertEqual(InboxSelectionMotion.checkboxOpacity(isSelecting: true), 1)
    }
}
