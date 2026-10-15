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
