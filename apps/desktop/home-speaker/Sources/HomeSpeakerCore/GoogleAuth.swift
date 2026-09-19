// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import CryptoKit
import Foundation
import Network

public enum GoogleAuthError: LocalizedError, Equatable {
    case noOAuthClient
    case notSignedIn
    case listenFailed
    case browserDenied(String)
    case stateMismatch
    case redirectNotRegistered(String)
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .noOAuthClient:
            return "No Google OAuth client configured. Add one under Settings > Advanced, or import an Antigravity login."
        case .notSignedIn: return "Not signed in to Google."
        case .listenFailed: return "Could not open a local port for the sign-in callback."
        case .browserDenied(let reason): return "Google sign-in was not completed (\(reason))."
        case .stateMismatch: return "Sign-in response did not match this request."
        case .redirectNotRegistered(let uri):
            return "Google rejected the callback address. Add \(uri) to your OAuth client's authorised redirect URIs (a Desktop-app client needs none)."
        case .tokenExchangeFailed(let why): return "Could not exchange the sign-in code: \(why)"
        case .refreshFailed(let why): return "Could not refresh the Google login: \(why)"
        case .timedOut: return "Timed out waiting for the browser sign-in."
        }
    }
}

/// OAuth client id/secret, resolved in this order:
///  1. a user override saved in the secret store (Settings > Advanced),
///  2. the values baked into Info.plist at packaging time
///     (`GoogleOAuthClientID` / `GoogleOAuthClientSecret`),
///  3. the client that issued the credentials we already hold — an imported
///     Antigravity login carries its own client id and secret, and that
///     client demonstrably has Home API access for this user, so there is no
///     reason to make them register a second one.
/// Google treats desktop client secrets as non-confidential, so shipping one
/// in the bundle is the documented pattern for installed apps.
public struct OAuthClient: Equatable {
    public var clientId: String
    public var clientSecret: String

    public init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    public static func resolve(secrets: Secrets, bundle: Bundle = .main) -> OAuthClient? {
        if let id = secrets.oauthClientIdOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            return OAuthClient(clientId: id, clientSecret: secrets.oauthClientSecretOverride ?? "")
        }
        if let id = bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String,
           !id.trimmingCharacters(in: .whitespaces).isEmpty {
            let secret = bundle.object(forInfoDictionaryKey: "GoogleOAuthClientSecret") as? String ?? ""
            return OAuthClient(clientId: id, clientSecret: secret)
        }
        if let g = secrets.google, !g.clientId.isEmpty {
            return OAuthClient(clientId: g.clientId, clientSecret: g.clientSecret)
        }
        return nil
    }
}

