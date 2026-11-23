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

/// Motion rules for `TypingLine` above the composer, keeping a constant reserved height.
public enum TypingLineMotion {
    public static let fadeDuration: TimeInterval = 0.15
    public static let reservedHeight: CGFloat = 22
    public static let fadeCurve: MotionCurve = .easeInOut

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

/// Visibility state of the top and bottom scroll-edge fade masks.
public struct ScrollEdgeFadeState: Equatable, Sendable {
    public let top: Bool
    public let bottom: Bool

    public init(top: Bool, bottom: Bool) {
        self.top = top
        self.bottom = bottom
    }

    public static let none = Self(top: false, bottom: false)
}

/// Pure scroll-geometry rules determining when top and bottom edge fades appear.
public enum ScrollEdgeFadeMotion {
    public static let fadeHeight: CGFloat = 10
    public static let threshold: CGFloat = 1.0
    public static let fadeTransitionDuration: TimeInterval = 0.12

    public static func effectiveFadeHeight(containerHeight: CGFloat) -> CGFloat {
        min(fadeHeight, max(0, containerHeight / 2))
    }

    public static func state(
        documentMinY: CGFloat,
        documentMaxY: CGFloat,
        clipMinY: CGFloat,
        clipMaxY: CGFloat,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0,
        isFlipped: Bool = true,
        threshold: CGFloat = ScrollEdgeFadeMotion.threshold
    ) -> ScrollEdgeFadeState {
        guard documentMaxY > documentMinY, clipMaxY > clipMinY else {
            return .none
        }
        if isFlipped {
            let visibleTop = clipMinY + topInset
            let visibleBottom = clipMaxY - bottomInset
            return ScrollEdgeFadeState(
                top: (visibleTop - documentMinY) > threshold,
                bottom: (documentMaxY - visibleBottom) > threshold
            )
        } else {
            let visibleTop = clipMaxY - topInset
            let visibleBottom = clipMinY + bottomInset
            return ScrollEdgeFadeState(
                top: (documentMaxY - visibleTop) > threshold,
                bottom: (visibleBottom - documentMinY) > threshold
            )
        }
    }

    public static func animatesMaskChange(reduceMotion: Bool) -> Bool {
        !reduceMotion
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
