// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// "Also hide that you're typing?" is asked by one presenter, once, however Incognito was turned on.
@MainActor
final class HideTypingQuestionTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
    }

    /// A conversation with the plan, its settings in a defaults suite of its own; its engine is never started.
    private func conversation() -> (ConversationModel, ComposerPreferences) {
        let name = "courier.hide-typing.\(UUID().uuidString)"
        suites.append(name)
        let preferences = ComposerPreferences(defaults: UserDefaults(suiteName: name)!)
        let supervisor = EngineSupervisor(
            enginePath: "/Applications/Courier.app/Contents/Helpers/courier-engine",
            dataDir: URL(fileURLWithPath: "/tmp/courier-test-data"), environment: [:],
            launcher: FakeLauncher { _, _ in }, credentials: InMemoryCredentialStore(), clientName: "Courier/test",
            timing: FakeTime().timing())
        let conversation = ConversationModel(appModel: AppModel(supervisor: supervisor))
        conversation.preferences = preferences
        conversation.isEntitled = { _ in true }
        return (conversation, preferences)
    }

    /// Lets the main actor run what is waiting on it (the question is asked on its next turn).
    private func settle() async {
        for _ in 0 ..< 20 { await Task.yield() }
    }

    func testTheCommandBarsTurnOnIsAskedOnceAndHideTurnsTypingOff() async throws {
        let (conversation, preferences) = conversation()
        var answers: [@MainActor (Bool) -> Void] = []
        let question = HideTypingQuestion(conversation: conversation) { answers.append($0); return {} }
        let login = LoginFlowModel(caller: ScriptedLoginCaller(), accounts: { [] }, reloadAccounts: {},
                                   credentials: InMemoryCredentialStore(), builtInCredentials: { nil },
                                   restartEngine: {})
        try XCTUnwrap(CommandSet.accounts(login, conversation).first { $0.id == "Turn on incognito mode" }).run()
        XCTAssertTrue(answers.isEmpty, "never inside the change that raised it")
        try await waitUntil { answers.count == 1 }
        XCTAssertTrue(question.isAsking)

        // Off and on again (Settings, say) while it is up: the first is taken down (B11), the second asked once.
        conversation.setIncognito(false)
        conversation.setIncognito(true)
        try await waitUntil { answers.count == 2 }
        await settle()
        XCTAssertEqual(answers.count, 2, "never asked twice at once")

        answers[0](false) // the one taken down: its late answer changes nothing
        XCTAssertTrue(question.isAsking)
        XCTAssertTrue(preferences.showTyping)
        answers[1](true)
        XCTAssertFalse(question.isAsking)
        XCTAssertFalse(conversation.asksToHideTyping)
        XCTAssertFalse(preferences.showTyping, "Hide Typing")
        XCTAssertTrue(preferences.incognito)
    }

    func testKeepShowingLeavesTypingAndTheNextTurnOnAsksAgain() async throws {
        let (conversation, preferences) = conversation()
        var answers: [@MainActor (Bool) -> Void] = []
        let question = HideTypingQuestion(conversation: conversation) { answers.append($0); return {} }
        conversation.setIncognito(true)
        try await waitUntil { answers.count == 1 }
        answers[0](false)
        XCTAssertTrue(preferences.showTyping, "Keep Showing")
        XCTAssertFalse(question.isAsking)

        conversation.setIncognito(false)
        conversation.setIncognito(true)
        try await waitUntil { answers.count == 2 }
        answers[1](true)
        XCTAssertFalse(preferences.showTyping)
    }

    /// B11: Incognito turned off while the question is up takes it down (the presenter's dismiss runs once), and a
    /// late answer from it changes nothing. Turned on again, it is asked again.
    func testTurningIncognitoOffTakesTheQuestionDown() async throws {
        let (conversation, preferences) = conversation()
        var answers: [@MainActor (Bool) -> Void] = []
        var dismissed = 0
        let question = HideTypingQuestion(conversation: conversation) { answer in
            answers.append(answer)
            return { dismissed += 1 }
        }
        conversation.setIncognito(true)
        try await waitUntil { answers.count == 1 }
        XCTAssertEqual(dismissed, 0)

        conversation.setIncognito(false)
        XCTAssertEqual(dismissed, 1, "taken down")
        XCTAssertFalse(question.isAsking)
        answers[0](true) // as an alert being taken down may answer
        XCTAssertTrue(preferences.showTyping, "a late answer changes nothing")
        XCTAssertEqual(dismissed, 1)

        conversation.setIncognito(true)
        try await waitUntil { answers.count == 2 }
        answers[1](true)
        XCTAssertFalse(preferences.showTyping)
        XCTAssertEqual(dismissed, 1, "an answered question is not taken down")
    }

    /// Turned on and straight off again before the question came up: it isn't asked. Turned off while it is up: the
    /// late answer changes nothing.
    func testAWithdrawnQuestionIsNotAskedAndItsLateAnswerDoesNothing() async throws {
        let (conversation, preferences) = conversation()
        var answers: [@MainActor (Bool) -> Void] = []
        let question = HideTypingQuestion(conversation: conversation) { answers.append($0); return {} }
        conversation.setIncognito(true)
        conversation.setIncognito(false)
        await settle()
        XCTAssertTrue(answers.isEmpty)
        XCTAssertFalse(question.isAsking)

        conversation.setIncognito(true)
        try await waitUntil { answers.count == 1 }
        conversation.setIncognito(false)
        answers[0](true)
        XCTAssertTrue(preferences.showTyping, "Incognito was turned off before the answer")
        XCTAssertFalse(question.isAsking)
    }
}
