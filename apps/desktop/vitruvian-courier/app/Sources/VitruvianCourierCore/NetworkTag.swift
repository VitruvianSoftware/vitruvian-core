// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The network tag a bridge adds to a person's name: WhatsApp's `Toan Vu (WA)`, LinkedIn's `Ana (LinkedIn)`.
///
/// The bridges build these into the name they hand over, but Vitruvian Courier already says which network a chat
/// is on (the badge on its row, the header, the composer's "on WhatsApp"), so the tag only crowds the name. This is
/// the one place that removes it; every view that shows a person's name goes through here.
///
/// Only the tags the bridges are known to add are removed. A name's own brackets are the person's, not the
/// bridge's: `Room (2)`, `Alex (Work)`, `Fred Fireflies (bot)`, `James (you)` and `Pat (EST)` are left alone.
public enum NetworkTag {
    /// What can sit between the brackets, compared without regard to case. WA and TG are the short tags WhatsApp
    /// and Telegram bridges use; the rest are the long tags (LinkedIn, Twitter, Bluesky) and the same short kind
    /// for the other networks.
    public static let known: Set<String> = [
        "wa", "tg", "ig", "fb", "signal", "whatsapp", "telegram", "instagram", "facebook",
        "linkedin", "twitter", "bluesky",
    ]

    /// `name` without one trailing network tag and the space before it (`Toan Vu (WA)` is `Toan Vu`). Unchanged when
    /// the name has no known tag at the end, and unchanged when the tag is all there is (`(WA)`): a name is never
    /// emptied.
    public static func stripped(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"), let open = trimmed.lastIndex(of: "(") else { return name }
        let inside = trimmed[trimmed.index(after: open) ..< trimmed.index(before: trimmed.endIndex)]
            .trimmingCharacters(in: .whitespaces)
        guard known.contains(inside.lowercased()) else { return name }
        let rest = trimmed[trimmed.startIndex ..< open].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? name : rest
    }
}
