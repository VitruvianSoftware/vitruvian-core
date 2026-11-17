// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import XCTest

@testable import VitruvianCourierCore

@MainActor
final class ChatNotesStoreTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    private func file() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chat-notes-\(UUID().uuidString)")
        folders.append(folder)
        return folder.appendingPathComponent(ChatNotesStore.fileName)
    }

    private func onDisk(_ url: URL) -> [String: String]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    func testTypingIsSavedAfterTheDelayAndShownOnReopen() async throws {
        let url = file()
        let store = ChatNotesStore(fileURL: url, saveDelay: .milliseconds(40), notificationCenter: NotificationCenter())
        store.setNote("Gate c", for: "!a")
        store.setNote("Gate code 4417", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "Gate code 4417", "shown at once")
        XCTAssertNil(onDisk(url), "not written before the delay")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(onDisk(url), ["!a": "Gate code 4417"])

        let reopened = ChatNotesStore(fileURL: url, notificationCenter: NotificationCenter())
        XCTAssertEqual(reopened.note(for: "!a"), "Gate code 4417")
    }

    func testSwitchingChatsMidDelaySavesEachNoteUnderItsOwnChat() async throws {
        let url = file()
        let store = ChatNotesStore(fileURL: url, saveDelay: .seconds(30), notificationCenter: NotificationCenter())
        store.setNote("About A", for: "!a")
        store.flush() // the pane flushes when the chat changes
        store.setNote("About B", for: "!b")
        store.flush()
        XCTAssertEqual(onDisk(url), ["!a": "About A", "!b": "About B"])
    }

    func testQuitWritesWhatIsStillWaiting() throws {
        let url = file()
        let center = NotificationCenter()
        let store = ChatNotesStore(fileURL: url, saveDelay: .seconds(30), notificationCenter: center)
        store.setNote("Typed just before quitting", for: "!a")
        XCTAssertNil(onDisk(url))
        center.post(name: NSApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(onDisk(url), ["!a": "Typed just before quitting"])
    }

    func testTwoWindowsShareOneLiveStore() throws {
        let store = ChatNotesStore(fileURL: file(), saveDelay: .seconds(30), notificationCenter: NotificationCenter())
        // Both windows read and write the one store: the second sees the first's typing, and neither undoes it.
        store.setNote("typed in window 1", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "typed in window 1")
        store.setNote("typed in window 1, then 2", for: "!a")
        XCTAssertEqual(store.note(for: "!a"), "typed in window 1, then 2")
    }

    func testClearingANoteRemovesIt() throws {
        let url = file()
        let store = ChatNotesStore(fileURL: url, saveDelay: .seconds(30), notificationCenter: NotificationCenter())
        store.setNote("keep", for: "!a")
        store.flush()
        store.setNote("  \n ", for: "!a")
        store.flush()
        XCTAssertFalse(store.hasNote(for: "!a"))
        XCTAssertEqual(onDisk(url), [:])
        store.setNote("no chat", for: "")
        XCTAssertEqual(store.note(for: ""), "")
    }

    func testTheNotesFileIsInTheAppDataFolder() {
        XCTAssertEqual(ChatNotesStore.defaultFileURL(),
                       EngineLocation.dataDirectory().appendingPathComponent("chat-notes.json"))
    }
}
