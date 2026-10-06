// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign

/// Filters a complete accidental click immediately after a healthy click.
/// Healthy Down and Up events are never delayed. A suppressed bounce Down owns
/// exactly one suppressed Up, while every Up belonging to an accepted Down is
/// passed through, so lifecycle resets cannot leave a button stuck. This safe
/// boundary filters complete extra clicks; it does not delay an Up to repair
/// contact noise in the middle of a click being held.
///
/// The click state answers under `eventLock`, the tap's lifecycle under
/// `lifecycleLock`, and the sleep observers live on the main thread, so it is
/// `@unchecked Sendable`.
package final class MouseClickDebounceService: @unchecked Sendable {
    package static let shared = MouseClickDebounceService(environment: .live)

    /// What the click filter reaches outside itself: its preferences, the
    /// Accessibility grant, the session, sleep and wake, the main queue, the
    /// thread that serves the tap and the tap. `live` is the Mac; a test hands
    /// in doubles, runs a started thread's body itself and gets no tap, so no
    /// real click is filtered.
    package struct Environment: @unchecked Sendable {
        /// Whether the feature is available and switched on.
        package var featureWanted: @Sendable () -> Bool
        /// The filter window the preference asks for, before sanitizing.
        package var windowMilliseconds: @Sendable () -> Int
        package var accessibilityGranted: @Sendable () -> Bool
        package var session: SessionActivity
        /// Where sleep and wake are posted.
        package var workspaceNotifications: NotificationCenter
        /// Runs work on the main queue.
        package var main: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// Starts the thread that serves the tap.
        package var startThread: @Sendable (@escaping @Sendable () -> Void) -> Void
        /// Creates the tap whose callback feeds `owner`; nil when refused.
        package var createTap: @Sendable (_ owner: MouseClickDebounceService) -> CFMachPort?

        // Spelled out because a memberwise initializer never leaves its module.
        package init(featureWanted: @escaping @Sendable () -> Bool,
                     windowMilliseconds: @escaping @Sendable () -> Int,
                     accessibilityGranted: @escaping @Sendable () -> Bool,
                     session: SessionActivity,
                     workspaceNotifications: NotificationCenter,
                     main: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     startThread: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void,
                     createTap: @escaping @Sendable (_ owner: MouseClickDebounceService) -> CFMachPort?) {
            self.featureWanted = featureWanted
            self.windowMilliseconds = windowMilliseconds
            self.accessibilityGranted = accessibilityGranted
            self.session = session
            self.workspaceNotifications = workspaceNotifications
            self.main = main
            self.startThread = startThread
            self.createTap = createTap
        }

        package static var live: Environment {
            Environment(
                featureWanted: {
                    AppFeature.mouseClickDebounce.isAvailable
                        && UserDefaults.standard[Preferences.mouseClickDebounceEnabled]
                },
                windowMilliseconds: {
                    UserDefaults.standard.integer(forKey: DefaultsKey.mouseClickDebounceWindowMs)
                },
                accessibilityGranted: { AXIsProcessTrusted() },
                session: .shared,
                workspaceNotifications: NSWorkspace.shared.notificationCenter,
                main: { work in DispatchQueue.main.async(execute: work) },
                startThread: { body in
                    let thread = Thread(block: body)
                    thread.name = "Vitruvian Mouse Click Debounce"
                    thread.qualityOfService = .userInteractive
                    thread.start()
                },
                createTap: { owner in
                    CGEvent.tapCreate(
                        tap: .cghidEventTap,
                        place: .headInsertEventTap,
                        options: .defaultTap,
                        eventsOfInterest: MouseClickDebounceService.eventMask,
                        callback: { _, type, event, userInfo in
                            guard let userInfo else { return Unmanaged.passUnretained(event) }
                            let service = Unmanaged<MouseClickDebounceService>
                                .fromOpaque(userInfo).takeUnretainedValue()
                            return service.handle(type: type, event: event)
                        },
                        userInfo: Unmanaged.passUnretained(owner).toOpaque()
                    )
                })
        }
    }

    private static let ownProcessID = Int64(getpid())

    private static let eventMask: CGEventMask = [
        CGEventType.leftMouseDown,
        .leftMouseDragged,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseDragged,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseDragged,
        .otherMouseUp,
    ].reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

    private let environment: Environment
    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var lifecycle = MouseClickDebounceLifecycle()
    private var sleepObservers: [NSObjectProtocol] = []
    private var state = MouseClickDebounceState()
    private var config = MouseClickDebounceConfig(
        enabled: false,
        windowMilliseconds: Defaults.defaultMouseClickDebounceWindowMs
    )

    package init(environment: Environment) {
        self.environment = environment
        environment.session.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    package func syncWithPreferences() {
        let wanted = environment.featureWanted()
        let shouldRun = SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: environment.accessibilityGranted(),
            sessionIsActive: environment.session.isActive
        )
        let nextConfig = MouseClickDebounceConfig(
            enabled: shouldRun,
            windowMilliseconds: Defaults.sanitizedMouseClickDebounceWindow(
                environment.windowMilliseconds()
            )
        )
        eventLock.withLock {
            config = nextConfig
            state.reset()
        }

        if shouldRun {
            installSleepObservers()
            start()
        } else {
            stop()
        }
    }

    package func suspend() {
        stop()
    }

    private func start() {
        let startsThread = lifecycleLock.withLock { lifecycle.requestStart() }
        guard startsThread else { return }
        environment.startThread { [weak self] in
            self?.runEventTap()
        }
    }

    private func stop() {
        removeSleepObservers()
        eventLock.withLock {
            state.reset()
        }
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?) in
            lifecycle.requestStop()
            return (tapRunLoop, tap)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }
            let shouldStopBeforeCreatingTap = lifecycleLock.withLock {
                lifecycle.isStopping
            }
            guard !shouldStopBeforeCreatingTap else {
                finishEventTapThread()
                return
            }

            guard let tap = environment.createTap(self) else {
                finishEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock { lifecycle.isStopping }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            eventLock.withLock {
                state.reset()
            }
            finishEventTapThread()
        }
    }

    /// The serving thread is gone. A start asked while it was on its way out
    /// is made on the main queue, through the preferences, and only if no
    /// newer lifecycle change came first.
    private func finishEventTapThread() {
        let restart = clearEventTapThread()
        guard restart.restart else { return }
        environment.main { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                self.lifecycle.isCurrent(restart.generation)
            }
            guard isCurrent else { return }
            self.syncWithPreferences()
        }
    }

    private func clearEventTapThread() -> (restart: Bool, generation: UInt) {
        lifecycleLock.withLock {
            tap = nil
            tapRunLoop = nil
            return lifecycle.threadFinished()
        }
    }

    private func installSleepObservers() {
        guard sleepObservers.isEmpty else { return }
        let center = environment.workspaceNotifications
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.eventLock.withLock {
                    self.state.reset()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.suspend()
                self.syncWithPreferences()
            },
        ]
    }

    private func removeSleepObservers() {
        let center = environment.workspaceNotifications
        for observer in sleepObservers {
            center.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapWasDisabled()
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID,
              let input = MouseClickDebounceInput.resolve(
                type: type,
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber)
              ) else {
            return Unmanaged.passUnretained(event)
        }

        return suppresses(input, at: EventTimestamp.nanoseconds(of: event))
            ? nil : Unmanaged.passUnretained(event)
    }

    /// The tap's answer for one click event it filters: true swallows it.
    package func suppresses(_ input: MouseClickDebounceInput, at timestampNanoseconds: UInt64) -> Bool {
        eventLock.withLock {
            state.shouldSuppress(
                button: input.button,
                event: input.event,
                timestampNanoseconds: timestampNanoseconds,
                config: config
            )
        }
    }

    /// The window server switched the tap off. Clicks went by unseen, so the
    /// ownership kept for them is forgotten first; the tap then goes straight
    /// back on only while it should run at all, and is otherwise rebuilt on
    /// the main queue, unless a newer lifecycle change gets there first.
    package func tapWasDisabled() {
        eventLock.withLock {
            state.reset()
        }
        let stopping = lifecycleLock.withLock { lifecycle.isStopping }
        let shouldRearm = MouseClickDebounceLifecycle.rearmsDisabledTap(
            enabled: eventLock.withLock { config.enabled },
            sessionIsActive: environment.session.isActive,
            accessibilityGranted: environment.accessibilityGranted(),
            stopping: stopping)
        let currentTap = lifecycleLock.withLock { tap }
        if shouldRearm, let currentTap {
            CGEvent.tapEnable(tap: currentTap, enable: true)
        } else {
            let recoveryGeneration = lifecycleLock.withLock { lifecycle.generation }
            environment.main { [weak self] in
                guard let self else { return }
                let isCurrent = self.lifecycleLock.withLock {
                    self.lifecycle.isCurrent(recoveryGeneration)
                }
                guard isCurrent else { return }
                self.stop()
                self.syncWithPreferences()
            }
        }
    }
}