/// Google sign-in for a native app: PKCE + a loopback redirect on 127.0.0.1.
/// Nothing here touches the UI; the caller opens `authorizationURL` in the
/// browser and awaits `signIn`.
public actor GoogleAuth {
    public static let shared = GoogleAuth()

    public static let homeScope = "https://www.googleapis.com/auth/home.platform.v2"
    public static let chatScopes = [
        "https://www.googleapis.com/auth/chat.spaces.readonly",
        "https://www.googleapis.com/auth/chat.messages.readonly",
    ]
    /// `openid` yields an id_token whose `sub` is the Google user id; `email`
    /// is only for showing "signed in as" in Settings.
    public static let identityScopes = ["openid", "email"]

    public static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    /// Fixed so the redirect URI is predictable for users registering their
    /// own OAuth client; falls through to the next ports if it is busy.
    public static let callbackPorts: [UInt16] = [8765, 8766, 8767, 8768]
    public static let callbackPath = "/callback"

    private let store: SecretStore
    private let session: URLSession

    public init(store: SecretStore = .shared, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    // MARK: PKCE (pure, testable)

    public struct PKCE: Equatable {
        public let verifier: String
        public let challenge: String

        public init(verifier: String) {
            self.verifier = verifier
            self.challenge = PKCE.challenge(for: verifier)
        }

        public static func random() -> PKCE {
            var bytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return PKCE(verifier: Data(bytes).base64URLEncoded())
        }

        public static func challenge(for verifier: String) -> String {
            Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
        }
    }

    public static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(callbackPath)"
    }

    /// Every redirect URI this app can end up using. A "Desktop app" OAuth
    /// client accepts any loopback port and needs none of them registered; a
    /// "Web application" client matches the port exactly, so all of these must
    /// be registered or sign-in fails with redirect_uri_mismatch on whichever
    /// port happens to be free.
    public static var allRedirectURIs: [String] { callbackPorts.map(redirectURI(port:)) }

    public static func authorizationURL(
        client: OAuthClient, scopes: [String], pkce: PKCE, state: String, port: UInt16,
        loginHint: String? = nil
    ) -> URL {
        var comps = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: client.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI(port: port)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        comps.queryItems = items
        return comps.url!
    }

    /// Parses the first request line of the loopback callback:
    /// "GET /callback?code=…&state=… HTTP/1.1". Returns nil when it is not
    /// the callback path (browsers also ask for /favicon.ico).
    public static func parseCallback(requestLine: String) -> (code: String?, state: String?, error: String?)? {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let comps = URLComponents(string: "http://127.0.0.1" + parts[1]),
              comps.path == callbackPath else { return nil }
        let q = comps.queryItems ?? []
        func value(_ name: String) -> String? { q.first(where: { $0.name == name })?.value }
        return (value("code"), value("state"), value("error"))
    }

    /// Decodes the `sub` and `email` claims of a JWT without verifying it —
    /// it arrived over TLS straight from Google's token endpoint, which is the
    /// trust boundary here; we only use it to label the account.
    public static func claims(fromIdToken jwt: String) -> (sub: String?, email: String?) {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2,
              let data = Data(base64URLEncoded: String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return (json["sub"] as? String, json["email"] as? String)
    }

    // MARK: Sign-in flow

    /// Runs the full browser sign-in. `openBrowser` receives the URL to open.
    /// Scopes already granted are kept (incremental auth) so enabling Google
    /// Chat later only asks for the extra permission.
    public func signIn(
        additionalScopes: [String] = [],
        openBrowser: @escaping @Sendable (URL) -> Void,
        timeout: TimeInterval = 300
    ) async throws -> GoogleCredentials {
        let secrets = store.load()
        guard let client = OAuthClient.resolve(secrets: secrets) else { throw GoogleAuthError.noOAuthClient }

        var scopes = Self.identityScopes + [Self.homeScope]
        scopes += (secrets.google?.scopes ?? []) + additionalScopes
        scopes = Array(NSOrderedSet(array: scopes)) as? [String] ?? scopes

        let pkce = PKCE.random()
        let state = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64URLEncoded()

        let listener = try LoopbackListener(ports: Self.callbackPorts)
        defer { listener.cancel() }
        let url = Self.authorizationURL(
            client: client, scopes: scopes, pkce: pkce, state: state, port: listener.port,
            loginHint: secrets.google?.email)
        openBrowser(url)

        let callback = try await listener.waitForCallback(timeout: timeout)
        if let error = callback.error {
            if error == "redirect_uri_mismatch" {
                throw GoogleAuthError.redirectNotRegistered(Self.redirectURI(port: listener.port))
            }
            throw GoogleAuthError.browserDenied(error)
        }
        guard callback.state == state else { throw GoogleAuthError.stateMismatch }
        guard let code = callback.code else { throw GoogleAuthError.browserDenied("no code") }

        let form = [
            "code": code,
            "client_id": client.clientId,
            "client_secret": client.clientSecret,
            "redirect_uri": Self.redirectURI(port: listener.port),
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier,
        ]
        let json = try await postForm(Self.tokenEndpoint, form: form, failure: GoogleAuthError.tokenExchangeFailed)
        guard let access = json["access_token"] as? String else {
            throw GoogleAuthError.tokenExchangeFailed("no access_token in response")
        }
        // Google only returns a refresh token on the consent prompt; keep the
        // previous one when a re-auth omits it.
        let refresh = (json["refresh_token"] as? String) ?? secrets.google?.refreshToken ?? ""
        let expires = (json["expires_in"] as? Double) ?? 3600
        let granted = (json["scope"] as? String)?.split(separator: " ").map(String.init) ?? scopes
        let ident = Self.claims(fromIdToken: (json["id_token"] as? String) ?? "")

        let creds = GoogleCredentials(
            clientId: client.clientId, clientSecret: client.clientSecret,
            accessToken: access, refreshToken: refresh,
            expiry: Date().addingTimeInterval(expires), scopes: granted,
            userId: ident.sub ?? secrets.google?.userId,
            email: ident.email ?? secrets.google?.email)
        try store.update { $0.google = creds }
        return creds
    }

    /// Returns a usable access token, refreshing first when it is stale.
    public func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard var creds = store.load().google else { throw GoogleAuthError.notSignedIn }
        guard forceRefresh || creds.needsRefresh() else { return creds.accessToken }
        let form = [
            "client_id": creds.clientId,
            "client_secret": creds.clientSecret,
            "refresh_token": creds.refreshToken,
            "grant_type": "refresh_token",
        ]
        let json = try await postForm(Self.tokenEndpoint, form: form) { why in
            GoogleAuthError.refreshFailed(Self.refreshFailureMessage(why))
        }
        guard let access = json["access_token"] as? String else {
            throw GoogleAuthError.refreshFailed("no access_token in response")
        }
        creds.accessToken = access
        creds.expiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        try store.update { $0.google = creds }
        return access
    }

    /// Google reports an expired or revoked refresh token as a bare
    /// `invalid_grant`. The most common cause for a bring-your-own client is
    /// a consent screen still in Testing, which expires logins after 7 days,
    /// so say that instead of leaving the user to search for it.
    public static func refreshFailureMessage(_ why: String) -> String {
        guard why.localizedCaseInsensitiveContains("invalid_grant")
            || why.localizedCaseInsensitiveContains("expired or revoked") else { return why }
        return "\(why). Sign in again. If this happens every week, your Google Cloud consent screen is still in Testing — publish it."
    }

    public func signOut(revoke: Bool = true) async {
        if revoke, let creds = store.load().google {
            _ = try? await postForm(Self.revokeEndpoint, form: ["token": creds.refreshToken], failure: GoogleAuthError.refreshFailed)
        }
        try? store.update { $0.google = nil }
    }

    private func postForm(
        _ url: URL, form: [String: String], failure: (String) -> GoogleAuthError
    ) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(form.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").utf8)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard status == 200 else {
            let why = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "HTTP \(status)"
            throw failure(why)
        }
        return json
    }
}

