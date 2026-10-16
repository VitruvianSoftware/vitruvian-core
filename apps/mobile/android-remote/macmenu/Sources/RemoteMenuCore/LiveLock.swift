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

/// An exclusive BSD `flock` on `<data>/running.lock` held while the extension's
/// long-lived process runs, so another process can tell whether the extension is
/// currently alive. The kernel releases the lock automatically on process exit.
public final class LiveLock: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var fd: Int32

    private init(url: URL, fd: Int32) {
        self.url = url
        self.fd = fd
    }

    deinit { release() }

    public static func hold(at url: URL) throws -> LiveLock {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard tryLock(fd) else {
            let code = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EWOULDBLOCK)
        }
        return LiveLock(url: url, fd: fd)
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    public static func isHeld(at url: URL) -> Bool {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard tryLock(fd) else { return errno == EWOULDBLOCK }
        flock(fd, LOCK_UN)
        return false
    }

    private static func tryLock(_ fd: Int32) -> Bool {
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EINTR else { return false }
        }
        return true
    }
}

/// Exclusive BSD `flock` helper for atomic read-modify-write operations on
/// shared JSON files (`remote_door.json`, `settings.json`).
public enum FileLock {
    public static func withExclusiveLock<T>(
        for fileURL: URL,
        body: () throws -> T
    ) throws -> T {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockURL = dir.appendingPathComponent(".\(fileURL.lastPathComponent).lock")
        let fd = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        while flock(fd, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        return try body()
    }

    /// Writes `data` atomically to `url` with `permissions` (default `0o600`).
    public static func writeAtomically(
        _ data: Data,
        to url: URL,
        permissions: mode_t = 0o600
    ) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let tmpURL = dir.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        let fd = open(tmpURL.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, permissions)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var succeeded = false
        defer {
            if fd >= 0 { close(fd) }
            if !succeeded { unlink(tmpURL.path) }
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let written = write(fd, base.advanced(by: offset), remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                remaining -= written
                offset += written
            }
        }
        fchmod(fd, permissions)
        fsync(fd)
        if rename(tmpURL.path, url.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        chmod(url.path, permissions)
        succeeded = true
    }
}
