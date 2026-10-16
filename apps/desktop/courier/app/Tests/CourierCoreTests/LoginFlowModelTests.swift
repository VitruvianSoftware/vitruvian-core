// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import CourierCore

/// Adding a network: the picker, the steps, the sign-in window's ends and Telegram's set-up, against a scripted
/// engine that answers what the test says and writes down what it was asked. Every value here is made up.
@MainActor
final class LoginFlowModelTests: XCTestCase {
    // MARK: - Harness

    private struct Harness {
        let model: LoginFlowModel
        let caller: ScriptedLoginCaller
        let credentials: InMemoryCredentialStore
        let counts: Counts
    }

    private final class Counts {
        var reloads = 0
        var restarts = 0
    }

    private nonisolated static let accounts = [
        Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .running),
        Account(network: "telegram", displayName: "Telegram", flows: ["qr", "phone"], state: .notStarted,
                notStarted: "Telegram needs its own app credentials"),
        Account(network: "gmessages", displayName: "Google Messages", flows: ["google"], state: .running),
        Account(network: "slack", displayName: "Slack", flows: ["email", "token", "app"], state: .running),
        Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected, remoteName: "+1 555 0100"),
    ]

    private func make(accounts: [Account] = LoginFlowModelTests.accounts) -> Harness {
        let caller = ScriptedLoginCaller()
        let credentials = InMemoryCredentialStore()
        let counts = Counts()
        let model = LoginFlowModel(caller: caller, accounts: { accounts },
                                   reloadAccounts: { counts.reloads += 1 }, credentials: credentials,
                                   restartEngine: { counts.restarts += 1 })
        return Harness(model: model, caller: caller, credentials: credentials, counts: counts)
    }

    private func step(_ type: LoginStepType, id: String = "L1", stepID: String = "s1", instructions: String? = nil,
                      display: LoginDisplay? = nil, fields: [LoginField]? = nil, cookies: LoginCookies? = nil,
                      remoteName: String? = nil) -> LoginStep {
        LoginStep(loginID: id, stepID: stepID, type: type, instructions: instructions, display: display,
                  fields: fields, cookies: cookies, remoteName: remoteName)
    }

    private func qr(_ data: String, stepID: String = "qr") -> LoginStep {
        step(.displayAndWait, stepID: stepID, display: LoginDisplay(kind: .qr, data: data, imageURL: nil))
    }

    private func inputField(_ id: String, type: LoginFieldType = .username, pattern: String? = nil,
                            options: [String]? = nil, defaultValue: String? = nil) -> LoginField {
        LoginField(id: id, name: id.capitalized, description: "", type: type, pattern: pattern, options: options,
                   defaultValue: defaultValue)
    }

    private func cookieStep(_ fields: [LoginCookieField], stepID: String = "cookies") -> LoginStep {
        step(.cookies, stepID: stepID,
             cookies: LoginCookies(url: "https://example.invalid/signin", userAgent: nil, waitForURL: nil,
                                   extractJS: "new Promise(r => r({}))", fields: fields))
    }

    private func rpc(_ code: RPCErrorCode) -> EngineError { .rpc(code, message: "x", reason: nil) }

    // MARK: - Choosing a network and a flow

    func testFlowsPreferredFirstAndOnlyThoseReported() {
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "slack", reported: ["email", "token", "app"]),
                       ["token", "email"], "Slack signs in on the web first, by email second")
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "telegram", reported: ["qr", "phone"]), ["qr", "phone"])
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "telegram", reported: ["phone"]), ["phone"],
                       "a flow the engine does not report is never offered")
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "gmessages", reported: ["google"]), ["google"])
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "whatsapp", reported: ["qr"]), ["qr"])
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "signal", reported: ["qr"]), ["qr"])
        // A network or flows this app has no preference for: the engine's, in its order.
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "newnet", reported: ["b", "a"]), ["b", "a"])
        XCTAssertEqual(LoginFlowModel.offeredFlows(network: "slack", reported: ["app"]), ["app"])

        let harness = make()
        harness.model.showPicker()
        XCTAssertEqual(harness.model.screen, .picker)
        let choices = harness.model.choices
        XCTAssertEqual(choices.map(\.network), ["whatsapp", "telegram", "gmessages", "slack", "signal"])
        XCTAssertEqual(choices.first { $0.network == "slack" }?.flows, ["token", "email"])
        XCTAssertEqual(choices.first { $0.network == "telegram" }?.needsSetUp, true)
        XCTAssertEqual(choices.first { $0.network == "signal" }?.isLinked, true)
        XCTAssertEqual(choices.first { $0.network == "whatsapp" }?.isLinked, false)
    }

    func testGoogleMessagesWarnsBeforeStart() async {
        let harness = make()
        harness.model.begin(network: "gmessages")
        XCTAssertEqual(harness.model.screen, .googleWarning(network: "gmessages", flow: "google"))
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls, [], "nothing starts before the person says Continue")

        // Cancel ends it with nothing sent.
        harness.model.close()
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .closed)
        XCTAssertEqual(harness.caller.calls, [])

        // Continue starts the google flow.
        harness.caller.answer("start", cookieStep([
            LoginCookieField(id: "SID", required: true,
                             sources: [LoginCookieSource(type: .cookie, name: "SID", cookieDomain: ".example.com")],
                             pattern: nil),
        ]))
        harness.model.begin(network: "gmessages")
        harness.model.continueAfterWarning()
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls, [.start(network: "gmessages", flow: "google")])
        guard case .signIn(network: "gmessages", step: _) = harness.model.screen else {
            return XCTFail("expected the sign-in window, got \(harness.model.screen)")
        }

        // Other networks start at once, with their first flow, or the one asked for.
        let other = make()
        other.caller.answer("start", qr("code-1"))
        other.caller.answer("wait", step(.complete, remoteName: "Made-up"))
        other.model.begin(network: "whatsapp")
        await other.model.settle()
        XCTAssertEqual(other.caller.calls.first, .start(network: "whatsapp", flow: "qr"))
        let phone = make()
        phone.caller.answer("start", step(.userInput, fields: [inputField("phone_number", type: .phoneNumber)]))
        phone.model.begin(network: "telegram", flow: "phone")
        await phone.model.settle()
        XCTAssertEqual(phone.caller.calls, [.start(network: "telegram", flow: "phone")])
    }

    // MARK: - Steps

    func testDisplayStepWaitsAndShowsEachNextStep() async {
        let harness = make()
        harness.caller.answer("start", qr("code-1"))
        harness.caller.answer("wait", qr("code-2", stepID: "qr-2"))
        harness.caller.answer("wait", step(.complete, stepID: "done", remoteName: "Made-up Name"))
        harness.model.begin(network: "whatsapp")
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls, [
            .start(network: "whatsapp", flow: "qr"), .wait(loginID: "L1"), .wait(loginID: "L1"),
        ])
        XCTAssertEqual(harness.model.screen, .linked(network: "whatsapp", remoteName: "Made-up Name"))
        XCTAssertEqual(harness.counts.reloads, 1, "the accounts are read again once linked")
    }

    func testUserInputValidatesPattern() async {
        let harness = make()
        harness.caller.answer("start", step(.userInput, fields: [
            inputField("phone_number", type: .phoneNumber, pattern: #"^\+[0-9]{6,15}$"#),
            inputField("region", type: .select, options: ["One", "Two"], defaultValue: "Two"),
        ]))
        harness.model.begin(network: "telegram", flow: "phone")
        await harness.model.settle()
        guard case let .input(network: "telegram", step: shown) = harness.model.screen,
              let fields = shown.fields else { return XCTFail("expected the input step") }
        XCTAssertEqual(harness.model.inputValues, ["region": "Two"], "a default value is filled in")

        let phone = fields[0]
        XCTAssertFalse(LoginFlowModel.isValid("", for: phone), "a field is never left empty")
        XCTAssertFalse(LoginFlowModel.isValid("555 0100", for: phone))
        XCTAssertTrue(LoginFlowModel.isValid("+15550100", for: phone))
        XCTAssertFalse(LoginFlowModel.isValid("Three", for: fields[1]), "an option not on the list")
        XCTAssertTrue(LoginFlowModel.isValid("One", for: fields[1]))
        // A pattern this app can't read is the engine's to check.
        XCTAssertTrue(LoginFlowModel.isValid("x", for: inputField("odd", pattern: "(")))

        harness.model.inputValues["phone_number"] = "555 0100"
        XCTAssertFalse(harness.model.canSubmitInput)
        harness.model.submitInput()
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.count, 1, "nothing is sent while a value does not fit")

        harness.model.inputValues["phone_number"] = "+15550100"
        harness.model.inputValues["stray"] = "not a field"
        XCTAssertTrue(harness.model.canSubmitInput)
        // The engine refuses the first value: the step stays, with a calm word, for another try.
        harness.caller.fail("submit", rpc(.badValue))
        harness.model.submitInput()
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.last,
                       .submit(loginID: "L1", values: ["phone_number": "+15550100", "region": "Two"]),
                       "only the step's own fields are sent")
        guard case .input = harness.model.screen else { return XCTFail("the step stays open after a refusal") }
        XCTAssertNotNil(harness.model.notice)
        XCTAssertFalse(harness.caller.calls.contains(.cancel(loginID: "L1")))

        harness.caller.answer("submit", step(.complete, remoteName: "Made-up"))
        harness.model.submitInput()
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .linked(network: "telegram", remoteName: "Made-up"))
        XCTAssertNil(harness.model.notice)
    }

    func testSecretFieldsUseSecureEntry() {
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("password", type: .password)), .secure)
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("token", type: .token)), .secure)
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("user", type: .username)), .plain)
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("code", type: .twoFactorCode)), .plain)
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("phone", type: .phoneNumber)), .plain)
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("team", type: .select, options: ["A", "B"])),
                       .picker(["A", "B"]))
        // Options make a picker whatever the field's type.
        XCTAssertEqual(LoginFlowModel.entry(for: inputField("x", type: .domain, options: ["a.example"])),
                       .picker(["a.example"]))
    }

    func testUnsupportedStepCancelsWithAdvice() async {
        let harness = make()
        harness.caller.answer("start", step(.unsupported, instructions: "Choose a different sign-in method."))
        harness.model.begin(network: "whatsapp")
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .message(network: "whatsapp", text: "Choose a different sign-in method."))
        XCTAssertEqual(harness.caller.calls.last, .cancel(loginID: "L1"))
    }

    func testUncapturableCookieStepCancelsWithoutOpeningTheWindow() async {
        let harness = make()
        harness.caller.answer("start", cookieStep([
            LoginCookieField(id: "bearer", required: true,
                             sources: [LoginCookieSource(type: .requestHeader, name: "Authorization", cookieDomain: nil)],
                             pattern: nil),
        ]))
        harness.model.begin(network: "slack")
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen,
                       .message(network: "slack", text: LoginFlowModel.cantDoThisStepText))
        XCTAssertEqual(harness.caller.calls, [.start(network: "slack", flow: "token"), .cancel(loginID: "L1")])
    }

    func testCollectedCookiesAreSubmittedThenTheNextStepShows() async {
        let harness = make()
        harness.caller.answer("start", cookieStep([
            LoginCookieField(id: "cookie_token", required: true,
                             sources: [LoginCookieSource(type: .cookie, name: "d", cookieDomain: "slack.com")],
                             pattern: nil),
        ]))
        harness.caller.answer("submit", step(.complete, stepID: "done", remoteName: "Made-up Team"))
        harness.model.begin(network: "slack")
        await harness.model.settle()
        guard case let .signIn(network: "slack", step: shown) = harness.model.screen else {
            return XCTFail("expected the sign-in window")
        }
        // A report from a window for another step is not this one's.
        harness.model.signInCollected(loginID: "L1", stepID: "other", values: ["cookie_token": "wrong"])
        harness.model.signInWindowClosed(loginID: "L0", stepID: shown.stepID)
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.count, 1)

        harness.model.signInCollected(loginID: "L1", stepID: shown.stepID, values: ["cookie_token": "xoxd-a%2F"])
        // The window closing after it collected is not an early close.
        harness.model.signInWindowClosed(loginID: "L1", stepID: shown.stepID)
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.last, .submit(loginID: "L1", values: ["cookie_token": "xoxd-a%2F"]))
        XCTAssertFalse(harness.caller.calls.contains(.cancel(loginID: "L1")))
        XCTAssertEqual(harness.model.screen, .linked(network: "slack", remoteName: "Made-up Team"))
    }

    func testClosingSignInWindowCancelsLogin() async {
        let harness = make()
        harness.caller.answer("start", cookieStep([
            LoginCookieField(id: "cookie_token", required: true,
                             sources: [LoginCookieSource(type: .cookie, name: "d", cookieDomain: "slack.com")],
                             pattern: nil),
        ]))
        harness.model.begin(network: "slack")
        await harness.model.settle()
        guard case let .signIn(network: "slack", step: shown) = harness.model.screen else {
            return XCTFail("expected the sign-in window")
        }
        harness.model.signInWindowClosed(loginID: shown.loginID, stepID: shown.stepID)
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.last, .cancel(loginID: "L1"))
        XCTAssertEqual(harness.model.screen, .message(network: "slack", text: LoginFlowModel.windowClosedText("Slack")))

        // A report that comes after is too late to send anything.
        harness.model.signInCollected(loginID: "L1", stepID: shown.stepID, values: ["cookie_token": "late"])
        await harness.model.settle()
        XCTAssertFalse(harness.caller.calls.contains { if case .submit = $0 { true } else { false } })
    }

    func testClosingWhileWaitingCancelsAndDropsLateAnswers() async {
        let harness = make()
        harness.caller.answer("start", qr("code-1"))
        // No answer for wait: it waits until the sign-in is cancelled.
        harness.model.begin(network: "whatsapp")
        try? await waitUntil { harness.caller.calls.contains(.wait(loginID: "L1")) }
        harness.model.close()
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .closed)
        XCTAssertTrue(harness.caller.calls.contains(.cancel(loginID: "L1")))

        // An answer to a start the person walked away from is cancelled too: no half-open sign-in.
        let late = make()
        late.caller.holdStart()
        late.model.begin(network: "whatsapp")
        try? await waitUntil { late.caller.calls.contains(.start(network: "whatsapp", flow: "qr")) }
        late.model.close()
        late.caller.releaseStart(qr("code-1"))
        await late.model.settle()
        try? await waitUntil { late.caller.calls.contains(.cancel(loginID: "L1")) }
        XCTAssertEqual(late.model.screen, .closed)
        XCTAssertFalse(late.caller.calls.contains(.wait(loginID: "L1")))
    }

    func testStartErrorsSayWhatHappened() async {
        let harness = make()
        harness.caller.fail("start", rpc(.loginInProgress))
        harness.model.begin(network: "slack")
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .message(network: "slack", text: "A sign-in for Slack is already open."))

        harness.caller.fail("start", rpc(.alreadyLinked))
        harness.model.begin(network: "whatsapp")
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .message(network: "whatsapp", text: "WhatsApp is already linked."))

        // Anything else gets words, never the engine's own message.
        harness.caller.fail("start", EngineError.rpc(.internalError, message: "engine words", reason: nil))
        harness.model.begin(network: "whatsapp")
        await harness.model.settle()
        guard case let .message(network: "whatsapp", text: text) = harness.model.screen else {
            return XCTFail("expected a message")
        }
        XCTAssertFalse(text.contains("engine words"))
        XCTAssertFalse(text.isEmpty)
        XCTAssertFalse(harness.caller.calls.contains { if case .cancel = $0 { true } else { false } },
                       "a start that failed left nothing to cancel")
    }

    func testAWaitThatFailsEndsTheSignIn() async {
        let harness = make()
        harness.caller.answer("start", qr("code-1"))
        harness.caller.fail("wait", rpc(.unknownLogin))
        harness.model.begin(network: "signal")
        await harness.model.settle()
        guard case let .message(network: "signal", text: text) = harness.model.screen else {
            return XCTFail("expected a message, got \(harness.model.screen)")
        }
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(harness.caller.calls.last, .cancel(loginID: "L1"), "cancelling is harmless, and sure")
    }

    // MARK: - Telegram

    /// 32 hexadecimal characters, upper and lower case, made up.
    private let madeUpHash = String(repeating: "0a1B", count: 8)

    func testTelegramSetupValidatesSavesAndRestarts() {
        XCTAssertEqual(TelegramSetup.problems(apiID: "", apiHash: ""), [.apiID, .apiHash])
        XCTAssertEqual(TelegramSetup.problems(apiID: "0", apiHash: String(repeating: "a", count: 32)), [.apiID])
        XCTAssertEqual(TelegramSetup.problems(apiID: "-5", apiHash: String(repeating: "a", count: 32)), [.apiID])
        XCTAssertEqual(TelegramSetup.problems(apiID: "12ab", apiHash: String(repeating: "a", count: 32)), [.apiID])
        XCTAssertEqual(TelegramSetup.problems(apiID: "2147483648", apiHash: String(repeating: "a", count: 32)),
                       [.apiID], "under 2^31, as the engine reads it")
        XCTAssertEqual(TelegramSetup.problems(apiID: "2147483647", apiHash: String(repeating: "a", count: 32)), [])
        XCTAssertEqual(TelegramSetup.problems(apiID: "12345", apiHash: String(repeating: "g", count: 32)), [.apiHash])
        XCTAssertEqual(TelegramSetup.problems(apiID: "12345", apiHash: String(repeating: "a", count: 31)), [.apiHash])
        XCTAssertEqual(TelegramSetup.problems(apiID: " 12345 ", apiHash: " \(madeUpHash) "), [],
                       "spaces around a pasted value don't count, as in the engine")

        let harness = make()
        harness.model.showTelegramSetup()
        XCTAssertEqual(harness.model.screen, .telegramSetup)
        XCTAssertFalse(harness.model.saveTelegram(apiID: "nope", apiHash: "nope"))
        XCTAssertEqual(harness.counts.restarts, 0)
        XCTAssertNil(TelegramCredentials.load(from: harness.credentials), "nothing is saved until both fit")

        XCTAssertTrue(harness.model.saveTelegram(apiID: " 12345 ", apiHash: madeUpHash))
        XCTAssertEqual(TelegramCredentials.load(from: harness.credentials),
                       TelegramCredentials(apiID: "12345", apiHash: madeUpHash))
        XCTAssertEqual(harness.counts.restarts, 1)
        guard case let .message(network: "telegram", text: text) = harness.model.screen else {
            return XCTFail("expected a confirmation")
        }
        XCTAssertFalse(text.contains("12345"), "the values are never shown after saving")
        XCTAssertFalse(text.contains(madeUpHash))
    }
}

