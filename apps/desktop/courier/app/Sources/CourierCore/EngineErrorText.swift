// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What an engine error says to a person. The engine's own message is English and meant for logs, so it is
/// never shown: each code it defines has words here, and a code this app does not know gets the caller's
/// general words.
public enum EngineErrorText {
    public static func text(for error: Error, network: String? = nil, fallback: String) -> String {
        switch error as? EngineError {
        case let .rpc(code, _, _):
            return text(for: code, network: network) ?? fallback
        case .timedOut:
            return String(localized: "Courier’s engine did not answer in time.")
        case .notConnected:
            return String(localized: "Courier’s engine is not connected.")
        default:
            return fallback
        }
    }

    private static func text(for code: RPCErrorCode, network: String?) -> String? {
        switch code {
        case .notLinked: String(localized: "This chat’s network isn’t linked.")
        case .bridgeCommand: String(localized: "The network would take this as a command, so it was not sent.")
        case .tooLarge: String(localized: "A file is over 90 MB.")
        case .notRunning: String(localized: "This chat’s network isn’t running.")
        case .notConnected: String(localized: "The network isn’t connected yet.")
        case .notFailed: String(localized: "Only a message that was not sent can be sent again or deleted.")
        case .notFound: String(localized: "That chat or message is no longer there.")
        case .badValue: String(localized: "That isn’t accepted. Check it and try again.")
        case .unknownLogin: String(localized: "The sign-in ended before it was finished. Try again.")
        case .pinned: String(localized: "Unpin a chat to archive it.")
        case .notEntitled: String(localized: "Available with a plan")
        case .notSupported: String(localized: "This chat’s network can’t do that.")
        // Past the chat's age limit or its edit-count limit: the engine doesn't say which.
        case .tooOld: String(localized: "That message can’t be changed any more.")
        // Neutral on purpose: a held message whose hand-off failed is also "already sent" to the engine, and it did
        // not go (Ruling 20). Whoever undoes reads the message's status for the full story.
        case .alreadySent: String(localized: "Too late to undo. Check the message in the chat.")
        case .notYours: String(localized: "You can only change your own messages.")
        case .networkRefused:
            if let network, let name = NetworkNames.displayName(of: network) {
                String(localized: "\(name) didn’t accept that change.")
            } else {
                String(localized: "The network didn’t accept that change.")
            }
        default: nil
        }
    }
}
