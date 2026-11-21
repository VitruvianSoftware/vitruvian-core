// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// What Chat Info's grouped sections (Shared, Bookmarks, Contact, and the settings with their one-line explanations)
// say. Pure, so tests can check them without drawing anything.

// MARK: - Shared

/// One tile of Chat Info's Shared section: a photo or video, or a link card.
public enum ChatInfoSharedTile: Equatable, Identifiable, Sendable {
    case media(Event)
    case link(RoomLink)

    public var id: String {
        switch self {
        case let .media(event): "media:\(event.eventID)"
        case let .link(link): "link:\(link.id)"
        }
    }

    /// The message it is in: what a click opens the chat at.
    public var eventID: String {
        switch self {
        case let .media(event): event.eventID
        case let .link(link): link.eventID
        }
    }

    /// When it was sent, in Unix milliseconds.
    public var ts: Int64 {
        switch self {
        case let .media(event): event.ts
        case let .link(link): link.ts
        }
    }
}

public enum ChatInfoShared {
    /// How many tiles the section shows before "Show All".
    public static let tileLimit = 4

    /// The newest `limit` photos, videos and links of a chat, newest first. Links count once each, however often they
    /// were sent; a photo and a link sent at the same moment come photo first.
    public static func tiles(media: [Event], links: [RoomLink], limit: Int = tileLimit) -> [ChatInfoSharedTile] {
        everything(media: media, links: links).prefix(max(0, limit)).map { $0 }
    }

    /// How many things the chat has shared: what the section's count says, and whether "Show All" has more to show.
    public static func count(media: [Event], links: [RoomLink]) -> Int {
        everything(media: media, links: links).count
    }

    /// The media viewer's tab Show All opens: the one of the first (newest) tile, so what a person is looking at
    /// is what opens. A link first opens Links, a photo or video first opens Media; the other is one tab away.
    public static func viewerTab(media: [Event], links: [RoomLink]) -> MediaViewerModel.Tab {
        guard let first = everything(media: media, links: links).first else { return .media }
        if case .link = first { return .links }
        return .media
    }

    /// The number by the section's title. A chat the engine could not read all of (`RoomInfoResult.sharedCapped`)
    /// has at least that many, so it reads "50+", never a count that is too small to be true.
    public static func countText(_ count: Int, capped: Bool) -> String {
        capped ? "\(count)+" : "\(count)"
    }

    private static func everything(media: [Event], links: [RoomLink]) -> [ChatInfoSharedTile] {
        let mediaTiles = ChatInfoPresentation.sharedMediaEvents(media).map(ChatInfoSharedTile.media)
        let linkTiles = RoomLink.deduplicated(links).map(ChatInfoSharedTile.link)
        // A stable sort: equal times keep the order they came in, photos and videos before links.
        return (mediaTiles + linkTiles).enumerated()
            .sorted { lhs, rhs in
                lhs.element.ts != rhs.element.ts ? lhs.element.ts > rhs.element.ts : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

extension RoomLink {
    /// Whether the link points at a map (Google Maps and its short links, Apple Maps): its card shows a pin.
    public var isMapsLink: Bool {
        guard let parsed = URL(string: url), let rawHost = parsed.host?.lowercased() else { return false }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if host == "maps.app.goo.gl" || host == "maps.apple.com" || host.hasPrefix("maps.google.") { return true }
        if host == "goo.gl" || host.hasPrefix("google.") { return parsed.path.hasPrefix("/maps") }
        return false
    }

    /// The SF Symbol on the link's card in place of the site's own icon, which the app does not fetch.
    public var cardSymbolName: String { isMapsLink ? "mappin.circle.fill" : "globe" }

    /// What a link card calls the link: the page's title, else the site, else for a map "Map".
    public var cardTitle: String {
        if let title = displayTitle { return title }
        return isMapsLink ? String(localized: "Map") : displayDomain
    }
}

// MARK: - Bookmarks

/// A bookmarked message as Chat Info's Bookmarks section lists it.
public struct ChatInfoBookmarkRow: Equatable, Identifiable, Sendable {
    public var id: String { eventID }
    public let eventID: String
    /// Who sent it: their name, or "You".
    public let sender: String
    /// What it says; a photo or a file has no text, so it names what it is.
    public let snippet: String
    public let ts: Int64

    public init(eventID: String, sender: String, snippet: String, ts: Int64) {
        self.eventID = eventID
        self.sender = sender
        self.snippet = snippet
        self.ts = ts
    }
}

extension ChatInfoPresentation {
    /// The chat's bookmarked messages, newest first. A bookmark is kept per message, so the list is the chat's own:
    /// the pane asks for the bookmarks of this chat alone.
    public static func bookmarkRows(_ hits: [MessageHit]) -> [ChatInfoBookmarkRow] {
        hits.sorted { ($0.ts, $0.seq) > ($1.ts, $1.seq) }.map { hit in
            let name = hit.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = hit.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChatInfoBookmarkRow(
                eventID: hit.eventID,
                sender: hit.mine ? String(localized: "You") : (name.isEmpty ? hit.sender : name),
                snippet: snippet.isEmpty ? bookmarkKindName(hit.kind) : snippet,
                ts: hit.ts
            )
        }
    }

    private static func bookmarkKindName(_ kind: MessageHitKind) -> String {
        switch kind {
        case .image: String(localized: "Photo")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .file: String(localized: "File")
        case .sticker: String(localized: "Sticker")
        default: String(localized: "Message")
        }
    }

    /// The date on a bookmark: the time today, "Yesterday", else the day, with the year when it isn't this one.
    public static func bookmarkDateText(
        ts: Int64, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMMdy")
        }
        return formatter.string(from: date)
    }
}

// MARK: - Contact

/// One line of Chat Info's Contact box.
public struct ChatContactRow: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case phone, email, handle }

