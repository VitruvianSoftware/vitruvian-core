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

/// "This HomeSpeaker's long-lived process is alive": an exclusive BSD
/// `flock` on a file of its own (the extension's `<data>/running.lock`),
/// held for as long as that process runs.
///
/// The kernel lets go of a `flock` when the process ends, however it ends,
/// so a crash or a kill never leaves the lock looking held. Another process
/// (a Stop hook, `--say`) asks `isHeld(at:)` before raising a speaker's
/// volume that only the live process would put back.
///
/// A `flock` belongs to an open file description, so a check in the same
/// process as the holder still sees it held.
public final class LiveLock: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var fd: Int32

    private init(url: URL, fd: Int32) {
        self.url = url
        self.fd = fd
    }

    deinit { release() }

    /// How many more times `hold` tries, and how long it waits between.
    /// `isHeld` takes the lock for a moment to look; a process starting in
    /// that moment would otherwise be refused. A real holder keeps it, so
    /// it is still refused, about a quarter of a second later.
    static let retries = 10
    static let retryWait: useconds_t = 25_000

    /// Takes the lock at `url`, creating its folder and the file (0600) if
    /// need be. Throws `EWOULDBLOCK` when another holder has it: there is
    /// one live process per side. A lock taken only for a look is waited
    /// out (`retries`).
    public static func hold(at url: URL) throws -> LiveLock {
        try hold(at: url, retries: retries, wait: retryWait, onBusy: { _ in })
    }

    /// `hold` with its wait made visible, for tests. `onBusy(n)` is called
    /// each time the lock is found taken, as try number `n` (1, 2, ...),
    /// just before the wait. A test lets go of its own lock there, so the
    /// retry is exercised without a timer.
    static func hold(
        at url: URL, retries: Int, wait: useconds_t, onBusy: (Int) -> Void
    ) throws -> LiveLock {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var tries = 0
        while !tryLock(fd) {
            let code = errno
            guard code == EWOULDBLOCK, tries < retries else {
                close(fd)
                throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EWOULDBLOCK)
            }
            tries += 1
            onBusy(tries)
            usleep(wait)
        }
        return LiveLock(url: url, fd: fd)
    }

    /// Lets go. The process ending does the same.
    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    /// Whether some process holds the lock at `url`. Tries to take it
    /// without waiting, and lets go at once if it could. No file means no
    /// holder; the file is never created here.
    public static func isHeld(at url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard tryLock(fd) else { return errno == EWOULDBLOCK }
        flock(fd, LOCK_UN)
        return false
    }

    /// A non-blocking exclusive lock, retried on a signal.
    private static func tryLock(_ fd: Int32) -> Bool {
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EINTR else { return false }
        }
        return true
    }
}