/// The engine's sign-in calls, scripted. `start`, `submit` and `wait` take their answers in order; a `wait` with
/// none left waits until the sign-in is cancelled, then fails as the engine's would.
final class ScriptedLoginCaller: LoginCalling, @unchecked Sendable {
    enum Call: Equatable {
        case start(network: String, flow: String)
        case submit(loginID: String, values: [String: String])
        case wait(loginID: String)
        case cancel(loginID: String)
    }

    private let lock = NSLock()
    private var answers: [String: [Result<LoginStep, EngineError>]] = [:]
    private var _calls: [Call] = []
    private var waiting: [String: CheckedContinuation<LoginStep, Error>] = [:]
    private var heldStart: CheckedContinuation<LoginStep, Error>?
    private var holdingStart = false

    var calls: [Call] { lock.withLock { _calls } }

    func answer(_ method: String, _ step: LoginStep) {
        lock.withLock { answers[method, default: []].append(.success(step)) }
    }

    func fail(_ method: String, _ error: EngineError) {
        lock.withLock { answers[method, default: []].append(.failure(error)) }
    }

    /// The next start waits until `releaseStart`.
    func holdStart() { lock.withLock { holdingStart = true } }

    func releaseStart(_ step: LoginStep) {
        let held = lock.withLock { () -> CheckedContinuation<LoginStep, Error>? in
            defer { heldStart = nil }
            return heldStart
        }
        held?.resume(returning: step)
    }

