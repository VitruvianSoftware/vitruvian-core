// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

extension RoomLink {
    /// The host/domain label shown above the URL in Chat Info's Links section.
    public var displayDomain: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty {
            return trimmedHost
        }
        if let parsedHost = URL(string: url)?.host, !parsedHost.isEmpty {
            return parsedHost
        }
        return url
    }

    /// What a Links row names the page: its preview title, when the message had one that says more than the domain
    /// does. nil otherwise, and the row shows the domain alone.
    public var displayTitle: String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        guard trimmed.caseInsensitiveCompare(displayDomain) != .orderedSame else { return nil }
        return trimmed
    }

    /// Whether the link's preview has a picture on this Mac.
    public var hasImage: Bool {
        guard let path = imagePath else { return false }
        return !path.isEmpty
    }

    /// De-duplicates links with identical `url` strings, keeping the newest entry (`ts` descending)
    /// and preserving relative input order when timestamps match.
    public static func deduplicated(_ links: [RoomLink]) -> [RoomLink] {
        var bestByURL: [String: (index: Int, link: RoomLink)] = [:]
        for (index, link) in links.enumerated() {
            if let existing = bestByURL[link.url] {
                if link.ts > existing.link.ts {
                    // The newest message wins, but not at the cost of a title another copy of the link has.
                    var newest = link
                    if newest.displayTitle == nil, existing.link.displayTitle != nil { newest.title = existing.link.title }
                    if !newest.hasImage, existing.link.hasImage { newest.imagePath = existing.link.imagePath }
                    bestByURL[link.url] = (index, newest)
                } else {
                    var kept = existing.link
                    var changed = false
                    if kept.displayTitle == nil, link.displayTitle != nil {
                        kept.title = link.title
                        changed = true
                    }
                    if !kept.hasImage, link.hasImage {
                        kept.imagePath = link.imagePath
                        changed = true
                    }
                    if changed { bestByURL[link.url] = (existing.index, kept) }
                }
            } else {
                bestByURL[link.url] = (index, link)
            }
        }
        return bestByURL.values
            .sorted { lhs, rhs in
                if lhs.link.ts != rhs.link.ts {
                    return lhs.link.ts > rhs.link.ts
                }
                return lhs.index < rhs.index
            }
            .map(\.link)
    }
}

/// Pure, testable presentation helpers for `ChatInfoPane`.
public enum ChatInfoPresentation {
    /// Attribution badge info overlaid on a Shared Media tile when the sender is known.
    public struct MediaSender: Equatable, Sendable {
        public let name: String
        public let initials: String
        public let avatarPath: String
        /// What the placeholder colour is keyed on: the sender's user ID (their name only when no ID is known).
        public let identity: String

        public init(name: String, initials: String, avatarPath: String, identity: String? = nil) {
            self.name = name
            self.initials = initials
            self.avatarPath = avatarPath
            self.identity = AvatarColor.identity(id: identity ?? "", fallbackName: name.isEmpty ? "?" : name)
        }
    }

    /// Resolves the header avatar path for `info`: the user's local avatar override wins over the network avatar.
    public static func displayAvatarPath(for info: RoomInfoResult) -> String {
        !info.localAvatarURI.isEmpty ? info.localAvatarURI : info.avatarPath
    }

    /// Returns `false` (unarchive) when `rows` is non-empty and every row is already archived;
    /// otherwise `true` (archive — when none or only some are archived, or no rows are loaded).
    public static func shouldArchive(_ rows: [InboxRow]) -> Bool {
        rows.isEmpty || !rows.allSatisfy(\.archived)
    }

    /// Filters `events` to only non-view-once image and video messages (`m.room.message` with `m.image` / `m.video`),
    /// excluding link-preview text messages, stickers, files, audio, and view-once items.
    public static func sharedMediaEvents(_ events: [Event]) -> [Event] {
        events.filter { event in
            guard event.type == "m.room.message", event.viewOnce != true else { return false }
            guard case let .object(dict) = event.content,
                  dict["com.beeper.view_once"] != .bool(true),
                  dict["view_once"] != .bool(true),
                  case let .string(msgtype)? = dict["msgtype"] else {
                return false
            }
            return msgtype == "m.image" || msgtype == "m.video"
        }
    }

    /// Resolves sender attribution for a shared-media tile, returning `nil` when neither a sender name
    /// nor an avatar path can be determined.
    public static func mediaSender(for event: Event, members: [Member]) -> MediaSender? {
        let member = event.sender.isEmpty ? nil : members.first { $0.userID == event.sender }
        let avatarPath = !event.senderAvatarPath.isEmpty ? event.senderAvatarPath : (member?.avatarPath ?? "")

        let eventSenderName = event.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let memberName = member?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawSenderID = event.sender.trimmingCharacters(in: .whitespacesAndNewlines)

        let name: String
        if !eventSenderName.isEmpty {
            name = eventSenderName
        } else if !memberName.isEmpty {
            name = memberName
        } else if event.mine || event.sender == Timeline.meUserID {
            name = String(localized: "You")
        } else if !rawSenderID.isEmpty {
            name = rawSenderID
        } else {
            name = ""
        }

        guard !name.isEmpty || !avatarPath.isEmpty else { return nil }
        let initial = String(InboxRow.initials(of: name.isEmpty ? "?" : name).prefix(1))
        return MediaSender(name: name, initials: initial, avatarPath: avatarPath, identity: rawSenderID)
    }

