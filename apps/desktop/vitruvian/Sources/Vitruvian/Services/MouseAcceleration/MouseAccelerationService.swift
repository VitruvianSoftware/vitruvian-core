// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import HIDEventSystem
import VitruvianCore
import VitruvianDesign

/// Applies macOS's per-device linear pointer mode to ordinary mouse devices.
/// Trackpads are deliberately excluded.
@MainActor
package final class MouseAccelerationService {
    package static let shared = MouseAccelerationService()

    private let defaults = UserDefaults.standard
    private var client: IOHIDEventSystemClient?
    private var hidManager: IOHIDManager?
    private var reapplySchedule = MouseAccelerationReapplySchedule()
    private var reapplyWork: DispatchWorkItem?
    private var recoveryGuard: MouseAccelerationGuard.Handle?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var sessionIsActive = false
    private var systemIsAwake = true

    private init() {}

    package static func recoverPendingAtLaunch() {
        guard MouseAccelerationRecovery.hasPendingEntries() else { return }
        _ = shared.pauseAndRestore()
    }

    package func syncWithPreferences() {
        guard featureWanted else {
            stop()
            return
        }
        installLifecycleObservers()
        startIfAllowed()
    }

    /// Restores every value owned by this feature before its process goes away.
    @discardableResult
    package func stop() -> Bool {
        removeLifecycleObservers()
        return pauseAndRestore()
    }

    private var featureWanted: Bool {
        AppFeature.mouseAcceleration.isAvailable
            && defaults.bool(forKey: DefaultsKey.mouseAccelerationDisabled)
    }

    private func startIfAllowed() {
        guard featureWanted, sessionIsActive, systemIsAwake else {
            pauseAndRestore()
            return
        }
        start()
    }

    private func start() {
        if client != nil {
            applyLinearMode()
            return
        }
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        _ = MouseAccelerationRecovery.restorePending(using: client)
        self.client = client
        startDeviceObservation()
        applyLinearMode()
        scheduleDeviceReapplication()
    }

    @discardableResult
    private func pauseAndRestore() -> Bool {
        stopDeviceObservation()
        if let client {
            _ = MouseAccelerationRecovery.restorePending(using: client)
        } else if MouseAccelerationRecovery.hasPendingEntries() {
            _ = MouseAccelerationRecovery.restorePending()
        }
        client = nil
        if let recoveryGuard {
            _ = recoveryGuard.stop()
            self.recoveryGuard = nil
        }
        let hasPendingRecovery = MouseAccelerationRecovery.hasPendingEntries()
        if hasPendingRecovery {
            recoveryGuard = MouseAccelerationGuard.start()
        }
        return !hasPendingRecovery
    }

    private func applyLinearMode() {
        guard let client,
              let services = MouseAccelerationRecovery.services(using: client),
              var journal = MouseAccelerationRecovery.journalForMutation() else {
            return
        }

        for service in services where MouseAccelerationRecovery.isMouse(service) {
            guard let id = MouseAccelerationRecovery.registryID(of: service),
                  let identity = MouseAccelerationRecovery.identity(of: service) else { continue }

            let entry: MouseAccelerationRecoveryEntry
            if let existing = journal.entry(registryID: id, identity: identity) {
                entry = existing
            } else {
                let unresolvedIdentity = identity.canMatchAcrossRegistryIDs
                    && journal.entries.contains { $0.identity.matches(identity) }
                guard !journal.entries.contains(where: { $0.registryID == id }),
                      !unresolvedIdentity,
                      ensureRecoveryGuard(),
                      let captured = MouseAccelerationRecovery.captureEntry(
                          for: service,
                          registryID: id,
                          identity: identity
                      ),
                      MouseAccelerationRecovery.record(captured, in: &journal) else {
                    continue
                }
                entry = captured
            }

            guard ensureRecoveryGuard() else {
                pauseAndRestore()
                return
            }
            guard MouseAccelerationRecovery.applyTarget(for: entry, to: service) else {
                if MouseAccelerationRecovery.restore(entry, on: service) {
                    _ = MouseAccelerationRecovery.remove(registryID: id, from: &journal)
                }
                continue
            }
        }

        if journal.entries.isEmpty, let recoveryGuard {
            _ = recoveryGuard.stop()
            self.recoveryGuard = nil
        }
    }

    private func ensureRecoveryGuard() -> Bool {
        if recoveryGuard != nil { return true }
        recoveryGuard = MouseAccelerationGuard.start()
        return recoveryGuard != nil
    }

    // MARK: - Device lifecycle

    // The manager is scheduled on the main run loop, so this runs on the main thread.
    nonisolated private static let deviceChanged: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let service = Unmanaged<MouseAccelerationService>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated { service.scheduleDeviceReapplication() }
    }

    private func scheduleDeviceReapplication() {
        guard client != nil, featureWanted, sessionIsActive, systemIsAwake else { return }
        reapplyWork?.cancel()
        scheduleDeviceReapplication(for: reapplySchedule.restart())
    }

    private func scheduleDeviceReapplication(for token: UUID) {
        guard let delay = reapplySchedule.nextDelay(for: token) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.reapplySchedule.isCurrent(token) else { return }
            self.reapplyWork = nil
            guard self.client != nil, self.featureWanted,
                  self.sessionIsActive, self.systemIsAwake else { return }
            // Physical-device callbacks can precede the event-system service, and
            // its initial settings can arrive later still. Read a fresh service list.
            let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
            self.client = client
            _ = MouseAccelerationRecovery.restorePending(using: client,
                                                          preservingConnectedEntries: true)
            self.applyLinearMode()
            self.scheduleDeviceReapplication(for: token)
        }
        reapplyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startDeviceObservation() {
        guard hidManager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceChanged, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceChanged, context)
        IOHIDManagerScheduleWithRunLoop(manager,
                                        CFRunLoopGetMain(),
                                        CFRunLoopMode.commonModes.rawValue)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager,
                                              CFRunLoopGetMain(),
                                              CFRunLoopMode.commonModes.rawValue)
            return
        }
        hidManager = manager
    }

    private func stopDeviceObservation() {
        reapplyWork?.cancel()
        reapplyWork = nil
        reapplySchedule.cancel()
        guard let manager = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager,
                                          CFRunLoopGetMain(),
                                          CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
    }

    // MARK: - Session and sleep lifecycle

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        lifecycleObservers = [
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    self?.sessionIsActive = false
                    self?.pauseAndRestore()
                }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    self?.sessionIsActive = true
                    self?.startIfAllowed()
                }
            },
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    self?.systemIsAwake = false
                    self?.pauseAndRestore()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated {
                    self?.systemIsAwake = true
                    self?.startIfAllowed()
                }
            },
        ]
        sessionIsActive = Self.sessionIsOnScreen(CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    private func removeLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in lifecycleObservers { center.removeObserver(observer) }
        lifecycleObservers = []
    }

    /// Whether `session` is the one on screen, read the way `SessionActivity`
    /// reads it at launch: a session that cannot be read counts as on screen.
    /// A wrong "off" would never be corrected, because a session that is
    /// already active gets no become-active notification.
    package static func sessionIsOnScreen(_ session: [String: Any]?) -> Bool {
        SessionActivitySupport.isOnConsole(session)
    }
}
