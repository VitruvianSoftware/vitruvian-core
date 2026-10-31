// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Combine
import Foundation

/// The engine's sign-in calls. The app's goes through the engine that is up; tests script one.
public protocol LoginCalling: AnyObject, Sendable {
    /// login.start: the network's first account, a second one beside those linked (`another`), or one of its
    /// accounts again (`accountID`, a `Login.accountID`; never with `another`).
    func start(network: String, flow: String, another: Bool, accountID: String?) async throws -> LoginStep
    func submit(loginID: String, values: [String: String]) async throws -> LoginStep
    /// Waits for the phone. No time limit: a person may take minutes.
    func wait(loginID: String) async throws -> LoginStep
    func cancel(loginID: String) async throws
}

/// The sign-in calls on the engine that is up when each is made.
public final class EngineLoginCaller: LoginCalling {
    /// login.start can wait on the network (Signal asks its server for a code); login.submit can sign in and
    /// connect before it answers (Slack does both).
    static let startTimeout: TimeInterval = 60
    static let submitTimeout: TimeInterval = 120

    private let appModel: AppModel

    public init(appModel: AppModel) {
        self.appModel = appModel
    }

    private func client() async throws -> EngineClient {
        guard let client = await appModel.client else { throw EngineError.notConnected }
        return client
    }

    public func start(network: String, flow: String, another: Bool, accountID: String?) async throws -> LoginStep {
        // Left out unless asked: a plain start stays protocol 4's call.
        try await client().call("login.start", LoginStartParams(network: network, flow: flow,
                                                                another: another ? true : nil, accountID: accountID),
                                timeout: Self.startTimeout)
    }

    public func submit(loginID: String, values: [String: String]) async throws -> LoginStep {
        try await client().call("login.submit", LoginSubmitParams(loginID: loginID, values: values),
                                timeout: Self.submitTimeout)
    }

    public func wait(loginID: String) async throws -> LoginStep {
        try await client().call("login.wait", LoginParams(loginID: loginID))
    }

    public func cancel(loginID: String) async throws {
        let _: Empty = try await client().call("login.cancel", LoginParams(loginID: loginID))
    }
}

/// One network in the "Add a network" picker.
public struct NetworkChoice: Equatable, Identifiable, Sendable {
    public let network: String
    public let displayName: String
    /// The flows to offer, the app's choice first. Only flows the engine reports.
    public let flows: [String]
    /// The account works: linking it again is refused (-32013), so the picker says "Linked" and offers Add Another
    /// Account instead. With several accounts, the first one decides (a plain sign-in signs it in again).
    public let isLinked: Bool
    /// What the network calls each account linked, in the engine's order ("Linked as …"); accounts it hasn't named
    /// yet are left out.
    public let linkedAs: [String]
    /// The engine hasn't started the network yet this session: it can't be picked until it runs ("Starting…").
    public let isStarting: Bool
    /// How many accounts the engine lists for the network, named or not.
    public let accountCount: Int

    public var id: String { network }

    /// What the picker says beside a linked network (02 §1.7): "Linked as +1 555 0101", "Linked as Work and Home",
    /// "Linked: 3 accounts", or "Linked" when no account has a name yet. Two accounts of which one has no name yet
    /// read as a count, so the line never names one account of two as if it were the only one.
    public var linkedLabel: String {
        let count = max(accountCount, linkedAs.count)
        if count >= 3 || (count == 2 && linkedAs.count < 2) {
            return String(localized: "Linked: \(count) accounts")
        }
        if linkedAs.count == 2 { return String(localized: "Linked as \(linkedAs[0]) and \(linkedAs[1])") }
        if let only = linkedAs.first { return String(localized: "Linked as \(only)") }
        return String(localized: "Linked")
    }

    /// The picker's button for a linked network, which signs in beside the accounts linked
    /// (`LoginFlowModel.begin(network:another: true)`).
    public static var addAnotherTitle: String { String(localized: "Add Another Account…") }

