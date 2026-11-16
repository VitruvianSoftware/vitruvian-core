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

    /// De-duplicates links with identical `url` strings, keeping the newest entry (`ts` descending)
    /// and preserving relative input order when timestamps match.
    public static func deduplicated(_ links: [RoomLink]) -> [RoomLink] {
        var bestByURL: [String: (index: Int, link: RoomLink)] = [:]
        for (index, link) in links.enumerated() {
            if let existing = bestByURL[link.url] {
                if link.ts > existing.link.ts {
                    bestByURL[link.url] = (index, link)
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

        public init(name: String, initials: String, avatarPath: String) {
            self.name = name
            self.initials = initials
            self.avatarPath = avatarPath
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
        return MediaSender(name: name, initials: initial, avatarPath: avatarPath)
    }

    /// Shows the "Admin" badge only when the member is an admin AND not every member in the chat is an admin.
    public static func showsAdminBadge(for member: Member, in members: [Member]) -> Bool {
        member.isAdmin && !members.isEmpty && !members.allSatisfy(\.isAdmin)
    }

    /// Resolves up to 3 member tuples for `GroupCompositeAvatar`, matching `InboxRow.groupAvatarStyle`.
    public static func groupCompositeMembers(for info: RoomInfoResult) -> [(name: String, avatarPath: String?)] {
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
                avatarPath: member.avatarPath.isEmpty ? nil : Optional(member.avatarPath)
            )
        }
        if !picked.isEmpty {
            return Array(picked)
        }
        if case let .people(people) = GroupAvatarStyle.of(name: info.name) {
            return people.map { ($0.name, $0.avatarPath) }
        }
        return []
    }
}
