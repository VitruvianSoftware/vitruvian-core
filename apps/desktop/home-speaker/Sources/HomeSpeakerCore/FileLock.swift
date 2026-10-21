// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

/// An exclusive BSD `flock` on a lock file, shared by every store several
/// processes write: `SecretStore` (the app, `--sign-in`, the Vitruvian tool)
/// and `BroadcastHistory` (the app, `--say`, `--announce`, the Stop hook).
///
/// The lock is taken on a file of its own beside the data file, so the
/// atomic replace (rename) of the data file never swaps the locked inode out
/// from under a waiting writer.
///
/// Re-entrancy: a `flock` belongs to an open file description, and each call
/// opens the lock file afresh, so a second call in the same process waits on
/// the first exactly as another process would. That makes two threads (or
/// two store objects) on the same file contend correctly, and makes nesting a
/// deadlock: never call this from inside `body` on the same `lockURL`.
public enum FileLock {
    /// Runs `body` holding an exclusive lock on `lockURL`, creating its
    /// folder (with `directoryPermissions` when given, and only when the
    /// folder is new) and the lock file (0600) if need be. Blocks while
    /// another holder has it.
    public static func withExclusiveLock<T>(
        at lockURL: URL,
        directoryPermissions: Int? = nil,
        _ body: () throws -> T
    ) throws -> T {
        let attributes: [FileAttributeKey: Any]? = directoryPermissions.map { [.posixPermissions: $0] }
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: attributes)
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

/// An async-safe cross-process and in-process FIFO speech lock so only one
/// announcement plays at a time across the app, the extension (`bin/tool`),
/// `--say`, `--announce`, and the end-of-turn hooks.
///
/// Acquires an exclusive BSD `flock` (`LOCK_EX`) on a per-file serial
/// `DispatchQueue` so waiting for an earlier announcement to finish never
/// blocks a thread in Swift's cooperative thread pool, then holds the file
/// descriptor across the `async` announcement body and unlocks/closes it
/// when the announcement finishes (or automatically if the process exits).
public enum SpeechLock {
    /// Shared across both HomeSpeaker doors and all agent hooks on this Mac.
    public static let defaultURL = URL(fileURLWithPath: "/tmp/homespeaker_speech.lock")

    /// Maximum extra timeout allowance granted to a CLI process that spent
    /// time waiting in the speech queue behind earlier announcements.
    public static let maxQueueWaitSeconds: TimeInterval = 180

    /// Maximum post-broadcast speaker cooldown honored from a lock file.
    public static let maxCooldownSeconds: TimeInterval = 60

    /// A non-blocking lock lease acquired by `tryAcquire(at:)`.
    public final class Lease: @unchecked Sendable {
        private let lock = NSLock()
        private var fd: Int32

        fileprivate init(fd: Int32) {
            self.fd = fd
        }

        public func release(cooldownUntil: Date? = nil) {
            let current = lock.withLock { () -> Int32 in
                let value = fd
                fd = -1
                return value
            }
            SpeechLock.release(current, cooldownUntil: cooldownUntil)
        }

        deinit {
            release()
        }
    }

    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var queues: [String: DispatchQueue] = [:]
    nonisolated(unsafe) private static var completedWaitSeconds: TimeInterval = 0
    nonisolated(unsafe) private static var activeWaitStarts: [UUID: Date] = [:]

    /// How many seconds this process has spent waiting to acquire `SpeechLock`
    /// (including any wait currently in flight), capped at `maxQueueWaitSeconds`.
    public static func queueWaitSeconds(now: Date = Date()) -> TimeInterval {
        stateLock.withLock {
            let active = activeWaitStarts.values.reduce(0.0) { sum, start in
                sum + max(0, now.timeIntervalSince(start))
            }
            return min(maxQueueWaitSeconds, completedWaitSeconds + active)
        }
    }

    private static func queue(for lockURL: URL) -> DispatchQueue {
        let key = lockURL.standardizedFileURL.path
        return stateLock.withLock {
            if let existing = queues[key] { return existing }
            let created = DispatchQueue(label: "com.vitruviansoftware.homespeaker.speech-lock.\(queues.count)")
            queues[key] = created
            return created
        }
    }

    /// Attempts to acquire the speech lock immediately without waiting.
    /// Returns `nil` when another process/task holds the lock or when a
    /// home-speaker broadcast cooldown is still active on `lockURL`.
    public static func tryAcquire(at lockURL: URL?, now: Date = Date()) -> Lease? {
        guard let lockURL else { return nil }
        try? FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        if let deadline = readCooldownDeadline(fd: fd, now: now), deadline > now {
            _ = flock(fd, LOCK_UN)
            _ = close(fd)
            return nil
        }
        writeCooldownDeadline(nil, fd: fd)
        return Lease(fd: fd)
    }

