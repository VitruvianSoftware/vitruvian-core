// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI
import VitruvianCore
import VitruvianDesign

/// "Cleaning mode" temporarily locks the keyboard so the user can wipe it down
/// without typing gibberish, then restores it on a deliberate gesture. The lock
/// is a HID-level event tap that swallows key events before the system handles
/// them, including keyboard system keys such as brightness, media and volume.
/// The very same tap watches for the unlock gesture, so there is always a way
/// back.
///
/// Two deliberate escapes guarantee no one is ever stranded:
///   1. press Escape five times in a row,
///   2. click Unlock on the overlay (pointer movement and clicks stay available).
///
/// Requires Accessibility, like the app's other event taps. If it is missing the
/// tap can't be created, so we never lock the keyboard with no way to unlock it.
@MainActor
package final class CleaningModeManager: ObservableObject {
    package static let shared = CleaningModeManager(environment: .live)

    private static let systemDefinedEventType = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
    private static let gestureEventType = CGEventType(rawValue: UInt32(NSEvent.EventType.gesture.rawValue))!
    private static let escapeKeyCode: Int64 = 53
    private static let eventMask: CGEventMask = [
        CGEventType.keyDown,
        .keyUp,
        .flagsChanged,
        .scrollWheel,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        systemDefinedEventType,
        gestureEventType,
    ].reduce(CGEventMask(0)) { mask, type in
        mask | (CGEventMask(1) << type.rawValue)
    }

    /// The installed cleaning tap, as the manager drives it.
    package struct Tap {
        /// Switches the tap back on after the window server switched it off.
        package var rearm: @MainActor () -> Void
        /// Switches the tap off, takes it off the run loop and invalidates its
        /// port: a disabled tap would still own its place in the chain.
        package var remove: @MainActor () -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(rearm: @escaping @MainActor () -> Void, remove: @escaping @MainActor () -> Void) {
            self.rearm = rearm
            self.remove = remove
        }
    }

    /// What Cleaning Mode reaches outside itself: the Accessibility grant, the
    /// tap, the features it suspends, the cover over the screens, the session
    /// and the main queue. `live` is the Mac; a test hands in doubles and feeds
    /// the tap's events to `handle(_:)`, so no keyboard is locked.
    package struct Environment {
        /// The grant checked before anything locks.
        package var hasAccessibility: @MainActor () -> Bool
        /// Explains a missing grant and offers its settings.
        package var promptForAccessibility: @MainActor () -> Void
        /// Installs the tap that feeds `manager`; nil when the system refuses it.
        package var installTap: @MainActor (_ manager: CleaningModeManager) -> Tap?
        /// Suspends the features whose own taps could run ahead of the lock.
        package var suspendFeatures: @MainActor () -> Void
        /// Brings them back, each from its own availability and preferences.
        package var resumeFeatures: @MainActor () -> Void
        /// Covers every screen, following screen changes until `hideCover`.
        package var showCover: @MainActor () -> Void
        package var hideCover: @MainActor () -> Void
        package var session: SessionActivity
        /// Whether this process is trusted for Accessibility right now.
        package var isProcessTrusted: @MainActor () -> Bool
        /// The monotonic clock the unlock presses are timed on.
        package var now: @MainActor () -> TimeInterval
        /// Runs work on a later turn of the main queue.
        package var main: @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void
        /// Runs work on the main queue after a delay, unless cancelled first.
        package var schedule: @MainActor (TimeInterval, DispatchWorkItem) -> Void

        // Spelled out because a memberwise initializer never leaves its module.
        package init(hasAccessibility: @escaping @MainActor () -> Bool,
                     promptForAccessibility: @escaping @MainActor () -> Void,
                     installTap: @escaping @MainActor (_ manager: CleaningModeManager) -> Tap?,
                     suspendFeatures: @escaping @MainActor () -> Void,
                     resumeFeatures: @escaping @MainActor () -> Void,
                     showCover: @escaping @MainActor () -> Void,
                     hideCover: @escaping @MainActor () -> Void,
                     session: SessionActivity,
                     isProcessTrusted: @escaping @MainActor () -> Bool,
                     now: @escaping @MainActor () -> TimeInterval,
                     main: @escaping @MainActor (@escaping @MainActor @Sendable () -> Void) -> Void,
                     schedule: @escaping @MainActor (TimeInterval, DispatchWorkItem) -> Void) {
            self.hasAccessibility = hasAccessibility
            self.promptForAccessibility = promptForAccessibility
            self.installTap = installTap
            self.suspendFeatures = suspendFeatures
            self.resumeFeatures = resumeFeatures
            self.showCover = showCover
            self.hideCover = hideCover
            self.session = session
            self.isProcessTrusted = isProcessTrusted
            self.now = now
            self.main = main
            self.schedule = schedule
        }

        @MainActor package static var live: Environment {
            let cover = CleaningCover()
            return Environment(
                hasAccessibility: { Permissions.shared.accessibility },
                promptForAccessibility: { CleaningModeManager.promptForAccessibility() },
                installTap: { CleaningModeManager.installTap(for: $0) },
                suspendFeatures: {
                    // Debounce must not filter while the lock is up: its tap can run ahead
                    // of ours (head-insert order depends on creation order) and would eat
                    // the repeated same-key presses the unlock gesture counts on.
                    KeyboardDebounceService.shared.suspend()
                    MouseClickDebounceService.shared.suspend()
                    // Wiping the trackpad is nothing but stray three-finger contacts;
                    // middle-click emulation must not fire from them.
                    MiddleClickService.shared.suspend()
                    MouseNavigationService.shared.suspend()
                    // A stray side-button press while wiping the mouse must not type a
                    // key combination into the frontmost app (the synthesized keys are
                    // posted below this lock's keyboard tap) nor open the wheel over
                    // the cleaning overlay.
                    MouseButtonShortcutService.shared.suspend()
                    RadialMenuService.shared.suspend()
                },
                resumeFeatures: {
                    // Each owner reads its current availability, preference and permission,
                    // so a feature changed while Cleaning Mode was active stays changed.
                    KeyboardDebounceService.shared.syncWithPreferences()
                    MouseClickDebounceService.shared.syncWithPreferences()
                    MiddleClickService.shared.syncWithPreferences()
                    MouseNavigationService.shared.syncWithPreferences()
                    MouseButtonShortcutService.shared.syncWithPreferences()
                    RadialMenuService.shared.syncWithPreferences()
                },
                showCover: { cover.show() },
                hideCover: { cover.hide() },
                session: .shared,
                isProcessTrusted: { AXIsProcessTrusted() },
                now: { ProcessInfo.processInfo.systemUptime },
                main: { work in DispatchQueue.main.async { work() } },
                schedule: { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) })
        }
    }

    @Published package private(set) var isActive = false
    /// Consecutive Escape presses so far (0...unlockThreshold). The
    /// overlay shows this as progress.
    @Published package private(set) var unlockProgress = 0

    /// Deliberate Escape presses needed to unlock. Other keys reset the count so
    /// wiping the keyboard cannot complete the gesture accidentally.
    package let unlockThreshold = 5

    private let environment: Environment
    private var tap: Tap?
    private var shouldRestoreSuspendedFeaturesOnSessionReturn = false
    // Mouse events still pass through Cleaning Mode. We only remember the
    // down/up lifecycle so teardown never cuts a click in half.
    private var mouseReleaseGate = CleaningMouseReleaseGate()
    /// Ends a user unlock's wait for a release this tap never sees.
    private var releaseDeadline: DispatchWorkItem?

    /// The unlock-gesture state machine (pure, unit-tested separately).
    /// The 6s press window forgives hesitant, deliberate presses — at 2s a user
    /// pressing Escape slower than once per two seconds could never unlock
    /// (progress restarted at 1 on every press). The window's one remaining job
    /// is rejecting five isolated Esc-only contacts spread across a long wipe:
    /// every other key resets the count — modifiers included, they reach the
    /// counter as flags-changed events — and auto-repeat never counts, but a
    /// cloth can strike Escape alone. Widening to 6s weakens that guard on
    /// purpose — a gesture a deliberate user cannot complete protects nothing.
    private lazy var unlock = CleaningUnlockCounter(requiredKeyCode: Self.escapeKeyCode,
                                                    threshold: unlockThreshold,
                                                    pressWindow: CleaningUnlockCounter.shippedPressWindow)

    package init(environment: Environment) {
        self.environment = environment
        // A switched-away login session cannot keep a filter tap in the input
        // chain. Cleaning is a temporary local state, so leaving the session
        // ends it; suspended features resume only after this session returns.
        environment.session.onChange { [weak self] active in
            guard let self else { return }
            switch CleaningSessionSupport.sessionChanged(
                isActive: active, locked: self.isActive,
                featuresAwaitSession: self.shouldRestoreSuspendedFeaturesOnSessionReturn) {
            case .keep:
                break
            case .endLockKeepingFeaturesSuspended:
                self.deactivate(restoreSuspendedFeatures: false)
            case .resumeSuspendedFeatures:
                self.shouldRestoreSuspendedFeaturesOnSessionReturn = false
                self.resumeSuspendedFeatures()
            }
        }
    }

    package func toggle() { isActive ? deactivate() : activate() }

    /// Starts the lock. No-op (and guides the user) when Accessibility is missing,
    /// because without the tap there would be no way to unlock the keyboard.
    package func activate() {
        guard !isActive else { return }
        // Check Accessibility explicitly (same gate the other event taps use) so a
        // missing grant is reported clearly, rather than inferred from a nil tap.
        guard environment.hasAccessibility() else {
            environment.promptForAccessibility()
            return
        }
        mouseReleaseGate.reset()
        guard let tap = environment.installTap(self) else { return }
        self.tap = tap
        environment.suspendFeatures()
        unlock.reset()
        unlockProgress = 0
        isActive = true
        environment.showCover()
    }

    package func deactivate() {
        guard isActive else { return }
        // If a click began while the overlay was up, keep the overlay and tap
        // alive until its real mouse-up passes through. Never manufacture a
        // release: the physical event is the only event that completes the click.
        armReleaseDeadline()
        guard mouseReleaseGate.requestDeactivation() else { return }
        scheduleUserDeactivation()
    }

    /// Every unlock path waits on the gate, and the overlay can cover the menu
    /// bar, so the wait is bounded. Nothing is posted; it only stops waiting.
    private func armReleaseDeadline() {
        guard releaseDeadline == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.releaseDeadline = nil
            guard self.isActive, self.mouseReleaseGate.releaseWaitExpired() else { return }
            self.scheduleUserDeactivation()
        }
        releaseDeadline = work
        environment.schedule(CleaningMouseReleaseGate.releaseWaitLimit, work)
    }

    /// Permission teardown must remove the tap before Accessibility is reset.
    package func deactivateForSystemTeardown() {
        deactivate(restoreSuspendedFeatures: true)
    }

    private func deactivate(restoreSuspendedFeatures: Bool) {
        guard isActive else { return }
        // Session/tap failure paths cannot wait for another input event. They
        // retain the existing fail-open behaviour and tear down immediately.
        finishDeactivation(restoreSuspendedFeatures: restoreSuspendedFeatures)
    }

    private func scheduleUserDeactivation() {
        // Even when no button is currently held, leave the AppKit control action
        // before unmapping its non-activating panel. A new press may arrive before
        // this block runs, so keep the request pending until teardown completes.
        environment.main { [weak self] in
            guard let self, self.isActive, self.mouseReleaseGate.deactivationPending,
                  self.mouseReleaseGate.pressedButtons.isEmpty else { return }
            self.finishDeactivation(restoreSuspendedFeatures: true)
        }
    }

    private func finishDeactivation(restoreSuspendedFeatures: Bool) {
        guard isActive else { return }
        releaseDeadline?.cancel()
        releaseDeadline = nil
        mouseReleaseGate.reset()
        tap?.remove()
        tap = nil
        environment.hideCover()
        unlock.reset()
        unlockProgress = 0
        isActive = false
        guard restoreSuspendedFeatures else {
            shouldRestoreSuspendedFeaturesOnSessionReturn = true
            return
        }
        shouldRestoreSuspendedFeaturesOnSessionReturn = false
        resumeSuspendedFeatures()
    }

    private func resumeSuspendedFeatures() {
        environment.resumeFeatures()
    }

    // MARK: - Event tap

    /// The live tap, at the head of the HID stream and on the main run loop.
    private static func installTap(for manager: CleaningModeManager) -> Tap? {
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<CleaningModeManager>.fromOpaque(userInfo).takeUnretainedValue()
                // The tap's source is on the main run loop (below).
                return MainActor.assumeIsolated { manager.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(manager).toOpaque()
        ) else {
            return nil
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return Tap(rearm: { CGEvent.tapEnable(tap: tap, enable: true) },
                   remove: {
                       CGEvent.tapEnable(tap: tap, enable: false)
                       CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                       CFMachPortInvalidate(tap)
                   })
    }

    /// The tap callback. Its run-loop source lives on the main run loop, so this
    /// runs on the main thread and can touch published state and AppKit directly.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let tapEvent = CleaningTapSupport.classify(type: type,
                                                   field: { event.getIntegerValueField($0) },
                                                   systemKey: { Self.systemKeyEvent(from: event) })
        return handle(tapEvent) ? Unmanaged.passUnretained(event) : nil
    }

    /// What the lock does with one event from its tap: true lets it through.
    /// Keys, scrolling and trackpad gestures are swallowed while the lock is
    /// on, and the keys among them feed the unlock gesture. Mouse buttons pass,
    /// so the Unlock button stays clickable, and only their boundaries are
    /// watched. The one other event that passes is a disabled tap's notice
    /// when the lock ends with it, where holding on would strand the user.
    package func handle(_ event: CleaningTapEvent) -> Bool {
        switch event {
        case .tapDisabled:
            // The system disables taps that stall or when the session locks; re-arm so
            // the keyboard stays locked instead of silently coming back.
            let step = CleaningSessionSupport.tapDisabled(sessionIsActive: environment.session.isActive,
                                                          accessibilityGranted: environment.isProcessTrusted(),
                                                          hasTap: tap != nil)
            if case .endLock(let restoreSuspendedFeatures) = step {
                environment.main { [weak self] in
                    self?.deactivate(restoreSuspendedFeatures: restoreSuspendedFeatures)
                }
                return true
            }
            // A disabled tap creates an observation gap: any tracked mouseDown
            // may already have received its real mouseUp while we were blind.
            // Invalidate that incomplete sequence so no later unlock can wait
            // forever for a release that already happened. If the user had
            // already requested deactivation, fail open after the callback.
            let shouldFinishUserDeactivation = mouseReleaseGate.deactivationPending
            mouseReleaseGate.invalidateTrackedPresses()
            tap?.rearm()
            if shouldFinishUserDeactivation {
                scheduleUserDeactivation()
            }
            return false

        case .mouseButton(let button, isDown: let isDown):
            // Mouse clicks are never locked. Observe only their boundaries so a
            // user-requested teardown can wait for a matching real release.
            if isDown {
                mouseReleaseGate.buttonDown(button)
            } else if mouseReleaseGate.buttonUp(button) {
                // The callback is running on this tap's run loop. Removing the tap
                // here would invalidate it from its own callback stack, so finish on
                // the next main-loop turn after the real release has propagated.
                scheduleUserDeactivation()
            }
            return true

        case .unlockKey(code: let code, isRepeat: let isRepeat):
            // Auto-repeat (holding a key) is ignored, so only distinct,
            // deliberate taps of the same key count.
            registerUnlockKeyDown(code: code, isRepeat: isRepeat)
            return false

        case .other:
            return false
        }
    }

    private static func systemKeyEvent(from event: CGEvent) -> CleaningSystemKeyEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        return CleaningSystemKeyEvent.decode(subtype: Int(nsEvent.subtype.rawValue),
                                             data1: nsEvent.data1)
    }

    private func registerUnlockKeyDown(code: Int64, isRepeat: Bool) {
        let unlocked = unlock.registerKeyDown(code: code,
                                              time: environment.now(),
                                              isRepeat: isRepeat)
        unlockProgress = unlock.progress
        if unlocked {
            // deactivate() only records the request here; actual teardown is
            // scheduled after this tap callback has returned.
            deactivate()
        }
    }

    // MARK: - Overlay

    /// One display's cover, before it is configured: a floating overlay, which
    /// window managers do not list.
    package static func makePanel(frame: NSRect) -> NSPanel {
        OverlayPanel(contentRect: frame,
                     styleMask: [.borderless, .nonactivatingPanel],
                     backing: .buffered, defer: false)
    }

    private static func promptForAccessibility() {
        let strings = L10n.shared.s
        let alert = NSAlert()
        alert.messageText = strings.cleaningNeedsAxTitle
        alert.informativeText = strings.cleaningNeedsAxBody
        alert.addButton(withTitle: strings.permissionOpenSettings)
        alert.addButton(withTitle: strings.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.shared.requestAccessibility()
            Permissions.shared.openAccessibilitySettings()
        }
    }
}

