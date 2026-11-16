// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// When a message's hover bar (quick reactions, Reply, More) is on screen.
///
/// It is the selected message's. It goes when the pointer leaves the message (its row, or the bar itself, which sits
/// over the row's top corner), and while anything covers the timeline: the ⌘K search panel, the command bar, a sheet
/// or an alert. Covering only pauses it: the pointer's place is kept, so when the cover closes with the pointer
/// still over the message, the bar is back without the pointer having to leave and return. It stays while the
/// message's own menu or reaction picker is open, which the pointer leaves to reach.
public enum ActionBarVisibility {
    public static func isShown(canAct: Bool, isSelected: Bool, menuOpen: Bool, pickingReaction: Bool,
                               pointer: ActionBarPointer, timelineCovered: Bool) -> Bool {
        guard canAct, !timelineCovered else { return false }
        if menuOpen || pickingReaction { return true }
        return isSelected && !pointer.hasLeft
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
    /// The pointer went (or the timeline was covered), and has not come back.
    public private(set) var hasLeft = false

    public init() {}

    /// True while the pointer is on the row or on its bar.
    public var isOver: Bool { inRow || onBar }

    public mutating func rowHover(_ inside: Bool) {
        inRow = inside
        if inside { hasLeft = false }
    }

    public mutating func barHover(_ inside: Bool) {
        onBar = inside
        if inside { hasLeft = false }
    }

    /// The moment after the pointer left both: it is gone, unless it came back.
    public mutating func settle() {
        if !isOver { hasLeft = true }
    }

    /// The message was selected anew (a key, say): its bar shows.
    public mutating func selectionChanged() {
        hasLeft = false
    }
}
