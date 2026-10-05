// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Combine
import CoreGraphics
import Foundation
import VitruvianCore
import VitruvianDesign

/// Suppresses accidental duplicate physical key presses inside a short window.
/// Auto-repeat from a held key is left untouched so normal key-repeat behavior
/// keeps working.
@MainActor
package final class KeyboardDebounceService: ObservableObject {
    package static let shared = KeyboardDebounceService()

    @Published package private(set) var isRunning = false

    // The tap thread reads these too: `state` and `config` are guarded by
    // eventLock, the rest by lifecycleLock.
    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    nonisolated(unsafe) private var tap: CFMachPort?
    nonisolated(unsafe) private var runLoopSource: CFRunLoopSource?
    nonisolated(unsafe) private var tapRunLoop: CFRunLoop?
    nonisolated(unsafe) private var tapThread: Thread?
    nonisolated(unsafe) private var shouldStopTapThread = false
    nonisolated(unsafe) private var pendingStartAfterStop = false
    nonisolated(unsafe) private var lifecycleGeneration: UInt = 0
    nonisolated(unsafe) private var state = KeyboardDebounceState()
    nonisolated(unsafe) private var config = KeyboardDebounceConfig(enabled: false,
                                                globalWindowMs: Defaults.defaultKeyboardDebounceWindowMs,
                                                keyWindows: [:])

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    package func syncWithPreferences() {
        let nextConfig = KeyboardDebounceConfig(
            enabled: AppFeature.keyboardDebounce.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.keyboardDebounceEnabled),
            globalWindowMs: Defaults.sanitizedKeyboardDebounceWindow(
                UserDefaults.standard.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
            ),
            keyWindows: KeyboardDebounceConfig.decodeKeyWindows(
                UserDefaults.standard.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? ""
            )
        )
        eventLock.withLock {
            config = nextConfig
        }

        if SessionActivitySupport.tapShouldRun(featureWanted: nextConfig.enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    package func suspend() {
        stop()
    }

    nonisolated private func start() {
        eventLock.withLock {
            state.reset()
        }

        // The new thread is created and assigned to tapThread inside the same
        // critical section as the decision: a stop() must never observe
        // tapThread == nil while a start is committed, or it would reset
        // shouldStopTapThread and let the new thread enable a tap whose
        // "running" publish is then dropped as stale — a live tap with the
        // feature showing disabled.
        let startState = lifecycleLock.withLock { () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vitruvian Keyboard Debounce"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        eventLock.withLock {
            state.reset()
        }

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            TapThreadRunLoop.stop(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
    }

    nonisolated private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock {
                shouldStopTapThread
            }
            guard !shouldStopBeforeCreatingTap else {
                let shouldRestart = clearEventTapThread()
                if shouldRestart {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<KeyboardDebounceService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            eventLock.withLock {
                state.reset()
            }

            let shouldStop = lifecycleLock.withLock {
                shouldStopTapThread
            }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            eventLock.withLock {
                state.reset()
            }
            let shouldRestart = clearEventTapThread()
            if shouldRestart {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
        }
    }

    nonisolated private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    nonisolated private func publishRunning(_ running: Bool, generation: UInt) {
        let update: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            // Run on the main thread only: directly there, or queued to it below.
            MainActor.assumeIsolated { self.isRunning = running }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    nonisolated
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = eventLock.withLock {
            Self.suppresses(type, event: event, state: &state, config: config)
        }
        if shouldSuppress {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// Whether a key event the tap sees is chatter to drop, as `state`
    /// remembers the keys before it.
    nonisolated package static func suppresses(_ type: CGEventType, event: CGEvent, state: inout KeyboardDebounceState,
                                              config: KeyboardDebounceConfig) -> Bool {
        // Keys this app posts (a Quit Protection confirmation, text a snippet
        // retypes) follow a real press on purpose and are not chatter.
        guard type == .keyDown || type == .keyUp, !OwnKeyEvent.isPosted(event) else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let timestamp = EventTimestamp.nanoseconds(of: event)
        let eventKind: KeyboardDebounceState.EventKind = type == .keyDown ? .keyDown : .keyUp
        return state.shouldSuppress(keyCode: keyCode,
                                    isAutoRepeat: isRepeat,
                                    event: eventKind,
                                    timestampNanoseconds: timestamp,
                                    config: config)
    }
}

