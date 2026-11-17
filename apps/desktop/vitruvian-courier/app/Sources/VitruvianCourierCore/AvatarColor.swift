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

    /// What to key a person's colour on: their ID, or (only when no ID is known) their name.
    public static func identity(id: String, fallbackName: String) -> String {
        id.isEmpty ? fallbackName : id
    }
}

extension InboxRow {
    /// What a one-to-one chat's initials avatar is coloured by: the chat's room ID, not its (changeable) name.
    public var avatarIdentity: String { AvatarColor.identity(id: roomID, fallbackName: name) }
}

extension RoomInfoResult {
    /// The same identity as the chat's inbox row and header, so chat info shows the same colour.
    public var avatarIdentity: String { AvatarColor.identity(id: roomID, fallbackName: name) }
}

extension Member {
    /// A member's colour is keyed on their user ID, the same on every list and beside every message.
    public var avatarIdentity: String { AvatarColor.identity(id: userID, fallbackName: name) }
}
