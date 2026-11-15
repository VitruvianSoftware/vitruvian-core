// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation

// Signing in, as values. The three ways in: the GitHub CLI's saved login,
// a token the person pastes, and GitHub's device flow (RFC 8628), "a code".
// The app's fourth way, GitHub's authorize page in a browser window ending
// on `vitruvian://github/callback`, cannot move here: a custom URL scheme
// belongs to an app bundle, and the relay that redeemed the code is gone.

/// A GitHub user token. Its description never shows the value, so a logged
/// state cannot leak it.
public struct AccessToken: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let value: String

    public init(_ value: String) { self.value = value }

    public var description: String { "AccessToken(redacted)" }
    public var debugDescription: String { description }
}

/// Where the person's files are.
public enum Paths {
    /// The home folder: `$HOME` when it is set, as a test or a launcher sets
    /// it, else the account's. `NSHomeDirectory()` alone reads the account's
    /// and would find the person's real logins under a test's scratch home.
    public static var home: String {
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty { return home }
        return NSHomeDirectory()
    }
}

/// The GitHub CLI's saved login, read from its `hosts.yml`.
public enum CLIAccount {
    /// Where the GitHub CLI keeps its login, under `Paths.home`.
    public static var defaultHostsURL: URL {
        URL(fileURLWithPath: Paths.home, isDirectory: true).appendingPathComponent(".config/gh/hosts.yml")
    }

    /// The login and the token for github.com, or nil without a token.
    public static func read(hostsFile: URL = defaultHostsURL) -> (login: String, token: String)? {
        guard let content = try? String(contentsOf: hostsFile, encoding: .utf8) else { return nil }
        return parse(content)
    }

    public static func parse(_ content: String) -> (login: String, token: String)? {
        var user: String?
        var token: String?
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("user:") {
                user = trimmed.dropFirst("user:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("oauth_token:") {
                token = trimmed.dropFirst("oauth_token:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        guard let token, !token.isEmpty else { return nil }
        return (login: user ?? "", token: token)
    }
}

// MARK: - Device flow (RFC 8628)

/// GitHub's answer to `POST /login/device/code`.
public struct DeviceCode: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let expiresIn: TimeInterval
    public let interval: TimeInterval

    public init(deviceCode: String, userCode: String, verificationURI: URL, expiresIn: TimeInterval,
                interval: TimeInterval) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// What one poll of `POST /login/oauth/access_token` said.
public enum DevicePollResult: Sendable, Equatable {
    case pending
    case slowDown
    case denied
    case expired
    case token(AccessToken)
    case failure(String)

    /// GitHub's `error` value.
    public init(errorCode: String) {
        switch errorCode {
        case "authorization_pending": self = .pending
        case "slow_down": self = .slowDown
        case "access_denied": self = .denied
        case "expired_token", "token_expired": self = .expired
        default: self = .failure(errorCode)
        }
    }
}

public enum DeviceFlowFailure: Sendable, Equatable {
    case denied
    case expired
    case other(String)
}

/// A device-flow sign-in waiting for the person to enter the code.
public struct DeviceFlowWaiting: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let interval: TimeInterval
    public let nextPollAt: Date
    public let expiresAt: Date

    public init(deviceCode: String, userCode: String, verificationURI: URL, interval: TimeInterval,
                nextPollAt: Date, expiresAt: Date) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.interval = interval
        self.nextPollAt = nextPollAt
        self.expiresAt = expiresAt
    }
}

public enum DeviceFlowInput: Sendable, Equatable {
    case start
    case codeIssued(DeviceCode)
    case codeRequestFailed(String)
    case poll(DevicePollResult)
    /// Time passed; the code may have expired.
    case tick
    case cancel
}

/// The device flow as a value. The tool performs the requests the state asks
/// for (a code while `requestingCode`, a poll when `shouldPoll`) and feeds
/// back what came of them; the times come from the tool's clock.
public enum DeviceFlowState: Sendable, Equatable {
    case idle
    case requestingCode
    case awaitingUser(DeviceFlowWaiting)
    case authorized(AccessToken)
    case failed(DeviceFlowFailure)

    /// RFC 8628 §3.5: each `slow_down` adds five seconds.
    public static let slowDownStep: TimeInterval = 5

    public func next(_ input: DeviceFlowInput, now: Date) -> DeviceFlowState {
        if input == .cancel { return .idle }
        switch (self, input) {
        case (.idle, .start), (.failed, .start), (.authorized, .start):
            return .requestingCode
        case (.requestingCode, .codeIssued(let code)):
            return .awaitingUser(DeviceFlowWaiting(
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
                return .awaitingUser(DeviceFlowWaiting(
                    deviceCode: waiting.deviceCode, userCode: waiting.userCode,
                    verificationURI: waiting.verificationURI, interval: interval,
                    nextPollAt: now.addingTimeInterval(interval), expiresAt: waiting.expiresAt))
            }
        default:
            return self
        }
    }

    /// Whether a poll is due.
    public func shouldPoll(now: Date) -> Bool {
        guard case .awaitingUser(let waiting) = self else { return false }
        return now >= waiting.nextPollAt && now < waiting.expiresAt
    }
}

// MARK: - The sign-in as the panels show it

/// Why a sign-in did not finish.
public enum AuthFailure: Sendable, Equatable {
    /// The `clientID` preference is empty: a code needs the GitHub App's
    /// client ID.
    case notConfigured
    /// No answer from github.com or api.github.com.
    case unreachable
    /// GitHub answered with an HTTP error other than 401.
    case refused(status: Int)
    /// GitHub said the token is dead.
    case tokenRejected
    case deviceFlow(DeviceFlowFailure)
}

/// Where the sign-in stands, for the Settings panel.
public enum AuthState: Sendable, Equatable {
    case signedOut
    /// Checking a token with GitHub.
    case checking
    /// "A code": the code to type at the page.
    case deviceFlow(userCode: String, verificationURL: URL)
    case signedIn(login: String)
    case failed(AuthFailure)

    public var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}
