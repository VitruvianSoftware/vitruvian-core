// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// Session cache, in-flight deduplicator, and sequential incoming auto-transcribe queue for voice notes.
///
/// - Keyed by `TimelineMessage.id` (`eventID`) for the session so scrolling back never repeats work.
/// - Checks `AudioPlayerModel.localMediaURL(for:)` before touching any engine: if the voice note is not on disk yet,
///   records `"Download the voice note first."` and makes zero engine or network calls.
/// - Auto-transcribe processes incoming (`!message.mine`) voice notes shown on screen one at a time.
@MainActor
public final class VoiceNoteTranscriptStore: ObservableObject {
    public enum Entry: Equatable, Sendable {
        case transcribing
        case transcribed(text: String, provenance: SpeechProvenance, isCollapsed: Bool)
        case failed(message: String)
    }

    private struct QueuedNote: Equatable {
        let eventID: String
        let mediaPath: String
    }

    @Published public private(set) var entries: [String: Entry] = [:]

    public var engineFactory: SpeechEngineFactory
    public var resolveLocalFile: @MainActor (String) -> URL?

    private var inFlightTasks: [String: Task<Void, Never>] = [:]
    private var missingLocalFileMediaPaths: [String: String] = [:]
    private var autoTranscribedEventIDs: Set<String> = []
    private var autoQueue: [QueuedNote] = []
    private var autoWorkerTask: Task<Void, Never>?

    public init(
        engineFactory: SpeechEngineFactory? = nil,
        resolveLocalFile: @escaping @MainActor (String) -> URL? = { AudioPlayerModel.localMediaURL(for: $0) }
    ) {
        self.engineFactory = engineFactory ?? SpeechEngineFactory(preferences: AIPreferences())
        self.resolveLocalFile = resolveLocalFile
    }

    public func entry(for eventID: String) -> Entry? {
        if let missingPath = missingLocalFileMediaPaths[eventID],
           resolveLocalFile(missingPath) != nil
        {
            return nil
        }
        return entries[eventID]
    }

    public func toggleCollapsed(eventID: String) {
        guard case let .transcribed(text, provenance, isCollapsed) = entries[eventID] else { return }
        entries[eventID] = .transcribed(text: text, provenance: provenance, isCollapsed: !isCollapsed)
    }

    /// Preview/snapshot helper for deterministic view rendering tests.
    public func setEntryForTesting(_ entry: Entry?, for eventID: String) {
        missingLocalFileMediaPaths.removeValue(forKey: eventID)
        if let entry {
            entries[eventID] = entry
        } else {
            entries.removeValue(forKey: eventID)
        }
    }