/// The live cover over every screen while the lock is up: one overlay per
/// display carrying the Unlock button, rebuilt as the screens change.
@MainActor
private final class CleaningCover {
    private var overlays: [NSPanel] = []
    private var screenObserver: NSObjectProtocol?
    private var isShown = false

    func show() {
        isShown = true
        installScreenObserver()
        showOverlays()
    }

    func hide() {
        isShown = false
        removeScreenObserver()
        hideOverlays()
    }

    private func showOverlays() {
        let frames = NSScreen.screens.map(\.frame)
        let targetFrames = frames.isEmpty
            ? [NSRect(x: 0, y: 0, width: 800, height: 600)]
            : frames
        // Screen notifications can arrive in bursts even when the frames stay
        // unchanged. Reuse those panels so the overlay never flashes or drops a click.
        var reusable = overlays
        overlays = targetFrames.map { frame in
            if let index = reusable.firstIndex(where: { $0.frame == frame }) {
                return reusable.remove(at: index)
            }
            return makeOverlay(frame: frame)
        }
        reusable.forEach { $0.orderOut(nil) }
    }

    private func makeOverlay(frame: NSRect) -> NSPanel {
        let panel = CleaningModeManager.makePanel(frame: frame)
        panel.isFloatingPanel = true
        // Above the menu bar and full-screen apps — the shielding level macOS uses
        // for its own lock-style windows.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // acceptsFirstMouse so the Unlock button fires on the very first click even
        // though the panel never becomes key or activates the app — otherwise that
        // click would just be absorbed as the window-activating click.
        let host = OverlayHostingView(rootView: ServiceViews.factory.cleaningOverlay())
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        return panel
    }

    private func hideOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = []
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue.
            MainActor.assumeIsolated {
                guard self?.isShown == true else { return }
                self?.showOverlays()
            }
        }
    }

    private func removeScreenObserver() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
    }

    /// Hosting view that accepts the first click into the (non-key, non-activating)
    /// overlay panel, so the Unlock button works without a throwaway activating click.
    private final class OverlayHostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