    public let kind: Kind
    /// "Phone", "Email", "Username".
    public let label: String
    /// What it shows and what a click copies.
    public let value: String

    public var id: String { "\(label):\(value)" }

    public init(kind: Kind, label: String, value: String) {
        self.kind = kind
        self.label = label
        self.value = value
    }
}

extension ChatInfoPresentation {
    /// The Contact box of a one-to-one chat: the other person's phone numbers, email addresses and network usernames,
    /// by what the network knows of them. Opaque bridge identifiers are left out (`ContactsBridge`).
    public static func contactRows(for member: Member?) -> [ChatContactRow] {
        guard let member else { return [] }
        return ContactsBridge.displayableIdentifiers(member.identifiers).compactMap { raw in
            let value = ContactsBridge.displayIdentifier(raw)
            if ContactsBridge.normalizePhone(raw) != nil {
                return ChatContactRow(kind: .phone, label: String(localized: "Phone"), value: value)
            }
            if ContactsBridge.normalizeEmail(raw) != nil {
                return ChatContactRow(kind: .email, label: String(localized: "Email"), value: value)
            }
            return ChatContactRow(kind: .handle, label: String(localized: "Username"), value: value)
        }
    }
}

// MARK: - Settings and what they mean

extension NotificationPreferences {
    /// The sound a chat with no sound of its own plays: its account's, else the direct-message or group sound from
    /// Settings ▸ Notifications. The same order the notifier uses.
    public func defaultSound(isDirect: Bool, network: String, accountID: String) -> NotificationSoundChoice {
        let key = AccountsAndBridgesModel.accountKey(network: network, accountID: accountID)
        return accountOverrides[key]?.sound ?? (isDirect ? messageSound : groupSound)
    }
}

extension ChatInfoPresentation {
    /// A notification sound's name in the picker. "Default" says which sound it is now ("Default (Pop)"); with the
    /// system's own sound as the default there is nothing to add. `name` gives a choice's name.
    public static func soundPickerTitle(
        _ choice: NotificationSoundChoice, resolvedDefault: NotificationSoundChoice,
        name: (NotificationSoundChoice) -> String
    ) -> String {
        guard choice == .default else { return name(choice) }
        guard resolvedDefault != .default else { return String(localized: "Default") }
        let sound = name(resolvedDefault)
        return String(localized: "Default (\(sound))")
    }

    /// The line under the sound picker.
    public static func soundExplanation(chosen: NotificationSoundChoice) -> String {
        chosen == .default
            ? String(localized: "Uses your sound from Settings ▸ Notifications. Muted chats stay silent.")
            : String(localized: "Plays this sound for this chat only. Muted chats stay silent.")
    }

