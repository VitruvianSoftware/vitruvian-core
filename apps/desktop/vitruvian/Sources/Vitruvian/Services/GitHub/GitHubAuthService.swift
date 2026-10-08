// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

// Connecting GitHub (design spec §2.2, §3.2, §6).
//
// For the store that reads GitHub with the token (package B), the whole
// contract is `GitHubTokenProviding`, which `GitHubAuthService.shared`
// conforms to:
//
//   @MainActor protocol GitHubTokenProviding: AnyObject {
//       func currentToken() -> String?          // nil while signed out
//       func handleUnauthorized()               // call on any 401: drops the token, signs out
//       var signedInChanges: AnyPublisher<Bool, Never> { get }  // true once signed in; replays the current value
//   }
//
// Take it as `any GitHubTokenProviding` in an initializer, so a test hands in
// its own. Open the stream when `signedInChanges` says true, close it when it
// says false, and read `currentToken()` for each request rather than keeping
// a copy: a disconnect or a 401 drops it. Nothing else in this file is part
// of the contract.

import AppKit
import AuthenticationServices
import Combine
import Foundation
import os
import VitruvianCore

// MARK: - Interfaces

/// What another service needs from the sign-in. See the file header.
@MainActor
package protocol GitHubTokenProviding: AnyObject {
    /// The signed-in user's token, or nil.
    func currentToken() -> String?
    /// GitHub or the relay answered 401: the token is dead. Drops it and signs out.
    func handleUnauthorized()
    /// Whether someone is signed in, now and on every change.
    var signedInChanges: AnyPublisher<Bool, Never> { get }
}

/// One HTTP exchange. The app sends through `URLSession`; tests answer
/// themselves, so no test reaches the network.
package protocol GitHubAuthTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

package struct URLSessionGitHubAuthTransport: GitHubAuthTransport {
    private let session: URLSession

    package init(session: URLSession = .shared) {
        self.session = session
    }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// The person closed the sign-in window.
package struct GitHubWebAuthCancelled: Error, Sendable {
    package init() {}
}

/// Shows GitHub's authorize page and hands back the redirect it ends on.
/// The app uses `ASWebAuthenticationSession`; tests never open a browser.
@MainActor
package protocol GitHubWebAuthPresenting: AnyObject {
    /// The callback URL, or `GitHubWebAuthCancelled` when the person closed
    /// the window, or `GitHubAuthError.browserFailed`.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
    /// Closes a window still open. `authenticate` then throws `GitHubWebAuthCancelled`.
    func cancel()
}

/// `ASWebAuthenticationSession` with the browser's own cookies, so a browser
/// already signed in to GitHub shows one "Authorize" button.
@MainActor
package final class SystemGitHubWebAuthPresenter: NSObject, GitHubWebAuthPresenting,
                                                   ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    package override init() {
        super.init()
    }

    package func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        cancel()
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let completion: @Sendable (URL?, (any Error)?) -> Void = { url, error in
                if let url {
                    once.resume(.success(url))
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    once.resume(.failure(GitHubWebAuthCancelled()))
                } else {
                    once.resume(.failure(GitHubAuthError.browserFailed))
                }
            }
            let session: ASWebAuthenticationSession
            if #available(macOS 14.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme),
                                                     completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme,
                                                     completionHandler: completion)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                once.resume(.failure(GitHubAuthError.browserFailed))
            }
        }
    }

    package func cancel() {
        session?.cancel()
        session = nil
    }

    package func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
    }
}

/// A continuation that the session's completion and a failed start may both
/// try to finish; only the first one counts.
private final class ResumeOnce: @unchecked Sendable {
    // Guarded by `lock`.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?

