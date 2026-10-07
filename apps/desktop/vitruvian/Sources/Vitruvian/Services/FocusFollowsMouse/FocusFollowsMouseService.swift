// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import VitruvianCore
import VitruvianDesign

@MainActor
package final class FocusFollowsMouseService {
    package static let shared = FocusFollowsMouseService()

    /// The pointer movement hover follows: plain moves and drags with any
    /// button, since a drag is the pointer moving too.
    package static let movementEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    private let queryQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.focus-follows-mouse")
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var state = FocusFollowsMouseState()
    private var delayMilliseconds = FocusFollowsMouseSupport.defaultDelayMilliseconds
    private var isRunning = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    package func syncWithPreferences() {
        let wanted = AppFeature.focusFollowsMouse.isAvailable
            && UserDefaults.standard[Preferences.focusFollowsMouseEnabled]
        if SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    package func preferencesDidChange() {
        delayMilliseconds = Self.savedDelay()
    }

    package func stop() {
        resetMovement()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        isRunning = false
    }

    private func start() {
        guard !isRunning else {
            preferencesDidChange()
            return
        }
        delayMilliseconds = Self.savedDelay()
        guard let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: Self.movementEvents,
            handler: { [weak self] event in
                guard let point = event.cgEvent?.location else { return }
                self?.recordMovement(to: point)
            }
        ) else { return }
        self.mouseMonitor = mouseMonitor

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated { self?.resetMovement() }
        })
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                      object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated { self?.resetMovement() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated { self?.resetMovement() }
        })
        isRunning = true
    }

    private func recordMovement(to point: CGPoint) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.recordMovement(to: point)
            }
            return
        }
        guard isRunning else { return }
        // Raising always waits for the pointer to stop, so windows passed on
        // the way are not reshuffled. Without a raise, the user may instead
        // have the delay count time over a window while the pointer moves.
        let waitsForStop = UserDefaults.standard[Preferences.focusFollowsMouseRaise]
            || UserDefaults.standard[Preferences.focusFollowsMouseWaitForStop]
        state.recordMovement(to: point, at: ProcessInfo.processInfo.systemUptime,
                             windowID: waitsForStop ? nil : Self.receivingWindow(at: point))
        guard timer == nil, state.hasPendingEvaluation else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            // Added to the main run loop below, so it fires on the main thread.
            MainActor.assumeIsolated { self?.evaluateIfSettled() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func resetMovement() {
        state.reset()
        timer?.invalidate()
        timer = nil
    }

    /// Nothing held down: no mouse button pressed and no modifier. Asked
    /// again when the window query answers, because the query takes long
    /// enough for a click or a shortcut to begin while it runs, and a pointer
    /// that never moved keeps the answer looking current.
    private var nothingIsHeldDown: Bool {
        Self.nothingHeld(pressedMouseButtons: NSEvent.pressedMouseButtons,
                         modifierFlags: NSEvent.modifierFlags)
    }

    /// No mouse button of any kind is down, and no modifier: a click, a drag
    /// with the middle or a side button, or a shortcut may be beginning.
    package static func nothingHeld(pressedMouseButtons: Int,
                                    modifierFlags: NSEvent.ModifierFlags) -> Bool {
        pressedMouseButtons == 0
            && modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    private func evaluateIfSettled() {
        defer {
            if !state.hasPendingEvaluation {
                timer?.invalidate()
                timer = nil
            }
        }
        guard AXIsProcessTrusted(),
              nothingIsHeldDown,
              let evaluation = state.nextEvaluation(
                  at: ProcessInfo.processInfo.systemUptime,
                  delayMilliseconds: delayMilliseconds),
              !FocusFollowsMouseSupport.leavesAlone(evaluation.point, excludes: {
                  MouseAppExceptions.shared.excludesPointerTarget($0, at: $1)
              }),
              let pointerWindowID = Self.receivingWindow(at: evaluation.point)
        else { return }

        // WindowServer cannot report ignoresMouseEvents. Read our windows on
        // main so full-screen brightness overlays do not block focus everywhere.
        let clickThroughWindowIDs = Set(NSApp.windows.filter(\.ignoresMouseEvents).compactMap {
            CGWindowID(exactly: $0.windowNumber)
        })
        queryQueue.async { [weak self] in
            guard let self else { return }
            let target = FocusFollowsMouseSupport.queryWindow(
                in: WindowServerSupport.onScreenWindowInfo(), at: evaluation.point,
                pointerWindowID: pointerWindowID,
                ownProcessID: ProcessInfo.processInfo.processIdentifier,
                clickThroughWindowIDs: clickThroughWindowIDs
            ) { self.target(at: evaluation.point, processID: $0) }
            guard let target else { return }
            DispatchQueue.main.async { [weak self] in
                let targetAppIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == target.processID
                guard let self, self.isRunning, self.nothingIsHeldDown,
                      self.state.isCurrent(evaluation),
                      Self.receivingWindow(at: evaluation.point) == pointerWindowID,
                      let app = NSRunningApplication(processIdentifier: target.processID),
                      app.activationPolicy == .regular, !app.isTerminated,
                      FocusFollowsMouseSupport.handsToActivator(
                          targetWindowID: target.windowID,
                          focusedWindowID: target.focusedWindowID,
                          targetAppIsFrontmost: targetAppIsFrontmost,
                          isParkedOnHiddenSpace: { SpaceWindowBridge.isParkedOnHiddenSpace($0) })
                else { return }
                guard UserDefaults.standard[Preferences.focusFollowsMouseRaise] else {
                    SpaceWindowBridge.focusWithoutRaise(
                        target.windowID, ownerPID: target.processID,
                        replacing: targetAppIsFrontmost ? target.focusedWindowID : nil)
                    return
                }
                WindowActivator.activate(pid: target.processID,
                                         windowID: target.windowID,
                                         appName: app.localizedName ?? "",
                                         retry: false)
            }
        }
    }

    /// AppKit resolves the window that would receive a click, skipping
    /// input-transparent overlays. Keep this on the main thread; the worker
    /// receives just the ID and never needs a system-wide Accessibility query.
    private static func receivingWindow(at axPoint: CGPoint) -> CGWindowID? {
        guard let primary = NSScreen.screens.first else { return nil }
        let point = CGPoint(x: axPoint.x, y: primary.frame.maxY - axPoint.y)
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard number > 0 else { return nil }
        return CGWindowID(exactly: number)
    }

    nonisolated
    private func target(at point: CGPoint, processID: pid_t) -> Target? {
        // An app-scoped hit test cannot enter our tree if window stacking
        // changes after the ownership lookup. Never fall back to a global query.
        guard let scope = FocusFollowsMouseSupport.hitTestProcess(
            processID, ownProcessID: ProcessInfo.processInfo.processIdentifier) else { return nil }
        let application = AXUIElementCreateApplication(scope)
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &rawElement) == .success,
              let rawElement
        else { return nil }
        AXUIElementSetMessagingTimeout(rawElement, 0.25)
        guard let window = topLevelWindow(from: rawElement) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.25)
        var windowProcessID: pid_t = 0
        guard AXUIElementGetPid(window, &windowProcessID) == .success,
              windowProcessID == processID,
              stringAttribute(window, kAXRoleAttribute as String) == (kAXWindowRole as String),
              let windowID = AXWindowResolver.windowID(for: window)
        else { return nil }

        return Target(processID: processID,
                      windowID: windowID,
                      focusedWindowID: WindowActivator.focusedWindowID(for: processID))
    }

    nonisolated
    private func topLevelWindow(from element: AXUIElement) -> AXUIElement? {
        if stringAttribute(element, kAXRoleAttribute as String) == (kAXWindowRole as String) {
            return element
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    nonisolated
    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func savedDelay() -> Int {
        FocusFollowsMouseSupport.sanitizedDelay(
            UserDefaults.standard[Preferences.focusFollowsMouseDelay])
    }

    private struct Target {
        let processID: pid_t
        let windowID: CGWindowID
        let focusedWindowID: CGWindowID?

        // Spelled out because a memberwise initializer never leaves its module.
        package init(processID: pid_t, windowID: CGWindowID, focusedWindowID: CGWindowID?) {
            self.processID = processID
            self.windowID = windowID
            self.focusedWindowID = focusedWindowID
        }
    }
}
