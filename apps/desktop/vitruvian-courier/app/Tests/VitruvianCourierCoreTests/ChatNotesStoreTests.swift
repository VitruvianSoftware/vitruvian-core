// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest

@testable import VitruvianCourierCore

/// A clock the test turns by hand: what the store schedules waits here until `fire`.
@MainActor
final class ManualNotesScheduler {
    struct Job { let delay: Duration; let work: @MainActor () -> Void; var cancelled = false }
    private(set) var jobs: [Job] = []

    var scheduler: ChatNotesStore.Scheduler {
        { [self] delay, work in
            let index = jobs.count
            jobs.append(Job(delay: delay, work: work))
            return { [self] in jobs[index].cancelled = true }
        }
    }

    var pending: [Job] { jobs.filter { !$0.cancelled } }

    /// Runs what is waiting (not what was cancelled), once.
    func fire() {
        let due = pending
        for index in jobs.indices { jobs[index].cancelled = true }
        for job in due { job.work() }
    }
}

@MainActor
final class ChatNotesStoreTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    private func folder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-notes-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        return folder
    }

    private func store(_ url: URL?, _ clock: ManualNotesScheduler, center: NotificationCenter = NotificationCenter())
        -> ChatNotesStore {
        ChatNotesStore(fileURL: url, schedule: clock.scheduler, notificationCenter: center)
    }

    private func onDisk(_ url: URL) -> [String: String]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    // MARK: - Reading

    func testAMissingFileIsNoNotesAndMakesNoFile() async {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        let store = store(url, ManualNotesScheduler())
        await store.waitForFileWork()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testACorruptFileIsMovedAsideWithItsContentAndNeverWrittenOver() async throws {
        let dir = folder()
        let url = dir.appendingPathComponent(ChatNotesStore.fileName)
        let garbage = Data("{ not json at all".utf8)
        try garbage.write(to: url)
        let clock = ManualNotesScheduler()
        let store = store(url, clock)
        await store.waitForFileWork()
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "moved out of the way")
        let moved = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("chat-notes.corrupt-") && $0.hasSuffix(".json") }
        XCTAssertEqual(moved.count, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(moved[0])), garbage, "its content is kept")

        store.setNote("fresh", for: "!a")
        clock.fire()
        await store.waitForFileWork()
        XCTAssertEqual(onDisk(url), ["!a": "fresh"])
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(moved[0])), garbage)
    }

    func testNotesAlreadyOnDiskAreLoadedAndWhatWasTypedFirstWins() async throws {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        try JSONEncoder().encode(["!a": "from disk", "!b": "also disk"]).write(to: url)
        let store = store(url, ManualNotesScheduler())
        store.setNote("typed before the file came in", for: "!a")
        await store.waitForFileWork()
        XCTAssertEqual(store.note(for: "!a"), "typed before the file came in")
        XCTAssertEqual(store.note(for: "!b"), "also disk")
    }

    // MARK: - Writing

    func testTypingIsWrittenOnlyWhenThePauseEndsAndShownOnReopen() async throws {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        let clock = ManualNotesScheduler()
        let store = store(url, clock)
        store.setNote("Gate c", for: "!a")
        store.setNote("Gate code 4417", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "Gate code 4417", "shown at once")
        XCTAssertEqual(clock.pending.count, 1, "each keystroke restarts the one wait")
        XCTAssertEqual(clock.pending.first?.delay, ChatNotesStore.defaultSaveDelay)
        await store.waitForFileWork()
        XCTAssertNil(onDisk(url), "not written before the pause ends")
        clock.fire()
        await store.waitForFileWork()
        XCTAssertEqual(onDisk(url), ["!a": "Gate code 4417"])
        XCTAssertFalse(store.hasUnsavedChanges)

        let reopened = self.store(url, ManualNotesScheduler())
        await reopened.waitForFileWork()
        XCTAssertEqual(reopened.note(for: "!a"), "Gate code 4417")
    }

    func testSwitchingChatsFlushesEachNoteUnderItsOwnChat() async throws {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        let store = store(url, ManualNotesScheduler())
        store.setNote("About A", for: "!a")
        store.flush() // the pane flushes when the chat changes
        store.setNote("About B", for: "!b")
        store.flush()
        await store.waitForFileWork()
        XCTAssertEqual(onDisk(url), ["!a": "About A", "!b": "About B"])
    }

    func testQuitWritesWhatIsWaitingBeforeItReturns() {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        let center = NotificationCenter()
        let store = store(url, ManualNotesScheduler(), center: center)
        store.setNote("Typed just before quitting", for: "!a")
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        // No waiting for background work: the quit write is done when the post returns.
        XCTAssertEqual(onDisk(url), ["!a": "Typed just before quitting"])
    }

    func testAFailedWriteIsKeptAndTriedAgainByItselfThenOnTheNextChange() async throws {
        let dir = folder()
        // A file where the folder should be: the notes file can't be made under it.
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let url = blocker.appendingPathComponent(ChatNotesStore.fileName)
        let clock = ManualNotesScheduler()
        let store = store(url, clock)
        await store.waitForFileWork()
        store.setNote("must not be lost", for: "!a")
        clock.fire()
        await store.waitForFileWork()
        XCTAssertTrue(store.hasUnsavedChanges, "the failure is not forgotten")
        XCTAssertEqual(clock.pending.map(\.delay), [ChatNotesStore.retryDelay], "a retry is waiting")

        try FileManager.default.removeItem(at: blocker) // the problem goes away
        clock.fire()
        await store.waitForFileWork()
        XCTAssertFalse(store.hasUnsavedChanges)
        XCTAssertEqual(onDisk(url), ["!a": "must not be lost"])
    }

    // MARK: - Sharing and cleanup

    func testTwoWindowsShareOneLiveStore() {
        let store = store(nil, ManualNotesScheduler())
        store.setNote("typed in window 1", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "typed in window 1")
        store.setNote("typed in window 1, then 2", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "typed in window 1, then 2")
    }

    func testClearingANoteRemovesIt() async {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        let store = store(url, ManualNotesScheduler())
        store.setNote("keep", for: "!a")
        store.flush()
        store.setNote("  \n ", for: "!a")
        store.flush()
        await store.waitForFileWork()
        XCTAssertFalse(store.hasNote(for: "!a"))
        XCTAssertEqual(onDisk(url), [:])
        store.setNote("no chat", for: "")
        XCTAssertEqual(store.note(for: ""), "")
    }

    func testAStoreThatIsGoneNoLongerAnswersTheQuit() {
        let url = folder().appendingPathComponent(ChatNotesStore.fileName)
        let center = NotificationCenter()
        var store: ChatNotesStore? = self.store(url, ManualNotesScheduler(), center: center)
        store?.setNote("x", for: "!a")
        store = nil
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the observer left with the store")
    }

    func testTheNotesFileIsInTheAppDataFolder() {
        XCTAssertEqual(ChatNotesStore.defaultFileURL(),
                       EngineLocation.dataDirectory().appendingPathComponent("chat-notes.json"))
    }
}
