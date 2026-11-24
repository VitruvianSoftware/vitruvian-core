// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

/// Motion and visibility rules for the inbox chat-row hover action (Archive / Mark Read / More).
public enum InboxRowHoverMotion {
    /// Duration of the hover button's scale+fade entrance/exit (0.1 s ease-in-out).
    public static let duration: TimeInterval = 0.1

    /// Whether the row hover action button is visible and interactive.
    public static func showsHoverAction(isHovered: Bool, isSelecting: Bool, hoverAction: HoverAction) -> Bool {
        isHovered && !isSelecting && hoverAction != .nothing
    }

    /// Whether the row's right-side indicators (unread badge, mention, reminder, muted) are visible.
    public static func showsIndicators(isHovered: Bool, isSelecting: Bool, hoverAction: HoverAction) -> Bool {
        !isSelecting && !showsHoverAction(isHovered: isHovered, isSelecting: isSelecting, hoverAction: hoverAction)
    }

    /// Whether the hover action button can act (e.g. a pinned unarchived chat cannot be archived until unpinned).
    public static func isHoverActionEnabled(isPinned: Bool, isArchived: Bool, hoverAction: HoverAction) -> Bool {
        hoverAction == .archive ? (!isPinned || isArchived) : true
    }

    /// SF Symbol name for the row hover action button, or `nil` when `hoverAction == .nothing`.
    public static func hoverActionSymbol(isArchived: Bool, isUnread: Bool, hoverAction: HoverAction) -> String? {
        switch hoverAction {
        case .archive:
            isArchived ? "tray.and.arrow.up" : "archivebox"
        case .toggleRead:
            isUnread ? "envelope.open" : "envelope.badge"
        case .menu:
            "ellipsis.circle"
        case .nothing:
            nil
        }
    }

    /// Scale factor for the hover button: grows from 0 to 1, or stays 1 under Reduce Motion.
    public static func scale(isVisible: Bool, reduceMotion: Bool) -> CGFloat {
        reduceMotion ? 1 : (isVisible ? 1 : 0)
    }

    /// Opacity for the hover button.
    public static func opacity(isVisible: Bool) -> Double {
        isVisible ? 1 : 0
    }
}

/// Choreographed timing and layout values for multi-select checkbox entrance/exit in inbox rows.
public enum InboxSelectionMotion {
    public static let widthDuration: TimeInterval = 0.16
    public static let opacityDuration: TimeInterval = 0.12
    public static let checkboxSlotWidth: CGFloat = 22

    public struct Timing: Equatable, Sendable {
        public let widthDuration: TimeInterval
        public let widthDelay: TimeInterval
        public let opacityDuration: TimeInterval
        public let opacityDelay: TimeInterval
        public let animatesWidth: Bool

        public init(
            widthDuration: TimeInterval,
            widthDelay: TimeInterval,
            opacityDuration: TimeInterval,
            opacityDelay: TimeInterval,
            animatesWidth: Bool
        ) {
            self.widthDuration = widthDuration
            self.widthDelay = widthDelay
            self.opacityDuration = opacityDuration
            self.opacityDelay = opacityDelay
            self.animatesWidth = animatesWidth
        }
    }

    /// On enter: width expands over 0.16 s, then opacity fades in over 0.12 s after a 0.16 s delay.
    /// On exit: opacity fades out over 0.12 s immediately, then width collapses over 0.16 s after a 0.12 s delay.
    /// Under Reduce Motion: no width animation (snaps), short 0.12 s fade only.
    public static func timing(entering: Bool, reduceMotion: Bool) -> Timing {
        if reduceMotion {
            return Timing(
                widthDuration: 0,
                widthDelay: 0,
                opacityDuration: opacityDuration,
                opacityDelay: 0,
                animatesWidth: false
            )
        }
        if entering {
            return Timing(
                widthDuration: widthDuration,
                widthDelay: 0,
                opacityDuration: opacityDuration,
                opacityDelay: widthDuration,
                animatesWidth: true
            )
        }
        return Timing(
            widthDuration: widthDuration,
            widthDelay: opacityDuration,
            opacityDuration: opacityDuration,
            opacityDelay: 0,
            animatesWidth: true
        )
    }

    public static func checkboxWidth(isSelecting: Bool, rowSpacing: CGFloat) -> CGFloat {
        isSelecting ? checkboxSlotWidth + rowSpacing : 0
    }

    public static func checkboxOpacity(isSelecting: Bool) -> Double {
        isSelecting ? 1 : 0
    }
}