    private func next(_ method: String) -> Result<LoginStep, EngineError>? {
        lock.withLock {
            guard var queue = answers[method], !queue.isEmpty else { return nil }
            let first = queue.removeFirst()
            answers[method] = queue
            return first
        }
    }

    private func record(_ call: Call) { lock.withLock { _calls.append(call) } }

    func start(network: String, flow: String) async throws -> LoginStep {
        record(.start(network: network, flow: flow))
        let hold = lock.withLock { () -> Bool in
            defer { holdingStart = false }
            return holdingStart
        }
        if hold {
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock { heldStart = continuation }
            }
        }
        guard let answer = next("start") else { throw EngineError.badResponse }
        return try answer.get()
    }

    func submit(loginID: String, values: [String: String]) async throws -> LoginStep {
        record(.submit(loginID: loginID, values: values))
        guard let answer = next("submit") else { throw EngineError.badResponse }
        return try answer.get()
    }

    func wait(loginID: String) async throws -> LoginStep {
        record(.wait(loginID: loginID))
        if let answer = next("wait") { return try answer.get() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiting[loginID] = continuation }
        }
    }

    func cancel(loginID: String) async throws {
        record(.cancel(loginID: loginID))
        let waiter = lock.withLock { waiting.removeValue(forKey: loginID) }
        waiter?.resume(throwing: EngineError.rpc(.unknownLogin, message: "no sign-in", reason: nil))
    }
}
