// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation

// MARK: - Item 1: Waiting for a chat's first page

/// What the timeline shows while a chat's first page is still on its way. The chat's identity (header, composer,
/// drafts, commands) has already switched by then; only the message area waits.
public enum TimelineLoadMotion: Sendable {
    /// The pane stays plain and neutral for this long, so a fast read never flashes anything.
    public static let placeholderDelay: Duration = .milliseconds(120)
    /// The message-shaped placeholders fade in over this long (not at all under Reduce Motion).
    public static let placeholderFadeDuration: TimeInterval = 0.2

    /// One placeholder bubble: how wide it is, as a fraction of the pane, how many lines tall, and which side.
    public struct PlaceholderRow: Equatable, Sendable {
        public let widthFraction: CGFloat
        public let lines: Int
        public let fromMe: Bool
    }

    /// The placeholder bubbles, newest last, in a fixed pattern: the same every time, so the pane never "shimmers"
    /// differently between opens.
    public static func placeholderRows(count: Int = 7) -> [PlaceholderRow] {
        let pattern: [(CGFloat, Int, Bool)] = [
            (0.46, 1, false), (0.62, 2, false), (0.34, 1, true), (0.55, 1, false),
            (0.40, 2, true), (0.58, 1, false), (0.30, 1, true),
        ]
        return (0 ..< max(0, count)).map { index in
            let item = pattern[index % pattern.count]
            return PlaceholderRow(widthFraction: item.0, lines: item.1, fromMe: item.2)
        }
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

    /// Where to scale from, and how far to start below the resting place, for a layer of `boundsSize` whose
    /// superlayer's +y points down on screen when `superlayerYPointsDown` (the layer's own transform is read in its
    /// superlayer's orientation, not in the orientation its own `isGeometryFlipped` gives its sublayers).
    /// `pivotX` and `pivotY` are the bottom-right corner, measured from the layer's anchor point.
    /// `verticalShift` is the 14 pt that is visually lower.
    public static func bottomRightPivotOffset(
        boundsSize: CGSize,
        layerAnchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        superlayerYPointsDown: Bool
    ) -> (pivotX: CGFloat, pivotY: CGFloat, verticalShift: CGFloat) {
        let bottomY: CGFloat = superlayerYPointsDown ? boundsSize.height : 0
        return (
            boundsSize.width - layerAnchorPoint.x * boundsSize.width,
            bottomY - layerAnchorPoint.y * boundsSize.height,
            superlayerYPointsDown ? initialOffsetY : -initialOffsetY
        )
    }
}

/// Pure eligibility state machine ensuring the sent-message rise plays at most once for a message sent locally from
/// the current window while the person was already at the bottom, and never replays on reuse, scroll-back, history
/// loads, or chat reopen. Sending while scrolled up only jumps to the latest: no rise.
public struct SentMessageRiseTracker: Equatable, Sendable {
    private var pendingIDs: Set<String> = []
    private var playedIDs: Set<String> = []
    private var recentlyInsertedMineIDs: Set<String> = []
    /// Sends submitted from the bottom that have not yet been given their event id. Decided at the moment of
    /// submit: jumping to the latest afterwards must not make a send that began scrolled up eligible.
    private var localSubmitCredits = 0

    public init() {}

    /// The local chat composer submitted a draft. At the bottom it earns a credit; scrolled up it earns none and
    /// takes back any credit left over from an earlier submit that never got an event id.
    public mutating func noteLocalSubmit(
        isLoaded: Bool,
        isAtBottom: Bool,
        isAwayFromLatest: Bool,
        isHeldAwayFromLatest: Bool
    ) {
        guard isLoaded, isAtBottom, !isAwayFromLatest, !isHeldAwayFromLatest else {
            localSubmitCredits = 0
            return
        }
        localSubmitCredits += 1
    }

    /// Records the `eventID` produced by a local send from this window's chat composer, using up a credit.
    /// Returns `true` if `eventID` was already freshly inserted into the live timeline and is ready to animate now;
    /// `false` otherwise (`eventID` waits until its row arrives, or is ignored when there was no credit).
    @discardableResult
    public mutating func recordLocalSend(
        eventID: String,
        isLoaded: Bool,
        isAtBottom: Bool,
        isAwayFromLatest: Bool,
        isHeldAwayFromLatest: Bool
    ) -> Bool {
        guard localSubmitCredits > 0,
              isLoaded, isAtBottom, !isAwayFromLatest, !isHeldAwayFromLatest,
              !playedIDs.contains(eventID)
        else { return false }
        localSubmitCredits -= 1
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
        return true
    }

    /// Clears pending rise candidates on room switch or chat reopen so reopened chats never animate historical rows.
    public mutating func resetForRoomSwitchOrReopen() { clearCandidates() }

    /// Clears pending rise candidates when older/window history is loaded.
    public mutating func noteHistoryLoaded() { clearCandidates() }

    /// Clears pending rise candidates when the user scrolls off the bottom.
    public mutating func noteScrolledAwayFromBottom() { clearCandidates() }

    private mutating func clearCandidates() {
        pendingIDs.removeAll()
        recentlyInsertedMineIDs.removeAll()
        localSubmitCredits = 0
    }
}

// MARK: - Item 8: Stable Layout Across Sending -> Sent

/// Layout stability for the status line under my newest messages, so that `Sending…` becoming `Sent` leaves the
/// bubble where it is. The line has the same height in every one of these states.
public enum StatusLineStability: Sendable {
    /// Shared single-line height for `.queued`, `.sending`, `.sent`, `.delivered`, and single-line `.seen` status labels
    /// so `Sending…` and `Sent` have identical row height.
    public static let compactLineHeight: CGFloat = 16
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

    /// Whether the tint fades in and out. Under Reduce Motion it does not: it shows at its peak, then goes.
    public static func rampsTint(reduceMotion: Bool) -> Bool { !reduceMotion }
}

// MARK: - Item 6: The jump button's label while it fades

/// What the jump-to-latest button says. While the button fades out it keeps the words it had, so its width does not
/// snap down to the chevron alone halfway through the fade.
public struct JumpToLatestLabel: Equatable, Sendable {
    public var isAwayFromLatest: Bool
    public var hasNewerWhileAway: Bool
    public var newMessageCount: Int

    public init(isAwayFromLatest: Bool, hasNewerWhileAway: Bool, newMessageCount: Int) {
        self.isAwayFromLatest = isAwayFromLatest
        self.hasNewerWhileAway = hasNewerWhileAway
        self.newMessageCount = newMessageCount
    }

    /// The label to draw: the live one while the button is shown, the last shown one while it fades away.
    public static func displayed(current: JumpToLatestLabel, lastShown: JumpToLatestLabel, isVisible: Bool) -> JumpToLatestLabel {
        isVisible ? current : lastShown
    }
}
