// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Verification-code senders (a chat titled just `787473`, an SMS short code) file themselves under Low Priority,
/// so they do not sit among real conversations in the inbox.
///
/// Only the title decides: a chat whose name is a short code (`ContactListOrdering.isShortCode`, 3 to 8 digits).
/// A named sender such as "Chase Bank" is never filed, even when its messages are one-time codes.
///
/// This is a default, applied once to a chat and then left alone. What a person did with the chat is theirs:
/// - a pinned chat, one with a label or a reminder, one marked unread, one with a draft, one they renamed, and a
///   merged chat are never filed;
/// - a chat the app filed is remembered (`InboxPreferences.filedShortCodeRoomIDs`), so moving it back to the
///   inbox sticks: it is never filed again;
/// - only chats the inbox lists are looked at, so one the person archived, hid or put in Low Priority themselves
///   is not touched.
public enum ShortCodeSenders {
    /// Whether the chat is one-to-one with a sender whose name is a short code. A name the person gave it
    /// (`localName`) replaces the bridge's, so a renamed chat is not a short-code chat.
    public static func isShortCodeChat(_ row: InboxRow) -> Bool {
        guard row.isDirect, row.mergeID.isEmpty, !row.roomID.hasPrefix("merge:") else { return false }
        let title = row.localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? row.name : row.localName
        let trimmed = NetworkTag.stripped(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return ContactListOrdering.isShortCode(trimmed)
    }

    /// Whether the person has done anything with the chat that says where they want it.
    static func hasExplicitState(_ row: InboxRow) -> Bool {
        row.pinned || !row.labels.isEmpty || row.reminder != nil || row.markedUnread
            || !row.draft.isEmpty || !row.localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The chats among `rows`, which are the inbox's, to file under Low Priority now: short-code chats the person
    /// has not touched and the app has not filed before (`alreadyFiled`). Archived, hidden, Low Priority and
    /// request chats are not the inbox's, whatever their name.
    public static func lowPriorityCandidates(in rows: [InboxRow], alreadyFiled: Set<String>) -> [String] {
        rows.filter { row in
            isShortCodeChat(row) && !hasExplicitState(row) && !alreadyFiled.contains(row.roomID)
                && !row.archived && !row.hidden && !row.lowPriority && !row.request
        }.map(\.roomID)
    }
}
