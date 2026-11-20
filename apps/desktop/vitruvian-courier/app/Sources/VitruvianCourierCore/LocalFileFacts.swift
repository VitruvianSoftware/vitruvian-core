// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Whether a local media file is there, remembered in memory, so that a row being laid out (or measured off-screen for
/// its height) never touches the disk: a view asks `exists`, which answers from memory only. A path not known yet is
/// looked up on a background queue (or ahead of time, with `warm`, as `ImagePixelSizeReader.warm` does for sizes), and
/// the answer is announced with `ImagePixelSizeReader.didLearnSizeNotification` (the same one a learned picture size
/// posts, with the path), which the table timeline re-measures the row for.
///
/// A file that is there stays known as there. One that was not is asked again after a moment (a download finishing),
/// so a stale "missing" never outlives `missingLifetime`.
public enum LocalFileFacts {
    /// How long a "not there" answer is trusted.
    public nonisolated static let missingLifetime: TimeInterval = 0.5

    private struct Fact {
        let exists: Bool
        let at: Date
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var facts: [String: Fact] = [:]
        var inFlight = Set<String>()
        var warmer: (@Sendable (String) -> Void)?
    }

    private nonisolated static let state = State()
    private nonisolated static let queue = DispatchQueue(label: "courier.localfilefacts", qos: .userInitiated)

    /// What the memory holds (never reads disk); nil when unknown or when a "missing" has expired. An unknown or
    /// expired path is looked up in the background.
    public nonisolated static func exists(_ path: String) -> Bool? {
        let fact = state.lock.withLock { state.facts[path] }
        if let fact {
            if fact.exists || Date().timeIntervalSince(fact.at) < missingLifetime { return fact.exists }
            lookUpInBackground(path)
            // Expired "missing": still the best answer until the lookup says otherwise.
            return fact.exists
        }
        lookUpInBackground(path)
        return nil
    }

    /// Memory only, never starting a lookup: for a row's content revision.
    public nonisolated static func cachedExists(_ path: String) -> Bool? {
        state.lock.withLock { state.facts[path]?.exists }
    }

    /// Runs `body` for each local file once it is known to be there (off the main thread), for what is worth
    /// preparing ahead of its row (a PDF's pages). Set once.
    public nonisolated static func setWarmer(_ body: @escaping @Sendable (String) -> Void) {
        state.lock.withLock { state.warmer = body }
    }

    /// Looks `paths` up now, on the calling thread (not the main one), and runs the warmer for those that exist.
    public nonisolated static func warm(paths: [String]) {
        for path in paths where isLocalMediaStorePath(path) {
            probe(path, announce: false)
        }
    }

    /// Local files the events refer to: media, thumbnails and link-preview pictures.
    public nonisolated static func paths(in events: [Event]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ path: String?) {
            guard let path, !path.isEmpty, seen.insert(path).inserted else { return }
            result.append(path)
        }
        for event in events {
            add(event.mediaPath)
            add(event.thumbnailPath)
            for preview in event.linkPreviews ?? [] { add(preview.imagePath) }
        }
        return result
    }

    private nonisolated static func lookUpInBackground(_ path: String) {
        let started = state.lock.withLock { state.inFlight.insert(path).inserted }
        guard started else { return }
        queue.async { probe(path, announce: true) }
    }

    private nonisolated static func probe(_ path: String, announce: Bool) {
        var isDirectory: ObjCBool = false
        let there = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        let (changed, warmer) = state.lock.withLock { () -> (Bool, (@Sendable (String) -> Void)?) in
            let before = state.facts[path]?.exists
            state.facts[path] = Fact(exists: there, at: Date())
            state.inFlight.remove(path)
            return ((before ?? false) != there, there ? state.warmer : nil)
        }
        if there { warmer?(path) }
        guard announce, changed else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: ImagePixelSizeReader.didLearnSizeNotification,
                object: nil,
                userInfo: [ImagePixelSizeReader.pathUserInfoKey: path]
            )
        }
    }
}
