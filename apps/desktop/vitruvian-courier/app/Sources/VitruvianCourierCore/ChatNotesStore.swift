// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation
import os

/// Private notes a person keeps about a chat, one per chat, kept on this Mac only.
///
/// There is one live store for the app (`shared`), so two windows on the same chat read and write the same text and
/// neither overwrites the other. Typing changes the text in memory at once. The file, `chat-notes.json` in the app's
/// Application Support folder, is read and written on a background queue, so typing never waits on the disk: a write
/// happens a moment after the last keystroke, when the person switches chats or closes the pane (`flush`), and when
/// the app quits (that one waits, so nothing is lost). A write that fails is logged and tried again. A file that can't
/// be read is moved aside, never written over. A note is never sent to the network or the engine. An empty note is no
/// note, so clearing the text removes it.
@MainActor
public final class ChatNotesStore: ObservableObject {
    /// Starts `work` after `delay` and returns what cancels it. Tests pass one they fire by hand.
    public typealias Scheduler = @MainActor (_ delay: Duration, _ work: @escaping @MainActor () -> Void) -> () -> Void

    public static let defaultSaveDelay: Duration = .milliseconds(600)
    /// How long after a failed write the store tries again by itself (it also tries on the next change or flush).
    public static let retryDelay: Duration = .seconds(2)
    public static let fileName = "chat-notes.json"

    private static var replacement: ChatNotesStore?
    private static let appStore = ChatNotesStore(fileURL: defaultFileURL())
    /// The app's store, in its own data folder.
    public static var shared: ChatNotesStore { replacement ?? appStore }

    /// Makes `store` what `shared` returns (nil puts the app's own back). For tests, so they never touch the real folder.
    public static func useSharedStoreForTesting(_ store: ChatNotesStore?) { replacement = store }

    /// `chat-notes.json` in the app's data folder (`~/Library/Application Support/Vitruvian Courier`).
    public static func defaultFileURL() -> URL {
        EngineLocation.dataDirectory().appendingPathComponent(fileName)
    }

    /// The default scheduler: a task that sleeps.
    public static let sleepingScheduler: Scheduler = { delay, work in
        let task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            work()
        }
        return { task.cancel() }
    }

    /// Every note, by room ID. Views watching the store redraw when one changes.
    @Published public private(set) var notes: [String: String] = [:]
    /// A change is waiting to be written, or its write failed and will be tried again.
    public private(set) var hasUnsavedChanges = false

    private static let log = Logger(subsystem: "dev.vitruvian.courier", category: "ChatNotes")

    private let fileURL: URL?
    private let saveDelay: Duration
    private let schedule: Scheduler
    private let center: NotificationCenter
    private let io = DispatchQueue(label: "dev.vitruvian.courier.chat-notes")
    private var cancelPending: (() -> Void)?
    private var quitObserver: NSObjectProtocol?
    /// The file couldn't be read and couldn't be moved aside: nothing is written over it.
    private var writesBlocked = false

    /// - Parameters:
    ///   - fileURL: where the notes are kept; nil keeps them in memory only.
    ///   - schedule: how the pause before a write, and the retry, are timed.
    ///   - notificationCenter: where the app's quit is announced; the store writes what is waiting, then.
    public init(fileURL: URL?, saveDelay: Duration? = nil, schedule: Scheduler? = nil,
                notificationCenter: NotificationCenter = .default) {
        self.fileURL = fileURL
        self.saveDelay = saveDelay ?? Self.defaultSaveDelay
        self.schedule = schedule ?? Self.sleepingScheduler
        self.center = notificationCenter
        quitObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush(waiting: true) }
        }
        if let fileURL { load(fileURL) }
    }

    deinit {
        if let quitObserver { center.removeObserver(quitObserver) }
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
        hasUnsavedChanges = true
        scheduleWrite(after: saveDelay)
    }

    /// Writes any change not yet on disk, now: in the background, or with `waiting` (at quit) before returning.
    public func flush(waiting: Bool = false) {
        cancelPending?()
        cancelPending = nil
        guard hasUnsavedChanges, !writesBlocked, let fileURL else { return }
        let snapshot = notes
        hasUnsavedChanges = false
        if waiting {
            io.sync { _ = Self.write(snapshot, to: fileURL) }
            return
        }
        io.async { [weak self] in
            let failure = Self.write(snapshot, to: fileURL)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finishedWrite(failure) }
            }
        }
    }

    /// Returns once the file work started so far has finished and its results are in. For tests.
    public func waitForFileWork() async {
        await withCheckedContinuation { continuation in
            io.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }

    // MARK: - Files

    private func scheduleWrite(after delay: Duration) {
        cancelPending?()
        cancelPending = schedule(delay) { [weak self] in self?.flush() }
    }

    private func finishedWrite(_ failure: Error?) {
        guard let failure else { return }
        Self.log.error("Couldn't save chat notes: \(failure.localizedDescription, privacy: .public)")
        hasUnsavedChanges = true
        scheduleWrite(after: Self.retryDelay)
    }

    private func load(_ url: URL) {
        io.async { [weak self] in
            let result = Self.read(url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finishedLoad(result) }
            }
        }
    }

    private func finishedLoad(_ result: LoadResult) {
        switch result {
        case let .notes(loaded):
            // What was typed before the file came in wins over the file.
            notes = loaded.merging(notes) { _, typed in typed }
        case .missing:
            break
        case let .movedAside(from, to):
            Self.log.error("Chat notes file was unreadable; kept as \(to.lastPathComponent, privacy: .public)")
            _ = from
        case .unreadable:
            Self.log.error("Chat notes file is unreadable and could not be moved aside; it is left alone")
            writesBlocked = true
        }
    }

    enum LoadResult {
        case notes([String: String])
        case missing
        case movedAside(from: URL, to: URL)
        case unreadable
    }

    /// A missing file is no notes. A file that is there but not readable as notes is moved to
    /// `chat-notes.corrupt-<time>.json` beside it, so a later write can't destroy what was in it.
    nonisolated static func read(_ url: URL, now: Date = Date()) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            return .notes(decoded)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS"
        let stamp = formatter.string(from: now)
        let base = url.deletingPathExtension().lastPathComponent
        var target = url.deletingLastPathComponent().appendingPathComponent("\(base).corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: target.path) {
            target = url.deletingLastPathComponent()
                .appendingPathComponent("\(base).corrupt-\(stamp)-\(UUID().uuidString.prefix(8)).json")
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return .movedAside(from: url, to: target)
        } catch {
            return .unreadable
        }
    }

    /// nil when written; the error otherwise.
    nonisolated static func write(_ notes: [String: String], to url: URL) -> Error? {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(notes).write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }
}
