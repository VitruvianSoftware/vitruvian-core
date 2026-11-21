// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import VitruvianCourierCore
import XCTest

@testable import VitruvianCourier

/// D1 round 1: the inbox menu's Edit Chat… and Report as Spam… do something. Choosing them runs the same calls
/// Chat Info's buttons run, on the chat that was right-clicked.
@MainActor
final class ChatMenuActionsTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for name in suites { ScratchDefaults.suite(named: name)?.removePersistentDomain(forName: name) }
        suites = []
    }

    private func defaults() -> UserDefaults {
        let name = "courier.chatmenu.\(UUID().uuidString)"
        suites.append(name)
        return ScratchDefaults.suite(named: name)!
    }

    private func makeActions(conversationAttached: Bool = true)
        -> (actions: ChatMenuActions, conversation: ConversationModel) {
        let store = defaults()
        let app = AppModel(supervisor: EngineSupervisor(
            enginePath: "/nonexistent/vitruvian-courier-engine",
            dataDir: FileManager.default.temporaryDirectory.appendingPathComponent("vitruvian-courier-snapshots"),
            environment: [:], launcher: FoundationProcessLauncher()))
        let inbox = InboxModel(appModel: app, preferences: InboxPreferences(defaults: store))
        let spaces = SpacesModel(appModel: app, inbox: inbox)
        let conversation = ConversationModel(appModel: app, preferences: ComposerPreferences(defaults: store))
        var actions = ChatMenuActions(inbox: inbox, spaces: spaces, ui: InboxUI(), ids: ["!a"])
        if conversationAttached { actions.conversation = conversation }
        return (actions, conversation)
    }

    private func until(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out waiting") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testEditChatOpensTheEditSheetForTheChat() async throws {
        let (actions, conversation) = makeActions()
        actions.run(.editChat(roomID: "!a"))
        try await until { conversation.activeEditGroupDraft != nil }
        XCTAssertEqual(conversation.activeEditGroupDraft?.roomID, "!a")
    }

    func testReportAsSpamOpensTheReportSheetForTheChat() async throws {
        let (actions, conversation) = makeActions()
        actions.run(.reportSpam(roomID: "!a"))
        try await until { conversation.activeReportSpamDraft != nil }
        XCTAssertEqual(conversation.activeReportSpamDraft?.roomID, "!a")
    }

    func testAHandlerPassedInWinsOverTheConversation() async throws {
        let made = makeActions()
        var actions = made.actions
        let conversation = made.conversation
        var edited: [String] = []
        var reported: [String] = []
        actions.onEditChat = { edited.append($0) }
        actions.onReportSpam = { reported.append($0) }
        actions.run(.editChat(roomID: "!a"))
        actions.run(.reportSpam(roomID: "!a"))
        XCTAssertEqual(edited, ["!a"])
        XCTAssertEqual(reported, ["!a"])
        XCTAssertNil(conversation.activeEditGroupDraft)
        XCTAssertNil(conversation.activeReportSpamDraft)
    }
}
