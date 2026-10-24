// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
@preconcurrency import CoreGraphics
import QuartzCore
import VitruvianCore
import VitruvianDesign

/// Turns the mouse wheel's discrete jumps into short glides: a tap swallows
/// each wheel tick and replays its distance as a stream of continuous pixel
/// events that ease out, like a touch device would produce.
///
/// Wheel detection matches the scroll inverter (`ScrollWheelSupport`), so
/// mice whose drivers report the wheel as continuous pixel events (issue
/// #267) glide too; trackpads, Magic Mouse and momentum
/// are passed through untouched. The tap sits at the head, so the original
/// tick is swallowed before the inverter (appended at the tail) can see it
/// and the flip, like linear scrolling's cap, is applied here instead; the
/// glide carries a mark that keeps the inverter off it. Nothing (tap or timer)
/// exists while the feature is off. Requires Accessibility.
@MainActor
package final class SmoothScrollService: ObservableObject {
    /// What the service asks of the rest of the app. `live` asks the real
    /// App Switcher; tests pass a stand-in.
    package struct Environment {
        /// True while an open App Switcher steps its selection by wheel. The
        /// raw wheel is then the switcher's: no glide is started and the
        /// event goes on untouched, since a glide's frames carry the mark the
        /// switcher skips.
        package var switcherNavigatesByWheel: @MainActor () -> Bool

        package init(switcherNavigatesByWheel: @escaping @MainActor () -> Bool) {
            self.switcherNavigatesByWheel = switcherNavigatesByWheel
        }

        package static var live: Environment {
            Environment(switcherNavigatesByWheel: { AppSwitcher.shared.scrollNavigationActive })
        }
    }

    package static let shared = SmoothScrollService(environment: .live)

    /// True while the event tap is installed.
    @Published package private(set) var isRunning = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// The glide the swallowed ticks are replayed through. The tap callback
    /// and the glide's frames both live on the main run loop.
    private lazy var glide = SmoothScrollGlide(environment: .live)
    /// This process's own id, compared against the one every event carries.
    /// The glide's mark is the first thing that keeps a replayed frame out of
    /// this tap; this is the second lock on the same door, because the only
    /// scroll events this app posts are glide frames, and one that got back
    /// in would be swallowed and re-added at its full distance, leaving a
    /// glide that never ends.
    private static let ownProcessID = Int64(getpid())
    /// Timestamp (ns, event clock) of the last event carrying a gesture phase —
    /// only touch devices emit those. Read/written solely on the tap callback.
    private var lastGesturePhaseTimestamp: UInt64?
    private var tapCreationRetry = TapCreationRetry()
    private var tapCreationRetryWork: DispatchWorkItem?
    private let environment: Environment

    package init(environment: Environment) {
        self.environment = environment
        // Fast user switching: the tap goes back while this session is off
        // screen and is built again from the preferences on the way in.
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    /// Applies the persisted preference; safe to call repeatedly.
    package func syncWithPreferences() {
        let wanted = AppFeature.smoothScroll.isAvailable
            && UserDefaults.standard[Preferences.smoothScrollEnabled]
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    package func suspend() { stop() }

    private func start() {
        guard tap == nil else {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            glide.attach()
            MouseAppExceptions.shared.setSourceTracking(true, for: .smoothScroll)
            isRunning = true
            return
        }
        MouseAppExceptions.shared.setSourceTracking(true, for: .smoothScroll)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<SmoothScrollService>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap's source is on the main run loop (below).
                return MainActor.assumeIsolated { service.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            MouseAppExceptions.shared.setSourceTracking(false, for: .smoothScroll)
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
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        // Its isRunning is read from the tap callback, so it is built off the event path.
        _ = ScrollInverter.shared
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        glide.attach()
        isRunning = true
    }

    private func stop() {
        tapCreationRetryWork?.cancel()
        tapCreationRetryWork = nil
        tapCreationRetry.reset()
        MouseAppExceptions.shared.setSourceTracking(false, for: .smoothScroll)
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        // Hand the tap back rather than only switching it off: a disabled tap
        // keeps its place in the chain, and a session that is switched away
        // has to stop being an event tap owner outright (issue #1075).
        if let tap {
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        // The glide's scheduler and its screen and sleep observers go with it.
        glide.detach()
        isRunning = false
    }

    /// The tap's answer to one event, on the main run loop that serves it.
    package func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall or when the session locks; re-arm,
        // unless this session is the one that was switched away from, where
        // the stall is the reason the tap was disabled and re-arming feeds it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stopGlide()
            let wanted = AppFeature.smoothScroll.isAvailable
                && UserDefaults.standard[Preferences.smoothScrollEnabled]
            let shouldRearm = SessionActivitySupport.tapShouldRun(
                featureWanted: wanted,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRearm, let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    self?.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        let switcherNavigating = environment.switcherNavigatesByWheel()
        // Our own glide stream coming back through the tap.
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        let isOwnEvent = event.getIntegerValueField(.eventSourceUserData) == ScrollWheelSupport.syntheticTag
            || sourceProcessID == Self.ownProcessID
        // A stepped capture-loupe notch is a discrete command, so it must
        // reach the overlay now rather than being expanded into a delayed
        // glide. The opposite (fast) loupe mode intentionally keeps that
        // glide, including when Option temporarily swaps the two modes.
        switch SmoothScrollSupport.wheelEntry(
            switcherNavigating: switcherNavigating,
            isOwnEvent: isOwnEvent,
            steppedLoupeWantsRawWheel: {
                ScreenshotSelectionController.steppedLoupeNeedsRawWheel(
                    optionPressed: event.flags.contains(.maskAlternate))
            }) {
        case .passThroughEndingGlide:
            stopGlide()
            return Unmanaged.passUnretained(event)
        case .passThrough:
            return Unmanaged.passUnretained(event)
        case .glide:
            break
        }
        // Touch devices are already smooth; only mouse wheels glide. The
        // classification is shared with the scroll inverter, so mice that
        // report the wheel as continuous events (issue #267) are wheels too.
        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = EventTimestamp.nanoseconds(of: event)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }
        guard ScrollWheelSupport.isMouseWheel(traits,
                                              secondsSinceLastGesturePhase: secondsSinceGesturePhase)
        else { return Unmanaged.passUnretained(event) }
        if MouseButtonShortcutService.hasActiveSideWheelInterest,
           let input = MouseButtonShortcutSupport.sideWheelInput(
            isContinuous: traits.isContinuous,
            vertical: (
                line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                point: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            ),
            horizontal: (
                line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                point: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            )),
           MouseButtonShortcutService.claimsSideWheel(
               input,
               at: event.location,
               sourceProcessID: sourceProcessID,
               eventTimestamp: timestamp
           ) {
            return Unmanaged.passUnretained(event)
        }
        // Apps on this feature's exception list get their wheel raw: the
        // glide would arrive as a much longer move inside apps that read the
        // wheel themselves (issue #358).
        let exceptions = MouseAppExceptions.shared
        guard !exceptions.excludesPointerTarget(
                .smoothScroll,
                at: event.location,
                sourceProcessID: sourceProcessID) else {
            return Unmanaged.passUnretained(event)
        }

        // The head tap swallows the tick before the inverter's tail tap can
        // reach it, so when inverting is on the wheel's vertical flip is
        // applied here; the glide is marked so the inverter leaves it alone.
        // The flip is the inverter's, so it follows the inverter's own
        // exception list: an app excepted there must keep the system's
        // direction even while its wheel glides. Linear scrolling can keep
        // the inverter's tap running with the direction features uninstalled
        // and their switches left on, so the flip itself comes from
        // ScrollDirectionPreferences, which reads each one's availability.
        let adjustDirectionHere = ScrollInverter.shared.isRunning
            && !exceptions.excludesPointerTarget(
                .scrollDirection,
                at: event.location,
                sourceProcessID: sourceProcessID)
        let defaults = UserDefaults.standard
        let direction = ScrollDirectionPreferences(defaults: defaults)
        let redirected: Bool
        if adjustDirectionHere, let modifier = direction.horizontalModifier {
            redirected = ScrollWheelSupport.redirectVerticalScroll(event, modifier: modifier,
                targetsOwnWindow: ScrollWheelTarget.shared.contains(event.location))
        } else {
            redirected = false
        }
        // Control-scroll keeps its native zoom unless explicitly used by the
        // horizontal-scroll setting, which consumes Control above.
        guard !event.flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }
        let invertVertical = adjustDirectionHere && direction.invertVertical ? -1.0 : 1.0
        let invertHorizontal = adjustDirectionHere && direction.invertHorizontal ? -1.0 : 1.0
        // Linear scrolling is applied here for the same reason the flip is:
        // this tap swallows the tick before the wheel tap can see it. The cap
        // follows linear scrolling's own exception list the same way.
        let linearLinesPerNotch = ScrollWheelSupport.linearLinesPerNotch(
            defaults: defaults,
            isAvailable: AppFeature.linearScroll.isAvailable,
            isExcepted: {
                exceptions.excludesPointerTarget(
                    .linearScroll,
                    at: event.location,
                    sourceProcessID: sourceProcessID)
            })
        let shiftPressed = event.flags.contains(.maskShift)
        let vertical: Double
        let horizontal: Double
        let step: Double
        if traits.isContinuous {
            // The distance comes from the same fixed-point field the discrete
            // path reads, which counts lines, so it converts to pixels and
            // the step scales it from there. No Shift redirect: the system
            // never translates continuous events, apps react to the replayed
            // Shift flag.
            let userStep = Double(SmoothScrollSupport.sanitizedStep(
                defaults[Preferences.smoothScrollStep]))
            let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let verticalPoint = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let horizontalPoint = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            if let linearLinesPerNotch {
                vertical = SmoothScrollSupport.linearContinuousDistance(
                    fixedPointDelta: verticalFixedPoint, pointDelta: verticalPoint,
                    step: userStep, linesPerNotch: linearLinesPerNotch) * invertVertical
                horizontal = SmoothScrollSupport.linearContinuousDistance(
                    fixedPointDelta: horizontalFixedPoint, pointDelta: horizontalPoint,
                    step: userStep, linesPerNotch: linearLinesPerNotch) * invertHorizontal
            } else {
                vertical = SmoothScrollSupport.continuousDistance(
                    fixedPointDelta: verticalFixedPoint, pointDelta: verticalPoint,
                    step: userStep) * invertVertical
                horizontal = SmoothScrollSupport.continuousDistance(
                    fixedPointDelta: horizontalFixedPoint, pointDelta: horizontalPoint,
                    step: userStep) * invertHorizontal
            }
            // The distance is already in pixels; the budget must not scale it
            // a second time.
            step = 1
        } else {
            // The fixed-point field carries the fractional ticks that
            // high-resolution wheels report while the integer field reads 0.
            let verticalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let verticalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let verticalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let horizontalLine = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let horizontalFixedPoint = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            var verticalTicks = SmoothScrollSupport.ticks(line: Double(verticalLine),
                                                          fixedPoint: verticalFixedPoint)
            var horizontalTicks = SmoothScrollSupport.ticks(line: Double(horizontalLine),
                                                            fixedPoint: horizontalFixedPoint)
            // Linear scrolling counts notches, not the distance macOS scaled
            // them to, so a slow notch weighs as much as a fast one.
            if let linearLinesPerNotch {
                verticalTicks = ScrollWheelSupport.linearLines(
                    ticks: ScrollWheelSupport.discreteTicks(line: verticalLine,
                                                            fixedPoint: verticalFixedPoint,
                                                            point: verticalPoint),
                    linesPerNotch: linearLinesPerNotch)
                horizontalTicks = ScrollWheelSupport.linearLines(
                    ticks: ScrollWheelSupport.discreteTicks(line: horizontalLine,
                                                            fixedPoint: horizontalFixedPoint,
                                                            point: horizontalPoint),
                    linesPerNotch: linearLinesPerNotch)
            }
            let axes = SmoothScrollSupport.axes(
                vertical: verticalTicks,
                horizontal: horizontalTicks,
                shiftPressed: shiftPressed
            )
            vertical = axes.vertical * invertVertical
            horizontal = axes.horizontal * invertHorizontal
            step = Double(SmoothScrollSupport.sanitizedStep(
                defaults[Preferences.smoothScrollStep]))
        }
        guard vertical != 0 || horizontal != 0 else {
            return Unmanaged.passUnretained(event)
        }

        glide.feed(vertical: vertical, horizontal: horizontal, step: step,
                   flags: event.flags, redirected: redirected, continuous: traits.isContinuous,
                   response: SmoothScrollSupport.sanitizedResponse(
                    defaults[Preferences.smoothScrollResponse]),
                   coast: SmoothScrollSupport.sanitizedCoast(
                    defaults[Preferences.smoothScrollCoast]))
        // The tick itself is swallowed; the glide replays its distance.
        return nil
    }

    // MARK: - Glide

    private func stopGlide() {
        glide.stop()
    }
}

/// The glide that replays swallowed wheel ticks: the distance engine, the
/// frame scheduler (the display link of the screen under the pointer, or a
/// timer while there is none), the screen and sleep observers, and the frames
/// it posts. `SmoothScrollService` feeds it from its tap; a test hands in an
/// `Environment` of doubles, so no screen paces it and nothing is posted.
@MainActor
package final class SmoothScrollGlide {
    /// A running frame scheduler.
    package struct Scheduler {
        package var invalidate: @MainActor () -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(invalidate: @escaping @MainActor () -> Void) {
            self.invalidate = invalidate
        }
    }

    /// The screen under the pointer, as the glide follows it.
    package struct Screen {
        /// Nil when the screen names no display to follow.
        package var displayID: CGDirectDisplayID?
        /// Starts that display's own link, which calls `frame` on the main
        /// thread with each frame's timestamp and duration.
        package var startDisplayLink: @MainActor (
            _ frame: @escaping @MainActor (_ timestamp: TimeInterval, _ duration: TimeInterval) -> Void
        ) -> Scheduler

        // Spelled out because a memberwise initializer never leaves its module.
        package init(displayID: CGDirectDisplayID?,
                     startDisplayLink: @escaping @MainActor (
                        _ frame: @escaping @MainActor (_ timestamp: TimeInterval, _ duration: TimeInterval) -> Void
                     ) -> Scheduler) {
            self.displayID = displayID
            self.startDisplayLink = startDisplayLink
        }
    }

    /// What the glide reaches outside itself. `live` is the Mac.
    package struct Environment {
        package var screenUnderPointer: @MainActor () -> Screen?
        /// A repeating timer on the main run loop, for when no display can be
        /// followed.
        package var startTimer: @MainActor (_ interval: TimeInterval,
                                            _ fire: @escaping @MainActor @Sendable () -> Void) -> Scheduler
        /// The clock a timer's frames are measured on.
        package var uptime: @MainActor () -> TimeInterval
        /// Posts one frame, in whole pixels, with the wheel's modifiers.
        package var post: @MainActor (_ vertical: Int32, _ horizontal: Int32, _ flags: CGEventFlags) -> Void
        /// Where the screen-parameter change is posted.
        package var screenNotifications: NotificationCenter
        /// Where sleep is posted.
        package var sleepNotifications: NotificationCenter

        // Spelled out because a memberwise initializer never leaves its module.
        package init(screenUnderPointer: @escaping @MainActor () -> Screen?,
                     startTimer: @escaping @MainActor (_ interval: TimeInterval,
                                                       _ fire: @escaping @MainActor @Sendable () -> Void) -> Scheduler,
                     uptime: @escaping @MainActor () -> TimeInterval,
                     post: @escaping @MainActor (_ vertical: Int32, _ horizontal: Int32, _ flags: CGEventFlags) -> Void,
                     screenNotifications: NotificationCenter,
                     sleepNotifications: NotificationCenter) {
            self.screenUnderPointer = screenUnderPointer
            self.startTimer = startTimer
            self.uptime = uptime
            self.post = post
            self.screenNotifications = screenNotifications
            self.sleepNotifications = sleepNotifications
        }

        @MainActor package static var live: Environment {
            Environment(
                screenUnderPointer: {
                    guard let screen = NSScreen.withMouse else { return nil }
                    let candidate = screen.displayID
                    return Screen(displayID: candidate != 0 ? candidate : nil, startDisplayLink: { frame in
                        let target = SmoothScrollLinkTarget(frame: frame)
                        let link = screen.displayLink(target: target,
                                                      selector: #selector(SmoothScrollLinkTarget.fire(_:)))
                        link.add(to: .main, forMode: .common)
                        // A scheduled display link retains its target until invalidated.
                        return Scheduler(invalidate: { link.invalidate() })
                    })
                },
                startTimer: { interval, fire in
                    let timer = Timer(timeInterval: interval, repeats: true) { _ in
                        // Added to the main run loop below, so it fires on the main thread.
                        MainActor.assumeIsolated { fire() }
                    }
                    RunLoop.main.add(timer, forMode: .common)
                    return Scheduler(invalidate: { timer.invalidate() })
                },
                uptime: { ProcessInfo.processInfo.systemUptime },
                post: { vertical, horizontal, flags in
                    guard let event = CGEvent(scrollWheelEvent2Source: nil,
                                              units: .pixel,
                                              wheelCount: 2,
                                              wheel1: vertical,
                                              wheel2: horizontal,
                                              wheel3: 0) else { return }
                    event.setIntegerValueField(.eventSourceUserData, value: ScrollWheelSupport.syntheticTag)
                    event.flags = flags
                    event.post(tap: .cghidEventTap)
                },
                screenNotifications: .default,
                sleepNotifications: NSWorkspace.shared.notificationCenter)
        }
    }

    private enum SchedulerKind: Equatable {
        case none
        case timer
        case displayLink(CGDirectDisplayID)
    }

    private let environment: Environment
    /// Pure per-axis distance engine.
    private var engine = SmoothScrollSupport.Engine()
    private var lastFrameTimestamp: TimeInterval?
    private var currentResponse = SmoothScrollSupport.defaultResponse
    private var currentCoast = SmoothScrollSupport.defaultCoast
    /// Sub-pixel leftovers kept between frames, so a wheel that moves in
    /// fractions of a pixel still travels its full distance.
    private var carryVertical: Double = 0
    private var carryHorizontal: Double = 0
    /// Modifiers of the wheel event that started or fed the glide, replayed on
    /// the synthetic events so apps can still react to them.
    private var currentFlags: CGEventFlags = []
    private var currentScrollRedirected = false
    /// Whether the glide is being fed by continuous wheel events. The two
    /// kinds measure their distance differently, so switching devices
    /// mid-glide drops the tail rather than mixing the two budgets.
    private var glideFromContinuous = false
    private var scheduler: Scheduler?
    private var schedulerKind = SchedulerKind.none
    /// Tells the current scheduler's frames from a replaced one's.
    private var schedulerGeneration: UInt = 0
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    package init(environment: Environment) {
        self.environment = environment
    }

    /// Whether distance is still waiting to be replayed.
    package var isGliding: Bool { engine.isActive }

    /// Follows the screens and sleep while the tap runs.
    package func attach() {
        installScreenObserver()
        installSleepObserver()
    }

    /// The tap is gone: the observers go and the glide ends.
    package func detach() {
        removeScreenObserver()
        removeSleepObserver()
        stop()
    }

    /// Adds one swallowed tick's distance, `vertical` and `horizontal` scaled
    /// by `step`, and makes sure a scheduler is replaying it. `flags` are the
    /// wheel event's, replayed on every frame.
    package func feed(vertical: Double, horizontal: Double, step: Double, flags: CGEventFlags,
                      redirected: Bool, continuous: Bool, response: Int, coast: Int) {
        // Switching Shift while a glide is active changes the intended axis,
        // and switching between a discrete and a continuous wheel changes the
        // sign handling. Drop the old tail instead of fighting it.
        if currentFlags.contains(.maskShift) != flags.contains(.maskShift)
            || currentScrollRedirected != redirected
            || glideFromContinuous != continuous {
            engine.reset()
            carryVertical = 0
            carryHorizontal = 0
        }
        let verticalDistance = vertical * step
        let horizontalDistance = horizontal * step
        carryVertical = SmoothScrollSupport.carry(carryVertical, continuing: verticalDistance)
        carryHorizontal = SmoothScrollSupport.carry(carryHorizontal, continuing: horizontalDistance)
        engine.add(vertical: verticalDistance, horizontal: horizontalDistance)
        currentFlags = flags
        currentScrollRedirected = redirected
        currentResponse = response
        currentCoast = coast
        glideFromContinuous = continuous
        startGlideIfNeeded()
    }

    /// Ends the glide in flight: its scheduler and whatever distance is left.
    package func stop() {
        stopFrameScheduler()
        engine.reset()
        carryVertical = 0
        carryHorizontal = 0
    }

    private func startGlideIfNeeded() {
        let screen = environment.screenUnderPointer()
        let displayID = screen?.displayID
        if case .displayLink(let current) = schedulerKind, displayID == current { return }
        if schedulerKind == .timer, displayID == nil { return }

        stopFrameScheduler()
        if let screen, let displayID {
            schedulerGeneration &+= 1
            let generation = schedulerGeneration
            scheduler = screen.startDisplayLink { [weak self] timestamp, duration in
                self?.displayLinkFired(generation: generation, timestamp: timestamp, duration: duration)
            }
            schedulerKind = .displayLink(displayID)
            return
        }

        lastFrameTimestamp = environment.uptime() - SmoothScrollSupport.frameInterval
        schedulerGeneration &+= 1
        scheduler = environment.startTimer(SmoothScrollSupport.frameInterval) { [weak self] in
            self?.emitTimerFrame()
        }
        schedulerKind = .timer
        emitTimerFrame()
    }

    private func stopFrameScheduler() {
        // A scheduled display link retains its target until invalidated.
        scheduler?.invalidate()
        scheduler = nil
        schedulerKind = .none
        lastFrameTimestamp = nil
    }

    private func displayLinkFired(generation: UInt, timestamp: TimeInterval, duration: TimeInterval) {
        guard case .displayLink = schedulerKind, generation == schedulerGeneration else { return }
        let firstElapsed = duration > 0 ? duration : SmoothScrollSupport.frameInterval
        emitFrame(at: timestamp, firstElapsed: firstElapsed)
    }

    private func emitTimerFrame() {
        emitFrame(
            at: environment.uptime(),
            firstElapsed: SmoothScrollSupport.frameInterval
        )
    }

    private func emitFrame(at timestamp: TimeInterval, firstElapsed: TimeInterval) {
        let elapsed: TimeInterval
        if let lastFrameTimestamp {
            elapsed = timestamp - lastFrameTimestamp
        } else {
            elapsed = firstElapsed
        }
        lastFrameTimestamp = timestamp
        let frame = engine.advance(elapsed: elapsed, response: currentResponse, coast: currentCoast)

        // The frame that empties the budget is the glide's last, so it spends
        // the leftovers rather than saving them for a frame that never comes.
        if frame.vertical != 0 || frame.horizontal != 0 {
            post(vertical: frame.vertical, horizontal: frame.horizontal, landing: frame.finished)
        }
        if frame.finished {
            stopFrameScheduler()
            carryVertical = 0
            carryHorizontal = 0
        }
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = environment.screenNotifications.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                guard self?.engine.isActive == true else { return }
                self?.startGlideIfNeeded()
            }
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            environment.screenNotifications.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    private func installSleepObserver() {
        guard sleepObserver == nil else { return }
        sleepObserver = environment.sleepNotifications.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    private func removeSleepObserver() {
        if let sleepObserver {
            environment.sleepNotifications.removeObserver(sleepObserver)
        }
        sleepObserver = nil
    }

    private func post(vertical: Double, horizontal: Double, landing: Bool) {
        let up = landing
            ? (pixels: SmoothScrollSupport.finalPixels(vertical, carry: carryVertical), carry: 0)
            : SmoothScrollSupport.wholePixels(vertical, carry: carryVertical)
        let across = landing
            ? (pixels: SmoothScrollSupport.finalPixels(horizontal, carry: carryHorizontal), carry: 0)
            : SmoothScrollSupport.wholePixels(horizontal, carry: carryHorizontal)
        carryVertical = up.carry
        carryHorizontal = across.carry
        guard up.pixels != 0 || across.pixels != 0 else { return }
        environment.post(Self.pixelField(up.pixels), Self.pixelField(across.pixels), currentFlags)
    }

    /// A frame's distance as the event field wants it, never trapping on a
    /// value the math could not have produced.
    private static func pixelField(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        return Int32(clamping: Int(min(max(value, -1_000_000), 1_000_000)))
    }
}

/// The Objective-C target a display link calls, handing each frame to the
/// glide. Main-actor: the link is added to the main run loop.
@MainActor
private final class SmoothScrollLinkTarget: NSObject {
    private let frame: @MainActor (_ timestamp: TimeInterval, _ duration: TimeInterval) -> Void

    init(frame: @escaping @MainActor (_ timestamp: TimeInterval, _ duration: TimeInterval) -> Void) {
        self.frame = frame
        super.init()
    }

    @objc func fire(_ link: CADisplayLink) {
        frame(link.timestamp, link.duration)
    }
}
