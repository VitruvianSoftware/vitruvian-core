// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Verification-code senders (a chat titled just `787473`, an SMS short code) file themselves under Low Priority,
/// so they do not sit among real conversations in the inbox.
///
/// Only the title decides: a chat whose name is a short code (`ContactListOrdering.isShortCode`, 3 to 8 digits).
/// A named sender such as "Chase Bank" is never filed, even when its messages are one-time codes.
///
/// This is a default, applied to a chat at most once, ever. The first time the app sees a short-code chat anywhere
/// (the inbox, Archive, Low Priority) it is recorded (`InboxPreferences.evaluatedShortCodeRoomIDs`), filed or not, and
/// never looked at again. So whatever the person does afterwards sticks: moving it back to the inbox, unarchiving it,
/// moving it to Low Priority by hand and back. A chat is filed only when that first sight is in the inbox and the person
/// has not touched it:
/// - a pinned chat, one with a label or a reminder, one marked unread, one with a draft, one they renamed, and a
///   merged chat are never filed;
/// - one that is archived, hidden, in Low Priority or a request is not the inbox's, so it is recorded and left.
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
    ///
    /// "Unread" here is the person's own mark only (`markedUnread`), never the unread count. A verification code
    /// arrives unread by nature, so the count would keep every short-code chat out of Low Priority; a mark is something
    /// the person chose.
    static func hasExplicitState(_ row: InboxRow) -> Bool {
        row.pinned || !row.labels.isEmpty || row.reminder != nil || row.markedUnread
            || !row.draft.isEmpty || !row.localName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What a read of chats shows about short-code chats the app has not seen before.
    public struct Evaluation: Equatable {
        /// Every short-code chat in `rows` not yet recorded: record them all, filed or not.
        public var newlySeen: [String]
        /// Of those, the ones to file under Low Priority now.
        public var toFile: [String]
    }

    /// `rows` is a read of chats; `isInbox` is whether it is the inbox's (Archive, Low Priority and the rest are not).
    /// `alreadySeen` are the short-code chats recorded before: they are never in the answer.
    public static func evaluate(_ rows: [InboxRow], isInbox: Bool, alreadySeen: Set<String>) -> Evaluation {
        var newlySeen: [String] = []
        var toFile: [String] = []
        for row in rows where isShortCodeChat(row) && !alreadySeen.contains(row.roomID) && !newlySeen.contains(row.roomID) {
            newlySeen.append(row.roomID)
            if isInbox, !hasExplicitState(row), !row.archived, !row.hidden, !row.lowPriority, !row.request {
                toFile.append(row.roomID)
            }
        }
        return Evaluation(newlySeen: newlySeen, toFile: toFile)
    }
}
