// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class DetachedWindowModelTests: XCTestCase {
    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    private func makeAppModel() -> AppModel {
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-detached"),
            environment: [:],
            launcher: FakeLauncher { _, _ in }
        )
        return AppModel(supervisor: supervisor)
    }

    func testDetachedWindowRegistryDeduplicatesAndManagesChatSpaceAndThreadWindows() {
        let registry = DetachedWindowRegistry()

        registry.open(.chat(roomID: "!r1"))
        registry.open(.chat(roomID: "!r1")) // duplicate ignored
        registry.open(.space(spaceID: "work"))
        registry.open(.thread(roomID: "!r1", rootEventID: "$root1"))

        XCTAssertEqual(registry.openTargets.count, 3)
        XCTAssertEqual(registry.openTargets[0].id, "chat:!r1")
        XCTAssertEqual(registry.openTargets[1].id, "space:work")
        XCTAssertEqual(registry.openTargets[2].id, "thread:!r1:$root1")

        registry.close(.space(spaceID: "work"))
        XCTAssertEqual(registry.openTargets.map(\.id), ["chat:!r1", "thread:!r1:$root1"])

        registry.closeAll()
        XCTAssertTrue(registry.openTargets.isEmpty)
    }

    func testOpeningSameRoomTwiceFocusesExistingWindowWithoutDuplicating() {
        let appModel = makeAppModel()
        var focusedTargets: [DetachedWindowTarget] = []
        let registry = DetachedWindowRegistry(
            appModel: appModel,
            onFocus: { focusedTargets.append($0) }
        )

        let chatTarget = DetachedWindowTarget.chat(roomID: "!r1")
        registry.open(chatTarget)
        let firstSession = registry.session(for: chatTarget)
        XCTAssertNotNil(firstSession)
        XCTAssertEqual(firstSession?.conversation.roomID, "!r1")
        XCTAssertEqual(registry.openTargets, [chatTarget])
        XCTAssertEqual(focusedTargets, [chatTarget])
        XCTAssertEqual(registry.focusCount(for: chatTarget), 1)
        XCTAssertEqual(registry.focusedTarget, chatTarget)

        // Opening a second target moves focus to the new window.
        let secondTarget = DetachedWindowTarget.chat(roomID: "!r2")
        registry.open(secondTarget)
        XCTAssertEqual(registry.focusedTarget, secondTarget)

        // Opening the first room again focuses the existing window and keeps the same ConversationModel.
        registry.open(chatTarget)
        let secondSession = registry.session(for: chatTarget)
        XCTAssertTrue(firstSession === secondSession)
        XCTAssertTrue(firstSession?.conversation === secondSession?.conversation)
        XCTAssertEqual(registry.openTargets, [chatTarget, secondTarget])
        XCTAssertEqual(registry.focusCount(for: chatTarget), 2)
        XCTAssertEqual(registry.focusedTarget, chatTarget)
        XCTAssertEqual(focusedTargets, [chatTarget, secondTarget, chatTarget])

        // Changing main window selection must not change the detached chat window's roomID.
        appModel.selectedRoomID = "!mainRoom"
        XCTAssertEqual(firstSession?.conversation.roomID, "!r1")
    }

    func testClosingDetachedWindowReleasesItsConversationModel() {
        let appModel = makeAppModel()
        let registry = DetachedWindowRegistry(appModel: appModel)

        weak var weakChatConversation: ConversationModel?
        weak var weakThreadConversation: ConversationModel?
        weak var weakThreadModel: ThreadModel?
        weak var weakSpaceConversation: ConversationModel?
        weak var weakSpaceInbox: InboxModel?

        do {
            let chatTarget = DetachedWindowTarget.chat(roomID: "!leak-chat")
            registry.open(chatTarget)
            let chatSession = registry.session(for: chatTarget)
            XCTAssertNotNil(chatSession)
            weakChatConversation = chatSession?.conversation
            XCTAssertNotNil(weakChatConversation)

            let threadTarget = DetachedWindowTarget.thread(roomID: "!leak-chat", rootEventID: "$root-leak")
            registry.open(threadTarget)
            let threadSession = registry.session(for: threadTarget)
            XCTAssertNotNil(threadSession)
            weakThreadConversation = threadSession?.conversation
            weakThreadModel = threadSession?.thread
            XCTAssertNotNil(weakThreadConversation)
            XCTAssertNotNil(weakThreadModel)
            XCTAssertEqual(threadSession?.thread.roomID, "!leak-chat")
            XCTAssertEqual(threadSession?.thread.rootID, "$root-leak")

            let spaceTarget = DetachedWindowTarget.space(spaceID: "work")
            registry.open(spaceTarget)
            let spaceSession = registry.session(for: spaceTarget)
            XCTAssertNotNil(spaceSession)
            weakSpaceConversation = spaceSession?.conversation
            weakSpaceInbox = spaceSession?.inbox
            XCTAssertNotNil(weakSpaceConversation)
            XCTAssertNotNil(weakSpaceInbox)
            XCTAssertEqual(spaceSession?.inbox?.query.space, "work")

            registry.close(chatTarget)
        }

        XCTAssertNil(weakChatConversation, "Closing a detached chat window must release its ConversationModel")
        XCTAssertNotNil(weakThreadConversation)
        XCTAssertNotNil(weakSpaceConversation)

        registry.closeAll()
        XCTAssertNil(weakThreadConversation, "Closing a detached thread window must release its ConversationModel")
        XCTAssertNil(weakThreadModel, "Closing a detached thread window must release its ThreadModel")
        XCTAssertNil(weakSpaceConversation, "Closing a detached space window must release its ConversationModel")
        XCTAssertNil(weakSpaceInbox, "Closing a detached space window must release its InboxModel")
    }

    func testDetachedWindowsShowAppLockOverlayWhenLocked() async throws {
        let suiteName = "courier.test.detached.lock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bio = FakeBiometricAuthService(available: true, result: .success(true))
        let lifecycle = SystemLifecycleModel(
            defaults: defaults,
            loginItem: FakeLoginItemService(currentStatus: .notRegistered),
            biometrics: bio
        )
        let appModel = makeAppModel()
        let registry = DetachedWindowRegistry(appModel: appModel, lifecycle: lifecycle)

        let chatTarget = DetachedWindowTarget.chat(roomID: "!r1")
        let spaceTarget = DetachedWindowTarget.space(spaceID: "work")
        let threadTarget = DetachedWindowTarget.thread(roomID: "!r1", rootEventID: "$root1")

        registry.open(chatTarget)
        registry.open(spaceTarget)
        registry.open(threadTarget)

        for target in [chatTarget, spaceTarget, threadTarget] {
            XCTAssertFalse(registry.showsLockOverlay(for: target))
        }

        lifecycle.lockApp()
        XCTAssertTrue(lifecycle.isLocked)

        for target in [chatTarget, spaceTarget, threadTarget] {
            XCTAssertTrue(registry.showsLockOverlay(for: target), "Detached window \(target.id) must show lock overlay when app is locked")
        }

        let unlocked = await lifecycle.unlockWithTouchID()
        XCTAssertTrue(unlocked)
        for target in [chatTarget, spaceTarget, threadTarget] {
            XCTAssertFalse(registry.showsLockOverlay(for: target))
        }
    }

    func testDoubleClickChatPreferenceSupportsOpenInNewWindow() throws {
        let suite = "courier.test.inbox.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = InboxPreferences(defaults: defaults)
        prefs.doubleClickChat = .openInNewWindow
        let reloaded = InboxPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.doubleClickChat, .openInNewWindow)
    }

    func testDetachedChatSpaceAndThreadWindowsCopyToInjectedPasteboardAndWireServices() async throws {
        let suite = "courier.test.detached.services.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let appModel = makeAppModel()
        let inboxPrefs = InboxPreferences(defaults: defaults)
        let composerPrefs = ComposerPreferences(defaults: defaults)
        let quickReplies = QuickReplies(defaults: defaults)
        let mainInbox = InboxModel(appModel: appModel, preferences: inboxPrefs)

        final class RecordingPasteboard: TextPasteboard {
            var strings: [String] = []
            func setString(_ text: String) {
                strings.append(text)
            }
        }
        let pasteboard = RecordingPasteboard()
        var openedURLs: [URL] = []

        let registry = DetachedWindowRegistry(
            appModel: appModel,
            mainInbox: mainInbox,
            inboxPreferences: inboxPrefs,
            composerPreferences: composerPrefs,
            quickReplies: quickReplies,
            makePasteboard: { pasteboard },
            openURL: { openedURLs.append($0) }
        )

        let makeTextEvent = { (id: String, room: String, text: String, linkURL: String?) -> Event in
            var content: [String: JSONValue] = [
                "msgtype": .string("m.text"),
                "body": .string(text),
            ]
            if let linkURL {
                content["m.mentiones"] = .object([:])
                content["format"] = .string("org.matrix.custom.html")
                content["formatted_body"] = .string("<a href=\"\(linkURL)\">\(text)</a>")
            }
            return Event(
                eventID: id,
                roomID: room,
                sender: "@alice:courier.local",
                senderName: "Alice Example",
                mine: false,
                type: "m.room.message",
                content: .object(content),
                ts: 1_761_400_000_000,
                seq: 1,
                status: .sent
            )
        }

        // 1. Detached Chat Window (.chat)
        let chatTarget = DetachedWindowTarget.chat(roomID: "!r1")
        registry.open(chatTarget)
        let chatSession = try XCTUnwrap(registry.session(for: chatTarget))
        let chatItems = Timeline.build(
            events: [makeTextEvent("$chat-msg", "!r1", "Hello from detached chat https://example.com/chat", "https://example.com/chat")],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        chatSession.conversation.setSnapshotStateForTesting(roomID: "!r1", items: chatItems)
        await chatSession.messageActions.perform(.copy, on: "$chat-msg", from: .chat)
        XCTAssertEqual(pasteboard.strings.last, "Hello from detached chat https://example.com/chat")

        await chatSession.messageActions.perform(.openFirstLink, on: "$chat-msg", from: .chat)
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.com/chat"])
        XCTAssertTrue(chatSession.conversation.composer.quickReplies === quickReplies)
        XCTAssertTrue(chatSession.messageActions.quickReplies === quickReplies)

        chatSession.conversation.onToast("Detached chat toast")
        XCTAssertEqual(chatSession.hostInbox.toast?.message, "Detached chat toast")

        // 2. Detached Space Window (.space)
        let spaceTarget = DetachedWindowTarget.space(spaceID: "work")
        registry.open(spaceTarget)
        let spaceSession = try XCTUnwrap(registry.session(for: spaceTarget))
        spaceSession.inbox?.select("!r2")
        let spaceItems = Timeline.build(
            events: [makeTextEvent("$space-msg", "!r2", "Hello from detached space", nil)],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        spaceSession.conversation.setSnapshotStateForTesting(roomID: "!r2", items: spaceItems)
        await spaceSession.messageActions.perform(.copy, on: "$space-msg", from: .chat)
        XCTAssertEqual(pasteboard.strings.last, "Hello from detached space")

        // 3. Detached Thread Window (.thread)
        let threadTarget = DetachedWindowTarget.thread(roomID: "!r1", rootEventID: "$root1")
        registry.open(threadTarget)
        let threadSession = try XCTUnwrap(registry.session(for: threadTarget))
        let threadItems = Timeline.build(
            events: [makeTextEvent("$thread-msg", "!r1", "Hello from detached thread", nil)],
            me: "@me:courier.local",
            now: Date(timeIntervalSince1970: 1_761_400_100)
        )
        threadSession.thread.setSnapshotStateForTesting(roomID: "!r1", rootID: "$root1", items: threadItems)
        await threadSession.messageActions.perform(.copy, on: "$thread-msg", from: .thread)
        XCTAssertEqual(pasteboard.strings.last, "Hello from detached thread")
        XCTAssertEqual(
            pasteboard.strings,
            [
                "Hello from detached chat https://example.com/chat",
                "Hello from detached space",
                "Hello from detached thread",
            ]
        )
    }

    func testDetachedWindowScheduledModelTracksDetachedRoomNotMainWindowSelection() {
        let appModel = makeAppModel()
        appModel.selectedRoomID = "!main-room"
        let registry = DetachedWindowRegistry(appModel: appModel)

        let chatTarget = DetachedWindowTarget.chat(roomID: "!detached-chat")
        registry.open(chatTarget)
        let chatSession = registry.session(for: chatTarget)
        XCTAssertEqual(chatSession?.scheduled.roomID, "!detached-chat")

        let spaceTarget = DetachedWindowTarget.space(spaceID: "work")
        registry.open(spaceTarget)
        let spaceSession = registry.session(for: spaceTarget)
        XCTAssertNil(spaceSession?.scheduled.roomID)
        spaceSession?.inbox?.select("!space-chat")
        XCTAssertEqual(spaceSession?.scheduled.roomID, "!space-chat")

        // Changing main window selection must not alter detached ScheduledModel roomID.
        appModel.selectedRoomID = "!other-main-room"
        XCTAssertEqual(chatSession?.scheduled.roomID, "!detached-chat")
        XCTAssertEqual(spaceSession?.scheduled.roomID, "!space-chat")
    }

    func testDetachedWindowTargetCodableAndOnOpenWindowAlias() throws {
        let targets: [DetachedWindowTarget] = [
            .chat(roomID: "!r1"),
            .space(spaceID: "work"),
            .thread(roomID: "!r1", rootEventID: "$root1"),
        ]
        let encoded = try JSONEncoder().encode(targets)
        let decoded = try JSONDecoder().decode([DetachedWindowTarget].self, from: encoded)
        XCTAssertEqual(decoded, targets)

        let registry = DetachedWindowRegistry()
        var openedViaAlias: [DetachedWindowTarget] = []
        registry.onOpenWindow = { openedViaAlias.append($0) }
        registry.open(.chat(roomID: "!r1"))
        XCTAssertEqual(openedViaAlias, [.chat(roomID: "!r1")])
    }
}