    /// Who shared a link, for the small avatar on its tile: the member the link's sender is, me with `ownAvatarPath`,
    /// else just the sender's ID. nil when the sender is not known at all.
    public static func linkSender(for link: RoomLink, members: [Member], ownAvatarPath: String) -> MediaSender? {
        let sender = link.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sender.isEmpty else { return nil }
        if sender == Timeline.meUserID {
            return MediaSender(name: String(localized: "You"), initials: "Y", avatarPath: ownAvatarPath, identity: sender)
        }
        let member = members.first { $0.userID == sender }
        let name = member?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shown = name.isEmpty ? sender : name
        let initial = String(InboxRow.initials(of: shown).prefix(1))
        return MediaSender(name: shown, initials: initial, avatarPath: member?.avatarPath ?? "", identity: sender)
    }

    /// My own picture for Chat Info. The chat's member list often has none for me, so this looks for one in turn: my
    /// own entry in the member list, then a message of mine the pane already holds (shared media and files), then
    /// `fallback` (a picture the app has seen on any of my messages). "" when none is known.
    public static func ownAvatarPath(in info: RoomInfoResult, fallback: String = "") -> String {
        if let mine = info.members.first(where: { $0.userID == Timeline.meUserID }), !mine.avatarPath.isEmpty {
            return mine.avatarPath
        }
        let fromInfo = newestOwnAvatar(in: info.sharedMedia + info.sharedFiles)
        return fromInfo.isEmpty ? fallback : fromInfo
    }

    /// The picture on my newest message among `events` that carries one (newest by time, then by order), "" when none
    /// does. Never an arbitrary one: the same events always give the same picture.
    public static func newestOwnAvatar(in events: [Event]) -> String {
        events
            .filter { ($0.mine || $0.sender == Timeline.meUserID) && !$0.senderAvatarPath.isEmpty }
            .max { ($0.ts, $0.seq) < ($1.ts, $1.seq) }?.senderAvatarPath ?? ""
    }

    /// My newest picture among the open chat's `events`, from messages of the same account as the chat (`chatRoomID`).
    /// An account is a real match only: the same network and the same, non-empty account name. A message in the chat
    /// itself always counts. With no account known for the chat, nothing from other rooms is taken: "" (the row then
    /// shows initials).
    public static func ownAvatarFromTimeline(
        events: [Event], chatRoomID: String, chatNetwork: String, row: (String) -> InboxRow?
    ) -> String {
        let chatLogin = row(chatRoomID)?.loginName ?? ""
        let sameAccount = events.filter { event in
            if event.roomID == chatRoomID { return true }
            guard !chatLogin.isEmpty, let other = row(event.roomID) else { return false }
            return other.network == chatNetwork && other.loginName == chatLogin
        }
        return newestOwnAvatar(in: sameAccount)
    }

    /// The picture a Participants row shows: the member's own, else (for me) `ownAvatarPath`.
    public static func participantAvatarPath(for member: Member, ownAvatarPath: String) -> String {
        if !member.avatarPath.isEmpty { return member.avatarPath }
        return member.userID == Timeline.meUserID ? ownAvatarPath : ""
    }

    /// `mediaSender` with my picture filled in when the sender is me and no picture came with the message.
    public static func mediaSender(for event: Event, members: [Member], ownAvatarPath: String) -> MediaSender? {
        guard let sender = mediaSender(for: event, members: members) else {
            guard (event.mine || event.sender == Timeline.meUserID), !ownAvatarPath.isEmpty else { return nil }
            return MediaSender(name: String(localized: "You"), initials: "Y", avatarPath: ownAvatarPath, identity: Timeline.meUserID)
        }
        guard sender.avatarPath.isEmpty, event.mine || event.sender == Timeline.meUserID, !ownAvatarPath.isEmpty else {
            return sender
        }
        return MediaSender(name: sender.name, initials: sender.initials, avatarPath: ownAvatarPath, identity: sender.identity)
    }

    /// Shows the "Admin" badge only when the member is an admin AND not every member in the chat is an admin.
    public static func showsAdminBadge(for member: Member, in members: [Member]) -> Bool {
        member.isAdmin && !members.isEmpty && !members.allSatisfy(\.isAdmin)
    }

    /// Resolves up to 3 member tuples for `GroupCompositeAvatar`, matching `InboxRow.groupAvatarStyle`.
    public static func groupCompositeMembers(for info: RoomInfoResult) -> [(name: String, avatarPath: String?, identity: String)] {
        if case .channel = GroupAvatarStyle.of(name: info.name) {
            return []
        }
        let otherMembers = info.members.filter { $0.userID != Timeline.meUserID }
        let withAvatar = otherMembers.filter { !$0.avatarPath.isEmpty }
        let withoutAvatar = otherMembers.filter { $0.avatarPath.isEmpty }
        let picked = (withAvatar + withoutAvatar).prefix(GroupAvatarStyle.maxMembers).map { member in
            let displayName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                name: displayName.isEmpty ? member.userID : displayName,
                avatarPath: member.avatarPath.isEmpty ? nil : Optional(member.avatarPath),
                identity: member.avatarIdentity
            )
        }
        if !picked.isEmpty {
            return Array(picked)
        }
        if case let .people(people) = GroupAvatarStyle.of(name: info.name) {
            return people.map { ($0.name, $0.avatarPath, $0.identity) }
        }
        return []
    }
}
