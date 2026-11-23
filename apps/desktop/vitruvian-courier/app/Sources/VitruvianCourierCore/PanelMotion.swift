// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Timing curves shared between VitruvianCourierCore motion descriptors and SwiftUI animations.
public enum MotionCurve: Equatable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case cubicBezier(Double, Double, Double, Double)
}

/// One step in a vertical offset keyframe sequence.
public struct MotionKeyframe: Equatable, Sendable {
    public let offsetY: CGFloat
    public let duration: TimeInterval

    public init(offsetY: CGFloat, duration: TimeInterval) {
        self.offsetY = offsetY
        self.duration = duration
    }
}

/// Motion rules for thread and chat info side panes entering inside `ConversationView`.
public enum SidePaneMotion {
    public static let duration: TimeInterval = 0.2
    public static let reduceMotionFadeDuration: TimeInterval = 0.12
    public static let riseOffset: CGFloat = 10
    public static let curve: MotionCurve = .cubicBezier(0.165, 0.84, 0.44, 1.0)

    public static func usesRise(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func yOffset(isRevealed: Bool, reduceMotion: Bool) -> CGFloat {
        (isRevealed || reduceMotion) ? 0 : riseOffset
    }

    public static func opacity(isRevealed: Bool) -> Double {
        isRevealed ? 1 : 0
    }

    public static func effectiveDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionFadeDuration : duration
    }

    public static func effectiveCurve(reduceMotion: Bool) -> MotionCurve {
        reduceMotion ? .easeOut : curve
    }

    /// The entrance plays once each time the person opens the pane. A pane that is rebuilt while it stays open (the
    /// chat changed under it and its content came in again) does not play it again.
    public static func playsEntrance(alreadyPlayedThisOpen: Bool) -> Bool {
        !alreadyPlayedThisOpen
    }
}

/// Motion rules for the `CommandBarOverlay` dimmer and floating panel.
public enum CommandBarMotion {
    public static let fadeInDuration: TimeInterval = 0.12
    public static let fadeOutDuration: TimeInterval = 0.10
    public static let fadeInCurve: MotionCurve = .easeOut
    public static let fadeOutCurve: MotionCurve = .easeIn
    public static let reduceMotionFadeDuration: TimeInterval = 0.10

    public static func duration(isPresented: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reduceMotionFadeDuration : (isPresented ? fadeInDuration : fadeOutDuration)
    }

    public static func curve(isPresented: Bool, reduceMotion: Bool) -> MotionCurve {
        reduceMotion ? .easeOut : (isPresented ? fadeInCurve : fadeOutCurve)
    }

    public static func usesMovementOrScaling(reduceMotion _: Bool) -> Bool {
        false
    }

    public static func animatesSelectionScroll(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

/// Motion rules for `TypingLine`: a small floating pill just above the composer, over the timeline. It takes no
/// room when nobody is typing. While it shows and the person is at the bottom, the timeline's bottom inset grows by
/// the pill's height so the newest message stays fully visible; when they have scrolled up nothing changes.
public enum TypingLineMotion {
    public static let fadeDuration: TimeInterval = 0.15
    public static let fadeCurve: MotionCurve = .easeInOut
    public static let pillHeight: CGFloat = 24
    /// Space between the pill and the composer, and between the pill and the newest message when the inset is on.
    public static let pillGap: CGFloat = 6

    /// How far the timeline's bottom inset grows while the pill is held clear of the newest message.
    public static let timelineInset: CGFloat = pillHeight + pillGap

    public static func isVisible(text: String?) -> Bool {
        text != nil
    }

    public static func opacity(text: String?) -> Double {
        isVisible(text: text) ? 1 : 0
    }

    public static func animatesDots(isVisible: Bool, reduceMotion: Bool) -> Bool {
        isVisible && !reduceMotion
    }

    public static func effectiveFadeDuration(reduceMotion _: Bool) -> TimeInterval {
        fadeDuration
    }

    public static func usesMovement(reduceMotion _: Bool) -> Bool {
        false
    }

    /// Whether the timeline's bottom inset is raised for the pill. At the bottom it follows the pill (raised while
    /// it shows, back when it goes). Away from the bottom it stays as it was, so nothing under the person's eyes
    /// moves: a pill that came while they read above floats over the content, and one that goes leaves the inset
    /// until they are back at the bottom.
    public static func nextInsetRaised(current: Bool, pillVisible: Bool, atBottom: Bool) -> Bool {
        atBottom ? pillVisible : current
    }

    public static func insetHeight(raised: Bool) -> CGFloat {
        raised ? timelineInset : 0
    }

    /// The inset is eased over the fade; with Reduce Motion it changes at once.
    public static func animatesInset(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

/// Motion rules for the `SkeletonRows` loading shimmer in the inbox list.
public enum SkeletonShimmerMotion {
    public static let duration: TimeInterval = 1.0
    public static let curve: MotionCurve = .linear
    public static let baseOpacity: Double = 0.08
    public static let highlightOpacity: Double = 0.09
    public static let bandWidthFraction: CGFloat = 0.55

    public static func shouldAnimate(isVisible: Bool, reduceMotion: Bool) -> Bool {
        isVisible && !reduceMotion
    }

    /// Whether the window the rows are in is showing them: on screen, not minimised and not covered. A window the
    /// system reports as covered has no `visible` occlusion state. A shimmer in a window nobody can see only burns
    /// frames.
    public static func windowShowsContent(
        isOnScreen: Bool,
        isMiniaturized: Bool,
        occlusionVisible: Bool
    ) -> Bool {
        isOnScreen && !isMiniaturized && occlusionVisible
    }

    public static func phase(elapsed: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        let raw = elapsed.truncatingRemainder(dividingBy: duration) / duration
        let wrapped = raw < 0 ? raw + 1 : raw
        return wrapped >= 1 ? 0 : wrapped
    }

    public static func bandWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth * bandWidthFraction)
    }

    public static func bandOffsetX(phase: Double, containerWidth: CGFloat) -> CGFloat {
        let clamped = min(1, max(0, phase))
        let width = bandWidth(containerWidth: containerWidth)
        return -width + CGFloat(clamped) * (containerWidth + width)
    }
}

/// How strongly the top and bottom edges of a scroller fade out, 0 (not at all) to 1 (rows fade to nothing at the
/// edge). An edge fades only while there is more content beyond it, and eases in over the first points scrolled so
/// nothing pops.
public struct ScrollEdgeFadeState: Equatable, Sendable {
    public let top: CGFloat
    public let bottom: CGFloat

    public init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }

    public static let none = Self(top: 0, bottom: 0)

    /// True when either edge fades: the only time a mask is attached at all.
    public var isActive: Bool { top > 0 || bottom > 0 }
}

/// Pure scroll-geometry rules for the top and bottom edge fades.
public enum ScrollEdgeFadeMotion {
    public static let fadeHeight: CGFloat = 10
    /// Content hidden beyond an edge by no more than this counts as not hidden (rounding, rubber band).
    public static let threshold: CGFloat = 1.0