    /// The line under the Disappearing Messages picker.
    public static var disappearingExplanation: String {
        String(localized: "New messages disappear after the set time")
    }

    /// The network that has a chat history setting in place of a disappearing timer: Google Chat's history on or off.
    public static let historySettingNetwork = "gchat"

    /// The row Chat Info's Privacy section shows for a chat's disappearing messages, or nil when the chat has nothing
    /// to say about them.
    ///
    /// Google Chat has no timer, only history: on keeps messages, off deletes them after 24 hours (Beeper calls it
    /// Disappearing messages). This client can read it but has no call to change it, so the row is read only and says
    /// where to change it; it appears only when Google has told us the setting, so it never claims one it doesn't know.
    /// Every other network keeps its timer row, which has a picker when the chat's features offer timers.
    public static func disappearingRow(for info: RoomInfoResult) -> DisappearingRow? {
        if info.network == historySettingNetwork, let off = info.historyOff {
            return DisappearingRow(
                title: String(localized: "Chat history"),
                value: off ? String(localized: "Off") : String(localized: "On"),
                explanation: off
                    ? String(localized: "History is off: messages disappear after 24 hours. Change this in Google Chat.")
                    : String(localized: "History is on: messages are kept. Change this in Google Chat."),
                isHistorySetting: true
            )
        }
        guard info.features.disappearing != nil || info.disappearingMS > 0 || info.features.currentTimer != nil else {
            return nil
        }
        let ms = info.disappearingMS > 0 ? info.disappearingMS : (info.features.currentTimer?.timerMS ?? 0)
        return DisappearingRow(
            title: String(localized: "Disappearing Messages"),
            value: ms > 0 ? MessageActions.duration(ms) : String(localized: "Off"),
            explanation: disappearingExplanation,
            isHistorySetting: false
        )
    }
}

/// The Privacy section's disappearing-messages row: its title, what it is set to, and the line under it.
public struct DisappearingRow: Equatable, Sendable {
    public let title: String
    public let value: String
    public let explanation: String
    /// Google Chat's history setting, which this app reads but cannot change (no picker).
    public let isHistorySetting: Bool
}

extension ChatReadAloud {
    /// The line under the Read Aloud picker: what the chosen value does.
    public var explanation: String {
        switch self {
        case .always: String(localized: "Every new message is read aloud. Muted chats are never read aloud.")
        case .never: String(localized: "This chat is never read aloud.")
        default: String(localized: "Follows Vitruvian Speaker’s settings. Muted chats are never read aloud.")
        }
    }
}

// MARK: - Link tiles

/// What a link tile in Chat Info's Shared section shows: the preview's picture when it has one, the page's title,
/// who shared it, and the site. With no preview at all (no picture and no title) it falls back to a globe and the
/// site, as before.
public struct ChatInfoLinkCard: Equatable, Sendable {
    /// The page's title from the link preview; nil when there is none (or it is only the site's name).
    public let title: String?
    /// The site, shown on one line (cut in the middle when it is too long, never broken across lines).
    public let domain: String
    /// The preview's picture, when it has one on this Mac.
    public let imagePath: String?
    /// The small avatar of whoever shared it; nil when the sender is not known.
    public let sender: ChatInfoPresentation.MediaSender?
    /// The symbol drawn when there is no picture: a pin for a map link, else a globe.
    public let symbolName: String
    public let isMap: Bool

    public init(link: RoomLink, members: [Member] = [], ownAvatarPath: String = "") {
        title = link.displayTitle
        domain = link.displayDomain
        imagePath = link.hasImage ? link.imagePath : nil
        sender = ChatInfoPresentation.linkSender(for: link, members: members, ownAvatarPath: ownAvatarPath)
        symbolName = link.cardSymbolName
        isMap = link.isMapsLink
    }

    /// The tile has nothing of its own to show: a globe and the site.
    public var isFallback: Bool { imagePath == nil && title == nil }

    /// The words above the site: the page's title, or (a map with no title) "Map". nil for a plain link with no title,
    /// whose site is already on the tile.
    public var headline: String? {
        if let title { return title }
        return isMap ? String(localized: "Map") : nil
    }

    /// The most lines the title takes.
    public static let titleLineLimit = 2
    /// The site always takes one.
    public static let domainLineLimit = 1
}
