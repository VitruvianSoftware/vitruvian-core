// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How a message's floating action UI renders: hidden, compact hover pill, or full selected action bar.
public enum ActionBarMode: Equatable, Sendable {
    case hidden
    case hoverPill
    case selectedBar
}

/// When a message's hover pill or selected action bar is on screen.
///
/// A hovered unselected message shows the compact pill (React, Reply, More) with a 120 ms fade; a selected message
/// shows the full bar. Neither shows while anything covers the timeline (⌘K search,
/// command bar, sheet, alert). Covering only pauses it: the pointer's place is kept, so when the cover closes with
/// the pointer still over the message, the bar/pill returns without re-entry. Both stay open while the message's
/// menu or reaction picker is open.
public enum ActionBarVisibility {
    /// Fade-in / fade-out duration for the hover pill (~120 ms).
    public static let hoverFadeDuration: TimeInterval = 0.12

    public static func mode(
        canAct: Bool,
        isSelected: Bool,
        menuOpen: Bool,
        pickingReaction: Bool,
        pointer: ActionBarPointer,
        timelineCovered: Bool
    ) -> ActionBarMode {
        guard canAct, !timelineCovered else { return .hidden }
        if menuOpen || pickingReaction {
            return isSelected ? .selectedBar : .hoverPill
        }
        if isSelected {
            return pointer.hasLeft ? .hidden : .selectedBar
        }
        if pointer.isHovered {
            return .hoverPill
        }
        return .hidden
    }

    public static func isShown(
        canAct: Bool,
        isSelected: Bool,
        menuOpen: Bool,
        pickingReaction: Bool,
        pointer: ActionBarPointer,
        timelineCovered: Bool
    ) -> Bool {
        mode(
            canAct: canAct,
            isSelected: isSelected,
            menuOpen: menuOpen,
            pickingReaction: pickingReaction,
            pointer: pointer,
            timelineCovered: timelineCovered
        ) != .hidden
    }
}

/// Where the pointer is, for one message's bar: in the row, on the bar, or gone from both.
///
/// Moving from the row onto its bar leaves the row an instant before it reaches the bar, so leaving counts only once
/// both have stayed empty for a moment: the view calls `settle()` after that moment. Until the pointer first
/// enters the message, nothing has left: a message selected with the arrow keys shows its bar.
public struct ActionBarPointer: Equatable, Sendable {
    /// How long both stay empty before the pointer counts as gone, in milliseconds.
    public static let settleMilliseconds = 120

    public private(set) var inRow = false
    public private(set) var onBar = false
    /// Whether the pointer entered this message and has not yet settled away.
    public private(set) var hasEntered = false
    /// The pointer went (or the timeline was covered), and has not come back.
    public private(set) var hasLeft = false

    public init() {}

    /// True while the pointer is on the row or on its bar.
    public var isOver: Bool { inRow || onBar }

    /// True while the pointer is hovering this message (including the brief crossing gap before `settle()`).
    public var isHovered: Bool { isOver || (hasEntered && !hasLeft) }

    public mutating func rowHover(_ inside: Bool) {
        inRow = inside
        if inside {
            hasEntered = true
            hasLeft = false
        }
    }

    public mutating func barHover(_ inside: Bool) {
        onBar = inside
        if inside {
            hasEntered = true
            hasLeft = false
        }
    }

    /// The moment after the pointer left both: it is gone, unless it came back.
    public mutating func settle() {
        if !isOver {
            hasLeft = true
            hasEntered = false
        }
    }

    /// The message was selected anew (a key, say): its bar shows.
    public mutating func selectionChanged() {
        hasLeft = false
    }
}