    public static func effectiveFadeHeight(containerHeight: CGFloat) -> CGFloat {
        min(fadeHeight, max(0, containerHeight / 2))
    }

    /// 0 when nothing (beyond `threshold`) is hidden past the edge, rising to 1 once `fadeHeight` is.
    public static func strength(hiddenDistance: CGFloat) -> CGFloat {
        guard hiddenDistance > threshold else { return 0 }
        return min(1, hiddenDistance / fadeHeight)
    }

    public static func state(
        documentMinY: CGFloat,
        documentMaxY: CGFloat,
        clipMinY: CGFloat,
        clipMaxY: CGFloat,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        isFlipped: Bool = true
    ) -> ScrollEdgeFadeState {
        guard documentMaxY > documentMinY, clipMaxY > clipMinY else {
            return .none
        }
        if isFlipped {
            let visibleTop = clipMinY + topInset
            let visibleBottom = clipMaxY - bottomInset
            return ScrollEdgeFadeState(
                top: strength(hiddenDistance: visibleTop - documentMinY),
                bottom: strength(hiddenDistance: documentMaxY - visibleBottom)
            )
        } else {
            let visibleTop = clipMaxY - topInset
            let visibleBottom = clipMinY + bottomInset
            return ScrollEdgeFadeState(
                top: strength(hiddenDistance: documentMaxY - visibleTop),
                bottom: strength(hiddenDistance: visibleBottom - documentMinY)
            )
        }
    }

    /// Alpha of the mask at its two ends and where the fade ends, as fractions of the height, top to bottom:
    /// four stops `(alpha, location)`. An edge with strength 0 is fully opaque.
    public static func maskStops(
        state: ScrollEdgeFadeState,
        containerHeight: CGFloat
    ) -> [(alpha: CGFloat, location: CGFloat)] {
        let edge = effectiveFadeHeight(containerHeight: containerHeight)
        let fraction = containerHeight > 0 ? edge / containerHeight : 0
        return [
            (1 - state.top, 0),
            (1, fraction),
            (1, 1 - fraction),
            (1 - state.bottom, 1),
        ]
    }
}

/// Motion rules for collapsible sections in `ChatInfoPane`.
public enum ChatInfoSectionMotion {
    public static let expandDuration: TimeInterval = 0.25
    public static let expandCurve: MotionCurve = .easeInOut
    public static let chevronDuration: TimeInterval = 0.20
    public static let chevronCurve: MotionCurve = .easeInOut

    public static func chevronRotationDegrees(isOpen: Bool) -> Double {
        isOpen ? 90 : 0
    }

    public static func animatesExpand(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func animatesChevron(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

/// Motion rules for `ScheduledStrip` chevron rotation, expansion, and newly-queued toggle bounce.
public enum ScheduledStripMotion {
    public static let chevronDuration: TimeInterval = 0.30
    public static let chevronCurve: MotionCurve = .easeInOut
    public static let toggleDuration: TimeInterval = 0.20
    public static let toggleCurve: MotionCurve = .easeInOut
    public static let bounceDuration: TimeInterval = 0.30
    public static let bounceInitialOffsetY: CGFloat = 0
    public static let bounceKeyframes: [MotionKeyframe] = [
        MotionKeyframe(offsetY: -4, duration: 0.10),
        MotionKeyframe(offsetY: 2, duration: 0.10),
        MotionKeyframe(offsetY: 0, duration: 0.10),
    ]

    public static func chevronRotationDegrees(isOpen: Bool) -> Double {
        isOpen ? 180 : 0
    }

    public static func animatesChevron(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func animatesToggle(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func shouldBounce(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static func bounceOffsets(reduceMotion: Bool) -> [CGFloat] {
        reduceMotion ? [0] : [bounceInitialOffsetY] + bounceKeyframes.map(\.offsetY)
    }

    public static func hasNewlyQueuedMessage(previousIDs: Set<Int64>, currentIDs: Set<Int64>) -> Bool {
        !currentIDs.subtracting(previousIDs).isEmpty
    }
}