    /// What the picker says beside a network that hasn't started yet: it can't be picked until it runs.
    public static var startingLabel: String { String(localized: "Starting…") }
}

/// Telegram's app credentials, checked as the engine checks them (internal/networks telegramSpec): spaces at the
/// ends don't count, api_id is a whole number from 1 to 2^31 − 1, and api_hash is 32 hexadecimal characters.
public enum TelegramSetup {
    public enum Problem: Equatable, Sendable {
        case apiID
        case apiHash
    }

    public static let appsURL = URL(string: "https://my.telegram.org")!

    public static func problems(apiID: String, apiHash: String) -> [Problem] {
        var problems: [Problem] = []
        let id = apiID.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = apiHash.trimmingCharacters(in: .whitespacesAndNewlines)
        let digitsOnly = !id.isEmpty && id.unicodeScalars.allSatisfy { ("0" ... "9").contains($0) }
        if !digitsOnly || (UInt64(id).map { $0 == 0 || $0 >= 1 << 31 } ?? true) { problems.append(.apiID) }
        let hex = hash.unicodeScalars.allSatisfy {
            ("0" ... "9").contains($0) || ("a" ... "f").contains($0) || ("A" ... "F").contains($0)
        }
        if hash.unicodeScalars.count != 32 || !hex { problems.append(.apiHash) }
        return problems
    }
}

/// How long to wait for Telegram to start after the engine is restarted with a pair just saved: look at the
/// accounts every `interval` seconds, at most `attempts` times. `sleep` is the wait between; tests give one that
/// returns at once.
public struct TelegramStartWait: Sendable {
    public var attempts: Int
    public var interval: TimeInterval
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(timeout: TimeInterval, interval: TimeInterval,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                }) {
        self.attempts = max(1, Int((timeout / interval).rounded(.up)))
        self.interval = interval
        self.sleep = sleep
    }

    /// A minute, looking twice a second.
    public static let standard = TelegramStartWait(timeout: 60, interval: 0.5)
}

/// Adding a network, from the picker to "Linked as …", and Telegram's keys when the app has none.
///
/// - The picker lists every network the engine knows, each with the flows the app offers for it, its choice
///   first (`offeredFlows`).
/// - Telegram needs an app ID. A finished Courier carries its own (TelegramBuiltIn), so Telegram goes straight to
///   its QR code. A build without one asks for the pair first, as the first step of the same flow: it is saved in
///   the Keychain, the engine restarts to start Telegram with it, and when Telegram is running the sign-in
///   carries on by itself. If Telegram does not start within a minute, the app says so.
/// - Google Messages first warns that linking it here ends its web session elsewhere; only Continue starts it.
/// - A display step (a QR code, an emoji, a code) waits on the phone with login.wait and shows each next step.
/// - A user_input step checks each value against its pattern and options as it is typed, and sends only the
///   step's own fields. A value the engine refuses keeps the step open with a calm word, for another try.
/// - A cookies step opens the sign-in window, unless a required field can only come from a source the window
///   can't read: then the sign-in is cancelled at once and the app says so (Review Focus 4).
/// - Every way out but a completed sign-in cancels it on the engine: the person closing the sheet or the
///   sign-in window, an unsupported step, a failure. An answer to a call made for a sign-in the person has
///   walked away from is dropped, and if it opened a sign-in, that is cancelled too, so none is left half open.
/// - The engine's own error messages are never shown; known codes get words here, the rest the general words.
@MainActor
public final class LoginFlowModel: ObservableObject {
    public enum Screen: Equatable, Sendable {
        case closed
        case picker
        /// Google Messages' warning, before login.start. Continue starts `flow`.
        case googleWarning(network: String, flow: String)
        /// Waiting for the engine.
        case working(network: String)
        /// A QR code, an emoji or a code to use on the phone; login.wait is in flight.
        case display(network: String, step: LoginStep)
        case input(network: String, step: LoginStep)
        /// The sign-in window is open on the step's page.
        case signIn(network: String, step: LoginStep)
        case linked(network: String, remoteName: String)
        /// The end of a sign-in that did not link: what happened, in the app's words (or an unsupported step's
        /// advice).
        case message(network: String?, text: String)
        /// Telegram's api_id and api_hash, asked for before its sign-in because the app has none of its own.
        /// `flow` is the sign-in to start once Telegram is running.
        case telegramSetup(flow: String)
    }