// MARK: - Loopback HTTP listener

/// A one-shot HTTP server on 127.0.0.1 that answers the OAuth redirect with a
/// tiny "you can close this tab" page and hands the query back.
final class LoopbackListener: @unchecked Sendable {
    let port: UInt16
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.vitruviansoftware.homespeaker.oauth")
    private var continuation: CheckedContinuation<(code: String?, state: String?, error: String?), Error>?
    private var connections: [NWConnection] = []

    init(ports: [UInt16]) throws {
        var chosen: (NWListener, UInt16)?
        for p in ports {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            params.allowLocalEndpointReuse = true
            if let l = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: p)!) {
                chosen = (l, p)
                break
            }
        }
        guard let (l, p) = chosen else { throw GoogleAuthError.listenFailed }
        listener = l
        port = p
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> (code: String?, state: String?, error: String?) {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.continuation = cont
                self.listener.stateUpdateHandler = { state in
                    if case .failed = state { self.finish(.failure(GoogleAuthError.listenFailed)) }
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(GoogleAuthError.timedOut))
                }
            }
        }
    }

    func cancel() {
        queue.async {
            self.listener.cancel()
            self.connections.forEach { $0.cancel() }
            self.connections.removeAll()
        }
    }

    private func accept(_ conn: NWConnection) {
        connections.append(conn)
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, let text = String(data: data, encoding: .utf8),
                  let line = text.split(separator: "\r\n", maxSplits: 1).first else { return }
            guard let parsed = GoogleAuth.parseCallback(requestLine: String(line)) else {
                self.respond(conn, status: "404 Not Found", body: "")
                return
            }
            let ok = parsed.error == nil && parsed.code != nil
            self.respond(conn, status: "200 OK", body: Self.page(success: ok))
            self.finish(.success(parsed))
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in conn.cancel() })
    }

    private func finish(_ result: Result<(code: String?, state: String?, error: String?), Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    private static func page(success: Bool) -> String {
        let title = success ? "Signed in to HomeSpeaker" : "Sign-in not completed"
        let body = success
            ? "You can close this tab and return to HomeSpeaker."
            : "HomeSpeaker did not receive permission. Close this tab and try again from the app."
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font-family:-apple-system,system-ui,sans-serif;display:grid;place-items:center;height:100vh;margin:0;color:#1d1d1f;background:#f5f5f7}
        main{text-align:center;padding:2rem}h1{font-size:1.4rem;margin:0 0 .5rem}p{color:#6e6e73;margin:0}</style></head>
        <body><main><h1>\(title)</h1><p>\(body)</p></main></body></html>
        """
    }
}

// MARK: - Encoding helpers

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded text: String) {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        self.init(base64Encoded: s)
    }
}

extension String {
    /// application/x-www-form-urlencoded value encoding (RFC 3986 unreserved
    /// set only; `+`, `/`, `=` in tokens must be escaped).
    var formEncoded: String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: unreserved) ?? self
    }
}
