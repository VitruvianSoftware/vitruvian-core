// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Private notes a person keeps about a chat, one per chat, kept on this Mac only.
///
/// A note is never sent to the network or the engine: it lives in this Mac's user defaults, keyed by the chat's room
/// ID, so it is still there after a restart. An empty note is no note, so clearing the text removes the entry.
public final class ChatNotesStore: @unchecked Sendable {
    public static let defaultsKey = "courier.chatNotes"
    /// How long after the last keystroke a note is saved.
    public static let saveDelayNanoseconds: UInt64 = 600_000_000

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The note for `roomID`, or "" when there is none.
    public func note(for roomID: String) -> String {
        lock.withLock { read()[roomID] ?? "" }
    }

    /// Saves `text` as the note for `roomID`; a note that is only spaces and new lines removes it.
    public func setNote(_ text: String, for roomID: String) {
        guard !roomID.isEmpty else { return }
        lock.withLock {
            var notes = read()
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard notes.removeValue(forKey: roomID) != nil else { return }
            } else {
                guard notes[roomID] != text else { return }
                notes[roomID] = text
            }
            defaults.set(notes, forKey: Self.defaultsKey)
        }
    }

    /// Whether `roomID` has a note.
    public func hasNote(for roomID: String) -> Bool {
        !note(for: roomID).isEmpty
    }

    private func read() -> [String: String] {
        defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
    }
}