    /// How a user_input field is typed.
    public enum Entry: Equatable, Sendable {
        case plain
        /// Hidden as typed: passwords and tokens.
        case secure
        /// One of these.
        case picker([String])
    }

    @Published public private(set) var screen: Screen = .closed
    /// The values typed into the input step, by field id.
    @Published public var inputValues: [String: String] = [:]
    /// A calm word under the current step: the engine refused a value, or the Keychain refused Telegram's.
    @Published public private(set) var notice: String?
    /// Under "Linked as …": a sign-in asked to sign one account in again became another account (Ruling 11). Both are
    /// kept, and this says so in Courier's words. Nil otherwise, and from the next sign-in on.
    @Published public private(set) var linkedNote: String?

    private let caller: LoginCalling
    private let accounts: @MainActor () -> [Account]
    private let reloadAccounts: @MainActor () async -> Void
    private let credentials: CredentialStore
    private let telegramCredentials: TelegramCredentialSource
    private let telegramWait: TelegramStartWait
    private let restartEngine: @MainActor () -> Void
    private var subscription: AnyCancellable?
    private weak var observedLifecycle: SystemLifecycleModel?
    private var lockObserver: AnyCancellable?

    /// Bumped by every new sign-in and every ending: an answer for an older one is not this one's.
    private var session = 0
    /// The open sign-in on the engine, once login.start has answered; nil when there is none to cancel.
    private var loginID: String?
    private var network: String?
    /// What the sign-in under way asked login.start for, kept across Google Messages' warning.
    private var another = false
    private var accountID: String?
    /// What is in flight, so `settle()` can wait for it.
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(caller: LoginCalling, accounts: @escaping @MainActor () -> [Account],
                reloadAccounts: @escaping @MainActor () async -> Void, credentials: CredentialStore,
                builtInCredentials: @escaping @Sendable () -> TelegramCredentials? = { TelegramBuiltIn.load() },
                telegramWait: TelegramStartWait = .standard, restartEngine: @escaping @MainActor () -> Void) {
        self.caller = caller
        self.accounts = accounts
        self.reloadAccounts = reloadAccounts
        self.credentials = credentials
        self.telegramCredentials = TelegramCredentialSource(store: credentials, builtIn: builtInCredentials)
        self.telegramWait = telegramWait
        self.restartEngine = restartEngine
        self.lockObserver = NotificationCenter.default
            .publisher(for: SystemLifecycleModel.didLockNotification)
            .sink { [weak self] notification in
                self?.observedLifecycle = notification.object as? SystemLifecycleModel
                self?.dismissAllPresentations()
            }
    }

    public func dismissAllPresentations() {
        if screen != .closed {
            close()
        }
    }

    public var lifecycle: SystemLifecycleModel {
        observedLifecycle ?? AppLockGate.shared.lifecycle
    }

    public var isLocked: Bool {
        !AppLockGate.shared.canPerform(.settingsChange, lifecycle: lifecycle)
    }

