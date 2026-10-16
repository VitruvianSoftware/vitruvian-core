// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What an engine error says to a person. The engine's own message is English and meant for logs, so it is
/// never shown: each code it defines has words here, and a code this app does not know gets the caller's
/// general words.
public enum EngineErrorText {
    public static func text(for error: Error, fallback: String) -> String {
        switch error as? EngineError {
        case let .rpc(code, _, _):
            return text(for: code) ?? fallback
        case .timedOut:
            return String(localized: "Courier’s engine did not answer in time.")
        case .notConnected:
            return String(localized: "Courier’s engine is not connected.")
        default:
            return fallback
        }
    }

    private static func text(for code: RPCErrorCode) -> String? {
        switch code {
        case .notLinked: String(localized: "This chat’s network isn’t linked.")
        case .bridgeCommand: String(localized: "The network would take this as a command, so it was not sent.")
        case .tooLarge: String(localized: "A file is over 90 MB.")
        case .notRunning: String(localized: "This chat’s network isn’t running.")
        case .notConnected: String(localized: "The network isn’t connected yet.")
        case .notFailed: String(localized: "Only a message that was not sent can be sent again or deleted.")
        case .notFound: String(localized: "That chat or message is no longer there.")
        default: nil
        }
    }
}