    /// Transcribes `eventID` from its local `mediaPath`, returning immediately if already cached or joining an
    /// already in-flight request for the same `eventID`.
    public func transcribe(eventID: String, mediaPath: String) async {
        guard !eventID.isEmpty else { return }
        clearMissingLocalFileIfResolved(eventID: eventID, mediaPath: mediaPath)

        if case .transcribed = entries[eventID] {
            return
        }
        if let existingTask = inFlightTasks[eventID] {
            await existingTask.value
            return
        }

        guard let localURL = resolveLocalFile(mediaPath) else {
            missingLocalFileMediaPaths[eventID] = mediaPath
            entries[eventID] = .failed(message: SpeechError.missingLocalFile.message)
            return
        }
        missingLocalFileMediaPaths.removeValue(forKey: eventID)

        let engine: any SpeechEngine
        switch engineFactory.resolveEngine() {
        case let .available(resolved):
            engine = resolved
        case let .notAllowed(reason):
            entries[eventID] = .failed(message: reason)
            return
        }

        let language = engineFactory.preferences.transcriptionLanguage
        entries[eventID] = .transcribing

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.inFlightTasks.removeValue(forKey: eventID)
            }
            do {
                let raw = try await engine.transcribe(file: localURL, language: language)
                guard !Task.isCancelled else { return }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayText = trimmed.isEmpty ? String(localized: "No speech detected.") : trimmed
                self.entries[eventID] = .transcribed(
                    text: displayText,
                    provenance: engine.provenance,
                    isCollapsed: false
                )
            } catch is CancellationError {
                if case .transcribing = self.entries[eventID] {
                    self.entries.removeValue(forKey: eventID)
                }
            } catch {
                let message = (error as? SpeechError)?.message
                    ?? String(localized: "Voice-note transcription failed.")
                self.entries[eventID] = .failed(message: message)
            }
        }
        inFlightTasks[eventID] = task
        await task.value
    }

    /// Called when a voice note appears on screen. When `autoTranscribeVoiceNotes` is enabled, queues incoming
    /// (`!mine`) downloaded voice notes that have not yet been transcribed, processing them one at a time.
    public func noteAppeared(message: TimelineMessage) {
        guard message.kind == .voiceNote else { return }
        noteAppeared(eventID: message.id, mediaPath: message.mediaPath, isMine: message.mine)
    }

    public func noteAppeared(eventID: String, mediaPath: String, isMine: Bool) {
        guard !eventID.isEmpty else { return }
        clearMissingLocalFileIfResolved(eventID: eventID, mediaPath: mediaPath)
        guard engineFactory.preferences.autoTranscribeVoiceNotes else { return }
        guard !isMine else { return }
        guard entry(for: eventID) == nil,
              inFlightTasks[eventID] == nil,
              !autoTranscribedEventIDs.contains(eventID),
              !autoQueue.contains(where: { $0.eventID == eventID })
        else {
            return
        }
        guard resolveLocalFile(mediaPath) != nil else {
            return
        }

        autoQueue.append(QueuedNote(eventID: eventID, mediaPath: mediaPath))
        startAutoWorkerIfNeeded()
    }

    /// Called when a voice note leaves the screen (scrolls out of view or the open chat changes) so pending
    /// off-screen notes are removed from the auto-transcribe queue before starting.
    public func noteDisappeared(message: TimelineMessage) {
        guard message.kind == .voiceNote else { return }
        noteDisappeared(eventID: message.id)
    }

    public func noteDisappeared(eventID: String) {
        guard !eventID.isEmpty else { return }
        autoQueue.removeAll { $0.eventID == eventID }
    }

    /// Deterministic test helper: awaits the auto-transcribe worker and any in-flight tasks.
    public func waitForIdle() async {
        await autoWorkerTask?.value
        while !inFlightTasks.isEmpty {
            let tasks = Array(inFlightTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }

    private func clearMissingLocalFileIfResolved(eventID: String, mediaPath: String) {
        guard let previousMissingPath = missingLocalFileMediaPaths[eventID] else { return }
        if resolveLocalFile(mediaPath) != nil || resolveLocalFile(previousMissingPath) != nil {
            missingLocalFileMediaPaths.removeValue(forKey: eventID)
            if entries[eventID] == .failed(message: SpeechError.missingLocalFile.message) {
                entries.removeValue(forKey: eventID)
            }
        }
    }

    private func startAutoWorkerIfNeeded() {
        guard autoWorkerTask == nil, !autoQueue.isEmpty else { return }
        autoWorkerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.autoWorkerTask = nil }
            while !Task.isCancelled, !self.autoQueue.isEmpty {
                let next = self.autoQueue.removeFirst()
                guard self.engineFactory.preferences.autoTranscribeVoiceNotes else {
                    self.autoQueue.removeAll()
                    break
                }
                self.clearMissingLocalFileIfResolved(eventID: next.eventID, mediaPath: next.mediaPath)
                if self.entry(for: next.eventID) == nil {
                    await self.transcribe(eventID: next.eventID, mediaPath: next.mediaPath)
                }
                if self.entry(for: next.eventID) != nil,
                   self.missingLocalFileMediaPaths[next.eventID] == nil
                {
                    self.autoTranscribedEventIDs.insert(next.eventID)
                }
            }
        }
    }
}