    /// The app's: the engine that is up, its accounts, the Keychain and the supervisor.
    public convenience init(appModel: AppModel,
                            credentials: CredentialStore = KeychainStore(service: TelegramCredentials.service)) {
        self.init(caller: EngineLoginCaller(appModel: appModel), accounts: { appModel.accounts },
                  reloadAccounts: { await appModel.refreshAccounts() }, credentials: credentials,
                  restartEngine: { appModel.supervisor.restart() })
        // The picker shows the accounts, which are the app model's.
        subscription = appModel.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - Networks and flows

    /// The app's choice of flows per network, first first (Slack signs in on the web; its email flow is the
    /// other way). Flow ids from the bridges: mautrix-slack login-cookie.go LoginFlowIDAuthToken = "token" and
    /// login-email.go LoginFlowIDEmail = "email"; mautrix-gmessages login.go LoginFlowIDGoogle = "google";
    /// mautrix-whatsapp, mautrix-signal and mautrix-telegram "qr", and mautrix-telegram "phone".
    static let preferredFlows: [String: [String]] = [
        "slack": ["token", "email"],
        "gmessages": ["google"],
        "gchat": ["cookies"],
        "whatsapp": ["qr"],
        "signal": ["qr"],
        "telegram": ["qr", "phone"],
    ]

    /// The flows to offer: the app's choice, of those the engine reports. For a network (or flows) the app has
    /// no choice for, the engine's own, in its order.
    public static func offeredFlows(network: String, reported: [String]) -> [String] {
        let chosen = (preferredFlows[network] ?? []).filter(reported.contains)
        return chosen.isEmpty ? reported : chosen
    }

    /// The states in which an account works, and login.start would be refused as already linked.
    private static let workingStates: Set<AccountState> = [
        .connecting, .backfilling, .connected, .transientDisconnect, .bridgeUnreachable,
    ]

    /// The Add a Network picker's networks. One is linked ("Linked as …", with Add Another Account…) when any of its
    /// accounts works, whichever it is: one signed out beside one that works is still linked.
    public var choices: [NetworkChoice] {
        accounts().map { account in
            let starting = account.state == .starting
            let states = account.logins.isEmpty ? [account.state] : account.logins.map(\.state)
            return NetworkChoice(network: account.network, displayName: account.displayName,
                                 flows: Self.offeredFlows(network: account.network, reported: account.flows),
                                 isLinked: !starting && states.contains(where: Self.workingStates.contains),
                                 linkedAs: account.logins.map(\.remoteName).filter { !$0.isEmpty },
                                 isStarting: starting, accountCount: account.logins.count)
        }
    }

    /// A network's name for people: the engine's, or its id.
    public func displayName(_ network: String) -> String {
        accounts().first { $0.network == network }?.displayName ?? network
    }

    /// A flow's name for people.
    public static func flowName(_ flow: String, network: String) -> String {
        switch (network, flow) {
        case ("slack", "token"): String(localized: "Sign in on the web")
        case ("slack", "email"): String(localized: "Sign in with an emailed code")
        case ("slack", "app"): String(localized: "Slack app tokens")
        case ("gmessages", "google"): String(localized: "Google account")
        case ("gchat", "cookies"): String(localized: "Google account")
        case (_, "qr"): String(localized: "QR code")
        case (_, "phone"): String(localized: "Phone number")
        default: flow
        }
    }

    // MARK: - Starting

    /// "Add a network".
    public func showPicker() {
        guard !isLocked else { return }
        endSignIn()
        screen = .picker
    }

    /// Starts signing in to `network` with `flow`, or the first flow offered for it: its first account, another one
    /// beside those linked ("Add Another Account": `another`), or one of its accounts again (Reconnect on that
    /// account's banner: `accountID`). Google Messages warns first, and Telegram asks for its keys first when the
    /// app has none. A network still starting can't be signed in to yet, and says so. Any sign-in already open here
    /// is cancelled.
    public func begin(network: String, flow: String? = nil, another: Bool = false, accountID: String? = nil) {
        guard !isLocked else { return }
        endSignIn()
        self.another = another && accountID == nil
        self.accountID = accountID
        let account = accounts().first { $0.network == network }
        if account?.state == .starting {
            screen = .message(network: network, text: Self.startingText(displayName(network)))
            return
        }
        let reported = account?.flows ?? []
        guard let flow = flow ?? Self.offeredFlows(network: network, reported: reported).first else {
            screen = .message(network: network, text: Self.cantDoThisStepText)
            return
        }
        if network == "gmessages" {
            screen = .googleWarning(network: network, flow: flow)
            return
        }
        if network == "telegram", !telegramCredentials.hasCredentials {
            screen = .telegramSetup(flow: flow)
            return
        }
        start(network: network, flow: flow)
    }

    /// Continue on Google Messages' warning.
    public func continueAfterWarning() {
        guard !isLocked else { return }
        guard case let .googleWarning(network, flow) = screen else { return }
        start(network: network, flow: flow)
    }

    /// login.start, with what `begin` was asked for.
    private func start(network: String, flow: String) {
        session += 1
        let session = session
        self.network = network
        notice = nil
        linkedNote = nil
        screen = .working(network: network)
        let another = self.another, accountID = self.accountID
        run { [caller] in
            do {
                let step = try await caller.start(network: network, flow: flow, another: another, accountID: accountID)
                self.apply(step, session: session)
            } catch {
                self.failed(error, session: session, starting: true)
            }
        }
    }

    // MARK: - Steps

    private func apply(_ step: LoginStep, session: Int) {
        guard session == self.session, let network else {
            // The person walked away while the engine was answering: leave nothing open. A sign-in that
            // finished all the same linked an account, so the accounts are read again to show it.
            if step.type == .complete {
                run { await self.reloadAccounts() }
            } else {
                cancelOnEngine(step.loginID)
            }
            return
        }
        loginID = step.loginID
        notice = nil
        switch step.type {
        case .displayAndWait:
            screen = .display(network: network, step: step)
            waitForPhone(step.loginID, session: session)
        case .userInput:
            var values: [String: String] = [:]
            for field in step.fields ?? [] {
                if let value = field.defaultValue, !value.isEmpty { values[field.id] = value }
            }
            inputValues = values
            screen = .input(network: network, step: step)
        case .cookies:
            guard let params = step.cookies, CookieCollector.pageURL(params) != nil,
                  CookieCollector.uncapturableFields(params).isEmpty else {
                end(network: network, text: Self.cantDoThisStepText)
                return
            }
            screen = .signIn(network: network, step: step)
        case .complete:
            loginID = nil
            inputValues = [:]
            self.session += 1
            let name = step.remoteName ?? ""
            // Ruling 11: asked to sign one account in again, the person signed in another (another phone's QR
            // code, say). The engine kept the first and added this one; say so, in Courier's words.
            linkedNote = step.otherAccount == true ? otherAccountNote(signedIn: name, network: network) : nil
            screen = .linked(network: network, remoteName: name)
            run { await self.reloadAccounts() }
        case .unsupported:
            let advice = step.instructions ?? ""
            end(network: network, text: advice.isEmpty ? Self.cantDoThisStepText : advice)
        default:
            end(network: network, text: Self.cantDoThisStepText)
        }
    }

    private func waitForPhone(_ loginID: String, session: Int) {
        run { [caller] in
            do {
                let step = try await caller.wait(loginID: loginID)
                self.apply(step, session: session)
            } catch {
                self.failed(error, session: session, starting: false)
            }
        }
    }

    /// How a field is typed: a picker when it has options, hidden for passwords and tokens, else plain.
    public static func entry(for field: LoginField) -> Entry {
        if let options = field.options, !options.isEmpty { return .picker(options) }
        return field.type.isSecret ? .secure : .plain
    }

    /// Whether a typed value fits its field: not empty, one of its options if it has any, and matching its
    /// pattern (somewhere, as Go's regexp.MatchString, which the engine uses). A pattern this app can't compile
    /// is the engine's to check.
    public static func isValid(_ value: String, for field: LoginField) -> Bool {
        guard !value.isEmpty else { return false }
        if let options = field.options, !options.isEmpty, !options.contains(value) { return false }
        guard let pattern = field.pattern, !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else { return true }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private var inputStep: (network: String, step: LoginStep)? {
        if case let .input(network, step) = screen { return (network, step) }
        return nil
    }

    /// Every field of the input step has a value that fits.
    public var canSubmitInput: Bool {
        guard let fields = inputStep?.step.fields else { return false }
        return fields.allSatisfy { Self.isValid(inputValues[$0.id] ?? "", for: $0) }
    }

    /// Sends the input step's values: its own fields only.
    public func submitInput() {
        guard !isLocked else { return }
        guard let (network, step) = inputStep, canSubmitInput, let loginID else { return }
        var values: [String: String] = [:]
        for field in step.fields ?? [] { values[field.id] = inputValues[field.id] }
        submit(values, loginID: loginID, network: network, refusedStep: step)
    }

    /// The sign-in window collected the cookies step's values.
    public func signInCollected(loginID: String, stepID: String, values: [String: String]) {
        guard !isLocked else { return }
        guard case let .signIn(network, step) = screen, step.loginID == loginID, step.stepID == stepID,
              self.loginID == loginID else { return }
        submit(values, loginID: loginID, network: network, refusedStep: nil)
    }

    /// The person closed the sign-in window before it collected anything.
    public func signInWindowClosed(loginID: String, stepID: String) {
        guard case let .signIn(network, step) = screen, step.loginID == loginID, step.stepID == stepID else { return }
        end(network: network, text: Self.windowClosedText(displayName(network)))
    }

    /// - Parameter refusedStep: the step to show again if the engine refuses a value; nil ends the sign-in then.
    private func submit(_ values: [String: String], loginID: String, network: String, refusedStep: LoginStep?) {
        let session = session
        notice = nil
        screen = .working(network: network)
        run { [caller] in
            do {
                let step = try await caller.submit(loginID: loginID, values: values)
                self.apply(step, session: session)
            } catch {
                guard session == self.session else { return }
                if let refusedStep, case .rpc(.badValue, _, _)? = error as? EngineError {
                    // The sign-in stays open on the engine: try again.
                    self.notice = EngineErrorText.text(for: error, fallback: Self.genericText(self.displayName(network)))
                    self.screen = .input(network: network, step: refusedStep)
                    return
                }
                self.failed(error, session: session, starting: false)
            }
        }
    }

    private func failed(_ error: Error, session: Int, starting: Bool) {
        guard session == self.session, let network else { return }
        let name = displayName(network)
        let text: String
        switch error as? EngineError {
        case .rpc(.loginInProgress, _, _)?:
            text = String(localized: "A sign-in for \(name) is already open.")
        case .rpc(.alreadyLinked, _, _)? where accountID != nil:
            text = String(localized: "That \(name) account is already signed in.")
        case .rpc(.alreadyLinked, _, _)?:
            text = String(localized: "\(name) is already linked.")
        case .rpc(.notRunning, _, _)? where accounts().first(where: { $0.network == network })?.state == .starting:
            text = Self.startingText(name)
        case .rpc(.notRunning, _, _)?:
            text = String(localized: "\(name) isn’t running.")
        default:
            text = EngineErrorText.text(for: error, fallback: Self.genericText(name))
        }
        // A start that failed opened nothing; anything later is cancelled, which is harmless if it is over.
        if starting { loginID = nil }
        end(network: network, text: text)
    }

    // MARK: - Ending

    /// The person closed the sheet: whatever sign-in is open is cancelled.
    public func close() {
        endSignIn()
        notice = nil
        screen = .closed
    }

    /// Ends the sign-in with a message, cancelling it on the engine.
    private func end(network: String?, text: String) {
        endSignIn()
        screen = .message(network: network, text: text)
    }

    /// Drops what is in flight for the current sign-in and cancels it on the engine if it is open.
    private func endSignIn() {
        session += 1
        notice = nil
        linkedNote = nil
        // Nothing typed (a password, say) outlives its sign-in.
        inputValues = [:]
        if let loginID { cancelOnEngine(loginID) }
        loginID = nil
    }

    private func cancelOnEngine(_ loginID: String) {
        run { [caller] in try? await caller.cancel(loginID: loginID) }
    }

    // MARK: - Telegram

    /// Checks and saves Telegram's keys, restarts the engine so it starts Telegram with them, and carries on into
    /// Telegram's sign-in once Telegram is running. False, with a notice, when they don't fit or the Keychain
    /// refused them; nothing is saved then, and the keys screen stays.
    @discardableResult
    public func saveTelegram(apiID: String, apiHash: String) -> Bool {
        guard !isLocked else { return false }
        guard case let .telegramSetup(flow) = screen else { return false }
        guard TelegramSetup.problems(apiID: apiID, apiHash: apiHash).isEmpty else {
            notice = String(localized: "Check both values: api_id is a whole number and api_hash is 32 letters and digits, as shown at my.telegram.org.")
            return false
        }
        let saved = TelegramCredentials(apiID: apiID.trimmingCharacters(in: .whitespacesAndNewlines),
                                        apiHash: apiHash.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try saved.save(to: credentials)
        } catch {
            notice = String(localized: "Courier couldn’t save these in your Keychain.")
            return false
        }
        session += 1
        let session = session
        network = "telegram"
        notice = nil
        screen = .working(network: "telegram")
        restartEngine()
        run { await self.startAfterTelegramRuns(flow: flow, session: session) }
        return true
    }

    /// The engine reads the keys only when it starts, so Telegram is not running until the restart is done. Looks
    /// at the accounts until it is, then starts its sign-in; says so, calmly, if it does not come up in time.
    private func startAfterTelegramRuns(flow: String, session: Int) async {
        let wait = telegramWait
        for _ in 0 ..< wait.attempts {
            await reloadAccounts()
            guard session == self.session else { return }
            if let telegram = accounts().first(where: { $0.network == "telegram" }), Self.hasStarted(telegram.state) {
                start(network: "telegram", flow: flow)
                return
            }
            do {
                try await wait.sleep(wait.interval)
            } catch {
                return
            }
            guard session == self.session else { return }
        }
        end(network: "telegram", text: Self.telegramDidNotStartText)
    }

    /// A network the engine started: not "not started", and past the bridge's own "starting".
    private static func hasStarted(_ state: AccountState) -> Bool {
        state != .notStarted && state != .starting
    }

    // MARK: - Words

    static var telegramDidNotStartText: String {
        String(localized: "Telegram didn’t start. Courier has saved your keys, so try again from Add a network in a minute. If it still doesn’t start, quit Courier and open it again.")
    }

    /// Ruling 11's note: the account signed in, and the one asked for, by name when both names are known.
    private func otherAccountNote(signedIn: String, network: String) -> String {
        let asked = accounts().first { $0.network == network }?.logins.first { $0.accountID == accountID }?.remoteName
        guard !signedIn.isEmpty, let asked, !asked.isEmpty else {
            return String(localized: "That signed in a different account, so both are now linked.")
        }
        return String(localized: "That signed in \(signedIn) instead of \(asked). Both are linked now.")
    }

    /// A network the engine hasn't started yet this session (login.start is -32016 until it runs).
    static func startingText(_ name: String) -> String {
        String(localized: "\(name) is still starting. Try again in a moment.")
    }

    public static var cantDoThisStepText: String {
        String(localized: "This sign-in needs a step Courier can’t do yet.")
    }

    public static func windowClosedText(_ name: String) -> String {
        String(localized: "The sign-in window was closed, so signing in to \(name) was cancelled.")
    }

    static func genericText(_ name: String) -> String {
        String(localized: "Courier couldn’t sign in to \(name). Try again.")
    }

    // MARK: - Tasks

    private func run(_ body: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task {
            await body()
            self.tasks[id] = nil
        }
    }

    /// Returns once nothing is in flight. For tests; a wait on the phone never ends by itself.
    func settle() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