    init(_ continuation: CheckedContinuation<URL, any Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<URL, any Error>) {
        let pending: CheckedContinuation<URL, any Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}

// MARK: - State

package enum GitHubAuthState: Equatable, Sendable {
    case signedOut
    /// GitHub's authorize page is open.
    case authorizing
    /// "Use a code instead": the code to type at `verificationURL`.
    case deviceFlow(userCode: String, verificationURL: URL)
    /// Redeeming the code, or checking a saved token with GitHub.
    case exchanging
    case signedIn(login: String)
    case failed(GitHubAuthError)
}

// MARK: - Service

/// Signs in to GitHub and keeps the token (design spec §2.2):
///
/// - `connect()`: GitHub's authorize page in `ASWebAuthenticationSession`;
///   the redirect's `code` goes to the relay's `POST /auth/exchange` with the
///   attempt's `state` and `verifier` (`GitHubOAuthState`), which only this
///   app holds.
/// - `connectWithCode()`: the device flow, driven by Core's
///   `GitHubDeviceFlowState`. It needs no relay.
/// - `disconnect()`: a best-effort `POST /auth/revoke`, then the Keychain
///   item goes.
///
/// A token is saved before `GET /user` names its login. When GitHub cannot
/// be reached for that, the token stays and Settings offers to try again.
@MainActor
package final class GitHubAuthService: ObservableObject, GitHubTokenProviding {
    package static let shared = GitHubAuthService(
        store: KeychainGitHubTokenStore(), transport: URLSessionGitHubAuthTransport(),
        presenter: SystemGitHubWebAuthPresenter())

    package static let callbackScheme = "vitruvian"
    package static let webURL = URL(string: "https://github.com")!
    package static let apiURL = URL(string: "https://api.github.com")!
    package static let deviceGrantType = "urn:ietf:params:oauth:grant-type:device_code"
    /// Whether the authorize URL also carries GitHub's own PKCE
    /// (`code_challenge` = `state`, S256). GitHub supports it, and once it is
    /// sent GitHub refuses the code without `code_verifier`. The relay's
    /// exchange (`github.go`, `Exchange`) sends only client id, secret and
    /// code, so this stays off until the relay forwards the verifier; the
    /// relay's own `sha256(verifier) == state` check already binds the code
    /// to this app.
    package static let sendsPKCE = false
    /// Where the GitHub CLI keeps its login.
    package static let defaultCLIHostsURL = URL(
        fileURLWithPath: ("~/.config/gh/hosts.yml" as NSString).expandingTildeInPath)
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vitruvian",
                                    category: "github-auth")

    @Published package private(set) var state: GitHubAuthState = .signedOut {
        didSet { signedIn.send(isSignedIn) }
    }

    private let store: any GitHubTokenStore
    private let transport: any GitHubAuthTransport
    private let presenter: any GitHubWebAuthPresenting
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let randomBytes: @Sendable (Int) -> [UInt8]
    private let cliHostsURL: URL
    private let signedIn = CurrentValueSubject<Bool, Never>(false)
    private var token: String?
    private var tokenLoaded = false
    private var attempt: Task<Void, Never>?
    /// Set by `disconnect()`: the person signed out on purpose, so the GitHub
    /// CLI login must not sign them straight back in. Lasts until relaunch.
    private var cliAutoConnectSuppressed = false
    /// The last token GitHub answered 401 to. Auto-connect never retries it,
    /// so a dead CLI token cannot loop 401 → signed out → sync → 401.
    private var rejectedToken: String?

