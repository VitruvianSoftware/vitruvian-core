// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// An MCP client's focus_app in the app: it brings Courier forward at the chat, fills the composer with the draft
/// and the file (whose chip shows its name), and never sends. A chat the app can't find, or a file it can't attach,
/// leaves it on the inbox with nothing filled in. All data here is made up.
@MainActor
final class FocusRoutingTests: XCTestCase {
    private var harness: ConversationHarness?
    private var files: [URL] = []

    override func tearDown() async throws {
        await harness?.stop()
        harness = nil
        AppLockGate.shared.resetForTesting()
        for file in files { try? FileManager.default.removeItem(at: file) }
        files = []
    }

    private func start() async throws -> ConversationHarness {
        let h = try await startConversation(
            ["!a": [textEvent(id: "$1", room: "!a", at: 1), textEvent(id: "$2", room: "!a", at: 2)]],
            features: ["!a": featuresJSON()],
            rows: ["!a": chatRow("!a", name: "Example Person", network: "signal")])
        harness = h
        return h
    }

    private func router(_ h: ConversationHarness, known: Set<String> = ["!a"],
                        activations: @escaping () -> Void = {}) -> FocusRouter {
        FocusRouter(appModel: h.app, composer: h.conversation.composer,
                    lookUpChat: { known.contains($0) }, activate: activations)
    }

    private func makeFile(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("courier-focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try Data("made-up file".utf8).write(to: url)
        files.append(dir)
        return url
    }

    private func sends(_ h: ConversationHarness) -> [String] {
        h.server.receivedMethods().filter { $0.hasPrefix("message.send") || $0 == "message.schedule" }
    }

    func testChatAndDraftFillTheComposerWithoutSending() async throws {
        let h = try await start()
        var activated = 0
        let router = router(h) { activated += 1 }
        await router.route(FocusParams(chatID: "!a", draftText: "Example draft"))
        XCTAssertEqual(activated, 1)
        XCTAssertEqual(h.app.selectedRoomID, "!a")
        try await waitUntil { h.conversation.roomID == "!a" }
        XCTAssertEqual(h.conversation.composer.text, "Example draft")
        XCTAssertEqual(sends(h), [], "a focus_app draft is only filled in")
    }

    func testAttachmentIsAttachedWithItsNameAndNothingIsSent() async throws {
        let h = try await start()
        let file = try makeFile("agenda.pdf")
        let router = router(h)
        await router.route(FocusParams(chatID: "!a", draftText: "See attached", draftAttachmentPath: file.path))
        try await waitUntil { h.conversation.roomID == "!a" }
        let composer = h.conversation.composer
        XCTAssertEqual(composer.attachments.map(\.url), [file])
        XCTAssertEqual(composer.attachments.first?.fileName, "agenda.pdf", "the chip shows the file's name")
        XCTAssertEqual(composer.text, "See attached")
        // Time passes, and still nothing goes until the person presses Send.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sends(h), [])
        XCTAssertEqual(composer.attachments.count, 1)
    }

    func testDraftForTheOpenChatGoesStraightIntoItsComposer() async throws {
        let h = try await start()
        try await h.open("!a")
        let file = try makeFile("notes.txt")
        await router(h).route(FocusParams(chatID: "!a", draftAttachmentPath: file.path))
        XCTAssertEqual(h.conversation.composer.attachments.map(\.fileName), ["notes.txt"])
        XCTAssertEqual(sends(h), [])
    }

    func testMessageOpensTheChatAtIt() async throws {
        let h = try await start()
        await router(h).route(FocusParams(chatID: "!a", messageID: "$1"))
        XCTAssertEqual(h.app.pendingMessage?.roomID, "!a")
        XCTAssertEqual(h.app.pendingMessage?.eventID, "$1")
        XCTAssertEqual(h.app.selectedRoomID, "!a")
    }

    func testUnknownChatFallsBackToTheInbox() async throws {
        let h = try await start()
        var activated = 0
        await router(h, known: []) { activated += 1 }
            .route(FocusParams(chatID: "!gone", draftText: "Example draft"))
        XCTAssertEqual(activated, 1, "Courier still comes forward")
        XCTAssertNil(h.app.selectedRoomID, "no chat opens")
        try await h.open("!a")
        XCTAssertEqual(h.conversation.composer.text, "", "no draft went anywhere")
    }

    func testAFileThatCantBeAttachedFillsInNothing() async throws {
        let h = try await start()
        let folder = try makeFile("folder.txt").deletingLastPathComponent()
        await router(h).route(FocusParams(chatID: "!a", draftText: "Example draft", draftAttachmentPath: folder.path))
        XCTAssertNil(h.app.selectedRoomID, "a half-filled composer never opens")
        await router(h).route(FocusParams(chatID: "!a", draftText: "Example draft",
                                          draftAttachmentPath: "/nonexistent/made-up.pdf"))
        XCTAssertNil(h.app.selectedRoomID)
        try await h.open("!a")
        XCTAssertEqual(h.conversation.composer.text, "")
        XCTAssertEqual(h.conversation.composer.attachments, [])
    }

    func testTheEnginesNotificationReachesTheRouter() async throws {
        let h = try await start()
        let file = try makeFile("photo.png")
        let router = router(h)
        h.server.notify(method: "app.focus",
                        params: ["chatID": "!a", "draftText": "From a client", "draftAttachmentPath": file.path])
        try await waitUntil { h.conversation.roomID == "!a" && h.conversation.composer.text == "From a client" }
        XCTAssertEqual(h.conversation.composer.attachments.map(\.fileName), ["photo.png"])
        XCTAssertEqual(sends(h), [])
        withExtendedLifetime(router) {}
    }

    /// The engine hears whether Courier is locked, in order, so focus_app can tell its client the truth.
    func testTheEngineIsToldWhenCourierLocksAndUnlocks() async throws {
        struct AlwaysBiometric: BiometricAuthService {
            func canEvaluateBiometricsOrWatch() -> Bool { true }
            func authenticate(reason _: String) async throws -> Bool { true }
        }
        struct NoopLoginItem: LoginItemService {
            func status() -> LoginItemRegistrationStatus { .notRegistered }
            func register() throws {}
            func unregister() throws {}
        }
        let suiteName = "courier.test.focuslock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppLockGate.shared.resetForTesting()
        let lifecycle = SystemLifecycleModel(defaults: defaults, loginItem: NoopLoginItem(),
                                             biometrics: AlwaysBiometric())
        let h = try await start()
        // What the engine was told, in order. Saying the same twice is harmless (a connect and the first read can
        // both say it), so repeats are folded.
        let reports = {
            h.server.received.filter { $0["method"] as? String == "app.setLocked" }
                .compactMap { ($0["params"] as? [String: Any])?["locked"] as? Bool }
                .reduce(into: [Bool]()) { folded, locked in if folded.last != locked { folded.append(locked) } }
        }
        let router = router(h)
        try await waitUntil { reports() == [false] }
        lifecycle.lockNow()
        try await waitUntil { reports() == [false, true] }
        let unlocked = await lifecycle.unlock()
        XCTAssertTrue(unlocked)
        try await waitUntil { reports() == [false, true, false] }
        withExtendedLifetime(router) {}
    }
}
