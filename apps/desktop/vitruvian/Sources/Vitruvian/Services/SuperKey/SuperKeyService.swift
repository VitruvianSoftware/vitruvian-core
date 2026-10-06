// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
@preconcurrency import CoreFoundation
import CoreGraphics
import IOKit
import IOKit.hidsystem
import VitruvianCore
import VitruvianDesign

/// Turns one key into the user's chosen modifiers.
///
/// Two halves make it work. The keyboard mapping table turns the source into
/// F18; the event tap then keeps that key to itself and adds the user's
/// chosen modifiers to whatever is pressed while it is down. Nothing is
/// installed while the feature is off, and the mapping is always taken back
/// out when the feature goes off or the app quits. Requires Accessibility:
/// without it the tap cannot modify events, and the mapping is not applied
/// either, so the source is never left as a key that does nothing.
@MainActor
package final class SuperKeyService: ObservableObject {
    /// What the key reaches outside itself: the settings, the event taps and
    /// the thread they run on, the main queue that thread reports back to,
    /// Accessibility, and hidutil. `live` is the system's; tests pass
    /// doubles, so no tap, thread or key mapping is made.
    package struct System: @unchecked Sendable {
        /// Sendable by hand only for `defaults`: UserDefaults is thread-safe.
        package var defaults: UserDefaults
        package var createTap: @Sendable (CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions,
                                          CGEventMask, CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?
        /// Starts the tap thread.
        package var runThread: @Sendable (Thread) -> Void
        /// Where a refused or restarting tap thread reports back.
        package var main: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
        package var isTrusted: @Sendable () -> Bool
        /// Runs hidutil with these arguments and answers its status and output.
        package var hidutil: @Sendable ([String]) -> (status: Int32, output: String)

        // Spelled out because a memberwise initializer never leaves its module.
        package init(defaults: UserDefaults,
                     createTap: @escaping @Sendable (CGEventTapLocation, CGEventTapPlacement, CGEventTapOptions,
                                                     CGEventMask, CGEventTapCallBack,
                                                     UnsafeMutableRawPointer?) -> CFMachPort?,
                     runThread: @escaping @Sendable (Thread) -> Void,
                     main: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void,
                     isTrusted: @escaping @Sendable () -> Bool,
                     hidutil: @escaping @Sendable ([String]) -> (status: Int32, output: String)) {
            self.defaults = defaults
            self.createTap = createTap
            self.runThread = runThread
            self.main = main
            self.isTrusted = isTrusted
            self.hidutil = hidutil
        }

        package static var live: System {
            System(defaults: .standard,
                   createTap: { CGEvent.tapCreate(tap: $0, place: $1, options: $2, eventsOfInterest: $3,
                                                  callback: $4, userInfo: $5) },
                   runThread: { $0.start() },
                   main: { work in DispatchQueue.main.async { work() } },
                   isTrusted: { AXIsProcessTrusted() },
                   hidutil: { Shell.run("/usr/bin/hidutil", $0) })
        }
    }

    package static let shared = SuperKeyService(system: .live)
    nonisolated private let system: System

    /// True while the key is actually working: tap up and mapping applied.
    @Published package private(set) var isRunning = false
    @Published package private(set) var isPausedForApplication = false
    /// What stopped the mapping, while it is stopped. The feature has several
    /// reasons to refuse, and none of them is visible in the key itself.
    @Published package private(set) var mappingFailure: SuperKeyMappingFailure?
    @Published package private(set) var modifiers = SuperKeySupport.defaultModifiers
    @Published package private(set) var source = SuperKeySource.capsLock

    /// Read by the shortcut recording tap, which sits ahead of this one while a
    /// field is listening and would otherwise see the bare trigger key instead
    /// of the combination it stands for. Written and read on the main thread.
    package private(set) static var isEngaged = false

    /// A held gesture can follow this virtual modifier. True means the key was
    /// released; false means the hold was cancelled by teardown or recovery.
    package var onHoldEnded: ((_ released: Bool) -> Void)?
    package var isHeld: Bool { stateLock.withLock { state.isHeld } }

    /// Matches every keyboard, including one plugged in later.
    private let keyboardMatch = "keyboard"

    // The active tap must answer every key before the window server can deliver
    // it. A user-interactive run loop keeps that answer independent from UI,
    // window enumeration and every other main-thread task.
    // `lifecycleLock` guards the taps, the refusal count, the tap thread's
    // flags and the mapping generation; `stateLock` guards the key state,
    // what it adds and when it was last mapped. The tap thread reads both.
    private let lifecycleLock = NSLock()
    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var mouseTap: CFMachPort?
    /// How many times in a row the mouse tap was asked for and refused. Only
    /// the first one counts as a dead tap: the cure is a full rebuild, and
    /// that takes the healthy keyboard tap down with it, dropping held-key
    /// state and letting events through untapped for the gap. After that the
    /// mouse half stays broken and the keyboard half is left alone. Back to
    /// zero only when a tap is actually created, so a refusal after a working
    /// stretch is a new episode with its own single retry.
    nonisolated(unsafe) private var mouseTapRefusals = SuperKeyMouseTapRefusals()
    /// The presses the mouse tap watches, one list for both the tap mask and
    /// classify, so a button added later is added in one place. Moves and
    /// drags stay out: chords are read on the press, and per-move tap work is
    /// a known stutter source.
    nonisolated package static let mouseDownTypes: [CGEventType] = [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ]
    /// The mouse tap's mask: exactly `mouseDownTypes`.
    nonisolated package static var mouseEventMask: CGEventMask {
        mouseDownTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }
    /// Where the mouse presses are stamped: the HID stage, which runs before
    /// every session tap whatever the creation order, so consumers in this
    /// process and clicks delivered to other apps all see the held modifiers.
    nonisolated package static let mouseTapLocation: CGEventTapLocation = .cghidEventTap
    nonisolated(unsafe) private var tapRunLoop: CFRunLoop?
    nonisolated(unsafe) private var tapThread: Thread?
    nonisolated(unsafe) private var shouldStopTapThread = false
    nonisolated(unsafe) private var pendingTapRestart = false
    /// Invalidates a mapping request that was captured before a stop. Without
    /// this, a raw-key repair can enqueue a new mapping after the final clear.
    nonisolated(unsafe) private var mappingGeneration: UInt = 0
    private let stateLock = NSLock()
    nonisolated(unsafe) private var state = SuperKeySupport.State()
    nonisolated(unsafe) private var soloAction: SuperKeySoloAction = .none
    nonisolated(unsafe) private var eventModifiers = SuperKeySupport.defaultModifiers
    nonisolated(unsafe) private var eventSource = SuperKeySource.capsLock
    private var wakeObserver: NSObjectProtocol?
    private var exceptionObservation: AnyCancellable?
    /// The mapping is written off the main thread, and in the order it was
    /// asked for: a queue of one keeps an apply and a clear from crossing.
    private let mappingQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.superkey-mapping")
    /// Lives only while the mapping is owned and clears it if this process is
    /// killed before applicationWillTerminate can run.
    /// Touched only on `mappingQueue`.
    nonisolated(unsafe) private var mappingGuard: SuperKeyMappingGuard.Handle?
    /// When the last mapping went in, so a keyboard that arrives without one
    /// is repaired once and not on every keystroke.
    nonisolated(unsafe) private var lastMappingAt: TimeInterval = 0
    /// A stop requested while an apply is queued must enqueue a clear behind
    /// it, even though the persistent marker is not written until readback.
    nonisolated(unsafe) private var pendingMappingEnableCount = 0
    private let mappingRepairInterval: TimeInterval = 3
    /// Lets go of a press whose release never arrived. Without it the chosen
    /// modifiers would ride every keystroke from then on, with no way back but
    /// pressing the key again, and typing would be dead in the meantime.
    private var heldKeyWatchdog: DispatchWorkItem?
    /// How long before a held press is re-checked. The source is remapped to
    /// F18, which does not autorepeat, so the deadline cannot lean on repeats to
    /// know the key is still down: when it fires the watchdog reads the key's
    /// real state and either watches again or lets go (`reevaluateHold`).
    /// So this is both the poll interval while held and the longest a press
    /// whose key-up was lost keeps the modifiers down. Taken from the keyboard's
    /// own first-repeat delay and bounded at both ends: never so short it churns,
    /// never so long a lost release strands the keyboard.
    private var heldKeyTimeout: TimeInterval {
        let firstRepeat = NSEvent.keyRepeatDelay
        guard firstRepeat.isFinite, firstRepeat > 0 else { return 3 }
        return min(30, max(3, firstRepeat * 2))
    }

    package init(system: System) {
        self.system = system
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    package func syncWithPreferences() {
        let defaults = system.defaults
        let action = SuperKeySoloAction.sanitized(
            defaults.string(forKey: DefaultsKey.superKeySoloAction)
        )
        let modifiers = SuperKeySupport.modifiers(
            from: defaults.string(forKey: DefaultsKey.superKeyModifiers)
        )
        let source = SuperKeySource.sanitized(
            defaults.string(forKey: DefaultsKey.superKeySource)
        )
        let sourceChanged = self.source != source
        stateLock.withLock {
            soloAction = action
            eventModifiers = modifiers
            eventSource = source
        }
        self.modifiers = modifiers
        self.source = source
        let enabled = AppFeature.superKey.isAvailable
            && defaults.bool(forKey: DefaultsKey.superKeyEnabled)
            && SessionActivity.shared.isActive
        syncExceptionMonitoring(enabled: enabled && system.isTrusted())
        guard enabled, !isPausedForApplication else {
            stop()
            return
        }
        // A tap the system disabled (Accessibility revoked and granted again)
        // never revives on its own; rebuild it instead of keeping the corpse.
        // A mouse tap the system refused counts as dead too, or it would stay
        // missing for the rest of the run with nothing to notice — but only
        // the first refusal does, or every sync from here on would tear the
        // working keyboard tap down to ask a question already answered.
        let deadTap = lifecycleLock.withLock { () -> Bool in
            mouseTapRefusals.tapsNeedRebuild(keyboardTapEnabled: tap.map { CGEvent.tapIsEnabled(tap: $0) },
                                             mouseTapEnabled: mouseTap.map { CGEvent.tapIsEnabled(tap: $0) })
        }
        if deadTap || sourceChanged { stop() }
        start()
    }

    /// Quitting takes the mapping out on the spot: the process is about to go
    /// away, and a mapping left behind would leave its source doing nothing.
    package func suspend() {
        syncExceptionMonitoring(enabled: false)
        stop(synchronously: true)
    }

    private func syncExceptionMonitoring(enabled: Bool) {
        let exceptions = MouseAppExceptions.shared
        if enabled {
            if exceptionObservation == nil {
                exceptionObservation = exceptions.$runningScopes
                    .map { $0.contains(.superKey) }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] _ in self?.syncWithPreferences() }
            }
        } else {
            exceptionObservation = nil
        }
        // Tracking outlives a pause: the final app exit must restart the key.
        // An empty list leaves the shared workspace observer stopped.
        exceptions.setSourceTracking(enabled, for: .superKey)
        let paused = enabled && exceptions.runningScopes.contains(.superKey)
        if isPausedForApplication != paused { isPausedForApplication = paused }
    }

    package func start() {
        let tapExists = lifecycleLock.withLock { tap != nil && !shouldStopTapThread }
        guard !tapExists else { return }
        // Without Accessibility the tap cannot add the modifiers, and a
        // mapping alone would turn its source into a dead key. One left by a
        // run that was killed comes out here too: with the feature still
        // enabled, the launch-time stop() that normally clears it never runs.
        guard system.isTrusted() else {
            clearLeftoverMapping()
            isRunning = false
            return
        }
        forgetHeldKey()
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vitruvian Super Key"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        if let thread { system.runThread(thread) }
    }

    private func stop(synchronously: Bool = false) {
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, mouseTap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            mappingGeneration &+= 1
            return (tapRunLoop, tap, mouseTap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let mouseTap = snapshot.mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
        if let runLoop = snapshot.runLoop {
            TapThreadRunLoop.stop(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        forgetHeldKey()
        Self.isEngaged = false
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        clearLeftoverMapping(synchronously: synchronously)
        isRunning = false
        setMappingFailure(nil)
    }

    nonisolated
    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }
            guard !lifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
                | (CGEventMask(1) << CGEventType.keyUp.rawValue)
                | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            guard let tap = system.createTap(
                .cgSessionEventTap,
                .headInsertEventTap,
                .defaultTap,
                mask,
                { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                system.main { [weak self] in
                    guard let self else { return }
                    let stillStopped = self.lifecycleLock.withLock {
                        self.tap == nil && self.tapThread == nil
                    }
                    guard stillStopped else { return }
                    self.clearLeftoverMapping()
                    self.isRunning = false
                    Self.isEngaged = false
                    self.setMappingFailure(.keyboardTapRefused)
                }
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            // Mouse button presses need the modifiers too — a drag chord like
            // "move and resize by dragging" reads them off the mouse-down, not
            // off any keyboard event (#888). They are stamped from a separate
            // tap at the HID stage, which runs before every session tap
            // regardless of creation order, so consumers in this process and
            // clicks delivered to other apps both see the held modifiers.
            // Moves and drags stay out of the mask: chords are read on the
            // press, and per-move tap work is a known stutter source. Middle,
            // back and forward are in: their consumers read the button number
            // and set their own flags on anything they send on, so a stamped
            // press changes nothing for them and every mouse shortcut is
            // reached by the same chord as every other click.
            let mouseTap = system.createTap(
                Self.mouseTapLocation,
                .headInsertEventTap,
                .defaultTap,
                Self.mouseEventMask,
                { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<SuperKeyService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            var mouseSource: CFRunLoopSource?
            lifecycleLock.withLock {
                self.mouseTap = mouseTap
                self.mouseTapRefusals.requested(created: mouseTap != nil)
            }
            if let mouseTap {
                mouseSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mouseTap, 0)
                CFRunLoopAddSource(runLoop, mouseSource, .commonModes)
                CGEvent.tapEnable(tap: mouseTap, enable: true)
            }

            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }
            if lifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false) }
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if let mouseTap {
                CGEvent.tapEnable(tap: mouseTap, enable: false)
                if let mouseSource { CFRunLoopRemoveSource(runLoop, mouseSource, .commonModes) }
                CFMachPortInvalidate(mouseTap)
            }
            if clearEventTapThread() { startOnMain() }
        }
    }

    nonisolated private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            mouseTap = nil
            // mouseTapRefusals deliberately stays: it has to outlive the
            // teardown its own count asked for, or the rebuild it triggers
            // would clear the count and ask again for the rest of the run.
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    nonisolated private func startOnMain() {
        system.main { [weak self] in self?.syncWithPreferences() }
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let generation = lifecycleLock.withLock { () -> UInt? in
            guard tap === startedTap, !shouldStopTapThread else { return nil }
            return mappingGeneration
        }
        guard let generation else { return }
        confirmMapping(for: startedTap, generation: generation, publishingRunState: true)
    }

    /// The mapping is cleared even when this service never applied it: an
    /// app that was killed while the feature was on leaves one behind, and
    /// every path that ends without a live tap takes it out, so the source is
    /// never left as a key that does nothing.
    private func clearLeftoverMapping(synchronously: Bool = false) {
        let mappingMayBeApplied = system.defaults.bool(
            forKey: DefaultsKey.superKeyMappingApplied
        ) || stateLock.withLock { pendingMappingEnableCount > 0 }
        if mappingMayBeApplied {
            applyMapping(false, synchronously: synchronously)
        }
    }

    /// Sleep can bring the keyboard back without the mapping, and so can
    /// plugging in another one. Waking is the cheap moment to put it back.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self,
                  let active = self.lifecycleLock.withLock({
                      self.shouldStopTapThread ? nil : self.tap.map { ($0, self.mappingGeneration) }
                  })
            else { return }
            self.confirmMapping(for: active.0, generation: active.1, publishingRunState: false)
        }
    }

    // MARK: - The key mapping

    nonisolated private func applyMapping(_ enabled: Bool,
                              expectedTap: CFMachPort? = nil,
                              generation: UInt? = nil,
                              synchronously: Bool = false,
                              completion: (@MainActor (SuperKeyMappingFailure?) -> Void)? = nil) {
        let source = stateLock.withLock { eventSource }
        stateLock.withLock {
            lastMappingAt = ProcessInfo.processInfo.systemUptime
            if enabled { pendingMappingEnableCount += 1 }
        }
        let work: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            defer {
                if enabled {
                    self.stateLock.withLock { self.pendingMappingEnableCount -= 1 }
                }
            }
            if enabled {
                guard let expectedTap, let generation,
                      self.lifecycleLock.withLock({
                          SuperKeySupport.mappingRequestIsAuthorized(
                              requestGeneration: generation,
                              currentGeneration: self.mappingGeneration,
                              tapIsCurrent: self.tap === expectedTap,
                              stopping: self.shouldStopTapThread
                          )
                      })
                else { return }
            }
            let defaults = self.system.defaults
            let previousMarker = defaults.bool(forKey: DefaultsKey.superKeyMappingApplied)
            let ownedSource = previousMarker ? SuperKeySource.sanitized(
                defaults.string(forKey: DefaultsKey.superKeyMappedSource)
            ) : nil
            let failure = self.performMapping(
                enabled,
                source: source,
                ownedSource: ownedSource
            )
            if !enabled {
                let guardConfirmed = self.mappingGuard?.stop() ?? false
                self.mappingGuard = nil
                let marker = SuperKeySupport.mappingMarkerAfterClear(
                    previous: previousMarker,
                    readbackConfirmed: failure == nil || guardConfirmed
                )
                defaults.set(marker, forKey: DefaultsKey.superKeyMappingApplied)
                if !marker { defaults.removeObject(forKey: DefaultsKey.superKeyMappedSource) }
            }
            if let completion {
                DispatchQueue.main.async { completion(failure) }
            }
        }
        if synchronously {
            mappingQueue.sync(execute: work)
        } else {
            mappingQueue.async(execute: work)
        }
    }

    /// Applies or clears the mapping, and answers with the reason it could not
    /// be done, or nil when it was.
    ///
    /// Modifier Keys rules cannot be read here: hidd keeps
    /// `HIDKeyboardModifierMappingPairs` per client connection, so hidutil
    /// answers null for rules written by System Settings.
    nonisolated private func performMapping(_ enabled: Bool,
                                source: SuperKeySource,
                                ownedSource: SuperKeySource?) -> SuperKeyMappingFailure? {
        let report = system.hidutil(
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard report.status == 0 else { return .systemRefused }
        guard let existing = SuperKeySupport.consistentMappings(
            report.output,
            property: SuperKeySupport.userMappingProperty,
            ownedSource: ownedSource
        ) else { return .foreignMapping }
        guard !enabled || !SuperKeySupport.hasMappingConflict(
            in: existing,
            source: source,
            ownedSource: ownedSource
        )
        else { return .foreignMapping }
        let wanted = SuperKeySupport.mappings(
            enablingSuperKey: enabled,
            existing: existing,
            source: source,
            ownedSource: ownedSource
        )
        if !enabled, ownedSource == nil,
           SuperKeySupport.mappingsMatch(existing, wanted) { return nil }
        var startedGuard = false
        var mappingConfirmed = false
        if enabled {
            if let mappingGuard, mappingGuard.source != source {
                guard mappingGuard.stop() else { return .systemRefused }
                self.mappingGuard = nil
            }
            if mappingGuard == nil {
                guard let guardHandle = SuperKeyMappingGuard.start(source: source) else {
                    return .systemRefused
                }
                mappingGuard = guardHandle
                startedGuard = true
            }
            // Recovery is write-ahead only after every external-mapping check
            // passed. A crash after the command starts must leave the next
            // launch authorized to remove a possibly partial application.
            system.defaults.set(true, forKey: DefaultsKey.superKeyMappingApplied)
            system.defaults.set(source.rawValue, forKey: DefaultsKey.superKeyMappedSource)
        }
        defer {
            if startedGuard, !mappingConfirmed {
                let cleared = mappingGuard?.stop() ?? false
                mappingGuard = nil
                if cleared {
                    system.defaults.set(false, forKey: DefaultsKey.superKeyMappingApplied)
                    system.defaults.removeObject(forKey: DefaultsKey.superKeyMappedSource)
                }
            }
        }
        let write = system.hidutil(
            ["property", "--matching", keyboardMatch,
             "--set", SuperKeySupport.mappingArgument(wanted)]
        )
        guard write.status == 0 else { return .systemRefused }
        let readback = system.hidutil(
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard readback.status == 0 else { return .systemRefused }
        mappingConfirmed = SuperKeySupport.mappingReportConfirms(readback.output, expected: wanted)
        return mappingConfirmed ? nil : .systemRefused
    }

    nonisolated private func confirmMapping(for expectedTap: CFMachPort,
                                generation: UInt,
                                publishingRunState: Bool) {
        applyMapping(true, expectedTap: expectedTap, generation: generation) { [weak self] failure in
            guard let self else { return }
            let active = self.lifecycleLock.withLock {
                SuperKeySupport.mappingRequestIsAuthorized(
                    requestGeneration: generation,
                    currentGeneration: self.mappingGeneration,
                    tapIsCurrent: self.tap === expectedTap,
                    stopping: self.shouldStopTapThread
                )
            }
            guard active else { return }
            guard let failure else {
                self.setMappingFailure(nil)
                if publishingRunState || !self.isRunning { self.finishStart() }
                return
            }
            if publishingRunState {
                self.stop()
            } else {
                // A failed repair keeps the existing tap alive so a later
                // repair can recover without rebuilding the event pipeline.
                self.isRunning = false
            }
            self.setMappingFailure(failure)
        }
    }

    private func finishStart() {
        // Caps Lock left on would have no way back once the key stops locking.
        if source == .capsLock { setCapsLock(false) }
        observeWake()
        isRunning = true
        Self.isEngaged = true
    }

    /// Repair runs every few seconds while typing; republishing an unchanged
    /// reason would redraw Settings just as often.
    private func setMappingFailure(_ failure: SuperKeyMappingFailure?) {
        guard mappingFailure != failure else { return }
        mappingFailure = failure
    }

    /// A keyboard that arrives after the mapping was applied still sends the
    /// raw source; the first press on it is the signal to map it too. Repaired
    /// at most once every few seconds. A keyboard that refuses the mapping
    /// cannot turn typing into a stream of commands.
    nonisolated private func repairMappingIfStale() {
        guard let active = lifecycleLock.withLock({
            shouldStopTapThread ? nil : tap.map { ($0, mappingGeneration) }
        }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let shouldRepair = stateLock.withLock {
            now - lastMappingAt >= mappingRepairInterval
        }
        if shouldRepair {
            confirmMapping(for: active.0, generation: active.1, publishingRunState: false)
        }
    }

    // MARK: - The tap

    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTaps = lifecycleLock.withLock {
                shouldStopTapThread ? (nil, nil) : (tap, mouseTap)
            }
            if SessionActivity.shared.isActive, system.isTrusted() {
                if let currentTap = currentTaps.0 { CGEvent.tapEnable(tap: currentTap, enable: true) }
                if let currentMouseTap = currentTaps.1 { CGEvent.tapEnable(tap: currentMouseTap, enable: true) }
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            forgetHeldKey()
            return Unmanaged.passUnretained(event)
        }
        let source = stateLock.withLock { eventSource }
        let event0 = SuperKeyService.classify(type: type, source: source, event: event)
        let decision = stateLock.withLock { state.decide(event0) }
        // Only the key's own events say it is still down: the first press and
        // the repeats the system sends while it is held. Keys pressed meanwhile
        // must NOT push the deadline out. Someone whose keyboard is stuck under
        // a press that never lifted is typing, and letting that typing hold the
        // deadline open would keep it stuck for exactly as long as they kept
        // trying to get out of it.
        switch event0 {
        case .triggerDown:
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      }),
                      self.stateLock.withLock({ self.state.isHeld })
                else { return }
                self.armHeldKeyWatchdog()
            }
        case .triggerUp:
            DispatchQueue.main.async { [weak self] in
                self?.cancelHeldKeyWatchdog()
                self?.onHoldEnded?(true)
            }
        case .otherKey, .otherModifier, .sourceKey:
            break
        }
        switch decision {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .addModifiers:
            let modifierFlags = stateLock.withLock { eventModifiers.cgFlags }
            event.flags = event.flags.union(modifierFlags)
            return Unmanaged.passUnretained(event)
        case .soloTap(repeated: let repeated):
            performSoloAction(longHold: false, repeated: repeated)
            return nil
        case .soloHold(repeated: let repeated):
            performSoloAction(longHold: true, repeated: repeated)
            return nil
        case .interceptAndRemap:
            repairMappingIfStale()
            // At the session tap a missing Caps Lock mapping may already have
            // flipped the lock state. Put it back off while the mapping repairs.
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.lifecycleLock.withLock({
                          self.tap != nil && !self.shouldStopTapThread
                      })
                else { return }
                if source == .capsLock { self.setCapsLock(false) }
            }
            return nil
        }
    }

    // MARK: - A press whose release never came

    private func armHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reevaluateHold() }
        heldKeyWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + heldKeyTimeout, execute: work)
    }

    /// Decides whether a hold that reached its deadline should survive, and
    /// acts on it — re-arm the watchdog or let the modifiers go. The watchdog
    /// exists for a press whose key-up was lost, but the physical key (F18) does
    /// not autorepeat, so a key held perfectly steadily reaches here too. The
    /// only way to tell those apart is the real hardware state: still down means
    /// the hold is real, so watch again; up means the release was missed, so let
    /// go. Runs on the main thread, where the watchdog is scheduled; only the
    /// hardware read is moved off it.
    private func reevaluateHold() {
        guard stateLock.withLock({ state.isHeld }),
              lifecycleLock.withLock({ tap != nil && !shouldStopTapThread })
        else { forgetHeldKey(); return }
        readPhysicalKeyDown { [weak self] physicalKeyDown in
            guard let self else { return }
            // Re-read on the way back: the key may have come up during the hop.
            let stateThinksHeld = self.stateLock.withLock { self.state.isHeld }
            let tapAlive = self.lifecycleLock.withLock { self.tap != nil && !self.shouldStopTapThread }
            switch SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: physicalKeyDown,
                                                          stateThinksHeld: stateThinksHeld,
                                                          tapAlive: tapAlive) {
            case .reArm:
                self.armHeldKeyWatchdog()
            case .forget:
                self.forgetHeldKey()
            }
        }
    }

    /// Reads whether the physical source key is down, then calls `handler` on
    /// the main thread. It queries `triggerKeyCode` (F18), not `source.keyCode`:
    /// the key the user presses is remapped to F18 by hidutil, so that is what
    /// the hardware reports as down. Two things force the read off the main
    /// thread: keyState reaches the window server over a lock the main run loop
    /// itself has to service, so calling it from a main-queue block deadlocks
    /// the app; and only `.hidSystemState` reflects the remapped key — the
    /// combined session state reports it up even while it is held.
    private func readPhysicalKeyDown(_ handler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let key = CGKeyCode(SuperKeySupport.triggerKeyCode)
        DispatchQueue.global(qos: .userInitiated).async {
            let physicalKeyDown = CGEventSource.keyState(.hidSystemState, key: key)
            DispatchQueue.main.async { handler(physicalKeyDown) }
        }
    }

    private func cancelHeldKeyWatchdog() {
        heldKeyWatchdog?.cancel()
        heldKeyWatchdog = nil
    }

    /// Back to the key being up. State resets synchronously; UI callbacks stay
    /// on the main thread.
    nonisolated private func forgetHeldKey() {
        let wasHeld = stateLock.withLock { () -> Bool in
            let held = state.isHeld
            state.reset()
            return held
        }
        let notify: @Sendable () -> Void = { [weak self] in
            // Run on the main thread only: directly there, or queued to it below.
            MainActor.assumeIsolated {
                self?.cancelHeldKeyWatchdog()
                if wasHeld { self?.onHoldEnded?(false) }
            }
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }

    nonisolated package static func classify(type: CGEventType, source: SuperKeySource,
                                 event: CGEvent) -> SuperKeySupport.Event {
        // A mouse press while the key is held behaves like any other key: the
        // modifiers ride along and the press cancels the solo action. Answered
        // above the keycode read on purpose: a mouse event carries no keycode
        // and the field reads back as 0 on one, which is the keycode for A.
        // Kept here, no caller can hand that phantom key to anything.
        if mouseDownTypes.contains(type) { return .otherKey }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged {
            return keyCode == source.keyCode ? .sourceKey : .otherModifier
        }
        guard keyCode == SuperKeySupport.triggerKeyCode else { return .otherKey }
        if type == .keyDown {
            return .triggerDown(
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                hasPrimaryModifiers: !GlobalShortcutModifiers(cgFlags: event.flags).isEmpty,
                timestamp: UInt64(event.timestamp)
            )
        }
        return .triggerUp(timestamp: UInt64(event.timestamp))
    }

    // MARK: - Tapped on its own

    nonisolated private func performSoloAction(longHold: Bool, repeated: Bool) {
        let action = stateLock.withLock { soloAction }
        switch SuperKeySupport.soloEffect(action: action,
                                          longHold: longHold,
                                          repeated: repeated) {
        case .none:
            return
        case .escape:
            runOnMainIfNeeded { _ = Self.postKey(CGKeyCode(kVK_Escape)) }
        case .capsLock:
            runOnMainIfNeeded { self.setCapsLock(!self.capsLockIsOn()) }
        case .inputSource:
            // Must finish before this tap returns: the next keystroke is already
            // in flight, and hopping to main (or waiting on Accessibility) left
            // that character in the old source.
            Self.selectNextInputSource()
        }
    }

    nonisolated private func runOnMainIfNeeded(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    nonisolated private static func postKey(_ keyCode: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        // The HID source can inherit a still-held physical modifier.
        down.flags = []
        up.flags = []
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }

    /// Cycle enabled keyboard sources through TIS before the tap lets the next
    /// key through. An earlier path asked another app for marked text (up to
    /// 200 ms) and then slept 100 ms so Control-Space could commit IME
    /// composition; that wait ran on every tap, including ones with nothing to
    /// commit. Selecting the next source directly lets the input method commit
    /// or cancel on its own, the same way the Input menu does.
    nonisolated private static func selectNextInputSource() {
        let apply = {
            InputSourceSelection.selectNextSource(.live())
        }
        // TIS talks to the text-input server from the main thread. sync (not
        // async) keeps the switch ahead of the next keystroke this tap is
        // about to let through.
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    // MARK: - Caps Lock itself

    /// The lock state lives with the system's own keyboard service, which is
    /// also what lights the key.
    nonisolated private func withHIDSystem<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS
        else { return nil }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    nonisolated private func capsLockIsOn() -> Bool {
        withHIDSystem { connection in
            var state = false
            guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS
            else { return nil }
            return state
        } ?? false
    }

    nonisolated private func setCapsLock(_ on: Bool) {
        _ = withHIDSystem { connection in
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), on)
        }
    }
}
