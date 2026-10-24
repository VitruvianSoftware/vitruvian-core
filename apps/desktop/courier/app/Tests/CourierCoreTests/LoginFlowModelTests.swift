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
        /// What the accounts are now; a test changes it as the engine would.
        var accounts: [Account] = []
        /// Runs at each reload, after it is counted.
        var onReload: () -> Void = {}
    }

    /// Courier's own Telegram app ID, as a finished app carries it. Made up.
    private nonisolated static let builtIn = TelegramCredentials(apiID: "4242424", apiHash: String(repeating: "0a", count: 16))

    /// A wait for Telegram of three looks that takes no time.
    private nonisolated static let quickWait = TelegramStartWait(timeout: 3, interval: 1, sleep: { _ in
        await Task.yield()
    })

    private nonisolated static let accounts = [
        Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .running),
        Account(network: "telegram", displayName: "Telegram", flows: ["qr", "phone"], state: .notStarted,
                notStarted: "Telegram needs its own app credentials"),
        Account(network: "gmessages", displayName: "Google Messages", flows: ["google"], state: .running),
        Account(network: "slack", displayName: "Slack", flows: ["email", "token", "app"], state: .running),
        Account(network: "signal", displayName: "Signal", flows: ["qr"], state: .connected, remoteName: "+1 555 0100"),
    ]

    /// - Parameter builtIn: the app ID packaged into the app; by default it has one, like a finished Courier.
    private func make(accounts: [Account] = LoginFlowModelTests.accounts,
                      builtIn: TelegramCredentials? = LoginFlowModelTests.builtIn,
                      keychain: [String: String] = [:]) -> Harness {
        let caller = ScriptedLoginCaller()
        let credentials = InMemoryCredentialStore(keychain)
        let counts = Counts()
        counts.accounts = accounts
        let model = LoginFlowModel(caller: caller, accounts: { counts.accounts },
                                   reloadAccounts: { counts.reloads += 1; counts.onReload() },
                                   credentials: credentials, builtInCredentials: { builtIn },
                                   telegramWait: Self.quickWait, restartEngine: { counts.restarts += 1 })
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

    // MARK: - Several accounts on a network

    /// "Linked as …" names one or two accounts and counts three or more (02 §1.7).
    func testLinkedLabelNamesOneOrTwoAccountsAndCountsMore() {
        func choice(_ names: [String], count: Int) -> NetworkChoice {
            NetworkChoice(network: "slack", displayName: "Slack", flows: ["token"], isLinked: true, linkedAs: names,
                          isStarting: false, accountCount: count)
        }
        XCTAssertEqual(choice([], count: 0).linkedLabel, "Linked")
        XCTAssertEqual(choice([], count: 1).linkedLabel, "Linked", "no name yet")
        XCTAssertEqual(choice(["Work"], count: 1).linkedLabel, "Linked as Work")
        XCTAssertEqual(choice(["Work", "Home"], count: 2).linkedLabel, "Linked as Work and Home")
        XCTAssertEqual(choice(["Work"], count: 2).linkedLabel, "Linked: 2 accounts")
        XCTAssertEqual(choice(["Work", "Home", "Club"], count: 3).linkedLabel, "Linked: 3 accounts")
        XCTAssertEqual(choice(["Work", "Home"], count: 4).linkedLabel, "Linked: 4 accounts")
    }

    /// One WhatsApp account linked: the picker says who it is linked as, and Add Another Account signs in beside it
    /// (login.start's `another`), Google Messages' warning first where it applies.
    func testAddAnotherAccountStartsWithAnother() async {
        var accounts = Self.accounts
        accounts[0] = Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .connected,
                              remoteName: "+1 555 0101",
                              logins: [Login(accountID: "a1", remoteName: "+1 555 0101", state: .connected)])
        accounts[2] = Account(network: "gmessages", displayName: "Google Messages", flows: ["google"],
                              state: .connected, remoteName: "Pixel",
                              logins: [Login(accountID: "g1", remoteName: "Pixel", state: .connected),
                                       Login(accountID: "g2", remoteName: "", state: .connected)])
        let harness = make(accounts: accounts)
        let whatsapp = harness.model.choices[0]
        XCTAssertTrue(whatsapp.isLinked)
        XCTAssertEqual(whatsapp.linkedAs, ["+1 555 0101"])
        XCTAssertFalse(whatsapp.isStarting)
        XCTAssertEqual(harness.model.choices[2].linkedAs, ["Pixel"], "an account with no name yet isn't listed by name")
        XCTAssertEqual(harness.model.choices[1].linkedAs, [], "Telegram has no account")
        XCTAssertEqual(whatsapp.linkedLabel, "Linked as +1 555 0101")
        XCTAssertEqual(harness.model.choices[2].accountCount, 2)
        XCTAssertEqual(harness.model.choices[2].linkedLabel, "Linked: 2 accounts",
                       "one of two named reads as a count, never as the only account")

        var done = step(.complete, remoteName: "+1 555 0102")
        done.accountID = "b2"
        harness.caller.answer("start", qr("code-1"))
        harness.caller.answer("wait", done)
        harness.model.begin(network: "whatsapp", another: true)
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.first, .start(network: "whatsapp", flow: "qr", another: true))
        XCTAssertEqual(harness.model.screen, .linked(network: "whatsapp", remoteName: "+1 555 0102"))
        XCTAssertNil(harness.model.linkedNote, "a second account, as asked")

        // Google Messages warns first; Continue still adds one beside the others.
        let google = make(accounts: accounts)
        google.caller.answer("start", step(.unsupported, instructions: "Made-up advice"))
        google.model.begin(network: "gmessages", another: true)
        google.model.continueAfterWarning()
        await google.model.settle()
        XCTAssertEqual(google.caller.calls.first, .start(network: "gmessages", flow: "google", another: true))
    }

    /// Reconnect on one account's banner signs that account in again (login.start's `account_id`). If the person
    /// signs in a different account instead, both are kept, and Courier says so in its own words (Ruling 11).
    func testReconnectStartsWithTheLoginID() async {
        let harness = make()
        var other = step(.complete, remoteName: "+1 555 0109")
        other.accountID = "c3"
        other.otherAccount = true
        harness.caller.answer("start", qr("code-1"))
        harness.caller.answer("wait", other)
        harness.model.begin(network: "whatsapp", accountID: "a1")
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.first, .start(network: "whatsapp", flow: "qr", accountID: "a1"))
        XCTAssertEqual(harness.model.screen, .linked(network: "whatsapp", remoteName: "+1 555 0109"))
        XCTAssertEqual(harness.model.linkedNote, "That signed in a different account, so both are now linked.",
                       "the account asked for has no name Courier knows: the plain words")

        // The next sign-in starts with no note.
        harness.caller.answer("start", qr("code-2"))
        harness.model.begin(network: "whatsapp")
        XCTAssertNil(harness.model.linkedNote)
        harness.model.close()
        await harness.model.settle()

        // Both names known: the note names them.
        var accounts = Self.accounts
        accounts[0] = Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .loggedOut,
                              logins: [Login(accountID: "a1", remoteName: "+1 555 0101", state: .loggedOut)])
        let named = make(accounts: accounts)
        named.caller.answer("start", qr("code-1"))
        named.caller.answer("wait", other)
        named.model.begin(network: "whatsapp", accountID: "a1")
        await named.model.settle()
        XCTAssertEqual(named.model.linkedNote, "That signed in +1 555 0109 instead of +1 555 0101. Both are linked now.")

        // The same account signed in again: no note.
        let same = make()
        var back = step(.complete, remoteName: "+1 555 0101")
        back.accountID = "a1"
        back.otherAccount = false
        same.caller.answer("start", qr("code-1"))
        same.caller.answer("wait", back)
        same.model.begin(network: "whatsapp", accountID: "a1")
        await same.model.settle()
        XCTAssertNil(same.model.linkedNote)

        // An account that doesn't need signing in again (-32013 with account_id): said for that account.
        let fine = make()
        fine.caller.fail("start", rpc(.alreadyLinked))
        fine.model.begin(network: "whatsapp", accountID: "a1")
        await fine.model.settle()
        XCTAssertEqual(fine.model.screen, .message(network: "whatsapp", text: "That WhatsApp account is already signed in."))
    }

    /// A network the engine hasn't started yet this session can't be signed in to (-32016 until it runs): the picker
    /// says it is starting and starts nothing; a sign-in that meets it anyway says so in the same words.
    func testAStartingNetworkCannotBePicked() async {
        var accounts = Self.accounts
        accounts[0] = Account(network: "whatsapp", displayName: "WhatsApp", flows: ["qr"], state: .starting,
                              logins: [Login(accountID: "a1", remoteName: "+1 555 0101", state: .connected)])
        let harness = make(accounts: accounts)
        XCTAssertTrue(harness.model.choices[0].isStarting)
        XCTAssertFalse(harness.model.choices[0].isLinked, "starting is not linked yet")
        XCTAssertEqual(harness.model.choices[0].linkedAs, ["+1 555 0101"], "who it was linked as is still known")
        XCTAssertFalse(harness.model.choices[3].isStarting)
        harness.model.begin(network: "whatsapp")
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls, [])
        XCTAssertEqual(harness.model.screen, .message(network: "whatsapp", text: "WhatsApp is still starting. Try again in a moment."))

        // A banner read a moment before the network went back to starting: the engine says -32016, in the same words.
        var running = accounts
        running[0].state = .connected
        let raced = make(accounts: running)
        raced.caller.fail("start", rpc(.notRunning))
        raced.model.begin(network: "whatsapp", accountID: "a1")
        raced.counts.accounts = accounts // the engine's answer and the accounts read after it say starting
        await raced.model.settle()
        XCTAssertEqual(raced.model.screen, .message(network: "whatsapp", text: "WhatsApp is still starting. Try again in a moment."))
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

    func testTypedValuesAreClearedWhenTheSignInEnds() async {
        let harness = make()
        harness.caller.answer("start", step(.userInput, fields: [inputField("password", type: .password)]))
        harness.model.begin(network: "telegram", flow: "phone")
        await harness.model.settle()
        harness.model.inputValues["password"] = "made-up-secret"
        harness.model.close()
        XCTAssertEqual(harness.model.inputValues, [:], "a closed sign-in keeps nothing typed")

        harness.caller.answer("start", step(.userInput, fields: [inputField("password", type: .password)]))
        harness.caller.answer("submit", step(.complete, remoteName: "Made-up"))
        harness.model.begin(network: "telegram", flow: "phone")
        await harness.model.settle()
        harness.model.inputValues["password"] = "made-up-secret"
        harness.model.submitInput()
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .linked(network: "telegram", remoteName: "Made-up"))
        XCTAssertEqual(harness.model.inputValues, [:], "nor does a finished one")
    }

    func testASignInThatCompletesAfterCancelStillReloadsAccounts() async {
        let harness = make()
        harness.caller.holdStart()
        harness.model.begin(network: "whatsapp")
        try? await waitUntil { harness.caller.calls.contains(.start(network: "whatsapp", flow: "qr")) }
        harness.model.close()
        harness.caller.releaseStart(step(.complete, remoteName: "Made-up"))
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .closed, "the person walked away; nothing reopens")
        XCTAssertEqual(harness.counts.reloads, 1, "but the account it linked shows")
        XCTAssertFalse(harness.caller.calls.contains(.cancel(loginID: "L1")), "a finished sign-in has nothing to cancel")
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

    func testTelegramKeysAreCheckedAsTheEngineChecksThem() {
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
    }

    /// A Courier that carries its own app ID never shows the keys screen: Telegram goes straight to its QR code.
    func testTelegramWithABuiltInAppIDGoesStraightToTheQRCode() async {
        let harness = make()
        harness.caller.answer("start", qr("tg-code"))
        harness.caller.answer("wait", step(.complete, remoteName: "Made-up"))
        harness.model.begin(network: "telegram")
        XCTAssertEqual(harness.model.screen, .working(network: "telegram"))
        await harness.model.settle()
        // The QR code was asked for at once, and waited on: nothing in between asked for keys.
        XCTAssertEqual(harness.caller.calls, [.start(network: "telegram", flow: "qr"), .wait(loginID: "L1")])
        XCTAssertEqual(harness.model.screen, .linked(network: "telegram", remoteName: "Made-up"))
        XCTAssertEqual(harness.counts.restarts, 0)
    }

    /// The pair the person saved before counts as much as the built-in one.
    func testTelegramWithKeysInTheKeychainGoesStraightToTheQRCode() async {
        let harness = make(builtIn: nil, keychain: [
            TelegramCredentials.apiIDAccount: "1234567", TelegramCredentials.apiHashAccount: madeUpHash,
        ])
        harness.caller.answer("start", qr("tg-code"))
        harness.caller.answer("wait", step(.complete, remoteName: "Made-up"))
        harness.model.begin(network: "telegram")
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.first, .start(network: "telegram", flow: "qr"))
        XCTAssertEqual(harness.model.screen, .linked(network: "telegram", remoteName: "Made-up"))
        XCTAssertEqual(harness.counts.restarts, 0)
    }

    /// A built-in pair that does not fit is no pair: the person is asked.
    func testAnInvalidBuiltInAppIDMeansTheKeysAreAsked() {
        let harness = make(builtIn: TelegramCredentials(apiID: "0", apiHash: "not hex"))
        harness.model.begin(network: "telegram")
        XCTAssertEqual(harness.model.screen, .telegramSetup(flow: "qr"))
    }

    func testTelegramWithoutKeysAsksForThemFirstThenRestartsWaitsAndLinks() async {
        let harness = make(builtIn: nil)
        harness.caller.answer("start", qr("tg-code"))
        harness.caller.answer("wait", step(.complete, remoteName: "Made-up"))
        harness.model.begin(network: "telegram")
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .telegramSetup(flow: "qr"), "the keys come first")
        XCTAssertEqual(harness.caller.calls, [], "no sign-in is started before there are keys")

        // Values that don't fit save nothing and keep the screen.
        XCTAssertFalse(harness.model.saveTelegram(apiID: "nope", apiHash: "nope"))
        XCTAssertEqual(harness.counts.restarts, 0)
        XCTAssertNil(TelegramCredentials.load(from: harness.credentials), "nothing is saved until both fit")
        XCTAssertEqual(harness.model.screen, .telegramSetup(flow: "qr"))
        XCTAssertNotNil(harness.model.notice)

        // Telegram comes up on the third look: not started, then starting, then running. The sign-in has not
        // been started before that.
        var callsWhenRunning: [ScriptedLoginCaller.Call]?
        let counts = harness.counts
        let caller = harness.caller
        counts.onReload = {
            let states: [AccountState] = [.notStarted, .starting, .running]
            let state = states[min(counts.reloads, states.count) - 1]
            counts.accounts = LoginFlowModelTests.accounts.map { account in
                var account = account
                if account.network == "telegram" { account.state = state }
                return account
            }
            if state == .running, callsWhenRunning == nil { callsWhenRunning = caller.calls }
        }
        XCTAssertTrue(harness.model.saveTelegram(apiID: " 12345 ", apiHash: madeUpHash))
        XCTAssertEqual(TelegramCredentials.load(from: harness.credentials),
                       TelegramCredentials(apiID: "12345", apiHash: madeUpHash))
        XCTAssertEqual(harness.counts.restarts, 1, "the engine restarts to start Telegram with the keys")
        XCTAssertEqual(harness.model.screen, .working(network: "telegram"))
        XCTAssertNil(harness.model.notice)
        await harness.model.settle()

        XCTAssertEqual(callsWhenRunning, [], "nothing started before Telegram was running")
        XCTAssertEqual(harness.counts.reloads, 4, "three looks at Telegram, and one more when the link completed")
        XCTAssertEqual(harness.caller.calls, [.start(network: "telegram", flow: "qr"), .wait(loginID: "L1")],
                       "straight into Telegram's QR code, with no second look at the keys")
        XCTAssertEqual(harness.model.screen, .linked(network: "telegram", remoteName: "Made-up"))
        XCTAssertEqual(harness.counts.restarts, 1)
    }

    /// Another way in ("Other ways" on the picker) is the sign-in the keys lead on to.
    func testTheFlowChosenSurvivesTheKeysScreen() async {
        let harness = make(builtIn: nil)
        let counts = harness.counts
        counts.onReload = {
            counts.accounts = LoginFlowModelTests.accounts.map { account in
                var account = account
                if account.network == "telegram" { account.state = .running }
                return account
            }
        }
        harness.caller.answer("start", step(.userInput, fields: [inputField("phone_number", type: .phoneNumber)]))
        harness.model.begin(network: "telegram", flow: "phone")
        XCTAssertEqual(harness.model.screen, .telegramSetup(flow: "phone"))
        XCTAssertTrue(harness.model.saveTelegram(apiID: "12345", apiHash: madeUpHash))
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls, [.start(network: "telegram", flow: "phone")])
        guard case .input(network: "telegram", step: _) = harness.model.screen else {
            return XCTFail("expected the phone number step, got \(harness.model.screen)")
        }
    }

    /// Telegram never comes up: the wait is bounded and ends with a plain message, not a spinner.
    func testTelegramThatDoesNotStartEndsWithAClearMessage() async {
        let harness = make(builtIn: nil)
        harness.model.begin(network: "telegram")
        XCTAssertTrue(harness.model.saveTelegram(apiID: "12345", apiHash: madeUpHash))
        await harness.model.settle()

        XCTAssertEqual(harness.counts.reloads, 3, "it looked as often as the wait allows, and no more")
        XCTAssertEqual(harness.caller.calls, [], "no sign-in was started")
        XCTAssertEqual(harness.model.screen,
                       .message(network: "telegram", text: LoginFlowModel.telegramDidNotStartText))
        XCTAssertTrue(LoginFlowModel.telegramDidNotStartText.contains("saved your keys"))
        XCTAssertNotNil(TelegramCredentials.load(from: harness.credentials), "the keys stay saved")
        XCTAssertEqual(harness.counts.restarts, 1)

        // Trying again does not ask for them again.
        harness.caller.answer("start", qr("tg-code"))
        harness.caller.answer("wait", step(.complete, remoteName: "Made-up"))
        harness.model.begin(network: "telegram")
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls, [.start(network: "telegram", flow: "qr"), .wait(loginID: "L1")])
    }

    func testClosingTheSheetWhileTelegramStartsLeavesNothingStarted() async {
        let harness = make(builtIn: nil)
        let counts = harness.counts
        counts.onReload = {
            counts.accounts = LoginFlowModelTests.accounts.map { account in
                var account = account
                if account.network == "telegram" { account.state = .running }
                return account
            }
        }
        harness.model.begin(network: "telegram")
        XCTAssertTrue(harness.model.saveTelegram(apiID: "12345", apiHash: madeUpHash))
        harness.model.close()
        await harness.model.settle()
        XCTAssertEqual(harness.model.screen, .closed)
        XCTAssertEqual(harness.caller.calls, [], "the person walked away: no sign-in is started")
    }

    func testSavingKeysOutsideTheKeysScreenDoesNothing() {
        let harness = make(builtIn: nil)
        XCTAssertFalse(harness.model.saveTelegram(apiID: "12345", apiHash: madeUpHash))
        XCTAssertNil(TelegramCredentials.load(from: harness.credentials))
        XCTAssertEqual(harness.counts.restarts, 0)
    }

    /// The keys screen is for Telegram alone.
    func testOtherNetworksNeverAskForTelegramsKeys() async {
        let harness = make(builtIn: nil)
        harness.caller.answer("start", qr("code-1"))
        harness.caller.answer("wait", step(.complete, remoteName: "Made-up"))
        harness.model.begin(network: "whatsapp")
        await harness.model.settle()
        XCTAssertEqual(harness.caller.calls.first, .start(network: "whatsapp", flow: "qr"))
    }
}

/// The engine's sign-in calls, scripted. `start`, `submit` and `wait` take their answers in order; a `wait` with
/// none left waits until the sign-in is cancelled, then fails as the engine's would.
final class ScriptedLoginCaller: LoginCalling, @unchecked Sendable {
    enum Call: Equatable {
        /// `another` and `accountID` as login.start would carry them.
        case start(network: String, flow: String, another: Bool = false, accountID: String? = nil)
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

    func start(network: String, flow: String, another: Bool, accountID: String?) async throws -> LoginStep {
        let call = Call.start(network: network, flow: flow, another: another, accountID: accountID)
        let hold = lock.withLock { () -> Bool in
            defer { holdingStart = false }
            return holdingStart
        }
        if hold {
            // Held, then written down, under one lock: a test that sees the call can release it.
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    heldStart = continuation
                    _calls.append(call)
                }
            }
        }
        record(call)
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
