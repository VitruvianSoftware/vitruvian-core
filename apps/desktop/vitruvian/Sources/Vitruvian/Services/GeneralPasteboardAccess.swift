// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

/// Serializes every access the app makes to the general pasteboard.
/// NSPasteboard keeps a mutable type cache on its shared instance, so reading
/// it from two queues at once can race inside AppKit, and a read has no time
/// limit: content can be promised and rendered only on demand, so an app that
/// stops answering leaves the reader hanging. Hence one serial lane, off the
/// main thread, and no way to wait for it — a caller waiting on the main
/// thread is a frozen app (issue #887).
///
/// It holds only constants: the lane, the clock the lane reads, and the
/// deadline scheduler its callers run. So it is `@unchecked Sendable`.
package final class GeneralPasteboardAccess: @unchecked Sendable {
    package static let shared = GeneralPasteboardAccess()

    package typealias DeadlineScheduler = (_ delay: TimeInterval,
                                   _ action: @escaping () -> Void) -> (() -> Void)

    private let queue: DispatchQueue
    /// Read on the lane, so `@Sendable`.
    private let now: @Sendable () -> TimeInterval
    private let scheduleDeadline: DeadlineScheduler

    package init(label: String = "Vitruvian.Pasteboard.general",
         now: @escaping @Sendable () -> TimeInterval = {
             TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
         },
         scheduleDeadline: DeadlineScheduler? = nil) {
        queue = DispatchQueue(label: label, qos: .utility)
        self.now = now
        self.scheduleDeadline = scheduleDeadline ?? { delay, action in
            let item = DispatchWorkItem(block: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return { item.cancel() }
        }
    }

    /// `work` runs on the lane, off the main thread, so it is `@Sendable`:
    /// a closure from main-actor code then runs as plain code there, instead
    /// of carrying a main-actor check that the lane would fail.
    package func async(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }

    /// Runs `work` on the lane and hands its result to `completion` on the
    /// main queue. The caller returns immediately: a wedged lane delays the
    /// completion, it never blocks whoever asked.
    package func async<T: Sendable>(_ work: @escaping @Sendable () -> T,
                                    then completion: @escaping @MainActor (T) -> Void) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A deadline limits result delivery and prevents expired queued work
    /// from starting. It cannot interrupt an AppKit call already in progress.
    /// `didFinish` runs on main only when the actual queue operation ends,
    /// even if `completion` already received nil at the deadline. Callers use
    /// it to keep admission bounded while a provider is unresponsive.
    package func async<T: Sendable>(timeout: TimeInterval,
                   _ work: @escaping @Sendable (_ isExpired: () -> Bool) -> T?,
                   then completion: @escaping @MainActor (T?) -> Void,
                   didFinish: @escaping @MainActor (T?) -> Void = { _ in }) {
        let deadline = now() + timeout
        let delivery = PasteboardResultDelivery(completion: completion, didFinish: didFinish)
        delivery.cancelDeadline = scheduleDeadline(timeout) { delivery.complete(nil) }
        let isExpired: @Sendable () -> Bool = { self.now() >= deadline }
        queue.async {
            let value = isExpired() ? nil : work(isExpired)
            DispatchQueue.main.async {
                delivery.finish(value, expired: isExpired())
            }
        }
    }
}

/// Both deadline and queue completion deliver on main. Clearing the callback
/// before invoking it also makes reentrant callers safe. Made, scheduled and
/// answered on the main thread, which `complete` checks; the lane only carries
/// it back there. So it is `@unchecked Sendable`.
private final class PasteboardResultDelivery<Value: Sendable>: @unchecked Sendable {
    private var completion: (@MainActor (Value?) -> Void)?
    private let didFinish: @MainActor (Value?) -> Void
    /// Set right after the deadline is scheduled, before the lane can answer.
    var cancelDeadline: (() -> Void)?

    init(completion: @escaping @MainActor (Value?) -> Void,
         didFinish: @escaping @MainActor (Value?) -> Void) {
        self.completion = completion
        self.didFinish = didFinish
    }

    /// The lane's own answer: the operation really ended, whether or not the
    /// deadline already answered for it.
    func finish(_ value: Value?, expired: Bool) {
        precondition(Thread.isMainThread)
        cancelDeadline?()
        // Checked just above.
        MainActor.assumeIsolated { didFinish(value) }
        complete(expired ? nil : value)
    }

    func complete(_ value: Value?) {
        precondition(Thread.isMainThread)
        let callback = completion
        completion = nil
        // Checked just above.
        MainActor.assumeIsolated { callback?(value) }
    }
}
