// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

// MARK: - Item 1: Atomic Chat Switch & Cold-Mount Loading

/// Rules and timing thresholds for switching to an uncached chat without flashing an empty pane.
public enum TimelineLoadMotion: Sendable {
    /// How long loading an uncached chat may take before showing the delayed spinner.
    public static let spinnerDelay: Duration = .milliseconds(250)
    public static let spinnerDelaySeconds: TimeInterval = 0.25

    /// True when the currently open, loaded chat should stay on screen (header, timeline, and composer together) while
    /// fetching `targetRoomID`'s first page instead of clearing the pane immediately.
    public static func shouldKeepPreviousChatVisible(
        currentRoomID: String?,
        isCurrentlyLoaded: Bool,
        targetRoomID: String?,
        isTargetCached: Bool,
        hasClient: Bool
    ) -> Bool {
        guard let currentRoomID,
              isCurrentlyLoaded,
              let targetRoomID,
              targetRoomID != currentRoomID,
              !isTargetCached,
              hasClient
        else { return false }
        return true
    }
}

// MARK: - Item 6: Jump-to-Latest Button

/// Motion and legibility parameters for `JumpToLatestButton`.
public enum JumpToLatestMotion: Sendable {
    public static let fadeDuration: TimeInterval = 0.15
    public static let reduceMotionDuration: TimeInterval = 0.10
    public static let appearDelay: TimeInterval = 0.05
    public static let appearDelayMilliseconds = 50
    public static let disappearDelay: TimeInterval = 0

    public static let shadowRadius: CGFloat = 8
    public static let shadowYOffset: CGFloat = 3
    public static let shadowOpacityLight: Double = 0.18
    public static let shadowOpacityDark: Double = 0.42
    public static let surfaceFillOpacityLight: Double = 0.94
    public static let surfaceFillOpacityDark: Double = 0.90

    public static func delay(appearing: Bool, reduceMotion: Bool) -> TimeInterval {
        (!appearing || reduceMotion) ? 0 : appearDelay
    }

    public static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionDuration : fadeDuration
    }
}

// MARK: - Item 7: Sent Message Rise-In

/// Animation parameters and bottom-right pivot maths for a locally sent message rising into the bottom of the
/// timeline.
public enum SentMessageRiseMotion: Sendable {
    public static let duration: TimeInterval = 0.26
    public static let reduceMotionDuration: TimeInterval = 0.15
    public static let initialOffsetY: CGFloat = 14
    public static let initialScale: CGFloat = 0.97
    public static let initialOpacity: Double = 0
    public static let controlPoints: (Float, Float, Float, Float) = (0.22, 1.0, 0.36, 1.0)

    public struct InitialTransform: Equatable, Sendable {
        public let opacity: Double
        public let offsetY: CGFloat
        public let scale: CGFloat
        public let duration: TimeInterval
        public let usesMovementAndScale: Bool

        public init(
            opacity: Double,
            offsetY: CGFloat,
            scale: CGFloat,
            duration: TimeInterval,
            usesMovementAndScale: Bool
        ) {
            self.opacity = opacity
            self.offsetY = offsetY
            self.scale = scale
            self.duration = duration
            self.usesMovementAndScale = usesMovementAndScale
        }
    }

    /// Initial transform for the sent-message entrance. Under Reduce Motion, movement and scaling are disabled and only
    /// a short opacity fade runs.
    public static func initialTransform(reduceMotion: Bool) -> InitialTransform {
        if reduceMotion {
            return InitialTransform(
                opacity: initialOpacity,
                offsetY: 0,
                scale: 1.0,
                duration: reduceMotionDuration,
                usesMovementAndScale: false
            )
        }
        return InitialTransform(
            opacity: initialOpacity,
            offsetY: initialOffsetY,
            scale: initialScale,
            duration: duration,
            usesMovementAndScale: true
        )
    }

    /// Translation offsets needed to scale around the bottom-right corner of a layer of `boundsSize` with
    /// `layerAnchorPoint`, plus the downward vertical offset (`14 pt` visually lower) in the layer's coordinate space.
    public static func bottomRightPivotOffset(
        boundsSize: CGSize,
        layerAnchorPoint: CGPoint,
        isGeometryFlipped: Bool
    ) -> (pivotX: CGFloat, pivotY: CGFloat, verticalShift: CGFloat) {
        let ax = boundsSize.width
        let ay = isGeometryFlipped ? boundsSize.height : 0
        let pivotX = ax - layerAnchorPoint.x * boundsSize.width
        let pivotY = ay - layerAnchorPoint.y * boundsSize.height
        let verticalShift = isGeometryFlipped ? initialOffsetY : -initialOffsetY
        return (pivotX, pivotY, verticalShift)
    }
}

