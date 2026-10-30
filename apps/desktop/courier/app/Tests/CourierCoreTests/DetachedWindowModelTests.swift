// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation
import XCTest

@MainActor
final class DetachedWindowModelTests: XCTestCase {
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
}
