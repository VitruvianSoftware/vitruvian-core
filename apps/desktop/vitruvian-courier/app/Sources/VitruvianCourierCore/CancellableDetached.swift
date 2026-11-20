// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

private struct DetachedBox<V>: @unchecked Sendable { let value: V? }

/// Runs `work` on a background thread and gives its result back, the way `Task.detached(...).value` does, except that
/// cancelling the caller cancels the work too (a detached task is not cancelled with its parent): a row that scrolled
/// away or was reused stops its decode, and `work` can check `Task.isCancelled` to stop early. Nil when cancelled
/// before it started.
public func runDetachedCancellable<T>(
    priority: TaskPriority = .utility,
    _ work: @escaping @Sendable () -> T?
) async -> T? {
    let task = Task.detached(priority: priority) { () -> DetachedBox<T> in
        guard !Task.isCancelled else { return DetachedBox(value: nil) }
        return DetachedBox(value: work())
    }
    let box = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    return box.value
}