    /// `now` and `sleep` pace the device flow; tests pass a clock that jumps.
    /// `cliHostsURL` is the GitHub CLI's `hosts.yml`; tests point it at a file of their own.
    package init(store: any GitHubTokenStore, transport: any GitHubAuthTransport,
                 presenter: any GitHubWebAuthPresenting, defaults: UserDefaults = .standard,
                 now: @escaping @Sendable () -> Date = { Date() },
                 sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                     try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                 },
                 randomBytes: @escaping @Sendable (Int) -> [UInt8] = { GitHubOAuthState.systemRandomBytes($0) },
                 cliHostsURL: URL = GitHubAuthService.defaultCLIHostsURL) {
        self.store = store
        self.transport = transport
        self.presenter = presenter
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.randomBytes = randomBytes
        self.cliHostsURL = cliHostsURL
    }

    // MARK: Reading

    package var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    /// A token is kept, whether or not GitHub has confirmed it this session.
    package var hasSavedToken: Bool {
        loadTokenIfNeeded()
        return token != nil
    }

    /// The App's client ID, or nil while none is set.
    package var clientID: String? {
        let value = defaults[Preferences.githubClientID].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// The relay's base URL, or nil when the preference is not an http(s) URL.
    package var relayURL: URL? { Self.relayURL(from: defaults[Preferences.githubRelayURL]) }

    package static func relayURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Installed and switched on.
    package static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.notchGitHub.isAvailable(in: defaults) && defaults[Preferences.notchGitHubEnabled]
    }

    package func currentToken() -> String? {
        loadTokenIfNeeded()
        return token
    }

    package var signedInChanges: AnyPublisher<Bool, Never> {
        signedIn.removeDuplicates().eraseToAnyPublisher()
    }

    // MARK: Lifecycle

    /// The feature runtime's binding. Switched on, a saved token is checked
    /// with GitHub so the login shows; with no saved token, a GitHub CLI
    /// login (`hosts.yml`) signs in with no click, unless the person
    /// disconnected this session or GitHub already refused that token.
    /// Switched off or uninstalled, a sign-in in progress stops. The token
    /// itself stays: reinstalling finds it.
    package func syncWithPreferences() {
        guard Self.isEnabled(in: defaults) else {
            stopAttempt()
            if !isSignedIn { state = .signedOut }
            return
        }
        guard state == .signedOut else { return }
        loadTokenIfNeeded()
        if let token {
            start { service in await service.confirm(token) }
        } else if state == .signedOut, !cliAutoConnectSuppressed,
                  let detected = detectedCLIAccount, detected.token != rejectedToken {
            connectWithToken(detected.token)
        }
    }

    /// Checks the saved token with GitHub again, after it could not be reached.
    package func retry() {
        loadTokenIfNeeded()
        guard let token else { state = .signedOut; return }
        start { service in await service.confirm(token) }
    }

    /// Stops a sign-in in progress.
    package func cancel() {
        stopAttempt()
        state = .signedOut
    }

    // MARK: CLI & Token Sign-In

    /// Reads credentials from the GitHub CLI's `hosts.yml`
    /// (`~/.config/gh/hosts.yml` unless the initializer named another) if present.
    package var detectedCLIAccount: (login: String, token: String)? {
        guard let content = try? String(contentsOf: cliHostsURL, encoding: .utf8) else { return nil }
        var user: String?
        var token: String?
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("user:") {
                user = trimmed.replacingOccurrences(of: "user:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("oauth_token:") {
                token = trimmed.replacingOccurrences(of: "oauth_token:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        if let token, !token.isEmpty {
            return (login: user ?? "CLI User", token: token)
        }
        return nil
    }

    /// 1-click connect using the local GitHub CLI token.
    package func connectWithGitHubCLI() {
        guard let detected = detectedCLIAccount else {
            state = .failed(.gitHubRefused(status: 404))
            return
        }
        connectWithToken(detected.token)
    }

    /// Connect with a Personal Access Token or fine-grained token.
    package func connectWithToken(_ rawToken: String) {
        let trimmed = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stopAttempt()
        state = .exchanging
        start { service in await service.finishSignIn(with: trimmed) }
    }

    // MARK: Browser sign-in

    package func connect() {
        guard let clientID else { state = .failed(.notConfigured); return }
        guard let relay = relayURL else { state = .failed(.invalidRelayURL); return }
        let oauth = GitHubOAuthState.generate(randomBytes: randomBytes)
        let url = oauth.authorizeURL(clientID: clientID, redirectURI: GitHubOAuthState.redirectURI,
                                     pkce: Self.sendsPKCE)
        stopAttempt()
        state = .authorizing
        start { service in await service.signInInBrowser(url: url, oauth: oauth, relay: relay) }
    }

    private func signInInBrowser(url: URL, oauth: GitHubOAuthState, relay: URL) async {
        let callback: URL
        do {
            callback = try await presenter.authenticate(url: url, callbackScheme: Self.callbackScheme)
        } catch is GitHubWebAuthCancelled {
            if !Task.isCancelled { state = .signedOut }
            return
        } catch {
            if !Task.isCancelled { state = .failed(error as? GitHubAuthError ?? .browserFailed) }
            return
        }
        guard !Task.isCancelled else { return }
        let code: String
        switch oauth.code(fromCallback: callback) {
        case .failure(let reason):
            state = .failed(.callback(reason))
            return
        case .success(let value):
            code = value
        }
        state = .exchanging
        do {
            let token = try await exchange(code: code, oauth: oauth, relay: relay)
            guard !Task.isCancelled else { return }
            await finishSignIn(with: token)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(error as? GitHubAuthError ?? .relayUnreachable(host: Self.host(relay)))
        }
    }

    /// `POST <relay>/auth/exchange {code, state, verifier}` → `{access_token, …}`.
    private func exchange(code: String, oauth: GitHubOAuthState, relay: URL) async throws -> String {
        let host = Self.host(relay)
        var request = URLRequest(url: relay.appendingPathComponent("auth/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            ExchangeRequest(code: code, state: oauth.state, verifier: oauth.verifier))
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw GitHubAuthError.relayUnreachable(host: host)
        }
        if response.statusCode == 200 {
            guard let body = try? JSONDecoder().decode(TokenResponse.self, from: data),
                  let token = body.accessToken, !token.isEmpty else {
                throw GitHubAuthError.relayRefused(host: host, reason: "no_token")
            }
            return token
        }
        let refusal = try? JSONDecoder().decode(RelayError.self, from: data)
        // A gateway in front of a relay that is down answers 5xx without the relay's JSON.
        guard let refusal, let error = refusal.error else {
            if response.statusCode >= 500 { throw GitHubAuthError.relayUnreachable(host: host) }
            throw GitHubAuthError.relayRefused(host: host, reason: "HTTP \(response.statusCode)")
        }
        if error == "state_mismatch" { throw GitHubAuthError.callback(.stateMismatch) }
        throw GitHubAuthError.relayRefused(host: host, reason: refusal.reason ?? error)
    }

    // MARK: Device flow

    /// "Use a code instead" (RFC 8628). The steps come from Core's
    /// `GitHubDeviceFlowState`; this only performs the requests it asks for.
    package func connectWithCode() {
        guard let clientID else { state = .failed(.notConfigured); return }
        stopAttempt()
        state = .exchanging
        start { service in await service.signInWithCode(clientID: clientID) }
    }

    private func signInWithCode(clientID: String) async {
        var flow = GitHubDeviceFlowState.idle.next(.start, now: now())
        do {
            let issued = try await requestDeviceCode(clientID: clientID)
            flow = flow.next(.codeIssued(issued), now: now())
        } catch let error as GitHubAuthError {
            if !Task.isCancelled { state = .failed(error) }
            return
        } catch {
            flow = flow.next(.codeRequestFailed(String(describing: error)), now: now())
        }
        while !Task.isCancelled {
            switch flow {
            case .awaitingUser(let waiting):
                state = .deviceFlow(userCode: waiting.userCode, verificationURL: waiting.verificationURI)
                do { try await sleep(max(0, waiting.nextPollAt.timeIntervalSince(now()))) } catch { return }
                guard !Task.isCancelled else { return }
                flow = flow.next(.tick, now: now())
                guard flow.shouldPoll(now: now()) else { continue }
                let result = await poll(clientID: clientID, deviceCode: waiting.deviceCode)
                guard !Task.isCancelled else { return }
                flow = flow.next(.poll(result), now: now())
            case .authorized(let token):
                state = .exchanging
                await finishSignIn(with: token.value)
                return
            case .failed(let failure):
                state = .failed(.deviceFlow(failure))
                return
            case .idle, .requestingCode:
                state = .signedOut
                return
            }
        }
    }

    /// `POST https://github.com/login/device/code`.
    private func requestDeviceCode(clientID: String) async throws -> GitHubDeviceCode {
        let request = Self.form(Self.webURL.appendingPathComponent("login/device/code"),
                                ["client_id": clientID])
        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch {
            throw GitHubAuthError.gitHubUnreachable
        }
        let body = try? JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        guard let body, let deviceCode = body.deviceCode, let userCode = body.userCode,
              let uri = body.verificationURI.flatMap(URL.init(string:)) else {
            throw GitHubAuthError.deviceFlow(.other(body?.error ?? "no_device_code"))
        }
        return GitHubDeviceCode(deviceCode: deviceCode, userCode: userCode, verificationURI: uri,
                                expiresIn: TimeInterval(body.expiresIn ?? 900),
                                interval: TimeInterval(body.interval ?? 5))
    }

    /// One `POST https://github.com/login/oauth/access_token`. A network
    /// blip is read as "still waiting", so the code stays usable until it
    /// expires.
    private func poll(clientID: String, deviceCode: String) async -> GitHubDeviceFlowPollResult {
        let request = Self.form(Self.webURL.appendingPathComponent("login/oauth/access_token"),
                                ["client_id": clientID, "device_code": deviceCode,
                                 "grant_type": Self.deviceGrantType])
        guard let (data, _) = try? await transport.send(request) else { return .pending }
        guard let body = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            return .failure("unreadable_response")
        }
        if let token = body.accessToken, !token.isEmpty { return .token(GitHubAccessToken(token)) }
        return GitHubDeviceFlowPollResult(errorCode: body.error ?? "no_token")
    }

    // MARK: Signing in and out

    /// Saves the token, then confirms it. A Keychain refusal does not stop the
    /// sign-in: ad-hoc builds lack the Keychain entitlement, so the token
    /// lives in memory for this session and the next launch asks again (or
    /// finds the GitHub CLI login).
    private func finishSignIn(with token: String) async {
        do {
            try store.save(token)
        } catch {
            let status = (error as? GitHubTokenStoreError)?.status ?? errSecIO
            Self.log.notice("Keychain refused the GitHub token (OSStatus \(status, privacy: .public)); keeping it in memory")
        }
        self.token = token
        tokenLoaded = true
        await confirm(token)
    }

    /// `GET https://api.github.com/user`: the login to show, and proof the
    /// token still works.
    private func confirm(_ token: String) async {
        state = .exchanging
        var request = URLRequest(url: Self.apiURL.appendingPathComponent("user"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let answer: (Data, HTTPURLResponse)
        do {
            answer = try await transport.send(request)
        } catch {
            if !Task.isCancelled { state = .failed(.gitHubUnreachable) }
            return
        }
        guard !Task.isCancelled, self.token == token else { return }
        switch answer.1.statusCode {
        case 200:
            if let user = try? JSONDecoder().decode(User.self, from: answer.0), !user.login.isEmpty {
                state = .signedIn(login: user.login)
            } else {
                state = .failed(.gitHubRefused(status: 200))
            }
        case 401:
            handleUnauthorized()
        default:
            state = .failed(.gitHubRefused(status: answer.1.statusCode))
        }
    }

    package func disconnect() {
        stopAttempt()
        cliAutoConnectSuppressed = true
        loadTokenIfNeeded()
        let revoked = token
        token = nil
        tokenLoaded = true
        do {
            try store.delete()
            state = .signedOut
        } catch {
            state = .failed(.keychain(status: (error as? GitHubTokenStoreError)?.status ?? errSecIO))
        }
        // Best effort, as the relay's own revoke is: the Keychain item is gone either way.
        guard let revoked, let relay = relayURL else { return }
        var request = URLRequest(url: relay.appendingPathComponent("auth/revoke"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(revoked)", forHTTPHeaderField: "Authorization")
        let transport = transport
        Task { _ = try? await transport.send(request) }
    }

    package func handleUnauthorized() {
        stopAttempt()
        if let token { rejectedToken = token }
        token = nil
        tokenLoaded = true
        try? store.delete()
        state = .signedOut
    }

    // MARK: Helpers

    private func start(_ work: @escaping @MainActor @Sendable (GitHubAuthService) async -> Void) {
        attempt?.cancel()
        attempt = Task { [weak self] in
            guard let self else { return }
            await work(self)
        }
    }

    private func stopAttempt() {
        attempt?.cancel()
        attempt = nil
        presenter.cancel()
    }

    private func loadTokenIfNeeded() {
        guard !tokenLoaded else { return }
        tokenLoaded = true
        do {
            token = try store.load()
        } catch {
            token = nil
            state = .failed(.keychain(status: (error as? GitHubTokenStoreError)?.status ?? errSecIO))
        }
    }

    private static func host(_ url: URL) -> String { url.host ?? url.absoluteString }

    private static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
        return request
    }
}

// MARK: - Wire format

/// The relay's `exchangeRequest` (`apps/services/github-relay/server.go`).
private struct ExchangeRequest: Encodable {
    let code: String
    let state: String
    let verifier: String
}

/// The relay's `TokenResponse`, which is also GitHub's token answer; GitHub
/// puts its `error` in the same body.
private struct TokenResponse: Decodable {
    let accessToken: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case error
    }
}

/// The relay's error body: `{"error": …}`, plus `reason` when GitHub refused the code.
private struct RelayError: Decodable {
    let error: String?
    let reason: String?
}

private struct DeviceCodeResponse: Decodable {
    let deviceCode: String?
    let userCode: String?
    let verificationURI: String?
    let expiresIn: Int?
    let interval: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case error
    }
}

private struct User: Decodable {
    let login: String
}
