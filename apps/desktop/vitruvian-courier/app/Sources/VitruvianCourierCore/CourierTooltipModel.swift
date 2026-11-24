// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

/// Timing rules for fast styled tooltips: 250 ms cold hover, instant while moving between neighbours for 500 ms,
/// and a 100 ms opacity fade.
public enum CourierTooltipMotion {
    public static let initialDelay: TimeInterval = 0.25
    public static let warmupWindow: TimeInterval = 0.5
    public static let fadeDuration: TimeInterval = 0.1
}

/// Timing rules for subtle button hover fill eases.
public enum HoverFillMotion {
    public static let duration: TimeInterval = 0.1

    public static func animationDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : duration
    }
}

/// Preferred side relative to the hovered control where a tooltip tries to appear.
public enum CourierTooltipEdge: Equatable, Sendable {
    case top
    case bottom
    case leading
    case trailing

    public var opposite: Self {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}

/// Resolved window-space frame (top-left origin) and edge chosen for a tooltip.
public struct CourierTooltipPlacementResult: Equatable, Sendable {
    public let frame: CGRect
    public let resolvedEdge: CourierTooltipEdge

    public init(frame: CGRect, resolvedEdge: CourierTooltipEdge) {
        self.frame = frame
        self.resolvedEdge = resolvedEdge
    }
}

/// Pure window-edge flipping and clamping logic for tooltips (top-left origin, `y` increases downward).
public enum CourierTooltipPlacement {
    public static let anchorGap: CGFloat = 6
    public static let windowMargin: CGFloat = 8

    public static func place(
        tooltipSize: CGSize,
        anchor: CGRect,
        in windowBounds: CGRect,
        preferredEdge: CourierTooltipEdge = .top,
        gap: CGFloat = anchorGap,
        margin: CGFloat = windowMargin
    ) -> CourierTooltipPlacementResult {
        let inset = windowBounds.insetBy(dx: margin, dy: margin)
        let safe = (inset.width >= 0 && inset.height >= 0) ? inset : windowBounds

        let resolvedEdge = chooseEdge(
            preferred: preferredEdge,
            tooltipSize: tooltipSize,
            anchor: anchor,
            safeBounds: safe,
            gap: gap
        )

        let rawOrigin: CGPoint
        switch resolvedEdge {
        case .top:
            rawOrigin = CGPoint(
                x: anchor.midX - tooltipSize.width / 2,
                y: anchor.minY - gap - tooltipSize.height
            )
        case .bottom:
            rawOrigin = CGPoint(
                x: anchor.midX - tooltipSize.width / 2,
                y: anchor.maxY + gap
            )
        case .leading:
            rawOrigin = CGPoint(
                x: anchor.minX - gap - tooltipSize.width,
                y: anchor.midY - tooltipSize.height / 2
            )
        case .trailing:
            rawOrigin = CGPoint(
                x: anchor.maxX + gap,
                y: anchor.midY - tooltipSize.height / 2
            )
        }

        let maxX = max(safe.minX, safe.maxX - tooltipSize.width)
        let maxY = max(safe.minY, safe.maxY - tooltipSize.height)
        let clampedX = min(max(rawOrigin.x, safe.minX), maxX)
        let clampedY = min(max(rawOrigin.y, safe.minY), maxY)

        return CourierTooltipPlacementResult(
            frame: CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: tooltipSize),
            resolvedEdge: resolvedEdge
        )
    }

    private static func chooseEdge(
        preferred: CourierTooltipEdge,
        tooltipSize: CGSize,
        anchor: CGRect,
        safeBounds: CGRect,
        gap: CGFloat
    ) -> CourierTooltipEdge {
        let opposite = preferred.opposite
        let required: CGFloat = switch preferred {
        case .top, .bottom: tooltipSize.height
        case .leading, .trailing: tooltipSize.width
        }
        let preferredSpace = availableSpace(on: preferred, anchor: anchor, safeBounds: safeBounds, gap: gap)
        if preferredSpace >= required {
            return preferred
        }
        let oppositeSpace = availableSpace(on: opposite, anchor: anchor, safeBounds: safeBounds, gap: gap)
        if oppositeSpace >= required {
            return opposite
        }
        return oppositeSpace > preferredSpace ? opposite : preferred
    }

    private static func availableSpace(
        on edge: CourierTooltipEdge,
        anchor: CGRect,
        safeBounds: CGRect,
        gap: CGFloat
    ) -> CGFloat {
        switch edge {
        case .top:
            anchor.minY - gap - safeBounds.minY
        case .bottom:
            safeBounds.maxY - (anchor.maxY + gap)
        case .leading:
            anchor.minX - gap - safeBounds.minX
        case .trailing:
            safeBounds.maxX - (anchor.maxX + gap)
        }
    }
}

/// Splits a keyboard shortcut string (e.g. `"⌘⌥⇧S"`, `"⌃⌘Space"`, `"Return"`) into individual key-cap tokens.
public enum CourierShortcutKeyCaps {
    private static let modifierSymbols: Set<Character> = ["⌃", "⌥", "⇧", "⌘", "🌐"]

    public static func tokens(from shortcut: String) -> [String] {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var result: [String] = []
        var run = ""

        func flushRun() {
            if !run.isEmpty {
                result.append(run)
                run = ""
            }
        }

        for character in trimmed {
            if character.isWhitespace {
                flushRun()
            } else if modifierSymbols.contains(character) {
                flushRun()
                result.append(String(character))
            } else {
                run.append(character)
            }
        }
        flushRun()
        return result
    }
}

/// Pure delay and neighbour-warmup state machine for styled tooltips.
public struct CourierTooltipSchedulerState: Equatable, Sendable {
    public private(set) var activeID: String?
    public private(set) var isVisible: Bool = false
    public private(set) var lastDismissedAt: TimeInterval?

    public init() {}

    /// Pointer entered control `id` at monotonic timestamp `now`.
    /// Returns the delay (in seconds) before presenting, or `0` when already warm/visible.
    public mutating func hoverEntered(id: String, at now: TimeInterval) -> TimeInterval {
        if isVisible {
            activeID = id
            isVisible = true
            return 0
        }
        if let dismissed = lastDismissedAt,
           now >= dismissed,
           now - dismissed <= CourierTooltipMotion.warmupWindow {
            activeID = id
            isVisible = true
            return 0
        }
        activeID = id
        isVisible = false
        return CourierTooltipMotion.initialDelay
    }

    /// Pending initial delay finished for `id`. Returns `true` only if `id` is still the active hover target.
    public mutating func delayElapsed(for id: String) -> Bool {
        guard activeID == id else { return false }
        isVisible = true
        return true
    }

    /// Pointer left control `id` at `now`. Returns `true` if a visible tooltip should hide.
    public mutating func hoverExited(id: String, at now: TimeInterval) -> Bool {
        guard activeID == id else { return false }
        let wasVisible = isVisible
        if wasVisible {
            lastDismissedAt = now
        }
        activeID = nil
        isVisible = false
        return wasVisible
    }

    /// Dismisses any active/pending tooltip (e.g. click, scroll, or window resign).
    public mutating func dismiss(at now: TimeInterval, preserveWarmup: Bool = false) {
        if preserveWarmup, isVisible {
            lastDismissedAt = now
        } else {
            lastDismissedAt = nil
        }
        activeID = nil
        isVisible = false
    }
}
