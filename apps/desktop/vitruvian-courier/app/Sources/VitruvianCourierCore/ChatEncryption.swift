// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// What Chat Info says about a chat's encryption.
///
/// `RoomInfoResult.encrypted` is only whether the chat's room on this Mac is encrypted, which is the hop between the
/// network's bridge and the app. It says nothing about the network itself: a WhatsApp chat is end-to-end encrypted on
/// WhatsApp's side whatever that flag says. So the answer comes from the network, and the flag only settles the
/// networks that encrypt some chats and not others.
public enum ChatEncryption: Equatable, Sendable {
    /// Encrypted from sender to recipient on the network. The bridge on this Mac still has to read the messages to
    /// show them here.
    case endToEnd(networkName: String)
    /// The network does not encrypt this chat end to end.
    case notEndToEnd(networkName: String)
    /// The network encrypts some chats and not others, and this app can't tell which this is.
    case notConfirmed(networkName: String)

    /// Whether a network encrypts its chats end to end.
    enum Policy: Equatable {
        /// Every chat is.
        case always
        /// Some chats are. The room says so (`encrypted`): else it isn't known to be either way.
        case whenRoomSays
        /// No chat is.
        case never
    }

    /// The rule for each network, by the engine's id (see `NetworkNames`). Slack, Google Chat, Discord, LinkedIn,
    /// Google Voice, Bluesky and X direct messages are not end-to-end encrypted. Telegram's ordinary (cloud) chats
    /// are not either; only its secret chats are, which the bridge does not carry. Google Messages is end-to-end
    /// encrypted for RCS chats and not for SMS, and the app can't tell them apart. Messenger and Instagram encrypt
    /// some chats only.
    static let policies: [String: Policy] = [
        "whatsapp": .always,
        "signal": .always,
        "imessage": .always,
        "gmessages": .whenRoomSays,
        "facebook": .whenRoomSays,
        "instagram": .whenRoomSays,
        "telegram": .never,
        "slack": .never,
        "gchat": .never,
        "discord": .never,
        "twitter": .never,
        "linkedin": .never,
        "gvoice": .never,
        "bluesky": .never,
    ]

    /// The answer for a chat on `network` (the engine's id), `roomEncrypted` being `RoomInfoResult.encrypted`.
    /// A network this app doesn't know is treated like one that encrypts some chats: encrypted when its room says
    /// so, else "isn't confirmed". It is never said to be unencrypted, which nothing known says.
    public static func of(network: String, roomEncrypted: Bool) -> ChatEncryption {
        let name = NetworkNames.displayName(of: network) ?? String(localized: "this network")
        switch policies[network] ?? .whenRoomSays {
        case .always:
            return .endToEnd(networkName: name)
        case .never:
            return .notEndToEnd(networkName: name)
        case .whenRoomSays:
            return roomEncrypted ? .endToEnd(networkName: name) : .notConfirmed(networkName: name)
        }
    }

    public static func of(_ info: RoomInfoResult) -> ChatEncryption {
        of(network: info.network, roomEncrypted: info.encrypted)
    }

    public var isEndToEnd: Bool {
        if case .endToEnd = self { return true }
        return false
    }

    /// The row's one line: "End-to-end encrypted on WhatsApp".
    public var title: String {
        switch self {
        case let .endToEnd(name): String(localized: "End-to-end encrypted on \(name)")
        case let .notEndToEnd(name): String(localized: "Not end-to-end encrypted on \(name)")
        case let .notConfirmed(name): String(localized: "End-to-end encryption isn’t confirmed on \(name)")
        }
    }

    /// The line under it, nil when there is nothing more to say.
    public var note: String? {
        switch self {
        case .endToEnd: String(localized: "Messages are decrypted on this Mac to show them here.")
        case .notEndToEnd: nil
        case .notConfirmed: String(localized: "This chat doesn’t say whether it is end-to-end encrypted.")
        }
    }

    /// The padlock: closed for end to end, open otherwise.
    public var symbolName: String { isEndToEnd ? "lock.fill" : "lock.open" }
}