/// Pure eligibility state machine ensuring the sent-message rise plays at most once for a message sent locally from
/// the current window while anchored at the bottom, and never replays on reuse, scroll-back, history loads, or
/// chat reopen.
public struct SentMessageRiseTracker: Equatable, Sendable {
    private var pendingIDs: Set<String> = []
    private var playedIDs: Set<String> = []
    private var recentlyInsertedMineIDs: Set<String> = []
    private var localSubmitCredits = 0

    public init() {}

    /// Records that the local chat composer submitted a draft while the user was looking at the bottom of the chat.
    public mutating func noteLocalSubmit(
        isLoaded: Bool,
        isAtBottom: Bool,
        isAwayFromLatest: Bool,
        isHeldAwayFromLatest: Bool
    ) {
        guard isLoaded, isAtBottom, !isAwayFromLatest, !isHeldAwayFromLatest else { return }
        localSubmitCredits += 1
    }

    /// Records the `eventID` produced by a local send from this window's chat composer.
    /// Returns `true` if `eventID` was already freshly inserted into the live timeline and is immediately ready to
    /// animate; `false` otherwise (`eventID` waits in `pendingIDs` until its row arrives, or is ignored if ineligible).
    @discardableResult
    public mutating func recordLocalSend(
        eventID: String,
        isLoaded: Bool,
        isAtBottom: Bool,
        isAwayFromLatest: Bool,
        isHeldAwayFromLatest: Bool
    ) -> Bool {
        guard isLoaded, isAtBottom, !isAwayFromLatest, !isHeldAwayFromLatest,
              !playedIDs.contains(eventID)
        else { return false }
        pendingIDs.insert(eventID)
        return recentlyInsertedMineIDs.contains(eventID)
    }

    /// Records a newly inserted outgoing message observed during a live timeline refresh so that if the engine's
    /// `"event"` notification arrived moments before `message.send` returned `eventID`, the local send can still rise.
    public mutating func noteNewlyInsertedMineMessage(
        eventID: String,
        isAtBottom: Bool,
        isAwayFromLatest: Bool,
        isHeldAwayFromLatest: Bool
    ) {
        guard localSubmitCredits > 0,
              isAtBottom, !isAwayFromLatest, !isHeldAwayFromLatest,
              !playedIDs.contains(eventID)
        else { return }
        recentlyInsertedMineIDs.insert(eventID)
    }

    /// Consumes and authorizes the one-shot rise animation for `eventID` if and only if every condition holds.
    public mutating func consumeIfEligible(
        eventID: String,
        isInitialRender: Bool,
        isHistoryLoad: Bool,
        isAtBottom: Bool,
        isAwayFromLatest: Bool,
        isHeldAwayFromLatest: Bool
    ) -> Bool {
        guard !isInitialRender,
              !isHistoryLoad,
              isAtBottom,
              !isAwayFromLatest,
              !isHeldAwayFromLatest,
              !playedIDs.contains(eventID),
              pendingIDs.remove(eventID) != nil
        else { return false }
        playedIDs.insert(eventID)
        recentlyInsertedMineIDs.remove(eventID)
        if localSubmitCredits > 0 {
            localSubmitCredits -= 1
        }
        return true
    }

    /// Clears pending rise candidates on room switch or chat reopen so reopened chats never animate historical rows.
    public mutating func resetForRoomSwitchOrReopen() {
        pendingIDs.removeAll()
        recentlyInsertedMineIDs.removeAll()
        localSubmitCredits = 0
    }

    /// Clears pending rise candidates when older/window history is loaded.
    public mutating func noteHistoryLoaded() {
        pendingIDs.removeAll()
        recentlyInsertedMineIDs.removeAll()
        localSubmitCredits = 0
    }

    /// Clears pending rise candidates when the user scrolls off the bottom.
    public mutating func noteScrolledAwayFromBottom() {
        pendingIDs.removeAll()
        recentlyInsertedMineIDs.removeAll()
        localSubmitCredits = 0
    }
}

// MARK: - Item 8: Stable Layout Across Sending -> Sent

/// Layout stability helpers so transitioning the newest outgoing message from `Sending…` to `Sent` produces zero
/// vertical jump and preserves the exact gap from the message above it.
public enum StatusLineStability: Sendable {
    /// Shared single-line height for `.queued`, `.sending`, `.sent`, `.delivered`, and single-line `.seen` status labels
    /// so `Sending…` and `Sent` have identical row height.
    public static let compactLineHeight: CGFloat = 16

    /// Duration used when a secondary status change still requires a visual transition.
    public static let fallbackEaseDuration: TimeInterval = 0.15

    public static func isInFlight(_ status: StatusLine?) -> Bool {
        status == .sending || status == .queued
    }