    /// True when `lockURL` is currently held by an announcement or within an
    /// active home-speaker broadcast cooldown window.
    public static func isBusy(at lockURL: URL?, now: Date = Date()) -> Bool {
        guard let lockURL else { return false }
        guard let lease = tryAcquire(at: lockURL, now: now) else { return true }
        lease.release()
        return false
    }

    /// Runs `body` while holding an exclusive `flock` on `lockURL` (or runs
    /// `body` immediately when `lockURL` is `nil`, as in isolated unit tests).
    public static func withLock<T: Sendable>(
        at lockURL: URL?,
        _ body: () async throws -> T
    ) async rethrows -> T {
        try await withLockReportingCooldown(at: lockURL) {
            (try await body(), nil)
        }
    }

    /// Runs `body` while holding an exclusive `flock` on `lockURL` and, if
    /// `body` returns a future `cooldownUntil` timestamp (for a home-speaker
    /// broadcast that continues playing after its HTTP request returns),
    /// records that deadline in `lockURL` before unlocking so the next
    /// announcement waits for the speaker to finish.
    public static func withLockReportingCooldown<T: Sendable>(
        at lockURL: URL?,
        _ body: () async throws -> (value: T, cooldownUntil: Date?)
    ) async rethrows -> T {
        guard let lockURL else { return try await body().value }
        let fd = await acquire(at: lockURL)
        var cooldown: Date?
        defer { release(fd, cooldownUntil: cooldown) }
        let result = try await body()
        cooldown = result.cooldownUntil
        return result.value
    }

    private static func acquire(at lockURL: URL, maxWait: TimeInterval = maxQueueWaitSeconds) async -> Int32 {
        let waitID = UUID()
        let started = Date()
        stateLock.withLock { activeWaitStarts[waitID] = started }
        let serialQueue = queue(for: lockURL)
        return await withCheckedContinuation { continuation in
            serialQueue.async {
                defer {
                    let waited = max(0, Date().timeIntervalSince(started))
                    stateLock.withLock {
                        activeWaitStarts.removeValue(forKey: waitID)
                        completedWaitSeconds += waited
                    }
                }
                try? FileManager.default.createDirectory(
                    at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
                guard fd >= 0 else {
                    continuation.resume(returning: -1)
                    return
                }
                let deadline = started.addingTimeInterval(maxWait)
                while flock(fd, LOCK_EX | LOCK_NB) != 0 {
                    let err = errno
                    if err != EWOULDBLOCK && err != EAGAIN && err != EINTR {
                        close(fd)
                        continuation.resume(returning: -1)
                        return
                    }
                    if Date() >= deadline {
                        close(fd)
                        continuation.resume(returning: -1)
                        return
                    }
                    Thread.sleep(forTimeInterval: 0.01)
                }
                let now = Date()
                if let cooldownEnd = readCooldownDeadline(fd: fd, now: now) {
                    let remaining = min(maxCooldownSeconds, min(deadline, cooldownEnd).timeIntervalSince(now))
                    if remaining > 0 {
                        Thread.sleep(forTimeInterval: remaining)
                    }
                    writeCooldownDeadline(nil, fd: fd)
                }
                continuation.resume(returning: fd)
            }
        }
    }

    private static func readCooldownDeadline(fd: Int32, now: Date) -> Date? {
        guard fd >= 0, lseek(fd, 0, SEEK_SET) == 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = read(fd, &buffer, buffer.count)
        guard count > 0 else { return nil }
        let text = String(decoding: buffer.prefix(count), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let epoch = TimeInterval(text), epoch > 0 else { return nil }
        let capped = min(epoch, now.addingTimeInterval(maxCooldownSeconds).timeIntervalSince1970)
        return Date(timeIntervalSince1970: capped)
    }

    private static func writeCooldownDeadline(_ deadline: Date?, fd: Int32) {
        guard fd >= 0 else { return }
        _ = lseek(fd, 0, SEEK_SET)
        _ = ftruncate(fd, 0)
        if let deadline {
            let capped = min(deadline, Date().addingTimeInterval(maxCooldownSeconds))
            let payload = Data(String(format: "%.3f\n", capped.timeIntervalSince1970).utf8)
            _ = payload.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return 0 }
                return write(fd, base, ptr.count)
            }
        }
        _ = fsync(fd)
    }

    private static func release(_ fd: Int32, cooldownUntil: Date? = nil) {
        guard fd >= 0 else { return }
        if let cooldownUntil, cooldownUntil > Date() {
            writeCooldownDeadline(cooldownUntil, fd: fd)
        }
        _ = flock(fd, LOCK_UN)
        _ = close(fd)
    }
}
