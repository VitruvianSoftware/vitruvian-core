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

/// The "Recent Broadcasts" list, kept in `~/.gemini/speaker_history.json`.
///
/// Several processes add to it: the menu bar app (Quick Announce, chat
/// messages), `HomeSpeaker --say`, the Stop hook's detached `--announce`, and
/// the Stop hook itself when it broadcasts in-process. Each `append` is one
/// read-modify-write under an exclusive `flock` on
/// `speaker_history.json.lock` (see `FileLock`), so two writers never
/// both start from the same list and drop each other's entry.
///
/// The file format is unchanged from what `ConfigManager` wrote before this
/// type existed: a JSON array of `BroadcastLogItem`, newest first, at most
/// `limit` long, encoded with a default `JSONEncoder` (dates as seconds since
/// 2001-01-01). Older files read as they are.
///
/// Reads take no lock: a write replaces the file atomically (rename), so a
/// reader sees the old list or the new one, never half of one. A file that is
/// missing or does not decode reads as empty, and the next `append` starts
/// the list again from that one entry — what `ConfigManager` always did.
public final class BroadcastHistory: Sendable {
    public static let shared = BroadcastHistory()
    /// How many entries the file keeps.
    public static let limit = 30

    public let fileURL: URL
    /// The file the lock is taken on, next to the history.
    public var lockURL: URL { fileURL.appendingPathExtension("lock") }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/speaker_history.json")
    }

    public init(fileURL: URL = BroadcastHistory.defaultURL()) {
        self.fileURL = fileURL
    }

    /// The list on disk, newest first; empty when there is none or it does
    /// not read.
    public func load() -> [BroadcastLogItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([BroadcastLogItem].self, from: data) else { return [] }
        return items
    }

    /// Puts `item` at the top of the list on disk, keeps the newest `limit`,
    /// and returns the list as written.
    @discardableResult
    public func append(_ item: BroadcastLogItem) throws -> [BroadcastLogItem] {
        try FileLock.withExclusiveLock(at: lockURL) {
            let items = Array(([item] + load()).prefix(Self.limit))
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
            return items
        }
    }
}
