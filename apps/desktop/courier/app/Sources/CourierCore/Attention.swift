// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// What the Mac knows about whether someone is at it. The app's is `SystemPresence`; tests give one they set.
@MainActor
public protocol PresenceSource: AnyObject {
    /// The screen is locked (or the login window is up).
    var isScreenLocked: Bool { get }
    /// The display is asleep.
    var isDisplayAsleep: Bool { get }
    /// Seconds since the last keyboard, mouse or trackpad input, from anyone using this Mac.
    var secondsSinceLastInput: TimeInterval { get }
    /// Called when the screen locks or unlocks, or the display sleeps or wakes.
    var onChange: (@MainActor () -> Void)? { get set }
}

/// A presence that is whatever it is set to: someone is there unless told otherwise. For tests, previews, and a
/// model made without the system's.
@MainActor
public final class StaticPresence: PresenceSource {
    public var isScreenLocked = false
    public var isDisplayAsleep = false
    public var secondsSinceLastInput: TimeInterval = 0
    public var onChange: (@MainActor () -> Void)?

    public init() {}
}

/// Whether the person is looking at the open chat. That is: the window is key, the screen is unlocked, the display
/// is awake, and someone touched the keyboard, mouse or trackpad in the last three minutes. A window left in front
/// of a locked, sleeping or empty desk is not being read.
///
/// Opening a chat marks it read, and a message in the open chat makes no notification, only while this is true.
/// When it becomes true again (the person comes back, unlocks, wakes the display, or brings the window forward),
/// the `onReturn` hooks run, so a chat whose new messages waited for them is marked read then.
///
/// The idle time is not announced by the system, so while the window is key it is checked every `pollInterval`.
@MainActor
public final class Attention {
    /// Longer than this without any input, and nobody is looking.
    public static let idleLimit: TimeInterval = 180

    public private(set) var windowIsKey = false
    private let source: PresenceSource
    private let pollInterval: TimeInterval?
    private let isAppLocked: @MainActor () -> Bool
    private var hooks: [@MainActor () -> Void] = []
    private var wasLooking = false
    private var poll: Task<Void, Never>?
    private var lockCancellables: [AnyCancellable] = []

    /// - Parameter pollInterval: how often the idle time is checked while the window is key; nil never (tests call
    ///   `reevaluate`).
    public init(
        source: PresenceSource,
        pollInterval: TimeInterval? = 5,
        isAppLocked: @escaping @MainActor () -> Bool = { AppLockGate.shared.isLocked }
    ) {
        self.source = source
        self.pollInterval = pollInterval
        self.isAppLocked = isAppLocked
        source.onChange = { [weak self] in self?.reevaluate() }
        lockCancellables.append(
            NotificationCenter.default.publisher(for: SystemLifecycleModel.didLockNotification)
                .sink { [weak self] _ in
                    self?.reevaluate()
                }
        )
        lockCancellables.append(
            NotificationCenter.default.publisher(for: SystemLifecycleModel.didUnlockNotification)
                .sink { [weak self] _ in
                    self?.reevaluate()
                }
        )
    }

    /// Whether the person is looking now. Read fresh each time: the idle time moves on its own.
    public var isLooking: Bool {
        windowIsKey
            && !isAppLocked()
            && !AppLockGate.shared.isLocked
            && !source.isScreenLocked
            && !source.isDisplayAsleep
            && source.secondsSinceLastInput < Self.idleLimit
    }

    /// Runs `hook` each time the person starts looking again.
    public func onReturn(_ hook: @escaping @MainActor () -> Void) {
        hooks.append(hook)
    }

    /// The conversation's window became key or stopped being key. The conversation view also says false when it
    /// goes away (the window closed, ⌘W), since a closed window is never told it is no longer key.
    public func setWindowKey(_ isKey: Bool) {
        windowIsKey = isKey
        if isKey { startPolling() } else { stopPolling() }
        reevaluate()
    }

    /// Looks again, and runs the hooks if the person has just come back.
    public func reevaluate() {
        let now = isLooking
        defer { wasLooking = now }
        guard now, !wasLooking else { return }
        for hook in hooks { hook() }
    }

    private func startPolling() {
        guard poll == nil, let interval = pollInterval else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.reevaluate()
            }
        }
    }

    private func stopPolling() {
        poll?.cancel()
        poll = nil
    }
}
