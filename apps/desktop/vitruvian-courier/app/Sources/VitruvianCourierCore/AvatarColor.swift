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

    /// The other person in a one-to-one chat: the one joined human who is not me, given the candidates already
    /// narrowed to humans other than me (the row's `members_preview`, or chat info's members minus me, bridge bots
    /// and bot profiles). Exactly one names them; none, or more than one (so "whoever spoke last" never decides),
    /// gives "" and the chat falls back to its room ID. Row, header, chat info and the edit sheet all use this.
    static func soleCounterpartID(among userIDs: [String]) -> String {
        let people = Set(userIDs.filter { !$0.isEmpty && $0 != Timeline.meUserID })
        return people.count == 1 ? people.first ?? "" : ""
    }

    /// `soleCounterpartID` for a room's member list: leaves out me, the network's bridge bot and bot profiles.
    static func counterpartID(in members: [Member], network: String) -> String {
        let bridgeBot = "@\(network)bot:"
        return soleCounterpartID(among: members.filter { !$0.isBot && !$0.userID.hasPrefix(bridgeBot) }.map(\.userID))
    }
}

extension InboxRow {
    /// The other person in a one-to-one chat, by user ID: the engine's `members_preview` for the row holds the
    /// joined humans other than me (it leaves out bridge and service bots). "" for a group, when there is not exactly
    /// one such person, or until the engine has said.
    public var directPeerID: String { isDirect ? AvatarColor.soleCounterpartID(among: memberPreview.map(\.userID)) : "" }

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
