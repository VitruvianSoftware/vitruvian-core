// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

/// Private notes a person keeps about a chat, one per chat, kept on this Mac only.
///
/// There is one live store for the app (`shared`), so two windows on the same chat read and write the same text and
/// neither overwrites the other. Typing changes the text in memory at once; it is written to
/// `chat-notes.json` in the app's Application Support folder a moment later, when the person switches chats or closes
/// the pane (`flush`), and when the app quits. A note is never sent to the network or the engine. An empty note is no
/// note, so clearing the text removes it.
@MainActor
public final class ChatNotesStore: ObservableObject {
    /// The app's store, in its own data folder.
    public static let shared = ChatNotesStore(fileURL: defaultFileURL())
    /// How long after the last keystroke a note is written.
    public static let defaultSaveDelay: Duration = .milliseconds(600)
    public static let fileName = "chat-notes.json"

    /// `chat-notes.json` in the app's data folder (`~/Library/Application Support/Vitruvian Courier`).
    public static func defaultFileURL() -> URL {
        EngineLocation.dataDirectory().appendingPathComponent(fileName)
    }

    /// Every note, by room ID. Views watching the store redraw when one changes.
    @Published public private(set) var notes: [String: String]

    private let fileURL: URL?
    private let saveDelay: Duration
    private var isDirty = false
    private var pendingSave: Task<Void, Never>?
    private var quitObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - fileURL: where the notes are kept; nil keeps them in memory only.
    ///   - notificationCenter: where the app's quit is announced; the store writes what is pending then.
    public init(fileURL: URL?, saveDelay: Duration = ChatNotesStore.defaultSaveDelay,
                notificationCenter: NotificationCenter = .default) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay
        self.notes = fileURL.flatMap(Self.read) ?? [:]
        quitObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    deinit {
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
    }

    /// The note for `roomID`, or "" when there is none.
    public func note(for roomID: String) -> String { notes[roomID] ?? "" }

    public func hasNote(for roomID: String) -> Bool { notes[roomID] != nil }

    /// Sets the note for `roomID` in memory at once and writes it soon; text of only spaces and new lines removes it.
    public func setNote(_ text: String, for roomID: String) {
        guard !roomID.isEmpty else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard notes.removeValue(forKey: roomID) != nil else { return }
        } else {
            guard notes[roomID] != text else { return }
            notes[roomID] = text
        }
        isDirty = true
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes any change not yet on disk, now.
    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard isDirty, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            // Kept dirty: the next change, switch or quit tries again.
        }
    }

    private static func read(_ url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
