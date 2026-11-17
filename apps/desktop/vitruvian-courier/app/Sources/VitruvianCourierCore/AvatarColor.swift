// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The colour of an initials (placeholder) avatar. One function for every avatar in the app, keyed on a stable
/// identity (a user ID, or a chat's room ID) and never on a display name, so a person has the same colour in the
/// inbox, the chat header, beside messages and in chat info, however each place spells their name.
public enum AvatarColor {
    public struct HSB: Equatable, Sendable {
        public let hue: Double
        public let saturation: Double
        public let brightness: Double
    }

    /// The colour for `identity`. Stable across runs (a Swift `hashValue` is not).
    public static func hsb(forIdentity identity: String) -> HSB {
        var hash: UInt32 = 5381
        for byte in identity.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return HSB(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.62)
    }

    /// What to key a person's colour on: their ID, or the name when no ID is known.
    ///
    /// Two accepted fallbacks, both only for want of an ID:
    /// - an empty ID (an event or member the engine sent with no user ID) falls back to the display name;
    /// - a group whose members the engine has not sent (no `members_preview` yet, and a name that lists people, such
    ///   as "Ann, Bo") draws its circles from those names, so each circle is coloured by its name.
    /// A one-to-one chat with no known counterpart falls back to its room ID (see `InboxRow.avatarIdentity`).
    public static func identity(id: String, fallbackName: String) -> String {
        id.isEmpty ? fallbackName : id
    }

    /// The other person in a one-to-one chat, from a room's members: the one who is not me, not a bridge bot and not
    /// a bot profile. "" when there is not exactly one such person's ID to name.
    static func counterpartID(in members: [Member], network: String) -> String {
        let bridgeBot = "@\(network)bot:"
        let others = members.filter {
            $0.userID != Timeline.meUserID && !$0.isBot && !$0.userID.hasPrefix(bridgeBot) && !$0.userID.isEmpty
        }
        return others.first?.userID ?? ""
    }
}

extension InboxRow {
    /// The other person in a one-to-one chat, by user ID: the engine's `members_preview` for the row holds them (it
    /// leaves out me and bridge bots). "" for a group, or until the engine has said who.
    public var directPeerID: String { isDirect ? memberPreview.first?.userID ?? "" : "" }

    /// What the row's initials avatar is coloured by. A one-to-one chat is coloured by the other person's user ID, so
    /// they have one colour in the inbox, the header, chat info, beside group messages and in member lists; the
    /// room ID stands in only while no counterpart is known.
    public var avatarIdentity: String { AvatarColor.identity(id: directPeerID.isEmpty ? roomID : directPeerID, fallbackName: name) }
}

extension RoomInfoResult {
    /// The other person in a one-to-one chat, from the room's members (not me, not a bridge bot); "" otherwise.
    public var directPeerID: String { isDirect ? AvatarColor.counterpartID(in: members, network: network) : "" }

    /// The same identity as the chat's inbox row and header (see `InboxRow.avatarIdentity`).
    public var avatarIdentity: String { AvatarColor.identity(id: directPeerID.isEmpty ? roomID : directPeerID, fallbackName: name) }
}

extension Member {
    /// A member's colour is keyed on their user ID, the same on every list and beside every message.
    public var avatarIdentity: String { AvatarColor.identity(id: userID, fallbackName: name) }
}
