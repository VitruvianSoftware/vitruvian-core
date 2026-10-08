// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import CryptoKit
import Foundation

/// A GitHub user token. Its description never shows the value, so a logged
/// state or error cannot leak it.
package struct GitHubAccessToken: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    package let value: String

    package init(_ value: String) { self.value = value }

    package var description: String { "GitHubAccessToken(redacted)" }
    package var debugDescription: String { description }
}

/// Why a sign-in callback was refused.
package enum GitHubOAuthError: Error, Sendable, Equatable {
    /// Not `vitruvian://github/callback`.
    case wrongCallback
    /// The `state` is not the one this sign-in sent: someone else's redirect.
    case stateMismatch
    /// GitHub said the user declined (`error=access_denied`).
    case denied
    case missingCode
    /// Any other `error` GitHub returned.
    case other(String)
}

/// One sign-in attempt's secret and the value derived from it (design spec
/// §2.2).
///
/// `verifier` is 32 random bytes, base64url without padding (43 characters).
/// `state` is base64url(SHA-256(UTF-8 of `verifier`)), also without padding:
/// exactly RFC 7636's S256 code challenge. The app sends `state` to GitHub and
/// keeps `verifier`; the relay's `POST /auth/exchange {code, state, verifier}`
/// checks that the one derives from the other, so a different app that catches
/// the `vitruvian://` redirect has `code` and `state` but cannot redeem them.
package struct GitHubOAuthState: Sendable, Equatable {
    package static let redirectURI = "vitruvian://github/callback"
    package static let verifierByteCount = 32

    package let verifier: String
    package let state: String

    package init(verifier: String) {
        self.verifier = verifier
        self.state = Self.challenge(for: verifier)
    }

    /// A fresh attempt. `randomBytes` returns the given number of random
    /// bytes; tests pass a fixed source, the app the system's.
    package static func generate(randomBytes: (Int) -> [UInt8] = systemRandomBytes) -> GitHubOAuthState {
        GitHubOAuthState(verifier: base64URL(Data(randomBytes(verifierByteCount))))
    }

    /// The system's cryptographically secure generator.
    package static func systemRandomBytes(_ count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    package static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// GitHub's authorize page for this attempt. With `pkce`, `state` also
    /// goes as the S256 `code_challenge`, and the relay must then send
    /// `code_verifier` = `verifier` with the code exchange.
    package func authorizeURL(clientID: String, redirectURI: String, pkce: Bool = false) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/login/oauth/authorize"
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        if pkce {
            items.append(URLQueryItem(name: "code_challenge", value: state))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        components.queryItems = items
        // Every part above is fixed or URL-safe, so the URL always forms.
        return components.url!
    }

    /// The code in GitHub's redirect, once the redirect is ours and carries
    /// this attempt's `state`.
    package func code(fromCallback url: URL) -> Result<String, GitHubOAuthError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "vitruvian", components.host == "github", components.path == "/callback"
        else { return .failure(.wrongCallback) }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { return .failure(.stateMismatch) }
        if let error = value("error") {
            return .failure(error == "access_denied" ? .denied : .other(error))
        }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        return .success(code)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Device flow (RFC 8628), the "Use a code instead" fallback

/// GitHub's answer to `POST /login/device/code`.
package struct GitHubDeviceCode: Sendable, Equatable {
    package let deviceCode: String
    package let userCode: String
    package let verificationURI: URL
    package let expiresIn: TimeInterval
    package let interval: TimeInterval

    package init(deviceCode: String, userCode: String, verificationURI: URL,
                 expiresIn: TimeInterval, interval: TimeInterval) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// What one poll of `POST /login/oauth/access_token` said.
package enum GitHubDeviceFlowPollResult: Sendable, Equatable {
    case pending
    case slowDown
    case denied
    case expired
    case token(GitHubAccessToken)
    case failure(String)

    /// GitHub's `error` value.
    package init(errorCode: String) {
        switch errorCode {
        case "authorization_pending": self = .pending
        case "slow_down": self = .slowDown
        case "access_denied": self = .denied
        case "expired_token", "token_expired": self = .expired
        default: self = .failure(errorCode)
        }
    }
}

package enum GitHubDeviceFlowFailure: Sendable, Equatable {
    case denied
    case expired
    case other(String)
}

/// A device-flow sign-in waiting for the user to enter the code.
package struct GitHubDeviceFlowWaiting: Sendable, Equatable {
    package let deviceCode: String
    package let userCode: String
    package let verificationURI: URL
    package let interval: TimeInterval
    package let nextPollAt: Date
    package let expiresAt: Date

    package init(deviceCode: String, userCode: String, verificationURI: URL,
                 interval: TimeInterval, nextPollAt: Date, expiresAt: Date) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.interval = interval
        self.nextPollAt = nextPollAt
        self.expiresAt = expiresAt
    }
}

package enum GitHubDeviceFlowInput: Sendable, Equatable {
    case start
    case codeIssued(GitHubDeviceCode)
    case codeRequestFailed(String)
    case poll(GitHubDeviceFlowPollResult)
    /// Time passed; the code may have expired.
    case tick
    case cancel
}

/// The device flow as a value. The service performs the requests the state
/// asks for (a code while `requestingCode`, a poll when `shouldPoll`) and feeds
/// back what came of them; the times come from the service's clock.
package enum GitHubDeviceFlowState: Sendable, Equatable {
    case idle
    case requestingCode
    case awaitingUser(GitHubDeviceFlowWaiting)
    case authorized(GitHubAccessToken)
    case failed(GitHubDeviceFlowFailure)

    /// RFC 8628 §3.5: each `slow_down` adds five seconds.
    package static let slowDownStep: TimeInterval = 5

    package func next(_ input: GitHubDeviceFlowInput, now: Date) -> GitHubDeviceFlowState {
        if input == .cancel { return .idle }
        switch (self, input) {
        case (.idle, .start), (.failed, .start), (.authorized, .start):
            return .requestingCode
        case (.requestingCode, .codeIssued(let code)):
            return .awaitingUser(GitHubDeviceFlowWaiting(
                deviceCode: code.deviceCode, userCode: code.userCode, verificationURI: code.verificationURI,
                interval: code.interval, nextPollAt: now.addingTimeInterval(code.interval),
                expiresAt: now.addingTimeInterval(code.expiresIn)))
        case (.requestingCode, .codeRequestFailed(let reason)):
            return .failed(.other(reason))
        case (.awaitingUser(let waiting), .tick):
            return now >= waiting.expiresAt ? .failed(.expired) : self
        case (.awaitingUser(let waiting), .poll(let result)):
            switch result {
            case .token(let token): return .authorized(token)
            case .denied: return .failed(.denied)
            case .expired: return .failed(.expired)
            case .failure(let code): return .failed(.other(code))
            case .pending, .slowDown:
                if now >= waiting.expiresAt { return .failed(.expired) }
                let interval = waiting.interval + (result == .slowDown ? Self.slowDownStep : 0)
                return .awaitingUser(GitHubDeviceFlowWaiting(
                    deviceCode: waiting.deviceCode, userCode: waiting.userCode,
                    verificationURI: waiting.verificationURI, interval: interval,
                    nextPollAt: now.addingTimeInterval(interval), expiresAt: waiting.expiresAt))
            }
        default:
            return self
        }
    }

    /// Whether a poll is due.
    package func shouldPoll(now: Date) -> Bool {
        guard case .awaitingUser(let waiting) = self else { return false }
        return now >= waiting.nextPollAt && now < waiting.expiresAt
    }
}
