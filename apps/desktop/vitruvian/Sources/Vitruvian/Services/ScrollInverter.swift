// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import VitruvianCore
import VitruvianDesign

/// Rewrites mouse wheel events only, leaving the trackpad on macOS natural
/// scrolling: a modifying tap at the HID level (before the window server
/// derives pixel deltas from the wheel ticks), appended at the tail. It caps
/// every event at one notch for linear scrolling, redirects modifier-held
/// vertical ticks when requested and flips the selected axis deltas; any of
/// those features keeps the tap alive.
///
/// Wheel detection: discrete events (`isContinuous == 0`) are wheels; events
/// flagged continuous are wheels only when they carry no gesture phase at all.
/// Toggling takes effect immediately. Requires Accessibility.
///
/// Apps on this feature's own exception list (issue #358) keep the direction
/// macOS gives them. The list is separate from the smooth scrolling one on
/// purpose, so excepting an app from the glide never leaves it scrolling
/// backwards; when both features are on, the flip happens inside the smooth
/// scrolling tap and honors this same list. Linear scrolling keeps a list of
/// its own, honored the same way in both taps, so a game or a 3D tool that
/// counts the notches itself can be left out of the cap alone.
@MainActor
package final class ScrollInverter: ObservableObject {
    package static let shared = ScrollInverter()

    /// True while the wheel tap is installed, for any feature it serves.
    @Published package private(set) var isRunning = false

    /// This process's own id, compared against the one every event carries.
    nonisolated private static let ownProcessID = Int64(getpid())

    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    /// Guards the two above: the callback runs on the pointer thread while the
    /// main thread arms and tears the tap down.
    private let tapStateLock = NSLock()
    /// Read and written solely on the tap callback, which is the pointer
    /// thread and nothing else, and reset by `stop` once the tap is gone.
    nonisolated(unsafe) private var wheel = WheelTapState()
    private var tapCreationRetry = TapCreationRetry()
    private var tapCreationRetryWork: DispatchWorkItem?

    private init() {
        // Fast user switching: the tap goes back while this session is off
        // screen and is built again from the preferences on the way in.
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    /// Applies the persisted preference; safe to call repeatedly.
    package func syncWithPreferences() {
        let direction = ScrollDirectionPreferences()
        if SessionActivitySupport.tapShouldRun(featureWanted: direction.isEnabled || Self.linearScrollWanted,
                                               accessibilityGranted: Permissions.shared.accessibility,
                                               sessionIsActive: SessionActivity.shared.isActive) {
            ScrollWheelTarget.shared.setEnabled(direction.horizontalModifier != nil)
            start()
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    package func suspend() { stop() }

    /// Linear scrolling keeps the tap alive on its own, next to the direction
    /// features; its keys survive the hub uninstalling it.
    private static var linearScrollWanted: Bool {
        AppFeature.linearScroll.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.linearScrollEnabled)
    }

    /// Each list's source apps are tracked only while its feature is one the
    /// tap is up for, so a list left behind by the other feature costs nothing.
    private func setSourceTracking(_ running: Bool) {
        let exceptions = MouseAppExceptions.shared
        exceptions.setSourceTracking(running && ScrollDirectionPreferences().isEnabled, for: .scrollDirection)
        exceptions.setSourceTracking(running && Self.linearScrollWanted, for: .linearScroll)
    }

    private func start() {
        if let port = tapStateLock.withLock({ tap }) {
            CGEvent.tapEnable(tap: port, enable: true)
            setSourceTracking(true)
            isRunning = true
            return
        }
        setSourceTracking(true)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            ScrollWheelTarget.shared.setEnabled(false)
            setSourceTracking(false)
            isRunning = false
            // A create that fails during the session handoff gets one more look once the switch settles.
            guard tapCreationRetry.refused() else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.tapCreationRetryWork = nil
                self.syncWithPreferences()
            }
            tapCreationRetryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            return
        }

        tapCreationRetry.reset()
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        tapStateLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func stop() {
        ScrollWheelTarget.shared.setEnabled(false)
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetry.reset()
        setSourceTracking(false)
        let (port, source) = tapStateLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        // Hand the tap back rather than only switching it off: a disabled tap
        // keeps its place in the chain, and a session that is switched away
        // has to stop being an event tap owner outright (issue #1075).
        if let source {
            PointerTapRunLoop.remove(source, invalidating: port)
        }
        wheel.linearCarryVertical = 0
        wheel.linearCarryHorizontal = 0
        isRunning = false
    }

    /// Runs on the pointer thread, so it is written here, outside the main
    /// actor: a closure written in `start()` would check for the main thread
    /// first in Swift 6 mode, and stop the app on the first scroll.
    nonisolated private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let inverter = Unmanaged<ScrollInverter>.fromOpaque(userInfo).takeUnretainedValue()
        return inverter.handle(type: type, event: event)
    }

    nonisolated
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm,
        // unless this session is the one that was switched away from, where
        // the stall is the reason the tap was disabled and re-arming feeds it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, let port = tapStateLock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        let keeps = Self.adjustWheel(event, state: &wheel, defaults: .standard,
                                     ownProcessID: Self.ownProcessID, targets: .system)
        return keeps ? Unmanaged.passUnretained(event) : nil
    }

    /// What the wheel tap remembers from one event to the next.
    package struct WheelTapState: Sendable {
        /// Timestamp (ns, event clock) of the last event carrying a gesture
        /// phase — only touch devices emit those.
        package var lastGesturePhaseTimestamp: UInt64?
        /// Fractions of a line linear scrolling has yet to deliver, one per axis.
        package var linearCarryVertical: Double = 0
        package var linearCarryHorizontal: Double = 0

        package init() {}
    }

    /// What the wheel tap asks about where the pointer is.
    package struct WheelTapTargets: Sendable {
        package var excludes: @Sendable (_ scope: MouseExceptionScope, _ point: CGPoint,
                                         _ sourceProcessID: Int64) -> Bool
        /// One of this app's own windows is under the pointer.
        package var isOwnWindow: @Sendable (CGPoint) -> Bool

        package init(excludes: @escaping @Sendable (MouseExceptionScope, CGPoint, Int64) -> Bool,
                     isOwnWindow: @escaping @Sendable (CGPoint) -> Bool) {
            self.excludes = excludes
            self.isOwnWindow = isOwnWindow
        }

        package static let system = WheelTapTargets(excludes: {
            MouseAppExceptions.shared.excludesPointerTarget($0, at: $1, sourceProcessID: $2)
        }, isOwnWindow: { ScrollWheelTarget.shared.contains($0) })
    }

    /// Caps, turns or redirects one wheel event in place. False when it only
    /// carried part of a notch, which is held back and added to the next one.
    nonisolated package static func adjustWheel(_ event: CGEvent, state: inout WheelTapState,
                                                defaults: UserDefaults, ownProcessID: Int64,
                                                targets: WheelTapTargets) -> Bool {
        // Smooth scrolling swallows the wheel before this tap and already
        // turned its glide around, so flipping the glide here would cancel
        // that out and inverting would look broken while both are on. The
        // process id is checked too: the only scroll events this app posts
        // are those glide frames.
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              sourceProcessID != ownProcessID else {
            return true
        }

        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = EventTimestamp.nanoseconds(of: event)
        let secondsSinceGesturePhase = state.lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            state.lastGesturePhaseTimestamp = timestamp
        }

        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
        else { return true }

        let direction = ScrollDirectionPreferences(defaults: defaults)
        let directionApplies = direction.isEnabled
            && !targets.excludes(.scrollDirection, event.location, sourceProcessID)
        // Control-wheel is native zoom. Only the explicit Control-to-horizontal
        // shortcut turns it into scrolling; a direction exception or one of
        // our own windows leaves it as zoom too.
        let controlRedirects = directionApplies
            && direction.horizontalModifier == .control
            && event.flags.intersection([.maskShift, .maskAlternate, .maskControl, .maskCommand]) == .maskControl
            && ScrollWheelSupport.isVerticalOnly(event)
            && !targets.isOwnWindow(event.location)
        let nativeZoom = event.flags.contains(.maskControl) && !controlRedirects
        if let linesPerNotch = nativeZoom ? nil : ScrollWheelSupport.linearLinesPerNotch(
            defaults: defaults,
            isAvailable: AppFeature.linearScroll.isAvailable(in: defaults),
            isExcepted: { targets.excludes(.linearScroll, event.location, sourceProcessID) }) {
            // Capture both axes before any set: writing a line delta makes the
            // system rederive its point and fixed-point fields.
            let rawVertical = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
            let rawHorizontal = ScrollWheelAxisDelta(
                line: event.getIntegerValueField(.scrollWheelEventDeltaAxis2),
                point: event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))
            let linearVertical = ScrollWheelSupport.linearDelta(
                rawVertical, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: state.linearCarryVertical)
            let linearHorizontal = ScrollWheelSupport.linearDelta(
                rawHorizontal, isContinuous: traits.isContinuous,
                linesPerNotch: linesPerNotch, carry: state.linearCarryHorizontal)
            state.linearCarryVertical = linearVertical.carry
            state.linearCarryHorizontal = linearHorizontal.carry
            // A fraction of a notch is carried into the next event rather
            // than delivered as an event that moves nothing.
            if rawVertical.hasMovement || rawHorizontal.hasMovement,
               !linearVertical.delta.hasMovement, !linearHorizontal.delta.hasMovement {
                return false
            }
            // Every axis that moves is written back, even when the capped line
            // matches the one already there: a discrete event's line is what
            // the system rederives the other fields from, so writing it is
            // what takes a high-resolution wheel's leftover fraction out.
            ScrollWheelSupport.writeLinear(
                vertical: rawVertical.hasMovement ? linearVertical.delta : nil,
                horizontal: rawHorizontal.hasMovement ? linearHorizontal.delta : nil,
                to: event, isContinuous: traits.isContinuous)
        } else {
            // A fraction belongs to the active linear stream. Do not let it
            // reappear after an excepted app or an off/uninstalled interval.
            state.linearCarryVertical = 0
            state.linearCarryHorizontal = 0
        }

        // The direction features read their own availability here: linear
        // scrolling may be what keeps this tap alive, so the tap running says
        // nothing about whether the wheel should be turned or redirected.
        if directionApplies {
            ScrollWheelSupport.applyDirection(
                to: event, isContinuous: traits.isContinuous,
                invertVertical: direction.invertVertical,
                invertHorizontal: direction.invertHorizontal,
                horizontalModifier: direction.horizontalModifier,
                targetsOwnWindow: targets.isOwnWindow(event.location)
            )
        }
        return true
    }
}