    /// Returns the `eventID` of my newest outgoing message that should display `Sent` / `Delivered` / `Seen`, or `nil`
    /// while a newer outgoing message is currently in flight (`.sending` or `.queued`). Clearing the previous bubble's
    /// `"Sent"` label as soon as the new message starts sending guarantees zero layout or gap shift when that new
    /// message settles from `Sending…` to `Sent`. Newer `.waiting`, `.noAccount`, or failed messages still allow the
    /// preceding sent message to show its receipt status.
    public static func receiptRowID(in items: [TimelineItem]) -> String? {
        for item in items.reversed() {
            guard case let .message(message) = item,
                  message.mine,
                  !message.isNote,
                  message.kind != .deleted else { continue }
            if isInFlight(message.statusLine) {
                return nil
            }
            if message.statusLine?.hasGone == true {
                return message.id
            }
        }
        return nil
    }
}

// MARK: - Item 9: Short Chats Anchored at the Bottom

/// Pure scroll-geometry maths for anchoring short chats (whose rows do not fill the usable viewport) flush above the
/// composer while leaving scrollable tall chats unconstrained.
public enum TimelineBottomAnchoring: Sendable {
    /// Height available between `topInset` (header + top padding) and `bottomInset` (bottom padding / composer).
    public static func usableHeight(viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> CGFloat {
        max(0, viewportHeight - topInset - bottomInset)
    }

    /// Extra vertical space above the first row when `contentHeight` is shorter than the usable viewport.
    public static func extraTopOffset(
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        guard contentHeight > 0 else { return 0 }
        return max(0, usableHeight(viewportHeight: viewportHeight, topInset: topInset, bottomInset: bottomInset) - contentHeight)
    }

    public static func isShortChat(
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentHeight: CGFloat
    ) -> Bool {
        extraTopOffset(
            viewportHeight: viewportHeight,
            topInset: topInset,
            bottomInset: bottomInset,
            contentHeight: contentHeight
        ) > 0.5
    }

    /// Valid `(min, max)` clip-view `bounds.origin.y` range in flipped coordinates (`y = 0` at row 0 top).
    /// When the chat is short, `min == max == contentHeight + bottomInset - viewportHeight`, pinning the last row
    /// flush above the bottom inset.
    public static func originYBounds(
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentHeight: CGFloat
    ) -> (min: CGFloat, max: CGFloat) {
        let extra = extraTopOffset(
            viewportHeight: viewportHeight,
            topInset: topInset,
            bottomInset: bottomInset,
            contentHeight: contentHeight
        )
        let minY = -(topInset + extra)
        let maxY = max(minY, contentHeight + bottomInset - viewportHeight)
        return (minY, maxY)
    }

    /// Clamps `proposedY` into the bottom-anchored / scrollable `origin.y` bounds.
    public static func clampedOriginY(
        _ proposedY: CGFloat,
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        let bounds = originYBounds(
            viewportHeight: viewportHeight,
            topInset: topInset,
            bottomInset: bottomInset,
            contentHeight: contentHeight
        )
        return min(bounds.max, max(bounds.min, proposedY))
    }
}

// MARK: - Item 20: Gentler Jump Highlight

/// Timing and tint intensity curve for jump-to-message highlights (`ConversationModel.highlightDuration`).
public enum JumpHighlightMotion: Sendable {
    public static let totalDuration: TimeInterval = 1.5
    public static let duration: Duration = .milliseconds(1500)
    public static let fadeInFraction: Double = 0.20
    public static let fadeInDuration: TimeInterval = totalDuration * fadeInFraction
    public static let fadeOutDuration: TimeInterval = totalDuration - fadeInDuration
    public static let baseTintOpacity: Double = 0.28
    public static let peakTintFraction: Double = 0.40
    public static let peakTintOpacity: Double = baseTintOpacity * peakTintFraction

    private static func easeOut(_ u: Double) -> Double {
        let clamped = min(1, max(0, u))
        let inv = 1 - clamped
        return 1 - inv * inv
    }

    /// Normalized multiplier relative to `baseTintOpacity` (`0.28`) at `elapsed` seconds, peaking at `0.40` (40% of
    /// current tint = `0.112` final opacity) at `t = 0.3 s` (20% of `1.5 s`), then easing out over the remaining
    /// `1.2 s`.
    public static func tintFactor(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0, elapsed < totalDuration else { return 0 }
        if elapsed <= fadeInDuration {
            let progress = elapsed / fadeInDuration
            return peakTintFraction * easeOut(progress)
        }
        let progress = (elapsed - fadeInDuration) / fadeOutDuration
        return peakTintFraction * (1 - easeOut(progress))
    }

    /// Final yellow fill opacity (`baseTintOpacity * tintFactor(at:)`), peaking at `0.112`.
    public static func opacity(at elapsed: TimeInterval) -> Double {
        baseTintOpacity * tintFactor(at: elapsed)
    }
}
